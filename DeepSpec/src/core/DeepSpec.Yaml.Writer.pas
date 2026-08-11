
{ ============================================================================
  DeepSpec.Yaml.Writer

  Lightweight YAML writer for DeepSpec data model. Writes schema-compliant
  YAML files for trees, relations, evidence, issues, and decisions.

  This is a write-only implementation. Reading YAML requires a parser
  library (planned for P2 LLM merge phase).
  ============================================================================ }

unit DeepSpec.Yaml.Writer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DeepSpec.Models;

type
  TYamlWriter = class
  private
    FBuilder: TStringBuilder;
    FIndent: Integer;
    function Pad: string;
    function EscapeStr(const S: string): string;
    function FormatTimestamp(ADt: TDateTime): string;
    procedure WriteScalarKV(const AKey, AValue: string);
    procedure WriteQuotedKV(const AKey, AValue: string);
    procedure WriteIntKV(const AKey: string; AValue: Integer);
    procedure WriteBoolKV(const AKey: string; AValue: Boolean);
    procedure WriteStringList(const AKey: string; const AValues: TArray<string>);
    procedure WriteSourceRefs(const AKey: string; const ARefs: TSourceRefArray);
    procedure WriteDataNodeFields(const ANode: TSpecNode);
  public
    constructor Create;
    destructor Destroy; override;
    function ToString: string; override;

    procedure WriteTreeFile(ATree: TTreeType; const AGenerator: string;
      ANodes: TList<TSpecNode>);
    procedure WriteNode(const ANode: TSpecNode);

    procedure WriteRelationsFile(ARelations: TList<TSpecRelation>);
    procedure WriteRelation(const ARel: TSpecRelation);

    procedure WriteEvidenceFile(AEvidence: TList<TSpecEvidence>);
    procedure WriteEvidence(const AEv: TSpecEvidence);

    procedure WriteIssuesFile(AIssues: TList<TSpecIssue>);
    procedure WriteIssue(const AIssue: TSpecIssue);

    procedure WriteDecisionsFile(ADecisions: TList<TSpecDecision>);
    procedure WriteDecision(const ADec: TSpecDecision);
  end;

implementation

uses
  System.DateUtils,
  System.StrUtils;

constructor TYamlWriter.Create;
begin
  inherited Create;
  FBuilder := TStringBuilder.Create;
  FIndent := 0;
end;

destructor TYamlWriter.Destroy;
begin
  FBuilder.Free;
  inherited;
end;

function TYamlWriter.ToString: string;
begin
  Result := FBuilder.ToString;
end;

function TYamlWriter.Pad: string;
begin
  Result := StringOfChar(' ', FIndent);
end;

function TYamlWriter.EscapeStr(const S: string): string;
begin
  Result := S.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n');
end;

function TYamlWriter.FormatTimestamp(ADt: TDateTime): string;
begin
  if ADt = 0 then
    Result := ''
  else
    Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"+08:00"', ADt);
end;

procedure TYamlWriter.WriteScalarKV(const AKey, AValue: string);
begin
  FBuilder.AppendLine(Pad + AKey + ': ' + AValue);
end;

procedure TYamlWriter.WriteQuotedKV(const AKey, AValue: string);
begin
  if AValue = '' then
    FBuilder.AppendLine(Pad + AKey + ': null')
  else
    FBuilder.AppendLine(Pad + AKey + ': "' + EscapeStr(AValue) + '"');
end;

procedure TYamlWriter.WriteIntKV(const AKey: string; AValue: Integer);
begin
  FBuilder.AppendLine(Pad + AKey + ': ' + AValue.ToString);
end;

procedure TYamlWriter.WriteBoolKV(const AKey: string; AValue: Boolean);
begin
  FBuilder.AppendLine(Pad + AKey + ': ' + IfThen(AValue, 'true', 'false'));
end;

procedure TYamlWriter.WriteStringList(const AKey: string; const AValues: TArray<string>);
begin
  if Length(AValues) = 0 then
  begin
    FBuilder.AppendLine(Pad + AKey + ': []');
    Exit;
  end;
  FBuilder.AppendLine(Pad + AKey + ':');
  for var LVal in AValues do
    FBuilder.AppendLine(Pad + '  - "' + EscapeStr(LVal) + '"');
end;

procedure TYamlWriter.WriteSourceRefs(const AKey: string; const ARefs: TSourceRefArray);
begin
  if Length(ARefs) = 0 then
  begin
    FBuilder.AppendLine(Pad + AKey + ': []');
    Exit;
  end;
  FBuilder.AppendLine(Pad + AKey + ':');
  for var LRef in ARefs do
  begin
    FBuilder.AppendLine(Pad + '  - ref_id: "' + EscapeStr(LRef.RefId) + '"');
    if LRef.Relevance <> '' then
      FBuilder.AppendLine(Pad + '    relevance: ' + LRef.Relevance);
    if LRef.Note <> '' then
      FBuilder.AppendLine(Pad + '    note: "' + EscapeStr(LRef.Note) + '"');
  end;
end;

procedure TYamlWriter.WriteTreeFile(ATree: TTreeType; const AGenerator: string;
  ANodes: TList<TSpecNode>);
begin
  FBuilder.Clear;
  FIndent := 0;
  WriteQuotedKV('version', '1.0');
  WriteScalarKV('tree', TSpecEnums.TreeTypeToStr(ATree));
  WriteQuotedKV('generated_at', FormatTimestamp(Now));
  WriteQuotedKV('generator', AGenerator);
  FBuilder.AppendLine('');

  if ANodes.Count = 0 then
    FBuilder.AppendLine('nodes: []')
  else
  begin
    FBuilder.AppendLine('nodes:');
    for var LNode in ANodes do
      WriteNode(LNode);
  end;
end;

procedure TYamlWriter.WriteNode(const ANode: TSpecNode);
begin
  // First field with "- " prefix; subsequent fields aligned at indent 4
  FBuilder.AppendLine('  - id: "' + EscapeStr(ANode.Id) + '"');
  FIndent := 4;
  try
    WriteScalarKV('tree', TSpecEnums.TreeTypeToStr(ANode.Tree));
    WriteQuotedKV('title', ANode.Title);
    WriteScalarKV('kind', ANode.Kind);
    if ANode.ParentId <> '' then
      WriteQuotedKV('parent_id', ANode.ParentId)
    else
      WriteScalarKV('parent_id', 'null');
    if ANode.SlugOverride <> '' then
      WriteQuotedKV('slug_override', ANode.SlugOverride);
    if ANode.CreatedAt <> 0 then
      WriteQuotedKV('created_at', FormatTimestamp(ANode.CreatedAt));
    if ANode.UpdatedAt <> 0 then
      WriteQuotedKV('updated_at', FormatTimestamp(ANode.UpdatedAt));
    if ANode.ContentHash <> '' then
      WriteQuotedKV('content_hash', ANode.ContentHash);
    if ANode.RelationHash <> '' then
      WriteQuotedKV('relation_hash', ANode.RelationHash);
    WriteIntKV('revision', ANode.Revision);
    if ANode.Summary <> '' then
      WriteQuotedKV('summary', ANode.Summary);
    WriteScalarKV('status', TSpecEnums.NodeStatusToStr(ANode.Status));
    WriteScalarKV('gen_status', TSpecEnums.GenStatusToStr(ANode.GenStatus));
    WriteScalarKV('review_status', TSpecEnums.ReviewStatusToStr(ANode.ReviewStatus));
    WriteScalarKV('confidence', TSpecEnums.ConfidenceToStr(ANode.Confidence));
    // fog_state: write only when explicitly set so round-trip survives reload
    // and we don't pollute every node with a default 'clear'.
    if ANode.HasFogState then
      WriteScalarKV('fog_state', TSpecEnums.FogStateToStr(ANode.FogState));
    WriteScalarKV('source_layer', TSpecEnums.SourceLayerToStr(ANode.SourceLayer));
    WriteSourceRefs('source_refs', ANode.SourceRefs);
    WriteStringList('decision_refs', ANode.DecisionRefs);
    WriteStringList('issue_refs', ANode.IssueRefs);
    WriteStringList('related_functions', ANode.RelatedFunctions);
    WriteStringList('related_modules', ANode.RelatedModules);
    WriteStringList('related_views', ANode.RelatedViews);
    WriteStringList('related_data', ANode.RelatedData);
    WriteStringList('children', ANode.Children);
    WriteStringList('tags', ANode.Tags);
    WriteStringList('acceptance_criteria', ANode.AcceptanceCriteria);
    WriteStringList('not_doing', ANode.NotDoing);
    if ANode.Tree = ttData then
      WriteDataNodeFields(ANode);
  finally
    FIndent := 0;
  end;
end;

procedure TYamlWriter.WriteDataNodeFields(const ANode: TSpecNode);
begin
  if ANode.HasRiskScore then
    WriteScalarKV('risk_score', TSpecEnums.RiskLevelToStr(ANode.RiskScore));
  if ANode.DataType <> '' then
    WriteQuotedKV('data_type', ANode.DataType);
  if ANode.HasNullable then
    WriteBoolKV('nullable', ANode.Nullable);
  if ANode.DefaultValue <> '' then
    WriteQuotedKV('default_value', ANode.DefaultValue);
  WriteStringList('field_constraints', ANode.FieldConstraints);
  if ANode.Persistence <> '' then
    WriteScalarKV('persistence', ANode.Persistence);
  if ANode.SourceEntity <> '' then
    WriteQuotedKV('source_entity', ANode.SourceEntity);
  if ANode.TargetEntity <> '' then
    WriteQuotedKV('target_entity', ANode.TargetEntity);
  if ANode.Cardinality <> '' then
    WriteScalarKV('cardinality', ANode.Cardinality);
  if ANode.Cascade <> '' then
    WriteQuotedKV('cascade', ANode.Cascade);
  WriteStringList('valid_states', ANode.ValidStates);
  if Length(ANode.Transitions) > 0 then
  begin
    FBuilder.AppendLine(Pad + 'transitions:');
    for var LTrans in ANode.Transitions do
    begin
      FBuilder.AppendLine(Pad + '  - from: "' + EscapeStr(LTrans.Key) + '"');
      FBuilder.AppendLine(Pad + '    to: "' + EscapeStr(LTrans.Value) + '"');
    end;
  end;
  if ANode.HasBackwardCompatible then
    WriteBoolKV('backward_compatible', ANode.BackwardCompatible);
  if ANode.HasHasRollback then
    WriteBoolKV('has_rollback', ANode.HasRollback);
  if ANode.Scope <> '' then
    WriteQuotedKV('scope', ANode.Scope);
  if ANode.Enforcement <> '' then
    WriteScalarKV('enforcement', ANode.Enforcement);
end;

procedure TYamlWriter.WriteRelationsFile(ARelations: TList<TSpecRelation>);
begin
  FBuilder.Clear;
  FIndent := 0;
  WriteQuotedKV('version', '1.0');
  WriteQuotedKV('generated_at', FormatTimestamp(Now));
  FBuilder.AppendLine('');

  if ARelations.Count = 0 then
    FBuilder.AppendLine('relations: []')
  else
  begin
    FBuilder.AppendLine('relations:');
    for var LRel in ARelations do
      WriteRelation(LRel);
  end;
end;

procedure TYamlWriter.WriteRelation(const ARel: TSpecRelation);
begin
  FBuilder.AppendLine('  - id: "' + EscapeStr(ARel.Id) + '"');
  FIndent := 4;
  try
    WriteQuotedKV('from', ARel.FromId);
    WriteQuotedKV('to', ARel.ToId);
    WriteScalarKV('type', TSpecEnums.RelationTypeToStr(ARel.RelType));
    WriteScalarKV('confidence', TSpecEnums.ConfidenceToStr(ARel.Confidence));
    if ARel.CreatedAt <> 0 then
      WriteQuotedKV('created_at', FormatTimestamp(ARel.CreatedAt));
    if ARel.UpdatedAt <> 0 then
      WriteQuotedKV('updated_at', FormatTimestamp(ARel.UpdatedAt));
    WriteSourceRefs('source_refs', ARel.SourceRefs);
    WriteStringList('decision_refs', ARel.DecisionRefs);
    if ARel.Note <> '' then
      WriteQuotedKV('note', ARel.Note)
    else
      WriteScalarKV('note', 'null');
  finally
    FIndent := 0;
  end;
end;

procedure TYamlWriter.WriteEvidenceFile(AEvidence: TList<TSpecEvidence>);
begin
  FBuilder.Clear;
  FIndent := 0;
  WriteQuotedKV('version', '1.0');
  FBuilder.AppendLine('');

  if AEvidence.Count = 0 then
    FBuilder.AppendLine('evidence: []')
  else
  begin
    FBuilder.AppendLine('evidence:');
    for var LEv in AEvidence do
      WriteEvidence(LEv);
  end;
end;

procedure TYamlWriter.WriteEvidence(const AEv: TSpecEvidence);
begin
  FBuilder.AppendLine('  - id: "' + EscapeStr(AEv.Id) + '"');
  FIndent := 4;
  try
    WriteScalarKV('source_layer', TSpecEnums.SourceLayerToStr(AEv.SourceLayer));
    WriteQuotedKV('path', AEv.Path);
    if AEv.Lines <> '' then
      WriteQuotedKV('lines', AEv.Lines)
    else
      WriteScalarKV('lines', 'null');
    WriteQuotedKV('excerpt', AEv.Excerpt);
    WriteBoolKV('excerpt_truncated', AEv.ExcerptTruncated);
    if AEv.Note <> '' then
      WriteQuotedKV('note', AEv.Note)
    else
      WriteScalarKV('note', 'null');
    WriteScalarKV('confidence', TSpecEnums.ConfidenceToStr(AEv.Confidence));
    if AEv.CreatedAt <> 0 then
      WriteQuotedKV('created_at', FormatTimestamp(AEv.CreatedAt));
    if AEv.UpdatedAt <> 0 then
      WriteQuotedKV('updated_at', FormatTimestamp(AEv.UpdatedAt));
    if AEv.ContentHash <> '' then
      WriteQuotedKV('content_hash', AEv.ContentHash);
    if AEv.SourceFileHash <> '' then
      WriteQuotedKV('source_file_hash', AEv.SourceFileHash)
    else
      WriteScalarKV('source_file_hash', 'null');
    WriteBoolKV('is_stale', AEv.IsStale);
    WriteStringList('referenced_by', AEv.ReferencedBy);
  finally
    FIndent := 0;
  end;
end;

procedure TYamlWriter.WriteIssuesFile(AIssues: TList<TSpecIssue>);
begin
  FBuilder.Clear;
  FIndent := 0;
  WriteQuotedKV('version', '1.0');
  FBuilder.AppendLine('');

  if AIssues.Count = 0 then
    FBuilder.AppendLine('issues: []')
  else
  begin
    FBuilder.AppendLine('issues:');
    for var LIssue in AIssues do
      WriteIssue(LIssue);
  end;
end;

procedure TYamlWriter.WriteIssue(const AIssue: TSpecIssue);
begin
  FBuilder.AppendLine('  - id: "' + EscapeStr(AIssue.Id) + '"');
  FIndent := 4;
  try
    WriteScalarKV('severity', TSpecEnums.IssueSeverityToStr(AIssue.Severity));
    WriteScalarKV('type', TSpecEnums.IssueTypeToStr(AIssue.IssueType));
    WriteQuotedKV('title', AIssue.Title);
    WriteQuotedKV('description', AIssue.Description);
    WriteStringList('affected_nodes', AIssue.AffectedNodes);
    WriteSourceRefs('source_refs', AIssue.SourceRefs);
    if AIssue.SuggestedAction <> '' then
      WriteQuotedKV('suggested_action', AIssue.SuggestedAction)
    else
      WriteScalarKV('suggested_action', 'null');
    if AIssue.SuggestedPrompt <> '' then
      WriteQuotedKV('suggested_prompt', AIssue.SuggestedPrompt)
    else
      WriteScalarKV('suggested_prompt', 'null');
    WriteScalarKV('status', TSpecEnums.IssueStatusToStr(AIssue.Status));
    if AIssue.ResolvedBy <> '' then
      WriteQuotedKV('resolved_by', AIssue.ResolvedBy)
    else
      WriteScalarKV('resolved_by', 'null');
    if AIssue.CreatedAt <> 0 then
      WriteQuotedKV('created_at', FormatTimestamp(AIssue.CreatedAt));
    if AIssue.UpdatedAt <> 0 then
      WriteQuotedKV('updated_at', FormatTimestamp(AIssue.UpdatedAt));
    if AIssue.ResolvedAt <> 0 then
      WriteQuotedKV('resolved_at', FormatTimestamp(AIssue.ResolvedAt))
    else
      WriteScalarKV('resolved_at', 'null');
    // requires_human: HITL/AFK attribute for exploration tickets (BUG-11).
    // Optional — persisted only when explicitly set, so non-ticket issues
    // (which never set it) stay out of the YAML.
    if AIssue.HasRequiresHuman then
      WriteBoolKV('requires_human', AIssue.RequiresHuman);
  finally
    FIndent := 0;
  end;
end;

procedure TYamlWriter.WriteDecisionsFile(ADecisions: TList<TSpecDecision>);
begin
  FBuilder.Clear;
  FIndent := 0;
  WriteQuotedKV('version', '1.0');
  FBuilder.AppendLine('');

  if ADecisions.Count = 0 then
    FBuilder.AppendLine('decisions: []')
  else
  begin
    FBuilder.AppendLine('decisions:');
    for var LDec in ADecisions do
      WriteDecision(LDec);
  end;
end;

procedure TYamlWriter.WriteDecision(const ADec: TSpecDecision);
begin
  FBuilder.AppendLine('  - id: "' + EscapeStr(ADec.Id) + '"');
  FIndent := 4;
  try
    WriteScalarKV('type', TSpecEnums.DecisionTypeToStr(ADec.DecisionType));
    WriteQuotedKV('title', ADec.Title);
    WriteQuotedKV('decision', ADec.DecisionText);
    WriteQuotedKV('rationale', ADec.Rationale);
    WriteStringList('target_nodes', ADec.TargetNodes);
    WriteStringList('affected_relations', ADec.AffectedRelations);
    WriteStringList('affected_requirements', ADec.AffectedRequirements);
    WriteStringList('affected_views', ADec.AffectedViews);
    WriteStringList('affected_modules', ADec.AffectedModules);
    WriteStringList('resolved_issues', ADec.ResolvedIssues);
    WriteSourceRefs('source_refs', ADec.SourceRefs);
    if ADec.AiInstruction <> '' then
      WriteQuotedKV('ai_instruction', ADec.AiInstruction)
    else
      WriteScalarKV('ai_instruction', 'null');
    if ADec.HasPriority then
      WriteScalarKV('priority', TSpecEnums.PriorityToStr(ADec.Priority))
    else
      WriteScalarKV('priority', 'null');
    if ADec.Release <> '' then
      WriteQuotedKV('release', ADec.Release)
    else
      WriteScalarKV('release', 'null');
    if ADec.CreatedAt <> 0 then
      WriteQuotedKV('created_at', FormatTimestamp(ADec.CreatedAt));
    if ADec.UpdatedAt <> 0 then
      WriteQuotedKV('updated_at', FormatTimestamp(ADec.UpdatedAt));
    WriteScalarKV('decided_by', TSpecEnums.DecidedByToStr(ADec.DecidedBy));
    WriteScalarKV('confidence', TSpecEnums.ConfidenceToStr(ADec.Confidence));
    WriteScalarKV('status', TSpecEnums.DecisionStatusToStr(ADec.Status));
    if ADec.SupersededBy <> '' then
      WriteQuotedKV('superseded_by', ADec.SupersededBy)
    else
      WriteScalarKV('superseded_by', 'null');
    WriteStringList('supersedes', ADec.Supersedes);
  finally
    FIndent := 0;
  end;
end;

end.
