{ ============================================================================
  DeepUITest.Lamp

  Red-Yellow-Green-Gray lamp evaluation for Runner results.

  Takes RunnerResult + RunnerStepResult[] + AssertRule[] and produces a
  single TLampEvaluation.

  See: DeepUITest.009 红绿灯与Bug诊断.md
  ============================================================================ }

unit DeepUITest.Lamp;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DeepUITest.Models;

type
  TUITestLamp = class
  public
    class function Evaluate(
      const AResult: TRunnerResult;
      const AStepResults: TArray<TRunnerStepResult>;
      const AAssertions: TArray<TAssertRule>;
      const APrecondMissing: Boolean;
      const AEnvironmentIssues: string
    ): TLampEvaluation;
  end;

implementation

uses
  System.DateUtils;

{ TUITestLamp }

class function TUITestLamp.Evaluate(
  const AResult: TRunnerResult;
  const AStepResults: TArray<TRunnerStepResult>;
  const AAssertions: TArray<TAssertRule>;
  const APrecondMissing: Boolean;
  const AEnvironmentIssues: string
): TLampEvaluation;
var
  LFailCount, LYellowCount, LTotalMust, LTotalSteps: Integer;
begin
  Result := TLampEvaluation.Create;
  Result.LampState := lsGray;
  Result.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);

  // ---- Preconditions missing → Gray ----
  if APrecondMissing or (AResult = nil) then
  begin
    Result.LampState := lsGray;
    Result.ReasonCode := 'PRECOND_MISSING';
    Result.ReasonText := 'Preconditions not met; cannot evaluate';
    Exit;
  end;

  if Length(AStepResults) = 0 then
  begin
    Result.LampState := lsGray;
    Result.ReasonCode := 'NO_STEP_RESULTS';
    Result.ReasonText := 'No step results recorded';
    Exit;
  end;

  LTotalSteps := Length(AStepResults);

  // ---- Count must-assertion failures and yellow-qualified passes ----
  LFailCount := 0;
  LYellowCount := 0;
  LTotalMust := 0;

  for var LStep in AStepResults do
  begin
    if not SameText(LStep.Status, 'pass') then
      Inc(LFailCount);

    // Yellow: passed but with errorCode = 'WEAK_ASSERT'
    if SameText(LStep.Status, 'pass') and (LStep.ErrorCode = 'WEAK_ASSERT') then
      Inc(LYellowCount);
  end;

  // Count must-level assertions
  for var LA in AAssertions do
    if SameText(LA.RequiredLevel, 'must') then
      Inc(LTotalMust);

  // ---- Environment issues → Yellow warning ----
  if AEnvironmentIssues <> '' then
  begin
    Result.LampState := lsYellow;
    Result.ReasonCode := 'ENV_WARNING';
    Result.ReasonText := 'Environment issues: ' + AEnvironmentIssues;
    Exit;
  end;

  // ---- Runner status crashed/timeout → Red ----
  if SameText(AResult.Status, 'crashed') or SameText(AResult.Status, 'timeout') then
  begin
    Result.LampState := lsRed;
    Result.ReasonCode := 'RUNNER_' + UpperCase(AResult.Status);
    Result.ReasonText := 'Runner terminated with status: ' + AResult.Status;
    Exit;
  end;

  // ---- Any step failure → Red ----
  if LFailCount > 0 then
  begin
    Result.LampState := lsRed;
    Result.ReasonCode := 'STEP_FAILURE';
    Result.ReasonText := Format('%d / %d steps failed', [LFailCount, LTotalSteps]);
    Exit;
  end;

  // ---- Weak assertions only → Yellow ----
  if LYellowCount > 0 then
  begin
    Result.LampState := lsYellow;
    Result.ReasonCode := 'WEAK_ASSERT_ONLY';
    Result.ReasonText := Format('%d steps passed with weak assertions', [LYellowCount]);
    Exit;
  end;

  // ---- All must assertions satisfied → Green ----
  Result.LampState := lsGreen;
  Result.ReasonCode := 'ALL_PASS';
  Result.ReasonText := Format('All %d steps passed, all assertions satisfied', [LTotalSteps]);
end;

end.