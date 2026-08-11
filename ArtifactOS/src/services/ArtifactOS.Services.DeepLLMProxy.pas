{ ============================================================================
  ArtifactOS.Services.DeepLLMProxy

  LLM call routing for ArtifactOS pipeline stages.
  Wraps DeepBase.LLM with ArtifactOS-specific config names and tier routing:
    - ES (rule-based):        no LLM call, pure Delphi rules
    - semi-ES (light check):  small model (Haiku/GPT-4o-mini)
    - NES (deep evaluation):  strong model (Sonnet/GPT-4o)
    - generation (writing):   strong model (Sonnet/GPT-4o)
    - delegate (quick write): strong model (Sonnet/GPT-4o)
    - request_more (multi):   small model (Haiku/GPT-4o-mini)

  Config names are stored in the ArtifactOS ConfigDB (SQLite) via DeepBase.LLM
  convention.  If a named config doesn't exist yet, the proxy falls back to the
  'Default' config with the appropriate parameters.

  Version: 0.1
  ============================================================================ }

unit ArtifactOS.Services.DeepLLMProxy;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  DeepBase.LLM;

type
  /// <summary>
  /// ArtifactOS LLM usage tiers — determines model choice and cost envelope.
  /// </summary>
  TAOSLLMTier = (
    aostES,          // Rule-based, no LLM
    aostSemiES,      // Light check — small model
    aostNES,         // Deep evaluation — strong model
    aostGeneration,  // Content generation — strong model
    aostDelegate,    // Quick full article — strong model
    aostRequestMore, // Multi-version drafts — small model (high volume)
    aostStrategy     // Strategy recommendation — strong model
  );

  /// <summary>
  /// Result of a single LLM call with ArtifactOS metadata.
  /// </summary>
  TAOSLLMResult = record
    Success: Boolean;
    Content: string;
    Tier: TAOSLLMTier;
    InputTokens: Integer;
    OutputTokens: Integer;
    DurationMs: Int64;
    ModelUsed: string;
    ConfigName: string;
    ErrorCode: string;
    ErrorMessage: string;
    procedure Init;
  end;

  /// <summary>
  /// LLM call proxy for ArtifactOS.
  /// Routes calls through DeepBase.LLM with tier-appropriate config names.
  /// </summary>
  TArtifactOSLLMProxy = class
  private
    class var FInstance: TArtifactOSLLMProxy;
    class var FLock: TObject;  // guards Instance lazy-init

    /// <summary>Map tier → DeepBase.LLM config name.</summary>
    class function ConfigNameForTier(const ATier: TAOSLLMTier): string;
    /// <summary>Map tier → fallback model name if no config found.</summary>
    class function FallbackModelForTier(const ATier: TAOSLLMTier): string;
    /// <summary>Map tier → temperature.</summary>
    class function TemperatureForTier(const ATier: TAOSLLMTier): Double;
    /// <summary>Map tier → max output tokens.</summary>
    class function MaxTokensForTier(const ATier: TAOSLLMTier): Integer;
  public
    /// <summary>Singleton access. Creates on first call.</summary>
    class function Instance: TArtifactOSLLMProxy;

    /// <summary>
    /// Execute a chat completion for the given tier.
    /// System prompt is optional (tier default used if empty).
    /// Returns a structured result.
    /// </summary>
    function Chat(const ATier: TAOSLLMTier;
      const AUserPrompt: string;
      const ASystemPrompt: string = '';
      const AMaxTokens: Integer = 0): TAOSLLMResult;

    /// <summary>
    /// Execute a chat completion with full message history (multi-turn).
    /// </summary>
    function ChatMultiTurn(const ATier: TAOSLLMTier;
      const AMessages: TLLMMessages;
      const AMaxTokens: Integer = 0): TAOSLLMResult;

    /// <summary>
    /// Check if the LLM backend is available (config loaded, API key set).
    /// </summary>
    function IsAvailable: Boolean;

    /// <summary>
    /// Get tier display name for logging.
    /// </summary>
    class function TierDisplayName(const ATier: TAOSLLMTier): string;
  end;

  /// <summary>Convenience alias for singleton access.</summary>
function ArtifactOS_LLM: TArtifactOSLLMProxy;

implementation

uses
  System.SyncObjs,
  DeepBase.Config;

function ArtifactOS_LLM: TArtifactOSLLMProxy;
begin
  Result := TArtifactOSLLMProxy.Instance;
end;

{ TAOSLLMResult }

procedure TAOSLLMResult.Init;
begin
  Success := False;
  Content := '';
  Tier := aostES;
  InputTokens := 0;
  OutputTokens := 0;
  DurationMs := 0;
  ModelUsed := '';
  ConfigName := '';
  ErrorCode := '';
  ErrorMessage := '';
end;

{ TArtifactOSLLMProxy }

class function TArtifactOSLLMProxy.ConfigNameForTier(const ATier: TAOSLLMTier): string;
begin
  case ATier of
    aostES:          Result := 'ArtifactOS_ES';         // Should never be called
    aostSemiES:      Result := 'ArtifactOS_SemiES';
    aostNES:         Result := 'ArtifactOS_NES';
    aostGeneration:  Result := 'ArtifactOS_Generation';
    aostDelegate:    Result := 'ArtifactOS_Delegate';
    aostRequestMore: Result := 'ArtifactOS_RequestMore';
    aostStrategy:    Result := 'ArtifactOS_Strategy';
  else
    Result := 'Default';
  end;
end;

class function TArtifactOSLLMProxy.FallbackModelForTier(const ATier: TAOSLLMTier): string;
begin
  case ATier of
    aostES:          Result := '';  // No LLM
    aostSemiES,
    aostRequestMore: Result := 'claude-haiku-4-5-20251001';
    aostNES,
    aostGeneration,
    aostDelegate,
    aostStrategy:    Result := 'claude-sonnet-4-6';
  else
    Result := 'claude-sonnet-4-6';
  end;
end;

class function TArtifactOSLLMProxy.TemperatureForTier(const ATier: TAOSLLMTier): Double;
begin
  case ATier of
    aostES:          Result := 0.0;   // N/A
    aostSemiES:      Result := 0.1;   // Deterministic checking
    aostNES:         Result := 0.2;   // Low-variance evaluation
    aostGeneration:  Result := 0.7;   // Creative writing
    aostDelegate:    Result := 0.5;   // Balanced quick articles
    aostRequestMore: Result := 0.8;   // Diverse multi-versions
    aostStrategy:    Result := 0.3;   // Analytical recommendations
  else
    Result := 0.5;
  end;
end;

class function TArtifactOSLLMProxy.MaxTokensForTier(const ATier: TAOSLLMTier): Integer;
begin
  case ATier of
    aostES:          Result := 0;     // No LLM
    aostSemiES:      Result := 1024;  // Short evaluations
    aostNES:         Result := 2048;  // Detailed assessments
    aostGeneration:  Result := 8192;  // Full articles
    aostDelegate:    Result := 8192;  // Full articles
    aostRequestMore: Result := 4096;  // Multiple shorter versions
    aostStrategy:    Result := 2048;  // Strategy recommendations
  else
    Result := 2048;
  end;
end;

class function TArtifactOSLLMProxy.TierDisplayName(const ATier: TAOSLLMTier): string;
begin
  case ATier of
    aostES:          Result := 'ES (rule-based)';
    aostSemiES:      Result := 'Semi-ES (light LLM)';
    aostNES:         Result := 'NES (deep LLM)';
    aostGeneration:  Result := 'Generation';
    aostDelegate:    Result := 'Delegate';
    aostRequestMore: Result := 'RequestMore';
    aostStrategy:    Result := 'Strategy';
  else
    Result := 'Unknown';
  end;
end;

class function TArtifactOSLLMProxy.Instance: TArtifactOSLLMProxy;
begin
  // Thread-safe lazy init with double-checked locking
  if FInstance = nil then
  begin
    TMonitor.Enter(TArtifactOSLLMProxy.FLock);
    try
      if FInstance = nil then
        FInstance := TArtifactOSLLMProxy.Create;
    finally
      TMonitor.Exit(TArtifactOSLLMProxy.FLock);
    end;
  end;
  Result := FInstance;
end;

function TArtifactOSLLMProxy.Chat(const ATier: TAOSLLMTier;
  const AUserPrompt, ASystemPrompt: string;
  const AMaxTokens: Integer): TAOSLLMResult;
var
  Messages: TLLMMessages;
  SysPrompt: string;
begin
  Result.Init;
  Result.Tier := ATier;

  if ATier = aostES then
  begin
    // ES is rule-based, no LLM call
    Result.Success := True;
    Result.Content := '';
    Result.ConfigName := 'rule-based';
    Result.ModelUsed := 'none';
    Exit;
  end;

  SysPrompt := ASystemPrompt;
  if SysPrompt = '' then
    SysPrompt := 'You are an expert assistant for the ArtifactOS content production system.';

  SetLength(Messages, 2);
  Messages[0] := TLLMMessage.System(SysPrompt);
  Messages[1] := TLLMMessage.User(AUserPrompt);

  Result := ChatMultiTurn(ATier, Messages, AMaxTokens);
end;

function TArtifactOSLLMProxy.ChatMultiTurn(const ATier: TAOSLLMTier;
  const AMessages: TLLMMessages;
  const AMaxTokens: Integer): TAOSLLMResult;
var
  LLM: TDeepBaseLLM;
  ChatResp: TLLMChatResponse;
  Config: TLLMConfig;
  ConfigName: string;
  Ok: Boolean;
begin
  Result.Init;
  Result.Tier := ATier;

  if ATier = aostES then
  begin
    Result.Success := True;
    Result.Content := '';
    Result.ConfigName := 'rule-based';
    Result.ModelUsed := 'none';
    Exit;
  end;

  // Per-call LLM instance for thread safety — TDeepBaseLLM is not documented
  // as thread-safe, and concurrent pipelines (GenerationService, QualityGate,
  // TopicFunnel, TheoryWeave) may call Chat simultaneously.
  LLM := TDeepBaseLLM.Create(nil);
  try
    ConfigName := ConfigNameForTier(ATier);
    Result.ConfigName := ConfigName;

    // Try loading the tier-specific config
    Config := LLM.GetConfig(ConfigName);
    if not Config.IsEnabled then
    begin
      // Fallback to Default config
      ConfigName := 'Default';
      Config := LLM.GetConfig(ConfigName);
      if not Config.IsEnabled then
      begin
        Result.Success := False;
        Result.ErrorCode := 'NO_LLM_CONFIG';
        Result.ErrorMessage := Format(
          'No LLM config found for tier %s and no Default config available.',
          [TierDisplayName(ATier)]);
        Exit;
      end;
      Result.ConfigName := ConfigName + '+' + TierDisplayName(ATier);
    end;

    // Call via ChatWithMessages (TDeepBaseLLM's multi-turn API)
    Ok := LLM.ChatWithMessages(AMessages, ChatResp, ConfigName);

    Result.Success := Ok and ChatResp.Success;
    Result.Content := ChatResp.Content;
    Result.InputTokens := ChatResp.InputTokens;
    Result.OutputTokens := ChatResp.OutputTokens;
    Result.DurationMs := ChatResp.DurationMs;
    Result.ModelUsed := Config.Model;
    if not Ok then
    begin
      Result.ErrorCode := 'CHAT_FAILED';
      Result.ErrorMessage := 'LLM.ChatWithMessages returned False';
    end
    else if not ChatResp.Success then
    begin
      Result.ErrorCode := ChatResp.ErrorCode;
      Result.ErrorMessage := ChatResp.ErrorMessage;
    end;
  finally
    LLM.Free;
  end;
end;

function TArtifactOSLLMProxy.IsAvailable: Boolean;
var
  LLM: TDeepBaseLLM;
  Config: TLLMConfig;
begin
  Result := False;
  // Per-call instance for thread safety
  LLM := TDeepBaseLLM.Create(nil);
  try
    Config := LLM.GetConfig('Default');
    Result := Config.IsEnabled and (Config.ApiKey <> '');
  finally
    LLM.Free;
  end;
end;

initialization
  TArtifactOSLLMProxy.FLock := TObject.Create;

finalization
  if Assigned(TArtifactOSLLMProxy.FInstance) then
    FreeAndNil(TArtifactOSLLMProxy.FInstance);
  TArtifactOSLLMProxy.FLock.Free;

end.
