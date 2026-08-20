unit DeepFrames.Domain.Types;

interface

type
  TProjectInfo = record
    ProjectId: string;
    Title: string;
    ContentType: string;
    SourceUri: string;
    Status: string;
  end;

  TContentUnitInfo = record
    ContentUnitId: string;
    ProjectId: string;
    UnitType: string;
    DisplayLabel: string;
    OrderIndex: Integer;
    Status: string;
    // external_video_import adapter 来源元数据（docs/12.db）
    SourceType: string;     // original_article|external_video|external_audio|local_file
    OriginUrl: string;      // 外部来源 URL
    LocalPath: string;      // 本地文件路径或下载落盘路径
    LicenseHint: string;    // self|authorized|unknown
    DownloadedAt: string;   // ISO8601 下载时间戳
  end;

  // VAD 分片结果（external_video_import adapter 用）
  TAudioSegment = record
    StartSec: Double;
    DurationSec: Double;
    LocalPath: string;   // 分片音频文件路径
  end;

  TSourceDocumentVersion = record
    DocumentId: string;
    ProjectId: string;
    ContentUnitId: string;
    VersionNo: Integer;
    ContentHash: string;
    MarkdownText: string;
    SourceUri: string;
    Status: string;
  end;

  TDeepFramesJob = record
    JobId: string;
    ProjectId: string;
    ContentUnitId: string;
    JobType: string;
    LogicalKey: string;
    JobQueueTaskId: string;
    Status: string;
  end;

  TDeepFramesJobStep = record
    StepId: string;
    JobId: string;
    StepType: string;
    StepKey: string;
    Status: string;
  end;

  TScriptDocumentVersion = record
    DocumentId: string;
    ProjectId: string;
    ContentUnitId: string;
    VersionNo: Integer;
    ParentDocumentId: string;
    SourceDocumentId: string;
    ContentHash: string;
    Status: string;
  end;

  TAccuracyReport = record
    ReportId: string;
    ProjectId: string;
    SourceDocumentId: string;
    ScriptDocumentId: string;
    CoverageScore: Double;
    DistortionScore: Double;
    Result: string;
    HumanReviewStatus: string;
    ReviewerNote: string;
    Status: string;
  end;

  TVariantDocumentVersion = record
    DocumentId: string;
    ProjectId: string;
    ContentUnitId: string;
    VersionNo: Integer;
    ParentDocumentId: string;
    VariantKind: string;
    VariantLabel: string;
    TargetPlatform: string;
    ContentHash: string;
    Status: string;
  end;

  TShotDocumentVersion = record
    DocumentId: string;
    ProjectId: string;
    ContentUnitId: string;
    VersionNo: Integer;
    ParentDocumentId: string;
    ContentHash: string;
    Status: string;
    PayloadJson: string;   // shot-level script JSON: {shots:[{visual_prompt,...}]} or {segments:[...]}
  end;

  TAssetRecord = record
    AssetId: string;
    AssetType: string;
    Uri: string;
    Sha256: string;
    ByteSize: Int64;
    MimeType: string;
    DurationSec: Double;
    SampleRate: Integer;
    Channels: Integer;
    Codec: string;
    Producer: string;
    ProducerVersion: string;
    Status: string;
    RetentionClass: string;
    ProjectId: string;
    ContentUnitId: string;
  end;

  TQualityGateResult = record
    ResultId: string;
    JobId: string;
    Gate: string;
    GateResult: string;
    Score: Double;
    HumanReviewStatus: string;
    ReviewerNote: string;
  end;

  // Phase 3: Agent chain types

  TPromptTemplate = record
    TemplateId: string;
    Name: string;
    AgentRole: string;
    SystemPrompt: string;
    OutputFormat: string;
    OutputSchemaJson: string;
    ExtractionHintsJson: string;
    FewShotExamplesJson: string;
    SplitRulesJson: string;
    Temperature: Double;
    MaxTokens: Integer;
    VersionNo: Integer;
    Status: string;
  end;

  TPromptRun = record
    RunId: string;
    JobId: string;
    JobStepId: string;
    PromptTemplateId: string;
    PromptVersionNo: Integer;
    ModelBindingId: string;
    AgentRole: string;
    RawOutput: string;
    NormalizedJson: string;
    ValidationError: string;
    RepairCount: Integer;
    TokenInput: Integer;
    TokenOutput: Integer;
    LatencyMs: Integer;
    Provider: string;
    Model: string;
    Capability: string;
    RetryCount: Integer;
    ErrorCode: string;
    Status: string;
    // Phase 4: Audio/TTS/ASR fields
    TtsCharCount: Integer;
    AsrDurationSec: Double;
  end;

  TModelBinding = record
    BindingId: string;
    AgentRole: string;
    Provider: string;
    Model: string;
    Capability: string;
    ApiBaseUrl: string;
    Temperature: Double;
    MaxTokens: Integer;
    Status: string;
  end;

  TEvalResult = record
    EvalId: string;
    JobId: string;
    JobStepId: string;
    PromptRunId: string;
    ShotDocumentId: string;
    EvalType: string;
    Score: Double;
    DimensionsJson: string;
    IssuesJson: string;
    Gate: string;
    GateResult: string;
    RecommendedAction: string;
    ReviewerNote: string;
  end;

  // Phase 4: Audio chain types

  TAudioManifest = record
    ManifestId: string;
    ProjectId: string;
    ContentUnitId: string;
    JobId: string;
    ShotDocumentId: string;
    AudioAssetId: string;
    TimestampsAssetId: string;
    MergedAudioAssetId: string;
    DurationSec: Double;
    SampleRate: Integer;
    Channels: Integer;
    Codec: string;
    BgmEnabled: Boolean;
    TtsRewriteCount: Integer;
    TtsRewriteLogJson: string;
    LoudnormPass1Json: string;
    LoudnormPass2Json: string;
    ResampleFrom: Integer;
    ResampleTo: Integer;
    TargetLufs: Double;
    MeasuredLufs: Double;
    MeasuredTp: Double;
    MeasuredLra: Double;
    ConcatDurationDeltaMs: Double;
    Status: string;
  end;

  // Phase 5: Video chain types

  TPlatformSpec = record
    PlatformSpecId: string;
    Platform: string;
    DeliveryType: string;
    AspectRatio: string;
    Width: Integer;
    Height: Integer;
    Fps: Double;
    VideoCodec: string;
    AudioCodec: string;
    Status: string;
  end;

  TVideoIR = record
    VideoIRId: string;
    ProjectId: string;
    ContentUnitId: string;
    ShotDocumentId: string;
    AudioManifestId: string;
    PlatformSpecId: string;
    RenderBackend: string;
    TemplateVersion: string;
    TimelineJson: string;
    AssetRefsJson: string;
    DurationSource: string;
    EstimatedDurationSec: Double;
    ActualDurationSec: Double;
    SceneCount: Integer;
    VersionNo: Integer;
    Status: string;
  end;

  TVideoJob = record
    VideoJobId: string;
    JobId: string;
    VideoIRId: string;
    PlatformSpecId: string;
    RenderBackend: string;
    RunMode: string;
    TemplateId: string;
    OutputDir: string;
    Status: string;
  end;

  TVideoStep = record
    VideoStepId: string;
    VideoJobId: string;
    StepType: string;
    StepKey: string;
    ShotId: string;
    AssetId: string;
    MetricsJson: string;
    ErrorMessage: string;
    Status: string;
  end;

  TVideoAsset = record
    VideoAssetId: string;
    VideoJobId: string;
    VideoStepId: string;
    AssetId: string;
    AssetCategory: string;
    ShotIndex: Integer;
  end;

  // Phase 6: Candidate package types

  TCandidatePackage = record
    PackageId: string;
    ProjectId: string;
    ContentUnitId: string;
    VariantDocumentId: string;
    AudioManifestId: string;
    VideoIRId: string;
    TargetPlatform: string;
    DeliveryType: string;
    ManifestAssetId: string;
    CoverAssetId: string;
    MetadataJson: string;
    QualitySnapshotJson: string;
    SourceTraceJson: string;
    OutputRootUri: string;
    &Label: string;
    VersionNo: Integer;
    Status: string;
  end;

  // Phase 7: Extension types

  TBgmLibrary = record
    LibraryId: string;
    Name: string;
    Description: string;
    IsDefault: Boolean;
    Status: string;
  end;

  TBgmTrack = record
    TrackId: string;
    LibraryId: string;
    Title: string;
    Artist: string;
    Genre: string;
    MoodTagsJson: string;
    AssetId: string;
    DurationSec: Double;
    Bpm: Integer;
    KeySignature: string;
    LicenseType: string;
    LicenseUri: string;
    FadeInSec: Double;
    FadeOutSec: Double;
    LoopEnabled: Boolean;
    Status: string;
  end;

  TBgmAssociation = record
    AssociationId: string;
    AudioManifestId: string;
    TrackId: string;
    MixVolume: Double;
    StartOffsetSec: Double;
  end;

  TContentTypeAdapter = record
    AdapterId: string;
    ContentType: string;
    DisplayName: string;
    Description: string;
    AdapterClass: string;
    SupportedOutputTypesJson: string;
    DefaultPipelineJson: string;
    ConfigSchemaJson: string;
    VersionNo: Integer;
    Status: string;
  end;

  TReadinessReport = record
    ReportId: string;
    AdapterId: string;
    CheckType: string;
    CheckResult: string;
    Score: Double;
    Summary: string;
    IssuesJson: string;
    EvidenceJson: string;
    VersionNo: Integer;
    Status: string;
  end;

implementation

end.
