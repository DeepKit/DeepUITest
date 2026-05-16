{ ============================================================================
  DeepSpec.Services.SpecStore

  Manages the .deepspec directory: creates structure, writes YAML files,
  generates scan-report and project-spec.
  ============================================================================ }

unit DeepSpec.Services.SpecStore;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DeepSpec.Services.Scan,
  DeepSpec.Models;

type
  TDeepSpecStoreService = class(TInterfacedObject)
  private
    FBasePath: string;
    procedure EnsureDirectory(const ARelPath: string);
    procedure WriteYamlFile(const ARelPath, AContent: string);
  public
    constructor Create;
    procedure Initialize(const AProjectPath: string);
    procedure CreateDirectoryStructure;
    procedure WriteScanReport(AScanService: TDeepSpecScanService);
    procedure WriteProjectSpec(const AProjectName, AProjectType: string;
      ATotalNodes: Integer);
    procedure WriteEmptyTrees;
    procedure WriteGitIgnore;
    procedure WriteTreeFile(const ARelPath: string; ATree: DeepSpec.Models.TTreeType;
      ANodes: System.Generics.Collections.TList<DeepSpec.Models.TSpecNode>);
    procedure WriteEvidenceFile(const ARelPath: string;
      AEvidence: System.Generics.Collections.TList<DeepSpec.Models.TSpecEvidence>);

    /// <summary>
    /// Read a tree YAML file produced by WriteTreeFile and return the
    /// list of nodes. Returns an empty list if the file is missing or
    /// the YAML cannot be parsed. Caller owns the returned list.
    /// </summary>
    function ReadTreeFile(const ARelPath: string): TList<TSpecNode>;
    property BasePath: string read FBasePath;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  DeepSpec.Yaml.Writer,
  DeepSpec.Yaml.Parser;

constructor TDeepSpecStoreService.Create;
begin
  inherited Create;
end;

procedure TDeepSpecStoreService.Initialize(const AProjectPath: string);
begin
  FBasePath := TPath.Combine(AProjectPath, '.deepspec');
end;

procedure TDeepSpecStoreService.EnsureDirectory(const ARelPath: string);
begin
  var LFullPath := TPath.Combine(FBasePath, ARelPath);
  if not TDirectory.Exists(LFullPath) then
    TDirectory.CreateDirectory(LFullPath);
end;

procedure TDeepSpecStoreService.WriteYamlFile(const ARelPath, AContent: string);
begin
  var LFullPath := TPath.Combine(FBasePath, ARelPath);
  var LDir := TPath.GetDirectoryName(LFullPath);
  if not TDirectory.Exists(LDir) then
    TDirectory.CreateDirectory(LDir);
  TFile.WriteAllText(LFullPath, AContent, TEncoding.UTF8);
end;

procedure TDeepSpecStoreService.CreateDirectoryStructure;
begin
  EnsureDirectory('');
  EnsureDirectory('trees');
  EnsureDirectory('relations');
  EnsureDirectory('evidence');
  EnsureDirectory('issues');
  EnsureDirectory('decisions');
  EnsureDirectory('prompts');
  EnsureDirectory('html');
  EnsureDirectory('llm');
  EnsureDirectory('logs');
end;

procedure TDeepSpecStoreService.WriteScanReport(AScanService: TDeepSpecScanService);
begin
  var LNow := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"+08:00"', Now);
  var LSb := TStringBuilder.Create;
  try
    LSb.AppendLine('version: "1.0"');
    LSb.AppendLine('scan_time: "' + LNow + '"');
    LSb.AppendLine('project_path: "."');
    LSb.AppendLine('project_type: "unknown"');
    LSb.AppendLine('');
    LSb.AppendLine('file_classification:');

    // Documents
    LSb.AppendLine('  documents:');
    for var LFile in AScanService.GetFilesByCategory(fcDocuments) do
      LSb.AppendLine('    - "' + LFile + '"');

    // Code
    LSb.AppendLine('  code:');
    for var LFile in AScanService.GetFilesByCategory(fcCode) do
      LSb.AppendLine('    - "' + LFile + '"');

    // UI
    LSb.AppendLine('  ui:');
    for var LFile in AScanService.GetFilesByCategory(fcUI) do
      LSb.AppendLine('    - "' + LFile + '"');

    // Config
    LSb.AppendLine('  config:');
    for var LFile in AScanService.GetFilesByCategory(fcConfig) do
      LSb.AppendLine('    - "' + LFile + '"');

    // AI Rules
    LSb.AppendLine('  ai_rules:');
    for var LFile in AScanService.GetFilesByCategory(fcAiRules) do
      LSb.AppendLine('    - "' + LFile + '"');

    // Ignored
    LSb.AppendLine('  ignored:');
    for var LFile in AScanService.GetFilesByCategory(fcIgnored) do
      LSb.AppendLine('    - "' + LFile + '"');

    LSb.AppendLine('');
    LSb.AppendLine('stats:');
    LSb.AppendLine('  total_files: ' + AScanService.TotalFiles.ToString);
    LSb.AppendLine('  documents: ' + AScanService.CategoryCount(fcDocuments).ToString);
    LSb.AppendLine('  code: ' + AScanService.CategoryCount(fcCode).ToString);
    LSb.AppendLine('  ui: ' + AScanService.CategoryCount(fcUI).ToString);
    LSb.AppendLine('  config: ' + AScanService.CategoryCount(fcConfig).ToString);
    LSb.AppendLine('  ai_rules: ' + AScanService.CategoryCount(fcAiRules).ToString);
    LSb.AppendLine('  ignored: ' + AScanService.CategoryCount(fcIgnored).ToString);
    LSb.AppendLine('');
    LSb.AppendLine('warnings: []');

    WriteYamlFile('scan-report.yaml', LSb.ToString);
  finally
    LSb.Free;
  end;
end;

procedure TDeepSpecStoreService.WriteProjectSpec(const AProjectName, AProjectType: string;
  ATotalNodes: Integer);
begin
  var LNow := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"+08:00"', Now);
  var LSb := TStringBuilder.Create;
  try
    LSb.AppendLine('version: "1.0"');
    LSb.AppendLine('project:');
    LSb.AppendLine('  name: "' + AProjectName + '"');
    LSb.AppendLine('  path: "."');
    LSb.AppendLine('  type: "' + AProjectType + '"');
    LSb.AppendLine('  scan_time: "' + LNow + '"');
    LSb.AppendLine('');
    LSb.AppendLine('summary:');
    LSb.AppendLine('  total_nodes: ' + ATotalNodes.ToString);
    LSb.AppendLine('  confirmed_nodes: 0');
    LSb.AppendLine('  uncertain_nodes: 0');
    LSb.AppendLine('  open_issues: 0');
    LSb.AppendLine('  decisions_count: 0');
    LSb.AppendLine('');
    LSb.AppendLine('trees:');
    LSb.AppendLine('  function_tree: "trees/function-tree.yaml"');
    LSb.AppendLine('  module_tree: "trees/module-tree.yaml"');
    LSb.AppendLine('  view_tree: "trees/view-tree.yaml"');
    LSb.AppendLine('');
    LSb.AppendLine('relations: "relations/requirement-relations.yaml"');
    LSb.AppendLine('evidence: "evidence/source-evidence.yaml"');
    LSb.AppendLine('issues: "issues/doc-issues.yaml"');
    LSb.AppendLine('decisions: "decisions/requirement-decisions.yaml"');
    LSb.AppendLine('');
    LSb.AppendLine('imports: []');

    WriteYamlFile('project-spec.yaml', LSb.ToString);
  finally
    LSb.Free;
  end;
end;

procedure TDeepSpecStoreService.WriteEmptyTrees;
begin
  var LNow := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"+08:00"', Now);

  var LTemplate :=
    'version: "1.0"' + sLineBreak +
    'tree: %s' + sLineBreak +
    'generated_at: "' + LNow + '"' + sLineBreak +
    'generator: "deepspec-scan"' + sLineBreak +
    'nodes: []' + sLineBreak;

  WriteYamlFile('trees/function-tree.yaml', Format(LTemplate, ['function']));
  WriteYamlFile('trees/module-tree.yaml', Format(LTemplate, ['module']));
  WriteYamlFile('trees/view-tree.yaml', Format(LTemplate, ['view']));

  WriteYamlFile('relations/requirement-relations.yaml',
    'version: "1.0"' + sLineBreak +
    'generated_at: "' + LNow + '"' + sLineBreak +
    'relations: []' + sLineBreak);

  WriteYamlFile('evidence/source-evidence.yaml',
    'version: "1.0"' + sLineBreak +
    'evidence: []' + sLineBreak);

  WriteYamlFile('issues/doc-issues.yaml',
    'version: "1.0"' + sLineBreak +
    'issues: []' + sLineBreak);

  WriteYamlFile('decisions/requirement-decisions.yaml',
    'version: "1.0"' + sLineBreak +
    'decisions: []' + sLineBreak);
end;

procedure TDeepSpecStoreService.WriteGitIgnore;
begin
  var LContent :=
    '# DeepSpec generated artifacts (regenerable)' + sLineBreak +
    'html/' + sLineBreak +
    'llm/candidate-output.yaml' + sLineBreak +
    'llm/last-run.yaml' + sLineBreak +
    'logs/' + sLineBreak +
    '' + sLineBreak +
    '# Auto-generated prompt templates' + sLineBreak +
    'prompts/context-pack.md' + sLineBreak +
    'prompts/doc-optimization-prompt.md' + sLineBreak +
    'prompts/node-prompt.md' + sLineBreak +
    'prompts/agents-draft.md' + sLineBreak +
    'prompts/claude-draft.md' + sLineBreak +
    'prompts/cursor-rules-draft.md' + sLineBreak;

  WriteYamlFile('.gitignore', LContent);
end;

procedure TDeepSpecStoreService.WriteTreeFile(const ARelPath: string;
  ATree: DeepSpec.Models.TTreeType;
  ANodes: System.Generics.Collections.TList<DeepSpec.Models.TSpecNode>);
begin
  var LWriter := TYamlWriter.Create;
  try
    LWriter.WriteTreeFile(ATree, 'deepspec-treebuilder', ANodes);
    WriteYamlFile(ARelPath, LWriter.ToString);
  finally
    LWriter.Free;
  end;
end;

procedure TDeepSpecStoreService.WriteEvidenceFile(const ARelPath: string;
  AEvidence: System.Generics.Collections.TList<DeepSpec.Models.TSpecEvidence>);
begin
  var LWriter := TYamlWriter.Create;
  try
    LWriter.WriteEvidenceFile(AEvidence);
    WriteYamlFile(ARelPath, LWriter.ToString);
  finally
    LWriter.Free;
  end;
end;

function TDeepSpecStoreService.ReadTreeFile(const ARelPath: string): TList<TSpecNode>;

  function StringList(ANode: TYamlNode): TArray<string>;
  begin
    Result := nil;
    if (ANode = nil) or (ANode.Kind <> ykSequence) then Exit;
    SetLength(Result, ANode.SeqCount);
    for var I := 0 to ANode.SeqCount - 1 do
    begin
      var LItem := ANode.SeqItem(I);
      if LItem <> nil then
        Result[I] := LItem.AsString;
    end;
  end;

  function ReadSourceRefs(ANode: TYamlNode): TSourceRefArray;
  begin
    Result := nil;
    if (ANode = nil) or (ANode.Kind <> ykSequence) then Exit;
    SetLength(Result, ANode.SeqCount);
    for var I := 0 to ANode.SeqCount - 1 do
    begin
      var LItem := ANode.SeqItem(I);
      if LItem = nil then Continue;
      Result[I].RefId := LItem.GetString('ref_id', '');
      Result[I].Relevance := LItem.GetString('relevance', '');
      Result[I].Note := LItem.GetString('note', '');
    end;
  end;

var
  LParser: TYamlParser;
  LRoot, LNodesSeq, LItem: TYamlNode;
  LFullPath: string;
  LNode: TSpecNode;
  LDefaultTree: TTreeType;
begin
  Result := TList<TSpecNode>.Create;
  LFullPath := TPath.Combine(FBasePath, ARelPath);
  if not TFile.Exists(LFullPath) then Exit;

  LParser := TYamlParser.Create;
  try
    LRoot := LParser.ParseFile(LFullPath);
    if LRoot = nil then Exit;
    try
      LDefaultTree := TSpecEnums.TreeTypeFromStr(LRoot.GetString('tree', ''));
      LNodesSeq := LRoot.GetSeq('nodes');
      if LNodesSeq = nil then Exit;

      for var I := 0 to LNodesSeq.SeqCount - 1 do
      begin
        LItem := LNodesSeq.SeqItem(I);
        if (LItem = nil) or (LItem.Kind <> ykMap) then Continue;

        LNode := Default(TSpecNode);
        LNode.Id := LItem.GetString('id', '');
        if LNode.Id = '' then Continue;
        LNode.Tree := TSpecEnums.TreeTypeFromStr(LItem.GetString('tree', ''),
          LDefaultTree);
        LNode.Title := LItem.GetString('title', '');
        LNode.Kind := LItem.GetString('kind', '');
        LNode.ParentId := LItem.GetString('parent_id', '');
        LNode.SlugOverride := LItem.GetString('slug_override', '');
        LNode.ContentHash := LItem.GetString('content_hash', '');
        LNode.RelationHash := LItem.GetString('relation_hash', '');
        LNode.Revision := LItem.GetInteger('revision', 0);
        LNode.Summary := LItem.GetString('summary', '');
        LNode.Status := TSpecEnums.NodeStatusFromStr(LItem.GetString('status', ''));
        LNode.Confidence := TSpecEnums.ConfidenceFromStr(LItem.GetString('confidence', ''));
        LNode.SourceLayer := TSpecEnums.SourceLayerFromStr(
          LItem.GetString('source_layer', ''));
        LNode.SourceRefs := ReadSourceRefs(LItem.Get('source_refs'));
        LNode.DecisionRefs := StringList(LItem.Get('decision_refs'));
        LNode.IssueRefs := StringList(LItem.Get('issue_refs'));
        LNode.RelatedFunctions := StringList(LItem.Get('related_functions'));
        LNode.RelatedModules := StringList(LItem.Get('related_modules'));
        LNode.RelatedViews := StringList(LItem.Get('related_views'));
        LNode.Children := StringList(LItem.Get('children'));
        LNode.Tags := StringList(LItem.Get('tags'));
        LNode.AcceptanceCriteria := StringList(LItem.Get('acceptance_criteria'));
        LNode.NotDoing := StringList(LItem.Get('not_doing'));

        Result.Add(LNode);
      end;
    finally
      LRoot.Free;
    end;
  finally
    LParser.Free;
  end;
end;

end.
