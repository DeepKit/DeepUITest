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
    if OpenConnection then
      Result.Open;
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
begin
  Result := False;
  AError := '';
  Conn := nil;
  try
    Conn := CreateConnection(True);
    Conn.ExecSQL('SELECT 1');
    Result := True;
  except
    on E: Exception do
      AError := E.Message;
  end;
  Conn.Free;
end;

end.
