{ ============================================================================
  DeepSpec.Services.Prompts

  Generates LLM prompts: Context Pack, A→B generation, node review,
  decision write-back. Outputs to .deepspec/prompts/.
  ============================================================================ }

unit DeepSpec.Services.Prompts;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DeepSpec.Models,
  DeepSpec.Services.Scan;

type
  TDeepSpecPromptService = class(TInterfacedObject)
  private
    FBasePath: string;
    procedure WritePromptFile(const ARelPath, AContent: string);
  public
    procedure Initialize(const ADeepSpecPath: string);
    procedure WriteContextPack(AScan: TDeepSpecScanService;
      const AProjectName, AProjectType: string);
    procedure WriteGenerationPrompt(const AProjectName, AProjectType: string);
    procedure WriteNodePrompt(const ANode: TSpecNode);
    procedure WriteDecisionRewritePrompt(const ADecisions: TList<TSpecDecision>);
  end;

implementation

uses
  System.IOUtils;

procedure TDeepSpecPromptService.Initialize(const ADeepSpecPath: string);
begin
  FBasePath := TPath.Combine(ADeepSpecPath, 'prompts');
  if not TDirectory.Exists(FBasePath) then
    TDirectory.CreateDirectory(FBasePath);
end;

procedure TDeepSpecPromptService.WritePromptFile(const ARelPath, AContent: string);
begin
  TFile.WriteAllText(TPath.Combine(FBasePath, ARelPath), AContent, TEncoding.UTF8);
end;

procedure TDeepSpecPromptService.WriteContextPack(AScan: TDeepSpecScanService;
  const AProjectName, AProjectType: string);
var
  LSb: TStringBuilder;
begin
  LSb := TStringBuilder.Create;
  try
    LSb.AppendLine('# Context Pack');
    LSb.AppendLine('');
    LSb.AppendLine('## 1. Project');
    LSb.AppendLine('');
    LSb.AppendLine('- Name: ' + AProjectName);
    LSb.AppendLine('- Type: ' + AProjectType);
    LSb.AppendLine('- Scan time: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    LSb.AppendLine('');
    LSb.AppendLine('## 2. File Statistics');
    LSb.AppendLine('');
    LSb.AppendLine('| Category | Count |');
    LSb.AppendLine('|----------|-------|');
    LSb.AppendLine(Format('| Documents | %d |', [AScan.CategoryCount(fcDocuments)]));
    LSb.AppendLine(Format('| Code | %d |', [AScan.CategoryCount(fcCode)]));
    LSb.AppendLine(Format('| UI | %d |', [AScan.CategoryCount(fcUI)]));
    LSb.AppendLine(Format('| Config | %d |', [AScan.CategoryCount(fcConfig)]));
    LSb.AppendLine(Format('| AI Rules | %d |', [AScan.CategoryCount(fcAiRules)]));
    LSb.AppendLine(Format('| Total | %d |', [AScan.TotalFiles]));
    LSb.AppendLine('');

    LSb.AppendLine('## 3. Key Documents');
    LSb.AppendLine('');
    var LDocCount := 0;
    for var LFile in AScan.GetFilesByCategory(fcDocuments) do
    begin
      if LDocCount >= 20 then
      begin
        LSb.AppendLine('- ... (truncated)');
        Break;
      end;
      LSb.AppendLine('- ' + LFile);
      Inc(LDocCount);
    end;
    LSb.AppendLine('');

    LSb.AppendLine('## 4. AI Rules Files');
    LSb.AppendLine('');
    for var LFile in AScan.GetFilesByCategory(fcAiRules) do
      LSb.AppendLine('- ' + LFile);
    LSb.AppendLine('');

    LSb.AppendLine('## 5. Code Structure (sample)');
    LSb.AppendLine('');
    var LCodeCount := 0;
    for var LFile in AScan.GetFilesByCategory(fcCode) do
    begin
      if LCodeCount >= 30 then
      begin
        LSb.AppendLine('- ... (truncated)');
        Break;
      end;
      LSb.AppendLine('- ' + LFile);
      Inc(LCodeCount);
    end;
    LSb.AppendLine('');

    LSb.AppendLine('## 6. Task');
    LSb.AppendLine('');
    LSb.AppendLine('Read the project material above and generate or update the DeepSpec B at `.deepspec/`.');
    LSb.AppendLine('');
    LSb.AppendLine('Required outputs (YAML files in `.deepspec/`):');
    LSb.AppendLine('- `trees/function-tree.yaml` - what the software does');
    LSb.AppendLine('- `trees/module-tree.yaml` - how it is structured');
    LSb.AppendLine('- `trees/view-tree.yaml` - what users see');
    LSb.AppendLine('- `evidence/source-evidence.yaml` - traceable evidence for each node');
    LSb.AppendLine('- `issues/doc-issues.yaml` - gaps, conflicts, ambiguities');
    LSb.AppendLine('');

    LSb.AppendLine('## 7. Constraints');
    LSb.AppendLine('');
    LSb.AppendLine('- Follow the DeepSpec Protocol v1.1 schema strictly.');
    LSb.AppendLine('- Use English snake_case for enum values (e.g., `ai_inferred`, not `B:AI推断`).');
    LSb.AppendLine('- Mark all AI-generated content with `status: candidate` and `source_layer: ai_inferred`.');
    LSb.AppendLine('- Do NOT set `decided_by: human` - that is reserved for DeepSpec UI writes.');
    LSb.AppendLine('- Provide `source_refs` for every node tracing back to a file or doc.');
    LSb.AppendLine('- Do not modify any files outside `.deepspec/`.');
    LSb.AppendLine('');

    LSb.AppendLine('## 8. Output Format');
    LSb.AppendLine('');
    LSb.AppendLine('Write valid YAML files. Do NOT wrap output in Markdown code fences.');
    LSb.AppendLine('Each file must start with `version: "1.0"` and follow the schema.');

    WritePromptFile('context-pack.md', LSb.ToString);
  finally
    LSb.Free;
  end;
end;

procedure TDeepSpecPromptService.WriteGenerationPrompt(const AProjectName,
  AProjectType: string);
var
  LSb: TStringBuilder;
begin
  LSb := TStringBuilder.Create;
  try
    LSb.AppendLine('# A '#$2192' B Generation Prompt');
    LSb.AppendLine('');
    LSb.AppendLine('You are generating the DeepSpec B (specification facts) for a ' +
      AProjectType + ' project: ' + AProjectName);
    LSb.AppendLine('');
    LSb.AppendLine('## Process');
    LSb.AppendLine('');
    LSb.AppendLine('1. Read the project material listed in `context-pack.md`.');
    LSb.AppendLine('2. Identify functional capabilities (what the software does).');
    LSb.AppendLine('3. Identify modular structure (how code is organized).');
    LSb.AppendLine('4. Identify visible UI elements (what the user sees).');
    LSb.AppendLine('5. Cross-reference and find gaps, conflicts, ambiguities.');
    LSb.AppendLine('6. Output YAML files conforming to DeepSpec Protocol v1.1.');
    LSb.AppendLine('');
    LSb.AppendLine('## Output Files');
    LSb.AppendLine('');
    LSb.AppendLine('Write ONLY these files (do not modify anything else):');
    LSb.AppendLine('');
    LSb.AppendLine('- `.deepspec/trees/function-tree.yaml`');
    LSb.AppendLine('- `.deepspec/trees/module-tree.yaml`');
    LSb.AppendLine('- `.deepspec/trees/view-tree.yaml`');
    LSb.AppendLine('- `.deepspec/relations/requirement-relations.yaml`');
    LSb.AppendLine('- `.deepspec/evidence/source-evidence.yaml`');
    LSb.AppendLine('- `.deepspec/issues/doc-issues.yaml`');
    LSb.AppendLine('');
    LSb.AppendLine('## Quality Bar');
    LSb.AppendLine('');
    LSb.AppendLine('- Every node has at least one `source_refs[].ref_id`.');
    LSb.AppendLine('- Inferred content uses `confidence: low` and `status: candidate`.');
    LSb.AppendLine('- Do not invent features not supported by source material.');
    LSb.AppendLine('- Mark uncertain content as issues (type: low_confidence or no_source).');
    LSb.AppendLine('- Use stable IDs: `func-{slug}`, `mod-{slug}`, `view-{slug}`.');

    WritePromptFile('doc-optimization-prompt.md', LSb.ToString);
  finally
    LSb.Free;
  end;
end;

procedure TDeepSpecPromptService.WriteNodePrompt(const ANode: TSpecNode);
var
  LSb: TStringBuilder;
begin
  LSb := TStringBuilder.Create;
  try
    LSb.AppendLine('# Node Review Task');
    LSb.AppendLine('');
    LSb.AppendLine('## Node');
    LSb.AppendLine('');
    LSb.AppendLine('- ID: `' + ANode.Id + '`');
    LSb.AppendLine('- Tree: ' + TSpecEnums.TreeTypeToStr(ANode.Tree));
    LSb.AppendLine('- Title: ' + ANode.Title);
    LSb.AppendLine('- Kind: ' + ANode.Kind);
    LSb.AppendLine('- Status: ' + TSpecEnums.NodeStatusToStr(ANode.Status));
    LSb.AppendLine('- Confidence: ' + TSpecEnums.ConfidenceToStr(ANode.Confidence));
    LSb.AppendLine('- Source layer: ' + TSpecEnums.SourceLayerToStr(ANode.SourceLayer));
    LSb.AppendLine('');
    if ANode.Summary <> '' then
    begin
      LSb.AppendLine('## Current Summary');
      LSb.AppendLine('');
      LSb.AppendLine(ANode.Summary);
      LSb.AppendLine('');
    end;

    LSb.AppendLine('## Task');
    LSb.AppendLine('');
    LSb.AppendLine('Review this node. If you can improve the summary, acceptance criteria,');
    LSb.AppendLine('or source evidence, write an updated YAML fragment for it.');
    LSb.AppendLine('');
    LSb.AppendLine('Do NOT change the `id`. Do NOT delete `decision_refs` if present.');

    WritePromptFile('node-prompt.md', LSb.ToString);
  finally
    LSb.Free;
  end;
end;

procedure TDeepSpecPromptService.WriteDecisionRewritePrompt(
  const ADecisions: TList<TSpecDecision>);
var
  LSb: TStringBuilder;
begin
  LSb := TStringBuilder.Create;
  try
    LSb.AppendLine('# Decision Write-Back Prompt');
    LSb.AppendLine('');
    LSb.AppendLine('The user has made the following decisions about the project specification.');
    LSb.AppendLine('Update the corresponding nodes in `.deepspec/trees/` to reflect these decisions.');
    LSb.AppendLine('');

    if ADecisions.Count = 0 then
      LSb.AppendLine('(No accepted decisions yet.)')
    else
    begin
      LSb.AppendLine('## Accepted Decisions');
      LSb.AppendLine('');
      for var LDec in ADecisions do
      begin
        if LDec.Status <> dsAccepted then Continue;
        LSb.AppendLine('### ' + LDec.Title);
        LSb.AppendLine('');
        LSb.AppendLine('- ID: `' + LDec.Id + '`');
        LSb.AppendLine('- Type: ' + TSpecEnums.DecisionTypeToStr(LDec.DecisionType));
        LSb.AppendLine('- Decision: ' + LDec.DecisionText);
        if LDec.Rationale <> '' then
          LSb.AppendLine('- Rationale: ' + LDec.Rationale);
        if LDec.AiInstruction <> '' then
        begin
          LSb.AppendLine('');
          LSb.AppendLine('**AI Instruction:** ' + LDec.AiInstruction);
        end;
        LSb.AppendLine('');
      end;
    end;

    LSb.AppendLine('## Constraints');
    LSb.AppendLine('');
    LSb.AppendLine('- Treat accepted decisions as authoritative facts.');
    LSb.AppendLine('- When source documents conflict with an accepted decision, the decision wins.');
    LSb.AppendLine('- Do not silently delete nodes that have `decision_refs` non-empty.');
    LSb.AppendLine('- Update affected nodes by adding the `decision_refs` and adjusting status to `confirmed`.');

    WritePromptFile('decision-rewrite-prompt.md', LSb.ToString);
  finally
    LSb.Free;
  end;
end;

end.
