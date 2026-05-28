{ ============================================================================
  DeepSpec.Models

  Core data model records corresponding to the DeepSpec Protocol v1.1.
  These records map 1:1 to the YAML schemas in protocol/schemas/.
  ============================================================================ }

unit DeepSpec.Models;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  TTreeType = (ttFunction, ttModule, ttView, ttData);

  TNodeStatus = (nsCandidate, nsConfirmed, nsUncertain, nsRejected, nsSuperseded);

  TGenStatus = (gsDraft, gsGenerated, gsConfirmed, gsSkipped);

  TReviewStatus = (rsUnreviewed, rsAccepted, rsRejected, rsDeferred);

  TConfidenceLevel = (clLow, clMedium, clHigh);

  TSourceLayer = (slParsedFromA, slHumanDecision, slAiInferred, slGeneratedSummary);

  TFunctionKind = (fkFeature, fkCapability, fkUserStory, fkUseCase,
    fkRule, fkConstraint, fkNonFunctional, fkIntegration, fkExtended);

  TModuleKind = (mkPackage, mkUnit, mkClass, mkInterface, mkService,
    mkRepository, mkController, mkAdapter, mkUtility, mkConfig, mkExtended);

  TViewKind = (vkApplication, vkWindow, vkDialog, vkPage, vkFrame,
    vkPanel, vkControl, vkMenu, vkToolbar, vkStatusbar, vkTray, vkExtended);

  TDataKind = (dkEntity, dkField, dkRelation, dkState, dkMigration, dkConstraint, dkExtended);

  TRiskLevel = (rlLow, rlMedium, rlHigh, rlCritical);

  TRelationType = (rtContains, rtDependsOn, rtImplements, rtPresentedBy,
    rtOwnedBy, rtConstrainedBy, rtConflictsWith, rtDerivedFrom,
    rtTriggers, rtExtends);

  TIssueSeverity = (isCritical, isHigh, isMedium, isLow, isInfo);

  TIssueType = (itMissingRequirement, itConflict, itAmbiguity, itStaleDoc,
    itNoSource, itLowConfidence, itParseWarning, itParseError,
    itOrphanNode, itCoverageGap);

  TIssueStatus = (issOpen, issResolved, issWontfix, issDeferred);

  TDecisionType = (dtConfirm, dtReject, dtClarify, dtGapFill, dtResolveConflict,
    dtScope, dtPriority, dtTerminology, dtViewMapping, dtModuleMapping,
    dtPermission, dtRule);

  TDecisionStatus = (dsProposed, dsAccepted, dsRejected, dsSuperseded,
    dsRolledBack, dsWithdrawn);

  TDecidedBy = (dbHuman, dbSystem);

  TPriorityLevel = (plP0, plP1, plP2, plLater);

  /// <summary>
  /// Reference to evidence by id, with optional relevance and note.
  /// </summary>
  TSourceRef = record
    RefId: string;
    Relevance: string;     // 'primary' | 'supporting' | 'contradicting' | ''
    Note: string;
  end;

  TSourceRefArray = TArray<TSourceRef>;

  /// <summary>
  /// A node in one of the three trees. Field names match protocol §4.
  /// </summary>
  TSpecNode = record
    Id: string;
    Tree: TTreeType;
    Title: string;
    Kind: string;             // string to support x_ extensions
    ParentId: string;
    SlugOverride: string;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
    ContentHash: string;
    RelationHash: string;
    Revision: Integer;
    Summary: string;
    Status: TNodeStatus;
    GenStatus: TGenStatus;
    ReviewStatus: TReviewStatus;
    Confidence: TConfidenceLevel;
    SourceLayer: TSourceLayer;
    SourceRefs: TSourceRefArray;
    DecisionRefs: TArray<string>;
    IssueRefs: TArray<string>;
    RelatedFunctions: TArray<string>;
    RelatedModules: TArray<string>;
    RelatedViews: TArray<string>;
    RelatedData: TArray<string>;
    RiskScore: TRiskLevel;
    HasRiskScore: Boolean;
    DataType: string;
    Nullable: Boolean;
    HasNullable: Boolean;
    DefaultValue: string;
    FieldConstraints: TArray<string>;
    Persistence: string;
    SourceEntity: string;
    TargetEntity: string;
    Cardinality: string;
    Cascade: string;
    ValidStates: TArray<string>;
    Transitions: TArray<TPair<string, string>>;
    BackwardCompatible: Boolean;
    HasBackwardCompatible: Boolean;
    HasRollback: Boolean;
    HasHasRollback: Boolean;
    Scope: string;
    Enforcement: string;
    Children: TArray<string>;
    Tags: TArray<string>;
    AcceptanceCriteria: TArray<string>;
    NotDoing: TArray<string>;
    class function MakeNew(const AId: string; ATree: TTreeType;
      const ATitle, AKind: string): TSpecNode; static;
  end;

  TSpecNodeList = TList<TSpecNode>;

  TSemanticBundle = record
    Id: string;
    Title: string;
    Description: string;
    NodeIds: TArray<string>;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
  end;

  TSpecRelation = record
    Id: string;
    FromId: string;
    ToId: string;
    RelType: TRelationType;
    Confidence: TConfidenceLevel;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
    SourceRefs: TSourceRefArray;
    DecisionRefs: TArray<string>;
    Note: string;
  end;

  TSpecEvidence = record
    Id: string;
    SourceLayer: TSourceLayer;
    Path: string;
    Lines: string;
    Excerpt: string;
    ExcerptTruncated: Boolean;
    Note: string;
    Confidence: TConfidenceLevel;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
    ContentHash: string;
    SourceFileHash: string;
    IsStale: Boolean;
    ReferencedBy: TArray<string>;
  end;

  TSpecIssue = record
    Id: string;
    Severity: TIssueSeverity;
    IssueType: TIssueType;
    Title: string;
    Description: string;
    AffectedNodes: TArray<string>;
    SourceRefs: TSourceRefArray;
    SuggestedAction: string;
    SuggestedPrompt: string;
    Status: TIssueStatus;
    ResolvedBy: string;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
    ResolvedAt: TDateTime;
  end;

  TSpecDecision = record
    Id: string;
    DecisionType: TDecisionType;
    Title: string;
    DecisionText: string;
    Rationale: string;
    TargetNodes: TArray<string>;
    AffectedRelations: TArray<string>;
    AffectedRequirements: TArray<string>;
    AffectedViews: TArray<string>;
    AffectedModules: TArray<string>;
    ResolvedIssues: TArray<string>;
    SourceRefs: TSourceRefArray;
    AiInstruction: string;
    Priority: TPriorityLevel;
    HasPriority: Boolean;
    Release: string;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
    DecidedBy: TDecidedBy;
    Confidence: TConfidenceLevel;
    Status: TDecisionStatus;
    SupersededBy: string;
    Supersedes: TArray<string>;
  end;

  /// <summary>
  /// String conversion helpers for enum values matching protocol enum names.
  /// </summary>
  TSpecEnums = class
  public
    class function TreeTypeToStr(AValue: TTreeType): string; static;
    class function NodeStatusToStr(AValue: TNodeStatus): string; static;
    class function ConfidenceToStr(AValue: TConfidenceLevel): string; static;
    class function SourceLayerToStr(AValue: TSourceLayer): string; static;
    class function RelationTypeToStr(AValue: TRelationType): string; static;
    class function IssueSeverityToStr(AValue: TIssueSeverity): string; static;
    class function IssueTypeToStr(AValue: TIssueType): string; static;
    class function IssueStatusToStr(AValue: TIssueStatus): string; static;
    class function DecisionTypeToStr(AValue: TDecisionType): string; static;
    class function DecisionStatusToStr(AValue: TDecisionStatus): string; static;
    class function DecidedByToStr(AValue: TDecidedBy): string; static;
    class function PriorityToStr(AValue: TPriorityLevel): string; static;

    class function TreeTypeFromStr(const AValue: string;
      ADefault: TTreeType = ttFunction): TTreeType; static;
    class function NodeStatusFromStr(const AValue: string;
      ADefault: TNodeStatus = nsCandidate): TNodeStatus; static;
    class function ConfidenceFromStr(const AValue: string;
      ADefault: TConfidenceLevel = clMedium): TConfidenceLevel; static;
    class function SourceLayerFromStr(const AValue: string;
      ADefault: TSourceLayer = slAiInferred): TSourceLayer; static;
    class function DataKindToStr(AValue: TDataKind): string; static;
    class function DataKindFromStr(const AValue: string;
      ADefault: TDataKind = dkEntity): TDataKind; static;
    class function RiskLevelToStr(AValue: TRiskLevel): string; static;
    class function RiskLevelFromStr(const AValue: string;
      ADefault: TRiskLevel = rlMedium): TRiskLevel; static;
    class function GenStatusToStr(AValue: TGenStatus): string; static;
    class function GenStatusFromStr(const AValue: string;
      ADefault: TGenStatus = gsDraft): TGenStatus; static;
    class function ReviewStatusToStr(AValue: TReviewStatus): string; static;
    class function ReviewStatusFromStr(const AValue: string;
      ADefault: TReviewStatus = rsUnreviewed): TReviewStatus; static;

    /// <summary>Validate GenStatus transition. Returns True if allowed.</summary>
    class function CanTransitionGen(AFrom, ATo: TGenStatus): Boolean; static;
    /// <summary>Validate ReviewStatus transition. Returns True if allowed.</summary>
    class function CanTransitionReview(AFrom, ATo: TReviewStatus): Boolean; static;
    /// <summary>Attempt GenStatus transition. Returns error message or ''.</summary>
    class function TryTransitionGen(var ACurrent: TGenStatus; ATo: TGenStatus;
      out AError: string): Boolean; static;
    /// <summary>Attempt ReviewStatus transition. Returns error message or ''.</summary>
    class function TryTransitionReview(var ACurrent: TReviewStatus; ATo: TReviewStatus;
      out AError: string): Boolean; static;
  end;

implementation

uses
  System.DateUtils;

{ TSpecNode }

class function TSpecNode.MakeNew(const AId: string; ATree: TTreeType;
  const ATitle, AKind: string): TSpecNode;
begin
  Result := Default(TSpecNode);
  Result.Id := AId;
  Result.Tree := ATree;
  Result.Title := ATitle;
  Result.Kind := AKind;
  Result.Status := nsCandidate;
  Result.GenStatus := gsDraft;
  Result.ReviewStatus := rsUnreviewed;
  Result.Confidence := clMedium;
  Result.SourceLayer := slAiInferred;
  Result.Revision := 1;
  Result.CreatedAt := Now;
  Result.UpdatedAt := Now;
end;

{ TSpecEnums }

class function TSpecEnums.TreeTypeToStr(AValue: TTreeType): string;
begin
  case AValue of
    ttFunction: Result := 'function';
    ttModule:   Result := 'module';
    ttView:     Result := 'view';
    ttData:     Result := 'data';
  end;
end;

class function TSpecEnums.NodeStatusToStr(AValue: TNodeStatus): string;
begin
  case AValue of
    nsCandidate:  Result := 'candidate';
    nsConfirmed:  Result := 'confirmed';
    nsUncertain:  Result := 'uncertain';
    nsRejected:   Result := 'rejected';
    nsSuperseded: Result := 'superseded';
  end;
end;

class function TSpecEnums.ConfidenceToStr(AValue: TConfidenceLevel): string;
begin
  case AValue of
    clLow:    Result := 'low';
    clMedium: Result := 'medium';
    clHigh:   Result := 'high';
  end;
end;

class function TSpecEnums.SourceLayerToStr(AValue: TSourceLayer): string;
begin
  case AValue of
    slParsedFromA:     Result := 'parsed_from_a';
    slHumanDecision:   Result := 'human_decision';
    slAiInferred:      Result := 'ai_inferred';
    slGeneratedSummary: Result := 'generated_summary';
  end;
end;

class function TSpecEnums.RelationTypeToStr(AValue: TRelationType): string;
begin
  case AValue of
    rtContains:      Result := 'contains';
    rtDependsOn:     Result := 'depends_on';
    rtImplements:    Result := 'implements';
    rtPresentedBy:   Result := 'presented_by';
    rtOwnedBy:       Result := 'owned_by';
    rtConstrainedBy: Result := 'constrained_by';
    rtConflictsWith: Result := 'conflicts_with';
    rtDerivedFrom:   Result := 'derived_from';
    rtTriggers:      Result := 'triggers';
    rtExtends:       Result := 'extends';
  end;
end;

class function TSpecEnums.IssueSeverityToStr(AValue: TIssueSeverity): string;
begin
  case AValue of
    isCritical: Result := 'critical';
    isHigh:     Result := 'high';
    isMedium:   Result := 'medium';
    isLow:      Result := 'low';
    isInfo:     Result := 'info';
  end;
end;

class function TSpecEnums.IssueTypeToStr(AValue: TIssueType): string;
begin
  case AValue of
    itMissingRequirement: Result := 'missing_requirement';
    itConflict:           Result := 'conflict';
    itAmbiguity:          Result := 'ambiguity';
    itStaleDoc:           Result := 'stale_doc';
    itNoSource:           Result := 'no_source';
    itLowConfidence:      Result := 'low_confidence';
    itParseWarning:       Result := 'parse_warning';
    itParseError:         Result := 'parse_error';
    itOrphanNode:         Result := 'orphan_node';
    itCoverageGap:        Result := 'coverage_gap';
  end;
end;

class function TSpecEnums.IssueStatusToStr(AValue: TIssueStatus): string;
begin
  case AValue of
    issOpen:     Result := 'open';
    issResolved: Result := 'resolved';
    issWontfix:  Result := 'wontfix';
    issDeferred: Result := 'deferred';
  end;
end;

class function TSpecEnums.DecisionTypeToStr(AValue: TDecisionType): string;
begin
  case AValue of
    dtConfirm:         Result := 'confirm';
    dtReject:          Result := 'reject';
    dtClarify:         Result := 'clarify';
    dtGapFill:         Result := 'gap_fill';
    dtResolveConflict: Result := 'resolve_conflict';
    dtScope:           Result := 'scope';
    dtPriority:        Result := 'priority';
    dtTerminology:     Result := 'terminology';
    dtViewMapping:     Result := 'view_mapping';
    dtModuleMapping:   Result := 'module_mapping';
    dtPermission:      Result := 'permission';
    dtRule:            Result := 'rule';
  end;
end;

class function TSpecEnums.DecisionStatusToStr(AValue: TDecisionStatus): string;
begin
  case AValue of
    dsProposed:   Result := 'proposed';
    dsAccepted:   Result := 'accepted';
    dsRejected:   Result := 'rejected';
    dsSuperseded: Result := 'superseded';
    dsRolledBack: Result := 'rolled_back';
    dsWithdrawn:  Result := 'withdrawn';
  end;
end;

class function TSpecEnums.DecidedByToStr(AValue: TDecidedBy): string;
begin
  if AValue = dbHuman then Result := 'human' else Result := 'system';
end;

class function TSpecEnums.PriorityToStr(AValue: TPriorityLevel): string;
begin
  case AValue of
    plP0:    Result := 'P0';
    plP1:    Result := 'P1';
    plP2:    Result := 'P2';
    plLater: Result := 'later';
  end;
end;

class function TSpecEnums.TreeTypeFromStr(const AValue: string;
  ADefault: TTreeType): TTreeType;
begin
  var LLower := LowerCase(AValue.Trim);
  if LLower = 'function' then Result := ttFunction
  else if LLower = 'module' then Result := ttModule
  else if LLower = 'view' then Result := ttView
  else if LLower = 'data' then Result := ttData
  else Result := ADefault;
end;

class function TSpecEnums.NodeStatusFromStr(const AValue: string;
  ADefault: TNodeStatus): TNodeStatus;
begin
  var LLower := LowerCase(AValue.Trim);
  if LLower = 'candidate' then Result := nsCandidate
  else if LLower = 'confirmed' then Result := nsConfirmed
  else if LLower = 'uncertain' then Result := nsUncertain
  else if LLower = 'rejected' then Result := nsRejected
  else if LLower = 'superseded' then Result := nsSuperseded
  else Result := ADefault;
end;

class function TSpecEnums.ConfidenceFromStr(const AValue: string;
  ADefault: TConfidenceLevel): TConfidenceLevel;
begin
  var LLower := LowerCase(AValue.Trim);
  if LLower = 'low' then Result := clLow
  else if LLower = 'medium' then Result := clMedium
  else if LLower = 'high' then Result := clHigh
  else Result := ADefault;
end;

class function TSpecEnums.SourceLayerFromStr(const AValue: string;
  ADefault: TSourceLayer): TSourceLayer;
begin
  var LLower := LowerCase(AValue.Trim);
  if LLower = 'parsed_from_a' then Result := slParsedFromA
  else if LLower = 'human_decision' then Result := slHumanDecision
  else if LLower = 'ai_inferred' then Result := slAiInferred
  else if LLower = 'generated_summary' then Result := slGeneratedSummary
  else Result := ADefault;
end;

class function TSpecEnums.DataKindToStr(AValue: TDataKind): string;
begin
  case AValue of
    dkEntity:    Result := 'entity';
    dkField:     Result := 'field';
    dkRelation:  Result := 'relation';
    dkState:     Result := 'state';
    dkMigration: Result := 'migration';
    dkConstraint:Result := 'constraint';
    dkExtended:  Result := 'x_extended';
  end;
end;

class function TSpecEnums.DataKindFromStr(const AValue: string;
  ADefault: TDataKind): TDataKind;
begin
  var LLower := LowerCase(AValue.Trim);
  if LLower = 'entity' then Result := dkEntity
  else if LLower = 'field' then Result := dkField
  else if LLower = 'relation' then Result := dkRelation
  else if LLower = 'state' then Result := dkState
  else if LLower = 'migration' then Result := dkMigration
  else if LLower = 'constraint' then Result := dkConstraint
  else Result := ADefault;
end;

class function TSpecEnums.RiskLevelToStr(AValue: TRiskLevel): string;
begin
  case AValue of
    rlLow:      Result := 'low';
    rlMedium:   Result := 'medium';
    rlHigh:     Result := 'high';
    rlCritical: Result := 'critical';
  end;
end;

class function TSpecEnums.RiskLevelFromStr(const AValue: string;
  ADefault: TRiskLevel): TRiskLevel;
begin
  var LLower := LowerCase(AValue.Trim);
  if LLower = 'low' then Result := rlLow
  else if LLower = 'medium' then Result := rlMedium
  else if LLower = 'high' then Result := rlHigh
  else if LLower = 'critical' then Result := rlCritical
  else Result := ADefault;
end;

class function TSpecEnums.GenStatusToStr(AValue: TGenStatus): string;
begin
  case AValue of
    gsDraft:     Result := 'draft';
    gsGenerated: Result := 'generated';
    gsConfirmed: Result := 'confirmed';
    gsSkipped:   Result := 'skipped';
  end;
end;

class function TSpecEnums.GenStatusFromStr(const AValue: string;
  ADefault: TGenStatus): TGenStatus;
begin
  var LLower := LowerCase(AValue.Trim);
  if LLower = 'draft' then Result := gsDraft
  else if LLower = 'generated' then Result := gsGenerated
  else if LLower = 'confirmed' then Result := gsConfirmed
  else if LLower = 'skipped' then Result := gsSkipped
  else Result := ADefault;
end;

class function TSpecEnums.ReviewStatusToStr(AValue: TReviewStatus): string;
begin
  case AValue of
    rsUnreviewed: Result := 'unreviewed';
    rsAccepted:   Result := 'accepted';
    rsRejected:   Result := 'rejected';
    rsDeferred:   Result := 'deferred';
  end;
end;

class function TSpecEnums.ReviewStatusFromStr(const AValue: string;
  ADefault: TReviewStatus): TReviewStatus;
begin
  var LLower := LowerCase(AValue.Trim);
  if LLower = 'unreviewed' then Result := rsUnreviewed
  else if LLower = 'accepted' then Result := rsAccepted
  else if LLower = 'rejected' then Result := rsRejected
  else if LLower = 'deferred' then Result := rsDeferred
  else Result := ADefault;
end;

class function TSpecEnums.CanTransitionGen(AFrom, ATo: TGenStatus): Boolean;
begin
  // GenStatus state machine:
  //   draft → generated → confirmed
  //   draft → skipped
  //   generated → skipped
  //   confirmed is terminal
  //   skipped is terminal
  //   Any → same (no-op)
  if AFrom = ATo then Exit(True);
  case AFrom of
    gsDraft:     Result := ATo in [gsGenerated, gsSkipped];
    gsGenerated: Result := ATo in [gsConfirmed, gsSkipped];
    gsConfirmed: Result := False; // terminal
    gsSkipped:   Result := False; // terminal
  else
    Result := False;
  end;
end;

class function TSpecEnums.CanTransitionReview(AFrom, ATo: TReviewStatus): Boolean;
begin
  // ReviewStatus state machine:
  //   unreviewed → accepted / rejected / deferred
  //   deferred → accepted / rejected
  //   accepted is terminal
  //   rejected is terminal
  //   Any → same (no-op)
  if AFrom = ATo then Exit(True);
  case AFrom of
    rsUnreviewed: Result := ATo in [rsAccepted, rsRejected, rsDeferred];
    rsDeferred:   Result := ATo in [rsAccepted, rsRejected];
    rsAccepted:   Result := False; // terminal
    rsRejected:   Result := False; // terminal
  else
    Result := False;
  end;
end;

class function TSpecEnums.TryTransitionGen(var ACurrent: TGenStatus;
  ATo: TGenStatus; out AError: string): Boolean;
begin
  if CanTransitionGen(ACurrent, ATo) then
  begin
    ACurrent := ATo;
    AError := '';
    Result := True;
  end
  else
  begin
    AError := Format('Invalid GenStatus transition: %s -> %s',
      [GenStatusToStr(ACurrent), GenStatusToStr(ATo)]);
    Result := False;
  end;
end;

class function TSpecEnums.TryTransitionReview(var ACurrent: TReviewStatus;
  ATo: TReviewStatus; out AError: string): Boolean;
begin
  if CanTransitionReview(ACurrent, ATo) then
  begin
    ACurrent := ATo;
    AError := '';
    Result := True;
  end
  else
  begin
    AError := Format('Invalid ReviewStatus transition: %s -> %s',
      [ReviewStatusToStr(ACurrent), ReviewStatusToStr(ATo)]);
    Result := False;
  end;
end;

end.
