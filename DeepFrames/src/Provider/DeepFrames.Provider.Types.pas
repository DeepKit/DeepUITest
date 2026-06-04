unit DeepFrames.Provider.Types;

/// <summary>
/// Shared types consumed by all provider interfaces and implementations.
/// Provider-specific types (TTS metadata, ASR word timestamps, etc.) live here
/// so that consumers don't need to know which provider produced them.
/// </summary>

interface

type
  /// <summary>LLM chat completion result — token usage.</summary>
  TTokenUsage = record
    PromptTokens: Integer;
    CompletionTokens: Integer;
    TotalTokens: Integer;
  end;

  /// <summary>Per-call metrics captured by every provider for cost/quality tracking.</summary>
  TProviderRunMetrics = record
    ProviderName: string;
    Model: string;
    Capability: string;
    LatencyMs: Integer;
    TokenUsage: TTokenUsage;
    RequestId: string;
    ErrorCode: string;
    RetryCount: Integer;
  end;

  /// <summary>Set of capabilities a provider advertises.</summary>
  TProviderCapabilities = set of (pcLLM, pcTTS, pcASR, pcImageGen, pcImageEdit);

  /// <summary>Result of a TTS synthesis call (returned by any TTS provider).</summary>
  TTtsSynthesisResult = record
    Format: string;          // wav / mp3 / opus / pcm
    SampleRate: Integer;     // Hz (typically 24000)
    Channels: Integer;       // 1 or 2
    DurationSec: Double;
    Voice: string;
    Instruction: string;
    CharCount: Integer;
    OutputUri: string;       // path to saved audio file
    OutputSizeBytes: Int64;
  end;

  /// <summary>Single word-level timestamp from ASR.</summary>
  TAsrWordTimestamp = record
    Word: string;
    StartSec: Double;
    EndSec: Double;
    Confidence: Double;
  end;

  /// <summary>Result of an ASR transcription call.</summary>
  TAsrTranscriptionResult = record
    DurationSec: Double;
    Words: TArray<TAsrWordTimestamp>;
  end;

  /// <summary>LLM chat completion input.</summary>
  TChatCompletionRequest = record
    SystemPrompt: string;
    UserMessage: string;
    OutputSchemaJson: string;   // JSON Schema string for structured output validation
    Model: string;
    Temperature: Double;
    MaxTokens: Integer;
    AgentRole: string;          // e.g. 'splitter', 'worker' — used by fake provider routing
  end;

  /// <summary>LLM chat completion output.</summary>
  TChatCompletionResult = record
    ResponseJson: string;       // raw JSON response
    NormalizedJson: string;     // schema-validated / repaired JSON
    ValidationError: string;
    RepairCount: Integer;
    FinishReason: string;
  end;

  /// <summary>Provider health / status.</summary>
  TProviderStatus = (
    psUnknown,
    psOk,
    psDegraded,
    psUnavailable
  );

  /// <summary>Image generation request.</summary>
  TImageGenRequest = record
    Prompt: string;
    NegativePrompt: string;
    Width: Integer;
    Height: Integer;
    NumImages: Integer;
    Style: string;       // e.g. 'realistic', 'anime', 'illustration'
  end;

  /// <summary>Image generation result (one image).</summary>
  TImageGenResult = record
    OutputUri: string;        // saved file path
    OutputSizeBytes: Int64;
    Width: Integer;
    Height: Integer;
    Format: string;           // png / jpg / webp
    Seed: Integer;
    RevisedPrompt: string;    // model-optimized version of prompt
  end;

function ProviderCapabilitiesToStr(const Caps: TProviderCapabilities): string;
function ProviderStatusToStr(const Status: TProviderStatus): string;

implementation

uses
  System.SysUtils;

function ProviderCapabilitiesToStr(const Caps: TProviderCapabilities): string;
begin
  Result := '';
  if pcLLM in Caps then
    Result := Result + 'LLM,';
  if pcTTS in Caps then
    Result := Result + 'TTS,';
  if pcASR in Caps then
    Result := Result + 'ASR,';
  if pcImageGen in Caps then
    Result := Result + 'ImageGen,';
  if pcImageEdit in Caps then
    Result := Result + 'ImageEdit,';
  if Result <> '' then
    SetLength(Result, Length(Result) - 1)
  else
    Result := 'none';
end;

function ProviderStatusToStr(const Status: TProviderStatus): string;
begin
  case Status of
    psUnknown:     Result := 'unknown';
    psOk:          Result := 'ok';
    psDegraded:    Result := 'degraded';
    psUnavailable: Result := 'unavailable';
  else
    Result := 'unknown';
  end;
end;

end.