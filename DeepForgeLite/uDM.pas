unit uDM;

interface

uses
  System.SysUtils, System.Classes, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef, FireDAC.Stan.ExprFuncs, FireDAC.FMXUI.Wait,
  FireDAC.Stan.Param, FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt,
  FireDAC.Comp.DataSet, FireDAC.Comp.Client, Data.DB;

type
  TDM = class(TDataModule)
    ConnConfig: TFDConnection;
    ConnData: TFDConnection;
    procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
  private
    FDataDBPath: string;
    procedure InitDataDatabase;
    procedure CreateTables;
  public
    property DataDBPath: string read FDataDBPath;
    function GetNewQuery: TFDQuery;
    function GetNewMemTable: TFDMemTable;
  end;

var
  DM: TDM;

implementation

uses
  System.IOUtils;

{%CLASSGROUP 'FMX.Controls.TControl'}

{$R *.dfm}

procedure TDM.DataModuleCreate(Sender: TObject);
var
  RootPath: string;
  SL: TStringList;
  DataDir: string;
begin
  FDataDBPath := '';
  RootPath := '';
  
  if FileExists(ExtractFilePath(ParamStr(0)) + 'root.txt') then
  begin
    SL := TStringList.Create;
    try
      SL.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'root.txt');
      RootPath := Trim(SL.Text);
    finally
      SL.Free;
    end;
  end;
  
  if RootPath = '' then
    RootPath := ExtractFilePath(ParamStr(0));
  
  FDataDBPath := TPath.Combine(TPath.Combine(RootPath, 'data'), 'DeepDevLiteData.db');
  
  DataDir := ExtractFilePath(FDataDBPath);
  if not TDirectory.Exists(DataDir) then
    TDirectory.CreateDirectory(DataDir);
  
  InitDataDatabase;
end;

procedure TDM.DataModuleDestroy(Sender: TObject);
begin
  if ConnData.Connected then
    ConnData.Connected := False;
  if ConnConfig.Connected then
    ConnConfig.Connected := False;
end;

procedure TDM.InitDataDatabase;
begin
  ConnData.DriverName := 'SQLite';
  ConnData.Params.Values['Database'] := FDataDBPath;
  ConnData.Params.Values['LockingMode'] := 'Normal';
  ConnData.Connected := True;
  
  CreateTables;
end;

procedure TDM.CreateTables;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := ConnData;
    
    Q.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS contracts (' +
      '  id TEXT PRIMARY KEY,' +
      '  title TEXT NOT NULL,' +
      '  language TEXT,' +
      '  purpose TEXT,' +
      '  source_file TEXT,' +
      '  source_code TEXT,' +
      '  status TEXT DEFAULT ''draft'',' +
      '  created_at TEXT,' +
      '  confirmed_at TEXT,' +
      '  sealed_at TEXT,' +
      '  rework_count INTEGER DEFAULT 0,' +
      '  extra TEXT' +
      ')';
    Q.ExecSQL;
    
    Q.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS tasks (' +
      '  id TEXT PRIMARY KEY,' +
      '  contract_id TEXT,' +
      '  title TEXT,' +
      '  description TEXT,' +
      '  scenario_id TEXT,' +
      '  status TEXT DEFAULT ''pending'',' +
      '  artifact_type TEXT,' +
      '  artifact_path TEXT,' +
      '  input_spec TEXT,' +
      '  output_spec TEXT,' +
      '  test_result TEXT,' +
      '  created_at TEXT,' +
      '  updated_at TEXT,' +
      '  extra TEXT' +
      ')';
    Q.ExecSQL;
    
    Q.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS test_results (' +
      '  id TEXT PRIMARY KEY,' +
      '  contract_id TEXT,' +
      '  task_id TEXT,' +
      '  scenario_id TEXT,' +
      '  passed INTEGER DEFAULT 0,' +
      '  detail TEXT,' +
      '  execution_ms INTEGER,' +
      '  raw_output TEXT,' +
      '  created_at TEXT' +
      ')';
    Q.ExecSQL;
    
    Q.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS reports (' +
      '  id TEXT PRIMARY KEY,' +
      '  contract_id TEXT,' +
      '  project_name TEXT,' +
      '  source_file TEXT,' +
      '  language TEXT,' +
      '  ai_model TEXT,' +
      '  seal_hash TEXT,' +
      '  is_sealed INTEGER DEFAULT 0,' +
      '  created_at TEXT,' +
      '  extra TEXT' +
      ')';
    Q.ExecSQL;
    
    Q.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS seal_records (' +
      '  id TEXT PRIMARY KEY,' +
      '  report_id TEXT,' +
      '  source_file TEXT,' +
      '  source_hash TEXT,' +
      '  seal_hash TEXT,' +
      '  model_used TEXT,' +
      '  retry_count INTEGER,' +
      '  contract_file TEXT,' +
      '  sealed_at TEXT' +
      ')';
    Q.ExecSQL;
    
  finally
    Q.Free;
  end;
end;

function TDM.GetNewQuery: TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := ConnData;
end;

function TDM.GetNewMemTable: TFDMemTable;
begin
  Result := TFDMemTable.Create(nil);
end;

end.
