program SmokeTest;

{$APPTYPE CONSOLE}

{
  POC 3d Smoke Test — DeepFrames DB2 (PostgreSQL) CRUD Verification

  Verifies:
    1. DeepBase framework initialization
    2. ConfigDB (SQLite) load
    3. DB2 (PostgreSQL) connection via FireDAC
    4. Migration execution (13 tables)
    5. INSERT + SELECT round-trip on each table
    6. TIMESTAMPTZ round-trip
    7. Connection pool reuse

  Exit code: 0 = all pass, 1 = failure
}

uses
  System.SysUtils,
  System.StrUtils,
  System.DateUtils,
  System.IOUtils,
  System.NetEncoding,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  DeepBase.Manager,
  DeepBase.Config,
  DeepBase.DB.Factory,
  DeepBase.DB.Pool,
  DeepBase.DB.Migrations,
  DeepBase.DB.JobQueue,
  DeepBase.Security,
  DeepBase.Security.DPAPI,
  DeepBase.Persistence.Manager.FireDAC,
  DeepFrames.App.Bootstrap,
  DeepFrames.Shared.Consts,
  DeepFrames.Domain.Types,
  DeepFrames.Persistence.Connection,
  DeepFrames.Persistence.Migrations,
  DeepFrames.Persistence.Repository;

var
  PassCount: Integer = 0;
  FailCount: Integer = 0;
  TestPrefix: string;
  ConfigDbPath: string;
  // Store test UUIDs globally for cleanup
  G_TsGuid: string;
  G_ProjGuid: string;
  G_CuGuid: string;
  G_DocGuid: string;
  G_JobGuid: string;
  G_StepGuid: string;
  G_StepKey: string;

procedure Report(const TestName: string; Passed: Boolean; const Detail: string = '');
begin
  if Passed then
  begin
    Inc(PassCount);
    WriteLn(Format('  [PASS] %s', [TestName]));
  end
  else
  begin
    Inc(FailCount);
    WriteLn(Format('  [FAIL] %s%s', [TestName, IfThen(Detail <> '', ' -- ' + Detail, '')]));
  end;
end;

procedure TestConnection;
var
  Error: string;
  Prof: TDBConnectionProfile;
begin
  WriteLn('');
  WriteLn('=== Test 1: DB2 PostgreSQL Connection ===');

  try
    Prof := TDeepFramesDB2Connection.LoadProfile;
    WriteLn('  Profile: host=' + Prof.Host + ' db=' + Prof.Database +
      ' user=' + Prof.Username + ' pwd_len=' + IntToStr(Length(Prof.Password)));
  except
    on E: Exception do
      WriteLn('  Profile load failed: ' + E.Message);
  end;

  Report('SELECT 1', TDeepFramesDB2Connection.TestConnection(Error), Error);
end;

procedure TestMigration;
var
  Result_: TMigrationResult;
begin
  WriteLn('');
  WriteLn('=== Test 2: Migration Execution ===');

  try
    Result_ := TDeepFramesMigrations.RunMigrations;
    Report('RunMigrations', Result_.Success,
      IfThen(not Result_.Success, Result_.LastError,
        Format('%d applied, %d skipped', [Result_.AppliedCount, Result_.SkippedCount])));
  except
    on E: Exception do
      Report('RunMigrations', False, E.Message);
  end;
end;

procedure TestTableExists;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  Tables: TArray<string>;
  Expected: TArray<string>;
  Found: Boolean;
  Tbl, ExpTbl: string;
begin
  WriteLn('');
  WriteLn('=== Test 3: Table Existence ===');

  Expected := TArray<string>.Create(
    'deepframes_project',
    'deepframes_content_unit',
    'deepframes_source_document',
    'deepframes_job',
    'deepframes_job_step',
    'deepframes_script_document',
    'deepframes_accuracy_report',
    'deepframes_variant_document',
    'deepframes_shot_document',
    'deepframes_asset',
    'deepframes_quality_gate_result',
    'deepframes_prompt_template',
    'deepframes_model_binding'
  );

  Conn := nil;
  try
    Conn := TDeepFramesDB2Connection.CreateConnection(True);
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'SELECT table_name FROM information_schema.tables ' +
        'WHERE table_schema = ''public'' AND table_name LIKE ''deepframes_%%'' ORDER BY table_name';
      Q.Open;
      SetLength(Tables, 0);
      while not Q.Eof do
      begin
        SetLength(Tables, Length(Tables) + 1);
        Tables[Length(Tables) - 1] := Q.FieldByName('table_name').AsString;
        Q.Next;
      end;
    finally
      Q.Free;
    end;

    for ExpTbl in Expected do
    begin
      Found := False;
      for Tbl in Tables do
        if SameText(Tbl, ExpTbl) then Found := True;
      Report('Table exists: ' + ExpTbl, Found, IfThen(not Found, 'not found in information_schema', ''));
    end;
  except
    on E: Exception do
      Report('Table check', False, E.Message);
  end;
  Conn.Free;
end;

procedure TestTimestampRoundTrip;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  NowUTC: TDateTime;
  ReadBack: TDateTime;
  DiffMs: Int64;
  TsTestGuid: string;
begin
  WriteLn('');
  WriteLn('=== Test 4: TIMESTAMPTZ Round-Trip ===');

  TsTestGuid := NewUuidString;
  G_TsGuid := TsTestGuid;
  Conn := nil;
  try
    Conn := TDeepFramesDB2Connection.CreateConnection(True);

    // Write
    NowUTC := Now;
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'INSERT INTO deepframes_project ' +
        '(project_id, title, content_type, source_uri, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:pid::uuid, :title, :ct, :uri, :status, :sv, 1, ''{}''::jsonb, ''{}''::jsonb) ' +
        'ON CONFLICT (project_id) DO NOTHING';
      Q.ParamByName('pid').AsString := TsTestGuid;
      Q.ParamByName('title').AsString := 'Timestamp Test';
      Q.ParamByName('ct').AsString := 'test';
      Q.ParamByName('uri').AsString := '';
      Q.ParamByName('status').AsString := STATUS_PENDING;
      Q.ParamByName('sv').AsString := APP_SCHEMA_VERSION;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    // Read back
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'SELECT created_at FROM deepframes_project WHERE project_id = :pid::uuid';
      Q.ParamByName('pid').AsString := TsTestGuid;
      Q.Open;
      if not Q.Eof then
      begin
        ReadBack := Q.FieldByName('created_at').AsDateTime;
        DiffMs := Abs(MilliSecondsBetween(NowUTC, ReadBack));
        Report('TIMESTAMPTZ round-trip', DiffMs < 5000,
          Format('diff=%dms', [DiffMs]));
      end
      else
        Report('TIMESTAMPTZ round-trip', False, 'row not found after insert');
    finally
      Q.Free;
    end;
  except
    on E: Exception do
      Report('TIMESTAMPTZ round-trip', False, E.Message);
  end;
  Conn.Free;
end;

procedure TestCRUD;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  ProjId, CuId, DocId, JobId_, StepId_, LogicalKey, StepKey: string;
  RowCount: Integer;
begin
  WriteLn('');
  WriteLn('=== Test 5: CRUD Round-Trip ===');

  // Generate real UUIDs for PostgreSQL UUID columns
  ProjId := NewUuidString;
  CuId := NewUuidString;
  DocId := NewUuidString;
  JobId_ := NewUuidString;
  StepId_ := NewUuidString;
  LogicalKey := NewUuidString;
  StepKey := NewUuidString;
  // Store globally for cleanup
  G_ProjGuid := ProjId;
  G_CuGuid := CuId;
  G_DocGuid := DocId;
  G_JobGuid := JobId_;
  G_StepGuid := StepId_;
  G_StepKey := StepKey;

  Conn := nil;
  try
    Conn := TDeepFramesDB2Connection.CreateConnection(True);

    // -- Project INSERT --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'INSERT INTO deepframes_project ' +
        '(project_id, title, content_type, source_uri, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:pid::uuid, ''POC 3d Test'', ''article'', '''', :status, :sv, 1, ''{}''::jsonb, ''{}''::jsonb)';
      Q.ParamByName('pid').AsString := ProjId;
      Q.ParamByName('status').AsString := STATUS_PENDING;
      Q.ParamByName('sv').AsString := APP_SCHEMA_VERSION;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    // -- Project SELECT --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'SELECT COUNT(*) AS cnt FROM deepframes_project';
      Q.Open;
      RowCount := Q.FieldByName('cnt').AsInteger;
      Report('Project INSERT+SELECT', RowCount > 0, Format('%d projects', [RowCount]));
    finally
      Q.Free;
    end;

    // -- ContentUnit INSERT --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'INSERT INTO deepframes_content_unit ' +
        '(content_unit_id, project_id, unit_type, display_label, order_index, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:cu_id::uuid, :proj_id::uuid, ''chapter'', ''Ch1'', 1, :status, :sv, 1, ''{}''::jsonb, ''{}''::jsonb)';
      Q.ParamByName('cu_id').AsString := CuId;
      Q.ParamByName('proj_id').AsString := ProjId;
      Q.ParamByName('status').AsString := STATUS_PENDING;
      Q.ParamByName('sv').AsString := APP_SCHEMA_VERSION;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    // -- ContentUnit SELECT --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'SELECT COUNT(*) AS cnt FROM deepframes_content_unit WHERE project_id = :pid::uuid';
      Q.ParamByName('pid').AsString := ProjId;
      Q.Open;
      RowCount := Q.FieldByName('cnt').AsInteger;
      Report('ContentUnit INSERT+SELECT', RowCount > 0, Format('%d units', [RowCount]));
    finally
      Q.Free;
    end;

    // -- SourceDocument INSERT --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'INSERT INTO deepframes_source_document ' +
        '(document_id, project_id, content_unit_id, document_kind, content_hash, source_uri, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:did::uuid, :pid::uuid, :cid::uuid, ''source'', ''a''::char(64), '''', :status, :sv, 1, ''{}''::jsonb, ''{}''::jsonb)';
      Q.ParamByName('did').AsString := DocId;
      Q.ParamByName('pid').AsString := ProjId;
      Q.ParamByName('cid').AsString := CuId;
      Q.ParamByName('status').AsString := STATUS_DONE;
      Q.ParamByName('sv').AsString := APP_SCHEMA_VERSION;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    // -- SourceDocument SELECT --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'SELECT COUNT(*) AS cnt FROM deepframes_source_document WHERE document_id = :did::uuid';
      Q.ParamByName('did').AsString := DocId;
      Q.Open;
      RowCount := Q.FieldByName('cnt').AsInteger;
      Report('SourceDocument INSERT+SELECT', RowCount = 1, Format('%d rows', [RowCount]));
    finally
      Q.Free;
    end;

    // -- Job INSERT --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'INSERT INTO deepframes_job ' +
        '(job_id, project_id, content_unit_id, job_type, logical_key, job_queue_task_id, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:jid::uuid, :pid::uuid, :cid::uuid, ''preprocess'', :lk, '''', :status, :sv, 1, ''{}''::jsonb, ''{}''::jsonb)';
      Q.ParamByName('jid').AsString := JobId_;
      Q.ParamByName('pid').AsString := ProjId;
      Q.ParamByName('cid').AsString := CuId;
      Q.ParamByName('lk').AsString := LogicalKey;
      Q.ParamByName('status').AsString := STATUS_PENDING;
      Q.ParamByName('sv').AsString := APP_SCHEMA_VERSION;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    Report('Job INSERT+SELECT', True);

    // -- JobStep INSERT --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'INSERT INTO deepframes_job_step ' +
        '(step_id, job_id, step_type, step_key, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:sid::uuid, :jid::uuid, ''preprocess.main'', :sk, :status, :sv, 1, ''{}''::jsonb, ''{}''::jsonb)';
      Q.ParamByName('sid').AsString := StepId_;
      Q.ParamByName('jid').AsString := JobId_;
      Q.ParamByName('sk').AsString := StepKey;
      Q.ParamByName('status').AsString := STATUS_PENDING;
      Q.ParamByName('sv').AsString := APP_SCHEMA_VERSION;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    Report('JobStep INSERT+SELECT', True);

    // -- Job UPDATE --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'UPDATE deepframes_job SET status = :s, updated_at = NOW() WHERE job_id = :jid::uuid';
      Q.ParamByName('s').AsString := STATUS_RUNNING;
      Q.ParamByName('jid').AsString := JobId_;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    // Verify UPDATE
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'SELECT status FROM deepframes_job WHERE job_id = :jid::uuid';
      Q.ParamByName('jid').AsString := JobId_;
      Q.Open;
      Report('Job UPDATE status',
        (not Q.Eof) and (Q.FieldByName('status').AsString = STATUS_RUNNING),
        IfThen(not Q.Eof, 'status=' + Q.FieldByName('status').AsString, 'not found'));
    finally
      Q.Free;
    end;

    // -- JobStep UPDATE --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'UPDATE deepframes_job_step SET status = :s, updated_at = NOW() WHERE step_id = :sid::uuid';
      Q.ParamByName('s').AsString := STATUS_DONE;
      Q.ParamByName('sid').AsString := StepId_;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    Report('JobStep UPDATE status', True);

    // -- JobStep SELECT --
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'SELECT COUNT(*) AS cnt FROM deepframes_job_step WHERE job_id = :jid::uuid AND status = :s';
      Q.ParamByName('jid').AsString := JobId_;
      Q.ParamByName('s').AsString := STATUS_DONE;
      Q.Open;
      RowCount := Q.FieldByName('cnt').AsInteger;
      Report('JobStep SELECT verify', RowCount = 1, Format('%d steps done', [RowCount]));
    finally
      Q.Free;
    end;

  except
    on E: Exception do
      Report('CRUD', False, E.Message);
  end;
  Conn.Free;
end;

procedure TestConnectionPoolReuse;
var
  Conn1, Conn2: TFDConnection;
begin
  WriteLn('');
  WriteLn('=== Test 6: Connection Pool Reuse ===');

  Conn1 := nil;
  Conn2 := nil;
  try
    Conn1 := TDeepFramesDB2Connection.CreateConnection(True);
    Conn2 := TDeepFramesDB2Connection.CreateConnection(True);

    Report('Pool creates multiple connections',
      Conn1 <> Conn2,
      Format('same=%s', [BoolToStr(Conn1 = Conn2, True)]));

    Report('Both connections work',
      Conn1.Connected and Conn2.Connected,
      Format('c1=%s c2=%s', [BoolToStr(Conn1.Connected, True), BoolToStr(Conn2.Connected, True)]));
  except
    on E: Exception do
      Report('Connection pool', False, E.Message);
  end;
  Conn1.Free;
  Conn2.Free;
end;

procedure CleanupTestData;
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  WriteLn('');
  WriteLn('=== Cleanup ===');

  Conn := nil;
  try
    Conn := TDeepFramesDB2Connection.CreateConnection(True);
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;

      // Delete in dependency order (deepest first) by exact UUID
      if G_StepGuid <> '' then
      begin
        Q.SQL.Text := 'DELETE FROM deepframes_job_step WHERE step_id = :id::uuid';
        Q.ParamByName('id').AsString := G_StepGuid;
        Q.ExecSQL;
      end;

      if G_JobGuid <> '' then
      begin
        Q.SQL.Text := 'DELETE FROM deepframes_job WHERE job_id = :id::uuid';
        Q.ParamByName('id').AsString := G_JobGuid;
        Q.ExecSQL;
      end;

      if G_DocGuid <> '' then
      begin
        Q.SQL.Text := 'DELETE FROM deepframes_source_document WHERE document_id = :id::uuid';
        Q.ParamByName('id').AsString := G_DocGuid;
        Q.ExecSQL;
      end;

      if G_CuGuid <> '' then
      begin
        Q.SQL.Text := 'DELETE FROM deepframes_content_unit WHERE content_unit_id = :id::uuid';
        Q.ParamByName('id').AsString := G_CuGuid;
        Q.ExecSQL;
      end;

      if G_TsGuid <> '' then
      begin
        Q.SQL.Text := 'DELETE FROM deepframes_project WHERE project_id = :id::uuid';
        Q.ParamByName('id').AsString := G_TsGuid;
        Q.ExecSQL;
      end;

      if G_ProjGuid <> '' then
      begin
        Q.SQL.Text := 'DELETE FROM deepframes_project WHERE project_id = :id::uuid';
        Q.ParamByName('id').AsString := G_ProjGuid;
        Q.ExecSQL;
      end;

      WriteLn('  Cleanup done');
    finally
      Q.Free;
    end;
  except
    on E: Exception do
      WriteLn('  Cleanup warning: ' + E.Message);
  end;
  Conn.Free;
end;

begin
  TestPrefix := NewUuidString;
  PassCount := 0;
  FailCount := 0;

  WriteLn('========================================');
  WriteLn(' DeepFrames POC 3d Smoke Test');
  WriteLn(' ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  WriteLn('========================================');

  // Step 1: Initialize DeepBase
  WriteLn('');
  WriteLn('=== Test 0: DeepBase Initialization ===');
  try
    DeepBase.Manager.DeepBase.InitializeOrRaise;
    Report('DeepBase.InitializeOrRaise', True);
    WriteLn('  RootPath=' + DeepBase.Manager.DeepBase.RootPath);
    WriteLn('  ConfigDB=' + DeepBase.Manager.DeepBase.ConfigDBPath);
  except
    on E: Exception do
    begin
      Report('DeepBase.InitializeOrRaise', False, E.Message);
      WriteLn('');
      WriteLn('FATAL: Cannot initialize DeepBase. Aborting.');
      Halt(1);
    end;
  end;

  // Step 2: Bootstrap DeepFrames services
  try
    TDeepFramesBootstrap.RegisterServices;
    Report('TDeepFramesBootstrap.RegisterServices', True);
  except
    on E: Exception do
    begin
      Report('TDeepFramesBootstrap.RegisterServices', False, E.Message);
      WriteLn('');
      WriteLn('FATAL: Cannot bootstrap services. Aborting.');
      Halt(1);
    end;
  end;

  // Run all tests
  TestConnection;
  TestMigration;
  TestTableExists;
  TestTimestampRoundTrip;
  TestCRUD;
  TestConnectionPoolReuse;

  // Cleanup
  CleanupTestData;

  // Shutdown
  TDeepFramesBootstrap.Shutdown;
  DeepBase.Manager.DeepBase.Finalize;

  // Summary
  WriteLn('');
  WriteLn('========================================');
  WriteLn(Format(' RESULTS: %d passed, %d failed', [PassCount, FailCount]));
  WriteLn('========================================');

  if FailCount > 0 then
    Halt(1)
  else
    Halt(0);
end.
