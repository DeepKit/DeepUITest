unit DeepAxis.Core.DataTypes;

interface

uses
  System.SysUtils, System.DateUtils, System.JSON,
  DeepAxis.Core.Base;

type
  // ── Data source discovery ──────────────────────────────────────

  TDataSourceScan = record
    ScanId: string;
    SourceAccountId: string;
    Path: string;
    DbFiles: TArray<string>;
    Readable: Boolean;
    FailureReason: string;
    WeChatVersion: string;
    DiscoveredAt: TDateTime;
  end;

  TSchemaReport = record
    ScanId: string;
    AdapterId: string;
    SchemaFingerprint: string;
    Supported: Boolean;
    UnsupportedReason: string;
  end;

  // ── Body-zero audit report ─────────────────────────────────────

  TBodyZeroReport = record
    BodyColumnsSeen: Boolean;
    BodyColumnsQueried: Boolean;
    WriteAttempts: Integer;
    UiaCalls: Integer;
    GeneratedAt: TDateTime;
    function IsClean: Boolean;
    class function CreateClean: TBodyZeroReport; static;
  end;

  // ── Conversation ───────────────────────────────────────────────

  TConversation = record
    ConversationId: string;
    SourceAccountId: string;
    Kind: string; // DIRECT, GROUP, UNKNOWN
    ParticipantRefs: TArray<string>;
    PrivacyScope: TPrivacyScope;
  end;

  // ── Ad track ───────────────────────────────────────────────────

  TAdHistoryEntry = record
    AdAt: TDateTime;
    ContentHash: string;
    HadResponse: Boolean;
    ResponseProductTag: string;
  end;

  TAdTrack = record
    ContactId: string;
    AdCount: Integer;
    LastAdAt: TDateTime;
    AdHistory: TArray<TAdHistoryEntry>;
    IdleStatus: TIdleStatus;
  end;

  // ── Contact ────────────────────────────────────────────────────

  /// <summary>
  ///   Local representation of a WeChat contact. tag_profile is stored as JSON.
  ///   display_name_hash is SHA-256 of the actual display name.
  ///   display_name_redacted is a masked version for display (e.g. "张**").
  /// </summary>
  TContact = record
    ContactId: string;
    SourceAccountId: string;
    DisplayNameHash: string;
    DisplayNameRedacted: string;
    Privacy: TPrivacyScope;
    PrivacySource: TPrivacySource;
    FirstSeen: TDateTime;
    LastSeen: TDateTime;
    TagProfile: string; // JSON
    WeChatLabels: TArray<string>; // imported WeChat label names
    Remark: string; // contact remark (hashed or redacted for privacy)
    MessagePreview: string; // Brief summary of recent messages
    function IsBusiness: Boolean;
    function IsPrivate: Boolean;
    function IsUnknown: Boolean;
    function IsIdle: Boolean;
  end;

  // ── Message metadata ───────────────────────────────────────────

  /// <summary>
  ///   Metadata-only message record. body_queried is ALWAYS False in P0.
  ///   This is a compile-time invariant enforced by BodyZeroReport.
  /// </summary>
  TMessageMeta = record
    SourceAccountId: string;
    ConversationId: string;
    ContactId: string;
    SourceRowRef: string;
    Direction: TDirection;
    DirectionEvidence: string;
    RawType: Int64;
    NormalizedType: TNormalizedMsgType;
    SentAt: TDateTime;
    IngestedAt: TDateTime;
    HasBodyColumn: Boolean;
    BodyQueried: Boolean;
    Body: string;           // Decompressed message content (UTF-8)
    SourceXml: string;      // Decompressed source field (XML with sender info)
    class function CreateM0: TMessageMeta; static;
  end;

  // ── Interaction metric ─────────────────────────────────────────

  TInteractionMetric = record
    MetricId: string;
    ContactId: string;
    ConversationId: string;
    SourceAccountId: string;
    WindowStart: TDateTime;
    WindowEnd: TDateTime;
    LastInteractionAt: TDateTime;
    InboundCount: Integer;
    OutboundCount: Integer;
    ResponseDelayTrend: Double; // seconds, negative = getting faster
    OutboundInboundRatio: Double; // outbound/inbound, or -1 if no inbound
    // Content-based metrics (from message body analysis)
    LinkCount: Integer;           // number of link messages (type=49)
    MediaCount: Integer;          // image + video + voice count
    AvgTextLength: Integer;       // average text message length
    HasMarketingKeywords: Boolean; // contains marketing/promotion keywords
    DataQuality: TDataQuality;
    ComputedAt: TDateTime;
    function IsValid: Boolean;
  end;

  // ── Radar hint ─────────────────────────────────────────────────

  TRadarHint = record
    HintId: string;
    ContactId: string;
    SourceAccountId: string;
    HintType: TRadarHintType;
    Confidence: Double;
    WindowStart: TDateTime;
    WindowEnd: TDateTime;
    ThresholdsUsed: string; // JSON
    Uncertainty: string;
    Prediction: string;
    ExpiresAt: TDateTime;
    RecommendedIntervention: TInterventionRecommendation;
    EvidenceIds: TArray<string>;
    CreatedAt: TDateTime;
  end;

  // ── Evidence record ────────────────────────────────────────────

  TEvidenceRecord = record
    EvidenceId: string;
    HintId: string;
    SourceAccountId: string;
    EvidenceType: TEvidenceType;
    SourceRef: string;
    SourceHash: string; // SHA-256 of referenced MessageMeta fields
    Summary: string;
    ContainsBody: Boolean; // MUST be False in P0
    CreatedAt: TDateTime;
  end;

  // ── Audit event ────────────────────────────────────────────────

  TAuditEvent = record
    AuditId: string;
    EventType: TAuditEventType;
    PreviousAuditHash: string;
    SourceAccountId: string;
    DataCategories: TArray<string>;
    BodyColumnsSeen: Boolean;
    BodyColumnsQueried: Boolean;
    WriteAttempts: Integer;
    UiaCalls: Integer;
    CreatedAt: TDateTime;
    function ToJSON: string;
    class function Create(const AEventType: TAuditEventType;
      const APreviousHash: string): TAuditEvent; static;
  end;

  // ── Deletion manifest ──────────────────────────────────────────

  TDeletionManifest = record
    DeletionId: string;
    TargetScope: string;
    DeletedObjects: TArray<string>;
    RetainedAuditSummary: string;
    CreatedAt: TDateTime;
  end;

  // ── WeChat key capture result ──────────────────────────────────

  TWeChatKeyCaptureResult = record
    State: TWeChatProcessState;
    KeyHex: string;
    KeyBytes: TBytes;
    WeChatPid: Cardinal;
    WeChatVersion: string;
    ErrorMessage: string;
    function IsSuccess: Boolean;
  end;

  // ── Poll result ────────────────────────────────────────────────

  TPollResult = record
    Contacts: TArray<TContact>;
    Metrics: TArray<TInteractionMetric>;
    Hints: TArray<TRadarHint>;
    EvidenceRecords: TArray<TEvidenceRecord>;
    AuditEvents: TArray<TAuditEvent>;
    NewMessageCount: Integer;
    UpdatedAt: TDateTime;
  end;

  // ── Pipeline state ─────────────────────────────────────────────

  TPipelineState = record
    LastCompletedTask: string;
    ScanCursors: TScanCursorArray;
    ComputedAt: TDateTime;
    function FindCursor(const AContactId: string): TScanCursor;
    procedure SetCursor(const ACursor: TScanCursor);
  end;

implementation

// ── TBodyZeroReport ──────────────────────────────────────────────

function TBodyZeroReport.IsClean: Boolean;
begin
  Result := (not BodyColumnsQueried) and (WriteAttempts = 0) and (UiaCalls = 0);
end;

class function TBodyZeroReport.CreateClean: TBodyZeroReport;
begin
  Result := Default(TBodyZeroReport);
  Result.BodyColumnsSeen := False;
  Result.BodyColumnsQueried := False;
  Result.WriteAttempts := 0;
  Result.UiaCalls := 0;
  Result.GeneratedAt := Now;
end;

// ── TContact ─────────────────────────────────────────────────────

function TContact.IsBusiness: Boolean;
begin
  Result := (Privacy = psBusiness);
end;

function TContact.IsPrivate: Boolean;
begin
  Result := (Privacy = psPrivate);
end;

function TContact.IsUnknown: Boolean;
begin
  Result := (Privacy = psUnknown);
end;

function TContact.IsIdle: Boolean;
begin
  Result := (Privacy = psIdle);
end;

// ── TMessageMeta ─────────────────────────────────────────────────

class function TMessageMeta.CreateM0: TMessageMeta;
begin
  Result := Default(TMessageMeta);
  Result.Direction := dUnknown;
  Result.NormalizedType := nmtUnknown;
  Result.SentAt := 0;
  Result.IngestedAt := Now;
  Result.HasBodyColumn := False;
  Result.BodyQueried := True;  // User command: read message bodies
  Result.Body := '';
  Result.SourceXml := '';
end;

// ── TInteractionMetric ───────────────────────────────────────────

function TInteractionMetric.IsValid: Boolean;
begin
  Result := (DataQuality <> dqDataInsufficient) and (MetricId <> '');
end;

// ── TAuditEvent ──────────────────────────────────────────────────

function TAuditEvent.ToJSON: string;
var
  LObj: TJSONObject;
  LArr: TJSONArray;
  S: string;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('audit_id', AuditId);
    LObj.AddPair('event_type', Ord(EventType).ToString);
    LObj.AddPair('previous_audit_hash', PreviousAuditHash);
    LObj.AddPair('source_account_id', SourceAccountId);
    LArr := TJSONArray.Create;
    for S in DataCategories do
      LArr.Add(S);
    LObj.AddPair('data_categories', LArr);
    LObj.AddPair('body_columns_seen', TJSONBool.Create(BodyColumnsSeen));
    LObj.AddPair('body_columns_queried', TJSONBool.Create(BodyColumnsQueried));
    LObj.AddPair('write_attempts', TJSONNumber.Create(WriteAttempts));
    LObj.AddPair('uia_calls', TJSONNumber.Create(UiaCalls));
    LObj.AddPair('created_at', DateToISO8601(CreatedAt));
    Result := LObj.ToJSON;
  finally
    LObj.Free;
  end;
end;

class function TAuditEvent.Create(const AEventType: TAuditEventType;
  const APreviousHash: string): TAuditEvent;
begin
  Result := Default(TAuditEvent);
  Result.AuditId := GenerateId;
  Result.EventType := AEventType;
  Result.PreviousAuditHash := APreviousHash;
  Result.BodyColumnsSeen := False;
  Result.BodyColumnsQueried := False;
  Result.WriteAttempts := 0;
  Result.UiaCalls := 0;
  Result.CreatedAt := Now;
end;

// ── TWeChatKeyCaptureResult ──────────────────────────────────────

function TWeChatKeyCaptureResult.IsSuccess: Boolean;
begin
  Result := (State in [wpsKeyFound, wpsKeyVerified]);
end;

// ── TPipelineState ───────────────────────────────────────────────

function TPipelineState.FindCursor(const AContactId: string): TScanCursor;
var
  I: Integer;
begin
  for I := 0 to Length(ScanCursors) - 1 do
    if ScanCursors[I].ContactId = AContactId then
      Exit(ScanCursors[I]);
  Result := Default(TScanCursor);
  Result.ContactId := AContactId;
end;

procedure TPipelineState.SetCursor(const ACursor: TScanCursor);
var
  I: Integer;
begin
  for I := 0 to Length(ScanCursors) - 1 do
    if ScanCursors[I].ContactId = ACursor.ContactId then
    begin
      ScanCursors[I] := ACursor;
      Exit;
    end;
  SetLength(ScanCursors, Length(ScanCursors) + 1);
  ScanCursors[High(ScanCursors)] := ACursor;
end;

end.