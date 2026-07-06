unit DeepAxis.Core.Contracts;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DeepAxis.Core.Base,
  DeepAxis.Core.DataTypes;

type
  // ── Schema adapter (forward-use by IWxReader) ──────────────────

  ISchemaAdapter = interface
    ['{E5F6A7B8-C9D0-1234-EFAB-345678901234}']
    function GetAdapterId: string;
    function GetSchemaFingerprint: string;
    function GetSupportedVersionRange: string;
    function GetAllowedFields: TArray<string>;
    function GetForbiddenFields: TArray<string>;
    function MapDirection(const ARawValue: Int64): TDirection;
    function GetTimestampColumn: string;
    function MapType(const ARawType: Int64): TNormalizedMsgType;
    function IsDegraded: Boolean;
    function GetDegradedFields: TArray<string>;
    function GetMsgTablePrefix: string;
    function GetContactTableName: string;
    function GetConversationTableName: string;
  end;

  // ── WeChat reader ──────────────────────────────────────────────

  IWxReader = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    function Open(const ADbPath: string; const AKeyBytes: TBytes): Boolean;
    function OpenPaths(const AContactPath, AMessage0Path, ASessionPath: string): Boolean;
    function ReadContacts: TArray<TContact>;
    function ReadMessages(const AContactId: string;
      const ASince: TScanCursor): TArray<TMessageMeta>;
    /// <summary>
    ///   Read all messages grouped by contact ID.
    ///   Ownership: Caller owns the returned TDictionary and must Free it.
    ///   The TArray&lt;TMessageMeta&gt; values are managed (no manual free needed).
    /// </summary>
    function ReadAllMessages(const ASince: TScanCursor):
      TDictionary<string, TArray<TMessageMeta>>;
    function ReadConversations: TArray<TConversation>;
    function GetScanCursors: TScanCursorArray;
    procedure Close;
    function IsOpen: Boolean;
    function GetAdapter: ISchemaAdapter;
  end;

  // ── Metric calculator ──────────────────────────────────────────

  IMetricCalculator = interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']
    function Compute(const AMessages: TArray<TMessageMeta>;
      const AOldMetric: TInteractionMetric): TInteractionMetric;
    function ComputeBatch(const AContacts: TArray<TContact>;
      const AMessagesByContact: TArray<TMessageMeta>;
      const AOldMetrics: TArray<TInteractionMetric>): TArray<TInteractionMetric>;
  end;

  // ── Radar engine ───────────────────────────────────────────────

  IRadarEngine = interface
    ['{C3D4E5F6-A7B8-9012-CDEF-123456789012}']
    function Generate(const AMetrics: TArray<TInteractionMetric>;
      const AContacts: TArray<TContact>;
      const AOldMetrics: TArray<TInteractionMetric>): TArray<TRadarHint>;
  end;

  // ── Evidence builder ───────────────────────────────────────────

  IEvidenceBuilder = interface
    ['{D4E5F6A7-B8C9-0123-DEFA-234567890123}']
    function Build(const AHint: TRadarHint;
      const AMetrics: TArray<TInteractionMetric>): TArray<TEvidenceRecord>;
    function BuildBodyZeroReport: TBodyZeroReport;
  end;

  // ── Tag engine ─────────────────────────────────────────────────

  ITagEngine = interface
    ['{F6A7B8C9-D0E1-2345-FABC-456789012345}']
    function DeriveTags(const AContact: TContact;
      const AMetrics: TArray<TInteractionMetric>;
      const AMessages: TArray<TMessageMeta>): TContact;
    function DeriveTagsBatch(const AContacts: TArray<TContact>;
      const AMetrics: TArray<TInteractionMetric>;
      const AMessagesByContact: TDictionary<string, TArray<TMessageMeta>>): TArray<TContact>;
  end;

  // ── Idle funnel ────────────────────────────────────────────────

  IIdleFunnel = interface
    ['{A7B8C9D0-E1F2-3456-ABCD-567890123456}']
    function ClassifyContacts(const AContacts: TArray<TContact>): TArray<TContact>;
    function GetAdSuggestions(const AContact: TContact): string;
    function GetDeletionCandidates(const AContacts: TArray<TContact>): TArray<TContact>;
  end;

  // ── State machine ──────────────────────────���───────────────────

  IStateMachine = interface
    ['{B8C9D0E1-F2A3-4567-BCDE-678901234567}']
    function GetAxis1State(const AContact: TContact): TAxis1State;
    function TransitState(const AContact: TContact;
      const ATrigger: string): TAxis1State;
    function GetTransitionEvents(const AContact: TContact): TArray<string>;
    function GetStateLabel(const AState: TAxis1State): string;
  end;

  // ── Pipeline orchestrator ──────────────────────────────────────

  IPipelineOrchestrator = interface
    ['{C9D0E1F2-A3B4-5678-CDEF-789012345678}']
    function RunPipeline(const AState: TPipelineState;
      const AContacts: TArray<TContact>;
      const AMessages: TArray<TMessageMeta>): TPollResult;
    procedure SetReader(const AReader: IWxReader);
    procedure SetMetricCalculator(const ACalc: IMetricCalculator);
    procedure SetRadarEngine(const AEngine: IRadarEngine);
    procedure SetEvidenceBuilder(const ABuilder: IEvidenceBuilder);
    procedure SetTagEngine(const AEngine: ITagEngine);
    procedure SetIdleFunnel(const AFunnel: IIdleFunnel);
  end;

implementation

end.