unit DeepFrames.Workflow.GateEvaluator;

/// <summary>
/// Quality gate evaluator for DeepFrames production pipeline.
///
/// Evaluates Gate 1-4 results based on score thresholds and returns
/// pass/warn/fail decisions. Warn is a yellow light -- record and continue.
/// Fail is a red light -- set blocked_review and stop.
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

const
  /// <summary>D8: sentinel score returned by EvaluateGate3bFromVLM when the
  /// VLM could not be called, returned no parseable score, or frame extraction
  /// failed. A degraded gate is WARN (yellow light, record + continue) per
  /// red-line #8 — never silently fall back to a hardcoded PASS. Callers MUST
  /// check IsDegraded to flag the warn as "unverified" in the reason.</summary>
  GATE3B_DEGRADED_SCORE = -1.0;

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

    /// <summary>D8 (tasks.md): parse a Gate 3b score from VLM free-text and
    /// delegate to EvaluateGate3b. AVlmText is the raw vision-LLM response to
    /// a "rate 0.0-1.0 how well these frames match the visual prompt" probe.
    /// Returns a degraded WARN verdict (Score=GATE3B_DEGRADED_SCORE) when the
    /// VLM could not be reached or no score could be parsed — callers then
    /// surface this as "visual gate unverified" per red-line #8 (yellow light,
    /// never a silent hardcoded pass).</summary>
    class function EvaluateGate3bFromVLM(const AVlmText: string;
      AProviderReached: Boolean): TGateVerdict; static;

    /// <summary>D8: a verdict is degraded when its score equals the sentinel
    /// (VLM unreachable / unparseable). Use to distinguish a real WARN
    /// (marginal-but-scored) from a degraded WARN (unverified).</summary>
    class function IsDegraded(const AVerdict: TGateVerdict): Boolean; static;

    /// <summary>
    /// Evaluate Gate 4 (package integrity → all checks pass).
    /// Input: whether all integrity checks passed.
    /// </summary>
    class function EvaluateGate4(AAllChecksPassed: Boolean): TGateVerdict; static;

    /// <summary>
    /// Source-metadata compliance check for external_video_import (黄灯子检查).
    /// Inputs: source_type, license_hint from content_unit.
    ///   - source_type in (external_video|external_audio|local_file) +
    ///     license_hint in (self|authorized)        → pass
    ///   - license_hint = unknown                    → warn (record, continue)
    ///   - missing source_type or origin_url         → fail (block: 合规证据缺失)
    /// </summary>
    class function CheckSourceMetadata(const ASourceType, ALicenseHint,
      AOriginUrl: string): TGateVerdict; static;

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
  System.Math,
  System.RegularExpressions,
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
    Result.Reason := Format('Coverage %.2f < 0.85 or distortion %.2f > 0.15 -- script fidelity insufficient',
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
    Result.Reason := Format('QA score %.2f in [0.70, 0.85) -- production quality marginal', [AScore]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else
  begin
    Result.GateResult := GATE_RESULT_FAIL;
    Result.Reason := Format('QA score %.2f < 0.70 -- shot quality insufficient, requires rework', [AScore]);
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
    Result.Reason := Format('LUFS delta %.1f > 2.0 or concat delta %.0f ms > 500 -- audio quality failed',
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
    Result.Reason := Format('Visual QA score %.2f in [0.70, 0.85) -- visual quality marginal', [AScore]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else
  begin
    Result.GateResult := GATE_RESULT_FAIL;
    Result.Reason := Format('Visual QA score %.2f < 0.70 -- visual quality insufficient', [AScore]);
    Result.ShouldBlock := True;
    Result.ShouldContinue := False;
  end;
end;

class function TGateEvaluator.EvaluateGate3bFromVLM(const AVlmText: string;
  AProviderReached: Boolean): TGateVerdict;
var
  M: TMatch;
  Raw: string;
  Score: Double;
begin
  // D8: degrade to WARN (not silent PASS) when the VLM was unreachable or no
  // score could be parsed from its free-text response. red-line #8: a yellow
  // light is recorded and the pipeline continues, but it is flagged as
  // unverified so a future real run can close the loop.
  if not AProviderReached then
  begin
    Result.Gate := GATE_3B;
    Result.Score := GATE3B_DEGRADED_SCORE;
    Result.GateResult := GATE_RESULT_WARN;
    Result.Reason := 'VLM provider unreachable -- visual gate UNVERIFIED (degraded WARN, red-line #8)';
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
    Exit;
  end;

  // VLM reached: extract the first 0.0-1.0 float from the response. We accept
  // either a bare number ("0.82") or a "score: 0.82"-style phrase. Reject
  // anything outside [0,1] as unparseable (the prompt asks for a 0.0-1.0 rating).
  M := TRegEx.Match(AVlmText, '(?i)(?:score)?[:\s]*([01](?:\.\d+)?|0?\.\d+)');
  if M.Success then
  begin
    Raw := M.Groups[1].Value;
    if TryStrToFloat(Raw, Score) and (Score >= 0.0) and (Score <= 1.0) then
      Exit(EvaluateGate3b(Score));  // delegate to threshold logic
  end;

  // Provider reached but no parseable score -> degraded WARN.
  Result.Gate := GATE_3B;
  Result.Score := GATE3B_DEGRADED_SCORE;
  Result.GateResult := GATE_RESULT_WARN;
  Result.Reason := 'VLM response unparseable (no 0.0-1.0 score found) -- visual gate UNVERIFIED (degraded WARN, red-line #8)';
  Result.ShouldBlock := False;
  Result.ShouldContinue := True;
end;

class function TGateEvaluator.IsDegraded(const AVerdict: TGateVerdict): Boolean;
begin
  Result := SameText(AVerdict.Gate, GATE_3B) and
            SameValue(AVerdict.Score, GATE3B_DEGRADED_SCORE);
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
    Result.Reason := 'Package integrity checks failed -- manifest incomplete or asset references broken';
    Result.ShouldBlock := True;
    Result.ShouldContinue := False;
    Result.Score := 0.0;
  end;
end;

class function TGateEvaluator.CheckSourceMetadata(const ASourceType,
  ALicenseHint, AOriginUrl: string): TGateVerdict;
var
  IsExternal: Boolean;
  LicenseOk: Boolean;
begin
  Result.Gate := GATE_SOURCE;
  Result.Score := 1.0;
  Result.Reason := '';

  // 缺失来源类型或来源 URL → 合规证据缺失，红灯拦截
  if (Trim(ASourceType) = '') or
     ((ASourceType <> 'original_article') and (Trim(AOriginUrl) = '')) then
  begin
    Result.GateResult := GATE_RESULT_FAIL;
    Result.Reason := 'source_type or origin_url missing -- compliance evidence incomplete';
    Result.ShouldBlock := True;
    Result.ShouldContinue := False;
    Result.Score := 0.0;
    Exit;
  end;

  // 原创线无需许可证检查
  if ASourceType = 'original_article' then
  begin
    Result.GateResult := GATE_RESULT_PASS;
    Result.Reason := 'original_article -- no license check needed';
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
    Exit;
  end;

  // 外部来源: 检查 license_hint
  IsExternal := (ASourceType = 'external_video') or
                (ASourceType = 'external_audio') or
                (ASourceType = 'local_file');
  LicenseOk := (ALicenseHint = 'self') or (ALicenseHint = 'authorized');

  if IsExternal and LicenseOk then
  begin
    Result.GateResult := GATE_RESULT_PASS;
    Result.Reason := Format('source_type=%s license_hint=%s -- authorized',
      [ASourceType, ALicenseHint]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
  end
  else if IsExternal and (ALicenseHint = 'unknown') then
  begin
    // 黄灯: 许可证未确认，记录但继续流水线
    Result.GateResult := GATE_RESULT_WARN;
    Result.Reason := Format('source_type=%s license_hint=unknown -- license unverified, manual review recommended',
      [ASourceType]);
    Result.ShouldBlock := False;
    Result.ShouldContinue := True;
    Result.Score := 0.5;
  end
  else
  begin
    // 未知 source_type 或非法 license_hint
    Result.GateResult := GATE_RESULT_FAIL;
    Result.Reason := Format('source_type=%s license_hint=%s -- invalid combination',
      [ASourceType, ALicenseHint]);
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
  Result.HumanReviewStatus := 'auto_passed';
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