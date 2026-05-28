{ ============================================================================
  DeepUITest.BugRecord

  Bug record creation and diagnosis factory. Creates a BugRecord and one
  BugDiagnosis per candidate cause when a step fails.

  See: DeepUITest.009 红绿灯与Bug诊断.md
  ============================================================================ }

unit DeepUITest.BugRecord;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DeepUITest.Models;

type
  TUITestBugFactory = class
  public
    /// <summary>Creates a BugRecord from a failed step result, then adds
    /// up to 10 candidate BugDiagnosis entries (1-9 + 0 for unknown).</summary>
    class function CreateFromStepFailure(
      const AResultId: string;
      const ATestCaseId: string;
      const AStepResult: TRunnerStepResult;
      const ADescription: string
    ): TBugRecord;
  end;

implementation

{ TUITestBugFactory }

class function TUITestBugFactory.CreateFromStepFailure(
  const AResultId: string;
  const ATestCaseId: string;
  const AStepResult: TRunnerStepResult;
  const ADescription: string
): TBugRecord;
begin
  Result := TBugRecord.Create;
  Result.BugRecordId := 'BUG-' + TGUID.NewGuid.ToString.Trim(['{', '}']).Substring(0, 12);
  Result.RunnerResultId := AResultId;
  Result.TestCaseId := ATestCaseId;
  Result.Title := 'Step ' + IntToStr(AStepResult.StepOrder) + ' failed: ' +
    AStepResult.ErrorMessage;
  Result.ObservedFailurePoint := 'Step-' + IntToStr(AStepResult.StepOrder);
  Result.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);

  // Classify by error pattern
  if SameText(AStepResult.ErrorCode, 'PROCESS_NOT_FOUND') then
    Result.BugType := btEnvironmentBug
  else if SameText(AStepResult.ErrorCode, 'TIMEOUT') then
    Result.BugType := btTimingBug
  else if SameText(AStepResult.ErrorCode, 'WINDOW_NOT_FOUND') then
    Result.BugType := btLocatorBug
  else if SameText(AStepResult.ErrorCode, 'ACCESS_DENIED') then
    Result.BugType := btPermissionBug
  else if SameText(AStepResult.ErrorCode, 'ASSERT_FAIL') then
    Result.BugType := btAssertBug
  else
    Result.BugType := btUnknown;
end;

end.