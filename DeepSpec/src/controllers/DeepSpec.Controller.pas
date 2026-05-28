{ ============================================================================
  DeepSpec.Controller

  Coordinates the main workflow: open project → scan → generate .deepspec →
  refresh UI. Commands delegate to this controller.
  ============================================================================ }

unit DeepSpec.Controller;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DeepBase.VCL.DeepShell.Intf,
  DeepSpec.Services.Project,
  DeepSpec.Services.Scan,
  DeepSpec.Services.SpecStore,
  DeepSpec.Services.Render,
  DeepSpec.Services.TreeBuilder,
  DeepSpec.Services.Prompts,
  DeepSpec.Services.Decisions,
  DeepSpec.Services.LLM,
  DeepSpec.Services.Settings;

type
  TDeepSpecController = class
  private
    FProjectService: TDeepSpecProjectService;
    FScanService: TDeepSpecScanService;
    FSpecStore: TDeepSpecStoreService;
    FRender: TDeepSpecRenderService;
    FTreeBuilder: TDeepSpecTreeBuilder;
    FPrompts: TDeepSpecPromptService;
    FDecisions: TDeepSpecDecisionsService;
    FLLM: TDeepSpecLLMService;
    FSettings: TDeepSpecSettingsService;
    FStatus: IShellStatusManager;
    FContext: IShellContextManager;
    FBus: IShellEventBus;
    FDocsFiles: TArray<string>;
    procedure ScanDocsFirst;
    procedure WriteDocsSummary;
  public
    constructor Create(
      AProjectService: TDeepSpecProjectService;
      AScanService: TDeepSpecScanService;
      ASpecStore: TDeepSpecStoreService;
      ARender: TDeepSpecRenderService;
      ATreeBuilder: TDeepSpecTreeBuilder;
      APrompts: TDeepSpecPromptService;
      ADecisions: TDeepSpecDecisionsService;
      ALLM: TDeepSpecLLMService;
      ASettings: TDeepSpecSettingsService;
      const AStatus: IShellStatusManager;
      const AContext: IShellContextManager;
      const ABus: IShellEventBus);

    procedure OpenAndScan(const APath: string);
    procedure RunScan;
    procedure ExportPrompt;
    procedure GenerateB;
    procedure RenderAll;
    procedure RefreshFromYaml;
    procedure PromotePendingDecisions;
    function IsProjectOpen: Boolean;
    property ProjectService: TDeepSpecProjectService read FProjectService;
    property ScanService: TDeepSpecScanService read FScanService;
    property TreeBuilder: TDeepSpecTreeBuilder read FTreeBuilder;
    property Decisions: TDeepSpecDecisionsService read FDecisions;
    property LLM: TDeepSpecLLMService read FLLM;
    property Settings: TDeepSpecSettingsService read FSettings;
    property DocsFiles: TArray<string> read FDocsFiles;
  end;

implementation

uses
  System.IOUtils,
  DeepBase.VCL.DeepShell.Types,
  DeepSpec.Models;

constructor TDeepSpecController.Create(
  AProjectService: TDeepSpecProjectService;
  AScanService: TDeepSpecScanService;
  ASpecStore: TDeepSpecStoreService;
  ARender: TDeepSpecRenderService;
  ATreeBuilder: TDeepSpecTreeBuilder;
  APrompts: TDeepSpecPromptService;
  ADecisions: TDeepSpecDecisionsService;
  ALLM: TDeepSpecLLMService;
  ASettings: TDeepSpecSettingsService;
  const AStatus: IShellStatusManager;
  const AContext: IShellContextManager;
  const ABus: IShellEventBus);
begin
  inherited Create;
  FProjectService := AProjectService;
  FScanService := AScanService;
  FSpecStore := ASpecStore;
  FRender := ARender;
  FTreeBuilder := ATreeBuilder;
  FPrompts := APrompts;
  FDecisions := ADecisions;
  FLLM := ALLM;
  FSettings := ASettings;
  FStatus := AStatus;
  FContext := AContext;
  FBus := ABus;
end;

function TDeepSpecController.IsProjectOpen: Boolean;
begin
  Result := FProjectService.IsOpen;
end;

procedure TDeepSpecController.OpenAndScan(const APath: string);
begin
  FStatus.Info('DeepSpec', 'Opening project: ' + APath);

  // Open project
  FProjectService.OpenProject(APath);
  FContext.SetProject(FProjectService.ProjectName, APath);

  // Initialize settings (docs path)
  FSettings.Initialize(APath);

  // Initialize spec store, render, prompts, and decisions services
  FSpecStore.Initialize(APath);
  FRender.Initialize(FProjectService.DeepSpecPath);
  FPrompts.Initialize(FProjectService.DeepSpecPath);
  FDecisions.Initialize(FProjectService.DeepSpecPath);
  FDecisions.Load;

  // Run scan (includes docs-first reading)
  RunScan;
end;

procedure TDeepSpecController.ExportPrompt;
begin
  if not FProjectService.IsOpen then
  begin
    FStatus.Warning('DeepSpec', 'No project open');
    Exit;
  end;

  FPrompts.WriteContextPack(FScanService, FProjectService.ProjectName,
    FProjectService.ProjectType);
  FPrompts.WriteGenerationPrompt(FProjectService.ProjectName,
    FProjectService.ProjectType);

  FStatus.Info('DeepSpec.Prompts',
    'Exported prompts to ' + FProjectService.DeepSpecPath + '\prompts\');
end;

procedure TDeepSpecController.RenderAll;
begin
  if not FProjectService.IsOpen then
  begin
    FStatus.Warning('DeepSpec', 'No project open');
    Exit;
  end;

  try
    FRender.RenderScanReport(FScanService, FProjectService.ProjectName,
      FProjectService.ProjectType);
    FRender.RenderIndex(FProjectService.ProjectName, FScanService.TotalFiles);
    FRender.RenderTree('function-tree', 'Function Tree', FTreeBuilder.FunctionNodes);
    FRender.RenderTree('module-tree', 'Module Tree', FTreeBuilder.ModuleNodes);
    FRender.RenderTree('view-tree', 'View Tree', FTreeBuilder.ViewNodes);
    if FTreeBuilder.DataNodes.Count > 0 then
      FRender.RenderTree('data-tree', 'Data Tree', FTreeBuilder.DataNodes);
    FRender.RenderProblemsPage(FTreeBuilder.FunctionNodes, FTreeBuilder.ModuleNodes,
      FTreeBuilder.ViewNodes, FTreeBuilder.DataNodes);

    var LBundlePath := TPath.Combine(FProjectService.DeepSpecPath, 'bundles.yaml');
    if TFile.Exists(LBundlePath) then
    begin
      var LBundles := FSpecStore.ReadBundlesFile(LBundlePath);
      try
        FRender.RenderBundlesPage(LBundles, FTreeBuilder.FunctionNodes,
          FTreeBuilder.ModuleNodes, FTreeBuilder.ViewNodes, FTreeBuilder.DataNodes);
      finally
        LBundles.Free;
      end;
    end;

    FStatus.Info('DeepSpec.Render',
      'Re-rendered HTML to ' + FProjectService.DeepSpecPath + '\html\');
  except
    on E: Exception do
      FStatus.LogError('DeepSpec.Render', 'Render failed: ' + E.Message, E.ClassName);
  end;
end;

procedure TDeepSpecController.RefreshFromYaml;
var
  LFunc, LModule, LView, LData: TList<TSpecNode>;
begin
  if not FProjectService.IsOpen then
  begin
    FStatus.Warning('DeepSpec', 'No project open');
    Exit;
  end;

  LFunc := nil;
  LModule := nil;
  LView := nil;
  LData := nil;
  try
    try
      LFunc := FSpecStore.ReadTreeFile('trees/function-tree.yaml');
      LModule := FSpecStore.ReadTreeFile('trees/module-tree.yaml');
      LView := FSpecStore.ReadTreeFile('trees/view-tree.yaml');
      if TFile.Exists(TPath.Combine(FProjectService.DeepSpecPath, 'trees\data-tree.yaml')) then
        LData := FSpecStore.ReadTreeFile('trees/data-tree.yaml');

      FRender.RenderIndex(FProjectService.ProjectName, FScanService.TotalFiles);
      FRender.RenderTree('function-tree', 'Function Tree', LFunc);
      FRender.RenderTree('module-tree', 'Module Tree', LModule);
      FRender.RenderTree('view-tree', 'View Tree', LView);
      if (LData <> nil) and (LData.Count > 0) then
        FRender.RenderTree('data-tree', 'Data Tree', LData);
      FRender.RenderProblemsPage(LFunc, LModule, LView, LData);

      // Bundles page
      var LBundlePath := TPath.Combine(FProjectService.DeepSpecPath, 'bundles.yaml');
      if TFile.Exists(LBundlePath) then
      begin
        var LBundles := FSpecStore.ReadBundlesFile(LBundlePath);
        try
          FRender.RenderBundlesPage(LBundles, LFunc, LModule, LView, LData);
        finally
          LBundles.Free;
        end;
      end;

      var LMsg := Format('Refreshed HTML from YAML: %d func / %d module / %d view',
        [LFunc.Count, LModule.Count, LView.Count]);
      if LData <> nil then
        LMsg := LMsg + Format(' / %d data nodes.', [LData.Count])
      else
        LMsg := LMsg + '.';
      FStatus.Info('DeepSpec.Render', LMsg);
    except
      on E: Exception do
        FStatus.LogError('DeepSpec.Render', 'RefreshFromYaml failed: ' + E.Message,
          E.ClassName);
    end;
  finally
    LFunc.Free;
    LModule.Free;
    LView.Free;
    LData.Free;
  end;
end;

procedure TDeepSpecController.PromotePendingDecisions;
var
  LCount: Integer;
  LTreeNames: TArray<string>;
begin
  if not FProjectService.IsOpen then
  begin
    FStatus.Warning('DeepSpec', 'No project open');
    Exit;
  end;

  try
    LCount := FDecisions.PromotePending;
    if LCount = 0 then
    begin
      FStatus.Info('DeepSpec.Decisions', 'No pending decisions to promote.');
      Exit;
    end;

    FStatus.Info('DeepSpec.Decisions',
      Format('Promoted %d pending decision(s) to formal decisions.', [LCount]));

    // Apply state machine transitions to all trees
    LTreeNames := TArray<string>.Create(
      'trees/function-tree.yaml', 'trees/module-tree.yaml',
      'trees/view-tree.yaml', 'trees/data-tree.yaml');

    for var LTree in LTreeNames do
    begin
      if not TFile.Exists(TPath.Combine(FProjectService.DeepSpecPath, LTree)) then Continue;

      // Read and write back transitions inline
      var LNodes := FSpecStore.ReadTreeFile(LTree);
      try
        if LNodes <> nil then
        begin
          FDecisions.ApplyNodeStatusTransitions(LTree, LNodes);
          FSpecStore.WriteTreeFile(LTree, LNodes[0].Tree, LNodes);
        end;
      finally
        LNodes.Free;
      end;
    end;
  except
    on E: Exception do
      FStatus.LogError('DeepSpec.Decisions',
        'Promote failed: ' + E.Message, E.ClassName);
  end;
end;

procedure TDeepSpecController.GenerateB;
begin
  if not FProjectService.IsOpen then
  begin
    FStatus.Warning('DeepSpec', 'No project open');
    Exit;
  end;

  if not FLLM.IsAvailable then
  begin
    FStatus.Warning('DeepSpec.LLM',
      'LLM not configured. Configure it in DeepBase settings (LLM tab) or ' +
      'use Export Prompt to copy the prompt to your external AI tool.');
    Exit;
  end;

  // Run async to avoid blocking UI
  FStatus.TaskStart('llm-gen', 'DeepSpec.LLM',
    'Calling LLM to generate B (this may take 10-60 seconds)...');

  var LLLMRef := FLLM; // capture before thread
  var LDeepSpecPath := FProjectService.DeepSpecPath;

  TThread.CreateAnonymousThread(
    procedure
    var
      LContextPath: string;
      LPrompt: string;
      LResult: TDeepSpecLLMResult;
      LStatus: IShellStatusManager;
      LCandidatePath: string;
    begin
      LStatus := FStatus; // capture
      LCandidatePath := TPath.Combine(LDeepSpecPath, 'llm\candidate-output.yaml');
      LContextPath := TPath.Combine(LDeepSpecPath, 'prompts\context-pack.md');

      try
        if TFile.Exists(LContextPath) then
          LPrompt := TFile.ReadAllText(LContextPath, TEncoding.UTF8)
        else
        begin
          var LErrProc: TThreadProcedure :=
            procedure
            begin
              LStatus.LogError('DeepSpec.LLM',
                'Context pack not found. Run scan first.', LContextPath);
              LStatus.TaskFinish('llm-gen', 'Failed: no context pack');
            end;
          TThread.Synchronize(nil, LErrProc);
          Exit;
        end;

        LResult := LLLMRef.Generate(LPrompt);

        var LQueueProc: TThreadProcedure :=
          procedure
          begin
            // Ensure llm directory exists
            var LDir := TPath.GetDirectoryName(LCandidatePath);
            if not TDirectory.Exists(LDir) then
              TDirectory.CreateDirectory(LDir);

            if LResult.Success then
            begin
              TFile.WriteAllText(LCandidatePath, LResult.Content, TEncoding.UTF8);
              LStatus.TaskFinish('llm-gen',
                Format('LLM done in %dms. Tokens in/out: %d/%d. Output: %s',
                  [LResult.DurationMs, LResult.InputTokens, LResult.OutputTokens,
                   LCandidatePath]));
            end
            else
            begin
              LStatus.LogError('DeepSpec.LLM', 'LLM call failed', LResult.ErrorMessage);
              LStatus.TaskFinish('llm-gen', 'Failed: ' + LResult.ErrorMessage);
            end;
          end;
        TThread.Queue(nil, LQueueProc);
      except
        on E: Exception do
        begin
          var LMsg := E.Message;
          var LExProc: TThreadProcedure :=
            procedure
            begin
              LStatus.LogError('DeepSpec.LLM', 'LLM exception', LMsg);
              LStatus.TaskFinish('llm-gen', 'Failed: ' + LMsg);
            end;
          TThread.Queue(nil, LExProc);
        end;
      end;
    end).Start;
end;

procedure TDeepSpecController.ScanDocsFirst;
var
  LDocsPath: string;
  LDocFiles: TArray<string>;
begin
  LDocsPath := FSettings.DocsFullPath;
  if not TDirectory.Exists(LDocsPath) then
  begin
    FStatus.Info('DeepSpec.Docs', 'No docs directory found at ' + LDocsPath);
    FDocsFiles := nil;
    Exit;
  end;

  FStatus.Progress('scan', 'DeepSpec.Docs', 5, 'Reading docs from ' + LDocsPath);

  LDocFiles := TDirectory.GetFiles(LDocsPath, '*.md',
    TSearchOption.soAllDirectories);
  var LMoreDocs := TDirectory.GetFiles(LDocsPath, '*.txt',
    TSearchOption.soAllDirectories);

  var LList := TList<string>.Create;
  try
    for var Lf in LDocFiles do
      LList.Add(Lf);
    for var Lf in LMoreDocs do
      LList.Add(Lf);
    FDocsFiles := LList.ToArray;
  finally
    LList.Free;
  end;

  FStatus.Progress('scan', 'DeepSpec.Docs', 15,
    Format('Found %d document(s) in docs/', [Length(FDocsFiles)]));

  for var I := 0 to High(FDocsFiles) do
    FStatus.Info('DeepSpec.Docs', '  ' + ExtractFileName(FDocsFiles[I]));
end;

procedure TDeepSpecController.WriteDocsSummary;
var
  LSb: TStringBuilder;
  LOutPath: string;
begin
  if Length(FDocsFiles) = 0 then Exit;

  LSb := TStringBuilder.Create;
  try
    LSb.AppendLine('version: "1.0"');
    LSb.AppendLine('docs_path: "' + FSettings.DocsFullPath.Replace('\', '/') + '"');
    LSb.AppendLine('count: ' + Length(FDocsFiles).ToString);
    LSb.AppendLine('files:');

    for var LFile in FDocsFiles do
    begin
      var LRoot := FSettings.DocsFullPath;
      if not LFile.StartsWith(LRoot, True) then Continue;
      var LRelPath := LFile.Substring(Length(LRoot) + 1);
      LSb.AppendLine('  - path: "' + LRelPath.Replace('\', '/') + '"');
      LSb.AppendLine('    name: "' + ExtractFileName(LFile) + '"');

      // Read first line as title hint
      try
        var LLines := TFile.ReadAllLines(LFile, TEncoding.UTF8);
        if Length(LLines) > 0 then
        begin
          var LTitle := LLines[0].Trim;
          if LTitle.StartsWith('#') then
            LTitle := LTitle.Trim(['#']).Trim;
          LSb.AppendLine('    title: "' + LTitle + '"');
        end;
      except
        LSb.AppendLine('    title: ""');
      end;
    end;

    LOutPath := TPath.Combine(FProjectService.DeepSpecPath, 'docs-summary.yaml');
    TFile.WriteAllText(LOutPath, LSb.ToString, TEncoding.UTF8);
  finally
    LSb.Free;
  end;
end;

procedure TDeepSpecController.RunScan;
begin
  if not FProjectService.IsOpen then
  begin
    FStatus.Warning('DeepSpec', 'No project open');
    Exit;
  end;

  var LPath := FProjectService.ProjectPath;
  FStatus.TaskStart('scan', 'DeepSpec.Scan', 'Scanning ' + LPath);

  try
    // Step 1: Read docs directory first
    ScanDocsFirst;

    // Step 2: Full project scan
    FStatus.Progress('scan', 'DeepSpec.Scan', 30, 'Scanning project files...');
    FScanService.ScanDirectory(LPath);
    FStatus.Progress('scan', 'DeepSpec.Scan', 40,
      'Classified ' + FScanService.TotalFiles.ToString + ' files');

    // Step 3: Detect project type
    var LType := 'unknown';
    if FScanService.CategoryCount(fcCode) > 0 then
    begin
      var LCodeFiles := FScanService.GetFilesByCategory(fcCode);
      for var LFile in LCodeFiles do
        if LFile.EndsWith('.pas') or LFile.EndsWith('.dpr') then
        begin
          LType := 'delphi_vcl';
          Break;
        end;
      if LType = 'unknown' then
        for var LFile in LCodeFiles do
        begin
          if LFile.EndsWith('.ts') or LFile.EndsWith('.tsx') then
          begin
            LType := 'web_react';
            Break;
          end;
          if LFile.EndsWith('.py') then
          begin
            LType := 'python_backend';
            Break;
          end;
          if LFile.EndsWith('.go') then
          begin
            LType := 'mixed';
            Break;
          end;
        end;
    end;
    FProjectService.SetProjectType(LType);
    FStatus.Progress('scan', 'DeepSpec.Scan', 50,
      'Detected project type: ' + LType);

    // Step 4: Write .deepspec structure
    FSpecStore.CreateDirectoryStructure;
    FStatus.Progress('scan', 'DeepSpec.Scan', 55, 'Writing .deepspec...');
    FSpecStore.WriteScanReport(FScanService);
    FSpecStore.WriteProjectSpec(FProjectService.ProjectName, LType, 0);
    FSpecStore.WriteEmptyTrees;
    FSpecStore.WriteGitIgnore;

    // Write docs summary
    WriteDocsSummary;

    // Step 5: Build trees from scan
    FTreeBuilder.BuildFromScan(FScanService, FProjectService.ProjectName,
      FProjectService.ProjectPath);
    FStatus.Progress('scan', 'DeepSpec.Scan', 70,
      Format('Building trees (%d modules, %d views, %d data)',
        [FTreeBuilder.ModuleNodes.Count,
         FTreeBuilder.ViewNodes.Count,
         FTreeBuilder.DataNodes.Count]));

    // Write populated trees
    FSpecStore.WriteTreeFile('trees/function-tree.yaml', ttFunction,
      FTreeBuilder.FunctionNodes);
    FSpecStore.WriteTreeFile('trees/module-tree.yaml', ttModule,
      FTreeBuilder.ModuleNodes);
    FSpecStore.WriteTreeFile('trees/view-tree.yaml', ttView,
      FTreeBuilder.ViewNodes);
    if FTreeBuilder.DataNodes.Count > 0 then
      FSpecStore.WriteTreeFile('trees/data-tree.yaml', ttData,
        FTreeBuilder.DataNodes);
    FSpecStore.WriteEvidenceFile('evidence/source-evidence.yaml',
      FTreeBuilder.EvidenceList);

    // Step 6: Render HTML
    FStatus.Progress('scan', 'DeepSpec.Scan', 85, 'Rendering HTML...');
    FRender.RenderScanReport(FScanService, FProjectService.ProjectName, LType);
    FRender.RenderIndex(FProjectService.ProjectName, FScanService.TotalFiles);
    FRender.RenderTree('function-tree', 'Function Tree', FTreeBuilder.FunctionNodes);
    FRender.RenderTree('module-tree', 'Module Tree', FTreeBuilder.ModuleNodes);
    FRender.RenderTree('view-tree', 'View Tree', FTreeBuilder.ViewNodes);
    if FTreeBuilder.DataNodes.Count > 0 then
      FRender.RenderTree('data-tree', 'Data Tree', FTreeBuilder.DataNodes);
    FRender.RenderProblemsPage(FTreeBuilder.FunctionNodes, FTreeBuilder.ModuleNodes,
      FTreeBuilder.ViewNodes, FTreeBuilder.DataNodes);

    // Bundles page
    var LBundlePath := TPath.Combine(FProjectService.DeepSpecPath, 'bundles.yaml');
    if TFile.Exists(LBundlePath) then
    begin
      var LBundles := FSpecStore.ReadBundlesFile(LBundlePath);
      try
        FRender.RenderBundlesPage(LBundles, FTreeBuilder.FunctionNodes,
          FTreeBuilder.ModuleNodes, FTreeBuilder.ViewNodes, FTreeBuilder.DataNodes);
      finally
        LBundles.Free;
      end;
    end;

    // Step 7: Generate prompts
    FStatus.Progress('scan', 'DeepSpec.Scan', 95, 'Generating LLM prompts...');
    FPrompts.WriteContextPack(FScanService, FProjectService.ProjectName, LType);
    FPrompts.WriteGenerationPrompt(FProjectService.ProjectName, LType);

    FStatus.Progress('scan', 'DeepSpec.Scan', 100, 'Done');
    FStatus.TaskFinish('scan',
      Format('Scan complete: %d files (%d docs, %d code, %d ui, %d config, %d ai_rules) | %d docs in docs/',
        [FScanService.TotalFiles,
         FScanService.CategoryCount(fcDocuments),
         FScanService.CategoryCount(fcCode),
         FScanService.CategoryCount(fcUI),
         FScanService.CategoryCount(fcConfig),
         FScanService.CategoryCount(fcAiRules),
         Length(FDocsFiles)]));

    // Notify UI to refresh
    var LEvent: TDeepShellEvent;
    LEvent := Default(TDeepShellEvent);
    LEvent.Kind := sekProjectOpened;
    LEvent.Context := FContext.Current;
    FBus.Publish(LEvent);
  except
    on E: Exception do
    begin
      FStatus.LogError('DeepSpec.Scan', 'Scan failed: ' + E.Message, E.ClassName);
      FStatus.TaskFinish('scan', 'Scan failed');
    end;
  end;
end;

end.
