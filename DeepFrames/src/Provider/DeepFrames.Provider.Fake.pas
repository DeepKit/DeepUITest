unit DeepFrames.Provider.Fake;

/// <summary>
/// Fake (stub) provider implementations for all three capabilities.
///
/// Returns deterministic, well-formed structured JSON for every call.
/// Used during Phase 1-2 development to exercise the full pipeline
/// without real API calls, and retained as a regression test fixture
/// after StepFun adapter is integrated.
///
/// All JSON output carries schema_version = '1.0.0'.
/// </summary>

interface

uses
  DeepFrames.Provider.Intf,
  DeepFrames.Provider.Types;

type
  /// <summary>Fake LLM provider — returns stub JSON per agent role.</summary>
  TFakeLLMProvider = class(TInterfacedObject, IDeepFramesLLMProvider)
  private
    FLastMetrics: TProviderRunMetrics;
    function BuildRoleOutput(const ARole: string): string;
  public
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;
    function ChatComplete(const ARequest: TChatCompletionRequest;
      out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;
    function GetLastRunMetrics: TProviderRunMetrics;
    function GetSupportedModels: TArray<string>;
  end;

  /// <summary>Fake TTS provider — returns stub audio metadata.</summary>
  TFakeTTSProvider = class(TInterfacedObject, IDeepFramesTTSProvider)
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

  /// <summary>Fake ASR provider — returns stub word-level timestamps.</summary>
  TFakeASRProvider = class(TInterfacedObject, IDeepFramesASRProvider)
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

{ TFakeLLMProvider }

function TFakeLLMProvider.GetProviderName: string;
begin
  Result := PROVIDER_FAKE;
end;

function TFakeLLMProvider.GetProviderStatus: TProviderStatus;
begin
  Result := psOk;
end;

function TFakeLLMProvider.GetCapabilities: TProviderCapabilities;
begin
  Result := [pcLLM];
end;

function TFakeLLMProvider.GetSupportedModels: TArray<string>;
begin
  Result := ['fake-llm-1.0'];
end;

function TFakeLLMProvider.BuildRoleOutput(const ARole: string): string;
var
  Obj: TJSONObject;
  ShotsArr: TJSONArray;
  ShotObj: TJSONObject;
  AudioObj: TJSONObject;
  VisualObj: TJSONObject;
begin
  if ARole = AGENT_ROLE_SPLITTER then
  begin
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
      Obj.AddPair('chapter_summary', 'Stub chapter summary');
      Obj.AddPair('style_anchor', TJSONObject.Create
        .AddPair('art_style', 'documentary')
        .AddPair('color_palette', TJSONArray.Create.Add('warm').Add('neutral'))
        .AddPair('mood', 'calm'));
      ShotsArr := TJSONArray.Create;
      ShotObj := TJSONObject.Create;
      ShotObj.AddPair('shot_id', 'shot_001');
      ShotObj.AddPair('group_id', 'group_01');
      ShotObj.AddPair('text', 'Stub shot text from splitter.');
      ShotObj.AddPair('duration_sec', TJSONNumber.Create(5.0));
      ShotsArr.AddElement(ShotObj);
      Obj.AddPair('shots', ShotsArr);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  end
  else if ARole = AGENT_ROLE_WORKER then
  begin
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
      Obj.AddPair('shot_id', 'shot_001');
      Obj.AddPair('group_id', 'group_01');
      AudioObj := TJSONObject.Create;
      AudioObj.AddPair('text', 'Stub worker audio text.');
      AudioObj.AddPair('voice', 'default');
      AudioObj.AddPair('emotion', 'neutral');
      AudioObj.AddPair('pace', 1.0);
      AudioObj.AddPair('pitch', 0.0);
      AudioObj.AddPair('instruction', '');
      Obj.AddPair('audio', AudioObj);
      VisualObj := TJSONObject.Create;
      VisualObj.AddPair('background_prompt', 'Documentary warm neutral bg');
      VisualObj.AddPair('target_aspect_ratios', TJSONArray.Create.Add('16:9'));
      VisualObj.AddPair('transition', 'cut');
      Obj.AddPair('visual', VisualObj);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  end
  else if ARole = AGENT_ROLE_ASSEMBLER then
  begin
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
      Obj.AddPair('assembled', True);
      Obj.AddPair('total_duration_sec', TJSONNumber.Create(5.0));
      Obj.AddPair('gaps_filled', TJSONNumber.Create(0));
      Obj.AddPair('continuity_issues', TJSONArray.Create);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  end
  else if ARole = AGENT_ROLE_QA then
  begin
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
      Obj.AddPair('gate', GATE_2);
      Obj.AddPair('gate_result', GATE_RESULT_PASS);
      Obj.AddPair('score', TJSONNumber.Create(0.95));
      Obj.AddPair('coverage_ratio', TJSONNumber.Create(0.97));
      Obj.AddPair('degraded_ratio', TJSONNumber.Create(0.0));
      Obj.AddPair('issues', TJSONArray.Create);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  end
  else if ARole = AGENT_ROLE_STYLE_KEEPER then
  begin
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
      Obj.AddPair('style_consistent', True);
      Obj.AddPair('intra_group_similarity', TJSONNumber.Create(0.92));
      Obj.AddPair('inter_group_similarity', TJSONNumber.Create(0.85));
      Obj.AddPair('color_consistency', True);
      Obj.AddPair('art_style_match', TJSONNumber.Create(0.88));
      Obj.AddPair('warnings', TJSONArray.Create);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  end
  else
    Result := '{}';
end;

function TFakeLLMProvider.ChatComplete(const ARequest: TChatCompletionRequest;
  out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;
var
  ResponseJson: string;
begin
  // System prompt encodes agent role for fake routing
  ResponseJson := BuildRoleOutput(ARequest.SystemPrompt);

  AResult.ResponseJson := ResponseJson;
  AResult.NormalizedJson := ResponseJson;
  AResult.ValidationError := '';
  AResult.RepairCount := 0;
  AResult.FinishReason := 'stop';

  AMetrics.ProviderName := GetProviderName;
  AMetrics.Model := ARequest.Model;
  AMetrics.Capability := CAPABILITY_LLM;
  AMetrics.LatencyMs := 10;
  AMetrics.TokenUsage.PromptTokens := 100;
  AMetrics.TokenUsage.CompletionTokens := 50;
  AMetrics.TokenUsage.TotalTokens := 150;
  AMetrics.RequestId := '';
  AMetrics.ErrorCode := '';
  AMetrics.RetryCount := 0;

  FLastMetrics := AMetrics;
  Result := True;
end;

function TFakeLLMProvider.GetLastRunMetrics: TProviderRunMetrics;
begin
  Result := FLastMetrics;
end;

{ TFakeTTSProvider }

function TFakeTTSProvider.GetProviderName: string;
begin
  Result := PROVIDER_FAKE;
end;

function TFakeTTSProvider.GetProviderStatus: TProviderStatus;
begin
  Result := psOk;
end;

function TFakeTTSProvider.GetCapabilities: TProviderCapabilities;
begin
  Result := [pcTTS];
end;

function TFakeTTSProvider.GetAvailableVoices: TArray<string>;
begin
  Result := ['cixingnansheng', 'wenrounvsheng', 'jizhiqingnian'];
end;

function TFakeTTSProvider.Synthesize(const AText: string; const AVoice,
  AInstruction, AOutputFormat: string; out AResult: TTtsSynthesisResult;
  out AMetrics: TProviderRunMetrics): Boolean;
var
  CharCount: Integer;
begin
  CharCount := Length(AText);
  if CharCount > 200 then
    CharCount := 200;

  AResult.Format := AOutputFormat;
  if AResult.Format = '' then
    AResult.Format := 'wav';
  AResult.SampleRate := 24000;
  AResult.Channels := 1;
  AResult.DurationSec := CharCount * 0.0833; // ~12 chars/sec for fake TTS
  AResult.Voice := AVoice;
  if AResult.Voice = '' then
    AResult.Voice := 'cixingnansheng';
  AResult.Instruction := AInstruction;
  AResult.CharCount := CharCount;
  AResult.OutputUri := 'audio/fake/tts_output.' + AResult.Format;
  AResult.OutputSizeBytes := Round(AResult.DurationSec * AResult.SampleRate * AResult.Channels * 2);

  AMetrics.ProviderName := GetProviderName;
  AMetrics.Model := 'stepaudio-2.5-tts';
  AMetrics.Capability := CAPABILITY_TTS;
  AMetrics.LatencyMs := 50;
  AMetrics.TokenUsage := Default(TTokenUsage);
  AMetrics.RequestId := '';
  AMetrics.ErrorCode := '';
  AMetrics.RetryCount := 0;

  FLastMetrics := AMetrics;
  Result := True;
end;

function TFakeTTSProvider.GetLastRunMetrics: TProviderRunMetrics;
begin
  Result := FLastMetrics;
end;

{ TFakeASRProvider }

function TFakeASRProvider.GetProviderName: string;
begin
  Result := PROVIDER_FAKE;
end;

function TFakeASRProvider.GetProviderStatus: TProviderStatus;
begin
  Result := psOk;
end;

function TFakeASRProvider.GetCapabilities: TProviderCapabilities;
begin
  Result := [pcASR];
end;

function TFakeASRProvider.Transcribe(const AAudioUri: string;
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
  AMetrics.LatencyMs := 80;
  AMetrics.TokenUsage := Default(TTokenUsage);
  AMetrics.RequestId := '';
  AMetrics.ErrorCode := '';
  AMetrics.RetryCount := 0;

  FLastMetrics := AMetrics;
  Result := True;
end;

function TFakeASRProvider.GetLastRunMetrics: TProviderRunMetrics;
begin
  Result := FLastMetrics;
end;

end.