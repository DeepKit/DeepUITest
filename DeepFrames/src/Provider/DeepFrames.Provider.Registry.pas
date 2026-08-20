unit DeepFrames.Provider.Registry;

/// <summary>
/// Singleton registry that maps capability → provider instance.
///
/// By default, all providers are "fake" (returns deterministic stub data).
/// Call SwitchTo(providerName) to activate a different provider (e.g. 'stepfun').
///
/// Thread-safety: not required for Phase 1-2 — all calls happen on VCL main thread.
/// Will be hardened in Phase 3 when worker threads are introduced.
/// </summary>

interface

uses
  System.SyncObjs,
  DeepFrames.Provider.Intf;

type
  TProviderRegistry = class
  private
    class var FInstance: TProviderRegistry;
    class var FLock: TCriticalSection;
    class destructor DestroyClass;

  private
    FLLMProvider: IDeepFramesLLMProvider;
    FTTSProvider: IDeepFramesTTSProvider;
    FASRProvider: IDeepFramesASRProvider;
    FImageProvider: IDeepFramesImageProvider;
    FVideoProvider: IDeepFramesVideoProvider;
    FActiveProviderName: string;
    FInitialized: Boolean;

    procedure InitializeDefaults;
    procedure CreateFakeProviders;
    procedure CreateStepFunProviders;
    procedure CreateAgnesProviders;
    /// <summary>StepFun-Mix chain: StepFun(LLM/TTS/ASR/Image) + Agnes(Video)
    /// as primaries, with WiseGateway(LLM) + Baidu(TTS/ASR) + Agnes(Image)
    /// as failover backups. Video stays Agnes-only (no alternative).</summary>
    procedure CreateStepFunMixProviders;
    /// <summary>WiseGateway-only chain: all LLM via WiseGateway gateway,
    /// StepFun for TTS/ASR, Agnes for Image/Video.</summary>
    procedure CreateWiseGatewayProviders;
    /// <summary>Production chain: Agnes(LLM/Image/Video) + Baidu(TTS/ASR) as
    /// primaries, Gemini(LLM/TTS/ASR) as failover backup. Each capability is
    /// wrapped in a TFailoverXxxProvider so a primary failure transparently
    /// falls through to Gemini.</summary>
    procedure CreateProductionProviders;
    /// <summary>Gemini-only chain (pure Google, all three capabilities go to
    /// Gemini). Used for the 'gemini' switch and real-integration RI6-RI8.</summary>
    procedure CreateGeminiProviders;
    procedure CreateProviders(const AProviderName: string);
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Singleton accessor.</summary>
    class function Instance: TProviderRegistry; static;

    /// <summary>Current active LLM provider. Never nil after first access.</summary>
    function LLMProvider: IDeepFramesLLMProvider;

    /// <summary>Current active TTS provider. Never nil after first access.</summary>
    function TTSProvider: IDeepFramesTTSProvider;

    /// <summary>Current active ASR provider. Never nil after first access.</summary>
    function ASRProvider: IDeepFramesASRProvider;

    /// <summary>Current active Image provider. Never nil after first access.</summary>
    function ImageProvider: IDeepFramesImageProvider;

    /// <summary>Current active Video provider. May be nil if provider doesn't support video.</summary>
    function VideoProvider: IDeepFramesVideoProvider;

    /// <summary>Name of the currently active provider set (e.g. 'fake', 'stepfun', 'agnes').
    function ActiveProviderName: string;
    function IsInitialized: Boolean;

    /// <summary>
    /// Switch all providers to another implementation.
    /// AProviderName is case-insensitive. Known values: 'fake', 'stepfun'.
    /// Raises ENotSupportedException for unknown names.
    /// </summary>
    procedure SwitchTo(const AProviderName: string);
  end;

implementation

uses
  System.SysUtils,
  DeepFrames.Provider.Fake,
  DeepFrames.Provider.StepFun,
  DeepFrames.Provider.Agnes,
  DeepFrames.Provider.Baidu,
  DeepFrames.Provider.Gemini,
  DeepFrames.Provider.WiseGateway,
  DeepFrames.Provider.Failover,
  DeepFrames.Shared.Consts;

class destructor TProviderRegistry.DestroyClass;
begin
  // FInstance + FLock freed in finalization (DestroyClass is not reliably
  // invoked without a paired class constructor).
  FreeAndNil(FInstance);
end;

constructor TProviderRegistry.Create;
begin
  inherited;
  FInitialized := False;
  FActiveProviderName := '';
end;

destructor TProviderRegistry.Destroy;
begin
  FLLMProvider := nil;
  FTTSProvider := nil;
  FASRProvider := nil;
  FImageProvider := nil;
  FVideoProvider := nil;
  inherited;
end;

class function TProviderRegistry.Instance: TProviderRegistry;
begin
  // Phase 3 hardening: double-checked locking so concurrent first-callers
  // (worker threads) don't race to create two instances. The outer nil-check
  // is the fast path (no lock once initialized); the inner block serializes
  // the one-time create+init. FLock is created in the unit's initialization
  // section (single-threaded at unit-load time, so no race on the lock itself).
  if FInstance = nil then
  begin
    FLock.Enter;
    try
      if FInstance = nil then
      begin
        FInstance := TProviderRegistry.Create;
        FInstance.InitializeDefaults;
      end;
    finally
      FLock.Leave;
    end;
  end;
  Result := FInstance;
end;

procedure TProviderRegistry.InitializeDefaults;
begin
  // Guarded by the same FLock as Instance (double-check) so a direct call
  // from outside Instance can't race the create-path. The fast-path nil-check
  // on FInitialized avoids the lock once initialized.
  //
  // Default chain is 'production' (Agnes/Baidu primary + Gemini failover) so a
  // fresh install with configured keys runs real APIs immediately. Tests and
  // offline dev call SwitchTo(PROVIDER_FAKE) explicitly — they never rely on
  // the default, so switching the default here does not affect them.
  if FInitialized then
    Exit;
  FLock.Enter;
  try
    if FInitialized then
      Exit;
    // 2026-07-14: switched back to Production (Agnes/Baidu primary + Gemini failover).
    // The Agnes LLM provider now points Agnes.LLMBaseUrl at the fccy relay
    // (http://127.0.0.1:8000/v1) with its own agnes_llm_api_key secret, so LLM
    // calls hit a real model instead of falling through to a stub.
    // StepFun-Mix (StepFun primary via DeepBase LLMAdmin) stays available via
    // SwitchTo('stepfun') for anyone who has LLMAdmin configured.
    CreateProductionProviders;
    // CreateStepFunMixProviders;  // 2026-07-12: StepFun primary + failover
    FInitialized := True;
  finally
    FLock.Leave;
  end;
end;

procedure TProviderRegistry.CreateFakeProviders;
begin
  FLLMProvider := TFakeLLMProvider.Create;
  FTTSProvider := TFakeTTSProvider.Create;
  FASRProvider := TFakeASRProvider.Create;
  FImageProvider := TFakeImageProvider.Create;
  FVideoProvider := nil;
  FActiveProviderName := PROVIDER_FAKE;
end;

procedure TProviderRegistry.CreateStepFunProviders;
begin
  // StepFun covers LLM/TTS/ASR/Image (step_plan subscription active);
  // Video is handled by Agnes (StepFun has no video generation API).
  FLLMProvider := TStepFunLLMProvider.Create;
  FTTSProvider := TStepFunTTSProvider.Create;
  FASRProvider := TStepFunASRProvider.Create;
  FImageProvider := TStepFunImageProvider.Create;
  FVideoProvider := TAgnesVideoProvider.Create; // StepFun has no video API
  FActiveProviderName := PROVIDER_STEPFUN;
end;

procedure TProviderRegistry.CreateAgnesProviders;
begin
  // Production provider set (2026-07-09): Agnes covers LLM/Image/Video (real
  // HTTP impls already shipped, agnes_key.txt ready); Baidu covers TTS/ASR
  // (text2audio / server_api, real HTTP added this round). StepFun has no
  // active subscription and is retired to a fallback option — kept as the
  // separate 'stepfun' switch for when a subscription is reactivated.
  FLLMProvider := TAgnesLLMProvider.Create;
  FTTSProvider := TBaiduTTSProvider.Create;
  FASRProvider := TBaiduASRProvider.Create;
  FImageProvider := TAgnesImageProvider.Create;
  FVideoProvider := TAgnesVideoProvider.Create;
  FActiveProviderName := PROVIDER_AGNES;
end;

procedure TProviderRegistry.CreateProductionProviders;
begin
  // Production chain (2026-07-09): each capability wraps a primary + Gemini
  // failover backup. A primary returning False (network/auth/429) transparently
  // falls through to Gemini. Image/Video have no Gemini backup (Veo free-tier
  // exhausted) so they stay Agnes-only — if Agnes image/video fails, the chain
  // has no backup and surfaces the failure (acceptable: no alternative exists).
  //
  // Switching is by Boolean return value only (see Failover.pas design note):
  // an unconfigured primary in stub mode returns True and short-circuits the
  // chain, so Gemini is only reached when the primary's real API call fails.
  FLLMProvider := TFailoverLLMProvider.Create(
    [TAgnesLLMProvider.Create, TGeminiLLMProvider.Create]);
  FTTSProvider := TFailoverTTSProvider.Create(
    [TBaiduTTSProvider.Create, TGeminiTTSProvider.Create]);
  FASRProvider := TFailoverASRProvider.Create(
    [TBaiduASRProvider.Create, TGeminiASRProvider.Create]);
  FImageProvider := TAgnesImageProvider.Create;   // no Gemini image backup
  FVideoProvider := TAgnesVideoProvider.Create;   // no Gemini video backup
  FActiveProviderName := 'production';
end;

procedure TProviderRegistry.CreateGeminiProviders;
begin
  // Pure Gemini chain — all three capabilities route to Google Gemini.
  // Used for the 'gemini' switch and the real-integration RI6-RI8 tests.
  // Image/Video remain Agnes (Gemini image is Imagen via separate endpoint,
  // Veo video is 429-exhausted on the test key) so this switch is not a full
  // "all-Google" set; it targets the LLM/TTS/ASR trio Gemini covers.
  FLLMProvider := TGeminiLLMProvider.Create;
  FTTSProvider := TGeminiTTSProvider.Create;
  FASRProvider := TGeminiASRProvider.Create;
  FImageProvider := TAgnesImageProvider.Create;
  FVideoProvider := TAgnesVideoProvider.Create;
  FActiveProviderName := PROVIDER_GEMINI;
end;

procedure TProviderRegistry.CreateStepFunMixProviders;
begin
  // StepFun-Mix chain (2026-07-12): StepFun as primary for LLM/TTS/ASR/Image,
  // with WiseGateway(LLM) + Baidu(TTS/ASR) + Agnes(Image) as failover backups.
  // Video stays Agnes-only (no alternative).
  //
  // WiseGateway provides LLM via local gateway with automatic failover across
  // multiple providers (stepfun, deepseek, bailian, fccy, xunfei).
  FLLMProvider := TFailoverLLMProvider.Create(
    [TStepFunLLMProvider.Create, TWiseGatewayLLMProvider.Create]);
  FTTSProvider := TFailoverTTSProvider.Create(
    [TStepFunTTSProvider.Create, TBaiduTTSProvider.Create]);
  FASRProvider := TFailoverASRProvider.Create(
    [TStepFunASRProvider.Create, TBaiduASRProvider.Create]);
  FImageProvider := TAgnesImageProvider.Create;  // StepFun image not yet wired; use Agnes directly
  FVideoProvider := TAgnesVideoProvider.Create;
  FActiveProviderName := PROVIDER_STEPFUN_MIX;
end;

procedure TProviderRegistry.CreateWiseGatewayProviders;
begin
  // WiseGateway chain: all LLM via WiseGateway gateway (local proxy with
  // automatic failover), StepFun for TTS/ASR, Agnes for Image/Video.
  FLLMProvider := TWiseGatewayLLMProvider.Create;
  FTTSProvider := TStepFunTTSProvider.Create;
  FASRProvider := TStepFunASRProvider.Create;
  FImageProvider := TAgnesImageProvider.Create;
  FVideoProvider := TAgnesVideoProvider.Create;
  FActiveProviderName := PROVIDER_WISEGATEWAY;
end;

procedure TProviderRegistry.CreateProviders(const AProviderName: string);
begin
  if SameText(AProviderName, PROVIDER_FAKE) then
    CreateFakeProviders
  else if SameText(AProviderName, PROVIDER_STEPFUN) then
    CreateStepFunProviders
  else if SameText(AProviderName, PROVIDER_AGNES) then
    CreateAgnesProviders
  else if SameText(AProviderName, 'production') then
    CreateProductionProviders
  else if SameText(AProviderName, PROVIDER_GEMINI) then
    CreateGeminiProviders
  else if SameText(AProviderName, PROVIDER_STEPFUN_MIX) then
    CreateStepFunMixProviders
  else if SameText(AProviderName, PROVIDER_WISEGATEWAY) then
    CreateWiseGatewayProviders
  else
    raise ENotSupportedException.CreateFmt(
      'Unknown provider: %s. Supported: %s, %s, %s, production, %s, %s, %s',
      [AProviderName, PROVIDER_FAKE, PROVIDER_STEPFUN, PROVIDER_AGNES,
       PROVIDER_GEMINI, PROVIDER_STEPFUN_MIX, PROVIDER_WISEGATEWAY]);
end;

procedure TProviderRegistry.SwitchTo(const AProviderName: string);
begin
  if SameText(FActiveProviderName, AProviderName) then
    Exit;
  // Release old providers before creating new ones
  FLLMProvider := nil;
  FTTSProvider := nil;
  FASRProvider := nil;
  FImageProvider := nil;
  FVideoProvider := nil;
  CreateProviders(AProviderName);
end;

function TProviderRegistry.LLMProvider: IDeepFramesLLMProvider;
begin
  InitializeDefaults;
  Result := FLLMProvider;
end;

function TProviderRegistry.TTSProvider: IDeepFramesTTSProvider;
begin
  InitializeDefaults;
  Result := FTTSProvider;
end;

function TProviderRegistry.ASRProvider: IDeepFramesASRProvider;
begin
  InitializeDefaults;
  Result := FASRProvider;
end;

function TProviderRegistry.ImageProvider: IDeepFramesImageProvider;
begin
  InitializeDefaults;
  Result := FImageProvider;
end;

function TProviderRegistry.VideoProvider: IDeepFramesVideoProvider;
begin
  InitializeDefaults;
  Result := FVideoProvider;
end;

function TProviderRegistry.ActiveProviderName: string;
begin
  Result := FActiveProviderName;
end;

function TProviderRegistry.IsInitialized: Boolean;
begin
  Result := FInitialized;
end;

initialization
  // Created at unit-load (single-threaded) so Instance's double-checked lock
  // never sees a nil FLock. Freed in finalization.
  TProviderRegistry.FLock := TCriticalSection.Create;

finalization
  FreeAndNil(TProviderRegistry.FInstance);
  FreeAndNil(TProviderRegistry.FLock);

end.