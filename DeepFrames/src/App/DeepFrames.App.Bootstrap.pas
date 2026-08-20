unit DeepFrames.App.Bootstrap;

interface

type
  TDeepFramesBootstrap = class
  public
    class procedure RegisterServices; static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  FireDAC.Comp.Client,
  DeepBase.Config,
  DeepBase.Manager,
  DeepBase.DB.Factory,
  DeepBase.DB.JobQueue,
  DeepBase.Security,
  DeepBase.LLM.Types,
  DeepBase.LLM.Service,
  DeepFrames.Shared.Consts,
  DeepFrames.Provider.Intf,
  DeepFrames.Persistence.Connection;

/// Seed LLM config from ConfigDB Secrets (DPAPI) into TLLMConfigStore
/// so IsConfigured returns True and real API calls work.
procedure SeedLLMConfig;
const
  SECRET_STEP_PLAN_KEY = 'stepfun_step_plan_key';
  STEPFUN_ENDPOINT = 'https://api.stepfun.com/step_plan/v1';
  // Gemini OpenAI-compatible endpoint. The facade's openai code path appends
  // '/chat/completions' to the endpoint, so this base must be the OpenAI-compat
  // root (not the native v1beta root used by ASR/vision's generateContent).
  GEMINI_OPENAI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/openai';
var
  Key: string;
begin
  Key := LoadSecret(SECRET_STEP_PLAN_KEY);
  if Key = '' then
    Exit;
  try
    LLMAdmin.AddProvider('stepfun', STEPFUN_ENDPOINT, Key, 'openai', 10);
    LLMAdmin.SetTierModels(TierSmart,   ['step-3.7-flash']);
    LLMAdmin.SetTierModels(TierBalanced,['step-3.7-flash']);
    LLMAdmin.SetTierModels(TierFast,    ['step-3.7-flash']);
    LLMAdmin.SetTierModels(TierImageGen,['step-image-edit-2']);
    LLMAdmin.SetTierModels(TierImageFallback,['step-image-edit-2']);

    // Agnes (OpenAI-compatible). Key read fresh each call via the facade's
    // GetApiKey, but AddProvider needs a non-empty seed so GetProvider('agnes')
    // succeeds; pass the current secret value, re-seeded on next startup if
    // the secret rotates.
    var AgnesKey := LoadSecret(SECRET_AGNES_API_KEY);
    if AgnesKey <> '' then
      LLMAdmin.AddProvider(PROVIDER_AGNES, DEFAULT_AGNES_BASE_URL, AgnesKey,
        'openai', 20);

    // Gemini via OpenAI-compatible endpoint (see GEMINI_OPENAI_ENDPOINT note).
    var GeminiKey := LoadSecret(SECRET_GEMINI_API_KEY);
    if GeminiKey <> '' then
      LLMAdmin.AddProvider(PROVIDER_GEMINI, GEMINI_OPENAI_ENDPOINT, GeminiKey,
        'openai', 30);

    LLMAdmin.Save;
  except
    // Don't fail app startup for LLM config seeding
  end;
end;

/// Seed default provider config (per-capability selection + Agnes/Baidu
/// endpoint/model defaults) into DB1 Settings. Only writes keys that don't
/// already exist, so user overrides are preserved. The active provider set
/// is then materialized by TProviderRegistry.ConfigureFromConfig (see
/// RegisterServices below), replacing the legacy fake-default.
procedure SeedProviderConfig;
  procedure Ensure(const Key, Default, Category: string);
  begin
    if Trim(GetConfig(Key, '')) = '' then
      SetConfig(Key, Default, Category);
  end;
begin
  try
    // Per-capability provider selection (independent, not whole-group)
    Ensure(CONFIG_PROVIDER_LLM,   PROVIDER_AGNES,  'Provider');
    Ensure(CONFIG_PROVIDER_ASR,   PROVIDER_BAIDU,  'Provider');
    Ensure(CONFIG_PROVIDER_IMAGE, PROVIDER_AGNES,  'Provider');
    Ensure(CONFIG_PROVIDER_VIDEO, PROVIDER_AGNES,  'Provider');

    // Agnes AI (OpenAI-compatible chat + image + video)
    Ensure(CONFIG_AGNES_BASE_URL,   DEFAULT_AGNES_BASE_URL,   'Agnes');
    Ensure(CONFIG_AGNES_LLM_MODEL,  DEFAULT_AGNES_LLM_MODEL,  'Agnes');
    Ensure(CONFIG_AGNES_IMAGE_MODEL,DEFAULT_AGNES_IMAGE_MODEL,'Agnes');
    Ensure(CONFIG_AGNES_VIDEO_MODEL,DEFAULT_AGNES_VIDEO_MODEL,'Agnes');
    Ensure(CONFIG_AGNES_KEY_SECRET_REF, SECRET_AGNES_API_KEY, 'Agnes');

    // Baidu ASR (access_token auth via AppId/ApiKey/SecretKey)
    Ensure(CONFIG_BAIDU_ASR_APP_ID, DEFAULT_BAIDU_ASR_APP_ID, 'Baidu');

    // yt-dlp download settings
    Ensure(CONFIG_DOWNLOAD_DIR, DEFAULT_DOWNLOAD_DIR, 'Download');
    Ensure(CONFIG_DOWNLOAD_THREADS, '4', 'Download');
  except
    // Don't fail app startup for provider config seeding
  end;
end;

class procedure TDeepFramesBootstrap.RegisterServices;
var
  RootPath: string;
  ConfigDbPath: string;
begin
  RootPath := DeepBase.Manager.DeepBase.RootPath;
  ConfigDbPath := TPath.Combine(RootPath, 'DeepFramesConfig.db');
  TDBConnectionFactory.Configure(ConfigDbPath, RootPath);

  TDirectory.CreateDirectory(TPath.Combine(RootPath, GetConfig(CONFIG_OUTPUT_DIR, 'output')));
  TDirectory.CreateDirectory(TPath.Combine(RootPath, GetConfig(CONFIG_WORKER_DIR, 'workers')));
  TDirectory.CreateDirectory(TPath.Combine(RootPath, GetConfig(CONFIG_LOG_DIR, 'logs')));

  if Trim(GetConfig(CONFIG_ROOT_PATH, '')) = '' then
    SetConfig(CONFIG_ROOT_PATH, RootPath, 'Paths');
  if Trim(GetConfig(CONFIG_OUTPUT_DIR, '')) = '' then
    SetConfig(CONFIG_OUTPUT_DIR, 'output', 'Paths');
  if Trim(GetConfig(CONFIG_WORKER_DIR, '')) = '' then
    SetConfig(CONFIG_WORKER_DIR, 'workers', 'Paths');
  if Trim(GetConfig(CONFIG_LOG_DIR, '')) = '' then
    SetConfig(CONFIG_LOG_DIR, 'logs', 'Paths');

  TDeepFramesDB2Connection.EnsureDefaultSettings;
  TJobQueue.SetConnectionProvider(
    function: TFDConnection
    begin
      Result := TDeepFramesDB2Connection.CreateConnection(True);
    end);
  SeedProviderConfig;
  SeedLLMConfig;
end;

class procedure TDeepFramesBootstrap.Shutdown;
begin
  TJobQueue.Clear;
  TDeepFramesDB2Connection.ReleasePool;
end;

end.
