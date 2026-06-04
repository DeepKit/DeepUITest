unit DeepFrames.Provider.StepFun;

/// <summary>
/// StepFun (阶跃星辰) provider implementations.
///
/// CURRENT STATE: Skeleton only — LLM chat completion is stubbed; TTS and ASR
/// raise ENotImplemented.
///
/// REAL INTEGRATION PHASE (Phase 2-3):
/// - LLM: POST https://api.stepfun.com/step_plan/v1/chat/completions
///   (OpenAI-compatible, Bearer token from DeepBase.Security)
/// - TTS: POST https://api.stepfun.com/step_plan/v1/audio/speech
///   (voice + instruction, 200-char instruction limit, box-parentheses escape)
/// - ASR: POST https://api.stepfun.com/v1/audio/asr/sse
///   (SSE streaming, word-level timestamps, different base URL from step_plan)
///
/// KEY RULES (from docs/02.api-阶跃星辰集成-step-plan-api.md):
/// - ASR SSE uses /v1 base URL, NOT /step_plan/v1
/// - Step Plan Key and Standard Key are NOT interchangeable
/// - TTS: no voice_label parameter, only voice + instruction
/// - TTS default output 24kHz, must resample to 48kHz
/// - API Keys loaded via DeepBase.Security.LoadSecret, never from .env/JSON/INI
/// </summary>

interface

uses
  DeepFrames.Provider.Intf,
  DeepFrames.Provider.Types;

type
  /// <summary>
  /// StepFun LLM provider (Chat Completion via OpenAI-compatible /v1/chat/completions).
  ///
  /// Currently skeleton: returns stub JSON matching fake provider structure.
  /// Real HTTP integration lands in Phase 2 (tasks P2.1-P2.9).
  /// </summary>
  TStepFunLLMProvider = class(TInterfacedObject, IDeepFramesLLMProvider)
  private
    FLastMetrics: TProviderRunMetrics;
    function GetApiBaseUrl: string;
    function GetApiKey: string;
    function BuildStubOutput(const ASystemPrompt: string): string;
  public
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;
    function ChatComplete(const ARequest: TChatCompletionRequest;
      out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;
    function GetLastRunMetrics: TProviderRunMetrics;
    function GetSupportedModels: TArray<string>;
  end;

  /// <summary>
  /// StepFun TTS provider (stepaudio-2.5-tts via /audio/speech).
  ///
  /// Raises ENotImplemented until Phase 4 (P4.1-P4.5) real TTS integration.
  /// </summary>
  TStepFunTTSProvider = class(TInterfacedObject, IDeepFramesTTSProvider)
  private
    FLastMetrics: TProviderRunMetrics;
  public
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;
    function Synthesize(const AText: string; const AVoice, AInstruction: string;
      const AOutputFormat: string; out AResult: TTtsSynthesisResult;
      out AMetrics: TProviderRunMetrics): Boolean;
    function GetAvailableVoices: TArray<string>;
    function GetLastRunMetrics: TProviderRunMetrics;
  end;

  /// <summary>
  /// StepFun ASR provider (stepfun-asr via /v1/audio/asr/sse).
  ///
  /// Raises ENotImplemented until Phase 4 (P4.6-P4.7) real ASR integration.
  /// Note: ASR uses /v1 base URL, NOT /step_plan/v1.
  /// </summary>
  TStepFunASRProvider = class(TInterfacedObject, IDeepFramesASRProvider)
  private
    FLastMetrics: TProviderRunMetrics;
  public
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;
    function Transcribe(const AAudioUri: string;
      out AResult: TAsrTranscriptionResult;
      out AMetrics: TProviderRunMetrics): Boolean;
    function GetLastRunMetrics: TProviderRunMetrics;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  DeepFrames.Shared.Consts;

{ TStepFunLLMProvider }

function TStepFunLLMProvider.GetProviderName: string;
begin
  Result := PROVIDER_STEPFUN;
end;

function TStepFunLLMProvider.GetProviderStatus: TProviderStatus;
begin
  Result := psOk; // skeleton — no real connectivity check yet
end;

function TStepFunLLMProvider.GetCapabilities: TProviderCapabilities;
begin
  Result := [pcLLM];
end;

function TStepFunLLMProvider.GetSupportedModels: TArray<string>;
begin
  Result := ['stepfun-flash-3.5', 'deepseek-v4-pro'];
end;

function TStepFunLLMProvider.GetApiBaseUrl: string;
begin
  Result := 'https://api.stepfun.com/step_plan/v1';
end;

function TStepFunLLMProvider.GetApiKey: string;
begin
  // TODO Phase 2: DeepBase.Security.LoadSecret('stepfun/step_plan_key')
  Result := '';
end;

function TStepFunLLMProvider.BuildStubOutput(const ASystemPrompt: string): string;
var
  Obj: TJSONObject;
  ShotsArr: TJSONArray;
  ShotObj: TJSONObject;
begin
  // Skeleton LLM output: matches Fake provider JSON structure
  // Phase 2 replaces this with real HTTP POST → JSON parse
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('provider', PROVIDER_STEPFUN);
    Obj.AddPair('model', 'stepfun-flash-3.5');
    Obj.AddPair('status', 'skeleton');
    Obj.AddPair('note', 'Real HTTP integration pending Phase 2');
    ShotsArr := TJSONArray.Create;
    ShotObj := TJSONObject.Create;
    ShotObj.AddPair('shot_id', 'shot_001');
    ShotObj.AddPair('group_id', 'group_01');
    ShotObj.AddPair('text', 'Skeleton StepFun output — replace with real API call');
    ShotObj.AddPair('duration_sec', TJSONNumber.Create(5.0));
    ShotsArr.AddElement(ShotObj);
    Obj.AddPair('shots', ShotsArr);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function TStepFunLLMProvider.ChatComplete(const ARequest: TChatCompletionRequest;
  out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;
var
  ResponseJson: string;
begin
  // TODO Phase 2 (P2.1): Real HTTP POST to GetApiBaseUrl + '/chat/completions'
  //   - Build OpenAI-compatible request body with ARequest
  //   - POST with Bearer token from GetApiKey
  //   - Parse response JSON, extract content
  //   - Validate against ARequest.OutputSchemaJson
  //   - Implement repair/retry on schema mismatch
  // For now: return skeleton stub output

  ResponseJson := BuildStubOutput(ARequest.SystemPrompt);

  AResult.ResponseJson := ResponseJson;
  AResult.NormalizedJson := ResponseJson;
  AResult.ValidationError := '';
  AResult.RepairCount := 0;
  AResult.FinishReason := 'stop';

  AMetrics.ProviderName := GetProviderName;
  AMetrics.Model := ARequest.Model;
  AMetrics.Capability := CAPABILITY_LLM;
  AMetrics.LatencyMs := 0;
  AMetrics.TokenUsage.PromptTokens := 0;
  AMetrics.TokenUsage.CompletionTokens := 0;
  AMetrics.TokenUsage.TotalTokens := 0;
  AMetrics.RequestId := '';
  AMetrics.ErrorCode := '';
  AMetrics.RetryCount := 0;

  FLastMetrics := AMetrics;
  Result := True;
end;

function TStepFunLLMProvider.GetLastRunMetrics: TProviderRunMetrics;
begin
  Result := FLastMetrics;
end;

{ TStepFunTTSProvider }

function TStepFunTTSProvider.GetProviderName: string;
begin
  Result := PROVIDER_STEPFUN;
end;

function TStepFunTTSProvider.GetProviderStatus: TProviderStatus;
begin
  Result := psOk;
end;

function TStepFunTTSProvider.GetCapabilities: TProviderCapabilities;
begin
  Result := [pcTTS];
end;

function TStepFunTTSProvider.GetAvailableVoices: TArray<string>;
begin
  // TODO Phase 4: query from StepFun /audio/voices endpoint or use known list
  Result := ['cixingnansheng', 'wenrounvsheng', 'jizhiqingnian'];
end;

function TStepFunTTSProvider.Synthesize(const AText: string; const AVoice,
  AInstruction, AOutputFormat: string; out AResult: TTtsSynthesisResult;
  out AMetrics: TProviderRunMetrics): Boolean;
begin
  // TODO Phase 4 (P4.1-P4.5):
  //   - POST to https://api.stepfun.com/step_plan/v1/audio/speech
  //   - Body: {model, input, voice, instruction, response_format}
  //   - Escape/remove parentheses in input text (TTS interprets () as inline commands)
  //   - Save binary audio stream to file
  //   - Record sample rate (24kHz default), resample to 48kHz downstream
  //   - Handle HTTP 451 (content review): generate tts_text_variant, not mutate shot_document
  raise ENotImplemented.Create('TStepFunTTSProvider.Synthesize: real TTS integration pending Phase 4');
end;

function TStepFunTTSProvider.GetLastRunMetrics: TProviderRunMetrics;
begin
  Result := FLastMetrics;
end;

{ TStepFunASRProvider }

function TStepFunASRProvider.GetProviderName: string;
begin
  Result := PROVIDER_STEPFUN;
end;

function TStepFunASRProvider.GetProviderStatus: TProviderStatus;
begin
  Result := psOk;
end;

function TStepFunASRProvider.GetCapabilities: TProviderCapabilities;
begin
  Result := [pcASR];
end;

function TStepFunASRProvider.Transcribe(const AAudioUri: string;
  out AResult: TAsrTranscriptionResult;
  out AMetrics: TProviderRunMetrics): Boolean;
begin
  // TODO Phase 4 (P4.6-P4.7):
  //   - POST to https://api.stepfun.com/v1/audio/asr/sse  (NOT /step_plan/v1!)
  //   - Body: Base64-encoded audio with enable_timestamp=true
  //   - Handle SSE streaming protocol:
  //     * Accumulate all Delta events (word-level timestamps arrive incrementally)
  //     * Wait for Done event before returning
  //     * Convert millisecond timestamps to seconds
  //   - Handle error event format
  raise ENotImplemented.Create('TStepFunASRProvider.Transcribe: real ASR integration pending Phase 4');
end;

function TStepFunASRProvider.GetLastRunMetrics: TProviderRunMetrics;
begin
  Result := FLastMetrics;
end;

end.