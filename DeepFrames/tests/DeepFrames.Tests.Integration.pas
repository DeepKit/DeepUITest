unit DeepFrames.Tests.Integration;

/// <summary>
/// Integration tests for DeepFrames module combinations.
/// Tests cover provider+schema+gate chains, gate status transitions,
/// WorkerProtocol JSON round-trips, error paths, and logging instrumentation.
///
/// Reuses AssertTrue/AssertEqual/AssertEqualInt pattern from Tests.Core.
/// </summary>

interface

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  DeepFrames.Shared.Consts,
  DeepFrames.Shared.JsonSchema,
  DeepFrames.Domain.Types,
  DeepFrames.Provider.Types,
  DeepFrames.Provider.Intf,
  DeepFrames.Provider.Registry,
  DeepFrames.Provider.Fake,
  DeepFrames.Workflow.GateEvaluator,
  DeepFrames.Workflow.WorkerProtocol,
  DeepFrames.Workflow.EventLog,
  DeepFrames.Workflow.PromptVersion,
  DeepFrames.Workflow.StyleKeeper,
  DeepFrames.Workflow.SubtitleEngine;

// ============================================================================
// Test runner utility (mirrors Tests.Core pattern)
// ============================================================================

var
  GITestCount: Integer;
  GIFailCount: Integer;

procedure IAssertTrue(const AMessage: string; ACondition: Boolean);
begin
  Inc(GITestCount);
  if not ACondition then
  begin
    Inc(GIFailCount);
    WriteLn('FAIL: ' + AMessage);
  end
  else
    WriteLn('OK:   ' + AMessage);
end;

procedure IAssertFalse(const AMessage: string; ACondition: Boolean);
begin
  IAssertTrue(AMessage, not ACondition);
end;

procedure IAssertEqual(const AMessage: string; const AExpected, AActual: string);
begin
  Inc(GITestCount);
  if AExpected <> AActual then
  begin
    Inc(GIFailCount);
    WriteLn(Format('FAIL: %s expected="%s" actual="%s"', [AMessage, AExpected, AActual]));
  end
  else
    WriteLn('OK:   ' + AMessage);
end;

procedure IAssertEqualInt(const AMessage: string; AExpected, AActual: Integer);
begin
  Inc(GITestCount);
  if AExpected <> AActual then
  begin
    Inc(GIFailCount);
    WriteLn(Format('FAIL: %s expected=%d actual=%d', [AMessage, AExpected, AActual]));
  end
  else
    WriteLn('OK:   ' + AMessage);
end;

procedure IAssertEqualDbl(const AMessage: string; AExpected, AActual: Double;
  AEpsilon: Double = 0.0001);
begin
  Inc(GITestCount);
  if Abs(AExpected - AActual) > AEpsilon then
  begin
    Inc(GIFailCount);
    WriteLn(Format('FAIL: %s expected=%g actual=%g', [AMessage, AExpected, AActual]));
  end
  else
    WriteLn('OK:   ' + AMessage);
end;

// ============================================================================
// I1: Provider + JsonSchema + Gate combination
// ============================================================================

procedure TestI1_FakeLLM_Splitter_SchemaValid;
const
  // Schema matches the actual Fake splitter output shape
  Schema = '{"type":"object","required":["shots"],"properties":{"shots":{"type":"array"}}}';
var
  Registry: TProviderRegistry;
  Req: TChatCompletionRequest;
  Res: TChatCompletionResult;
  Metrics: TProviderRunMetrics;
  Ok: Boolean;
begin
  Registry := TProviderRegistry.Instance;
  Registry.SwitchTo(PROVIDER_FAKE);
  Req := Default(TChatCompletionRequest);
  Req.AgentRole := AGENT_ROLE_SPLITTER;
  Req.SystemPrompt := 'You split text';
  Req.UserMessage := 'Split this';
  Req.OutputSchemaJson := Schema;
  Req.Temperature := 0.7;
  Req.MaxTokens := 4096;
  Ok := Registry.LLMProvider.ChatComplete(Req, Res, Metrics);
  IAssertTrue('I1 Fake LLM splitter succeeds', Ok);
  IAssertTrue('I1 Fake LLM splitter returns JSON', Length(Res.ResponseJson) > 0);
  IAssertTrue('I1 Fake LLM splitter JSON schema-valid',
    TJsonSchemaValidator.IsValid(Schema, Res.ResponseJson));
  IAssertEqualInt('I1 Fake LLM splitter repair count = 0', 0, Res.RepairCount);
end;

procedure TestI1_FakeLLM_QA_Gate2Pass;
const
  Schema = '{"type":"object","required":["score","decision"],"properties":{"score":{"type":"number"},"decision":{"type":"string"}}}';
var
  Registry: TProviderRegistry;
  Req: TChatCompletionRequest;
  Res: TChatCompletionResult;
  Metrics: TProviderRunMetrics;
  Json: TJSONObject;
  Score: Double;
  V: TGateVerdict;
begin
  Registry := TProviderRegistry.Instance;
  Registry.SwitchTo(PROVIDER_FAKE);
  Req := Default(TChatCompletionRequest);
  Req.AgentRole := AGENT_ROLE_QA;
  Req.SystemPrompt := 'QA';
  Req.UserMessage := 'Check quality';
  Req.OutputSchemaJson := Schema;
  Req.Temperature := 0.3;
  Req.MaxTokens := 2048;
  Registry.LLMProvider.ChatComplete(Req, Res, Metrics);
  IAssertTrue('I1 QA returns JSON', Length(Res.ResponseJson) > 0);
  Json := TJSONObject.ParseJSONValue(Res.ResponseJson) as TJSONObject;
  try
    if Json <> nil then
    begin
      Score := Json.GetValue<Double>('score', 0.0);
      V := TGateEvaluator.EvaluateGate2(Score);
      IAssertTrue('I1 QA Gate2 passes with fake high score', V.IsPass);
    end
    else
      IAssertTrue('I1 QA JSON parsed', False);
  finally
    Json.Free;
  end;
end;

procedure TestI1_FakeLLM_AllRoles_ProduceJson;
const
  Roles: array [0..4] of string = (
    AGENT_ROLE_SPLITTER, AGENT_ROLE_WORKER, AGENT_ROLE_ASSEMBLER,
    AGENT_ROLE_QA, AGENT_ROLE_STYLE_KEEPER);
var
  Registry: TProviderRegistry;
  Req: TChatCompletionRequest;
  Res: TChatCompletionResult;
  Metrics: TProviderRunMetrics;
  I: Integer;
begin
  Registry := TProviderRegistry.Instance;
  Registry.SwitchTo(PROVIDER_FAKE);
  Req := Default(TChatCompletionRequest);
  Req.SystemPrompt := 'sys';
  Req.UserMessage := 'usr';
  Req.Temperature := 0.5;
  Req.MaxTokens := 2048;
  for I := Low(Roles) to High(Roles) do
  begin
    Req.AgentRole := Roles[I];
    Registry.LLMProvider.ChatComplete(Req, Res, Metrics);
    IAssertTrue('I1 role ' + Roles[I] + ' produces JSON',
      Length(Res.ResponseJson) > 0);
  end;
end;

procedure TestI1_FakeTTS_Synthesize;
var
  Registry: TProviderRegistry;
  Res: TTtsSynthesisResult;
  Metrics: TProviderRunMetrics;
begin
  Registry := TProviderRegistry.Instance;
  Registry.SwitchTo(PROVIDER_FAKE);
  IAssertTrue('I1 Fake TTS synthesizes',
    Registry.TTSProvider.Synthesize('测试语音', 'narrator', '', 'wav', Res, Metrics));
  IAssertEqualInt('I1 Fake TTS sample rate 24000', 24000, Res.SampleRate);
  IAssertTrue('I1 Fake TTS char count > 0', Res.CharCount > 0);
  IAssertTrue('I1 Fake TTS duration > 0', Res.DurationSec > 0);
end;

procedure TestI1_FakeASR_Transcribe;
var
  Registry: TProviderRegistry;
  Res: TAsrTranscriptionResult;
  Metrics: TProviderRunMetrics;
begin
  Registry := TProviderRegistry.Instance;
  Registry.SwitchTo(PROVIDER_FAKE);
  IAssertTrue('I1 Fake ASR transcribes',
    Registry.ASRProvider.Transcribe('fake://audio.wav', Res, Metrics));
  IAssertTrue('I1 Fake ASR returns words', Length(Res.Words) > 0);
  IAssertTrue('I1 Fake ASR word start >= 0', Res.Words[0].StartSec >= 0);
  IAssertTrue('I1 Fake ASR confidence > 0.9', Res.Words[0].Confidence > 0.9);
end;

procedure TestI1_FakeImage_Generate;
var
  Registry: TProviderRegistry;
  Req: TImageGenRequest;
  Results: TArray<TImageGenResult>;
  Metrics: TProviderRunMetrics;
begin
  Registry := TProviderRegistry.Instance;
  Registry.SwitchTo(PROVIDER_FAKE);
  Req := Default(TImageGenRequest);
  Req.Prompt := 'a sunset';
  Req.Width := 512;
  Req.Height := 512;
  Req.NumImages := 3;
  IAssertTrue('I1 Fake image generate succeeds',
    Registry.ImageProvider.Generate(Req, Results, Metrics));
  IAssertEqualInt('I1 Fake image count = 3', 3, Length(Results));
end;

procedure TestI1_ProviderRegistry_SwitchFake;
var
  Registry: TProviderRegistry;
begin
  Registry := TProviderRegistry.Instance;
  Registry.SwitchTo(PROVIDER_FAKE);
  IAssertEqual('I1 Registry LLM name = fake', PROVIDER_FAKE, Registry.LLMProvider.GetProviderName);
  IAssertEqual('I1 Registry TTS name = fake', PROVIDER_FAKE, Registry.TTSProvider.GetProviderName);
  IAssertEqual('I1 Registry ASR name = fake', PROVIDER_FAKE, Registry.ASRProvider.GetProviderName);
  IAssertEqual('I1 Registry Image name = fake', PROVIDER_FAKE, Registry.ImageProvider.GetProviderName);
end;

procedure TestI1_ProviderRegistry_SwitchStepFun_Degrades;
var
  Registry: TProviderRegistry;
  Req: TChatCompletionRequest;
  Res: TChatCompletionResult;
  Metrics: TProviderRunMetrics;
begin
  Registry := TProviderRegistry.Instance;
  Registry.SwitchTo(PROVIDER_STEPFUN);
  IAssertEqual('I1 Registry stepfun LLM name', PROVIDER_STEPFUN, Registry.LLMProvider.GetProviderName);
  // StepFun without key should degrade to stub and still succeed
  Req := Default(TChatCompletionRequest);
  Req.AgentRole := AGENT_ROLE_SPLITTER;
  Req.SystemPrompt := 'sys';
  Req.UserMessage := 'usr';
  Req.Temperature := 0.5;
  Req.MaxTokens := 1024;
  IAssertTrue('I1 StepFun degrades to stub on no-key',
    Registry.LLMProvider.ChatComplete(Req, Res, Metrics));
  // Switch back to fake for subsequent tests
  Registry.SwitchTo(PROVIDER_FAKE);
end;

// ============================================================================
// I2: Gate full path tests
// ============================================================================

procedure TestI2_Gate1_Boundary_Coverage_Exact_085;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate1(0.85, 0.10);
  IAssertTrue('I2 Gate1 boundary coverage=0.85 is warn', V.IsWarn);
end;

procedure TestI2_Gate1_Boundary_Distortion_Exact_015;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate1(0.90, 0.15);
  IAssertTrue('I2 Gate1 boundary distortion=0.15 is warn', V.IsWarn);
end;

procedure TestI2_Gate2_Boundary_Exact_070;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate2(0.70);
  IAssertTrue('I2 Gate2 boundary score=0.70 is warn', V.IsWarn);
end;

procedure TestI2_Gate2_Boundary_Exact_085;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate2(0.85);
  IAssertTrue('I2 Gate2 boundary score=0.85 is pass', V.IsPass);
end;

procedure TestI2_Gate3a_LufsOk_ConcatFail;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3a(-16.0, -16.0, 600);
  IAssertTrue('I2 Gate3a LUFS ok but concat 600ms fails', V.IsFail);
end;

procedure TestI2_Gate3a_LufsFail_ConcatOk;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3a(-13.0, -16.0, 50);
  IAssertTrue('I2 Gate3a LUFS delta 3 fails even with concat ok', V.IsFail);
end;

procedure TestI2_Gate4_Fail_ScoreZero;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate4(False);
  IAssertTrue('I2 Gate4 fail', V.IsFail);
  IAssertEqualDbl('I2 Gate4 fail score = 0.0', 0.0, V.Score);
end;

procedure TestI2_TargetJobStatus_Gate1Fail_Blocked;
var
  V: TGateVerdict;
  Status: string;
begin
  V := TGateEvaluator.EvaluateGate1(0.50, 0.30);
  Status := TGateEvaluator.TargetJobStatus(V, False);
  IAssertEqual('I2 Gate1 fail -> blocked_review', STATUS_BLOCKED_REVIEW, Status);
end;

procedure TestI2_TargetJobStatus_Gate2Pass_Continue;
var
  V: TGateVerdict;
  Status: string;
begin
  V := TGateEvaluator.EvaluateGate2(0.95);
  Status := TGateEvaluator.TargetJobStatus(V, False);
  IAssertEqual('I2 Gate2 pass not-last -> running', STATUS_RUNNING, Status);
end;

procedure TestI2_TargetJobStatus_GateLastStep_Done;
var
  V: TGateVerdict;
  Status: string;
begin
  V := TGateEvaluator.EvaluateGate2(0.95);
  Status := TGateEvaluator.TargetJobStatus(V, True);
  IAssertEqual('I2 Gate2 pass last-step -> done', STATUS_DONE, Status);
end;

procedure TestI2_QualityGateResult_RoundTrip;
var
  V: TGateVerdict;
  QGR: TQualityGateResult;
begin
  V := TGateEvaluator.EvaluateGate2(0.90);
  QGR := TGateEvaluator.ToQualityGateResult('job-123', V);
  IAssertEqual('I2 QGR job id', 'job-123', QGR.JobId);
  IAssertEqual('I2 QGR gate = gate2', GATE_2, QGR.Gate);
  IAssertEqualDbl('I2 QGR score = 0.90', 0.90, QGR.Score);
end;

procedure TestI2_Gate3b_Boundary_070;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3b(0.70);
  IAssertTrue('I2 Gate3b boundary 0.70 is warn', V.IsWarn);
end;

procedure TestI2_Gate3b_Boundary_085;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate3b(0.85);
  IAssertTrue('I2 Gate3b boundary 0.85 is pass', V.IsPass);
end;

// ============================================================================
// I3: WorkerProtocol JSON round-trip + lifecycle
// ============================================================================

procedure TestI3_TaskTypeToString_All;
begin
  IAssertEqual('I3 TaskType render', 'render', TWorkerProtocol.TaskTypeToString(wtRender));
  IAssertEqual('I3 TaskType tts', 'tts', TWorkerProtocol.TaskTypeToString(wtTTS));
  IAssertEqual('I3 TaskType image_gen', 'image_gen', TWorkerProtocol.TaskTypeToString(wtImageGen));
  IAssertEqual('I3 TaskType subtitle', 'subtitle', TWorkerProtocol.TaskTypeToString(wtSubtitle));
  IAssertEqual('I3 TaskType ffmpeg', 'ffmpeg', TWorkerProtocol.TaskTypeToString(wtFFmpeg));
  IAssertEqual('I3 TaskType custom', 'custom', TWorkerProtocol.TaskTypeToString(wtCustom));
end;

procedure TestI3_StringToTaskType_RoundTrip;
begin
  IAssertTrue('I3 String->render', TWorkerProtocol.StringToTaskType('render') = wtRender);
  IAssertTrue('I3 String->tts', TWorkerProtocol.StringToTaskType('tts') = wtTTS);
  IAssertTrue('I3 String->image_gen', TWorkerProtocol.StringToTaskType('image_gen') = wtImageGen);
  IAssertTrue('I3 String->unknown -> custom', TWorkerProtocol.StringToTaskType('xxx') = wtCustom);
end;

procedure TestI3_RequestToJson_RoundTrip;
var
  Req, Parsed: TWorkerRequest;
  Json: string;
begin
  Req := Default(TWorkerRequest);
  Req.TaskId := 'task-001';
  Req.TaskType := 'render';
  Req.InputManifest := 'C:\input.json';
  Req.OutputDir := 'C:\output';
  Req.Params := '{"key":"value"}';
  Req.HeartbeatIntervalMs := 5000;
  Json := TWorkerProtocol.RequestToJson(Req);
  IAssertTrue('I3 Request JSON non-empty', Length(Json) > 0);
  // Parse back via JSON
  Parsed := Default(TWorkerRequest);
  with TJSONObject.ParseJSONValue(Json) as TJSONObject do
  try
    Parsed.TaskId := GetValue<string>('task_id');
    Parsed.TaskType := GetValue<string>('task_type');
    Parsed.HeartbeatIntervalMs := GetValue<Integer>('heartbeat_interval_ms');
  finally
    Free;
  end;
  IAssertEqual('I3 Request task_id round-trip', 'task-001', Parsed.TaskId);
  IAssertEqual('I3 Request task_type round-trip', 'render', Parsed.TaskType);
  IAssertEqualInt('I3 Request heartbeat round-trip', 5000, Parsed.HeartbeatIntervalMs);
end;

procedure TestI3_ProgressToJson_RoundTrip;
var
  Prog: TWorkerProgress;
  Json: string;
  Parsed: TWorkerProgress;
begin
  Prog := Default(TWorkerProgress);
  Prog.TaskId := 'task-002';
  Prog.Status := 'running';
  Prog.ProgressPercent := 50;
  Prog.CurrentStep := 'rendering';
  Prog.Message := 'halfway done';
  Prog.UpdatedAt := '2026-06-05T10:00:00Z';
  Json := TWorkerProtocol.ProgressToJson(Prog);
  Parsed := TWorkerProtocol.JsonToProgress(Json);
  IAssertEqual('I3 Progress task_id', 'task-002', Parsed.TaskId);
  IAssertEqual('I3 Progress status', 'running', Parsed.Status);
  IAssertEqualInt('I3 Progress percent = 50', 50, Parsed.ProgressPercent);
  IAssertEqual('I3 Progress step', 'rendering', Parsed.CurrentStep);
end;

procedure TestI3_ResultToJson_RoundTrip;
var
  Res: TWorkerResult;
  Json: string;
  Parsed: TWorkerResult;
begin
  Res := Default(TWorkerResult);
  Res.TaskId := 'task-003';
  Res.Success := True;
  Res.OutputFiles := TArray<string>.Create('C:\out1.mp4', 'C:\out2.mp4');
  Res.Metrics := '{"duration":120}';
  Res.ErrorMessage := '';
  Res.DurationMs := 45000;
  Res.CompletedAt := '2026-06-05T10:05:00Z';
  Json := TWorkerProtocol.ResultToJson(Res);
  Parsed := TWorkerProtocol.JsonToResult(Json);
  IAssertEqual('I3 Result task_id', 'task-003', Parsed.TaskId);
  IAssertTrue('I3 Result success', Parsed.Success);
  IAssertEqualInt('I3 Result files count', 2, Length(Parsed.OutputFiles));
  IAssertEqualInt('I3 Result duration ms', 45000, Parsed.DurationMs);
end;

procedure TestI3_WorkDir_Lifecycle;
var
  BaseDir, WorkDir: string;
  Req: TWorkerRequest;
begin
  BaseDir := TPath.Combine(TPath.GetTempPath, 'df_tests_i3');
  ForceDirectories(BaseDir);
  try
    WorkDir := TWorkerProtocol.CreateWorkDir(BaseDir, 'task-lifecycle-001');
    IAssertTrue('I3 workdir created', TDirectory.Exists(WorkDir));
    Req := Default(TWorkerRequest);
    Req.TaskId := 'task-lifecycle-001';
    Req.TaskType := 'render';
    Req.OutputDir := WorkDir;
    Req.HeartbeatIntervalMs := 5000;
    TWorkerProtocol.WriteRequest(WorkDir, Req);
    IAssertTrue('I3 request.json written',
      TFile.Exists(TPath.Combine(WorkDir, 'request.json')));
    TWorkerProtocol.SignalCancel(WorkDir);
    IAssertTrue('I3 cancel detected', TWorkerProtocol.IsCancelSignaled(WorkDir));
    TWorkerProtocol.Cleanup(WorkDir);
    IAssertFalse('I3 workdir removed after cleanup', TDirectory.Exists(WorkDir));
  finally
    if TDirectory.Exists(BaseDir) then
      TDirectory.Delete(BaseDir, True);
  end;
end;

// ============================================================================
// I4: Error / edge-case paths
// ============================================================================

procedure TestI4_SchemaValidation_EmptyDoc;
const
  Schema = '{"type":"object","required":["name"],"properties":{"name":{"type":"string"}}}';
var
  V: TSchemaValidationResult;
begin
  // Auto-repair adds missing required fields with default values, so it may pass
  V := TJsonSchemaValidator.Validate(Schema, '{}', True);
  IAssertTrue('I4 empty doc auto-repaired', V.IsValid);
  IAssertTrue('I4 empty doc had repairs', V.RepairCount > 0);
end;

procedure TestI4_SchemaValidation_TypeMismatch_Repairable;
const
  Schema = '{"type":"object","properties":{"count":{"type":"number"}}}';
  Doc = '{"count":"42"}';
var
  V: TSchemaValidationResult;
begin
  V := TJsonSchemaValidator.Validate(Schema, Doc, True);
  IAssertTrue('I4 string->number repair succeeds', V.IsValid);
  IAssertTrue('I4 repair count > 0', V.RepairCount > 0);
end;

procedure TestI4_FakeLLM_UnknownRole_StillSafe;
var
  Registry: TProviderRegistry;
  Req: TChatCompletionRequest;
  Res: TChatCompletionResult;
  Metrics: TProviderRunMetrics;
begin
  Registry := TProviderRegistry.Instance;
  Registry.SwitchTo(PROVIDER_FAKE);
  Req := Default(TChatCompletionRequest);
  Req.AgentRole := 'totally_unknown_role';
  Req.SystemPrompt := 'sys';
  Req.UserMessage := 'usr';
  // Fake provider should NOT crash on unknown role (graceful fallback)
  IAssertTrue('I4 unknown role does not crash',
    Registry.LLMProvider.ChatComplete(Req, Res, Metrics));
end;

procedure TestI4_GateEvaluator_NegativeScores;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate1(-0.5, -0.5);
  IAssertTrue('I4 negative scores -> Gate1 fail', V.IsFail);
end;

procedure TestI4_GateEvaluator_ScoresAboveOne;
var
  V: TGateVerdict;
begin
  V := TGateEvaluator.EvaluateGate2(1.5);
  IAssertTrue('I4 score > 1.0 -> Gate2 pass', V.IsPass);
end;

procedure TestI4_SubtitleEngine_EmptyText;
var
  Lines: TArray<string>;
begin
  Lines := TSubtitleEngine.SplitLines('', 20);
  IAssertEqualInt('I4 subtitle empty text -> 0 lines', 0, Length(Lines));
end;

procedure TestI4_Gate3a_BothWarn_StaysWarn;
var
  V: TGateVerdict;
begin
  // LUFS delta 1.5, concat 300ms -> both in warn range, neither in fail
  V := TGateEvaluator.EvaluateGate3a(-14.5, -16.0, 300);
  IAssertTrue('I4 Gate3a both warn -> warn (not fail)', V.IsWarn);
end;

// ============================================================================
// I5: Logging + PromptVersion
// ============================================================================

procedure TestI5_WorkflowLogger_NoException;
begin
  // Just verify logging calls do not raise; without DB they write to stub
  TWorkflowLogger.LogJobEvent('test-job', 'test_event', esInfo, 'test message', '{}');
  TWorkflowLogger.LogStepEvent('test-job', 'step-1', 'step_done', esInfo, 'step ok', '{}');
  TWorkflowLogger.LogGateResult('test-job', GATE_2, GATE_RESULT_PASS, 0.92, 'qa pass');
  TWorkflowLogger.LogProviderCall('test-job', 'step-1', 'fake', 'fake-model',
    CAPABILITY_LLM, 10, 100, 200, '');
  IAssertTrue('I5 WorkflowLogger calls no exception', True);
end;

procedure TestI5_WorkflowLogger_BuildPayload;
var
  Fields: TArray<TPair<string, string>>;
  Payload: string;
  Json: TJSONObject;
begin
  SetLength(Fields, 2);
  Fields[0] := TPair<string,string>.Create('job_id', 'job-001');
  Fields[1] := TPair<string,string>.Create('status', 'done');
  Payload := TWorkflowLogger.BuildPayload(Fields);
  IAssertTrue('I5 BuildPayload non-empty', Length(Payload) > 0);
  Json := TJSONObject.ParseJSONValue(Payload) as TJSONObject;
  try
    IAssertTrue('I5 BuildPayload parsed as JSON', Json <> nil);
    if Json <> nil then
    begin
      IAssertEqual('I5 BuildPayload job_id', 'job-001', Json.GetValue<string>('job_id'));
      IAssertEqual('I5 BuildPayload status', 'done', Json.GetValue<string>('status'));
    end;
  finally
    Json.Free;
  end;
end;

procedure TestI5_WorkflowLogger_SeverityToStr;
begin
  IAssertEqual('I5 severity info', 'info', TWorkflowLogger.SeverityToStr(esInfo));
  IAssertEqual('I5 severity warn', 'warn', TWorkflowLogger.SeverityToStr(esWarn));
  IAssertEqual('I5 severity error', 'error', TWorkflowLogger.SeverityToStr(esError));
  IAssertEqual('I5 severity fatal', 'fatal', TWorkflowLogger.SeverityToStr(esFatal));
end;

procedure TestI5_WorkflowLogger_NowISO;
var
  S: string;
begin
  S := TWorkflowLogger.NowISO;
  IAssertTrue('I5 NowISO non-empty', Length(S) > 0);
  // ISO 8601 should contain 'T' and likely 'Z' or '+'
  IAssertTrue('I5 NowISO contains T', Pos('T', S) > 0);
end;

procedure TestI5_PromptVersion_Identity_Stable;
var
  Id1, Id2: TPromptIdentity;
begin
  Id1 := TPromptVersionManager.ComputeIdentity('sys', 'usr', 'schema', 'role', 'model', 0.7, 4096);
  Id2 := TPromptVersionManager.ComputeIdentity('sys', 'usr', 'schema', 'role', 'model', 0.7, 4096);
  IAssertTrue('I5 prompt identity stable', Id1.IsIdentical(Id2));
  IAssertEqual('I5 prompt hash equal', Id1.ContentHash, Id2.ContentHash);
end;

procedure TestI5_PromptVersion_Identity_Different;
var
  Id1, Id2: TPromptIdentity;
begin
  Id1 := TPromptVersionManager.ComputeIdentity('sys-A', 'usr', 'schema', 'role', 'model', 0.7, 4096);
  Id2 := TPromptVersionManager.ComputeIdentity('sys-B', 'usr', 'schema', 'role', 'model', 0.7, 4096);
  IAssertFalse('I5 prompt identity different on sys change', Id1.IsIdentical(Id2));
end;

procedure TestI5_PromptVersion_ContentHash_NonEmpty;
var
  Id: TPromptIdentity;
begin
  Id := TPromptVersionManager.ComputeIdentity('s', 'u', 's', 'r', 'm', 0.5, 1024);
  IAssertTrue('I5 content hash non-empty', Length(Id.ContentHash) > 0);
  IAssertTrue('I5 version no > 0', Id.VersionNo > 0);
end;

procedure TestI5_PromptVersion_ComputeVersion_Stable;
var
  V1, V2: Integer;
begin
  V1 := TPromptVersionManager.ComputeVersion('sys', 'usr', 'schema');
  V2 := TPromptVersionManager.ComputeVersion('sys', 'usr', 'schema');
  IAssertEqualInt('I5 ComputeVersion stable', V1, V2);
end;

procedure TestI5_StyleKeeper_Evaluate_SingleShot;
var
  Shots: TArray<TShotVisualDescriptor>;
  R: TStyleKeeperResult;
begin
  SetLength(Shots, 1);
  Shots[0] := Default(TShotVisualDescriptor);
  Shots[0].ShotId := 'shot-1';
  Shots[0].GroupId := 'g1';
  Shots[0].ArtStyle := 'documentary';
  R := TStyleKeeper.Evaluate(Shots);
  IAssertTrue('I5 StyleKeeper single shot consistent', R.StyleConsistent);
end;

procedure TestI5_StyleKeeper_EvaluateFromJson;
const
  Json = '[{"shot_id":"s1","group_id":"g1","art_style":"doc","color_palette":[],"mood":"calm","transition":"cut"}]';
var
  R: TStyleKeeperResult;
begin
  R := TStyleKeeper.EvaluateFromJson(Json);
  IAssertTrue('I5 StyleKeeper EvaluateFromJson returns result', Length(R.RawJson) > 0);
end;

// ============================================================================
// Run all integration tests
// ============================================================================

procedure RunIntegrationTests;
begin
  WriteLn;
  WriteLn('====== DeepFrames Integration Tests ======');
  WriteLn;

  // I1: Provider + JsonSchema + Gate
  TestI1_FakeLLM_Splitter_SchemaValid;
  TestI1_FakeLLM_QA_Gate2Pass;
  TestI1_FakeLLM_AllRoles_ProduceJson;
  TestI1_FakeTTS_Synthesize;
  TestI1_FakeASR_Transcribe;
  TestI1_FakeImage_Generate;
  TestI1_ProviderRegistry_SwitchFake;
  TestI1_ProviderRegistry_SwitchStepFun_Degrades;

  // I2: Gate full path
  TestI2_Gate1_Boundary_Coverage_Exact_085;
  TestI2_Gate1_Boundary_Distortion_Exact_015;
  TestI2_Gate2_Boundary_Exact_070;
  TestI2_Gate2_Boundary_Exact_085;
  TestI2_Gate3a_LufsOk_ConcatFail;
  TestI2_Gate3a_LufsFail_ConcatOk;
  TestI2_Gate3b_Boundary_070;
  TestI2_Gate3b_Boundary_085;
  TestI2_Gate4_Fail_ScoreZero;
  TestI2_TargetJobStatus_Gate1Fail_Blocked;
  TestI2_TargetJobStatus_Gate2Pass_Continue;
  TestI2_TargetJobStatus_GateLastStep_Done;
  TestI2_QualityGateResult_RoundTrip;

  // I3: WorkerProtocol
  TestI3_TaskTypeToString_All;
  TestI3_StringToTaskType_RoundTrip;
  TestI3_RequestToJson_RoundTrip;
  TestI3_ProgressToJson_RoundTrip;
  TestI3_ResultToJson_RoundTrip;
  TestI3_WorkDir_Lifecycle;

  // I4: Error paths
  TestI4_SchemaValidation_EmptyDoc;
  TestI4_SchemaValidation_TypeMismatch_Repairable;
  TestI4_FakeLLM_UnknownRole_StillSafe;
  TestI4_GateEvaluator_NegativeScores;
  TestI4_GateEvaluator_ScoresAboveOne;
  TestI4_SubtitleEngine_EmptyText;
  TestI4_Gate3a_BothWarn_StaysWarn;

  // I5: Logging + PromptVersion
  TestI5_WorkflowLogger_NoException;
  TestI5_WorkflowLogger_BuildPayload;
  TestI5_WorkflowLogger_SeverityToStr;
  TestI5_WorkflowLogger_NowISO;
  TestI5_PromptVersion_Identity_Stable;
  TestI5_PromptVersion_Identity_Different;
  TestI5_PromptVersion_ContentHash_NonEmpty;
  TestI5_PromptVersion_ComputeVersion_Stable;
  TestI5_StyleKeeper_Evaluate_SingleShot;
  TestI5_StyleKeeper_EvaluateFromJson;

  WriteLn;
  WriteLn(Format('Integration: %d tests, %d passed, %d failed',
    [GITestCount, GITestCount - GIFailCount, GIFailCount]));
  WriteLn('==========================================');
end;

initialization
  RunIntegrationTests;
  if GIFailCount > 0 then
    Halt(1);

end.
