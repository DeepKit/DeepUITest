unit DeepFrames.Persistence.Connection;

interface

uses
  FireDAC.Comp.Client,
  DeepBase.DB.Pool;

type
  TDeepFramesDB2Connection = class
  private
    class var FSharedPool: TUniConnectionPool;
  public
    class procedure EnsureDefaultSettings; static;
    class function LoadProfile: TDBConnectionProfile; static;
    class function CreateConnection(OpenConnection: Boolean = True): TFDConnection; static;
    class function TestConnection(out AError: string): Boolean; static;
    class procedure ReleasePool; static;
  end;

implementation

uses
  System.SysUtils,
  DeepBase.Config,
  DeepBase.Exceptions,
  DeepBase.Security,
  DeepFrames.Shared.Consts;

class procedure TDeepFramesDB2Connection.EnsureDefaultSettings;
begin
  if Trim(GetConfig(DB2_TYPE, '')) = '' then
    SetConfig(DB2_TYPE, DEFAULT_DB2_TYPE, 'Database');
  if Trim(GetConfig(DB2_HOST, '')) = '' then
    SetConfig(DB2_HOST, DEFAULT_DB2_HOST, 'Database');
  if Trim(GetConfig(DB2_PORT, '')) = '' then
    SetConfigInt(DB2_PORT, DEFAULT_DB2_PORT, 'Database');
  if Trim(GetConfig(DB2_DATABASE, '')) = '' then
    SetConfig(DB2_DATABASE, DEFAULT_DB2_DATABASE, 'Database');
  if Trim(GetConfig(DB2_USER, '')) = '' then
    SetConfig(DB2_USER, DEFAULT_DB2_USER, 'Database');
  if Trim(GetConfig(DB2_PASSWORD_SECRET_REF, '')) = '' then
    SetConfig(DB2_PASSWORD_SECRET_REF, DEFAULT_DB2_PASSWORD_SECRET_REF, 'Database');
end;

class function TDeepFramesDB2Connection.LoadProfile: TDBConnectionProfile;
var
  SecretRef: string;
  Password: string;
begin
  EnsureDefaultSettings;
  if not SameText(GetConfig(DB2_TYPE, DEFAULT_DB2_TYPE), 'PostgreSQL') then
    raise EInvalidOperationException.Create('DeepFrames DB2 currently supports PostgreSQL only');

  SecretRef := GetConfig(DB2_PASSWORD_SECRET_REF, DEFAULT_DB2_PASSWORD_SECRET_REF);
  Password := LoadSecret(SecretNameFromRef(SecretRef));

  Result := TDBConnectionProfile.PostgreSQL(
    GetConfig(DB2_HOST, DEFAULT_DB2_HOST),
    GetConfig(DB2_DATABASE, DEFAULT_DB2_DATABASE),
    GetConfig(DB2_USER, DEFAULT_DB2_USER),
    Password,
    GetConfigInt(DB2_PORT, DEFAULT_DB2_PORT));
  Result.ApplicationName := APP_NAME;
  // Postgres stores TEXT/JSONB as UTF-8. Without CharacterSet=UTF8, FireDAC's
  // PG driver uses the default client encoding and ships Delphi UTF-16 string
  // bytes verbatim; every ASCII char is then followed by a 0x00 byte, which
  // Postgres rejects as "invalid byte sequence for encoding UTF8: 0x00" on
  // any write containing non-ASCII (e.g. LLM-generated Chinese script content).
  // The pool sets Params['CharacterSet'] from this field, so it must be set
  // here at profile load, not merely on the borrowed connection handle.
  Result.CharacterSet := 'UTF8';
  Result.SSLMode := GetConfig(DB2_SSL_MODE, Result.SSLMode);
  Result.VendorLib := GetConfig(DB2_VENDOR_LIB, '');
  Result.Validate;
end;

class function TDeepFramesDB2Connection.CreateConnection(
  OpenConnection: Boolean): TFDConnection;
begin
  if FSharedPool = nil then
  begin
    FSharedPool := TUniConnectionPool.Create;
    FSharedPool.Configure(LoadProfile);
  end;
  Result := FSharedPool.CreateUnopenedConnection;
  try
    // PostgreSQL stores `uuid` columns in big-endian (RFC 4122 network byte
    // order), e.g. 550e8400-e29b-41d4-a716-446655440000. FireDAC's PG driver
    // reads uuid via Delphi TGUID, whose default little-endian interpretation
    // flips the first three fields: AsString returns 00840e55-9be2-d441-...,
    // which matches NO row, so every WHERE project_id = :pid::uuid returns 0
    // rows (seed path fails: "no content unit"). Setting GUIDEndian=Big makes
    // the driver byte-swap on read so AsString returns the canonical text PG
    // stored. (A FormatOptions MapRule uuid->dtWideString is NOT used: it
    // changes the column type but leaves size 0, raising DatS overflow.)
    Result.FormatOptions.OwnMapRules := False;
    Result.Params.Values['GUIDEndian'] := 'Big';
    // Force client encoding UTF8 (see LoadProfile comment). FireDAC's PG
    // driver reads the CharacterSet param, so this is the authoritative name.
    // Set again here in case the pool returns a connection whose params were
    // not rebuilt from the profile.
    Result.Params.Values['CharacterSet'] := 'UTF8';
    if OpenConnection then
    begin
      Result.Open;
      // Force client encoding server-side. The CharacterSet param above is the
      // documented FireDAC mechanism, but it had no observed effect (PG still
      // rejected writes with "0x00 invalid byte sequence for UTF8" because
      // the driver shipped Delphi UTF-16 string bytes verbatim). Issuing
      // SET client_encoding = 'UTF8' immediately after Open makes libpq
      // negotiate UTF-8 for this session, so the driver transcodes Wide ->
      // UTF-8 before sending text parameters.
      Result.ExecSQL('SET client_encoding = ''UTF8''');
    end;
  except
    Result.Free;
    raise;
  end;
end;

class procedure TDeepFramesDB2Connection.ReleasePool;
begin
  FreeAndNil(FSharedPool);
end;

class function TDeepFramesDB2Connection.TestConnection(out AError: string): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  Result := False;
  AError := '';
  Conn := nil;
  try
    Conn := CreateConnection(True);
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.Open('SELECT 1');
      Q.Close;
    finally
      Q.Free;
    end;
    Result := True;
  except
    on E: Exception do
      AError := E.Message;
  end;
  Conn.Free;
end;

end.
