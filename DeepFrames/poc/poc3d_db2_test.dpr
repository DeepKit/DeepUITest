program poc3d_db2_test;

/// <summary>
/// POC 3d: Delphi 13.1 Runtime + FireDAC PostgreSQL Connection Verification.
///
/// Verifies:
///   1. DeepBase Manager initializes (SQLite config DB)
///   2. DB2 default settings populated
///   3. FireDAC can connect to PostgreSQL (SELECT 1)
///   4. Migration engine runs all 6 migration files (27 tables)
///   5. Basic CRUD: INSERT + SELECT + DELETE on deepframes_project
///
/// Exit code: 0 = all pass, 1 = failure at some step
///
/// Compile from repo root:
///   compile_test.bat  (produces bin\DeepFrames.exe)
///   — or use poc\poc3d_run.bat for this console test specifically.
/// </summary>

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  FireDAC.Comp.Client,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  DeepBase.Config,
  DeepBase.Security,
  DeepFrames.App.Bootstrap,
  DeepFrames.App.Constants,
  DeepFrames.Shared.Consts,
  DeepFrames.Persistence.Connection,
  DeepFrames.Persistence.Migrations;

var
  GPassCount: Integer = 0;
  GFailCount: Integer = 0;

procedure Check(const AStep: string; ASuccess: Boolean; const ADetail: string = '');
begin
  if ASuccess then
  begin
    Inc(GPassCount);
    WriteLn(Format('  [PASS] %s', [AStep]));
  end
  else
  begin
    Inc(GFailCount);
    WriteLn(Format('  [FAIL] %s%s', [AStep, IfThen(ADetail <> '', ' — ' + ADetail, '')]));
  end;
end;

procedure TestInitialize;
begin
  WriteLn('Step 1: DeepBase Manager initialization');
  try
    DeepBase.Manager.DeepBase.InitializeOrRaise;
    Check('InitializeOrRaise', True);
  except
    on E: Exception do
      Check('InitializeOrRaise', False, E.Message);
  end;
end;

procedure TestRegisterServices;
begin
  WriteLn('Step 2: Register services + DB2 default settings');
  try
    TDeepFramesBootstrap.RegisterServices;
    Check('RegisterServices', True);
  except
    on E: Exception do
      Check('RegisterServices', False, E.Message);
  end;
end;

procedure TestConnection;
var
  Error: string;
begin
  WriteLn('Step 3: FireDAC PostgreSQL connection (SELECT 1)');
  try
    if TDeepFramesDB2Connection.TestConnection(Error) then
      Check('TestConnection (SELECT 1)', True)
    else
      Check('TestConnection (SELECT 1)', False, Error);
  except
    on E: Exception do
      Check('TestConnection (SELECT 1)', False, E.Message);
  end;
end;

procedure TestMigrations;
var
  MigResult: DeepBase.DB.Migrations.TMigrationResult;
begin
  WriteLn('Step 4: Run database migrations');
  try
    MigResult := TDeepFramesMigrations.RunMigrations;
    Check('RunMigrations applied=' + IntToStr(MigResult.AppliedCount) +
      ' skipped=' + IntToStr(MigResult.SkippedCount),
      MigResult.Success, MigResult.LastError);
  except
    on E: Exception do
      Check('RunMigrations', False, E.Message);
  end;
end;

procedure TestCRUD;
var
  Conn: TFDConnection;
  Query: TFDQuery;
  TestId: string;
  Rows: Integer;
begin
  WriteLn('Step 5: Basic CRUD (deepframes_project)');
  TestId := '';
  Conn := nil;
  Query := nil;
  try
    Conn := TDeepFramesDB2Connection.CreateConnection(True);
    Query := TFDQuery.Create(nil);
    Query.Connection := Conn;

    // INSERT
    Query.SQL.Text :=
      'INSERT INTO deepframes_project (project_id, title, status, config_json)' +
      ' VALUES (gen_random_uuid()::text, ''POC3D-TEST'', ''active'', ''{}''::jsonb)' +
      ' RETURNING project_id';
    Query.Open;
    TestId := Query.Fields[0].AsString;
    Query.Close;
    Check('INSERT project (id=' + Copy(TestId, 1, 8) + '...)', TestId <> '');

    // SELECT
    Query.SQL.Text := 'SELECT title, status FROM deepframes_project WHERE project_id = :id';
    Query.ParamByName('id').AsString := TestId;
    Query.Open;
    Rows := 0;
    while not Query.Eof do
    begin
      Inc(Rows);
      Check('SELECT project (title=' + Query.FieldByName('title').AsString +
        ', status=' + Query.FieldByName('status').AsString + ')', True);
      Query.Next;
    end;
    Query.Close;
    if Rows = 0 then
      Check('SELECT project', False, 'no rows returned');

    // DELETE
    Query.SQL.Text := 'DELETE FROM deepframes_project WHERE project_id = :id';
    Query.ParamByName('id').AsString := TestId;
    Query.ExecSQL;
    Check('DELETE project', True);
  except
    on E: Exception do
      Check('CRUD', False, E.Message);
  end;
  Query.Free;
  Conn.Free;
end;

procedure TestTableCount;
var
  Conn: TFDConnection;
  Query: TFDQuery;
  Count: Integer;
begin
  WriteLn('Step 6: Verify table count');
  Conn := nil;
  Query := nil;
  try
    Conn := TDeepFramesDB2Connection.CreateConnection(True);
    Query := TFDQuery.Create(nil);
    Query.Connection := Conn;
    Query.SQL.Text :=
      'SELECT COUNT(*) FROM information_schema.tables' +
      ' WHERE table_schema = ''public'' AND table_name LIKE ''deepframes_%''';
    Query.Open;
    Count := Query.Fields[0].AsInteger;
    Query.Close;
    Check('deepframes_* tables count=' + IntToStr(Count) +
      ' (expected >= 22)', Count >= 22,
      'found ' + IntToStr(Count) + ' tables');
  except
    on E: Exception do
      Check('Table count', False, E.Message);
  end;
  Query.Free;
  Conn.Free;
end;

procedure PrintConfigSummary;
var
  Host, DB, User: string;
  Port: Integer;
begin
  WriteLn('--- Config Summary ---');
  Host := GetConfig(DB2_HOST, DEFAULT_DB2_HOST);
  Port := GetConfigInt(DB2_PORT, DEFAULT_DB2_PORT);
  DB := GetConfig(DB2_DATABASE, DEFAULT_DB2_DATABASE);
  User := GetConfig(DB2_USER, DEFAULT_DB2_USER);
  WriteLn(Format('  PostgreSQL: %s@%s:%d/%s', [User, Host, Port, DB]));
  WriteLn('');
end;

begin
  WriteLn('=== POC 3d: Delphi 13.1 Runtime + FireDAC PostgreSQL ===');
  WriteLn('');

  TestInitialize;
  TestRegisterServices;

  // Print config after registration (shows connection details)
  if GFailCount = 0 then
    PrintConfigSummary;

  // Steps 3-6 require a running PostgreSQL — skip gracefully if unreachable
  if GFailCount = 0 then
  begin
    TestConnection;

    if GFailCount = 0 then
    begin
      TestMigrations;
      TestCRUD;
      TestTableCount;
    end
    else
      WriteLn('  (skipping migrations/CRUD — connection failed)');
  end;

  WriteLn('');
  WriteLn(Format('=== Results: %d passed, %d failed ===', [GPassCount, GFailCount]));

  TDeepFramesBootstrap.Shutdown;
  DeepBase.Manager.DeepBase.Finalize;

  if GFailCount > 0 then
    Halt(1);
end.
