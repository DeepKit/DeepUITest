unit ArtifactOS.Core.DB.Connection;

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  DeepBase.Config;

type
  TArtifactDB = class
  private
    FConnection: TFDConnection;
    FDatabaseName: string;
    FSchema: string;
  public
    constructor Create(const ADatabaseName, ASchema: string);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Query(const ASQL: string): TFDQuery;
    function Execute(const ASQL: string): Integer;
    function ExecuteScalar(const ASQL: string): string;
    property Connection: TFDConnection read FConnection;
    property DatabaseName: string read FDatabaseName;
    property Schema: string read FSchema;
  end;

function ArtifactOS_DB: TArtifactDB;

implementation

uses
  DeepBase.DB.PostgreSQL,
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
end;

destructor TArtifactDB.Destroy;
begin
  Disconnect;
  FConnection.Free;
  inherited;
end;

procedure TArtifactDB.Connect;
var
  Host, Port, User, Pwd, Db: string;
begin
  if IsConnected then Exit;
  Host  := DeepBase.GetConfig('ArtifactOS.DB.Host',  '127.0.0.1');
  Port  := DeepBase.GetConfig('ArtifactOS.DB.Port',  '5432');
  User  := DeepBase.GetConfig('ArtifactOS.DB.User',  'fuyi01');
  Pwd   := DeepBase.GetConfig('ArtifactOS.DB.Pass',  '');
  Db    := DeepBase.GetConfig('ArtifactOS.DB.Name',  FDatabaseName);

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

function TArtifactDB.Query(const ASQL: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := FConnection;
  Result.SQL.Text := ASQL;
  Result.Open;
end;

function TArtifactDB.Execute(const ASQL: string): Integer;
begin
  Result := FConnection.ExecSQL(ASQL);
end;

function TArtifactDB.ExecuteScalar(const ASQL: string): string;
var
  Qry: TFDQuery;
begin
  Qry := Query(ASQL);
  try
    if Qry.IsEmpty or Qry.Fields[0].IsNull then
      Result := ''
    else
      Result := Qry.Fields[0].AsString;
  finally
    Qry.Free;
  end;
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

initialization
  _Instance := nil;

finalization
  _Instance.Free;

end.