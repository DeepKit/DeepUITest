unit DeepFrames.Tests.Core;

/// <summary>
/// Core unit tests for DeepFrames modules.
/// Tests pure-logic units that don't require DB2 or external services:
///   - JsonSchema validation + auto-repair
///   - GateEvaluator thresholds
///   - StyleKeeper deterministic engine
///   - VoiceProfile enum mappings
///   - SubtitleEngine safe zones + SRT formatting
///   - AssetRetention classification
///   - WorkerProtocol serialization
///
/// Run via DUnitX or compile_test.bat with -DTEST flag.
/// </summary>

interface

implementation

uses
  System.SysUtils,
  System.JSON,
  DeepFrames.Shared.Consts,
  DeepFrames.Shared.JsonSchema,
  DeepFrames.Workflow.GateEvaluator,
  DeepFrames.Workflow.StyleKeeper,
  DeepFrames.Domain.VoiceProfile,
  DeepFrames.Workflow.SubtitleEngine,
  DeepFrames.Workflow.AssetRetention,
  DeepFrames.Workflow.WorkerProtocol,
  DeepFrames.Provider.Types;

// ============================================================================
// Test runner utility
// ============================================================================

var
  GTestCount: Integer;
  GFailCount: Integer;

procedure AssertTrue(const AMessage: string; ACondition: Boolean);
begin
  Inc(GTestCount);
  if not ACondition then
  begin
    Inc(GFailCount);
    WriteLn('FAIL: ' + AMessage);
  end
  else
    WriteLn('OK:   ' + AMessage);
end;

procedure AssertFalse(const AMessage: string; ACondition: Boolean);
begin
  AssertTrue(AMessage, not ACondition);
end;

procedure AssertEqual(const AMessage: string; const AExpected, AActual: string);
begin
  Inc(GTestCount);
  if AExpected <> AActual then
  begin
    Inc(GFailCount);
    WriteLn('FAIL: ' + AMessage + Format(' expected="%s" actual="%s"', [AExpected, AActual]));
  end
  else
    WriteLn('OK:   ' + AMessage);
end;

procedure AssertEqualInt(const AMessage: string; AExpected, AActual: Integer);
begin
  Inc(GTestCount);
  if AExpected <> AActual then
  begin
    Inc(GFailCount);
    WriteLn('FAIL: ' + AMessage + Format(' expected=%d actual=%d', [AExpected, AActual]));
  end
  else
    WriteLn('OK:   ' + AMessage);
end;

// ============================================================================
// JsonSchema Tests
// ============================================================================

procedure TestSchema_ValidDocument;
const
  Schema = '{"type":"object","required":["name","score"],"properties":{"name":{"type":"string"},"score":{"type":"number"}}}';
  Doc    = '{"name":"test","score":0.95}';
begin
  AssertTrue('Schema valid doc passes', TJsonSchemaValidator.IsValid(Schema, Doc));
end;

procedure TestSchema_MissingRequiredField;
const
  Schema = '{"type":"object","required":["name","score"],"properties":{"name":{"type":"string"},"score":{"type":"number"}}}';
  Doc    = '{"name":"test"}';
var
  V: TSchemaValidationResult;
begin
  V := TJsonSchemaValidator.Validate(Schema, Doc, False);
  AssertTrue('Schema missing required field fails without repair', not V.IsValid);
  AssertEqualInt('Schema 1 error', 1, V.ErrorCount);
end;

procedure TestSchema_AutoRepair;
const
  Schema = '{"type":"object","required":["name","score"],"properties":{"name":{"type":"string"},"score":{"type":"number"}}}';
  Doc    = '{"name":"test"}';
var
  V: TSchemaValidationResult;
begin
  V := TJsonSchemaValidator.Validate(Schema, Doc, True);
  AssertTrue('Schema auto-repair succeeds', V.IsValid);
  AssertEqualInt('Schema auto-repair count', 1, V.RepairCount);
end;

procedure TestSchema_TypeCoercion;
const
  Schema = '{"type":"object","properties":{"count":{"type":"number"}}}';
  Doc    = '{"count":"42"}';
var
  V: TSchemaValidationResult;
begin
  V := TJsonSchemaValidator.Validate(Schema, Doc, True);
  AssertTrue('Schema string->number coercion passes', V.IsValid);
end;

procedure TestSchema_EnumValidation;
const
  Schema = '{"type":"object","required":["gate_result"],"properties":{"gate_result":{"type":"string","enum":["pass","warn","fail"]}}}';
  Doc    = '{"gate_result":"unknown"}';
var
  V: TSchemaValidationResult;
begin
  V := TJsonSchemaValidator.Validate(Schema, Doc, False);
  AssertTrue('Schema enum violation detected', not V.IsValid);
end;

procedure TestSchema_NestedObject;
const
  Schema = '{"type":"object","required":["audio"],"properties":{"audio":{"type":"object","required":["text"],"properties":{"text":{"type":"string"}}}}}';
  Doc    = '{"audio":{"text":"hello"}}';
begin
  AssertTrue('Schema nested object valid', TJsonSchemaValidator.IsValid(Schema, Doc));
end;

// ============================================================================
// GateEvaluator Tests
// ============================================================================

procedure TestGate1_Pass;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate1(0.97, 0.03);
  AssertTrue('Gate1 pass score=0.97', V.IsPass);
  AssertTrue('Gate1 pass should continue', V.ShouldContinue);
  AssertFalse('Gate1 pass should not block', V.ShouldBlock);
end;

procedure TestGate1_Warn;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate1(0.90, 0.10);
  AssertTrue('Gate1 warn score=0.90', V.IsWarn);
  AssertTrue('Gate1 warn should continue', V.ShouldContinue);
  AssertFalse('Gate1 warn should not block', V.ShouldBlock);
end;

procedure TestGate1_Fail;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate1(0.80, 0.05);
  AssertTrue('Gate1 fail coverage<0.85', V.IsFail);
  AssertTrue('Gate1 fail should block', V.ShouldBlock);
  AssertFalse('Gate1 fail should not continue', V.ShouldContinue);
end;

procedure TestGate2_Pass;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate2(0.90);
  AssertTrue('Gate2 pass score=0.90', V.IsPass);
end;

procedure TestGate2_Warn;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate2(0.75);
  AssertTrue('Gate2 warn score=0.75', V.IsWarn);
end;

procedure TestGate2_Fail;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate2(0.60);
  AssertTrue('Gate2 fail score=0.60', V.IsFail);
end;

procedure TestGate3a_Pass;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3a(-16.0, -16.0, 50);
  AssertTrue('Gate3a pass LUFS on target, delta 50ms', V.IsPass);
end;

procedure TestGate3a_Warn;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3a(-14.5, -16.0, 300);
  AssertTrue('Gate3a warn LUFS delta=1.5, delta=300ms', V.IsWarn);
end;

procedure TestGate3a_Fail;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3a(-13.0, -16.0, 600);
  AssertTrue('Gate3a fail LUFS delta=3.0, delta=600ms', V.IsFail);
end;

procedure TestGate4_Pass;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate4(True);
  AssertTrue('Gate4 pass all checks', V.IsPass);
end;

procedure TestGate4_Fail;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate4(False);
  AssertTrue('Gate4 fail', V.IsFail);
end;

// ============================================================================
// StyleKeeper Tests
// ============================================================================

procedure TestStyleKeeper_DefaultResult;
var
  R: TStyleKeeperResult;
begin
  R := TStyleKeeper.DefaultResult;
  AssertTrue('StyleKeeper default style_consistent', R.StyleConsistent);
  AssertEqualInt('StyleKeeper default warnings=0', 0, Length(R.Warnings));
end;

// ============================================================================
// VoiceProfile Tests
// ============================================================================

procedure TestVoiceProfile_DefaultProfiles;
var
  P: TArray<TVoiceConfig>;
begin
  P := TVoiceProfile.DefaultProfiles;
  AssertEqualInt('VoiceProfile 4 defaults', 4, Length(P));
  AssertTrue('VoiceProfile narrator exists', SameText(P[0].CharacterName, 'Narrator'));
end;

procedure TestVoiceProfile_FindByCharacter;
var
  P: TArray<TVoiceConfig>;
  C: TVoiceConfig;
begin
  P := TVoiceProfile.DefaultProfiles;
  AssertTrue('VoiceProfile find by name', TVoiceProfile.FindByCharacter('Narrator', P, C));
  AssertTrue('VoiceProfile found voice ID', C.VoiceId = 'cixingnansheng');
end;

procedure TestVoiceProfile_BuildInstruction;
begin
  AssertTrue('VoiceProfile instruction length ok',
    TVoiceProfile.IsInstructionValid(TVoiceProfile.BuildInstruction(teCalm, tpSlow, tpHNormal)));
end;

procedure TestVoiceProfile_InstructionUnder200;
var
  S: string;
begin
  S := TVoiceProfile.BuildInstruction(teCalm, tpSlow, tpHNormal);
  AssertTrue('VoiceProfile instruction < 200 chars', Length(S) <= 200);
end;

// ============================================================================
// SubtitleEngine Tests
// ============================================================================

procedure TestSubtitle_SplitLines;
var
  Lines: TArray<string>;
begin
  // Chinese text: "This is a test subtitle for the DeepFrames video generation pipeline validation"
  Lines := TSubtitleEngine.SplitLines('这是一条测试字幕，用于 DeepFrames 视频生成流水线验证', 20);
  AssertTrue('Subtitle split produces lines', Length(Lines) >= 1);
  AssertTrue('Subtitle max 2 lines', Length(Lines) <= 2);
end;

procedure TestSubtitle_BilibiliSafeZone;
var
  Z: TSafeZone;
begin
  Z := TSubtitleEngine.BilibiliSafeZone;
  AssertEqualInt('Bilibili safe zone width', 1920, Z.CanvasWidth);
  AssertEqualInt('Bilibili safe zone height', 1080, Z.CanvasHeight);
  AssertEqualInt('Bilibili font size', 36, Z.FontSizePt);
end;

procedure TestSubtitle_DouyinSafeZone;
var
  Z: TSafeZone;
begin
  Z := TSubtitleEngine.DouyinSafeZone;
  AssertEqualInt('Douyin safe zone width', 1080, Z.CanvasWidth);
  AssertEqualInt('Douyin safe zone height', 1920, Z.CanvasHeight);
  AssertTrue('Douyin vertical', Z.CanvasHeight > Z.CanvasWidth);
end;

procedure TestSubtitle_SRTFormatting;
var
  Cues: TArray<TSubtitleCue>;
  Srt: string;
begin
  SetLength(Cues, 2);
  Cues[0].Index := 1;
  Cues[0].StartSec := 0.0;
  Cues[0].EndSec := 3.5;
  Cues[0].Text := '第一行字幕';
  Cues[0].IsSafe := True;

  Cues[1].Index := 2;
  Cues[1].StartSec := 3.5;
  Cues[1].EndSec := 7.0;
  Cues[1].Text := '第二行字幕';
  Cues[1].IsSafe := True;

  Srt := TSubtitleEngine.ToSRT(Cues);
  AssertTrue('SRT contains index 1', Pos('1', Srt) > 0);
  AssertTrue('SRT contains index 2', Pos('2', Srt) > 0);
  AssertTrue('SRT contains timestamp', Pos('00:00:00', Srt) > 0);
end;

procedure TestSubtitle_VTTFormatting;
var
  Cues: TArray<TSubtitleCue>;
  Vtt: string;
begin
  SetLength(Cues, 1);
  Cues[0].Index := 1;
  Cues[0].StartSec := 0.0;
  Cues[0].EndSec := 3.0;
  Cues[0].Text := 'Test';
  Cues[0].IsSafe := True;

  Vtt := TSubtitleEngine.ToVTT(Cues);
  AssertTrue('VTT starts with WEBVTT', Pos('WEBVTT', Vtt) = 1);
end;

// ============================================================================
// AssetRetention Tests
// ============================================================================

procedure TestRetention_C1Forever;
begin
  AssertEqualInt('Retention C1 forever', 0, TAssetRetention.RetentionDays(RETENTION_CLASS_C1));
end;

procedure TestRetention_C2ThirtyDays;
begin
  AssertEqualInt('Retention C2 30 days', 30, TAssetRetention.RetentionDays(RETENTION_CLASS_C2));
end;

procedure TestRetention_C3SevenDays;
begin
  AssertEqualInt('Retention C3 7 days', 7, TAssetRetention.RetentionDays(RETENTION_CLASS_C3));
end;

procedure TestRetention_C4Immediate;
begin
  AssertEqualInt('Retention C4 immediate', 0, TAssetRetention.RetentionDays(RETENTION_CLASS_C4));
end;

procedure TestRetention_ClassifyAsset;
begin
  AssertTrue('Classify manifest as C1',
    TAssetRetention.ClassifyAsset('manifest', '', False) = RETENTION_CLASS_C1);
  AssertTrue('Classify final video as C2',
    TAssetRetention.ClassifyAsset('video', ASSET_CATEGORY_FINAL, False) = RETENTION_CLASS_C2);
  AssertTrue('Classify snapshot as C3',
    TAssetRetention.ClassifyAsset('image', ASSET_CATEGORY_SNAPSHOT, False) = RETENTION_CLASS_C3);
  AssertTrue('Classify failed asset as C4',
    TAssetRetention.ClassifyAsset('video', ASSET_CATEGORY_FINAL, True) = RETENTION_CLASS_C4);
end;

// ============================================================================
// WorkerProtocol Tests
// ============================================================================

procedure TestWorker_TaskTypeStrings;
begin
  AssertTrue('TaskType render->string',
    SameText(TWorkerProtocol.TaskTypeToString(wtRender), 'render'));
  AssertTrue('TaskType ffmpeg->string',
    SameText(TWorkerProtocol.TaskTypeToString(wtFFmpeg), 'ffmpeg'));
end;

// ============================================================================
// Main
// ============================================================================

procedure RunAllTests;
begin
  GTestCount := 0;
  GFailCount := 0;

  WriteLn('=== JsonSchema Tests ===');
  TestSchema_ValidDocument;
  TestSchema_MissingRequiredField;
  TestSchema_AutoRepair;
  TestSchema_TypeCoercion;
  TestSchema_EnumValidation;
  TestSchema_NestedObject;

  WriteLn('=== GateEvaluator Tests ===');
  TestGate1_Pass;
  TestGate1_Warn;
  TestGate1_Fail;
  TestGate2_Pass;
  TestGate2_Warn;
  TestGate2_Fail;
  TestGate3a_Pass;
  TestGate3a_Warn;
  TestGate3a_Fail;
  TestGate4_Pass;
  TestGate4_Fail;

  WriteLn('=== VoiceProfile Tests ===');
  TestVoiceProfile_DefaultProfiles;
  TestVoiceProfile_FindByCharacter;
  TestVoiceProfile_BuildInstruction;
  TestVoiceProfile_InstructionUnder200;

  WriteLn('=== SubtitleEngine Tests ===');
  TestSubtitle_SplitLines;
  TestSubtitle_BilibiliSafeZone;
  TestSubtitle_DouyinSafeZone;
  TestSubtitle_SRTFormatting;
  TestSubtitle_VTTFormatting;

  WriteLn('=== AssetRetention Tests ===');
  TestRetention_C1Forever;
  TestRetention_C2ThirtyDays;
  TestRetention_C3SevenDays;
  TestRetention_C4Immediate;
  TestRetention_ClassifyAsset;

  WriteLn('=== StyleKeeper Tests ===');
  TestStyleKeeper_DefaultResult;

  WriteLn('=== WorkerProtocol Tests ===');
  TestWorker_TaskTypeStrings;

  WriteLn('');
  WriteLn(Format('=== %d tests, %d failed, %d passed ===',
    [GTestCount, GFailCount, GTestCount - GFailCount]));
  if GFailCount > 0 then
    Halt(1);
end;

initialization
  RunAllTests;
end.