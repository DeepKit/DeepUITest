unit ArtifactOS.Core.DB.Connection;

interface

uses
  System.SysUtils, System.SyncObjs, System.Variants,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  FireDAC.Phys.PG,
  DeepBase.Config,
  DeepBase.DB.DoQry;

type
  TArtifactDB = class
  private
    FConnection: TFDConnection;
    FDatabaseName: string;
    FSchema: string;
    FLock: TCriticalSection;
    FRefCount: Integer;
  public
    constructor Create(const ADatabaseName, ASchema: string);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;

    function Query(const ASQL: string): TFDQuery;
    function Execute(const ASQL: string): Integer;
    function ExecuteScalar(const ASQL: string): string;
    function InsertAndReturnId(const ASQL: string): string;

    function QueryJson(const ASQL, AParamsJson: string): TFDMemTable;
    function ExecuteJson(const ASQL, AParamsJson: string): Integer;
    function ExecuteScalarJson(const ASQL, AParamsJson: string): string;
    function InsertAndReturnIdJson(const ASQL, AParamsJson: string): string;
    function Context(const ATimeoutSec: Integer = 30): TUniQueryContext;

    property Connection: TFDConnection read FConnection;
    property DatabaseName: string read FDatabaseName;
    property Schema: string read FSchema;
  end;

function ArtifactOS_DB: TArtifactDB;

implementation

uses
  System.JSON,
  DeepBase.Security,
  FireDAC.Stan.Def,
  FireDAC.Stan.Param;

var
  _Instance: TArtifactDB;

function ArtifactOS_DB: TArtifactDB;
begin
  Result := _Instance;
end;

constructor TArtifactDB.Create(const ADatabaseName, ASchema: string);
begin
  FDatabaseName := ADatabaseName;
  FSchema := ASchema;
  FConnection := TFDConnection.Create(nil);
  FLock := TCriticalSection.Create;
  FRefCount := 0;
end;

destructor TArtifactDB.Destroy;
begin
  FLock.Enter;
  try
    if FConnection.Connected then
      FConnection.Close;
    FConnection.Free;
  finally
    FLock.Leave;
    FLock.Free;
  end;
  inherited;
end;

procedure TArtifactDB.Connect;
var
  Host, Port, User, Pwd, Db: string;
begin
  FLock.Enter;
  try
    Inc(FRefCount);
    if IsConnected then Exit;
  finally
    FLock.Leave;
  end;
  FLock.Enter;
  try
    if IsConnected then Exit;

    Host  := GetConfig('ArtifactOS.DB.Host',  '127.0.0.1');
  Port  := GetConfig('ArtifactOS.DB.Port',  '5432');
  User := LoadSecret('ArtifactOS.DB.User');
  if User = '' then
    User := GetEnvironmentVariable('ARTIFACTOS_DB_USER');
  if User = '' then
    User := GetConfig('ArtifactOS.DB.User', '');
  if User = '' then
    User := 'postgres';
  // DI4: LoadSecret first (DeepBase recommended), env var fallback for dev
  Pwd := LoadSecret('ArtifactOS.DB.Pass');
  if Pwd = '' then
    Pwd := GetEnvironmentVariable('ARTIFACTOS_DB_PASS');
  if Pwd = '' then
    Pwd := GetConfig('ArtifactOS.DB.Pass', '');
  Db    := GetConfig('ArtifactOS.DB.Name',  FDatabaseName);

  FConnection.DriverName := 'PG';
  FConnection.Params.Values['Server']   := Host;
  FConnection.Params.Values['Port']     := Port;
  FConnection.Params.Values['Database'] := Db;
  FConnection.Params.Values['User_Name'] := User;
  FConnection.Params.Values['Password'] := Pwd;
  FConnection.LoginPrompt := False;

    // BUG-075: map PostgreSQL `uuid` columns to string, not ftGUID. FireDAC's
    // default maps uuid -> ftGUID, whose AsString applies Windows GUID
    // endianness to the first 3 fields, producing byte-swapped ids that
    // don't match the canonical uuid stored by PG (e.g. INSERT ... RETURNING
    // id yields 3924C8F0-... while PG stored f0c82439-...). Reading as text
    // returns the canonical lowercase form PG uses everywhere.
    // BUG-075: PG `uuid` columns map to FireDAC ftGUID, whose AsString applies
    // Windows GUID endianness to the first 3 fields, producing byte-swapped
    // ids (INSERT ... RETURNING id yields 3924C8F0-... while PG stored
    // f0c82439-...). We do NOT fix this here via MapRules (the target string
    // column gets size 0 and overflows). Instead InsertAndReturnId rewrites
    // `RETURNING id` to `RETURNING id::text` so the id comes back as a plain
    // lowercase string matching the canonical uuid PG stores everywhere.
    FConnection.Open;
  finally
    FLock.Leave;
  end;
end;

function TArtifactDB.IsConnected: Boolean;
begin
  Result := FConnection.Connected;
end;

procedure TArtifactDB.Disconnect;
begin
  FLock.Enter;
  try
    Dec(FRefCount);
    if (FRefCount <= 0) and not FConnection.InTransaction then
    begin
      FRefCount := 0;
      if FConnection.Connected then
        FConnection.Close;
    end;
    if FRefCount < 0 then
      FRefCount := 0;
  finally
    FLock.Leave;
  end;
end;

{ ── Core: Query / Execute / ExecuteScalar / InsertAndReturnId ── }

function TArtifactDB.Query(const ASQL: string): TFDQuery;
begin
  Connect;
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := FConnection;
    Result.SQL.Text := ASQL;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function TArtifactDB.Execute(const ASQL: string): Integer;
begin
  Connect;
  var Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := ASQL;
    Q.ExecSQL;
    Result := Q.RowsAffected;
  finally
    Q.Free;
  end;
end;

function TArtifactDB.ExecuteScalar(const ASQL: string): string;
begin
  Connect;
  var Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := ASQL;
    Q.Open;
    if Q.Eof then
      Result := ''
    else
      Result := Q.Fields[0].AsString;
  finally
    Q.Free;
  end;
end;

function TArtifactDB.InsertAndReturnId(const ASQL: string): string;
begin
  // N12.3: Prefer RETURNING id (atomic). If the SQL already has RETURNING,
  // read it directly; otherwise fall back to ExecSQL + SELECT for backwards
  // compatibility with callers that haven't yet added RETURNING.
  Connect;
  var UASQL := UpperCase(ASQL);
  var HasReturning := Pos('RETURNING', UASQL) > 0;

  if HasReturning then
  begin
    // Atomic path: INSERT ... RETURNING id — the PG row lock guarantees
    // we get our own row's id even under concurrency.
    // BUG-075: cast RETURNING id to text so FireDAC does not surface the
    // uuid as ftGUID (whose AsString byte-swaps the first 3 fields). `::text`
    // yields the canonical lowercase uuid PG stores, matching every other
    // id read in the codebase.
    var SQL := ASQL;
    var RetPos := Pos('RETURNING', UASQL);
    if RetPos > 0 then
    begin
      // Rewrite `RETURNING id` (optional trailing) -> `RETURNING id::text`.
      var After := Trim(Copy(ASQL, RetPos + Length('RETURNING'), MaxInt));
      if SameText(After, 'id') then
        SQL := Copy(ASQL, 1, RetPos + Length('RETURNING') - 1) + ' id::text'
      else if SameText(After, 'id;') then
        SQL := Copy(ASQL, 1, RetPos + Length('RETURNING') - 1) + ' id::text;';
    end;
    var Q := TFDQuery.Create(nil);
    try
      Q.Connection := FConnection;
      Q.SQL.Text := SQL;
      Q.Open;
      if Q.Eof then
        Result := ''
      else
        Result := Q.Fields[0].AsString;
      var L := Length(Result);
      if (L > 2) and (Result[1] = '{') and (Result[L] = '}') then
        Result := Copy(Result, 2, L - 2);
    finally
      Q.Free;
    end;
  end
  else
  begin
    // Legacy path: ExecSQL + separate SELECT — NOT concurrency-safe.
    // Callers should migrate to include RETURNING id in their SQL.
    var PosInto := Pos('INTO', UASQL);
    var AfterInto := Trim(Copy(ASQL, PosInto + 4, MaxInt));
    var PosParen := Pos('(', AfterInto);
    var TabName: string;
    if PosParen > 0 then
      TabName := Trim(Copy(AfterInto, 1, PosParen - 1));
    if TabName = '' then Exit('');
    if Pos('.', TabName) = 0 then
      TabName := FSchema + '.' + TabName;

    FConnection.ExecSQL(ASQL);

    var Q := TFDQuery.Create(nil);
    try
      Q.Connection := FConnection;
      Q.SQL.Text := 'SELECT id::text FROM ' + TabName + ' ORDER BY created_at DESC LIMIT 1';
      Q.Open;
      Result := Q.Fields[0].AsString;
      var L := Length(Result);
      if (L > 2) and (Result[1] = '{') and (Result[L] = '}') then
        Result := Copy(Result, 2, L - 2);
    finally
      Q.Free;
    end;
  end;
end;

{ ── JSON parameter binding engine ── }

// N10.2e: Rewritten to use TJSONObject for proper JSON parsing.
// Handles backslash-escaped strings, unicode escapes, and nested values
// that the old manual parser missed. Still substitutes into SQL as
// SQL-safe literals to avoid FireDAC ::uuid cast issues.
procedure BindParamsFromJson(AQuery: TFDQuery; var ASQL: string; const AParamsJson: string);
var
  JObj: TJSONObject;
  Pair: TJSONPair;
  ParamName, ParamValue: string;
  Placeholder: string;
  Names: TArray<string>;
  Values: TArray<string>;
begin
  if AParamsJson = '' then Exit;
  JObj := TJSONObject.ParseJSONValue(AParamsJson) as TJSONObject;
  if JObj = nil then Exit;
  try
    // N12.4: Collect all param names/values first, then sort by name length
    // descending. This prevents shorter names like :name from matching the
    // prefix of longer names like :name_suffix during StringReplace.
    SetLength(Names, JObj.Count);
    SetLength(Values, JObj.Count);
    for var I := 0 to JObj.Count - 1 do
    begin
      Pair := JObj.Pairs[I];
      Names[I] := Pair.JsonString.Value;
      if Names[I] = '' then Continue;

      if Pair.JsonValue is TJSONString then
        Values[I] := (Pair.JsonValue as TJSONString).Value
      else if Pair.JsonValue is TJSONNumber then
        Values[I] := (Pair.JsonValue as TJSONNumber).ToString
      else if Pair.JsonValue is TJSONBool then
        Values[I] := LowerCase((Pair.JsonValue as TJSONBool).ToString)
      else if Pair.JsonValue is TJSONNull then
        Values[I] := 'null'
      else
        Values[I] := Pair.JsonValue.ToJSON;
    end;

    // Sort by name length descending to avoid prefix collisions
    for var I := 0 to High(Names) - 1 do
      for var J := I + 1 to High(Names) do
        if Length(Names[I]) < Length(Names[J]) then
        begin
          var TmpName := Names[I]; Names[I] := Names[J]; Names[J] := TmpName;
          var TmpVal := Values[I]; Values[I] := Values[J]; Values[J] := TmpVal;
        end;

    for var I := 0 to High(Names) do
    begin
      ParamName := Names[I];
      if ParamName = '' then Continue;
      ParamValue := Values[I];

      // Escape single quotes for SQL literal safety (N10.1a)
      // N12.1: JsonEscape no longer escapes single quotes, so this is the
      // sole and correct layer for SQL single-quote doubling.
      ParamValue := StringReplace(ParamValue, '''', '''''', [rfReplaceAll]);

      Placeholder := ':' + ParamName;
      // Replace :name::uuid → '<value>'::uuid
      ASQL := StringReplace(ASQL, Placeholder + '::uuid ', '''' + ParamValue + '''::uuid ', [rfReplaceAll]);
      ASQL := StringReplace(ASQL, Placeholder + '::uuid)', '''' + ParamValue + '''::uuid)', [rfReplaceAll]);
      ASQL := StringReplace(ASQL, Placeholder + '::uuid' , '''' + ParamValue + '''::uuid', [rfReplaceAll]);
      // Replace :name::jsonb → '<value>'::jsonb
      ASQL := StringReplace(ASQL, Placeholder + '::jsonb', '''' + ParamValue + '''::jsonb', [rfReplaceAll]);
      // Replace :name::timestamptz → '<value>'::timestamptz
      ASQL := StringReplace(ASQL, Placeholder + '::timestamptz ', '''' + ParamValue + '''::timestamptz ', [rfReplaceAll]);
      ASQL := StringReplace(ASQL, Placeholder + '::timestamptz)', '''' + ParamValue + '''::timestamptz)', [rfReplaceAll]);
      ASQL := StringReplace(ASQL, Placeholder + '::timestamptz' , '''' + ParamValue + '''::timestamptz', [rfReplaceAll]);
      // Plain placeholder (no type cast)
      ASQL := StringReplace(ASQL, Placeholder + ' ', '''' + ParamValue + ''' ', [rfReplaceAll]);
      ASQL := StringReplace(ASQL, Placeholder + ')', '''' + ParamValue + ''')', [rfReplaceAll]);
      ASQL := StringReplace(ASQL, Placeholder  , '''' + ParamValue + '''', [rfReplaceAll]);
    end;
  finally
    JObj.Free;
  end;
end;

{ ── Parameterized: ExecuteJson / ExecuteScalarJson / InsertAndReturnIdJson ──
  // DI3: Two parameterization paths coexist for valid reasons:
  //
  //   QueryJson        → UniDbSelect (DeepBase native) — parameter binding
  //                       via FireDAC Params, works for plain :name placeholders.
  //
  //   ExecuteJson      → BindParamsFromJson (SQL text substitution)
  //   ExecuteScalarJson → BindParamsFromJson (SQL text substitution)
  //                       These use SQL text substitution because FireDAC cannot
  //                       handle PostgreSQL type casts like :param::uuid —
  //                       FireDAC treats the entire :param::uuid as a parameter
  //                       name. BindParamsFromJson resolves this by substituting
  //                       SQL-safe literals with proper type casts.
  //
  //   Both paths are safe when JsonEscape + BindParamsFromJson single-quote
  //   handling is correct (N12.1).  Long-term, consider migrating to a
  //   FireDAC macro-based approach or a custom TFDPhysPGDriverLink that
  //   strips ::type casts before parameter binding. }

function TArtifactDB.QueryJson(const ASQL, AParamsJson: string): TFDMemTable;
// DI3: QueryJson historically routed through DeepBase's UniDbSelect, which looks
// up SQL by Name in a `Queries` registry table. Repository passes raw SELECT text,
// not a registry Name → every SELECT hit "Query definition not found" (BUG-086).
// Aligned with ExecuteJson/ExecuteScalarJson: BindParamsFromJson (handles
// :param::uuid casts) + TFDQuery.Open, then copy rows into the TFDMemTable so
// callers' IsEmpty/First/FieldAsString API is unchanged.
// ParamCreate/MacroCreate disabled because BindParamsFromJson already inlined
// every value — leaving FireDAC to parse `::uuid` casts or jsonb `?` operators
// as phantom params (BUG-086 "Parameter [] data type is unknown").
var
  Q: TFDQuery;
begin
  Connect;
  var SQL := ASQL;
  BindParamsFromJson(nil, SQL, AParamsJson);
  Result := TFDMemTable.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.ResourceOptions.ParamCreate := False;
    Q.ResourceOptions.MacroCreate := False;
    Q.SQL.Text := SQL;
    try
      Q.Open;
      Result.CopyDataSet(Q, [coStructure, coRestart, coAppend]);
    except
      Result.Free;
      raise;
    end;
  finally
    Q.Free;
  end;
end;

function TArtifactDB.ExecuteJson(const ASQL, AParamsJson: string): Integer;
begin
  Connect;
  var SQL := ASQL;
  BindParamsFromJson(nil, SQL, AParamsJson);
  var Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := SQL;
    Q.ExecSQL;
    Result := Q.RowsAffected;
  finally
    Q.Free;
  end;
end;

function TArtifactDB.ExecuteScalarJson(const ASQL, AParamsJson: string): string;
begin
  Connect;
  var SQL := ASQL;
  BindParamsFromJson(nil, SQL, AParamsJson);
  var Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := SQL;
    Q.Open;
    if Q.Eof then
      Result := ''
    else
      Result := Q.Fields[0].AsString;
  finally
    Q.Free;
  end;
end;

function TArtifactDB.InsertAndReturnIdJson(const ASQL, AParamsJson: string): string;
begin
  Result := ExecuteScalarJson(ASQL, AParamsJson);
end;

function TArtifactDB.Context(const ATimeoutSec: Integer): TUniQueryContext;
begin
  Connect;
  Result := UniDbMakeContext(FConnection, udbPostgreSQL, ATimeoutSec, UniDbNewCorrelationId);
end;

initialization
  _Instance := TArtifactDB.Create('artifactos_test', 'artifactos');

finalization
  _Instance.Free;
end.
