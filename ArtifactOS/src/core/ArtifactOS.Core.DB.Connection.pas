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
  public
    constructor Create(const ADatabaseName, ASchema: string);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Query(const ASQL: string): TFDQuery;
    function QueryJson(const ASQL, AParamsJson: string): TFDMemTable;
    function Execute(const ASQL: string): Integer;
    function ExecuteJson(const ASQL, AParamsJson: string): Integer;
    function ExecuteScalar(const ASQL: string): string;
    function ExecuteScalarJson(const ASQL, AParamsJson: string): string;
    function InsertAndReturnId(const ASQL: string): string;
    function InsertAndReturnIdJson(const ASQL, AParamsJson: string): string;
    function Context(const ATimeoutSec: Integer = 30): TUniQueryContext;
    function ConnectLocked: Boolean;
    procedure DisconnectLocked;
    property Connection: TFDConnection read FConnection;
    property DatabaseName: string read FDatabaseName;
    property Schema: string read FSchema;
  end;

function ArtifactOS_DB: TArtifactDB;

implementation

uses
  DeepBase.Security,
  FireDAC.Stan.Def;

var
  _Instance: TArtifactDB;

function ArtifactOS_DB: TArtifactDB;
begin
  if _Instance = nil then
    _Instance := TArtifactDB.Create('artifactos_test', 'artifactos');
  Result := _Instance;
end;

constructor TArtifactDB.Create(const ADatabaseName, ASchema: string);
begin
  FDatabaseName := ADatabaseName;
  FSchema := ASchema;
  FConnection := TFDConnection.Create(nil);
  FLock := TCriticalSection.Create;
end;

destructor TArtifactDB.Destroy;
begin
  FLock.Enter;
  try
    Disconnect;
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
  if IsConnected then Exit;
  Host  := GetConfig('ArtifactOS.DB.Host',  '127.0.0.1');
  Port  := GetConfig('ArtifactOS.DB.Port',  '5432');
  User  := GetConfig('ArtifactOS.DB.User',  '');
  if User = '' then
    User := GetEnvironmentVariable('ARTIFACTOS_DB_USER');
  Pwd := LoadSecret('ArtifactOS.DB.Pass');
  if Pwd = '' then
  begin
    Pwd := GetEnvironmentVariable('ARTIFACTOS_DB_PASS');
    if Pwd <> '' then
      SaveSecret('ArtifactOS.DB.Pass', Pwd);
  end;
  Db    := GetConfig('ArtifactOS.DB.Name',  FDatabaseName);

  FConnection.DriverName := 'PG';
  FConnection.Params.Values['Server']   := Host;
  FConnection.Params.Values['Port']     := Port;
  FConnection.Params.Values['Database'] := Db;
  FConnection.Params.Values['User_Name'] := User;
  FConnection.Params.Values['Password'] := Pwd;
  FConnection.LoginPrompt := False;
  FConnection.Open;
end;

procedure TArtifactDB.Disconnect;
begin
  if FConnection.Connected then
    FConnection.Close;
end;

function TArtifactDB.IsConnected: Boolean;
begin
  Result := FConnection.Connected;
end;

function TArtifactDB.ConnectLocked: Boolean;
begin
  FLock.Enter;
  try
    Connect;
    Result := IsConnected;
  except
    FLock.Leave;
    raise;
  end;
end;

procedure TArtifactDB.DisconnectLocked;
begin
  try
    Disconnect;
  finally
    FLock.Leave;
  end;
end;

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

function TArtifactDB.Context(const ATimeoutSec: Integer): TUniQueryContext;
begin
  Result := UniDbMakeContext(FConnection, udbPostgreSQL, ATimeoutSec, UniDbNewCorrelationId);
end;

function TArtifactDB.QueryJson(const ASQL, AParamsJson: string): TFDMemTable;
begin
  Result := TFDMemTable.Create(nil);
  try
    UniDbSelect(ASQL, AParamsJson, Result, Context);
  except
    Result.Free;
    raise;
  end;
end;

function TArtifactDB.Execute(const ASQL: string): Integer;
begin
  Result := ExecuteJson(ASQL, '');
end;

function TArtifactDB.ExecuteJson(const ASQL, AParamsJson: string): Integer;
begin
  FLock.Enter;
  try
    Result := UniDbExec(ASQL, AParamsJson, Context);
  finally
    FLock.Leave;
  end;
end;

function TArtifactDB.ExecuteScalar(const ASQL: string): string;
begin
  Result := ExecuteScalarJson(ASQL, '');
end;

function TArtifactDB.ExecuteScalarJson(const ASQL, AParamsJson: string): string;
var
  V: Variant;
begin
  V := UniDbScalar(ASQL, AParamsJson, Context);
  if VarIsNull(V) or VarIsEmpty(V) then
    Result := ''
  else
    Result := VarToStr(V);
end;

function TArtifactDB.InsertAndReturnId(const ASQL: string): string;
var
  Q: TFDQuery;
begin
  Q := Query(ASQL);
  try
    Result := Q.Fields[0].AsString;
  finally
    Q.Free;
  end;
end;

function TArtifactDB.InsertAndReturnIdJson(const ASQL, AParamsJson: string): string;
begin
  Result := ExecuteScalarJson(ASQL, AParamsJson);
end;

initialization
  _Instance := nil;

finalization
  _Instance.Free;

end.