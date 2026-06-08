program DeepFrames.Tests.WorkerE2E;

{$APPTYPE CONSOLE}

{
  POC 3e — Worker Protocol v0 End-to-End Verification

  Flow:
    Delphi main → Write request.json → Launch Node worker (CreateProcess)
    → Monitor progress.json heartbeat → Read result.json → Update DB2 job_steps

  Exit code: 0 = all pass, 1 = failure
}

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.DateUtils,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  Winapi.Windows,
  DeepBase.Manager,
  DeepBase.Config,
  DeepBase.DB.Factory,
  DeepBase.Security,
  DeepBase.Persistence.Manager.FireDAC,
  DeepFrames.App.Bootstrap,
  DeepFrames.Shared.Consts,
  DeepFrames.Domain.Types,
  DeepFrames.Persistence.Connection,
  DeepFrames.Persistence.Repository,
  DeepFrames.Workflow.WorkerProtocol;

var
  PassCount, FailCount: Integer;
  G_ProjId: string;
  G_CuId: string;
  G_JobId: string;
  G_StepId: string;

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
    WriteLn(Format('  [FAIL] %s — %s', [TestName, Detail]));
  end;
end;

procedure TestWriteRequest;
var
  WorkDir: string;
  Req: TWorkerRequest;
  ReqPath: string;
  ReqJson: TJSONObject;
begin
  WriteLn('');
  WriteLn('=== Test 1: Write request.json ===');

  WorkDir := TPath.Combine(GetCurrentDir, 'poc3e_test_workdir');
  ForceDirectories(WorkDir);

  Req := TWorkerProtocol.BuildRequest(
    'poc3e-task-001', 'render',
    'poc3e_manifest.json',
    TPath.Combine(WorkDir, 'output'),
    '{"fps":30,"duration":10}',
    3000);
  TWorkerProtocol.WriteRequest(WorkDir, Req);

  ReqPath := TPath.Combine(WorkDir, 'request.json');
  Report('request.json exists', FileExists(ReqPath));

  if FileExists(ReqPath) then
  begin
    ReqJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(ReqPath, TEncoding.UTF8)) as TJSONObject;
    try
      Report('task_id correct', ReqJson.GetValue<string>('task_id') = 'poc3e-task-001');
      Report('task_type correct', ReqJson.GetValue<string>('task_type') = 'render');
      Report('schema_version present', ReqJson.GetValue<string>('schema_version') <> '');
    finally
      ReqJson.Free;
    end;
  end;
end;

procedure TestLaunchWorker;
var
  WorkDir: string;
  NodeExe: string;
  WorkerScript: string;
  Args: string;
  ProcessHandle: THandle;
  NodeFound: Boolean;
  StartTick: TDateTime;
  ResultPath: string;
begin
  WriteLn('');
  WriteLn('=== Test 2: Launch Node.js Worker ===');

  WorkDir := TPath.Combine(GetCurrentDir, 'poc3e_test_workdir');
  ForceDirectories(WorkDir);

  NodeExe := 'node.exe';
  WorkerScript := TPath.Combine(GetCurrentDir, 'poc\worker-poc\worker.js');
  WorkerScript := TPath.GetFullPath(WorkerScript);

  if not FileExists(NodeExe) then
  begin
    if FileExists('D:\Program Files\nodejs\node.exe') then
      NodeExe := 'D:\Program Files\nodejs\node.exe'
    else if FileExists('C:\Program Files\nodejs\node.exe') then
      NodeExe := 'C:\Program Files\nodejs\node.exe';
  end;

  NodeFound := FileExists(NodeExe);
  Report('node.exe found', NodeFound, NodeExe);

  if not FileExists(WorkerScript) then
  begin
    WorkerScript := TPath.GetFullPath(
      TPath.Combine(ExtractFilePath(ParamStr(0)),
      '..\poc\worker-poc\worker.js'));
  end;
  Report('worker.js found', FileExists(WorkerScript), WorkerScript);

  if NodeFound and FileExists(WorkerScript) then
  begin
    Args := Format('"%s" "%s"', [WorkerScript, WorkDir]);
    ProcessHandle := 0;
    // Show exact command line for debugging
    WriteLn('  CmdLine: ' + NodeExe + ' ' + Args);

    Report('LaunchWorker', TWorkerProtocol.LaunchWorker(WorkDir, NodeExe, Args, ProcessHandle));

    if ProcessHandle <> 0 then
    begin
      WriteLn('  Waiting for worker PID (' + IntToStr(ProcessHandle) + ')...');
      StartTick := Now;
      ResultPath := TPath.Combine(WorkDir, 'result.json');
      while MilliSecondsBetween(Now, StartTick) < 30000 do
      begin
        Sleep(500);
        if FileExists(ResultPath) then
          Break;
      end;
      CloseHandle(ProcessHandle);
      Report('worker process completed', FileExists(ResultPath));
    end;
  end;
end;

procedure TestReadResult;
var
  WorkDir: string;
  Progress: TWorkerProgress;
  Result: TWorkerResult;
  ResultPath: string;
begin
  WriteLn('');
  WriteLn('=== Test 3: Read Result ===');

  WorkDir := TPath.Combine(GetCurrentDir, 'poc3e_test_workdir');

  Progress := TWorkerProtocol.ReadProgress(WorkDir);
  Report('progress.json parsed', Progress.TaskId <> '', Format('status=%s, pct=%d', [Progress.Status, Progress.ProgressPercent]));
  Report('progress status is done', SameText(Progress.Status, 'done'), Progress.Status);

  ResultPath := TPath.Combine(WorkDir, 'result.json');
  Report('result.json exists', FileExists(ResultPath));

  if TWorkerProtocol.ReadResult(WorkDir, Result) then
  begin
    Report('result success=true', Result.Success, Result.ErrorMessage);
    Report('result has duration', Result.DurationMs > 0, IntToStr(Result.DurationMs) + 'ms');
    Report('result has output files', Length(Result.OutputFiles) > 0, IntToStr(Length(Result.OutputFiles)) + ' files');
    Report('result files exist', FileExists(Result.OutputFiles[0]), Result.OutputFiles[0]);
  end
  else
    Report('read result', False, 'could not parse result.json');
end;

procedure TestDB2Update;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  ProjId, CuId, JobId_, StepId_, LogicalKey, StepKey: string;
  RowCount: Integer;
  St: string;
begin
  WriteLn('');
  WriteLn('=== Test 4: DB2 Job/JobStep State Transition ===');

  ProjId := NewUuidString;
  CuId := NewUuidString;
  JobId_ := NewUuidString;
  StepId_ := NewUuidString;
  LogicalKey := NewUuidString;
  StepKey := NewUuidString;

  G_ProjId := ProjId;
  G_CuId := CuId;
  G_JobId := JobId_;
  G_StepId := StepId_;

  Conn := nil;
  try
    Conn := TDeepFramesDB2Connection.CreateConnection(True);

    // Project INSERT
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'INSERT INTO deepframes_project (project_id, title, content_type, source_uri, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:pid::uuid, ''POC3e'', ''article'', '''', ''pending'', ''1.0.0'', 1, ''{}''::jsonb, ''{}''::jsonb)';
      Q.ParamByName('pid').AsString := ProjId;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    // ContentUnit INSERT
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'INSERT INTO deepframes_content_unit (content_unit_id, project_id, unit_type, display_label, order_index, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:cid::uuid, :pid::uuid, ''chapter'', ''E2E'', 1, ''pending'', ''1.0.0'', 1, ''{}''::jsonb, ''{}''::jsonb)';
      Q.ParamByName('cid').AsString := CuId;
      Q.ParamByName('pid').AsString := ProjId;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    // Job INSERT (pending)
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'INSERT INTO deepframes_job (job_id, project_id, content_unit_id, job_type, logical_key, job_queue_task_id, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:jid::uuid, :pid::uuid, :cid::uuid, ''video'', :lk, '''', ''pending'', ''1.0.0'', 1, ''{}''::jsonb, ''{}''::jsonb)';
      Q.ParamByName('jid').AsString := JobId_;
      Q.ParamByName('pid').AsString := ProjId;
      Q.ParamByName('cid').AsString := CuId;
      Q.ParamByName('lk').AsString := LogicalKey;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    // JobStep INSERT (pending)
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text :=
        'INSERT INTO deepframes_job_step (step_id, job_id, step_type, step_key, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:sid::uuid, :jid::uuid, ''video.render'', :sk, ''pending'', ''1.0.0'', 1, ''{}''::jsonb, ''{}''::jsonb)';
      Q.ParamByName('sid').AsString := StepId_;
      Q.ParamByName('jid').AsString := JobId_;
      Q.ParamByName('sk').AsString := StepKey;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    Report('INSERT project+unit+job+step', True);

    // State transition: pending → running (simulating worker start)
    Conn.ExecSQL('UPDATE deepframes_job SET status = ''running'', updated_at = NOW() WHERE job_id = :jid::uuid', [JobId_]);
    Conn.ExecSQL('UPDATE deepframes_job_step SET status = ''running'', updated_at = NOW() WHERE step_id = :sid::uuid', [StepId_]);

    // Verify running
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'SELECT status FROM deepframes_job WHERE job_id = :jid::uuid';
      Q.ParamByName('jid').AsString := JobId_;
      Q.Open;
      St := Q.FieldByName('status').AsString;
      Report('Job pending→running', St = 'running', St);
    finally
      Q.Free;
    end;

    // State transition: running → succeeded (simulating worker completion)
    Conn.ExecSQL('UPDATE deepframes_job_step SET status = ''done'', updated_at = NOW() WHERE step_id = :sid::uuid', [StepId_]);
    Conn.ExecSQL('UPDATE deepframes_job SET status = ''done'', updated_at = NOW() WHERE job_id = :jid::uuid', [JobId_]);

    // Verify done
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'SELECT status FROM deepframes_job WHERE job_id = :jid::uuid';
      Q.ParamByName('jid').AsString := JobId_;
      Q.Open;
      St := Q.FieldByName('status').AsString;
      Report('Job running→done', St = 'done', St);
    finally
      Q.Free;
    end;

    // Verify step done
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := 'SELECT COUNT(*) AS cnt FROM deepframes_job_step WHERE job_id = :jid::uuid AND status = ''done''';
      Q.ParamByName('jid').AsString := JobId_;
      Q.Open;
      RowCount := Q.FieldByName('cnt').AsInteger;
      Report('Step running→done', RowCount = 1, IntToStr(RowCount) + ' steps done');
    finally
      Q.Free;
    end;

    Report('Full state transition: pending→running→done', True);
  except
    on E: Exception do
      Report('DB2 update', False, E.Message);
  end;
  Conn.Free;
end;

procedure Cleanup;
var
  WorkDir: string;
  Conn: TFDConnection;
begin
  WriteLn('');
  WriteLn('=== Cleanup ===');

  WorkDir := TPath.Combine(GetCurrentDir, 'poc3e_test_workdir');
  if TDirectory.Exists(WorkDir) then
  begin
    TDirectory.Delete(WorkDir, True);
    WriteLn('  Removed: ' + WorkDir);
  end;

  if (G_ProjId <> '') then
  begin
    Conn := TDeepFramesDB2Connection.CreateConnection(True);
    try
      if G_StepId <> '' then
        Conn.ExecSQL('DELETE FROM deepframes_job_step WHERE step_id = :id::uuid', [G_StepId]);
      if G_JobId <> '' then
        Conn.ExecSQL('DELETE FROM deepframes_job WHERE job_id = :id::uuid', [G_JobId]);
      if G_CuId <> '' then
        Conn.ExecSQL('DELETE FROM deepframes_content_unit WHERE content_unit_id = :id::uuid', [G_CuId]);
      if G_ProjId <> '' then
        Conn.ExecSQL('DELETE FROM deepframes_project WHERE project_id = :id::uuid', [G_ProjId]);
    finally
      Conn.Free;
    end;
  end;

  WriteLn('  Cleanup done');
end;

begin
  PassCount := 0;
  FailCount := 0;
  G_ProjId := '';
  G_CuId := '';
  G_JobId := '';
  G_StepId := '';

  WriteLn('========================================');
  WriteLn(' DeepFrames POC 3e — Worker Protocol E2E');
  WriteLn(' ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  WriteLn('========================================');

  WriteLn('');
  WriteLn('=== Test 0: Initialization ===');
  try
    DeepBase.Manager.DeepBase.InitializeOrRaise;
    TDeepFramesBootstrap.RegisterServices;
    Report('DeepBase+Bootstrap', True);
  except
    on E: Exception do
    begin
      Report('Init', False, E.Message);
      WriteLn('FATAL: Init failed');
      Halt(1);
    end;
  end;

  TestWriteRequest;
  TestLaunchWorker;
  TestReadResult;
  TestDB2Update;

  Cleanup;

  TDeepFramesBootstrap.Shutdown;
  DeepBase.Manager.DeepBase.Finalize;

  WriteLn('');
  WriteLn('========================================');
  WriteLn(Format(' RESULTS: %d passed, %d failed', [PassCount, FailCount]));
  WriteLn('========================================');

  if FailCount > 0 then
    Halt(1)
  else
    Halt(0);
end.
