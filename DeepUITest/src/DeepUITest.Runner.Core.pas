{ ============================================================================
  DeepUITest.Runner.Core

  Execution engine that reads a TestCase from DB2, loops through
  JourneySteps, dispatches to TUITestAction, evaluates assertions via
  TUITestLamp, and writes all results back to DB2.

  See: DeepUITest.007 Runner与Probe设计.md
  ============================================================================ }

unit DeepUITest.Runner.Core;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DeepUITest.Models;

type
  TUITestRunner = class
  private class var
    FWorkingPath: string;
    FLogPath: string;
  public
    class property WorkingPath: string read FWorkingPath;
    class property LogPath: string read FLogPath;

    class function Run(
      const AProjectId: string;
      const ATestCaseId: string
    ): string;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  DeepUITest.DB,
  DeepUITest.Runner.Actions,
  DeepUITest.Lamp,
  DeepUITest.BugRecord;

function NewId(const APrefix: string): string;
begin
  Result := APrefix + '-' + TGUID.NewGuid.ToString.Trim(['{', '}']).Substring(0, 8);
end;

class function TUITestRunner.Run(
  const AProjectId: string;
  const ATestCaseId: string
): string;
var
  LTestCase: TTestCase;
  LBatch: TRunnerBatch;
  LResult: TRunnerResult;
  LStepResults: TArray<TRunnerStepResult>;
  LLamp: TLampEvaluation;
  LPrecondMissing: Boolean;
  LEnvIssues: string;
  LRunId: string;
  I: Integer;
  LStep: TJourneyStep;
  LStepRes: TRunnerStepResult;
  LAssertArray: TArray<TAssertRule>;
  LBug: TBugRecord;
  LDiag: TBugDiagnosis;
begin
  LPrecondMissing := False;
  LEnvIssues := '';

  try
  LTestCase := TUITestDB.LoadTestCase(ATestCaseId);
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, 'ERROR loading testcase: ', E.Message);
      Exit('');
    end;
  end;

  if LTestCase = nil then
  begin
    WriteLn(ErrOutput, 'ERROR: TestCase not found: ', ATestCaseId);
    Exit('');
  end;

  LRunId := NewId('RUN');
  FWorkingPath := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'DeepUITest'), LRunId);
  FLogPath := TPath.Combine(FWorkingPath, 'runner.log');
  ForceDirectories(FWorkingPath);

  // ---- RunnerBatch ----
  LBatch := TRunnerBatch.Create;
  LBatch.RunnerBatchId := NewId('BATCH');
  LBatch.AppVersionId := '';
  LBatch.BatchName := 'Run-' + LRunId;
  LBatch.RunMode := 'single';
  LBatch.StartedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  LBatch.Status := 'running';
  TUITestDB.SaveRunnerBatch(LBatch);

  // ---- RunnerResult ----
  LResult := TRunnerResult.Create;
  LResult.RunnerResultId := NewId('RES');
  LResult.RunnerBatchId := LBatch.RunnerBatchId;
  LResult.TestCaseId := ATestCaseId;
  LResult.RunId := LRunId;
  LResult.StartedAt := LBatch.StartedAt;
  LResult.WorkingDir := FWorkingPath;
  LResult.LogPath := FLogPath;

  // ---- Log start ----
  TUITestAction.DoWriteLog('Runner started: testCase=' + ATestCaseId + ', runId=' + LRunId, FLogPath);

  // ---- Execute steps ----
  SetLength(LStepResults, LTestCase.Steps.Count);

  for I := 0 to LTestCase.Steps.Count - 1 do
  begin
    LStep := LTestCase.Steps[I];
    LStepRes := nil;

    WriteLn(Format('Step %d/%d: %s', [I+1, LTestCase.Steps.Count, LStep.StepName]));

    TUITestAction.DoWriteLog(
      Format('Step %d/%d: %s',
        [I+1, LTestCase.Steps.Count, LStep.StepName]),
      FLogPath);

    case LStep.ActionType of
      atStartProcess:
        LStepRes := TUITestAction.DoStartProcess(LStep.TargetRef, LStep.InputValue,
          LStep.TimeoutMs, FWorkingPath);
      atEnsureProcess:
        LStepRes := TUITestAction.DoEnsureProcess(LStep.TargetRef, LStep.TimeoutMs,
          LStep.ExpectedState, LStep.InputValue);
      atWaitWindow:
        LStepRes := TUITestAction.DoWaitWindow(LStep.TargetRef, LStep.TimeoutMs);
      atSendHotkey:
        LStepRes := TUITestAction.DoSendHotkey(LStep.InputValue);
      atSendKey:
        if LStep.InputValue <> '' then
          LStepRes := TUITestAction.DoSendKey(LStep.InputValue[1]);
      atMouseMove:
        begin
          var LP: TArray<string>;
          LP := LStep.TargetRef.Split([',']);
          if Length(LP) >= 2 then
            LStepRes := TUITestAction.DoMouseMove(StrToIntDef(LP[0], 0), StrToIntDef(LP[1], 0))
          else
          begin
            LStepRes := TRunnerStepResult.Create;
            LStepRes.Status := 'fail';
            LStepRes.ErrorCode := 'BAD_COORDS';
            LStepRes.ErrorMessage := 'MouseMove needs TargetRef as X,Y';
          end;
        end;
      atMouseClick:
        begin
          var LP: TArray<string>;
          LP := LStep.TargetRef.Split([',']);
          if Length(LP) >= 2 then
            LStepRes := TUITestAction.DoMouseClick(StrToIntDef(LP[0], 0), StrToIntDef(LP[1], 0))
          else
          begin
            LStepRes := TRunnerStepResult.Create;
            LStepRes.Status := 'fail';
            LStepRes.ErrorCode := 'BAD_COORDS';
            LStepRes.ErrorMessage := 'MouseClick needs TargetRef as X,Y';
          end;
        end;
      atMouseDrag:
        begin
          var LP: TArray<string>;
          var LT: TArray<string>;
          LP := LStep.TargetRef.Split([',']);
          LT := LStep.InputValue.Split([',']);
          if (Length(LP) >= 2) and (Length(LT) >= 2) then
            LStepRes := TUITestAction.DoMouseDrag(
              StrToIntDef(LP[0], 0), StrToIntDef(LP[1], 0),
              StrToIntDef(LT[0], 0), StrToIntDef(LT[1], 0))
          else
          begin
            LStepRes := TRunnerStepResult.Create;
            LStepRes.Status := 'fail';
            LStepRes.ErrorCode := 'BAD_COORDS';
            LStepRes.ErrorMessage := 'MouseDrag needs TargetRef=fromX,fromY InputValue=toX,toY';
          end;
        end;
      atMouseDblClick:
        begin
          var LP: TArray<string>;
          LP := LStep.TargetRef.Split([',']);
          if Length(LP) >= 2 then
            LStepRes := TUITestAction.DoMouseDblClick(StrToIntDef(LP[0], 0), StrToIntDef(LP[1], 0))
          else
          begin
            LStepRes := TRunnerStepResult.Create;
            LStepRes.Status := 'fail';
            LStepRes.ErrorCode := 'BAD_COORDS';
            LStepRes.ErrorMessage := 'MouseDblClick needs TargetRef as X,Y';
          end;
        end;
      atVerifyProcess:
        LStepRes := TUITestAction.DoVerifyProcess(LStep.TargetRef);
      atVerifyWindow:
        LStepRes := TUITestAction.DoVerifyWindow(LStep.TargetRef);
      atVerifyFile:
        LStepRes := TUITestAction.DoVerifyFile(LStep.TargetRef, LStep.ExpectedState);
      atTakeScreenshot:
        begin
          LStepRes := TRunnerStepResult.Create;
          LStepRes.Status := 'pass';
          LStepRes.ActualValue := 'TakeScreenshot deferred to MVP-2';
        end;
      atWriteLog:
        LStepRes := TUITestAction.DoWriteLog(LStep.InputValue, FLogPath);
    end;

    if LStepRes = nil then
    begin
      LStepRes := TRunnerStepResult.Create;
      LStepRes.Status := 'fail';
      LStepRes.ErrorCode := 'NO_ACTION';
      LStepRes.ErrorMessage := 'No action result for step: ' + LStep.StepName;
    end;

    LStepRes.RunnerStepResultId := NewId('SSR');
    LStepRes.RunnerResultId := LResult.RunnerResultId;
    LStepRes.JourneyStepId := LStep.JourneyStepId;
    LStepRes.StepOrder := LStep.StepOrder;
    LStepResults[I] := LStepRes;

    TUITestDB.SaveRunnerStepResult(LStepRes);

    TUITestAction.DoWriteLog(
      Format('  -> %s: %s',
        [LStepRes.Status, Copy(LStepRes.ErrorMessage, 1, 120)]),
      FLogPath);

    // Halt on fatal step failure if policy demands it
    if not SameText(LStepRes.Status, 'pass') and SameText(LStep.OnFailPolicy, 'halt') then
    begin
      TUITestAction.DoWriteLog('Halted on step failure: ' + LStep.StepName, FLogPath);
      Break;
    end;

    Sleep(300);
  end;

  // ---- Compact step results (remove nil entries from early halt) ----
  var LValidCount := 0;
  for I := 0 to High(LStepResults) do
    if LStepResults[I] <> nil then
      Inc(LValidCount);
  var LCompacted: TArray<TRunnerStepResult>;
  SetLength(LCompacted, LValidCount);
  var J := 0;
  for I := 0 to High(LStepResults) do
    if LStepResults[I] <> nil then
    begin
      LCompacted[J] := LStepResults[I];
      Inc(J);
    end;

  // ---- Evaluate assertions ----
  SetLength(LAssertArray, LTestCase.Assertions.Count);
  for I := 0 to LTestCase.Assertions.Count - 1 do
    LAssertArray[I] := LTestCase.Assertions[I];

  LLamp := TUITestLamp.Evaluate(LResult, LCompacted, LAssertArray,
    LPrecondMissing, LEnvIssues);
  LResult.LampState := LLamp.LampState;
  LLamp.LampEvaluationId := NewId('LAMP');
  LLamp.TestCaseId := ATestCaseId;
  LLamp.RunnerResultId := LResult.RunnerResultId;

  // Set RunnerResult status from lamp
  case LLamp.LampState of
    lsGreen:  LResult.Status := 'pass';
    lsYellow: LResult.Status := 'pass';
    lsRed:    LResult.Status := 'fail';
    lsGray:   LResult.Status := 'unknown';
  end;

  // ---- Save results ----
  LResult.FinishedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  TUITestDB.SaveRunnerResult(LResult);
  TUITestDB.SaveLampEvaluation(LLamp);

  // ---- Bug record on failure ----
  if LLamp.LampState = lsRed then
  begin
    for I := 0 to High(LStepResults) do
      if not SameText(LStepResults[I].Status, 'pass') then
      begin
        LBug := TUITestBugFactory.CreateFromStepFailure(
          LResult.RunnerResultId, ATestCaseId, LStepResults[I],
          LStepResults[I].ErrorMessage);
        TUITestDB.SaveBugRecord(LBug);

        LDiag := TBugDiagnosis.Create;
        LDiag.BugDiagnosisId := NewId('DIAG');
        LDiag.BugRecordId := LBug.BugRecordId;
        LDiag.CandidateNo := 1;
        LDiag.DiagnosisText := LBug.BugType.ToString + ': ' + LStepResults[I].ErrorMessage;
        TUITestDB.SaveBugDiagnosis(LDiag);

        LBug.Free;
        LDiag.Free;
        Break;
      end;
  end;

  // ---- Finalize ----
  LBatch.Status := 'done';
  LBatch.FinishedAt := LResult.FinishedAt;
  TUITestDB.SaveRunnerBatch(LBatch);

  TUITestAction.DoWriteLog(
    Format('Runner done: lamp=%s, status=%s',
      [LLamp.LampState.ToString, LResult.Status]),
    FLogPath);

  Result := LResult.RunnerResultId;

  // Cleanup
  LTestCase.Free;
  LBatch.Free;
  LResult.Free;
  LLamp.Free;
  for I := 0 to High(LStepResults) do
    LStepResults[I].Free;
end;

end.