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
  System.IOUtils,
  System.JSON,
  System.Hash,
  System.NetEncoding,
  DeepBase.Crypto.AES,
  DeepBase.Crypto.Hash,
  DeepBase.Crypto.Encoding,
  FireDAC.Comp.Client,
  DeepFrames.Persistence.Repository,
  DeepFrames.Shared.Consts,
  DeepFrames.Shared.JsonSchema,
  DeepFrames.Workflow.GateEvaluator,
  DeepFrames.Workflow.BudgetGuard,
  DeepFrames.Workflow.StyleKeeper,
  DeepFrames.Domain.VoiceProfile,
  DeepFrames.Workflow.SubtitleEngine,
  DeepFrames.Workflow.SubtitleTransformEngine,
  DeepFrames.Workflow.SubtitleQcEngine,
  DeepFrames.Workflow.VideoTranscoder,
  DeepFrames.Workflow.NotificationChain,
  DeepFrames.Workflow.CookieCloudSync,
  DeepFrames.Workflow.ChunkedUploader,
  DeepFrames.Workflow.AssetRetention,
  DeepFrames.Workflow.WorkerProtocol,
  DeepFrames.Workflow.KeywordMatcher,
  DeepFrames.Workflow.VideoRenderEngine,
  DeepFrames.Workflow.AudioProcessor,
  DeepFrames.Workflow.YtDlpDownloader,
  DeepFrames.Workflow.ExternalVideoImportChain,
  DeepFrames.Workflow.ArtifactOSBridge,
  DeepFrames.Domain.Types,
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

// D8 (tasks.md): Gate 3b threshold + VLM-parse tests.
procedure TestGate3b_Pass;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3b(0.90);
  AssertTrue('Gate3b pass score 0.90', V.IsPass);
end;

procedure TestGate3b_Warn;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3b(0.75);
  AssertTrue('Gate3b warn score 0.75', V.IsWarn);
end;

procedure TestGate3b_Fail;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3b(0.50);
  AssertTrue('Gate3b fail score 0.50', V.IsFail);
end;

// D8: VLM unreachable must degrade to WARN (never a silent hardcoded PASS).
// red-line #8: yellow light recorded + continue.
procedure TestGate3bFromVLM_Unreachable_DegradesToWarn;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3bFromVLM('', False);
  AssertTrue('Gate3bFromVLM unreachable -> WARN', V.IsWarn);
  AssertTrue('Gate3bFromVLM unreachable -> degraded (score sentinel)',
    TGateEvaluator.IsDegraded(V));
end;

// D8: VLM reached but no parseable score must also degrade to WARN.
procedure TestGate3bFromVLM_Unparseable_DegradesToWarn;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3bFromVLM('The frames look fine to me.', True);
  AssertTrue('Gate3bFromVLM unparseable -> WARN', V.IsWarn);
  AssertTrue('Gate3bFromVLM unparseable -> degraded', TGateEvaluator.IsDegraded(V));
end;

// D8: VLM reached with a parseable 0-1 score delegates to the threshold logic.
procedure TestGate3bFromVLM_ParseableScore_DelegatesToThreshold;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3bFromVLM('Overall score: 0.92', True);
  AssertTrue('Gate3bFromVLM parseable 0.92 -> PASS', V.IsPass);
  AssertFalse('Gate3bFromVLM parseable 0.92 -> not degraded',
    TGateEvaluator.IsDegraded(V));
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

procedure TestSourceMeta_OriginalPass;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.CheckSourceMetadata('original_article', 'unknown', '');
  AssertTrue('original_article pass', V.IsPass);
end;

procedure TestSourceMeta_ExternalAuthorizedPass;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.CheckSourceMetadata('external_video', 'authorized',
    'https://youtube.com/watch?v=x');
  AssertTrue('external authorized pass', V.IsPass);
end;

procedure TestSourceMeta_UnknownLicenseWarn;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.CheckSourceMetadata('external_video', 'unknown',
    'https://youtube.com/watch?v=x');
  AssertTrue('unknown license warn (yellow)', V.IsWarn);
  AssertFalse('warn does not block', V.ShouldBlock);
end;

procedure TestSourceMeta_MissingUrlFail;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.CheckSourceMetadata('external_video', 'authorized', '');
  AssertTrue('missing origin_url fail', V.IsFail);
  AssertTrue('fail blocks', V.ShouldBlock);
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

procedure TestVoiceProfile_ChineseInstruction;
begin
  AssertTrue('VoiceProfile calm not empty', TVoiceProfile.EmotionToText(teCalm) <> '');
  AssertTrue('VoiceProfile tense not empty', TVoiceProfile.EmotionToText(teTense) <> '');
  AssertTrue('VoiceProfile slow pace not empty', TVoiceProfile.PaceToText(tpSlow) <> '');
  AssertTrue('VoiceProfile fast pace not empty', TVoiceProfile.PaceToText(tpFast) <> '');
  AssertTrue('VoiceProfile instruction not English',
    (Pos('calm', TVoiceProfile.BuildInstruction(teCalm, tpSlow, tpHNormal)) = 0) and
    (Pos('slow', TVoiceProfile.BuildInstruction(teCalm, tpSlow, tpHNormal)) = 0));
  AssertTrue('VoiceProfile instruction under 200 chars',
    Length(TVoiceProfile.BuildInstruction(teCalm, tpSlow, tpHNormal)) <= 30);
end;

procedure TestVoiceProfile_ToneToEmotion;
begin
  AssertEqualInt('Tone warm -> calm', Ord(teCalm), Ord(TVoiceProfile.ToneToEmotion('warm')));
  AssertEqualInt('Tone energetic -> happy', Ord(teHappy), Ord(TVoiceProfile.ToneToEmotion('energetic')));
  AssertEqualInt('Tone serious -> neutral', Ord(teNeutral), Ord(TVoiceProfile.ToneToEmotion('serious')));
  AssertEqualInt('Tone tense -> tense', Ord(teTense), Ord(TVoiceProfile.ToneToEmotion('tense')));
  AssertTrue('Tone calm has instruction', TVoiceProfile.BuildInstructionFromTone('calm') <> '');
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
// SubtitleTransformEngine Tests
// ============================================================================

procedure TestTransform_FillerWordsRemoved;
var
  Cues, Out: TArray<TSubtitleCue>;
  C: TSubtitleCue;
  Opt: TTransformOptions;
begin
  C := Default(TSubtitleCue);
  C.Index := 1;
  C.StartSec := 0;
  C.EndSec := 2.0;
  C.Text := '嗯那个我们今天来聊一下人工智能';
  SetLength(Cues, 1);
  Cues[0] := C;

  Opt := TTransformOptions.Default;
  Out := TSubtitleTransformEngine.Transform(Cues, Opt);
  AssertTrue('Filler 嗯/那个 removed', (Pos('嗯', Out[0].Text) = 0) and (Pos('那个', Out[0].Text) = 0));
  AssertTrue('Core text preserved', Pos('人工智能', Out[0].Text) > 0);
end;

procedure TestTransform_MinDurationPadded;
var
  Cues, Out: TArray<TSubtitleCue>;
  C: TSubtitleCue;
  Opt: TTransformOptions;
begin
  C := Default(TSubtitleCue);
  C.Index := 1;
  C.StartSec := 1.0;
  C.EndSec := 1.2; // 0.2s < 0.6s
  C.Text := '短';
  SetLength(Cues, 1);
  Cues[0] := C;

  Opt := TTransformOptions.Default;
  Out := TSubtitleTransformEngine.Transform(Cues, Opt);
  AssertTrue('Min duration padded to 0.6s', (Out[0].EndSec - Out[0].StartSec) >= 0.6);
end;

procedure TestTransform_GapMerge;
var
  Cues, Out: TArray<TSubtitleCue>;
  C1, C2: TSubtitleCue;
  Opt: TTransformOptions;
begin
  C1 := Default(TSubtitleCue);
  C1.Index := 1; C1.StartSec := 0; C1.EndSec := 1.0; C1.Text := '第一句';
  C2 := Default(TSubtitleCue);
  C2.Index := 2; C2.StartSec := 1.1; C2.EndSec := 2.0; C2.Text := '第二句'; // gap 0.1s < 0.3s
  SetLength(Cues, 2);
  Cues[0] := C1; Cues[1] := C2;

  Opt := TTransformOptions.Default;
  Out := TSubtitleTransformEngine.Transform(Cues, Opt);
  AssertTrue('Two close cues merged into one', Length(Out) = 1);
  AssertTrue('Merged text contains both', (Pos('第一句', Out[0].Text) > 0) and (Pos('第二句', Out[0].Text) > 0));
end;

procedure TestTransform_LongLineSplit;
var
  Cues, Out: TArray<TSubtitleCue>;
  C: TSubtitleCue;
  Opt: TTransformOptions;
begin
  C := Default(TSubtitleCue);
  C.Index := 1;
  C.StartSec := 0;
  C.EndSec := 3.0;
  // >42 chars → must split into <=2 lines (no punctuation → hard break)
  C.Text := '这是一条非常非常长的字幕文本用来验证变换引擎的长行自动拆分功能是否能够正常工作的测试用例数据';
  SetLength(Cues, 1);
  Cues[0] := C;

  Opt := TTransformOptions.Default;
  Out := TSubtitleTransformEngine.Transform(Cues, Opt);
  AssertTrue('Long line split into multiple lines', Pos(#10, Out[0].Text) > 0);
end;

// ============================================================================
// SubtitleQcEngine Tests
// ============================================================================

procedure TestQc_RuleBlockSignature;
var
  Cues: TArray<TSubtitleCue>;
  C: TSubtitleCue;
  R: TSubtitleQcResult;
begin
  C := Default(TSubtitleCue);
  C.Index := 1;
  C.StartSec := 0; C.EndSec := 2.0;
  C.Text := '记得点击订阅我的频道';
  SetLength(Cues, 1);
  Cues[0] := C;

  R := TSubtitleQcEngine.Check(Cues, nil, TQcOptions.Default);
  AssertFalse('Rule-blocked signature cue fails QC', R.Passed);
  AssertTrue('Failed cue recorded', Length(R.FailedCueIndexes) = 1);
end;

procedure TestQc_NilProviderPassesCleanCues;
var
  Cues: TArray<TSubtitleCue>;
  C: TSubtitleCue;
  R: TSubtitleQcResult;
begin
  // Clean cue with no rule violation; nil provider → rule-only, passes
  C := Default(TSubtitleCue);
  C.Index := 1;
  C.StartSec := 0; C.EndSec := 3.0;
  C.Text := '今天我们来聊聊人工智能的发展';
  SetLength(Cues, 1);
  Cues[0] := C;

  R := TSubtitleQcEngine.Check(Cues, nil, TQcOptions.Default);
  AssertTrue('Clean cue with nil provider passes', R.Passed);
  AssertFalse('AI not scored when provider nil', R.AiScored);
end;

procedure TestQc_EmptyCuesPass;
var
  Cues: TArray<TSubtitleCue>;
  R: TSubtitleQcResult;
begin
  SetLength(Cues, 0);
  R := TSubtitleQcEngine.Check(Cues, nil, TQcOptions.Default);
  AssertTrue('Empty cue track passes', R.Passed);
end;

// ============================================================================
// VideoTranscoder Tests
// ============================================================================

procedure TestTranscoder_MissingInput;
var
  R: TVTranscodeResult;
begin
  R := TVideoTranscoder.Transcode('Z:\nonexistent\in.mp4',
    'Z:\nonexistent\out.mp4', vemNvidia);
  AssertFalse('Transcode missing input returns False', R.Success);
  AssertTrue('Missing input reason set', Length(R.Reason) > 0);
end;

procedure TestTranscoder_EncoderMapping;
begin
  AssertEqual('CPU mode → libx264', 'libx264',
    TVideoTranscoder.EncoderForMode(vemCpu));
  AssertEqual('NVIDIA mode → hevc_nvenc', 'hevc_nvenc',
    TVideoTranscoder.EncoderForMode(vemNvidia));
  AssertEqual('Intel mode → hevc_qsv', 'hevc_qsv',
    TVideoTranscoder.EncoderForMode(vemIntel));
  AssertEqual('AMD mode → hevc_amf', 'hevc_amf',
    TVideoTranscoder.EncoderForMode(vemAmd));
  AssertEqual('AV1 mode → libsvtav1', 'libsvtav1',
    TVideoTranscoder.EncoderForMode(vemAv1));
  AssertEqual('VP9 mode → libvpx-vp9', 'libvpx-vp9',
    TVideoTranscoder.EncoderForMode(vemVp9));
end;

procedure TestTranscoder_ParseCodec_Standard;
// Canonical ffmpeg -i stderr line: "    Stream #0:0: Video: h264 (High), yuv420p(...)"
begin
  AssertEqual('standard h264 line', 'h264',
    TVideoTranscoder.ParseCodecFromOutput(
      '  Duration: 00:00:10.00, bitrate: 1234 kb/s' + sLineBreak +
      '    Stream #0:0: Video: h264 (High), yuv420p, 1920x1080 [SAR 1:1 DAR 16:9], 30 fps'));
end;

procedure TestTranscoder_ParseCodec_CaseInsensitiveLower;
// Some ffmpeg builds emit "video:" lower-case — old Pos('Video: ') missed it.
begin
  AssertEqual('lower-case video marker', 'hevc',
    TVideoTranscoder.ParseCodecFromOutput(
      '    Stream #0:0: video: hevc (Main 10), yuv420p10le'));
end;

procedure TestTranscoder_ParseCodec_MultiSpace;
// "Video:  h264" (double space) — old code Trim'd after the fixed offset and
// took '' as the codec. The skip-trailing-spaces path now handles this.
begin
  AssertEqual('multi-space after marker', 'h264',
    TVideoTranscoder.ParseCodecFromOutput(
      '    Stream #0:0: Video:  h264, yuv420p'));
end;

procedure TestTranscoder_ParseCodec_ParenProfile;
// Codec immediately followed by "(profile)" — stop at '(', not just space/comma.
begin
  AssertEqual('codec before paren profile', 'h264',
    TVideoTranscoder.ParseCodecFromOutput(
      '    Stream #0:0: Video: h264(High 10), yuv420p10le'));
end;

procedure TestTranscoder_ParseCodec_NoVideoLine;
// Audio-only or probe failure → '' (caller treats as inconclusive, not failed).
begin
  AssertEqual('no Video line → empty', '',
    TVideoTranscoder.ParseCodecFromOutput(
      '  Duration: 00:00:10.00' + sLineBreak +
      '    Stream #0:0: Audio: aac, 44100 Hz, stereo'));
end;

procedure TestTranscoder_ParseCodec_EmptyInput;
begin
  AssertEqual('empty input → empty', '',
    TVideoTranscoder.ParseCodecFromOutput(''));
end;

procedure TestTranscoder_PatentStatus;
begin
  AssertTrue('libx264 is patented',
    TVideoTranscoder.PatentStatusForEncoder('libx264') = vepPatented);
  AssertTrue('hevc_nvenc is patented',
    TVideoTranscoder.PatentStatusForEncoder('hevc_nvenc') = vepPatented);
  AssertTrue('libsvtav1 is royalty-free',
    TVideoTranscoder.PatentStatusForEncoder('libsvtav1') = vepRoyaltyFree);
  AssertTrue('libvpx-vp9 is royalty-free',
    TVideoTranscoder.PatentStatusForEncoder('libvpx-vp9') = vepRoyaltyFree);
  AssertTrue('libaom-av1 is royalty-free',
    TVideoTranscoder.PatentStatusForEncoder('libaom-av1') = vepRoyaltyFree);
end;

procedure TestTranscoder_IsRoyaltyFree;
begin
  AssertTrue('libsvtav1 royalty-free', TVideoTranscoder.IsRoyaltyFree('libsvtav1'));
  AssertTrue('libvpx-vp9 royalty-free', TVideoTranscoder.IsRoyaltyFree('libvpx-vp9'));
  AssertFalse('libx264 not royalty-free', TVideoTranscoder.IsRoyaltyFree('libx264'));
  AssertFalse('hevc_qsv not royalty-free', TVideoTranscoder.IsRoyaltyFree('hevc_qsv'));
end;

// ============================================================================
// NotificationChain Tests
// ============================================================================

procedure TestNotify_ChannelName;
begin
  AssertEqual('Wecom channel name', 'wecom',
    TNotificationChain.ChannelName(ncWecom));
  AssertEqual('Dingtalk channel name', 'dingtalk',
    TNotificationChain.ChannelName(ncDingtalk));
  AssertEqual('HTTP channel name', 'http',
    TNotificationChain.ChannelName(ncHttp));
end;

procedure TestNotify_BuildEnvelope;
var
  Env: TJSONObject;
  Ch, Title, Content: string;
begin
  Env := TNotificationChain.BuildEnvelope(ncWecom, 'render done', 'video ok');
  try
    Env.TryGetValue<string>('channel', Ch);
    Env.TryGetValue<string>('title', Title);
    Env.TryGetValue<string>('content', Content);
    AssertEqual('envelope channel', 'wecom', Ch);
    AssertEqual('envelope title', 'render done', Title);
    AssertEqual('envelope content', 'video ok', Content);
  finally
    Env.Free;
  end;
end;

procedure TestNotify_Deliver_EmptyUrl;
var
  Env: TJSONObject;
  R: TNotifyResult;
begin
  // No webhook URL → failure with reason, no network call (deterministic)
  Env := TNotificationChain.BuildEnvelope(ncHttp, 't', 'c');
  try
    R := TNotificationChain.Deliver(Env, '');
    AssertFalse('Deliver with empty URL fails', R.Success);
    AssertTrue('Deliver reason set', Length(R.Reason) > 0);
  finally
    Env.Free;
  end;
end;

// ============================================================================
// CookieCloudSync Tests
// ============================================================================

procedure TestCookieCloud_DecryptEmpty;
begin
  // Empty/invalid inputs → empty plaintext (no crash, no crypto)
  AssertEqual('Decrypt empty payload returns empty', '',
    TCookieCloudSync.DecryptPayload('', 'uuid', 'key', 'legacy'));
  AssertEqual('Decrypt empty key returns empty', '',
    TCookieCloudSync.DecryptPayload('data', 'uuid', '', 'legacy'));
  AssertEqual('Decrypt empty uuid returns empty', '',
    TCookieCloudSync.DecryptPayload('data', '', 'key', 'legacy'));
end;

procedure TestCookieCloud_DecryptLegacyRoundtrip;
// Real decrypt roundtrip: encrypt a known JSON with the CookieCloud legacy
// protocol (CryptoJS OpenSSL format) and verify DecryptPayload recovers it.
var
  Uuid, Pw, KeyHex, PlainJson: string;
  KeyB, Salt, CT, Prev, Derived, KeyIV, EncBlob: TBytes;
  AES: TAESCrypto;
  B64: string;
  I, Needed: Integer;
begin
  Uuid := 'test-uuid-1234';
  Pw := 'secret-password';
  PlainJson := '{"cookie_data":{".example.com":[{"name":"sid","value":"abc","domain":".example.com","path":"/","expires":0,"secure":"true","httponly":"false"}]}}';

  // key = MD5(uuid+'-'+pw) hexdigest[:16] as ASCII bytes
  KeyHex := THashUtils.MD5(Uuid + '-' + Pw).Substring(0, 16);
  KeyB := TEncoding.UTF8.GetBytes(KeyHex);

  // Build CryptoJS OpenSSL format: "Salted__" + salt(8) + ciphertext
  SetLength(Salt, 8);
  for I := 0 to 7 do Salt[I] := Byte(I + 1);
  // EVP_BytesToKey → 32-byte key + 16-byte IV
  KeyIV := nil;
  Prev := nil;
  while Length(KeyIV) < 48 do
  begin
    SetLength(Derived, Length(Prev) + Length(KeyB) + Length(Salt));
    if Length(Prev) > 0 then
      Move(Prev[0], Derived[0], Length(Prev));
    Move(KeyB[0], Derived[Length(Prev)], Length(KeyB));
    Move(Salt[0], Derived[Length(Prev) + Length(KeyB)], Length(Salt));
    Prev := THashUtils.MD5(Derived);
    Needed := 48 - Length(KeyIV);
    if Needed > Length(Prev) then
      Needed := Length(Prev);
    SetLength(KeyIV, Length(KeyIV) + Needed);
    Move(Prev[0], KeyIV[Length(KeyIV) - Needed], Needed);
  end;
  SetLength(Derived, 32);
  Move(KeyIV[0], Derived[0], 32);
  // encrypt with AES-256-CBC
  AES := TAESCrypto.Create(aes256, aesCBC);
  try
    AES.SetKey(Derived);
    AES.SetIV(Copy(KeyIV, 32, 16));
    CT := AES.Encrypt(TEncoding.UTF8.GetBytes(PlainJson));
  finally
    AES.Free;
  end;
  // assemble "Salted__"+salt+CT
  SetLength(EncBlob, 8 + 8 + Length(CT));
  EncBlob[0] := Ord('S'); EncBlob[1] := Ord('a'); EncBlob[2] := Ord('l');
  EncBlob[3] := Ord('t'); EncBlob[4] := Ord('e'); EncBlob[5] := Ord('d');
  EncBlob[6] := Ord('_'); EncBlob[7] := Ord('_');
  Move(Salt[0], EncBlob[8], 8);
  Move(CT[0], EncBlob[16], Length(CT));
  B64 := TEncodingUtils.Base64Encode(EncBlob);

  AssertEqual('legacy roundtrip recovers plaintext', PlainJson,
    TCookieCloudSync.DecryptPayload(B64, Uuid, Pw, 'legacy'));
end;

procedure TestCookieCloud_DecryptFixedIvRoundtrip;
// Real decrypt roundtrip for aes-128-cbc-fixed mode (zero IV, no Salted header).
var
  Uuid, Pw, KeyHex, PlainJson: string;
  KeyB, IV, CT: TBytes;
  AES: TAESCrypto;
  B64: string;
begin
  Uuid := 'fixed-uuid-abc';
  Pw := 'pw-xyz';
  PlainJson := '{"cookie_data":{}}';
  KeyHex := THashUtils.MD5(Uuid + '-' + Pw).Substring(0, 16);
  KeyB := TEncoding.UTF8.GetBytes(KeyHex);
  SetLength(IV, 16); // all-zero
  AES := TAESCrypto.Create(aes128, aesCBC);
  try
    AES.SetKey(KeyB);
    AES.SetIV(IV);
    CT := AES.Encrypt(TEncoding.UTF8.GetBytes(PlainJson));
  finally
    AES.Free;
  end;
  B64 := TEncodingUtils.Base64Encode(CT);
  AssertEqual('fixed-iv roundtrip recovers plaintext', PlainJson,
    TCookieCloudSync.DecryptPayload(B64, Uuid, Pw, 'aes-128-cbc-fixed'));
end;

procedure TestCookieCloud_NetscapeFormat;
var
  Cookies: TArray<TCookieEntry>;
  S: string;
begin
  SetLength(Cookies, 1);
  Cookies[0].Domain := '.example.com';
  Cookies[0].Path := '/';
  Cookies[0].Name := 'session';
  Cookies[0].Value := 'abc123';
  Cookies[0].Expires := 1700000000;
  Cookies[0].Secure := True;
  Cookies[0].HttpOnly := True;
  S := TCookieCloudSync.ToNetscapeFormat(Cookies);
  AssertTrue('Netscape has header', Pos('Netscape HTTP Cookie File', S) > 0);
  AssertTrue('Netscape has domain', Pos('.example.com', S) > 0);
  AssertTrue('Netscape has subdomain flag TRUE', Pos('.example.com'#9'TRUE', S) > 0);
  AssertTrue('Netscape has cookie name', Pos('session', S) > 0);
  AssertTrue('Netscape has secure flag', Pos('TRUE'#9'1700000000', S) > 0);
end;

// ============================================================================
// ChunkedUploader Tests
// ============================================================================

procedure TestUploader_MissingInput;
var
  R: TUploadResult;
begin
  R := TChunkedUploader.Upload('Z:\nonexistent\file.mp4', 'http://x/upload');
  AssertFalse('Upload missing input returns False', R.Success);
  AssertTrue('Missing input reason set', Length(R.Reason) > 0);
end;

procedure TestUploader_EmptyUrl;
var
  R: TUploadResult;
begin
  // No upload URL → immediate failure, no network
  R := TChunkedUploader.Upload('Z:\nonexistent\file.mp4', '');
  AssertFalse('Upload empty URL returns False', R.Success);
  AssertEqual('Empty URL reason', 'Upload URL empty', R.Reason);
end;

procedure TestUploader_PartialPath;
begin
  AssertEqual('Partial sidecar path', 'video.mp4.partial',
    TChunkedUploader.PartialPath('video.mp4'));
end;

procedure TestUploader_ProbeOffset_Empty;
begin
  // Empty URL / zero total → 0 (deterministic, no network)
  AssertEqualInt('Probe empty URL → 0', 0,
    TChunkedUploader.ProbeOffset('', 1000));
  AssertEqualInt('Probe zero total → 0', 0,
    TChunkedUploader.ProbeOffset('http://x', 0));
end;

// ============================================================================
// ContentUnit Info Tests
// ============================================================================

procedure TestContentUnit_DefaultSourceType;
var
  U: TContentUnitInfo;
begin
  U := Default(TContentUnitInfo);
  AssertEqual('ContentUnit default source_type empty before insert', '', U.SourceType);
  AssertEqual('ContentUnit default license_hint empty', '', U.LicenseHint);
end;

procedure TestContentUnit_FieldsSettable;
var
  U: TContentUnitInfo;
begin
  U := Default(TContentUnitInfo);
  U.SourceType := 'external_video';
  U.OriginUrl := 'https://example.com/v.mp4';
  U.LocalPath := '';
  U.LicenseHint := 'self';
  U.DownloadedAt := '2026-07-08T10:00:00Z';
  AssertEqual('ContentUnit source_type set', 'external_video', U.SourceType);
  AssertEqual('ContentUnit origin_url set', 'https://example.com/v.mp4', U.OriginUrl);
  AssertEqual('ContentUnit license_hint set', 'self', U.LicenseHint);
end;

procedure TestContentUnit_SourceGateIntegration;
// Verify the DocumentChain source-gate接入语义: a verdict's IsFail/ShouldBlock
// drives block-vs-continue exactly. This pins the接入 contract without a DB.
var
  V: TGateVerdict;
begin
  // original_article → pass → does NOT block (chain continues)
  V := TGateEvaluator.CheckSourceMetadata('original_article', 'unknown', '');
  AssertTrue('original pass', V.IsPass);
  AssertFalse('original not block', V.ShouldBlock);

  // external + unknown license → warn → records but does NOT block
  V := TGateEvaluator.CheckSourceMetadata('external_video', 'unknown',
    'https://youtube.com/watch?v=x');
  AssertTrue('unknown warn', V.IsWarn);
  AssertFalse('warn not block', V.ShouldBlock);

  // external + authorized + missing url → fail → blocks (chain exits)
  V := TGateEvaluator.CheckSourceMetadata('external_video', 'authorized', '');
  AssertTrue('missing-url fail', V.IsFail);
  AssertTrue('fail blocks', V.ShouldBlock);
end;

// ============================================================================
// AudioProcessor Tests
// ============================================================================

procedure TestExtractAudio_MissingInput;
var
  ErrMsg: string;
begin
  AssertFalse('ExtractAudio missing input returns False',
    TAudioProcessor.ExtractAudio('Z:\nonexistent\video.mp4',
      'Z:\nonexistent\out.wav', ErrMsg));
  AssertTrue('ExtractAudio reports error message', ErrMsg <> '');
end;

procedure TestVadSplit_MissingInput;
var
  Segs: TArray<TAudioSegment>;
begin
  AssertFalse('VadSplit missing input returns False',
    TAudioProcessor.VadSplit('Z:\nonexistent\audio.wav', Segs));
  AssertEqualInt('VadSplit no segments for missing file', 0, Length(Segs));
end;

procedure TestVadScan_MissingInput;
var
  Segs: TArray<TAudioSegment>;
begin
  // True VAD: missing file → False, no segments (same contract as VadSplit)
  AssertFalse('VadScan missing input returns False',
    TAudioProcessor.VadScan('Z:\nonexistent\audio.wav', Segs));
  AssertEqualInt('VadScan no segments for missing file', 0, Length(Segs));
end;

procedure TestVadScan_EmptyPath;
var
  Segs: TArray<TAudioSegment>;
begin
  AssertFalse('VadScan empty path returns False',
    TAudioProcessor.VadScan('', Segs));
  AssertEqualInt('VadScan no segments for empty path', 0, Length(Segs));
end;
// ============================================================================
// YtDlpDownloader Tests
// ============================================================================

procedure TestYtDlp_EmptyUrl;
var
  R: TDownloadResult;
begin
  AssertFalse('YtDlp empty URL returns False',
    TYtDlpDownloader.Download('', '', R));
  AssertTrue('YtDlp reports error for empty URL', R.ErrorMessage <> '');
end;

// ============================================================================
// ExternalVideoImportChain Tests
// ============================================================================

procedure TestImport_EmptyUrl;
var
  R: TImportResult;
begin
  AssertFalse('Import empty URL returns False',
    TExternalVideoImportChain.RunImport('proj-x', '', R));
  AssertTrue('Import reports error for empty URL', R.ErrorMessage <> '');
end;

// ============================================================================
// ArtifactOSBridge Tenant Isolation Tests
// ============================================================================

procedure TestArtifactOS_TenantIdDefault;
// Unset tenant → default tenant uuid (backward-compat for single-tenant).
begin
  TArtifactOSBridge.SetTenantId('');
  AssertEqual('unset tenant falls back to default',
    '00000000-0000-0000-0000-000000000001', TArtifactOSBridge.GetTenantId);
end;

procedure TestArtifactOS_TenantIdInjected;
// SetTenantId injects the active tenant; GetTenantId reads it back.
// This is the foundation of tenant isolation — every Poll/Claim/Get/Write
// query is scoped by this value (see bridge SQL: tenant_id = :tid::uuid).
var
  Saved, Got: string;
begin
  Saved := TArtifactOSBridge.GetTenantId;
  TArtifactOSBridge.SetTenantId('11111111-2222-3333-4444-555555555555');
  Got := TArtifactOSBridge.GetTenantId;
  // restore so other tests are not affected
  TArtifactOSBridge.SetTenantId(Saved);
  AssertEqual('injected tenant read back',
    '11111111-2222-3333-4444-555555555555', Got);
end;

procedure TestArtifactOS_NotConnectedSafe;
// No factory set → all ops return False safely (no crash, no DB).
var
  Reqs: TArray<TArtifactOSRequest>;
  Rid: string;
  Req: TArtifactOSRequest;
begin
  TArtifactOSBridge.Disconnect;
  AssertFalse('Poll not connected returns False',
    TArtifactOSBridge.PollRequests(Reqs));
  AssertFalse('Claim not connected returns False',
    TArtifactOSBridge.ClaimRequest('00000000-0000-0000-0000-000000000001'));
  AssertFalse('Get not connected returns False',
    TArtifactOSBridge.GetRequest('00000000-0000-0000-0000-000000000001', Req));
  AssertFalse('WriteResult not connected returns False',
    TArtifactOSBridge.WriteResult(Default(TArtifactOSResult), Rid));
end;

// ============================================================================
// Repository Transaction Boundary Tests (P0-A)
// ============================================================================

procedure TestRepo_TxSafeWhenNoTxn;
// Commit/Rollback with no active transaction are no-ops; InTransaction is
// False on a fresh (unconnected) connection. This is the guard that lets
// DocumentChain's except-path call RollbackTransaction without crashing when
// the failure happened before BeginTransaction.
var
  Conn: TFDConnection;
  Repo: TDeepFramesRepository;
begin
  Conn := TFDConnection.Create(nil);
  try
    Conn.DriverName := 'PG';  // configured but not opened
    Repo := TDeepFramesRepository.Create(Conn, False);
    try
      AssertFalse('fresh repo not in transaction', Repo.InTransaction);
      // these MUST be no-ops, not crashes:
      Repo.CommitTransaction;
      Repo.RollbackTransaction;
      AssertFalse('still not in transaction after no-op commit/rollback',
        Repo.InTransaction);
    finally
      Repo.Free;
    end;
  finally
    Conn.Free;
  end;
end;

// ============================================================================
// Resume Status Tests (P0-C)
// ============================================================================

procedure TestResume_TerminalStatuses;
// done/failed/cancelled/skipped/blocked_review are terminal → RunChain returns
// the existing job as-is (no re-run). This is what stops the silent-false-
// success bug: a half-finished job no longer looks "done" just because its
// logical key exists.
begin
  AssertTrue('done is terminal', IsTerminalStatus(STATUS_DONE));
  AssertTrue('failed is terminal', IsTerminalStatus(STATUS_FAILED));
  AssertTrue('cancelled is terminal', IsTerminalStatus(STATUS_CANCELLED));
  AssertTrue('skipped is terminal', IsTerminalStatus(STATUS_SKIPPED));
  AssertTrue('blocked_review is terminal', IsTerminalStatus(STATUS_BLOCKED_REVIEW));
  AssertFalse('pending not terminal', IsTerminalStatus(STATUS_PENDING));
  AssertFalse('running not terminal', IsTerminalStatus(STATUS_RUNNING));
end;

procedure TestResume_ResumableStatuses;
// pending/running are resumable → RunChain adopts the existing JobId and
// falls through to re-run the chain (idempotent steps skip themselves).
begin
  AssertTrue('pending resumable', IsResumableStatus(STATUS_PENDING));
  AssertTrue('running resumable', IsResumableStatus(STATUS_RUNNING));
  AssertFalse('done not resumable', IsResumableStatus(STATUS_DONE));
  AssertFalse('blocked_review not resumable', IsResumableStatus(STATUS_BLOCKED_REVIEW));
end;

// ============================================================================
// Budget Guard Tests (P0-G)
// ============================================================================

procedure TestBudget_AccumulateAndCheck;
// Accumulate two LLM calls; totals and per-capability counters advance;
// ceiling not crossed → CheckBudget does not raise.
var
  M: TProviderRunMetrics;
  U: TBudgetUsage;
begin
  TBudgetGuard.Configure(100000, 60);
  TBudgetGuard.Reset('job-budget-1');

  M := Default(TProviderRunMetrics);
  M.Capability := 'llm';
  M.TokenUsage.PromptTokens := 1000;
  M.TokenUsage.CompletionTokens := 500;
  M.TokenUsage.TotalTokens := 1500;
  TBudgetGuard.Accumulate('job-budget-1', M);

  M.TokenUsage.TotalTokens := 2000;
  TBudgetGuard.Accumulate('job-budget-1', M);

  U := TBudgetGuard.GetUsage('job-budget-1');
  AssertEqualInt('two llm calls accumulated', 2, U.CallCount);
  AssertEqualInt('llm counter is 2', 2, U.LlmCalls);
  AssertEqualInt('total tokens summed', 3500, U.TotalTokens);

  // under ceiling → no raise
  TBudgetGuard.CheckBudget('job-budget-1');
  AssertFalse('not over budget', TBudgetGuard.IsOverBudget('job-budget-1'));
end;

procedure TestBudget_TokenCeilingRaises;
// Crossing the token ceiling raises EBudgetExceeded — this is the guard that
// stops a runaway chain from burning provider budget.
var
  M: TProviderRunMetrics;
  Raised: Boolean;
begin
  TBudgetGuard.Configure(5000, 60);  // low token ceiling
  TBudgetGuard.Reset('job-budget-2');

  M := Default(TProviderRunMetrics);
  M.Capability := 'llm';
  M.TokenUsage.TotalTokens := 6000;  // over 5000
  TBudgetGuard.Accumulate('job-budget-2', M);

  AssertTrue('over budget after exceed', TBudgetGuard.IsOverBudget('job-budget-2'));
  Raised := False;
  try
    TBudgetGuard.CheckBudget('job-budget-2');
  except
    on EBudgetExceeded do
      Raised := True;
  end;
  AssertTrue('CheckBudget raised EBudgetExceeded', Raised);
end;

procedure TestBudget_CallCeilingRaises;
// Crossing the call-count ceiling (>= max) raises — catches image regen
// storms even when each call is cheap on tokens.
var
  M: TProviderRunMetrics;
  U: TBudgetUsage;
  I: Integer;
  Raised: Boolean;
begin
  TBudgetGuard.Configure(1000000, 3);  // high token, low call ceiling
  TBudgetGuard.Reset('job-budget-3');

  M := Default(TProviderRunMetrics);
  M.Capability := 'image';
  M.TokenUsage.TotalTokens := 100;
  for I := 1 to 3 do
    TBudgetGuard.Accumulate('job-budget-3', M);

  U := TBudgetGuard.GetUsage('job-budget-3');
  AssertEqualInt('image counter is 3', 3, U.ImageCalls);

  Raised := False;
  try
    TBudgetGuard.CheckBudget('job-budget-3');
  except
    on EBudgetExceeded do
      Raised := True;
  end;
  AssertTrue('call ceiling raised EBudgetExceeded', Raised);
end;

procedure TestBudget_ResetClearsUsage;
// Reset wipes prior spend — a resumed job doesn't inherit a stale over-budget
// flag from a previous run.
var
  M: TProviderRunMetrics;
  U: TBudgetUsage;
begin
  TBudgetGuard.Configure(100, 1);
  TBudgetGuard.Reset('job-budget-4');
  M := Default(TProviderRunMetrics);
  M.Capability := 'llm';
  M.TokenUsage.TotalTokens := 500;
  TBudgetGuard.Accumulate('job-budget-4', M);
  AssertTrue('over budget before reset', TBudgetGuard.IsOverBudget('job-budget-4'));

  TBudgetGuard.Reset('job-budget-4');
  U := TBudgetGuard.GetUsage('job-budget-4');
  AssertEqualInt('tokens cleared after reset', 0, U.TotalTokens);
  AssertFalse('not over budget after reset', TBudgetGuard.IsOverBudget('job-budget-4'));
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
// KeywordMatcher Tests
// ============================================================================

procedure TestKeywordMatcher_ChineseSplitWords;
var
  Words: TArray<TAsrWordTimestamp>;
  MR: TKeywordMatchResult;
  HL: string;
  W: TAsrWordTimestamp;
begin
  // Simulate ASR returning "机器" + "器人" + "在" + "办公" + "室" + "工作"
  SetLength(Words, 6);
  W.Word := '机器'; W.StartSec := 0.0; W.EndSec := 0.4; W.Confidence := 0.95; Words[0] := W;
  W.Word := '器人'; W.StartSec := 0.4; W.EndSec := 0.8; W.Confidence := 0.95; Words[1] := W;
  W.Word := '在';   W.StartSec := 0.8; W.EndSec := 1.0; W.Confidence := 0.90; Words[2] := W;
  W.Word := '办公'; W.StartSec := 1.0; W.EndSec := 1.3; W.Confidence := 0.92; Words[3] := W;
  W.Word := '室';   W.StartSec := 1.3; W.EndSec := 1.5; W.Confidence := 0.85; Words[4] := W;
  W.Word := '工作'; W.StartSec := 1.5; W.EndSec := 2.0; W.Confidence := 0.95; Words[5] := W;

  // "机器人" should NOT match across "机器"+"器人" (splits to "机器器人" ≠ "机器人")
  // This is a known limitation of the Pos-based matcher; fallback is expected
  HL := TKeywordMatcher.MatchKeywords('机器人', Words, 10.0, MR);
  AssertTrue('Chinese compound: fallback used for split word', MR.FallbackUsed);
  // Fallback gives full-duration display
  AssertTrue('Chinese compound: fallback interval covers 0.0-10.0',
    Pos('机器人|0.0', HL) > 0);

  // "办公室" should match across words[3] and words[4] (1.0-1.5)
  HL := TKeywordMatcher.MatchKeywords('办公室', Words, 10.0, MR);
  AssertTrue('Chinese partial: fallback not used for office', not MR.FallbackUsed);
  AssertTrue('Chinese partial: interval covers 1.0-1.5',
    Pos('1.0', HL) > 0);
end;

procedure TestKeywordMatcher_FallbackForUnmatched;
var
  Words: TArray<TAsrWordTimestamp>;
  MR: TKeywordMatchResult;
  HL: string;
  W: TAsrWordTimestamp;
begin
  SetLength(Words, 2);
  W.Word := '你好'; W.StartSec := 0.0; W.EndSec := 1.0; W.Confidence := 0.9; Words[0] := W;
  W.Word := '世界'; W.StartSec := 1.0; W.EndSec := 2.0; W.Confidence := 0.9; Words[1] := W;

  // "AI" does not exist in Chinese ASR -> fallback
  HL := TKeywordMatcher.MatchKeywords('AI', Words, 10.0, MR);
  AssertTrue('Fallback: used for unmatched keyword', MR.FallbackUsed);
  AssertEqualInt('Fallback: 1 unmatched', 1, Length(MR.UnmatchedKeywords));
  AssertTrue('Fallback: unmatched is AI', MR.UnmatchedKeywords[0] = 'AI');
  AssertTrue('Fallback: interval covers full duration',
    Pos('AI|0.0', HL) > 0);
  AssertTrue('Fallback: end at 10.0',
    Pos('|10.000', HL) > 0);
end;

procedure TestKeywordMatcher_EnglishPhrase;
var
  Words: TArray<TAsrWordTimestamp>;
  MR: TKeywordMatchResult;
  HL: string;
  W: TAsrWordTimestamp;
begin
  SetLength(Words, 5);
  W.Word := 'artificial'; W.StartSec := 0.0; W.EndSec := 0.5; W.Confidence := 0.95; Words[0] := W;
  W.Word := ' ';          W.StartSec := 0.5; W.EndSec := 0.6; W.Confidence := 0.50; Words[1] := W;
  W.Word := 'intelligence'; W.StartSec := 0.6; W.EndSec := 1.2; W.Confidence := 0.92; Words[2] := W;
  W.Word := ' and ';       W.StartSec := 1.2; W.EndSec := 1.5; W.Confidence := 0.60; Words[3] := W;
  W.Word := 'future';      W.StartSec := 1.5; W.EndSec := 2.0; W.Confidence := 0.95; Words[4] := W;

  // "artificial intelligence" as a phrase
  HL := TKeywordMatcher.MatchKeywords('artificial intelligence', Words, 10.0, MR);
  AssertTrue('English phrase: fallback not used', not MR.FallbackUsed);
  AssertTrue('English phrase: interval covers 0.0-1.2',
    Pos('artificial intelligence|0.0', HL) > 0);

  // "future" should match words[4]
  HL := TKeywordMatcher.MatchKeywords('future', Words, 10.0, MR);
  AssertTrue('English word: fallback not used', not MR.FallbackUsed);
  AssertTrue('English word: interval near 1.5-2.0',
    Pos('1.5', HL) > 0);
end;

procedure TestKeywordMatcher_EmptyInput;
var
  Words: TArray<TAsrWordTimestamp>;
  MR: TKeywordMatchResult;
  HL: string;
begin
  SetLength(Words, 0);
  HL := TKeywordMatcher.MatchKeywords('', Words, 10.0, MR);
  AssertTrue('Empty keywords returns empty', HL = '');
  AssertTrue('Empty keywords no fallback', not MR.FallbackUsed);
end;

procedure TestBuildKeywordPopup_FadeAlpha;
var
  Filter: string;
begin
  // Single keyword with fade
  Filter := TVideoRenderEngine.BuildKeywordPopup('AI|2.5|4.0', '10.0', 0.3, 0.3);
  AssertTrue('Fade: alpha expression present', Pos('alpha=', Filter) > 0);
  AssertTrue('Fade: fade-in logic present', Pos('(t-2.5', Filter) > 0);
  AssertTrue('Fade: fade-out logic present', Pos('4.000-t)', Filter) > 0);
  AssertTrue('Fade: enable between', Pos('between(t,2.5', Filter) > 0);

  // No fade (zero duration)
  Filter := TVideoRenderEngine.BuildKeywordPopup('AI|0|10', '10.0', 0, 0);
  AssertTrue('No fade: alpha still present', Pos('alpha=', Filter) > 0);
  AssertTrue('No fade: drawtext present', Pos('drawtext', Filter) > 0);

  // Empty input
  Filter := TVideoRenderEngine.BuildKeywordPopup('', '10.0');
  AssertTrue('Empty: returns empty', Filter = '');
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

procedure TestWorker_WriteProgressRoundtrip;
// P0-B: WriteProgress writes progress.json (heartbeat); ReadProgress recovers
// it. This is the worker→host heartbeat contract — without WriteProgress the
// host's heartbeat_timeout check is dead code (no file ever appears).
var
  Dir, SavedDir: string;
  P, R: TWorkerProgress;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'df_wptest_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    P := Default(TWorkerProgress);
    P.TaskId := 'task-hb-1';
    P.Status := 'running';
    P.ProgressPercent := 42;
    P.Message := 'rendering segment 3/8';
    TWorkerProtocol.WriteProgress(Dir, P);

    AssertTrue('progress.json written by WriteProgress',
      FileExists(TPath.Combine(Dir, 'progress.json')));
    R := TWorkerProtocol.ReadProgress(Dir);
    AssertEqual('heartbeat roundtrip task_id', P.TaskId, R.TaskId);
    AssertEqual('heartbeat roundtrip status', P.Status, R.Status);
    AssertEqualInt('heartbeat roundtrip progress_pct', P.ProgressPercent, R.ProgressPercent);
    AssertEqual('heartbeat roundtrip message', P.Message, R.Message);
  finally
    SavedDir := Dir;
    TDirectory.Delete(SavedDir, True);
  end;
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
  TestGate3b_Pass;
  TestGate3b_Warn;
  TestGate3b_Fail;
  TestGate3bFromVLM_Unreachable_DegradesToWarn;
  TestGate3bFromVLM_Unparseable_DegradesToWarn;
  TestGate3bFromVLM_ParseableScore_DelegatesToThreshold;
  TestGate4_Pass;
  TestGate4_Fail;
  TestSourceMeta_OriginalPass;
  TestSourceMeta_ExternalAuthorizedPass;
  TestSourceMeta_UnknownLicenseWarn;
  TestSourceMeta_MissingUrlFail;

  WriteLn('=== VoiceProfile Tests ===');
  TestVoiceProfile_DefaultProfiles;
  TestVoiceProfile_FindByCharacter;
  TestVoiceProfile_BuildInstruction;
  TestVoiceProfile_InstructionUnder200;
  TestVoiceProfile_ChineseInstruction;
  TestVoiceProfile_ToneToEmotion;

  WriteLn('=== SubtitleEngine Tests ===');
  TestSubtitle_SplitLines;
  TestSubtitle_BilibiliSafeZone;
  TestSubtitle_DouyinSafeZone;
  TestSubtitle_SRTFormatting;
  TestSubtitle_VTTFormatting;

  WriteLn('=== SubtitleTransformEngine Tests ===');
  TestTransform_FillerWordsRemoved;
  TestTransform_MinDurationPadded;
  TestTransform_GapMerge;
  TestTransform_LongLineSplit;

  WriteLn('=== SubtitleQcEngine Tests ===');
  TestQc_RuleBlockSignature;
  TestQc_NilProviderPassesCleanCues;
  TestQc_EmptyCuesPass;

  WriteLn('=== VideoTranscoder Tests ===');
  TestTranscoder_MissingInput;
  TestTranscoder_EncoderMapping;
  TestTranscoder_ParseCodec_Standard;
  TestTranscoder_ParseCodec_CaseInsensitiveLower;
  TestTranscoder_ParseCodec_MultiSpace;
  TestTranscoder_ParseCodec_ParenProfile;
  TestTranscoder_ParseCodec_NoVideoLine;
  TestTranscoder_ParseCodec_EmptyInput;
  TestTranscoder_PatentStatus;
  TestTranscoder_IsRoyaltyFree;

  WriteLn('=== NotificationChain Tests ===');
  TestNotify_ChannelName;
  TestNotify_BuildEnvelope;
  TestNotify_Deliver_EmptyUrl;

  WriteLn('=== CookieCloudSync Tests ===');
  TestCookieCloud_DecryptEmpty;
  TestCookieCloud_DecryptLegacyRoundtrip;
  TestCookieCloud_DecryptFixedIvRoundtrip;
  TestCookieCloud_NetscapeFormat;

  WriteLn('=== ChunkedUploader Tests ===');
  TestUploader_MissingInput;
  TestUploader_EmptyUrl;
  TestUploader_PartialPath;
  TestUploader_ProbeOffset_Empty;

  WriteLn('=== ContentUnit Info Tests ===');
  TestContentUnit_DefaultSourceType;
  TestContentUnit_FieldsSettable;
  TestContentUnit_SourceGateIntegration;

  WriteLn('=== AudioProcessor Tests ===');
  TestExtractAudio_MissingInput;
  TestVadSplit_MissingInput;
  TestVadScan_MissingInput;
  TestVadScan_EmptyPath;

  WriteLn('=== YtDlpDownloader Tests ===');
  TestYtDlp_EmptyUrl;

  WriteLn('=== ExternalVideoImportChain Tests ===');
  TestImport_EmptyUrl;

  WriteLn('=== ArtifactOSBridge Tenant Isolation Tests ===');
  TestArtifactOS_TenantIdDefault;
  TestArtifactOS_TenantIdInjected;
  TestArtifactOS_NotConnectedSafe;

  WriteLn('=== Repository Transaction Boundary Tests ===');
  TestRepo_TxSafeWhenNoTxn;

  WriteLn('=== Resume Status Tests ===');
  TestResume_TerminalStatuses;
  TestResume_ResumableStatuses;

  WriteLn('=== Budget Guard Tests ===');
  TestBudget_AccumulateAndCheck;
  TestBudget_TokenCeilingRaises;
  TestBudget_CallCeilingRaises;
  TestBudget_ResetClearsUsage;

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
  TestWorker_WriteProgressRoundtrip;

  WriteLn('=== KeywordMatcher Tests ===');
  TestKeywordMatcher_ChineseSplitWords;
  TestKeywordMatcher_FallbackForUnmatched;
  TestKeywordMatcher_EnglishPhrase;
  TestKeywordMatcher_EmptyInput;

  WriteLn('=== BuildKeywordPopup Tests ===');
  TestBuildKeywordPopup_FadeAlpha;

  WriteLn('');
  WriteLn(Format('=== %d tests, %d failed, %d passed ===',
    [GTestCount, GFailCount, GTestCount - GFailCount]));
  if GFailCount > 0 then
    Halt(1);
end;

initialization
  RunAllTests;
end.