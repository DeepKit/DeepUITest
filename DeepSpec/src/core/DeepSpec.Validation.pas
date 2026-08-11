
{ ============================================================================
  DeepSpec.Validation

  Validates LLM-generated YAML against the DeepSpec Protocol v1.1 schema.
  Implements lenient and strict mode validation per protocol §11.
  ============================================================================ }

unit DeepSpec.Validation;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.RegularExpressions,
  DeepSpec.Yaml.Parser,
  DeepSpec.Models;

type
  TValidationSeverity = (vsError, vsWarning);

  TValidationMode = (vmLenient, vmStrict);

  TValidationError = record
    Rule: string;
    Severity: TValidationSeverity;
    Path: string;
    MessageText: string;
    FixHint: string;
  end;

  TValidationReport = class
  private
    FErrors: TList<TValidationError>;
    FMode: TValidationMode;
    FAutoFilled: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddError(const ARule: string; ASeverity: TValidationSeverity;
      const APath, AMessage, AFixHint: string);
    function HasErrors: Boolean;
    function ErrorCount: Integer;
    function WarningCount: Integer;
    procedure Clear;
    property Errors: TList<TValidationError> read FErrors;
    property Mode: TValidationMode read FMode write FMode;
    property AutoFilled: Integer read FAutoFilled write FAutoFilled;
  end;

  TYamlValidator = class
  private
    FNodeIdRegex: TRegex;
    procedure ValidateNodeId(const AId, APath: string;
      AReport: TValidationReport);
    procedure ValidateKind(const AKind, ATree, APath: string;
      AReport: TValidationReport);
    procedure ValidateNodeStatus(const AStatus, APath: string;
      AReport: TValidationReport);
    procedure ValidateConfidence(const AConf, APath: string;
      AReport: TValidationReport);
    procedure ValidateFogState(const AFog, APath: string;
      AReport: TValidationReport);
    procedure ValidateSourceLayer(const ALayer, APath: string;
      AReport: TValidationReport);
    /// <summary>Validate a single issue entry from doc-issues.yaml against the
    /// issues schema (BUG-11 step 1 remainder). Path root is /issues/<AIndex>.</summary>
    procedure ValidateIssue(AItem: TYamlNode; AIndex: Integer;
      AReport: TValidationReport);
    function IsValidFunctionKind(const AKind: string): Boolean;
    function IsValidModuleKind(const AKind: string): Boolean;
    function IsValidViewKind(const AKind: string): Boolean;
    function IsExtensionKind(const AKind: string): Boolean;
  public
    constructor Create;
    function ValidateTreeFile(const AYaml: string;
      AMode: TValidationMode = vmLenient): TValidationReport;
    function ValidateProjectSpec(const AYaml: string): TValidationReport;
    function ValidateLLMSecurityRules(const AYaml: string): TValidationReport;
    /// <summary>Validate an issues/doc-issues.yaml document (BUG-11 step 1
    /// remainder). Checks each issue: id prefix, enum legality of severity/
    /// type/status, non-empty title/affected_nodes, and requires_human
    /// consistency with ticket types. Empty issues list is valid.</summary>
    function ValidateIssuesFile(const AYaml: string): TValidationReport;
    function ValidateNodeHashes(const ANodes: TList<TSpecNode>;
      const ATreeName: string): TValidationReport;
  end;

implementation

uses
  System.StrUtils,
  DeepSpec.Hash;

{ TValidationReport }

constructor TValidationReport.Create;
begin
  inherited Create;
  FErrors := TList<TValidationError>.Create;
  FMode := vmLenient;
end;

destructor TValidationReport.Destroy;
begin
  FErrors.Free;
  inherited;
end;

procedure TValidationReport.AddError(const ARule: string;
  ASeverity: TValidationSeverity; const APath, AMessage, AFixHint: string);
var
  LErr: TValidationError;
begin
  LErr.Rule := ARule;
  LErr.Severity := ASeverity;
  LErr.Path := APath;
  LErr.MessageText := AMessage;
  LErr.FixHint := AFixHint;
  FErrors.Add(LErr);
end;

function TValidationReport.HasErrors: Boolean;
begin
  for var LErr in FErrors do
    if LErr.Severity = vsError then
      Exit(True);
  Result := False;
end;

function TValidationReport.ErrorCount: Integer;
begin
  Result := 0;
  for var LErr in FErrors do
    if LErr.Severity = vsError then
      Inc(Result);
end;

function TValidationReport.WarningCount: Integer;
begin
  Result := 0;
  for var LErr in FErrors do
    if LErr.Severity = vsWarning then
      Inc(Result);
end;

procedure TValidationReport.Clear;
begin
  FErrors.Clear;
  FAutoFilled := 0;
end;

{ TYamlValidator }

constructor TYamlValidator.Create;
begin
  inherited Create;
  FNodeIdRegex := TRegEx.Create(
    '^(func|mod|view|data)-[a-z0-9][a-z0-9\-]{0,49}$', [roCompiled]);
end;

function TYamlValidator.IsValidFunctionKind(const AKind: string): Boolean;
const
  KINDS: array[0..7] of string = (
    'feature', 'capability', 'user_story', 'use_case',
    'rule', 'constraint', 'non_functional', 'integration'
  );
begin
  for var K in KINDS do
    if K = AKind then Exit(True);
  Result := False;
end;

function TYamlValidator.IsValidModuleKind(const AKind: string): Boolean;
const
  KINDS: array[0..9] of string = (
    'package', 'unit', 'class', 'interface', 'service',
    'repository', 'controller', 'adapter', 'utility', 'config'
  );
begin
  for var K in KINDS do
    if K = AKind then Exit(True);
  Result := False;
end;

function TYamlValidator.IsValidViewKind(const AKind: string): Boolean;
const
  KINDS: array[0..10] of string = (
    'application', 'window', 'dialog', 'page', 'frame',
    'panel', 'control', 'menu', 'toolbar', 'statusbar', 'tray'
  );
begin
  for var K in KINDS do
    if K = AKind then Exit(True);
  Result := False;
end;

function TYamlValidator.IsExtensionKind(const AKind: string): Boolean;
begin
  Result := AKind.StartsWith('x_') and (AKind.Length >= 3);
end;

procedure TYamlValidator.ValidateNodeId(const AId, APath: string;
  AReport: TValidationReport);
begin
  if AId = '' then
  begin
    AReport.AddError('missing_id', vsError, APath,
      'Node id is required', 'Add a unique id like "func-some-name"');
    Exit;
  end;

  if not FNodeIdRegex.IsMatch(AId) then
    AReport.AddError('invalid_id_format', vsError, APath,
      'Node id "' + AId + '" does not match required pattern',
      'Use format {func|mod|view|data}-{slug}, lowercase letters/digits/hyphens only');
end;

procedure TYamlValidator.ValidateKind(const AKind, ATree, APath: string;
  AReport: TValidationReport);
begin
  if AKind = '' then
  begin
    AReport.AddError('missing_kind', vsError, APath,
      'Node kind is required', 'Add a kind value like "feature" for functions');
    Exit;
  end;

  if IsExtensionKind(AKind) then Exit;

  var LValid := False;
  if ATree = 'function' then
    LValid := IsValidFunctionKind(AKind)
  else if ATree = 'module' then
    LValid := IsValidModuleKind(AKind)
  else if ATree = 'view' then
    LValid := IsValidViewKind(AKind);

  if not LValid then
    AReport.AddError('unknown_kind', vsWarning, APath,
      'Kind "' + AKind + '" is not a built-in value for tree "' + ATree + '"',
      'Use a built-in kind or prefix with "x_" for extensions');
end;

procedure TYamlValidator.ValidateNodeStatus(const AStatus, APath: string;
  AReport: TValidationReport);
const
  VALID: array[0..4] of string = ('candidate', 'confirmed', 'uncertain', 'rejected', 'superseded');
begin
  if AStatus = '' then Exit; // optional, default applies
  for var V in VALID do
    if V = AStatus then Exit;
  AReport.AddError('invalid_status', vsError, APath,
    'Status "' + AStatus + '" is not valid',
    'Use one of: candidate, confirmed, uncertain, rejected, superseded');
end;

procedure TYamlValidator.ValidateConfidence(const AConf, APath: string;
  AReport: TValidationReport);
const
  VALID: array[0..2] of string = ('low', 'medium', 'high');
begin
  if AConf = '' then Exit;
  for var V in VALID do
    if V = AConf then Exit;
  AReport.AddError('invalid_confidence', vsError, APath,
    'Confidence "' + AConf + '" is not valid',
    'Use one of: low, medium, high');
end;

procedure TYamlValidator.ValidateFogState(const AFog, APath: string;
  AReport: TValidationReport);
const
  VALID: array[0..3] of string = ('clear', 'misty', 'foggy', 'unknown_unknowns');
begin
  if AFog = '' then Exit; // optional, default clear applies
  for var V in VALID do
    if V = AFog then Exit;
  AReport.AddError('invalid_fog_state', vsError, APath,
    'fog_state "' + AFog + '" is not valid',
    'Use one of: clear, misty, foggy, unknown_unknowns');
end;

procedure TYamlValidator.ValidateSourceLayer(const ALayer, APath: string;
  AReport: TValidationReport);
const
  VALID: array[0..3] of string = (
    'parsed_from_a', 'human_decision', 'ai_inferred', 'generated_summary'
  );
begin
  if ALayer = '' then Exit;
  for var V in VALID do
    if V = ALayer then Exit;
  AReport.AddError('invalid_source_layer', vsError, APath,
    'source_layer "' + ALayer + '" is not valid',
    'Use one of: parsed_from_a, human_decision, ai_inferred, generated_summary');
end;

procedure TYamlValidator.ValidateIssue(AItem: TYamlNode; AIndex: Integer;
  AReport: TValidationReport);
const
  SEVERITIES: array[0..4] of string = ('critical', 'high', 'medium', 'low', 'info');
  // 14 issue types per issues.schema.json (10 ordinary + 4 exploration tickets).
  ISSUE_TYPES: array[0..13] of string = (
    'missing_requirement', 'conflict', 'ambiguity', 'stale_doc',
    'no_source', 'low_confidence', 'parse_warning', 'parse_error',
    'orphan_node', 'coverage_gap',
    'research_ticket', 'prototype_ticket', 'grilling_ticket', 'fog_unknown'
  );
  STATUSES: array[0..3] of string = ('open', 'resolved', 'wontfix', 'deferred');
  // Types that are exploration tickets — requires_human is meaningful only for these.
  TICKET_TYPES: array[0..3] of string = (
    'research_ticket', 'prototype_ticket', 'grilling_ticket', 'fog_unknown'
  );

  function FoundIn(const AValue: string; const AList: array of string): Boolean;
  begin
    for var V in AList do
      if V = AValue then Exit(True);
    Result := False;
  end;

  function IsTicketType(const AType: string): Boolean;
  begin
    Result := FoundIn(AType, TICKET_TYPES);
  end;

var
  LBase, LId, LType: string;
  LNodes: TYamlNode;
begin
  if AItem = nil then Exit;
  LBase := '/issues/' + AIndex.ToString;

  // id: required, must start with "issue-" (issues.schema.json pattern ^issue-).
  LId := AItem.GetString('id', '');
  if LId = '' then
    AReport.AddError('missing_id', vsError, LBase + '/id',
      'Issue id is required', 'Add a unique id like "issue-fog-func-root"')
  else if not LId.StartsWith('issue-') then
    AReport.AddError('invalid_issue_id', vsError, LBase + '/id',
      'Issue id "' + LId + '" must start with "issue-"',
      'Use the "issue-" prefix');

  // severity: required, must be a built-in value.
  var LSev := AItem.GetString('severity', '');
  if LSev = '' then
    AReport.AddError('missing_issue_severity', vsError, LBase + '/severity',
      'Issue severity is required', 'Use: critical, high, medium, low, or info')
  else if not FoundIn(LSev, SEVERITIES) then
    AReport.AddError('invalid_issue_severity', vsError, LBase + '/severity',
      'severity "' + LSev + '" is not valid',
      'Use one of: critical, high, medium, low, info');

  // type: required, must be a built-in value (incl. 4 ticket types).
  LType := AItem.GetString('type', '');
  if LType = '' then
    AReport.AddError('missing_issue_type', vsError, LBase + '/type',
      'Issue type is required', 'Use a value from issues.schema.json')
  else if not FoundIn(LType, ISSUE_TYPES) then
    AReport.AddError('invalid_issue_type', vsError, LBase + '/type',
      'type "' + LType + '" is not a valid issue type',
      'Use a built-in type or one of research_ticket/prototype_ticket/grilling_ticket/fog_unknown');

  // title: required, non-empty.
  if AItem.GetString('title', '') = '' then
    AReport.AddError('missing_issue_title', vsError, LBase + '/title',
      'Issue title is required', 'Add a human-readable title');

  // description: schema allows empty; warn so authors notice missing rationale.
  if AItem.GetString('description', '') = '' then
    AReport.AddError('missing_issue_description', vsWarning, LBase + '/description',
      'Issue description is empty', 'Describe the issue so its rationale is traceable');

  // affected_nodes: required non-empty (an issue must point at something).
  LNodes := AItem.GetSeq('affected_nodes');
  if (LNodes = nil) or (LNodes.SeqCount = 0) then
    AReport.AddError('empty_affected_nodes', vsError, LBase + '/affected_nodes',
      'affected_nodes must list at least one node id',
      'Add the node id(s) this issue concerns');

  // status: required, must be a built-in value.
  var LStatus := AItem.GetString('status', '');
  if LStatus = '' then
    AReport.AddError('missing_issue_status', vsError, LBase + '/status',
      'Issue status is required', 'Use: open, resolved, wontfix, or deferred')
  else if not FoundIn(LStatus, STATUSES) then
    AReport.AddError('invalid_issue_status', vsError, LBase + '/status',
      'status "' + LStatus + '" is not valid',
      'Use one of: open, resolved, wontfix, deferred');

  // requires_human: only meaningful for exploration tickets (BUG-11). Setting it
  // on a non-ticket issue is semantically meaningless — warn, don't error,
  // so the field stays optional and we don't over-constrain LLM/user output.
  if AItem.Has('requires_human') and not IsTicketType(LType) then
    AReport.AddError('requires_human_mismatch', vsWarning, LBase + '/requires_human',
      'requires_human is only meaningful for ticket types (research/prototype/grilling/fog_unknown)',
      'Remove requires_human or change the issue type to a ticket type');
end;

function TYamlValidator.ValidateTreeFile(const AYaml: string;
  AMode: TValidationMode): TValidationReport;
var
  LParser: TYamlParser;
  LRoot: TYamlNode;
  LSeenIds: TDictionary<string, Boolean>;
begin
  Result := TValidationReport.Create;
  Result.Mode := AMode;
  LParser := TYamlParser.Create;
  LSeenIds := TDictionary<string, Boolean>.Create;
  try
    try
      LRoot := LParser.Parse(AYaml);
    except
      on E: Exception do
      begin
        Result.AddError('parse_error', vsError, '',
          'YAML parse failed: ' + E.Message, 'Check syntax and indentation');
        Exit;
      end;
    end;

    try
      // Check version
      var LVer := LRoot.GetString('version', '');
      if LVer = '' then
        Result.AddError('missing_version', vsWarning, '/version',
          'version field missing', 'Add: version: "1.0"');

      // Check tree type
      var LTree := LRoot.GetString('tree', '');
      if (LTree <> 'function') and (LTree <> 'module') and (LTree <> 'view') and (LTree <> 'data') then
        Result.AddError('invalid_tree', vsError, '/tree',
          'tree must be "function", "module", "view", or "data"', '');

      // Validate nodes
      var LNodes := LRoot.GetSeq('nodes');
      if LNodes <> nil then
      begin
        for var I := 0 to LNodes.SeqCount - 1 do
        begin
          var LNode := LNodes.SeqItem(I);
          if LNode = nil then Continue;

          var LPath := '/nodes/' + I.ToString;
          var LId := LNode.GetString('id', '');
          var LNodeTree := LNode.GetString('tree', LTree);

          ValidateNodeId(LId, LPath + '/id', Result);

          if (LId <> '') and LSeenIds.ContainsKey(LId) then
            Result.AddError('duplicate_id', vsError, LPath + '/id',
              'Duplicate id: ' + LId, 'Each node id must be globally unique');
          if LId <> '' then
            LSeenIds.AddOrSetValue(LId, True);

          if LNode.GetString('title', '') = '' then
            Result.AddError('missing_title', vsError, LPath + '/title',
              'Node title is required', 'Add a human-readable title');

          ValidateKind(LNode.GetString('kind', ''), LNodeTree, LPath + '/kind', Result);
          ValidateNodeStatus(LNode.GetString('status', ''), LPath + '/status', Result);
          ValidateConfidence(LNode.GetString('confidence', ''), LPath + '/confidence', Result);
          ValidateFogState(LNode.GetString('fog_state', ''), LPath + '/fog_state', Result);
          ValidateSourceLayer(LNode.GetString('source_layer', ''), LPath + '/source_layer', Result);
        end;
      end;

      // INV-2: parent_id reference existence
      // INV-5: circular parent_id chains
      if LNodes <> nil then
      begin
        // Build id->index map for parent ref checking
        var LIdMap := TDictionary<string, Integer>.Create;
        try
          for var I := 0 to LNodes.SeqCount - 1 do
          begin
            var LN := LNodes.SeqItem(I);
            if LN = nil then Continue;
            var LNId := LN.GetString('id', '');
            if LNId <> '' then
              LIdMap.AddOrSetValue(LNId, I);
          end;

          for var I := 0 to LNodes.SeqCount - 1 do
          begin
            var LNode := LNodes.SeqItem(I);
            if LNode = nil then Continue;
            var LPId := LNode.GetString('parent_id', '');
            if LPId = '' then Continue;

            var LPath := '/nodes/' + I.ToString + '/parent_id';

            // INV-2: parent must exist
            if not LIdMap.ContainsKey(LPId) then
              Result.AddError('invalid_parent_ref', vsError, LPath,
                'parent_id "' + LPId + '" does not reference an existing node',
                'Fix the parent_id or remove it for root nodes')
            else
            begin
              // INV-5: cycle detection - walk parent chain
              var LVisited := TDictionary<string, Boolean>.Create;
              try
                var LCurrent := LNode.GetString('id', '');
                var LCycleFound := False;
                while LCurrent <> '' do
                begin
                  if LVisited.ContainsKey(LCurrent) then
                  begin
                    LCycleFound := True;
                    Break;
                  end;
                  LVisited.AddOrSetValue(LCurrent, True);
                  var LIdx: Integer;
                  if not LIdMap.TryGetValue(LCurrent, LIdx) then Break;
                  var LPNode := LNodes.SeqItem(LIdx);
                  if LPNode = nil then Break;
                  LCurrent := LPNode.GetString('parent_id', '');
                end;
                if LCycleFound then
                  Result.AddError('circular_parent', vsError, LPath,
                    'parent_id chain contains a cycle',
                    'Break the cycle by setting a root node parent_id to empty');
              finally
                LVisited.Free;
              end;
            end;
          end;
        finally
          LIdMap.Free;
        end;

        // INV-4: gen_status / review_status value legality
        for var I := 0 to LNodes.SeqCount - 1 do
        begin
          var LNode := LNodes.SeqItem(I);
          if LNode = nil then Continue;
          var LPath := '/nodes/' + I.ToString;

          var LGS := LNode.GetString('gen_status', '');
          if (LGS <> '') and (LGS <> 'draft') and (LGS <> 'generated') and
             (LGS <> 'confirmed') and (LGS <> 'skipped') then
            Result.AddError('invalid_gen_status', vsError, LPath + '/gen_status',
              'gen_status "' + LGS + '" is not valid',
              'Use: draft, generated, confirmed, or skipped');

          var LRS := LNode.GetString('review_status', '');
          if (LRS <> '') and (LRS <> 'unreviewed') and (LRS <> 'accepted') and
             (LRS <> 'rejected') and (LRS <> 'deferred') then
            Result.AddError('invalid_review_status', vsError, LPath + '/review_status',
              'review_status "' + LRS + '" is not valid',
              'Use: unreviewed, accepted, rejected, or deferred');
        end;
      end;

    finally
      LRoot.Free;
    end;
  finally
    LParser.Free;
    LSeenIds.Free;
  end;
end;

function TYamlValidator.ValidateProjectSpec(const AYaml: string): TValidationReport;
var
  LParser: TYamlParser;
  LRoot: TYamlNode;
begin
  Result := TValidationReport.Create;
  LParser := TYamlParser.Create;
  try
    try
      LRoot := LParser.Parse(AYaml);
    except
      on E: Exception do
      begin
        Result.AddError('parse_error', vsError, '',
          'YAML parse failed: ' + E.Message, '');
        Exit;
      end;
    end;

    try
      if LRoot.GetString('version', '') = '' then
        Result.AddError('missing_version', vsWarning, '/version',
          'version field missing', '');

      var LProject := LRoot.Get('project');
      if LProject = nil then
        Result.AddError('missing_project', vsError, '/project',
          'project section is required', '')
      else
      begin
        if LProject.GetString('name', '') = '' then
          Result.AddError('missing_project_name', vsError, '/project/name',
            'project.name is required', '');
        if LProject.GetString('type', '') = '' then
          Result.AddError('missing_project_type', vsError, '/project/type',
            'project.type is required', 'Use a value from §3.1 recommended types or "unknown"');
      end;
    finally
      LRoot.Free;
    end;
  finally
    LParser.Free;
  end;
end;

function TYamlValidator.ValidateLLMSecurityRules(const AYaml: string): TValidationReport;
var
  LParser: TYamlParser;
  LRoot: TYamlNode;
begin
  // Per protocol §12.1 rule 11: LLM output must not contain decided_by: human
  Result := TValidationReport.Create;
  LParser := TYamlParser.Create;
  try
    try
      LRoot := LParser.Parse(AYaml);
    except
      Exit;
    end;

    try
      var LDecisions := LRoot.GetSeq('decisions');
      if LDecisions <> nil then
      begin
        for var I := 0 to LDecisions.SeqCount - 1 do
        begin
          var LDec := LDecisions.SeqItem(I);
          if LDec = nil then Continue;
          if LDec.GetString('decided_by', '') = 'human' then
            Result.AddError('forbidden_human_decided_by', vsError,
              '/decisions/' + I.ToString + '/decided_by',
              'LLM output must not set decided_by: human (protocol §12.1 rule 11)',
              'Remove the decided_by field or set it to "system". Human decisions ' +
              'must be created via DeepSpec UI write paths only.');
        end;
      end;
    finally
      LRoot.Free;
    end;
  finally
    LParser.Free;
  end;
end;

function TYamlValidator.ValidateIssuesFile(const AYaml: string): TValidationReport;
var
  LParser: TYamlParser;
  LRoot, LSeq: TYamlNode;
begin
  Result := TValidationReport.Create;
  LParser := TYamlParser.Create;
  try
    try
      LRoot := LParser.Parse(AYaml);
    except
      on E: Exception do
      begin
        Result.AddError('parse_error', vsError, '',
          'YAML parse failed: ' + E.Message, 'Check syntax and indentation');
        Exit;
      end;
    end;

    try
      // version is recommended; missing is a warning (mirrors tree-file policy).
      if LRoot.GetString('version', '') = '' then
        Result.AddError('missing_version', vsWarning, '/version',
          'version field missing', 'Add: version: "1.0"');

      LSeq := LRoot.GetSeq('issues');
      if LSeq = nil then
        // No issues key at all — treat as empty (callers may write issues: []).
        Exit;

      for var I := 0 to LSeq.SeqCount - 1 do
        ValidateIssue(LSeq.SeqItem(I), I, Result);
    finally
      LRoot.Free;
    end;
  finally
    LParser.Free;
  end;
end;

function TYamlValidator.ValidateNodeHashes(const ANodes: TList<TSpecNode>;
  const ATreeName: string): TValidationReport;
begin
  Result := TValidationReport.Create;
  if ANodes = nil then Exit;

  for var I := 0 to ANodes.Count - 1 do
  begin
    var LNode := ANodes[I];
    if LNode.ContentHash = '' then Continue;

    var LExpected := TSpecHash.NodeContentHash(LNode);
    if not LExpected.Equals(LNode.ContentHash) then
      Result.AddError('content_hash_mismatch', vsError,
        ATreeName + '/nodes/' + I.ToString + '/content_hash',
        'content_hash mismatch for node "' + LNode.Id + '"',
        'Regenerate the tree or re-run scan to update hashes');
  end;
end;

end.
