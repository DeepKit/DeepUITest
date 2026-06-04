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
  DeepFrames.Provider.Intf;

type
  TProviderRegistry = class
  private
    class var FInstance: TProviderRegistry;
    class destructor DestroyClass;

  private
    FLLMProvider: IDeepFramesLLMProvider;
    FTTSProvider: IDeepFramesTTSProvider;
    FASRProvider: IDeepFramesASRProvider;
    FActiveProviderName: string;
    FInitialized: Boolean;

    procedure InitializeDefaults;
    procedure CreateFakeProviders;
    procedure CreateStepFunProviders;
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

    /// <summary>Name of the currently active provider set (e.g. 'fake', 'stepfun').
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
  DeepFrames.Shared.Consts;

class destructor TProviderRegistry.DestroyClass;
begin
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
  inherited;
end;

class function TProviderRegistry.Instance: TProviderRegistry;
begin
  if FInstance = nil then
  begin
    FInstance := TProviderRegistry.Create;
    FInstance.InitializeDefaults;
  end;
  Result := FInstance;
end;

procedure TProviderRegistry.InitializeDefaults;
begin
  if FInitialized then
    Exit;
  CreateFakeProviders;
  FInitialized := True;
end;

procedure TProviderRegistry.CreateFakeProviders;
begin
  FLLMProvider := TFakeLLMProvider.Create;
  FTTSProvider := TFakeTTSProvider.Create;
  FASRProvider := TFakeASRProvider.Create;
  FActiveProviderName := PROVIDER_FAKE;
end;

procedure TProviderRegistry.CreateStepFunProviders;
begin
  FLLMProvider := TStepFunLLMProvider.Create;
  FTTSProvider := TStepFunTTSProvider.Create;
  FASRProvider := TStepFunASRProvider.Create;
  FActiveProviderName := PROVIDER_STEPFUN;
end;

procedure TProviderRegistry.CreateProviders(const AProviderName: string);
begin
  if SameText(AProviderName, PROVIDER_FAKE) then
    CreateFakeProviders
  else if SameText(AProviderName, PROVIDER_STEPFUN) then
    CreateStepFunProviders
  else
    raise ENotSupportedException.CreateFmt(
      'Unknown provider: %s. Supported: %s, %s',
      [AProviderName, PROVIDER_FAKE, PROVIDER_STEPFUN]);
end;

procedure TProviderRegistry.SwitchTo(const AProviderName: string);
begin
  if SameText(FActiveProviderName, AProviderName) then
    Exit;
  // Release old providers before creating new ones
  FLLMProvider := nil;
  FTTSProvider := nil;
  FASRProvider := nil;
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

function TProviderRegistry.ActiveProviderName: string;
begin
  Result := FActiveProviderName;
end;

function TProviderRegistry.IsInitialized: Boolean;
begin
  Result := FInitialized;
end;

end.