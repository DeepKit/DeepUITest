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
  STATUS_SKIPPED = 'skipped';
  STATUS_FAILED = 'failed';
  STATUS_CANCELLED = 'cancelled';

  JOB_TYPE_PREPROCESS = 'preprocess';
  JOB_TYPE_AGENT = 'agent';
  JOB_TYPE_AUDIO = 'audio';
  JOB_TYPE_VIDEO = 'video';
  JOB_TYPE_PACKAGE = 'package';
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
  QUEUE_DEEPFRAMES_PREPROCESS = 'deepframes.preprocess';

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

  // Quality gate results
  GATE_RESULT_PASS = 'pass';
  GATE_RESULT_WARN = 'warn';
  GATE_RESULT_FAIL = 'fail';
  GATE_1 = 'gate1';
  GATE_2 = 'gate2';
  GATE_3A = 'gate3a';
  GATE_3B = 'gate3b';
  GATE_4 = 'gate4';

  // Render backends
  RENDER_BACKEND_HYPERFRAMES = 'hyperframes';
  RENDER_BACKEND_REMOTION = 'remotion';

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

  DB2_TYPE = 'DB2.Type';
  DB2_HOST = 'DB2.Host';
  DB2_PORT = 'DB2.Port';
  DB2_DATABASE = 'DB2.Database';
  DB2_USER = 'DB2.User';
  DB2_PASSWORD_SECRET_REF = 'DB2.PasswordSecretRef';
  DB2_SSL_MODE = 'DB2.SSLMode';
  DB2_VENDOR_LIB = 'DB2.VendorLib';

  DEFAULT_DB2_TYPE = 'PostgreSQL';
  DEFAULT_DB2_HOST = '127.0.0.1';
  DEFAULT_DB2_PORT = 5432;
  DEFAULT_DB2_DATABASE = 'DeepFramesData';
  DEFAULT_DB2_USER = 'deepframes';
  DEFAULT_DB2_PASSWORD_SECRET_REF = 'secret://deepframes/db2';

  CONFIG_ROOT_PATH = 'RootPath';
  CONFIG_OUTPUT_DIR = 'OutputDir';
  CONFIG_WORKER_DIR = 'WorkerDir';
  CONFIG_LOG_DIR = 'LogDir';

function SecretNameFromRef(const SecretRef: string): string;
function NewUuidString: string;
function IsBusinessStatus(const Status: string): Boolean;
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
