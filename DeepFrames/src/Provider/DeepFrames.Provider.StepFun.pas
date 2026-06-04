unit DeepFrames.Provider.StepFun;

/// <summary>
/// StepFun (阶跃星辰) provider implementations.
///
/// LLM provider: Real HTTP POST to OpenAI-compatible /chat/completions endpoint
///   when API key is available; falls back to stub output when key is missing.
/// TTS/ASR providers: raise ENotImplemented until Phase 4.
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
  /// StepFun LLM provider — real HTTP POST to OpenAI-compatible endpoint.
  /// Falls back to stub JSON when API key is not configured.</summary>
  TStepFunLLMProvider = class(TInterfacedObject, IDeepFramesLLMProvider)
  private
    FLastMetrics: TProviderRunMetrics;
    FAvailable: Boolean;
    FKeyCheckDone: Boolean;
    FHasApiKey: Boolean;
    function GetApiBaseUrl: string;
    function GetApiKey: string;
    function HasApiKey: Boolean;
    function BuildStubOutput(const ASystemPrompt: string): string;
    function CallRealAPI(const ARequest: TChatCompletionRequest;
      out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;
    function CallStubAPI(const ARequest: TChatCompletionRequest;
      out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;
  public
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;
    function ChatComplete(const ARequest: TChatCompletionRequest;
      out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;
    function GetLastRunMetrics: TProviderRunMetrics;
    function GetSupportedModels: TArray<string>;
    function IsRealAPI: Boolean;
  end;

  /// <summary>
  /// StepFun TTS provider — ENotImplemented until Phase 4.</summary>
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
  /// StepFun ASR provider — ENotImplemented until Phase 4.</summary>
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
  System.Classes,
  System.JSON,
  System.Diagnostics,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetConsts,
  DeepBase.Security,
  DeepFrames.Shared.Consts,
  DeepFrames.Shared.JsonSchema;

const
  STEPFUN_STEP_PLAN_URL = 'https://api.stepfun.com/step_plan/v1';
  STEPFUN_STANDARD_URL  = 'https://api.stepfun.com/v1';
  SECRET_STEP_PLAN_KEY  = 'deepframes/stepfun/step_plan_key';
  SECRET_STANDARD_KEY   = 'deepframes/stepfun/standard_key';
  MAX_RETRIES           = 2;
  RETRY_DELAY_MS        = 500;

{ TStepFunLLMProvider }

function TStepFunLLMProvider.GetProviderName: string;
begin
  Result := PROVIDER_STEPFUN;
end;

function TStepFunLLMProvider.GetProviderStatus: TProviderStatus;
begin
  if not FKeyCheckDone then
    HasApiKey; // trigger lazy key check
  if FHasApiKey then
    Result := psOk
  else
    Result := psDegraded; // key missing → degraded (stub mode)
end;

function TStepFunLLMProvider.GetCapabilities: TProviderCapabilities;
begin
  Result := [pcLLM];
end;

function TStepFunLLMProvider.GetSupportedModels: TArray<string>;
begin
  Result := ['stepfun-flash-3.5', 'deepseek-v4-pro'];
end;

function TStepFunLLMProvider.IsRealAPI: Boolean;
begin
  Result := HasApiKey;
end;

function TStepFunLLMProvider.GetApiBaseUrl: string;
begin
  Result := STEPFUN_STEP_PLAN_URL;
end;

function TStepFunLLMProvider.GetApiKey: string;
begin
  try
    Result := LoadSecret(SECRET_STEP_PLAN_KEY);
  except
    Result := '';
  end;
end;

function TStepFunLLMProvider.HasApiKey: Boolean;
begin
  if not FKeyCheckDone then
  begin
    FHasApiKey := (Trim(GetApiKey) <> '');
    FKeyCheckDone := True;
  end;
  Result := FHasApiKey;
end;

function TStepFunLLMProvider.BuildStubOutput(const ASystemPrompt: string): string;
var
  Obj: TJSONObject;
  ShotsArr: TJSONArray;
  ShotObj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('provider', PROVIDER_STEPFUN);
    Obj.AddPair('model', 'stepfun-flash-3.5');
    Obj.AddPair('status', 'stub');
    Obj.AddPair('note', 'API key not configured — using stub output');
    ShotsArr := TJSONArray.Create;
    ShotObj := TJSONObject.Create;
    ShotObj.AddPair('shot_id', 'shot_001');
    ShotObj.AddPair('group_id', 'group_01');
    ShotObj.AddPair('text', 'StepFun stub output — configure API key for real calls');
    ShotObj.AddPair('duration_sec', TJSONNumber.Create(5.0));
    ShotsArr.AddElement(ShotObj);
    Obj.AddPair('shots', ShotsArr);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function TStepFunLLMProvider.CallRealAPI(const ARequest: TChatCompletionRequest;
  out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;
var
  HTTP: THTTPClient;
  RequestBody, ResponseStr: string;
  RequestObj, ResponseObj: TJSONObject;
  MessagesArr: TJSONArray;
  MsgObj: TJSONObject;
  ChoicesArr: TJSONArray;
  ChoiceObj: TJSONObject;
  MsgContent: TJSONObject;
  UsageObj: TJSONObject;
  Stream: TStringStream;
  Stopwatch: TStopwatch;
  Retry: Integer;
  ModelName: string;
begin
  Result := False;
  ResponseStr := '';
  ModelName := ARequest.Model;
  if Trim(ModelName) = '' then
    ModelName := 'stepfun-flash-3.5';

  // Build OpenAI-compatible request body
  RequestObj := TJSONObject.Create;
  try
    RequestObj.AddPair('model', ModelName);
    MessagesArr := TJSONArray.Create;
    // System message
    if Trim(ARequest.SystemPrompt) <> '' then
    begin
      MsgObj := TJSONObject.Create;
      MsgObj.AddPair('role', 'system');
      MsgObj.AddPair('content', ARequest.SystemPrompt);
      MessagesArr.AddElement(MsgObj);
    end;
    // User message
    MsgObj := TJSONObject.Create;
    MsgObj.AddPair('role', 'user');
    MsgObj.AddPair('content', ARequest.UserMessage);
    MessagesArr.AddElement(MsgObj);
    RequestObj.AddPair('messages', MessagesArr);
    RequestObj.AddPair('temperature', TJSONNumber.Create(ARequest.Temperature));
    if ARequest.MaxTokens > 0 then
      RequestObj.AddPair('max_tokens', TJSONNumber.Create(ARequest.MaxTokens));
    RequestObj.AddPair('stream', TJSONBool.Create(False));
    RequestBody := RequestObj.ToJSON;
  finally
    RequestObj.Free;
  end;

  // HTTP call with retry
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 30000;
    HTTP.ResponseTimeout := 60000;
    HTTP.ContentType := 'application/json';
    HTTP.CustomHeaders['Authorization'] := 'Bearer ' + GetApiKey;

    Stopwatch := TStopwatch.StartNew;
    for Retry := 0 to MAX_RETRIES do
    begin
      try
        Stream := TStringStream.Create(RequestBody, TEncoding.UTF8);
        try
          ResponseStr := HTTP.Post(GetApiBaseUrl + '/chat/completions', Stream).ContentAsString(TEncoding.UTF8);
        finally
          Stream.Free;
        end;
        Break; // success — exit retry loop
      except
        on E: Exception do
        begin
          if Retry = MAX_RETRIES then
          begin
            // All retries exhausted
            AMetrics.ProviderName := GetProviderName;
            AMetrics.Model := ModelName;
            AMetrics.Capability := CAPABILITY_LLM;
            AMetrics.LatencyMs := Integer(Stopwatch.ElapsedMilliseconds);
            AMetrics.ErrorCode := 'HTTP_ERROR';
            AMetrics.RetryCount := Retry;
            FLastMetrics := AMetrics;
            Exit(False);
          end;
          Sleep(RETRY_DELAY_MS);
        end;
      end;
    end;
    Stopwatch.Stop;
  finally
    HTTP.Free;
  end;

  // Parse the OpenAI-compatible response
  ResponseObj := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  if ResponseObj = nil then
  begin
    AMetrics.ErrorCode := 'JSON_PARSE_ERROR';
    Exit(False);
  end;
  try
    // Extract content from choices[0].message.content
    ChoicesArr := ResponseObj.GetValue<TJSONArray>('choices');
    if (ChoicesArr = nil) or (ChoicesArr.Count = 0) then
    begin
      AMetrics.ErrorCode := 'NO_CHOICES';
      Exit(False);
    end;

    ChoiceObj := ChoicesArr.Items[0] as TJSONObject;
    MsgContent := ChoiceObj.GetValue<TJSONObject>('message');
    if MsgContent = nil then
    begin
      AMetrics.ErrorCode := 'NO_MESSAGE';
      Exit(False);
    end;

    AResult.ResponseJson := MsgContent.GetValue<string>('content');
    AResult.FinishReason := ChoiceObj.GetValue<string>('finish_reason');
    AResult.ValidationError := '';
    AResult.RepairCount := 0;

    // Schema validation + auto-repair when output schema is provided
    if (Trim(ARequest.OutputSchemaJson) <> '') and
       (ARequest.OutputSchemaJson <> '{}') then
    begin
      var SchemaResult := TJsonSchemaValidator.Validate(
        ARequest.OutputSchemaJson, AResult.ResponseJson, True);
      if SchemaResult.HasErrors then
      begin
        AResult.ValidationError := string.Join('; ', SchemaResult.Errors);
        AResult.RepairCount := SchemaResult.RepairCount;
      end;
      if SchemaResult.HasRepairs then
      begin
        AResult.NormalizedJson := SchemaResult.RepairedJson;
        AResult.RepairCount := SchemaResult.RepairCount;
      end
      else
        AResult.NormalizedJson := AResult.ResponseJson;
    end
    else
      AResult.NormalizedJson := AResult.ResponseJson;

    // Extract usage
    UsageObj := ResponseObj.GetValue<TJSONObject>('usage');
    if UsageObj <> nil then
    begin
      AMetrics.TokenUsage.PromptTokens := UsageObj.GetValue<Integer>('prompt_tokens');
      AMetrics.TokenUsage.CompletionTokens := UsageObj.GetValue<Integer>('completion_tokens');
      AMetrics.TokenUsage.TotalTokens := UsageObj.GetValue<Integer>('total_tokens');
    end;

    AMetrics.ProviderName := GetProviderName;
    AMetrics.Model := ResponseObj.GetValue<string>('model');
    if AMetrics.Model = '' then
      AMetrics.Model := ModelName;
    AMetrics.Capability := CAPABILITY_LLM;
    AMetrics.LatencyMs := Integer(Stopwatch.ElapsedMilliseconds);
    AMetrics.RequestId := ResponseObj.GetValue<string>('id');
    AMetrics.ErrorCode := '';
    AMetrics.RetryCount := Retry;

    FLastMetrics := AMetrics;
    Result := True;
  finally
    ResponseObj.Free;
  end;
end;

function TStepFunLLMProvider.CallStubAPI(const ARequest: TChatCompletionRequest;
  out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;
var
  ResponseJson: string;
begin
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

function TStepFunLLMProvider.ChatComplete(const ARequest: TChatCompletionRequest;
  out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;
begin
  if HasApiKey then
    Result := CallRealAPI(ARequest, AResult, AMetrics)
  else
    Result := CallStubAPI(ARequest, AResult, AMetrics);
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
  Result := ['cixingnansheng', 'wenrounvsheng', 'jizhiqingnian'];
end;

function TStepFunTTSProvider.Synthesize(const AText: string; const AVoice,
  AInstruction, AOutputFormat: string; out AResult: TTtsSynthesisResult;
  out AMetrics: TProviderRunMetrics): Boolean;
begin
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
  raise ENotImplemented.Create('TStepFunASRProvider.Transcribe: real ASR integration pending Phase 4');
end;

function TStepFunASRProvider.GetLastRunMetrics: TProviderRunMetrics;
begin
  Result := FLastMetrics;
end;

end.