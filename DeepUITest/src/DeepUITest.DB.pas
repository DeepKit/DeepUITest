{ ============================================================================
  DeepUITest.DB

  DB2 SQLite business database: Schema creation + basic CRUD for
  Runner, Lamp, and Bug data.

  MVP-0 creates 10 tables (out of 16 planned). Windows/Control/Source
  indexing deferred to MVP-2+.

  See: DeepUITest.005 系统架构与数据模型.md
       DeepUITest.015 DB1-DB4数据部署与API边界.md
  ============================================================================ }

unit DeepUITest.DB;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  DeepUITest.Models;

type
  TUITestDB = class
  private class var
    FConn: TFDConnection;
    FDBPath: string;
  public
    class property Conn: TFDConnection read FConn;
    class property DBPath: string read FDBPath;

    class function Initialize(const ADBPath: string): Boolean;
    class procedure Finalize;

    class procedure InitSchema;

    // AppProject
    class procedure SaveAppProject(const A: TAppProject);
    class function LoadAppProject(const AId: string): TAppProject;

    // TestCase + steps + assertions (atomic load/save)
    class procedure SaveTestCase(const A: TTestCase);
    class function LoadTestCase(const AId: string): TTestCase;

    // Runner
    class procedure SaveRunnerBatch(const A: TRunnerBatch);
    class procedure SaveRunnerResult(const A: TRunnerResult);
    class procedure SaveRunnerStepResult(const A: TRunnerStepResult);

    // Lamp
    class procedure SaveLampEvaluation(const A: TLampEvaluation);

    // Bug
    class procedure SaveBugRecord(const A: TBugRecord);
    class procedure SaveBugDiagnosis(const A: TBugDiagnosis);
  end;

implementation

uses
  System.IOUtils,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Phys.SQLite,
  FireDAC.DApt;

{ TUITestDB }

class function TUITestDB.Initialize(const ADBPath: string): Boolean;
begin
  FDBPath := ExpandFileName(ADBPath);
  Result := False;

  var LDir := ExtractFilePath(FDBPath);
  if LDir <> '' then
    ForceDirectories(LDir);

  FConn := TFDConnection.Create(nil);
  try
    FConn.Params.Values['DriverID'] := 'SQLite';
    FConn.Params.Values['Database'] := ADBPath;
    FConn.LoginPrompt := False;
    FConn.Connected := True;
    Result := True;
  except
    FreeAndNil(FConn);
  end;
end;

class procedure TUITestDB.Finalize;
begin
  if FConn <> nil then
    FConn.Connected := False;
  FreeAndNil(FConn);
end;

class procedure TUITestDB.InitSchema;
begin
  if FConn = nil then Exit;

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS AppProject (' +
    '  AppProjectId TEXT PRIMARY KEY,' +
    '  Name TEXT NOT NULL,' +
    '  DisplayName TEXT,' +
    '  AppKind TEXT,' +
    '  TechStack TEXT,' +
    '  RootPath TEXT,' +
    '  Description TEXT,' +
    '  CreatedAt TEXT,' +
    '  UpdatedAt TEXT' +
    ')');

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS AppVersion (' +
    '  AppVersionId TEXT PRIMARY KEY,' +
    '  AppProjectId TEXT NOT NULL,' +
    '  VersionName TEXT,' +
    '  VersionNo INTEGER DEFAULT 0,' +
    '  BuildNo INTEGER DEFAULT 0,' +
    '  ExecutablePath TEXT,' +
    '  SourceRoot TEXT,' +
    '  IsSealed INTEGER DEFAULT 0,' +
    '  SealedAt TEXT,' +
    '  CreatedAt TEXT' +
    ')');

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS TestCase (' +
    '  TestCaseId TEXT PRIMARY KEY,' +
    '  AppVersionId TEXT NOT NULL,' +
    '  Title TEXT NOT NULL,' +
    '  OutputKey TEXT,' +
    '  RiskLevel INTEGER DEFAULT 0,' +
    '  Priority INTEGER DEFAULT 10,' +
    '  Status TEXT DEFAULT ''draft'',' +
    '  IsSealed INTEGER DEFAULT 0,' +
    '  CreatedBy TEXT,' +
    '  CreatedAt TEXT' +
    ')');

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS JourneyStep (' +
    '  JourneyStepId TEXT PRIMARY KEY,' +
    '  TestCaseId TEXT NOT NULL,' +
    '  StepOrder INTEGER NOT NULL,' +
    '  GateKey TEXT,' +
    '  StepName TEXT,' +
    '  ActionType TEXT NOT NULL,' +
    '  TargetRef TEXT,' +
    '  InputValue TEXT,' +
    '  TimeoutMs INTEGER DEFAULT 10000,' +
    '  ExpectedState TEXT,' +
    '  OnFailPolicy TEXT DEFAULT ''halt''' +
    ')');

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS AssertRule (' +
    '  AssertRuleId TEXT PRIMARY KEY,' +
    '  TestCaseId TEXT NOT NULL,' +
    '  JourneyStepId TEXT,' +
    '  AssertType TEXT NOT NULL,' +
    '  TargetRef TEXT,' +
    '  ExpectedValue TEXT,' +
    '  Tolerance INTEGER DEFAULT 0,' +
    '  RequiredLevel TEXT DEFAULT ''must'',' +
    '  EvidenceKind TEXT' +
    ')');

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS RunnerBatch (' +
    '  RunnerBatchId TEXT PRIMARY KEY,' +
    '  AppVersionId TEXT NOT NULL,' +
    '  BatchName TEXT,' +
    '  RunMode TEXT DEFAULT ''single'',' +
    '  StartedAt TEXT,' +
    '  FinishedAt TEXT,' +
    '  Status TEXT DEFAULT ''running'',' +
    '  Operator TEXT' +
    ')');

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS RunnerResult (' +
    '  RunnerResultId TEXT PRIMARY KEY,' +
    '  RunnerBatchId TEXT NOT NULL,' +
    '  TestCaseId TEXT NOT NULL,' +
    '  RunId TEXT,' +
    '  Status TEXT,' +
    '  LampState TEXT,' +
    '  StartedAt TEXT,' +
    '  FinishedAt TEXT,' +
    '  WorkingDir TEXT,' +
    '  LogPath TEXT' +
    ')');

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS RunnerStepResult (' +
    '  RunnerStepResultId TEXT PRIMARY KEY,' +
    '  RunnerResultId TEXT NOT NULL,' +
    '  JourneyStepId TEXT,' +
    '  StepOrder INTEGER,' +
    '  Status TEXT,' +
    '  ActualValue TEXT,' +
    '  ErrorCode TEXT,' +
    '  ErrorMessage TEXT,' +
    '  EvidencePath TEXT,' +
    '  StartedAt TEXT,' +
    '  FinishedAt TEXT' +
    ')');

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS LampEvaluation (' +
    '  LampEvaluationId TEXT PRIMARY KEY,' +
    '  TestCaseId TEXT NOT NULL,' +
    '  RunnerResultId TEXT,' +
    '  LampState TEXT NOT NULL,' +
    '  RiskLevel INTEGER DEFAULT 0,' +
    '  ReasonCode TEXT,' +
    '  ReasonText TEXT,' +
    '  EvidenceSummary TEXT,' +
    '  CreatedAt TEXT' +
    ')');

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS BugRecord (' +
    '  BugRecordId TEXT PRIMARY KEY,' +
    '  RunnerResultId TEXT NOT NULL,' +
    '  TestCaseId TEXT,' +
    '  Title TEXT,' +
    '  BugType TEXT DEFAULT ''Unknown'',' +
    '  ObservedFailurePoint TEXT,' +
    '  RootCausePoint TEXT,' +
    '  Severity INTEGER DEFAULT 1,' +
    '  Status TEXT DEFAULT ''open'',' +
    '  CreatedAt TEXT' +
    ')');

  FConn.ExecSQL(
    'CREATE TABLE IF NOT EXISTS BugDiagnosis (' +
    '  BugDiagnosisId TEXT PRIMARY KEY,' +
    '  BugRecordId TEXT NOT NULL,' +
    '  CandidateNo INTEGER DEFAULT 0,' +
    '  DiagnosisText TEXT,' +
    '  SelectedByUser INTEGER DEFAULT 0,' +
    '  UserChoiceValue INTEGER DEFAULT -1,' +
    '  Confidence INTEGER DEFAULT 0,' +
    '  CreatedAt TEXT' +
    ')');
end;

{ ---- AppProject ---- }

class procedure TUITestDB.SaveAppProject(const A: TAppProject);
begin
  FConn.ExecSQL(
    'INSERT OR REPLACE INTO AppProject (' +
    'AppProjectId,Name,DisplayName,AppKind,TechStack,RootPath,Description,CreatedAt,UpdatedAt' +
    ') VALUES (?,?,?,?,?,?,?,?,?)',
    [A.AppProjectId, A.Name, A.DisplayName, A.AppKind,
     A.TechStack, A.RootPath, A.Description, A.CreatedAt, A.UpdatedAt]);
end;

class function TUITestDB.LoadAppProject(const AId: string): TAppProject;
var
  LQ: TFDQuery;
begin
  Result := nil;
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := FConn;
    LQ.SQL.Text := 'SELECT * FROM AppProject WHERE AppProjectId = ?';
    LQ.Params[0].AsString := AId;
    LQ.Open;
    if not LQ.IsEmpty then
    begin
      Result := TAppProject.Create;
      Result.AppProjectId := LQ.FieldByName('AppProjectId').AsString;
      Result.Name         := LQ.FieldByName('Name').AsString;
      Result.DisplayName  := LQ.FieldByName('DisplayName').AsString;
      Result.AppKind      := LQ.FieldByName('AppKind').AsString;
      Result.TechStack    := LQ.FieldByName('TechStack').AsString;
      Result.RootPath     := LQ.FieldByName('RootPath').AsString;
      Result.Description  := LQ.FieldByName('Description').AsString;
      Result.CreatedAt    := LQ.FieldByName('CreatedAt').AsString;
      Result.UpdatedAt    := LQ.FieldByName('UpdatedAt').AsString;
    end;
  finally
    LQ.Free;
  end;
end;

{ ---- TestCase ---- }

class procedure TUITestDB.SaveTestCase(const A: TTestCase);
begin
  FConn.ExecSQL(
    'INSERT OR REPLACE INTO TestCase (' +
    'TestCaseId,AppVersionId,Title,OutputKey,RiskLevel,Priority,Status,IsSealed,CreatedBy,CreatedAt' +
    ') VALUES (?,?,?,?,?,?,?,?,?,?)',
    [A.TestCaseId, A.AppVersionId, A.Title, A.OutputKey,
     A.RiskLevel, A.Priority, A.Status, Ord(A.IsSealed), A.CreatedBy, A.CreatedAt]);

  // Save steps
  FConn.ExecSQL('DELETE FROM JourneyStep WHERE TestCaseId = ?', [A.TestCaseId]);
  for var LStep in A.Steps do
    FConn.ExecSQL(
      'INSERT INTO JourneyStep (' +
      'JourneyStepId,TestCaseId,StepOrder,GateKey,StepName,ActionType,TargetRef,InputValue,TimeoutMs,ExpectedState,OnFailPolicy' +
      ') VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      [LStep.JourneyStepId, A.TestCaseId, LStep.StepOrder, LStep.GateKey,
       LStep.StepName, LStep.ActionType.ToString, LStep.TargetRef,
       LStep.InputValue, LStep.TimeoutMs, LStep.ExpectedState, LStep.OnFailPolicy]);

  // Save assertions
  FConn.ExecSQL('DELETE FROM AssertRule WHERE TestCaseId = ?', [A.TestCaseId]);
  for var LAssert in A.Assertions do
    FConn.ExecSQL(
      'INSERT INTO AssertRule (' +
      'AssertRuleId,TestCaseId,JourneyStepId,AssertType,TargetRef,ExpectedValue,Tolerance,RequiredLevel,EvidenceKind' +
      ') VALUES (?,?,?,?,?,?,?,?,?)',
      [LAssert.AssertRuleId, A.TestCaseId, LAssert.JourneyStepId,
       LAssert.AssertType.ToString, LAssert.TargetRef,
       LAssert.ExpectedValue, LAssert.Tolerance,
       LAssert.RequiredLevel, LAssert.EvidenceKind]);
end;

class function TUITestDB.LoadTestCase(const AId: string): TTestCase;
var
  LQ: TFDQuery;
begin
  Result := nil;
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := FConn;
    LQ.SQL.Text := 'SELECT * FROM TestCase WHERE TestCaseId = ?';
    LQ.Params[0].AsString := AId;
    LQ.Open;
    if LQ.IsEmpty then Exit;

    Result := TTestCase.Create;
    Result.TestCaseId := LQ.FieldByName('TestCaseId').AsString;
    Result.AppVersionId := LQ.FieldByName('AppVersionId').AsString;
    Result.Title       := LQ.FieldByName('Title').AsString;
    Result.OutputKey   := LQ.FieldByName('OutputKey').AsString;
    Result.RiskLevel   := LQ.FieldByName('RiskLevel').AsInteger;
    Result.Priority    := LQ.FieldByName('Priority').AsInteger;
    Result.Status      := LQ.FieldByName('Status').AsString;
    Result.IsSealed    := LQ.FieldByName('IsSealed').AsInteger = 1;
    Result.CreatedBy   := LQ.FieldByName('CreatedBy').AsString;
    Result.CreatedAt   := LQ.FieldByName('CreatedAt').AsString;
  finally
    LQ.Free;
  end;

  // Load steps
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := FConn;
    LQ.SQL.Text := 'SELECT * FROM JourneyStep WHERE TestCaseId = ? ORDER BY StepOrder';
    LQ.Params[0].AsString := AId;
    LQ.Open;
    while not LQ.Eof do
    begin
      var LStep := TJourneyStep.Create;
      LStep.JourneyStepId := LQ.FieldByName('JourneyStepId').AsString;
      LStep.TestCaseId    := LQ.FieldByName('TestCaseId').AsString;
      LStep.StepOrder     := LQ.FieldByName('StepOrder').AsInteger;
      LStep.GateKey       := LQ.FieldByName('GateKey').AsString;
      LStep.StepName      := LQ.FieldByName('StepName').AsString;
var LActionStr: string;
        LActionStr := LQ.FieldByName('ActionType').AsString;
        if SameText(LActionStr, 'StartProcess')    then LStep.ActionType := atStartProcess
        else if SameText(LActionStr, 'EnsureProcess')  then LStep.ActionType := atEnsureProcess
        else if SameText(LActionStr, 'WaitWindow')     then LStep.ActionType := atWaitWindow
        else if SameText(LActionStr, 'SendHotkey')     then LStep.ActionType := atSendHotkey
        else if SameText(LActionStr, 'SendKey')        then LStep.ActionType := atSendKey
        else if SameText(LActionStr, 'MouseMove')      then LStep.ActionType := atMouseMove
        else if SameText(LActionStr, 'MouseClick')     then LStep.ActionType := atMouseClick
        else if SameText(LActionStr, 'MouseDrag')      then LStep.ActionType := atMouseDrag
        else if SameText(LActionStr, 'MouseDblClick')  then LStep.ActionType := atMouseDblClick
        else if SameText(LActionStr, 'VerifyProcess')  then LStep.ActionType := atVerifyProcess
        else if SameText(LActionStr, 'VerifyWindow')   then LStep.ActionType := atVerifyWindow
        else if SameText(LActionStr, 'VerifyFile')     then LStep.ActionType := atVerifyFile
        else if SameText(LActionStr, 'TakeScreenshot') then LStep.ActionType := atTakeScreenshot
        else LStep.ActionType := atWriteLog;
      LStep.TargetRef     := LQ.FieldByName('TargetRef').AsString;
      LStep.InputValue    := LQ.FieldByName('InputValue').AsString;
      LStep.TimeoutMs     := LQ.FieldByName('TimeoutMs').AsInteger;
      LStep.ExpectedState := LQ.FieldByName('ExpectedState').AsString;
      LStep.OnFailPolicy  := LQ.FieldByName('OnFailPolicy').AsString;
      Result.Steps.Add(LStep);
      LQ.Next;
    end;
  finally
    LQ.Free;
  end;

  // Load assertions
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := FConn;
    LQ.SQL.Text := 'SELECT * FROM AssertRule WHERE TestCaseId = ?';
    LQ.Params[0].AsString := AId;
    LQ.Open;
    while not LQ.Eof do
    begin
      var LAssert := TAssertRule.Create;
      LAssert.AssertRuleId := LQ.FieldByName('AssertRuleId').AsString;
      LAssert.TestCaseId   := LQ.FieldByName('TestCaseId').AsString;
      LAssert.JourneyStepId := LQ.FieldByName('JourneyStepId').AsString;
var LAssertStr: string;
        LAssertStr := LQ.FieldByName('AssertType').AsString;
        if SameText(LAssertStr, 'WindowVisible')         then LAssert.AssertType := astWindowVisible
        else if SameText(LAssertStr, 'WindowTitleMatch') then LAssert.AssertType := astWindowTitleMatch
        else if SameText(LAssertStr, 'FileExists')       then LAssert.AssertType := astFileExists
        else if SameText(LAssertStr, 'JsonValueMatch')   then LAssert.AssertType := astJsonValueMatch
        else LAssert.AssertType := astProcessExists;
      LAssert.TargetRef    := LQ.FieldByName('TargetRef').AsString;
      LAssert.ExpectedValue := LQ.FieldByName('ExpectedValue').AsString;
      LAssert.Tolerance    := LQ.FieldByName('Tolerance').AsInteger;
      LAssert.RequiredLevel := LQ.FieldByName('RequiredLevel').AsString;
      LAssert.EvidenceKind := LQ.FieldByName('EvidenceKind').AsString;
      Result.Assertions.Add(LAssert);
      LQ.Next;
    end;
  finally
    LQ.Free;
  end;
end;

{ ---- Runner ---- }

class procedure TUITestDB.SaveRunnerBatch(const A: TRunnerBatch);
begin
  FConn.ExecSQL(
    'INSERT OR REPLACE INTO RunnerBatch (' +
    'RunnerBatchId,AppVersionId,BatchName,RunMode,StartedAt,FinishedAt,Status,Operator' +
    ') VALUES (?,?,?,?,?,?,?,?)',
    [A.RunnerBatchId, A.AppVersionId, A.BatchName, A.RunMode,
     A.StartedAt, A.FinishedAt, A.Status, A.Operator]);
end;

class procedure TUITestDB.SaveRunnerResult(const A: TRunnerResult);
begin
  FConn.ExecSQL(
    'INSERT OR REPLACE INTO RunnerResult (' +
    'RunnerResultId,RunnerBatchId,TestCaseId,RunId,Status,LampState,StartedAt,FinishedAt,WorkingDir,LogPath' +
    ') VALUES (?,?,?,?,?,?,?,?,?,?)',
    [A.RunnerResultId, A.RunnerBatchId, A.TestCaseId, A.RunId,
     A.Status, A.LampState.ToString, A.StartedAt, A.FinishedAt,
     A.WorkingDir, A.LogPath]);
end;

class procedure TUITestDB.SaveRunnerStepResult(const A: TRunnerStepResult);
begin
  FConn.ExecSQL(
    'INSERT OR REPLACE INTO RunnerStepResult (' +
    'RunnerStepResultId,RunnerResultId,JourneyStepId,StepOrder,Status,ActualValue,ErrorCode,ErrorMessage,EvidencePath,StartedAt,FinishedAt' +
    ') VALUES (?,?,?,?,?,?,?,?,?,?,?)',
    [A.RunnerStepResultId, A.RunnerResultId, A.JourneyStepId,
     A.StepOrder, A.Status, A.ActualValue, A.ErrorCode, A.ErrorMessage,
     A.EvidencePath, A.StartedAt, A.FinishedAt]);
end;

{ ---- Lamp ---- }

class procedure TUITestDB.SaveLampEvaluation(const A: TLampEvaluation);
begin
  FConn.ExecSQL(
    'INSERT OR REPLACE INTO LampEvaluation (' +
    'LampEvaluationId,TestCaseId,RunnerResultId,LampState,RiskLevel,ReasonCode,ReasonText,EvidenceSummary,CreatedAt' +
    ') VALUES (?,?,?,?,?,?,?,?,?)',
    [A.LampEvaluationId, A.TestCaseId, A.RunnerResultId,
     A.LampState.ToString, A.RiskLevel, A.ReasonCode,
     A.ReasonText, A.EvidenceSummary, A.CreatedAt]);
end;

{ ---- Bug ---- }

class procedure TUITestDB.SaveBugRecord(const A: TBugRecord);
begin
  FConn.ExecSQL(
    'INSERT OR REPLACE INTO BugRecord (' +
    'BugRecordId,RunnerResultId,TestCaseId,Title,BugType,ObservedFailurePoint,RootCausePoint,Severity,Status,CreatedAt' +
    ') VALUES (?,?,?,?,?,?,?,?,?,?)',
    [A.BugRecordId, A.RunnerResultId, A.TestCaseId, A.Title,
     A.BugType.ToString, A.ObservedFailurePoint, A.RootCausePoint,
     A.Severity, A.Status, A.CreatedAt]);
end;

class procedure TUITestDB.SaveBugDiagnosis(const A: TBugDiagnosis);
begin
  FConn.ExecSQL(
    'INSERT OR REPLACE INTO BugDiagnosis (' +
    'BugDiagnosisId,BugRecordId,CandidateNo,DiagnosisText,SelectedByUser,UserChoiceValue,Confidence,CreatedAt' +
    ') VALUES (?,?,?,?,?,?,?,?)',
    [A.BugDiagnosisId, A.BugRecordId, A.CandidateNo,
     A.DiagnosisText, Ord(A.SelectedByUser), A.UserChoiceValue,
     A.Confidence, A.CreatedAt]);
end;

end.