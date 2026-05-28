{ ============================================================================
  DeepUITest.Models

  Pure data structures for DeepUITest — no logic, no DB, no UI.

  See: DeepUITest.005 系统架构与数据模型.md
  ============================================================================ }

unit DeepUITest.Models;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  // Forward declarations (needed by TTestCase)
  TJourneyStep = class;
  TAssertRule = class;

  // ---------------------------------------------------------------------------
  // 灯色
  // ---------------------------------------------------------------------------
  TLampState = (lsGreen, lsYellow, lsRed, lsGray);

  TLampStateHelper = record helper for TLampState
    function ToString: string;
    class function FromString(const S: string): TLampState; static;
  end;

  // ---------------------------------------------------------------------------
  // 动作类型
  // ---------------------------------------------------------------------------
  TActionType = (
    atStartProcess,
    atEnsureProcess,
    atWaitWindow,
    atSendHotkey,
    atSendKey,
    atMouseMove,
    atMouseClick,
    atMouseDrag,
    atMouseDblClick,
    atVerifyProcess,
    atVerifyWindow,
    atVerifyFile,
    atTakeScreenshot,
    atWriteLog
  );

  TActionTypeHelper = record helper for TActionType
    function ToString: string;
    class function FromString(const S: string): TActionType; static;
  end;

  // ---------------------------------------------------------------------------
  // 断言类型
  // ---------------------------------------------------------------------------
  TAssertType = (
    astProcessExists,
    astWindowVisible,
    astWindowTitleMatch,
    astFileExists,
    astJsonValueMatch
  );

  TAssertTypeHelper = record helper for TAssertType
    function ToString: string;
    class function FromString(const S: string): TAssertType; static;
  end;

  // ---------------------------------------------------------------------------
  // Bug 类型
  // ---------------------------------------------------------------------------
  TBugType = (
    btProductBug,
    btTestConfigBug,
    btLocatorBug,
    btAssertBug,
    btMockDataBug,
    btEnvironmentBug,
    btPermissionBug,
    btTimingBug,
    btUnknown
  );

  TBugTypeHelper = record helper for TBugType
    function ToString: string;
    class function FromString(const S: string): TBugType; static;
  end;

  // ---------------------------------------------------------------------------
  // AppProject
  // ---------------------------------------------------------------------------
  TAppProject = class
  public
    AppProjectId: string;
    Name: string;
    DisplayName: string;
    AppKind: string;
    TechStack: string;
    RootPath: string;
    Description: string;
    CreatedAt: string;
    UpdatedAt: string;
  end;

  // ---------------------------------------------------------------------------
  // AppVersion
  // ---------------------------------------------------------------------------
  TAppVersion = class
  public
    AppVersionId: string;
    AppProjectId: string;
    VersionName: string;
    VersionNo: Integer;
    BuildNo: Integer;
    ExecutablePath: string;
    SourceRoot: string;
    IsSealed: Boolean;
    SealedAt: string;
    CreatedAt: string;
  end;

  // ---------------------------------------------------------------------------
  // JourneyStep
  // ---------------------------------------------------------------------------
  TJourneyStep = class
  public
    JourneyStepId: string;
    TestCaseId: string;
    StepOrder: Integer;
    GateKey: string;
    StepName: string;
    ActionType: TActionType;
    TargetRef: string;
    InputValue: string;
    TimeoutMs: Integer;
    ExpectedState: string;
    OnFailPolicy: string;
  end;

  // ---------------------------------------------------------------------------
  // AssertRule
  // ---------------------------------------------------------------------------
  TAssertRule = class
  public
    AssertRuleId: string;
    TestCaseId: string;
    JourneyStepId: string;
    AssertType: TAssertType;
    TargetRef: string;
    ExpectedValue: string;
    Tolerance: Integer;
    RequiredLevel: string;
    EvidenceKind: string;
  end;

  // ---------------------------------------------------------------------------
  // TestCase
  // ---------------------------------------------------------------------------
  TTestCase = class
  public
    TestCaseId: string;
    AppVersionId: string;
    Title: string;
    OutputKey: string;
    RiskLevel: Integer;
    Priority: Integer;
    Status: string;
    IsSealed: Boolean;
    CreatedBy: string;
    CreatedAt: string;

    Steps: TObjectList<TJourneyStep>;
    Assertions: TObjectList<TAssertRule>;

    constructor Create;
    destructor Destroy; override;
  end;

  // ---------------------------------------------------------------------------
  // RunnerBatch
  // ---------------------------------------------------------------------------
  TRunnerBatch = class
  public
    RunnerBatchId: string;
    AppVersionId: string;
    BatchName: string;
    RunMode: string;
    StartedAt: string;
    FinishedAt: string;
    Status: string;
    Operator: string;
  end;

  // ---------------------------------------------------------------------------
  // RunnerResult
  // ---------------------------------------------------------------------------
  TRunnerResult = class
  public
    RunnerResultId: string;
    RunnerBatchId: string;
    TestCaseId: string;
    RunId: string;
    Status: string;
    LampState: TLampState;
    StartedAt: string;
    FinishedAt: string;
    WorkingDir: string;
    LogPath: string;
  end;

  // ---------------------------------------------------------------------------
  // RunnerStepResult
  // ---------------------------------------------------------------------------
  TRunnerStepResult = class
  public
    RunnerStepResultId: string;
    RunnerResultId: string;
    JourneyStepId: string;
    StepOrder: Integer;
    Status: string;
    ActualValue: string;
    ErrorCode: string;
    ErrorMessage: string;
    EvidencePath: string;
    StartedAt: string;
    FinishedAt: string;
  end;

  // ---------------------------------------------------------------------------
  // LampEvaluation
  // ---------------------------------------------------------------------------
  TLampEvaluation = class
  public
    LampEvaluationId: string;
    TestCaseId: string;
    RunnerResultId: string;
    LampState: TLampState;
    RiskLevel: Integer;
    ReasonCode: string;
    ReasonText: string;
    EvidenceSummary: string;
    CreatedAt: string;
  end;

  // ---------------------------------------------------------------------------
  // BugRecord
  // ---------------------------------------------------------------------------
  TBugRecord = class
  public
    BugRecordId: string;
    RunnerResultId: string;
    TestCaseId: string;
    Title: string;
    BugType: TBugType;
    ObservedFailurePoint: string;
    RootCausePoint: string;
    Severity: Integer;
    Status: string;
    CreatedAt: string;
  end;

  // ---------------------------------------------------------------------------
  // BugDiagnosis
  // ---------------------------------------------------------------------------
  TBugDiagnosis = class
  public
    BugDiagnosisId: string;
    BugRecordId: string;
    CandidateNo: Integer;
    DiagnosisText: string;
    SelectedByUser: Boolean;
    UserChoiceValue: Integer;
    Confidence: Integer;
    CreatedAt: string;
  end;

implementation

{ TLampStateHelper }

function TLampStateHelper.ToString: string;
begin
  case Self of
    lsGreen:  Result := 'Green';
    lsYellow: Result := 'Yellow';
    lsRed:    Result := 'Red';
    lsGray:   Result := 'Gray';
  else Result := 'Gray';
  end;
end;

class function TLampStateHelper.FromString(const S: string): TLampState;
begin
  if SameText(S, 'Green')  then Exit(lsGreen);
  if SameText(S, 'Yellow') then Exit(lsYellow);
  if SameText(S, 'Red')    then Exit(lsRed);
  Result := lsGray;
end;

{ TActionTypeHelper }

function TActionTypeHelper.ToString: string;
begin
  case Self of
    atStartProcess:    Result := 'StartProcess';
    atEnsureProcess:   Result := 'EnsureProcess';
    atWaitWindow:      Result := 'WaitWindow';
    atSendHotkey:      Result := 'SendHotkey';
    atSendKey:         Result := 'SendKey';
    atMouseMove:       Result := 'MouseMove';
    atMouseClick:      Result := 'MouseClick';
    atMouseDrag:       Result := 'MouseDrag';
    atMouseDblClick:   Result := 'MouseDblClick';
    atVerifyProcess:   Result := 'VerifyProcess';
    atVerifyWindow:    Result := 'VerifyWindow';
    atVerifyFile:      Result := 'VerifyFile';
    atTakeScreenshot:  Result := 'TakeScreenshot';
    atWriteLog:        Result := 'WriteLog';
  else Result := 'Unknown';
  end;
end;

class function TActionTypeHelper.FromString(const S: string): TActionType;
begin
  Result := atWriteLog;
  if SameText(S, 'StartProcess')    then Result := atStartProcess
  else if SameText(S, 'EnsureProcess')  then Result := atEnsureProcess
  else if SameText(S, 'WaitWindow')     then Result := atWaitWindow
  else if SameText(S, 'SendHotkey')     then Result := atSendHotkey
  else if SameText(S, 'SendKey')        then Result := atSendKey
  else if SameText(S, 'MouseMove')      then Result := atMouseMove
  else if SameText(S, 'MouseClick')     then Result := atMouseClick
  else if SameText(S, 'MouseDrag')      then Result := atMouseDrag
  else if SameText(S, 'MouseDblClick')  then Result := atMouseDblClick
  else if SameText(S, 'VerifyProcess')  then Result := atVerifyProcess
  else if SameText(S, 'VerifyWindow')   then Result := atVerifyWindow
  else if SameText(S, 'VerifyFile')     then Result := atVerifyFile
  else if SameText(S, 'TakeScreenshot') then Result := atTakeScreenshot;
end;

{ TAssertTypeHelper }

function TAssertTypeHelper.ToString: string;
begin
  case Self of
    astProcessExists:     Result := 'ProcessExists';
    astWindowVisible:     Result := 'WindowVisible';
    astWindowTitleMatch:  Result := 'WindowTitleMatch';
    astFileExists:        Result := 'FileExists';
    astJsonValueMatch:    Result := 'JsonValueMatch';
  else Result := 'Unknown';
  end;
end;

class function TAssertTypeHelper.FromString(const S: string): TAssertType;
begin
  Result := astProcessExists;
  if SameText(S, 'WindowVisible')         then Result := astWindowVisible
  else if SameText(S, 'WindowTitleMatch') then Result := astWindowTitleMatch
  else if SameText(S, 'FileExists')       then Result := astFileExists
  else if SameText(S, 'JsonValueMatch')   then Result := astJsonValueMatch;
end;

{ TBugTypeHelper }

function TBugTypeHelper.ToString: string;
begin
  case Self of
    btProductBug:     Result := 'ProductBug';
    btTestConfigBug:  Result := 'TestConfigBug';
    btLocatorBug:     Result := 'LocatorBug';
    btAssertBug:      Result := 'AssertBug';
    btMockDataBug:    Result := 'MockDataBug';
    btEnvironmentBug: Result := 'EnvironmentBug';
    btPermissionBug:  Result := 'PermissionBug';
    btTimingBug:      Result := 'TimingBug';
    btUnknown:        Result := 'Unknown';
  else Result := 'Unknown';
  end;
end;

class function TBugTypeHelper.FromString(const S: string): TBugType;
begin
  Result := btUnknown;
  if SameText(S, 'ProductBug')         then Result := btProductBug
  else if SameText(S, 'TestConfigBug') then Result := btTestConfigBug
  else if SameText(S, 'LocatorBug')    then Result := btLocatorBug
  else if SameText(S, 'AssertBug')     then Result := btAssertBug
  else if SameText(S, 'MockDataBug')   then Result := btMockDataBug
  else if SameText(S, 'EnvironmentBug') then Result := btEnvironmentBug
  else if SameText(S, 'PermissionBug') then Result := btPermissionBug
  else if SameText(S, 'TimingBug')     then Result := btTimingBug;
end;

{ TTestCase }

constructor TTestCase.Create;
begin
  Steps := TObjectList<TJourneyStep>.Create;
  Assertions := TObjectList<TAssertRule>.Create;
end;

destructor TTestCase.Destroy;
begin
  Steps.Free;
  Assertions.Free;
  inherited;
end;

end.