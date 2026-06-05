unit DeepFrames.Workflow.GateEvaluator;

/// <summary>
/// Quality gate evaluator for DeepFrames production pipeline.
///
/// Evaluates Gate 1-4 results based on score thresholds and returns
/// pass/warn/fail decisions. Warn is a yellow light — record and continue.
/// Fail is a red light — set blocked_review and stop.
///
/// Thresholds (from docs/08.quality-质量门控-quality-gate.md):
///   Gate 1 (accuracy): pass >= 0.95, warn >= 0.85, fail < 0.85
///   Gate 2 (QA):      pass >= 0.85, warn >= 0.70, fail < 0.70
///   Gate 3a (audio):  pass: lufs within ±1, delta < 200ms
///   Gate 3b (visual): pass >= 0.85, warn >= 0.70, fail < 0.70
///   Gate 4 (package): pass: all checks, fail: any check
/// </summary>

interface

uses
  DeepFrames.Domain.Types;

type
  /// <summary>Detailed evaluation result for a single gate.</summary>
  TGateVerdict = record
    Gate: string;
    GateResult: string;       // pass / warn / fail
    Score: Double;
    Reason: string;           // human-readable explanation
    ShouldBlock: Boolean;     // True if workflow should stop (red light)
    ShouldContinue: Boolean;  // True if workflow can proceed (green or yellow)
    function IsPass: Boolean;
    function IsWarn: Boolean;
    function IsFail: Boolean;
  end;

  /// <summary>Quality gate evaluator with per-gate thresholds.</summary>
  TGateEvaluator = class
  public
    /// <summary>
    /// Evaluate Gate 1 (accuracy_report → script fidelity to source).
    /// Input: coverage_score (0-1), distortion_score (0-1).
    /// </summary>
    class function EvaluateGate1(ACoverageScore, ADistortionScore: Double): TGateVerdict; static;

    /// <summary>
    /// Evaluate Gate 2 (QA → shot-level production quality).
    /// Input: overall score (0-1).
    /// </summary>
    class function EvaluateGate2(AScore: Double): TGateVerdict; static;

    /// <summary>
    /// Evaluate Gate 3a (audio quality → loudness + duration).
    /// Input: measured_lufs, target_lufs, concat_delta_ms.
    /// </summary>
    class function EvaluateGate3a(AMeasuredLufs, ATargetLufs, AConcatDeltaMs: Double): TGateVerdict; static;

    /// <summary>
    /// Evaluate Gate 3b (visual quality → snapshot review).
    /// Input: overall score (0-1).
    /// </summary>
    class function EvaluateGate3b(AScore: Double): TGateVerdict; static;

    /// <summary>
    /// Evaluate Gate 4 (package integrity → all checks pass).
    /// Input: whether all integrity checks passed.
    /// </summary>
    class function EvaluateGate4(AAllChecksPassed: Boolean): TGateVerdict; static;

    /// <summary>
    /// Convert a TGateVerdict into a TQualityGateResult for DB persistence.
    /// </summary>
    class function ToQualityGateResult(const AJobId: string;
      const AVerdict: TGateVerdict): TQualityGateResult; static;

    /// <summary>
    /// Determine the target job status after a gate evaluation.
    /// pass → done (if last step), warn → done (with warning recorded),
    /// fail → blocked_review.
    /// Returns the recommended status.
    /// </summary>
    class function TargetJobStatus(const AVerdict: TGateVerdict;
      AIsLastStep: Boolean): string; static;
  end;

implementation

uses
  System.SysUtils,
  DeepFrames.Shared.Consts;

{ TGateVerdict }

function TGateVerdict.IsPass: Boolean;
begin
  Result := SameText(GateResult, GATE_RESULT_PASS);
end;

function TGateVerdict.IsWarn: Boolean;
begin
  Result := SameText(GateResult, GATE_RESULT_WARN);
end;

function TGateVerdict.IsFail: Boolean;
begin
  Result := SameText(GateResult, GATE_RESULT_FAIL);
end;

{ TGateEvaluator }

class function TGateEvaluator.EvaluateGate1(ACoverageScore,
  ADistortionScore: Double): TGateVerdict;
begin
  Result.Gate := GATE_1;
  Result.Score := ACoverageScore;

  if (ACoverageScore >= 0.95) and (ADistortionScore <= 0.05) then
  begin
    Result.GateResult := GATE_RESULT_PASS;
    Result.Reason := Format('Coverage %.2f >= 0.95, distortion %.2f <= 0.05',
      [ACoverageScore, ADistortionScore]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else if (ACoverageScore >= 0.85) and (ADistortionScore <= 0.15) then
  begin
    Result.GateResult := GATE_RESULT_WARN;
    Result.Reason := Format('Coverage %.2f in [0.85, 0.95), distortion %.2f in (0.05, 0.15]',
      [ACoverageScore, ADistortionScore]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else
  begin
    Result.GateResult := GATE_RESULT_FAIL;
    Result.Reason := Format('Coverage %.2f < 0.85 or distortion %.2f > 0.15 — script fidelity insufficient',
      [ACoverageScore, ADistortionScore]);
    Result.ShouldBlock := True;
    Result.ShouldContinue := False;
  end;
end;

class function TGateEvaluator.EvaluateGate2(AScore: Double): TGateVerdict;
begin
  Result.Gate := GATE_2;
  Result.Score := AScore;

  if AScore >= 0.85 then
  begin
    Result.GateResult := GATE_RESULT_PASS;
    Result.Reason := Format('QA score %.2f >= 0.85', [AScore]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else if AScore >= 0.70 then
  begin
    Result.GateResult := GATE_RESULT_WARN;
    Result.Reason := Format('QA score %.2f in [0.70, 0.85) — production quality marginal', [AScore]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else
  begin
    Result.GateResult := GATE_RESULT_FAIL;
    Result.Reason := Format('QA score %.2f < 0.70 — shot quality insufficient, requires rework', [AScore]);
    Result.ShouldBlock := True;
    Result.ShouldContinue := False;
  end;
end;

class function TGateEvaluator.EvaluateGate3a(AMeasuredLufs, ATargetLufs,
  AConcatDeltaMs: Double): TGateVerdict;
var
  LufsDelta: Double;
begin
  Result.Gate := GATE_3A;
  LufsDelta := Abs(AMeasuredLufs - ATargetLufs);
  Result.Score := 1.0 - (LufsDelta / 5.0); // degrade score as lufs delta grows

  if (LufsDelta <= 1.0) and (Abs(AConcatDeltaMs) <= 200) then
  begin
    Result.GateResult := GATE_RESULT_PASS;
    Result.Reason := Format('LUFS delta %.1f <= 1.0, concat delta %.0f ms <= 200',
      [LufsDelta, AConcatDeltaMs]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else if (LufsDelta <= 2.0) and (Abs(AConcatDeltaMs) <= 500) then
  begin
    Result.GateResult := GATE_RESULT_WARN;
    Result.Reason := Format('LUFS delta %.1f in (1.0, 2.0], concat delta %.0f ms in (200, 500]',
      [LufsDelta, AConcatDeltaMs]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else
  begin
    Result.GateResult := GATE_RESULT_FAIL;
    Result.Reason := Format('LUFS delta %.1f > 2.0 or concat delta %.0f ms > 500 — audio quality failed',
      [LufsDelta, AConcatDeltaMs]);
    Result.ShouldBlock := True;
    Result.ShouldContinue := False;
  end;
end;

class function TGateEvaluator.EvaluateGate3b(AScore: Double): TGateVerdict;
begin
  Result.Gate := GATE_3B;
  Result.Score := AScore;

  if AScore >= 0.85 then
  begin
    Result.GateResult := GATE_RESULT_PASS;
    Result.Reason := Format('Visual QA score %.2f >= 0.85', [AScore]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else if AScore >= 0.70 then
  begin
    Result.GateResult := GATE_RESULT_WARN;
    Result.Reason := Format('Visual QA score %.2f in [0.70, 0.85) — visual quality marginal', [AScore]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else
  begin
    Result.GateResult := GATE_RESULT_FAIL;
    Result.Reason := Format('Visual QA score %.2f < 0.70 — visual quality insufficient', [AScore]);
    Result.ShouldBlock := True;
    Result.ShouldContinue := False;
  end;
end;

class function TGateEvaluator.EvaluateGate4(AAllChecksPassed: Boolean): TGateVerdict;
begin
  Result.Gate := GATE_4;
  Result.Score := 1.0;

  if AAllChecksPassed then
  begin
    Result.GateResult := GATE_RESULT_PASS;
    Result.Reason := 'All package integrity checks passed';
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else
  begin
    Result.GateResult := GATE_RESULT_FAIL;
    Result.Reason := 'Package integrity checks failed — manifest incomplete or asset references broken';
    Result.ShouldBlock := True;
    Result.ShouldContinue := False;
    Result.Score := 0.0;
  end;
end;

class function TGateEvaluator.ToQualityGateResult(const AJobId: string;
  const AVerdict: TGateVerdict): TQualityGateResult;
begin
  Result.ResultId := NewUuidString;
  Result.JobId := AJobId;
  Result.Gate := AVerdict.Gate;
  Result.GateResult := AVerdict.GateResult;
  Result.Score := AVerdict.Score;
  Result.HumanReviewStatus := 'auto_' + AVerdict.GateResult;
  Result.ReviewerNote := AVerdict.Reason;
end;

class function TGateEvaluator.TargetJobStatus(const AVerdict: TGateVerdict;
  AIsLastStep: Boolean): string;
begin
  if AVerdict.IsFail then
    Result := STATUS_BLOCKED_REVIEW
  else if AIsLastStep then
    Result := STATUS_DONE
  else
    Result := STATUS_RUNNING;
end;

end.