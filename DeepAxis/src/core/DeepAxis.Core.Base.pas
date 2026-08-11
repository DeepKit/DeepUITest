unit DeepAxis.Core.Base;

interface

type
  // ── Message direction ──────────────────────────────────────────
  /// <summary>
  ///   Direction of a message. Inbound = from contact to user.
  ///   Outbound = from user to contact. Unknown = cannot determine.
  /// </summary>
  TDirection = (dOutbound, dInbound, dUnknown);

  // ── Privacy classification ─────────────────────────────────────
  /// <summary>
  ///   Privacy scope of a contact. BUSINESS = allowed in analysis.
  ///   PRIVATE = excluded. IDLE = idle funnel only. UNKNOWN = pending confirmation.
  /// </summary>
  TPrivacyScope = (psUnknown, psBusiness, psPrivate, psIdle);

  /// <summary>Source of privacy classification.</summary>
  TPrivacySource = (psSystemGuess, psHumanConfirmed);

  // ── Radar hint types ───────────────────────────────────────────
  /// <summary>
  ///   P0 radar hint types. Five categories detectable from metadata alone,
  ///   plus content-based hints from message body analysis.
  /// </summary>
  TRadarHintType = (
    rhtCooling,          // 互动明显下降
    rhtLongSilence,      // 长期未联系
    rhtReactivated,      // 最近重新活跃
    rhtOutboundHeavy,    // 我发多对方回少
    rhtDataInsufficient, // 数据不足
    rhtHighLinkSharing,  // 高频链接分享 (content-based)
    rhtMarketingPattern  // 营销模式 (content-based)
  );

  // ── Evidence types ─────────────────────────────────────────────
  TEvidenceType = (etMetric, etThreshold, etPrivacyDecision, etSchema);

  // ── Audit event type ───────────────────────────────────────────
  TAuditEventType = (aetScan, aetRead, aetFieldAccess, aetPrivacyDecision,
    aetMetricCompute, aetHintGenerate, aetDeletion);

  // ── Message normalized type ────────────────────────────────────
  TNormalizedMsgType = (
    nmtText, nmtImage, nmtVoice, nmtVideo, nmtEmoji, nmtLink, nmtSystem,
    nmtLocation,      // Type=48: 位置消息
    nmtContactCard,   // Type=40: 好友推荐/名片
    nmtRecall,        // Type=10002: 撤回消息
    nmtUnknown
  );

  // ── Data quality ───────────────────────────────────────────────
  TDataQuality = (dqOK, dqPartial, dqDataInsufficient);

  // ── Intervention recommendation ────────────────────────────────
  TInterventionRecommendation = (irNone, irReview);

  // ── Profile identity ───────────────────────────────────────────
  TProfileIdentity = (piPersonalFull, piExternalSafe, piStrictCompliance);

  // ── Governance mode ────────────────────────────────────────────
  TGovernanceMode = (gmObserve, gmEnforce);

  // ── Axis 1 state (0-9) ─────────────────────────────────────────
  /// <summary>
  ///   Client fact state on Axis 1 (product dimension).
  ///   0=关联未激活, 1=知道, 2=培育中, 3=有意向, 4=洽谈中,
  ///   5=首单, 6=复购, 7=降温中, 8=已流失, 9=不适用
  /// </summary>
  TAxis1State = 0..9;

  // ── Display tier (绿/黄/红 简化分级) ──────────────────────────
  /// <summary>
  ///   User-facing contact tier derived from metadata. A simplified
  ///   three-color aggregation over Axis1State + interaction metrics,
  ///   usable in cold-start (M0). Does NOT replace TAxis1State — that
  ///   remains the precise fact state for the full state machine (P2).
  ///   tGreen  = 热客·活跃 (≤7d 且双向互动)
  ///   tYellow = 待激活·降温 (8-30d，或 ≤7d 但单向发)
  ///   tRed    = 闲人·沉默 (>30d)
  ///   tGray   = 数据不足 (无有效 metric)
  /// </summary>
  TTier = (tGreen, tYellow, tRed, tGray);

  // ── Tag source ─────────────────────────────────────────────────
  TTagSource = (
    tsMetadata,          // M0 metadata
    tsContent,           // M1 content analysis
    tsWeChatLabel,       // imported from WeChat label
    tsRemark,            // extracted from remark
    tsUserConfirmed      // user explicitly set
  );

  // ── Idle status ────────────────────────────────────────────────
  TIdleStatus = (isCanAdvertise, isPendingDeletion, isUserPreserved);

  // ── WeChat process state ───────────────────────────────────────
  TWeChatProcessState = (
    wpsNotFound, wpsLaunching, wpsRunning, wpsScanning,
    wpsKeyFound, wpsKeyVerified, wpsFailed
  );

  // ── Layout mode ────────────────────────────────────────────────
  TDeepAxisLayout = (dlCompact, dlDock, dlFullScreen);

  // ── Scan cursor ────────────────────────────────────────────────
  TScanCursor = record
    ContactId: string;
    LastLocalId: Int64;
    LastCreateTime: Int64;
  end;

  TScanCursorArray = TArray<TScanCursor>;

const
  // ── Layout ─────────────────────────────────────────────────────
  DEEPAXIS_STRIP_WIDTH = 640;
  DEEPAXIS_EXPANDED_WIDTH = 800;
  DEEPAXIS_COMPACT_HEIGHT = 120;

  // ── Polling intervals (ms) ─────────────────────────────────────
  POLL_INTERVAL_FOREGROUND = 5000;
  POLL_INTERVAL_BACKGROUND = 60000;

  // ── Radar thresholds (--1 = load from ConfigDB at runtime) ─────
  RADAR_COOLING_DAYS_DEFAULT = 7;              // 7 days of dropping interaction = cooling
  RADAR_LONG_SILENCE_DAYS_DEFAULT = 30;        // 30 days no interaction = long silence
  RADAR_REACTIVATED_DAYS_DEFAULT = 14;         // 14 days after silence resuming = reactivated
  RADAR_OUTBOUND_HEAVY_RATIO_DEFAULT = 3.0;    // outbound/inbound > 3.0 = outbound_heavy
  RADAR_MIN_MESSAGES_FOR_METRIC_DEFAULT = 5;   // minimum messages for valid metric
  RADAR_MIN_MESSAGES_FOR_OK_DEFAULT = 20;      // minimum messages for dqOK

  // -- Tier thresholds (绿/黄/红 简化分级) -- ────────────────────
  TIER_ACTIVE_DAYS = 7;          // ≤7d 互动 = 活跃窗口
  TIER_SILENCE_DAYS = 30;        // >30d = 闲人/沉默

  // -- Ad funnel -- ──────────────────────────────────────────────────
  AD_MAX_COUNT = 3;              // default max ad count before deletion suggestion
  AD_COOLDOWN_DAYS = 7;          // days after last ad before deletion suggestion
  /// <summary>用户"保留"标记。写入 TContact.WeChatLabels, 跨轮询存活 (TagProfile JSON 会被轮询覆盖, WeChatLabels 由 DeepAxis 附加不覆盖)。</summary>
  PRESERVE_TAG = '__preserved__';

  // ── Schema adapter identifiers ─────────────────────────────────
  ADAPTER_WECHAT_411053 = 'wechat-4.1.10.53';

  // ── Config keys (DB1 ConfigDB) ─────────────────────────────────
  CFG_PROFILE_CURRENT = 'DeepAxis.Profile.Current';
  CFG_POLL_FOREGROUND = 'DeepAxis.Poll.Foreground';
  CFG_POLL_BACKGROUND = 'DeepAxis.Poll.Background';
  CFG_AD_MAX = 'DeepAxis.Ad.MaxCount';
  CFG_WECHAT_PATH = 'DeepAxis.WeChat.Path';
  CFG_WECHAT_DATA = 'DeepAxis.WeChat.DataPath';

  // ── Secret keys (DeepBase.Security) ────────────────────────────
  SECRET_WECHAT_KEY = 'deepaxis.wechat.key';
  SECRET_LLM_KEY = 'deepaxis.llm.key';

  // ── Command IDs ────────────────────────────────────────────────
  CMD_LAUNCH_WECHAT = 'deepaxis.wechat.launch';
  CMD_START_SCAN = 'deepaxis.wechat.scan';
  CMD_TOGGLE_RADAR = 'deepaxis.ui.toggleRadar';
  CMD_EXPAND_PANEL = 'deepaxis.ui.expandPanel';
  CMD_COLLAPSE_PANEL = 'deepaxis.ui.collapsePanel';
  CMD_TOGGLE_LAYOUT = 'deepaxis.ui.toggleLayout';
  CMD_REFRESH_DATA = 'deepaxis.data.refresh';
  CMD_CONNECT_DECRYPTED = 'deepaxis.wechat.connectDecrypted';

  // ── Gate keys ──────────────────────────────────────────────────
  GATE_WECHAT_READ_METADATA = 'deepaxis.wechat.read_metadata';
  GATE_WECHAT_READ_BODY = 'deepaxis.wechat.read_body';
  GATE_WECHAT_WRITE_TAG = 'deepaxis.wechat.write_remark_tag';
  GATE_WECHAT_UIA_PASTE = 'deepaxis.wechat.uia_paste';
  GATE_WECHAT_FINAL_SEND = 'deepaxis.wechat.final_send';
  GATE_CONTACT_DELETE = 'deepaxis.contact.delete';
  GATE_BULK_PREPARE = 'deepaxis.bulk.prepare_queue';
  GATE_BULK_EXECUTE = 'deepaxis.bulk.execute_wave';
  GATE_LLM_CLOUD = 'deepaxis.llm.cloud';
  GATE_EXPORT_REPORT = 'deepaxis.export.report';

  // ── Capability IDs ─────────────────────────────────────────────
  CAP_WECHAT_M0_METADATA = 'wechat.m0.metadata_read';
  CAP_WECHAT_M1_BODY = 'wechat.m1.body_read';
  CAP_WECHAT_M2_WRITEBACK = 'wechat.m2.writeback_tag_remark';
  CAP_WECHAT_M3_UIA_PASTE = 'wechat.m3.uia_paste';
  CAP_WECHAT_FINAL_SEND = 'wechat.final_send';
  CAP_CONTACT_DELETE = 'contact.delete';
  CAP_BULK_PREPARE = 'bulk.prepare_queue';
  CAP_BULK_WAVE = 'bulk.wave_sending';
  CAP_LLM_LOCAL = 'llm.local';
  CAP_LLM_CLOUD = 'llm.cloud';
  CAP_EXPORT_REPORT = 'export.report';
  CAP_MULTI_ACCOUNT = 'multi_account';

  // ── Capability mode values ─────────────────────────────────────
  CAP_MODE_ON = 'on';
  CAP_MODE_OFF = 'off';
  CAP_MODE_EXPLICIT_CONSENT = 'explicit_consent';
  CAP_MODE_PER_CONTACT_CONFIRM = 'per_contact_confirm';
  CAP_MODE_CONFIRM_EACH_BATCH = 'confirm_each_batch';
  CAP_MODE_CONFIRM_EACH_WAVE = 'confirm_each_wave';
  CAP_MODE_CONFIRM_EACH_CONTACT = 'confirm_each_contact';
  CAP_MODE_PRIVACY_FILTERED = 'privacy_filtered';
  CAP_MODE_REVIEW_REQUIRED = 'review_required';

  // ── File extensions ────────────────────────────────────────────
  WECHAT_PROCESS_NAME = 'Weixin.exe';
  WECHAT_DLL_NAME = 'Weixin.dll';

  // ── DB2 table names ────────────────────────────────────────────
  DB2_TABLE_KEY_REFS = 'wechat_key_refs';
  DB2_TABLE_CONTACTS = 'contacts';
  DB2_TABLE_METRICS = 'interaction_metrics';
  DB2_TABLE_HINTS = 'radar_hints';
  DB2_TABLE_EVIDENCE = 'evidence_records';
  DB2_TABLE_AUDIT = 'audit_events';
  DB2_TABLE_CURSORS = 'scan_cursors';

  // ── Application ────────────────────────────────────────────────
  APP_TITLE = 'DeepAxis';
  APP_TITLE_ZH = '序枢';
  APP_VERSION = '0.1.0';

// ── Helper functions ─────────────────────────────────────────────

/// <summary>Convert TDirection to display string.</summary>
function DirectionToStr(const ADir: TDirection): string;

/// <summary>Convert TPrivacyScope to display string.</summary>
function PrivacyScopeToStr(const AScope: TPrivacyScope): string;

/// <summary>Convert TRadarHintType to display string.</summary>
function RadarHintTypeToStr(const AHintType: TRadarHintType): string;

/// <summary>Convert TRadarHintType to Chinese display string.</summary>
function RadarHintTypeToChinese(const AHintType: TRadarHintType): string;

/// <summary>Convert TProfileIdentity to string.</summary>
function ProfileIdentityToStr(const AId: TProfileIdentity): string;

/// <summary>Parse string to TProfileIdentity. Returns piPersonalFull on failure.</summary>
function StrToProfileIdentity(const S: string): TProfileIdentity;

/// <summary>Convert TAxis1State to Chinese display name.</summary>
function Axis1StateToChinese(const AState: TAxis1State): string;

/// <summary>Convert TTier to machine string (green/yellow/red/gray).</summary>
function TierToStr(const ATier: TTier): string;

/// <summary>Convert TTier to Chinese display name.</summary>
function TierToChinese(const ATier: TTier): string;

/// <summary>Convert TTier to emoji color marker.</summary>
function TierToEmoji(const ATier: TTier): string;

/// <summary>Convert TWeChatProcessState to display string.</summary>
function WeChatStateToStr(const AState: TWeChatProcessState): string;

/// <summary>Generate a unique ID string (UUID v4 format).</summary>
function GenerateId: string;

/// <summary>Generate a SHA-256 hash of a string as hex.</summary>
function SHA256Hex(const S: string): string;

implementation

uses
  System.SysUtils, System.Hash;

function DirectionToStr(const ADir: TDirection): string;
begin
  case ADir of
    dInbound:  Result := 'inbound';
    dOutbound: Result := 'outbound';
    dUnknown:  Result := 'unknown';
  end;
end;

function PrivacyScopeToStr(const AScope: TPrivacyScope): string;
begin
  case AScope of
    psBusiness: Result := 'BUSINESS';
    psPrivate:  Result := 'PRIVATE';
    psUnknown:  Result := 'UNKNOWN';
    psIdle:     Result := 'IDLE';
  end;
end;

function RadarHintTypeToStr(const AHintType: TRadarHintType): string;
begin
  case AHintType of
    rhtCooling:          Result := 'COOLING';
    rhtLongSilence:      Result := 'LONG_SILENCE';
    rhtReactivated:      Result := 'REACTIVATED';
    rhtOutboundHeavy:    Result := 'OUTBOUND_HEAVY';
    rhtDataInsufficient: Result := 'DATA_INSUFFICIENT';
    rhtHighLinkSharing:  Result := 'HIGH_LINK_SHARING';
    rhtMarketingPattern: Result := 'MARKETING_PATTERN';
  else
    Result := 'UNKNOWN';
  end;
end;

function RadarHintTypeToChinese(const AHintType: TRadarHintType): string;
begin
  case AHintType of
    rhtCooling:          Result := '互动明显下降';
    rhtLongSilence:      Result := '长期未联系';
    rhtReactivated:      Result := '最近重新活跃';
    rhtOutboundHeavy:    Result := '我发多对方回少';
    rhtDataInsufficient: Result := '数据不足';
    rhtHighLinkSharing:  Result := '高频链接分享';
    rhtMarketingPattern: Result := '营销模式';
  end;
end;

function ProfileIdentityToStr(const AId: TProfileIdentity): string;
begin
  case AId of
    piPersonalFull:      Result := 'personal_full';
    piExternalSafe:      Result := 'external_safe';
    piStrictCompliance:  Result := 'strict_compliance';
  end;
end;

function StrToProfileIdentity(const S: string): TProfileIdentity;
begin
  if SameText(S, 'external_safe') then
    Result := piExternalSafe
  else if SameText(S, 'strict_compliance') then
    Result := piStrictCompliance
  else
    Result := piPersonalFull;
end;

function Axis1StateToChinese(const AState: TAxis1State): string;
begin
  case AState of
    0: Result := '关联未激活';
    1: Result := '知道';
    2: Result := '培育中';
    3: Result := '有意向';
    4: Result := '洽谈中';
    5: Result := '首单';
    6: Result := '复购';
    7: Result := '降温中';
    8: Result := '已流失';
    9: Result := '不适用';
  end;
end;

function TierToStr(const ATier: TTier): string;
begin
  case ATier of
    tGreen:  Result := 'green';
    tYellow: Result := 'yellow';
    tRed:    Result := 'red';
    tGray:   Result := 'gray';
  end;
end;

function TierToChinese(const ATier: TTier): string;
begin
  case ATier of
    tGreen:  Result := '热客';
    tYellow: Result := '待激活';
    tRed:    Result := '闲人';
    tGray:   Result := '数据不足';
  end;
end;

function TierToEmoji(const ATier: TTier): string;
begin
  case ATier of
    tGreen:  Result := '🟢';
    tYellow: Result := '🟡';
    tRed:    Result := '🔴';
    tGray:   Result := '⚪';
  end;
end;

function WeChatStateToStr(const AState: TWeChatProcessState): string;
begin
  case AState of
    wpsNotFound:    Result := '未找到微信进程';
    wpsLaunching:   Result := '正在启动微信...';
    wpsRunning:     Result := '微信已运行';
    wpsScanning:    Result := '正在扫描密钥...';
    wpsKeyFound:    Result := '密钥已找到';
    wpsKeyVerified: Result := '密钥已验证';
    wpsFailed:      Result := '失败';
  end;
end;

function GenerateId: string;
begin
  Result := TGUID.NewGuid.ToString.ToLower.Replace('{', '').Replace('}', '').Replace('-', '');
end;

function SHA256Hex(const S: string): string;
begin
  Result := THashSHA2.GetHashString(S, THashSHA2.TSHA2Version.SHA256);
end;

end.
