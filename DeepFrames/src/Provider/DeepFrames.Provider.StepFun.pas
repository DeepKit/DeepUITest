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
  /// StepFun TTS provider (stepaudio-2.5-tts via /audio/speech).</summary>
  TStepFunTTSProvider = class(TInterfacedObject, IDeepFramesTTSProvider)
  private
    FLastMetrics: TProviderRunMetrics;
    FHasApiKey: Boolean;
    FKeyCheckDone: Boolean;
    function GetStepPlanKey: string;
    function HasKey: Boolean;
    function EscapeParentheses(const AText: string): string;
    function TruncateInstruction(const AInstruction: string): string;
    function GetOutputDir: string;
    function CallRealAPI(const AText, AVoice, AInstruction, AOutputFormat: string;
      out AResult: TTtsSynthesisResult; out AMetrics: TProviderRunMetrics): Boolean;
    function CallStubAPI(const AText, AVoice, AInstruction, AOutputFormat: string;
      out AResult: TTtsSynthesisResult; out AMetrics: TProviderRunMetrics): Boolean;
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
  /// SSE streaming: uses standard endpoint /v1, NOT /step_plan/v1.</summary>
  TStepFunASRProvider = class(TInterfacedObject, IDeepFramesASRProvider)
  private
    FLastMetrics: TProviderRunMetrics;
    FHasApiKey: Boolean;
    FKeyCheckDone: Boolean;
    function GetStandardKey: string;
    function HasKey: Boolean;
    function GetOutputDir: string;
    function CallRealAPI(const AAudioUri: string;
      out AResult: TAsrTranscriptionResult;
      out AMetrics: TProviderRunMetrics): Boolean;
    function CallStubAPI(const AAudioUri: string;
      out AResult: TAsrTranscriptionResult;
      out AMetrics: TProviderRunMetrics): Boolean;
    function ParseSSELine(const ALine: string; out AEventType, AData: string): Boolean;
    function ParseDeltaData(const AData: string; var AWords: TArray<TAsrWordTimestamp>;
      var ADurationSec: Double): Boolean;
  public
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;
    function Transcribe(const AAudioUri: string;
      out AResult: TAsrTranscriptionResult;
      out AMetrics: TProviderRunMetrics): Boolean;
    function GetLastRunMetrics: TProviderRunMetrics;
  end;

  /// <summary>
  /// StepFun Image provider (step-image-edit-2 via /images/generations).</summary>
  TStepFunImageProvider = class(TInterfacedObject, IDeepFramesImageProvider)
  private
    FLastMetrics: TProviderRunMetrics;
    FHasApiKey: Boolean;
    FKeyCheckDone: Boolean;
    function GetStepPlanKey: string;
    function HasKey: Boolean;
    function GetOutputDir: string;
    function CallRealAPI(const ARequest: TImageGenRequest;
      out AResults: TArray<TImageGenResult>;
      out AMetrics: TProviderRunMetrics): Boolean;
    function CallStubAPI(const ARequest: TImageGenRequest;
      out AResults: TArray<TImageGenResult>;
      out AMetrics: TProviderRunMetrics): Boolean;
  public
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;
    function Generate(const ARequest: TImageGenRequest;
      out AResults: TArray<TImageGenResult>;
      out AMetrics: TProviderRunMetrics): Boolean;
    function GetAvailableStyles: TArray<string>;
    function GetLastRunMetrics: TProviderRunMetrics;
  end;
  private
    FLastMetrics: TProviderRunMetrics;
    FHasApiKey: Boolean;
    FKeyCheckDone: Boolean;
    function GetStandardKey: string;
    function HasKey: Boolean;
    function GetOutputDir: string;
    function CallRealAPI(const AAudioUri: string;
      out AResult: TAsrTranscriptionResult;
      out AMetrics: TProviderRunMetrics): Boolean;
    function CallStubAPI(const AAudioUri: string;
      out AResult: TAsrTranscriptionResult;
      out AMetrics: TProviderRunMetrics): Boolean;
    function ParseSSELine(const ALine: string; out AEventType, AData: string): Boolean;
    function ParseDeltaData(const AData: string; var AWords: TArray<TAsrWordTimestamp>;
      var ADurationSec: Double): Boolean;
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
  System.IOUtils,
  System.JSON,
  System.Diagnostics,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetConsts,
  System.NetEncoding,
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
  if not FKeyCheckDone then
    HasKey;
  if FHasApiKey then
    Result := psOk
  else
    Result := psDegraded;
end;

function TStepFunTTSProvider.GetCapabilities: TProviderCapabilities;
begin
  Result := [pcTTS];
end;

function TStepFunTTSProvider.GetAvailableVoices: TArray<string>;
begin
  Result := ['cixingnansheng', 'wenrounvsheng', 'jizhiqingnian'];
end;

function TStepFunTTSProvider.GetStepPlanKey: string;
begin
  try
    Result := LoadSecret(SECRET_STEP_PLAN_KEY);
  except
    Result := '';
  end;
end;

function TStepFunTTSProvider.HasKey: Boolean;
begin
  if not FKeyCheckDone then
  begin
    FHasApiKey := (Trim(GetStepPlanKey) <> '');
    FKeyCheckDone := True;
  end;
  Result := FHasApiKey;
end;

function TStepFunTTSProvider.EscapeParentheses(const AText: string): string;
begin
  // StepFun TTS interprets () as inline control instructions.
  // Replace with Chinese full-width brackets to preserve meaning.
  Result := AText;
  Result := Result.Replace('(', '（');
  Result := Result.Replace(')', '）');
  // Also escape English square brackets commonly seen in TTS
  Result := Result.Replace('[', '【');
  Result := Result.Replace(']', '】');
end;

function TStepFunTTSProvider.TruncateInstruction(const AInstruction: string): string;
begin
  // instruction limited to 200 characters by StepFun TTS API
  Result := AInstruction;
  if Length(Result) > 200 then
    Result := Copy(Result, 1, 197) + '...';
end;

function TStepFunTTSProvider.GetOutputDir: string;
begin
  Result := 'output/audio/tts';
end;

function TStepFunTTSProvider.CallRealAPI(const AText, AVoice, AInstruction,
  AOutputFormat: string; out AResult: TTtsSynthesisResult;
  out AMetrics: TProviderRunMetrics): Boolean;
var
  HTTP: THTTPClient;
  RequestObj: TJSONObject;
  RequestBody: string;
  ResponseStream: TMemoryStream;
  FileStream: TFileStream;
  OutputFile: string;
  OutputDir: string;
  SafeText: string;
  SafeInstruction: string;
  Format: string;
  Stopwatch: TStopwatch;
  Retry: Integer;
  HttpStatus: Integer;
begin
  Result := False;

  // Prepare inputs
  SafeText := EscapeParentheses(AText);
  SafeInstruction := TruncateInstruction(AInstruction);
  Format := AOutputFormat;
  if Trim(Format) = '' then
    Format := 'wav';

  // Build request body
  RequestObj := TJSONObject.Create;
  try
    RequestObj.AddPair('model', 'stepaudio-2.5-tts');
    RequestObj.AddPair('input', SafeText);
    RequestObj.AddPair('voice', AVoice);
    RequestObj.AddPair('instruction', SafeInstruction);
    RequestObj.AddPair('response_format', Format);
    RequestBody := RequestObj.ToJSON;
  finally
    RequestObj.Free;
  end;

  // Ensure output directory
  OutputDir := GetOutputDir;
  if not DirectoryExists(OutputDir) then
    ForceDirectories(OutputDir);
  OutputFile := OutputDir + '/tts_' + NewUuidString + '.' + Format;

  // HTTP call with retry
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout := 60000;
    HTTP.ContentType := 'application/json';
    HTTP.CustomHeaders['Authorization'] := 'Bearer ' + GetStepPlanKey;

    Stopwatch := TStopwatch.StartNew;
    for Retry := 0 to MAX_RETRIES do
    begin
      try
        ResponseStream := TMemoryStream.Create;
        try
          var ReqStream := TStringStream.Create(RequestBody, TEncoding.UTF8);
          try
            HTTP.Post(STEPFUN_STEP_PLAN_URL + '/audio/speech', ReqStream, ResponseStream);
          finally
            ReqStream.Free;
          end;

          // Check HTTP status
          HttpStatus := HTTP.ResponseCode;
          if HttpStatus = 451 then
          begin
            // 451 Unavailable For Legal Reasons — content review
            // Per docs: generate tts_text_variant, do NOT mutate shot_document
            AMetrics.ProviderName := GetProviderName;
            AMetrics.Model := 'stepaudio-2.5-tts';
            AMetrics.Capability := CAPABILITY_TTS;
            AMetrics.LatencyMs := Integer(Stopwatch.ElapsedMilliseconds);
            AMetrics.ErrorCode := 'TTS_451_CONTENT_REVIEW';
            AMetrics.RetryCount := Retry;
            FLastMetrics := AMetrics;
            ResponseStream.Free;
            Exit(False);
          end;

          if HttpStatus >= 400 then
          begin
            ResponseStream.Free;
            if Retry = MAX_RETRIES then
            begin
              AMetrics.ErrorCode := Format('HTTP_%d', [HttpStatus]);
              AMetrics.LatencyMs := Integer(Stopwatch.ElapsedMilliseconds);
              AMetrics.RetryCount := Retry;
              FLastMetrics := AMetrics;
              Exit(False);
            end;
            Sleep(RETRY_DELAY_MS);
            Continue;
          end;

          // Save audio binary
          FileStream := TFileStream.Create(OutputFile, fmCreate);
          try
            ResponseStream.Position := 0;
            FileStream.CopyFrom(ResponseStream, ResponseStream.Size);
          finally
            FileStream.Free;
          end;

          // Fill result
          AResult.Format := Format;
          AResult.SampleRate := 24000; // StepFun TTS default
          AResult.Channels := 1;
          AResult.DurationSec := Length(AText) * 0.0833; // rough estimate
          AResult.Voice := AVoice;
          AResult.Instruction := SafeInstruction;
          AResult.CharCount := Length(AText);
          AResult.OutputUri := OutputFile;
          AResult.OutputSizeBytes := ResponseStream.Size;

          AMetrics.ProviderName := GetProviderName;
          AMetrics.Model := 'stepaudio-2.5-tts';
          AMetrics.Capability := CAPABILITY_TTS;
          AMetrics.LatencyMs := Integer(Stopwatch.ElapsedMilliseconds);
          AMetrics.TokenUsage := Default(TTokenUsage);
          AMetrics.RequestId := '';
          AMetrics.ErrorCode := '';
          AMetrics.RetryCount := Retry;

          FLastMetrics := AMetrics;
          Result := True;
          Break;
        finally
          ResponseStream.Free;
        end;
      except
        on E: Exception do
        begin
          if Retry = MAX_RETRIES then
          begin
            AMetrics.ProviderName := GetProviderName;
            AMetrics.Model := 'stepaudio-2.5-tts';
            AMetrics.Capability := CAPABILITY_TTS;
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
  finally
    HTTP.Free;
  end;
end;

function TStepFunTTSProvider.CallStubAPI(const AText, AVoice, AInstruction,
  AOutputFormat: string; out AResult: TTtsSynthesisResult;
  out AMetrics: TProviderRunMetrics): Boolean;
var
  CharCount: Integer;
  Format: string;
begin
  Format := AOutputFormat;
  if Trim(Format) = '' then
    Format := 'wav';

  CharCount := Length(AText);
  if CharCount > 200 then
    CharCount := 200;

  AResult.Format := Format;
  AResult.SampleRate := 24000;
  AResult.Channels := 1;
  AResult.DurationSec := CharCount * 0.0833;
  AResult.Voice := AVoice;
  if AResult.Voice = '' then
    AResult.Voice := 'cixingnansheng';
  AResult.Instruction := TruncateInstruction(AInstruction);
  AResult.CharCount := CharCount;
  AResult.OutputUri := Format('output/audio/tts/stub_%s.%s', [AVoice, Format]);
  AResult.OutputSizeBytes := Round(AResult.DurationSec * 24000 * 1 * 2);

  AMetrics.ProviderName := GetProviderName;
  AMetrics.Model := 'stepaudio-2.5-tts';
  AMetrics.Capability := CAPABILITY_TTS;
  AMetrics.LatencyMs := 0;
  AMetrics.TokenUsage := Default(TTokenUsage);
  AMetrics.RequestId := '';
  AMetrics.ErrorCode := '';
  AMetrics.RetryCount := 0;

  FLastMetrics := AMetrics;
  Result := True;
end;

function TStepFunTTSProvider.Synthesize(const AText: string; const AVoice,
  AInstruction, AOutputFormat: string; out AResult: TTtsSynthesisResult;
  out AMetrics: TProviderRunMetrics): Boolean;
begin
  if HasKey then
    Result := CallRealAPI(AText, AVoice, AInstruction, AOutputFormat, AResult, AMetrics)
  else
    Result := CallStubAPI(AText, AVoice, AInstruction, AOutputFormat, AResult, AMetrics);
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
  if not FKeyCheckDone then
    HasKey;
  if FHasApiKey then
    Result := psOk
  else
    Result := psDegraded;
end;

function TStepFunASRProvider.GetCapabilities: TProviderCapabilities;
begin
  Result := [pcASR];
end;

function TStepFunASRProvider.GetStandardKey: string;
begin
  try
    Result := LoadSecret(SECRET_STANDARD_KEY);
  except
    Result := '';
  end;
end;

function TStepFunASRProvider.HasKey: Boolean;
begin
  if not FKeyCheckDone then
  begin
    FHasApiKey := (Trim(GetStandardKey) <> '');
    FKeyCheckDone := True;
  end;
  Result := FHasApiKey;
end;

function TStepFunASRProvider.GetOutputDir: string;
begin
  Result := 'output/audio/asr';
end;

function TStepFunASRProvider.ParseSSELine(const ALine: string;
  out AEventType, AData: string): Boolean;
begin
  Result := False;
  AEventType := '';
  AData := '';

  if ALine.StartsWith('event:') then
  begin
    AEventType := Copy(ALine, 7, MaxInt).Trim;
    Result := True;
  end
  else if ALine.StartsWith('data:') then
  begin
    AData := Copy(ALine, 6, MaxInt).Trim;
    Result := True;
  end;
end;

function TStepFunASRProvider.ParseDeltaData(const AData: string;
  var AWords: TArray<TAsrWordTimestamp>; var ADurationSec: Double): Boolean;
var
  Obj: TJSONObject;
  WordsArr: TJSONArray;
  WordObj: TJSONObject;
  I, OldLen: Integer;
  StartMs, EndMs: Double;
begin
  Result := False;
  if Trim(AData) = '' then
    Exit;

  Obj := TJSONObject.ParseJSONValue(AData) as TJSONObject;
  if Obj = nil then
    Exit;
  try
    // Extract duration if present
    if Obj.TryGetValue<Double>('duration_sec', ADurationSec) then
      ; // already set

    // Extract word timestamps
    WordsArr := Obj.GetValue('words') as TJSONArray;
    if WordsArr = nil then
    begin
      // Try 'timestamps' key
      WordsArr := Obj.GetValue('timestamps') as TJSONArray;
    end;

    if (WordsArr <> nil) and (WordsArr.Count > 0) then
    begin
      OldLen := Length(AWords);
      SetLength(AWords, OldLen + WordsArr.Count);
      for I := 0 to WordsArr.Count - 1 do
      begin
        WordObj := WordsArr.Items[I] as TJSONObject;
        if WordObj = nil then
          Continue;

        AWords[OldLen + I].Word := WordObj.GetValue<string>('word');
        if AWords[OldLen + I].Word = '' then
          AWords[OldLen + I].Word := WordObj.GetValue<string>('text');

        // Timestamps may arrive in ms or seconds — normalize to seconds
        StartMs := 0;
        if WordObj.TryGetValue<Double>('start_sec', StartMs) then
          AWords[OldLen + I].StartSec := StartMs
        else if WordObj.TryGetValue<Double>('start_ms', StartMs) then
          AWords[OldLen + I].StartSec := StartMs / 1000.0
        else if WordObj.TryGetValue<Double>('start', StartMs) then
          AWords[OldLen + I].StartSec := StartMs;

        EndMs := 0;
        if WordObj.TryGetValue<Double>('end_sec', EndMs) then
          AWords[OldLen + I].EndSec := EndMs
        else if WordObj.TryGetValue<Double>('end_ms', EndMs) then
          AWords[OldLen + I].EndSec := EndMs / 1000.0
        else if WordObj.TryGetValue<Double>('end', EndMs) then
          AWords[OldLen + I].EndSec := EndMs;

        AWords[OldLen + I].Confidence := 0.95;
        WordObj.TryGetValue<Double>('confidence', AWords[OldLen + I].Confidence);
      end;
    end;
    Result := True;
  finally
    Obj.Free;
  end;
end;

function TStepFunASRProvider.CallRealAPI(const AAudioUri: string;
  out AResult: TAsrTranscriptionResult;
  out AMetrics: TProviderRunMetrics): Boolean;
var
  HTTP: THTTPClient;
  RequestObj: TJSONObject;
  RequestBody: string;
  AudioBytes: TBytes;
  ResponseStr: string;
  Stream: TStringStream;
  Lines: TArray<string>;
  SSEEvent: string;
  SSEData: string;
  Line: string;
  Stopwatch: TStopwatch;
  Retry: Integer;
  LastEventType: string;
  AllWords: TArray<TAsrWordTimestamp>;
  DurationSec: Double;
begin
  Result := False;
  SetLength(AllWords, 0);
  DurationSec := 0;

  // Read audio file
  if not FileExists(AAudioUri) then
  begin
    AMetrics.ErrorCode := 'AUDIO_FILE_NOT_FOUND';
    Exit(False);
  end;

  // Delphi 12.1+: TFile.ReadAllBytes is preferred over TBytesStream
  AudioBytes := TFile.ReadAllBytes(AAudioUri);

  // Build request with Base64 audio
  RequestObj := TJSONObject.Create;
  try
    RequestObj.AddPair('audio', TNetEncoding.Base64.EncodeBytesToString(AudioBytes));
    RequestObj.AddPair('enable_timestamp', TJSONBool.Create(True));
    RequestObj.AddPair('model', 'stepfun-asr');
    RequestBody := RequestObj.ToJSON;
  finally
    RequestObj.Free;
  end;

  // HTTP call with SSE stream parsing
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 30000;
    HTTP.ResponseTimeout := 120000;
    HTTP.ContentType := 'application/json';
    HTTP.CustomHeaders['Authorization'] := 'Bearer ' + GetStandardKey;
    // ASR SSE uses /v1 endpoint, NOT /step_plan/v1
    HTTP.CustomHeaders['Accept'] := 'text/event-stream';

    Stopwatch := TStopwatch.StartNew;
    for Retry := 0 to MAX_RETRIES do
    begin
      try
        Stream := TStringStream.Create(RequestBody, TEncoding.UTF8);
        try
          ResponseStr := HTTP.Post(STEPFUN_STANDARD_URL + '/audio/asr/sse',
            Stream).ContentAsString(TEncoding.UTF8);
        finally
          Stream.Free;
        end;

        // Parse SSE response
        Lines := ResponseStr.Split([#10]);
        LastEventType := '';
        for Line in Lines do
        begin
          if Trim(Line) = '' then
            Continue;

          if ParseSSELine(Line, SSEEvent, SSEData) then
          begin
            if SSEEvent <> '' then
              LastEventType := SSEEvent;

            if SSEData <> '' then
            begin
              if SameText(LastEventType, 'delta') or (LastEventType = '') then
                ParseDeltaData(SSEData, AllWords, DurationSec)
              else if SameText(LastEventType, 'done') then
              begin
                // Final result — duration may be in done event
                if DurationSec = 0 then
                begin
                  var DoneObj := TJSONObject.ParseJSONValue(SSEData) as TJSONObject;
                  if DoneObj <> nil then
                  begin
                    DoneObj.TryGetValue<Double>('duration_sec', DurationSec);
                    DoneObj.Free;
                  end;
                end;
              end
              else if SameText(LastEventType, 'error') then
              begin
                AMetrics.ErrorCode := 'ASR_ERROR_EVENT';
                AMetrics.LatencyMs := Integer(Stopwatch.ElapsedMilliseconds);
                FLastMetrics := AMetrics;
                Exit(False);
              end;
            end;
          end;
        end;

        Break; // success — exit retry loop
      except
        on E: Exception do
        begin
          if Retry = MAX_RETRIES then
          begin
            AMetrics.ProviderName := GetProviderName;
            AMetrics.Model := 'stepfun-asr';
            AMetrics.Capability := CAPABILITY_ASR;
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

  // Fill result
  AResult.DurationSec := DurationSec;
  AResult.Words := AllWords;

  AMetrics.ProviderName := GetProviderName;
  AMetrics.Model := 'stepfun-asr';
  AMetrics.Capability := CAPABILITY_ASR;
  AMetrics.LatencyMs := Integer(Stopwatch.ElapsedMilliseconds);
  AMetrics.TokenUsage := Default(TTokenUsage);
  AMetrics.RequestId := '';
  AMetrics.ErrorCode := '';
  AMetrics.RetryCount := Retry;

  FLastMetrics := AMetrics;
  Result := True;
end;

function TStepFunASRProvider.CallStubAPI(const AAudioUri: string;
  out AResult: TAsrTranscriptionResult;
  out AMetrics: TProviderRunMetrics): Boolean;
const
  STUB_WORDS: array[0..4] of string = ('词1', '词2', '词3', '词4', '词5');
var
  I: Integer;
begin
  SetLength(AResult.Words, 5);
  AResult.DurationSec := 3.5;
  for I := 0 to High(STUB_WORDS) do
  begin
    AResult.Words[I].Word := STUB_WORDS[I];
    AResult.Words[I].StartSec := I * 0.7;
    AResult.Words[I].EndSec := I * 0.7 + 0.6;
    AResult.Words[I].Confidence := 0.95;
  end;

  AMetrics.ProviderName := GetProviderName;
  AMetrics.Model := 'stepfun-asr';
  AMetrics.Capability := CAPABILITY_ASR;
  AMetrics.LatencyMs := 0;
  AMetrics.TokenUsage := Default(TTokenUsage);
  AMetrics.RequestId := '';
  AMetrics.ErrorCode := '';
  AMetrics.RetryCount := 0;

  FLastMetrics := AMetrics;
  Result := True;
end;

function TStepFunASRProvider.Transcribe(const AAudioUri: string;
  out AResult: TAsrTranscriptionResult;
  out AMetrics: TProviderRunMetrics): Boolean;
begin
  if HasKey then
    Result := CallRealAPI(AAudioUri, AResult, AMetrics)
  else
    Result := CallStubAPI(AAudioUri, AResult, AMetrics);
end;

function TStepFunASRProvider.GetLastRunMetrics: TProviderRunMetrics;
begin
  Result := FLastMetrics;
end;

{ TStepFunImageProvider }

function TStepFunImageProvider.GetProviderName: string;
begin
  Result := PROVIDER_STEPFUN;
end;

function TStepFunImageProvider.GetProviderStatus: TProviderStatus;
begin
  if not FKeyCheckDone then
    HasKey;
  if FHasApiKey then
    Result := psOk
  else
    Result := psDegraded;
end;

function TStepFunImageProvider.GetCapabilities: TProviderCapabilities;
begin
  Result := [pcImageGen, pcImageEdit];
end;

function TStepFunImageProvider.GetAvailableStyles: TArray<string>;
begin
  Result := ['realistic', 'anime', 'illustration', 'documentary'];
end;

function TStepFunImageProvider.GetStepPlanKey: string;
begin
  try
    Result := LoadSecret(SECRET_STEP_PLAN_KEY);
  except
    Result := '';
  end;
end;

function TStepFunImageProvider.HasKey: Boolean;
begin
  if not FKeyCheckDone then
  begin
    FHasApiKey := (Trim(GetStepPlanKey) <> '');
    FKeyCheckDone := True;
  end;
  Result := FHasApiKey;
end;

function TStepFunImageProvider.GetOutputDir: string;
begin
  Result := 'output/images';
end;

function TStepFunImageProvider.CallRealAPI(const ARequest: TImageGenRequest;
  out AResults: TArray<TImageGenResult>;
  out AMetrics: TProviderRunMetrics): Boolean;
var
  HTTP: THTTPClient;
  RequestObj: TJSONObject;
  RequestBody, ResponseStr: string;
  ResponseObj: TJSONObject;
  DataArr: TJSONArray;
  DataObj: TJSONObject;
  I: Integer;
  Stopwatch: TStopwatch;
  Retry: Integer;
  OutputDir: string;
begin
  Result := False;
  SetLength(AResults, 0);

  OutputDir := GetOutputDir;
  ForceDirectories(OutputDir);

  RequestObj := TJSONObject.Create;
  try
    RequestObj.AddPair('model', 'step-image-edit-2');
    RequestObj.AddPair('prompt', ARequest.Prompt);
    if ARequest.NegativePrompt <> '' then
      RequestObj.AddPair('negative_prompt', ARequest.NegativePrompt);
    RequestObj.AddPair('size', Format('%dx%d', [ARequest.Width, ARequest.Height]));
    RequestObj.AddPair('n', TJSONNumber.Create(ARequest.NumImages));
    if ARequest.Style <> '' then
      RequestObj.AddPair('style', ARequest.Style);
    RequestBody := RequestObj.ToJSON;
  finally
    RequestObj.Free;
  end;

  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 30000;
    HTTP.ResponseTimeout := 120000;
    HTTP.ContentType := 'application/json';
    HTTP.CustomHeaders['Authorization'] := 'Bearer ' + GetStepPlanKey;

    Stopwatch := TStopwatch.StartNew;
    for Retry := 0 to MAX_RETRIES do
    begin
      try
        var ReqStream := TStringStream.Create(RequestBody, TEncoding.UTF8);
        try
          ResponseStr := HTTP.Post(STEPFUN_STEP_PLAN_URL + '/images/generations',
            ReqStream).ContentAsString(TEncoding.UTF8);
        finally
          ReqStream.Free;
        end;
        Break;
      except
        if Retry = MAX_RETRIES then
        begin
          AMetrics.ErrorCode := 'HTTP_ERROR';
          FLastMetrics := AMetrics;
          Exit(False);
        end;
        Sleep(RETRY_DELAY_MS);
      end;
    end;
    Stopwatch.Stop;

    ResponseObj := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
    if ResponseObj = nil then
    begin
      AMetrics.ErrorCode := 'JSON_PARSE_ERROR';
      Exit(False);
    end;
    try
      DataArr := ResponseObj.GetValue('data') as TJSONArray;
      if (DataArr = nil) or (DataArr.Count = 0) then
      begin
        AMetrics.ErrorCode := 'NO_DATA';
        Result := False;
        Exit;
      end;

      SetLength(AResults, DataArr.Count);
      for I := 0 to DataArr.Count - 1 do
      begin
        DataObj := DataArr.Items[I] as TJSONObject;
        if DataObj = nil then
          Continue;

        AResults[I].OutputUri := Format('%s/img_%s_%d.png',
          [OutputDir, NewUuidString, I + 1]);
        AResults[I].Width := ARequest.Width;
        AResults[I].Height := ARequest.Height;
        AResults[I].Format := 'png';
        AResults[I].Seed := 0;
        DataObj.TryGetValue<Integer>('seed', AResults[I].Seed);
        AResults[I].RevisedPrompt := DataObj.GetValue<string>('revised_prompt');
        AResults[I].OutputSizeBytes := 0;
      end;

      AMetrics.ProviderName := GetProviderName;
      AMetrics.Model := 'step-image-edit-2';
      AMetrics.Capability := CAPABILITY_IMAGE_GEN;
      AMetrics.LatencyMs := Integer(Stopwatch.ElapsedMilliseconds);
      AMetrics.ErrorCode := '';
      AMetrics.RetryCount := Retry;
      FLastMetrics := AMetrics;
      Result := True;
    finally
      ResponseObj.Free;
    end;
  finally
    HTTP.Free;
  end;
end;

function TStepFunImageProvider.CallStubAPI(const ARequest: TImageGenRequest;
  out AResults: TArray<TImageGenResult>;
  out AMetrics: TProviderRunMetrics): Boolean;
var
  Count, I: Integer;
begin
  Count := ARequest.NumImages;
  if Count <= 0 then
    Count := 1;

  SetLength(AResults, Count);
  for I := 0 to Count - 1 do
  begin
    AResults[I].OutputUri := Format('output/images/stub/gen_%d.png', [I + 1]);
    AResults[I].OutputSizeBytes := 512000;
    AResults[I].Width := ARequest.Width;
    AResults[I].Height := ARequest.Height;
    AResults[I].Format := 'png';
    AResults[I].Seed := 42;
    AResults[I].RevisedPrompt := ARequest.Prompt + ' (stub)';
  end;

  AMetrics.ProviderName := GetProviderName;
  AMetrics.Model := 'step-image-edit-2';
  AMetrics.Capability := CAPABILITY_IMAGE_GEN;
  AMetrics.LatencyMs := 0;
  FLastMetrics := AMetrics;
  Result := True;
end;

function TStepFunImageProvider.Generate(const ARequest: TImageGenRequest;
  out AResults: TArray<TImageGenResult>;
  out AMetrics: TProviderRunMetrics): Boolean;
begin
  if HasKey then
    Result := CallRealAPI(ARequest, AResults, AMetrics)
  else
    Result := CallStubAPI(ARequest, AResults, AMetrics);
end;

function TStepFunImageProvider.GetLastRunMetrics: TProviderRunMetrics;
begin
  Result := FLastMetrics;
end;

end.