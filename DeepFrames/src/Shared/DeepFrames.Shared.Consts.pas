unit DeepFrames.Shared.Consts;

interface

const
  APP_NAME = 'DeepFrames';
  APP_SCHEMA_VERSION = '1.0.0';

  PROVIDER_DEEPFRAMES = 'deepframes';

  STATUS_PENDING = 'pending';
  STATUS_RUNNING = 'running';
  STATUS_BLOCKED_REVIEW = 'blocked_review';
  STATUS_DONE = 'done';
  STATUS_COMPLETED = 'completed';
  STATUS_SKIPPED = 'skipped';
  STATUS_FAILED = 'failed';
  STATUS_CANCELLED = 'cancelled';

  JOB_TYPE_PREPROCESS = 'preprocess';
  JOB_TYPE_AGENT = 'agent';
  JOB_TYPE_AUDIO = 'audio';
  JOB_TYPE_VIDEO = 'video';
  JOB_TYPE_PACKAGE = 'package';
  JOB_TYPE_IMPORT = 'import';
  STEP_TYPE_PREPROCESS_MAIN = 'preprocess.main';
  STEP_TYPE_BUILD_SCRIPT = 'agent.build_script';
  STEP_TYPE_ACCURACY_CHECK = 'agent.accuracy_check';
  STEP_TYPE_BUILD_VARIANT = 'agent.build_variant';
  STEP_TYPE_BUILD_SHOT = 'agent.build_shot';
  STEP_TYPE_AGENT_SPLITTER = 'agent.splitter';
  STEP_TYPE_AGENT_WORKER = 'agent.worker';
  STEP_TYPE_AGENT_ASSEMBLER = 'agent.assembler';
  STEP_TYPE_AGENT_QA = 'agent.qa';
  STEP_TYPE_STYLE_KEEPER = 'agent.style_keeper';
  STEP_TYPE_TTS_SYNTHESIS = 'audio.tts_synthesis';
  STEP_TYPE_ASR_TIMESTAMPS = 'audio.asr_timestamps';
  STEP_TYPE_AUDIO_MERGE = 'audio.merge';
  STEP_TYPE_LOUDNORM = 'audio.loudnorm';
  STEP_TYPE_VIDEO_COMPILE = 'video.compile_ir';
  STEP_TYPE_VIDEO_LINT = 'video.lint';
  STEP_TYPE_VIDEO_SNAPSHOT = 'video.snapshot';
  STEP_TYPE_VIDEO_RENDER = 'video.render';
  STEP_TYPE_VIDEO_MUX = 'video.mux';
  STEP_TYPE_PACKAGE_ASSEMBLE = 'package.assemble';
  STEP_TYPE_IMPORT_DOWNLOAD = 'import.download';
  STEP_TYPE_IMPORT_TRANSCRIBE = 'import.transcribe';
  QUEUE_DEEPFRAMES_PREPROCESS = 'deepframes.preprocess';
  QUEUE_DEEPFRAMES_IMPORT = 'deepframes.import';

  // Agent roles
  AGENT_ROLE_SPLITTER = 'splitter';
  AGENT_ROLE_WORKER = 'worker';
  AGENT_ROLE_ASSEMBLER = 'assembler';
  AGENT_ROLE_QA = 'qa';
  AGENT_ROLE_STYLE_KEEPER = 'style_keeper';

  // LLM capabilities
  CAPABILITY_LLM = 'llm';
  CAPABILITY_TTS = 'tts';
  CAPABILITY_ASR = 'asr';
  CAPABILITY_IMAGE_GEN = 'image_gen';
  CAPABILITY_IMAGE_EDIT = 'image_edit';
  CAPABILITY_VIDEO_GEN = 'video_gen';

  // Eval types
  EVAL_TYPE_QA = 'qa';
  EVAL_TYPE_STYLE_KEEPER = 'style_keeper';
  EVAL_TYPE_ACCURACY = 'accuracy';
  EVAL_TYPE_HUMAN_REVIEW = 'human_review';

  // Recommended actions
  ACTION_ACCEPT = 'accept';
  ACTION_REWORK_WORKER = 'rework_worker';
  ACTION_REWORK_SPLITTER = 'rework_splitter';
  ACTION_REWORK_SCRIPT = 'rework_script';
  ACTION_MANUAL_EDIT = 'manual_edit';

  // Document kinds
  DOCUMENT_KIND_SOURCE = 'source';
  DOCUMENT_KIND_SCRIPT = 'script';
  DOCUMENT_KIND_VARIANT = 'variant';
  DOCUMENT_KIND_SHOT = 'shot';

  // Content unit source types (provenance for external_video_import adapter)
  SOURCE_TYPE_ORIGINAL_ARTICLE = 'original_article';
  SOURCE_TYPE_EXTERNAL_VIDEO = 'external_video';
  SOURCE_TYPE_EXTERNAL_AUDIO = 'external_audio';
  SOURCE_TYPE_LOCAL_FILE = 'local_file';

  // License hints for external sources (advisory only, not a hard gate)
  LICENSE_HINT_SELF = 'self';
  LICENSE_HINT_AUTHORIZED = 'authorized';
  LICENSE_HINT_UNKNOWN = 'unknown';

  // Content type for the external_video_import adapter
  CONTENT_TYPE_EXTERNAL_VIDEO_IMPORT = 'external_video_import';

  // Quality gate results
  GATE_RESULT_PASS = 'pass';
  GATE_RESULT_WARN = 'warn';
  GATE_RESULT_FAIL = 'fail';
  GATE_1 = 'gate1';
  GATE_2 = 'gate2';
  GATE_3A = 'gate3a';
  GATE_3B = 'gate3b';
  GATE_4 = 'gate4';
  // external_video_import 来源元数据合规性黄灯子检查
  // NOTE: column gate is varchar(8), keep ≤8 chars
  GATE_SOURCE = 'gsource';

  // Render backends
  RENDER_BACKEND_HYPERFRAMES = 'hyperframes';
  RENDER_BACKEND_REMOTION = 'remotion';
  RENDER_BACKEND_AGNES = 'agnes';  // AI text/image-to-video generation (Agnes provider)

  // Video run modes
  VIDEO_MODE_VISUAL_PREVIEW = 'visual-preview';
  VIDEO_MODE_TIMED_PREVIEW = 'timed-preview';
  VIDEO_MODE_FINAL_WITH_AUDIO = 'final-with-audio';

  // Duration sources
  DURATION_SOURCE_ESTIMATED = 'estimated';
  DURATION_SOURCE_AUDIO = 'audio';
  DURATION_SOURCE_MEASURED = 'measured';

  // Platform defaults
  PLATFORM_BILIBILI = 'bilibili';
  DELIVERY_TYPE_VIDEO = 'video';
  DELIVERY_TYPE_AUDIO = 'audio';

  // Asset categories for video
  ASSET_CATEGORY_BACKGROUND = 'background';
  ASSET_CATEGORY_SUBTITLE = 'subtitle';
  ASSET_CATEGORY_SNAPSHOT = 'snapshot';
  ASSET_CATEGORY_PREVIEW = 'preview';
  ASSET_CATEGORY_FINAL = 'final';
  ASSET_CATEGORY_COVER = 'cover';
  ASSET_CATEGORY_MANIFEST = 'manifest';

  // Retention classes (102C strategy)
  RETENTION_CLASS_C1 = 'C1';
  RETENTION_CLASS_C2 = 'C2';
  RETENTION_CLASS_C3 = 'C3';
  RETENTION_CLASS_C4 = 'C4';

  // Asset status (separate from business object status)
  ASSET_STATUS_TEMP = 'temp';
  ASSET_STATUS_READY = 'ready';
  ASSET_STATUS_FAILED = 'failed';
  ASSET_STATUS_DELETED = 'deleted';

  // Variant kinds
  VARIANT_KIND_MAIN = 'main';
  VARIANT_KIND_EXPERIMENT = 'experiment';
  VARIANT_KIND_PLATFORM = 'platform';
  VARIANT_KIND_ACCOUNT = 'account';

  // Phase 7: Extension constants

  // Additional platforms
  PLATFORM_DOUYIN = 'douyin';
  PLATFORM_KUAISHOU = 'kuaishou';
  PLATFORM_XIAOHONGSHU = 'xiaohongshu';
  PLATFORM_WECHAT_VIDEO = 'wechat_video';
  PLATFORM_YOUTUBE = 'youtube';
  PLATFORM_XIMALAYA = 'ximalaya';

  // BGM status
  BGM_STATUS_ACTIVE = 'active';
  BGM_STATUS_DISABLED = 'disabled';
  BGM_STATUS_DELETED = 'deleted';

  // BGM license types
  BGM_LICENSE_ROYALTY_FREE = 'royalty_free';
  BGM_LICENSE_CREATIVE_COMMONS = 'creative_commons';
  BGM_LICENSE_CUSTOM = 'custom';

  // Content type adapter status
  ADAPTER_STATUS_PENDING = 'pending';
  ADAPTER_STATUS_ACTIVE = 'active';
  ADAPTER_STATUS_DISABLED = 'disabled';
  ADAPTER_STATUS_DEPRECATED = 'deprecated';

  // Readiness check types
  READINESS_CHECK_E2E_SAMPLE = 'e2e_sample';
  READINESS_CHECK_SCHEMA = 'schema';
  READINESS_CHECK_PIPELINE = 'pipeline';
  READINESS_CHECK_OUTPUT = 'output';

  // Readiness check results
  READINESS_RESULT_PASS = 'pass';
  READINESS_RESULT_WARN = 'warn';
  READINESS_RESULT_FAIL = 'fail';
  READINESS_RESULT_NOT_CHECKED = 'not_checked';

  // Extension step types
  STEP_TYPE_BGM_SELECT = 'extension.bgm_select';
  STEP_TYPE_BGM_MIX = 'extension.bgm_mix';
  STEP_TYPE_READINESS_CHECK = 'extension.readiness_check';
  STEP_TYPE_ADAPTER_REGISTER = 'extension.adapter_register';

  // Job type for extension
  JOB_TYPE_EXTENSION = 'extension';

  DB2_TYPE = 'DB2.Type';
  DB2_HOST = 'DB2.Host';
  DB2_PORT = 'DB2.Port';
  DB2_DATABASE = 'DB2.Database';
  DB2_USER = 'DB2.User';
  DB2_PASSWORD_SECRET_REF = 'DB2.PasswordSecretRef';
  DB2_SSL_MODE = 'DB2.SSLMode';
  DB2_VENDOR_LIB = 'DB2.VendorLib';

  DB3_TYPE = 'DB3.Type';
  DB3_HOST = 'DB3.Host';
  DB3_PORT = 'DB3.Port';
  DB3_DATABASE = 'DB3.Database';
  DB3_USER = 'DB3.User';
  DB3_PASSWORD_SECRET_REF = 'DB3.PasswordSecretRef';
  DB3_SSL_MODE = 'DB3.SSLMode';
  DB3_VENDOR_LIB = 'DB3.VendorLib';

  DEFAULT_DB2_TYPE = 'PostgreSQL';
  DEFAULT_DB2_HOST = '127.0.0.1';
  DEFAULT_DB2_PORT = 5432;
  DEFAULT_DB2_DATABASE = 'DeepFramesData';
  DEFAULT_DB2_USER = 'fuyi01';
  DEFAULT_DB2_PASSWORD_SECRET_REF = 'secret://deepframes/db2';

  DEFAULT_DB3_TYPE = 'PostgreSQL';
  DEFAULT_DB3_HOST = '127.0.0.1';
  DEFAULT_DB3_PORT = 5432;
  DEFAULT_DB3_DATABASE = 'DeepFramesCollab';
  DEFAULT_DB3_USER = 'fuyi01';
  DEFAULT_DB3_PASSWORD_SECRET_REF = 'secret://deepframes/db3';

  CONFIG_ROOT_PATH = 'RootPath';
  CONFIG_OUTPUT_DIR = 'OutputDir';
  CONFIG_WORKER_DIR = 'WorkerDir';
  CONFIG_LOG_DIR = 'LogDir';

  // P0-G budget guard: per-job hard ceilings. A job that blows past these
  // raises EBudgetExceeded instead of silently burning provider budget.
  CONFIG_BUDGET_MAX_TOKENS_PER_JOB = 'Budget.MaxTokensPerJob';
  CONFIG_BUDGET_MAX_CALLS_PER_JOB = 'Budget.MaxCallsPerJob';
  BUDGET_DEFAULT_MAX_TOKENS_PER_JOB = 200000;  // ~ a few long LLM+image runs
  BUDGET_DEFAULT_MAX_CALLS_PER_JOB = 60;       // LLM + TTS + ASR + image calls

  // Provider selection (per-capability, independent). Values reference
  // PROVIDER_FAKE/STEPFUN/AGNES/BAIDU constants from DeepFrames.Provider.Intf.
  CONFIG_PROVIDER_LLM = 'Provider.LLM';
  CONFIG_PROVIDER_ASR = 'Provider.ASR';
  CONFIG_PROVIDER_IMAGE = 'Provider.Image';
  CONFIG_PROVIDER_VIDEO = 'Provider.Video';

  // Agnes AI provider (apihub.agnes-ai.com, OpenAI-compatible)
  CONFIG_AGNES_BASE_URL = 'Agnes.BaseUrl';
  CONFIG_AGNES_LLM_BASE_URL = 'Agnes.LLMBaseUrl';
  CONFIG_AGNES_LLM_MODEL = 'Agnes.LLMModel';
  CONFIG_AGNES_IMAGE_MODEL = 'Agnes.ImageModel';
  CONFIG_AGNES_VIDEO_MODEL = 'Agnes.VideoModel';
  CONFIG_AGNES_KEY_SECRET_REF = 'Agnes.KeySecretRef';
  DEFAULT_AGNES_BASE_URL = 'https://apihub.agnes-ai.com/v1';
  DEFAULT_AGNES_LLM_MODEL = 'agnes-2.0-flash';
  DEFAULT_AGNES_IMAGE_MODEL = 'agnes-image-2.1-flash';
  DEFAULT_AGNES_VIDEO_MODEL = 'agnes-video-v2.0';
  // NOTE: secret names must be IsValidSecretName-compliant (a-z A-Z 0-9 _ - .),
  // no slashes — DeepBase.Security.SaveSecret rejects '/' (anti path-traversal),
  // and the CLI --set-secret path hangs on slashed names. Use the flat name.
  SECRET_AGNES_API_KEY = 'agnes_api_key';
  // LLM-specific key (e.g. when Agnes.LLMBaseUrl points at a fccy/relay host
  // that needs its own Bearer, distinct from the Agnes image/video host key).
  SECRET_AGNES_LLM_API_KEY = 'agnes_llm_api_key';

  // Baidu ASR provider (vop.baidu.com, access_token auth)
  CONFIG_BAIDU_ASR_APP_ID = 'Baidu.ASR.AppId';
  CONFIG_BAIDU_ASR_API_KEY = 'Baidu.ASR.ApiKey';
  CONFIG_BAIDU_ASR_SECRET_KEY = 'Baidu.ASR.SecretKey';
  CONFIG_BAIDU_ASR_TOKEN_CACHE = 'Baidu.ASR.TokenCache';
  CONFIG_BAIDU_ASR_TOKEN_EXPIRES = 'Baidu.ASR.TokenExpires';
  // NOTE: secret names must be IsValidSecretName-compliant (a-z A-Z 0-9 _ - .),
  // no slashes. DeepBase.Security.SaveSecret rejects names containing '/' (anti
  // path-traversal), so the CLI --set-secret path silently fails for slashed
  // names. Use the flat name and store the value as "APIKey;SecretKey" (single
  // line) — the provider splits on ';' (and, for back-compat, CR/LF).
  SECRET_BAIDU_ASR_KEY = 'baidu_asr_key';
  DEFAULT_BAIDU_ASR_APP_ID = '7698708';

  // Google Gemini provider (generativelanguage.googleapis.com, native API).
  // Covers LLM / TTS / ASR as a failover backup behind Agnes / Baidu.
  // NOTE: requires an HTTP proxy in CN environments — see DEFAULT_GEMINI_PROXY.
  CONFIG_GEMINI_BASE_URL = 'Gemini.BaseUrl';
  CONFIG_GEMINI_LLM_MODEL = 'Gemini.LLMModel';
  CONFIG_GEMINI_TTS_MODEL = 'Gemini.TTSModel';
  CONFIG_GEMINI_ASR_MODEL = 'Gemini.ASRModel';
  CONFIG_GEMINI_PROXY = 'Gemini.Proxy';
  DEFAULT_GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';
  DEFAULT_GEMINI_LLM_MODEL = 'gemini-2.5-flash';
  DEFAULT_GEMINI_TTS_MODEL = 'gemini-2.5-flash-preview-tts';
  DEFAULT_GEMINI_ASR_MODEL = 'gemini-2.5-flash';
  DEFAULT_GEMINI_PROXY = 'http://127.0.0.1:10808';
  SECRET_GEMINI_API_KEY = 'gemini_api_key';

  // yt-dlp / download settings for external_video_import adapter
  CONFIG_DOWNLOAD_DIR = 'Download.Dir';
  CONFIG_DOWNLOAD_PROXY = 'Download.Proxy';
  CONFIG_DOWNLOAD_THREADS = 'Download.Threads';
  CONFIG_DOWNLOAD_THROTTLED_RATE = 'Download.ThrottledRate';
  DEFAULT_DOWNLOAD_DIR = 'downloads';

  // Video transcode / encoder settings (docs/07.video §2)
  CONFIG_VIDEO_ENCODER = 'Video.Encoder';            // cpu/auto/nvidia/intel/amd
  CONFIG_FFMPEG_AUTO_DOWNLOAD = 'Video.FfmpegAutoDownload';
  CONFIG_FFMPEG_DIR = 'Video.FfmpegDir';
  DEFAULT_VIDEO_ENCODER = 'auto';
  DEFAULT_FFMPEG_DIR = 'ffmpeg';

  // Full-capability CLI overrides (tasks.md D1, 2026-07-13).
  // --voice: TTS voice id (Baidu 106/4118/4119, StepFun cixingnansheng/...).
  CONFIG_TTS_VOICE = 'TTS.VoiceId';
  DEFAULT_TTS_VOICE = 'cixingnansheng';
  // --subtitle-lang: subtitle file language tag, e.g. zh.srt / en.srt.
  CONFIG_SUBTITLE_LANG = 'Subtitle.Lang';
  DEFAULT_SUBTITLE_LANG = 'zh';
  // --duration-strategy: audio/video alignment strategy for mux.
  //   audio-base = trim/loop video to audio length (audio is the timing truth)
  //   video-base = pad/trim audio to video length
  //   shortest   = legacy -shortest (keeps current behaviour)
  CONFIG_DURATION_STRATEGY = 'Video.DurationStrategy';
  DEFAULT_DURATION_STRATEGY = 'audio-base';
  // --keep-intermediates: '1' retains TTS wav / ASR timestamps / extracted
  //   frames for debugging instead of deleting them between phases.
  CONFIG_KEEP_INTERMEDIATES = 'Debug.KeepIntermediates';
  DEFAULT_KEEP_INTERMEDIATES = '0';
  // --output-dir: overrides the output root for generated artifacts.
  //   Empty = use DeepBase.RootPath/output (default).
  //   NOTE: reuses the pre-existing CONFIG_OUTPUT_DIR ('OutputDir') declared
  //   above with CONFIG_ROOT_PATH — same key, same semantics, no new symbol.

  // Notification channels (docs/09.notification §1)
  CONFIG_NOTIFY_WECOM_WEBHOOK = 'Notify.WecomWebhook';
  CONFIG_NOTIFY_DINGTALK_WEBHOOK = 'Notify.DingtalkWebhook';
  CONFIG_NOTIFY_HTTP_WEBHOOK = 'Notify.HttpWebhook';
  QUEUE_DEEPFRAMES_NOTIFY = 'deepframes.notify';

  // CookieCloud sync (docs/09.cookiecloud)
  CONFIG_COOKIECLOUD_SERVER = 'CookieCloud.Server';
  CONFIG_COOKIECLOUD_UUID = 'CookieCloud.Uuid';
  CONFIG_COOKIECLOUD_KEY = 'CookieCloud.Key';
  DEFAULT_COOKIECLOUD_OUTPUT = 'cookies.txt';

  // Chunked uploader (docs/09.uploader)
  CONFIG_UPLOAD_CHUNK_SIZE = 'Upload.ChunkSizeBytes';
  CONFIG_UPLOAD_MAX_RETRIES = 'Upload.MaxRetries';
  DEFAULT_UPLOAD_CHUNK_SIZE = 5242880;  // 5 MiB
  DEFAULT_UPLOAD_MAX_RETRIES = 3;

function SecretNameFromRef(const SecretRef: string): string;
function NewUuidString: string;
function IsBusinessStatus(const Status: string): Boolean;
/// <summary>Terminal: job/step reached a final state, no resume needed.</summary>
function IsTerminalStatus(const Status: string): Boolean;
/// <summary>Resumable: mid-flight (pending/running), chain should resume.</summary>
function IsResumableStatus(const Status: string): Boolean;
function IsAssetStatus(const Status: string): Boolean;
function IsGateResult(const Value: string): Boolean;

implementation

uses
  System.SysUtils;

function SecretNameFromRef(const SecretRef: string): string;
const
  Prefix = 'secret://';
begin
  Result := SecretRef;
  if Result.StartsWith(Prefix, True) then
    Delete(Result, 1, Length(Prefix));
end;

function NewUuidString: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := GUIDToString(G).ToLower.Replace('{', '').Replace('}', '');
end;

function IsBusinessStatus(const Status: string): Boolean;
begin
  Result := SameText(Status, STATUS_PENDING) or
    SameText(Status, STATUS_RUNNING) or
    SameText(Status, STATUS_BLOCKED_REVIEW) or
    SameText(Status, STATUS_DONE) or
    SameText(Status, STATUS_SKIPPED) or
    SameText(Status, STATUS_FAILED) or
    SameText(Status, STATUS_CANCELLED);
end;

function IsTerminalStatus(const Status: string): Boolean;
begin
  // done/failed/cancelled/skipped: nothing to resume; blocked_review needs
  // human action, not an automatic re-run.
  Result := SameText(Status, STATUS_DONE) or
    SameText(Status, STATUS_FAILED) or
    SameText(Status, STATUS_CANCELLED) or
    SameText(Status, STATUS_SKIPPED) or
    SameText(Status, STATUS_BLOCKED_REVIEW);
end;

function IsResumableStatus(const Status: string): Boolean;
begin
  Result := SameText(Status, STATUS_PENDING) or
    SameText(Status, STATUS_RUNNING);
end;

function IsAssetStatus(const Status: string): Boolean;
begin
  Result := SameText(Status, ASSET_STATUS_TEMP) or
    SameText(Status, ASSET_STATUS_READY) or
    SameText(Status, ASSET_STATUS_FAILED) or
    SameText(Status, ASSET_STATUS_DELETED);
end;

function IsGateResult(const Value: string): Boolean;
begin
  Result := SameText(Value, GATE_RESULT_PASS) or
    SameText(Value, GATE_RESULT_WARN) or
    SameText(Value, GATE_RESULT_FAIL);
end;

end.
