unit DeepFrames.Provider.Intf;

/// <summary>
/// Provider interfaces for DeepFrames.
///
/// Design rules (from docs/02.api-阶跃星辰集成-step-plan-api.md):
/// 1. Per-capability interfaces — Chat/TTS/ASR use different capability routes,
///    separate interfaces prevent misuse.
/// 2. Business layer never calls provider-specific HTTP directly.
/// 3. API Keys are loaded from DeepBase.Security by the implementation, not the interface.
/// 4. Fake provider is preserved as a regression test fixture.
///
/// All providers return structured results via the types declared in
/// DeepFrames.Provider.Types. Consumers never receive provider-specific raw output.
/// </summary>

interface

uses
  DeepFrames.Domain.Types,
  DeepFrames.Provider.Types;

type
  /// <summary>LLM provider (Chat completion, structured JSON output).</summary>
  IDeepFramesLLMProvider = interface
    ['{E8B7A1D2-3C4F-5E6A-7890-ABCDEF123456}']
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;

    /// <summary>
    /// Execute a chat completion with structured output.
    /// Returns False if the call failed (network, auth, rate-limit).
    /// On success, fills Result and Metrics.
    /// </summary>
    function ChatComplete(const ARequest: TChatCompletionRequest;
      out AResult: TChatCompletionResult; out AMetrics: TProviderRunMetrics): Boolean;

    /// <summary>Return the most recent call metrics (for prompt_run recording).</summary>
    function GetLastRunMetrics: TProviderRunMetrics;

    /// <summary>Return the list of supported models for this provider.</summary>
    function GetSupportedModels: TArray<string>;
  end;

  /// <summary>TTS provider (text-to-speech synthesis).</summary>
  IDeepFramesTTSProvider = interface
    ['{A1C2E3D4-5B6F-789A-BCDE-F01234567890}']
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;

    /// <summary>
    /// Synthesize speech from text.
    /// OutputUri is set to the saved audio file path.
    /// Returns False on failure (network, auth, 451, etc.).
    /// </summary>
    function Synthesize(const AText: string; const AVoice, AInstruction: string;
      const AOutputFormat: string; out AResult: TTtsSynthesisResult;
      out AMetrics: TProviderRunMetrics): Boolean;

    /// <summary>Return available voice IDs.</summary>
    function GetAvailableVoices: TArray<string>;

    /// <summary>Return the most recent call metrics.</summary>
    function GetLastRunMetrics: TProviderRunMetrics;
  end;

  /// <summary>ASR provider (speech-to-text with word-level timestamps).</summary>
  IDeepFramesASRProvider = interface
    ['{F9E8D7C6-5B4A-3210-FEDC-BA9876543210}']
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;

    /// <summary>
    /// Transcribe an audio file.
    /// Returns word-level timestamps for subtitle sync.
    /// Supports SSE streaming internally; consumer only sees final result.
    /// </summary>
    function Transcribe(const AAudioUri: string;
      out AResult: TAsrTranscriptionResult;
      out AMetrics: TProviderRunMetrics): Boolean;

    /// <summary>Return the most recent call metrics.</summary>
    function GetLastRunMetrics: TProviderRunMetrics;
  end;

  /// <summary>Optional factory for creating providers (used by Registry).</summary>
  IDeepFramesProviderFactory = interface
    ['{B1C2D3E4-F5A6-7890-ABCD-EF1234567890}']
    function CreateLLMProvider(const AProviderName: string): IDeepFramesLLMProvider;
    function CreateTTSProvider(const AProviderName: string): IDeepFramesTTSProvider;
    function CreateASRProvider(const AProviderName: string): IDeepFramesASRProvider;
  end;

  /// <summary>Image generation provider (backgrounds, covers, scene art).</summary>
  IDeepFramesImageProvider = interface
    ['{D4E5F6A7-B8C9-0123-DEF4-567890ABCDEF}']
    function GetProviderName: string;
    function GetProviderStatus: TProviderStatus;
    function GetCapabilities: TProviderCapabilities;

    /// <summary>
    /// Generate images from a prompt.
    /// Returns one or more images saved to the output directory.
    /// </summary>
    function Generate(const ARequest: TImageGenRequest;
      out AResults: TArray<TImageGenResult>;
      out AMetrics: TProviderRunMetrics): Boolean;

    /// <summary>Return available image styles.</summary>
    function GetAvailableStyles: TArray<string>;

    /// <summary>Return the most recent call metrics.</summary>
    function GetLastRunMetrics: TProviderRunMetrics;
  end;

const
  PROVIDER_FAKE = 'fake';
  PROVIDER_STEPFUN = 'stepfun';

implementation

end.