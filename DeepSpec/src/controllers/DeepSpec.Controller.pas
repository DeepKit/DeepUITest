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
  DeepSpec.Services.LLM;

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
    FStatus: IShellStatusManager;
    FContext: IShellContextManager;
    FBus: IShellEventBus;
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

  // Initialize spec store, render, prompts, and decisions services
  FSpecStore.Initialize(APath);
  FRender.Initialize(FProjectService.DeepSpecPath);
  FPrompts.Initialize(FProjectService.DeepSpecPath);
  FDecisions.Initialize(FProjectService.DeepSpecPath);
  FDecisions.Load;

  // Run scan
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
    FStatus.Info('DeepSpec.Render',
      'Re-rendered HTML to ' + FProjectService.DeepSpecPath + '\html\');
  except
    on E: Exception do
      FStatus.LogError('DeepSpec.Render', 'Render failed: ' + E.Message, E.ClassName);
  end;
end;

procedure TDeepSpecController.RefreshFromYaml;
var
  LFunc, LModule, LView: TList<TSpecNode>;
begin
  if not FProjectService.IsOpen then
  begin
    FStatus.Warning('DeepSpec', 'No project open');
    Exit;
  end;

  LFunc := nil;
  LModule := nil;
  LView := nil;
  try
    try
      LFunc := FSpecStore.ReadTreeFile('trees/function-tree.yaml');
      LModule := FSpecStore.ReadTreeFile('trees/module-tree.yaml');
      LView := FSpecStore.ReadTreeFile('trees/view-tree.yaml');

      FRender.RenderIndex(FProjectService.ProjectName, FScanService.TotalFiles);
      FRender.RenderTree('function-tree', 'Function Tree', LFunc);
      FRender.RenderTree('module-tree', 'Module Tree', LModule);
      FRender.RenderTree('view-tree', 'View Tree', LView);

      FStatus.Info('DeepSpec.Render',
        Format('Refreshed HTML from YAML: %d func / %d module / %d view nodes.',
          [LFunc.Count, LModule.Count, LView.Count]));
    except
      on E: Exception do
        FStatus.LogError('DeepSpec.Render', 'RefreshFromYaml failed: ' + E.Message,
          E.ClassName);
    end;
  finally
    LFunc.Free;
    LModule.Free;
    LView.Free;
  end;
end;

procedure TDeepSpecController.PromotePendingDecisions;
var
  LCount: Integer;
begin
  if not FProjectService.IsOpen then
  begin
    FStatus.Warning('DeepSpec', 'No project open');
    Exit;
  end;

  try
    LCount := FDecisions.PromotePending;
    if LCount = 0 then
      FStatus.Info('DeepSpec.Decisions', 'No pending decisions to promote.')
    else
      FStatus.Info('DeepSpec.Decisions',
        Format('Promoted %d pending decision(s) to formal decisions.', [LCount]));
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
      LCandidatePath := TPath.Combine(FProjectService.DeepSpecPath, 'llm\candidate-output.yaml');
      LContextPath := TPath.Combine(FProjectService.DeepSpecPath, 'prompts\context-pack.md');

      try
        if TFile.Exists(LContextPath) then
          LPrompt := TFile.ReadAllText(LContextPath, TEncoding.UTF8)
        else
        begin
          TThread.Queue(nil,
            procedure
            begin
              LStatus.LogError('DeepSpec.LLM',
                'Context pack not found. Run scan first.', LContextPath);
              LStatus.TaskFinish('llm-gen', 'Failed: no context pack');
            end);
          Exit;
        end;

        LResult := FLLM.Generate(LPrompt);

        TThread.Queue(nil,
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
          end);
      except
        on E: Exception do
        begin
          var LMsg := E.Message;
          TThread.Queue(nil,
            procedure
            begin
              LStatus.LogError('DeepSpec.LLM', 'LLM exception', LMsg);
              LStatus.TaskFinish('llm-gen', 'Failed: ' + LMsg);
            end);
        end;
      end;
    end).Start;
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
    // Scan files
    FScanService.ScanDirectory(LPath);
    FStatus.Progress('scan', 'DeepSpec.Scan', 50, 'Classified ' +
      FScanService.TotalFiles.ToString + ' files');

    // Detect project type
    var LType := 'unknown';
    if FScanService.CategoryCount(fcCode) > 0 then
    begin
      // Check for Delphi
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

    // Create .deepspec directory
    FSpecStore.CreateDirectoryStructure;
    FStatus.Progress('scan', 'DeepSpec.Scan', 70, 'Writing .deepspec');

    // Write files
    FSpecStore.WriteScanReport(FScanService);
    FSpecStore.WriteProjectSpec(FProjectService.ProjectName, LType, 0);
    FSpecStore.WriteEmptyTrees;
    FSpecStore.WriteGitIgnore;

    // Build basic three trees from scan
    FTreeBuilder.BuildFromScan(FScanService, FProjectService.ProjectName,
      FProjectService.ProjectPath);
    FStatus.Progress('scan', 'DeepSpec.Scan', 80, 'Building trees');

    // Write the populated trees
    FSpecStore.WriteTreeFile('trees/function-tree.yaml', ttFunction,
      FTreeBuilder.FunctionNodes);
    FSpecStore.WriteTreeFile('trees/module-tree.yaml', ttModule,
      FTreeBuilder.ModuleNodes);
    FSpecStore.WriteTreeFile('trees/view-tree.yaml', ttView,
      FTreeBuilder.ViewNodes);
    FSpecStore.WriteEvidenceFile('evidence/source-evidence.yaml',
      FTreeBuilder.EvidenceList);

    // Render HTML
    FRender.RenderScanReport(FScanService, FProjectService.ProjectName, LType);
    FRender.RenderIndex(FProjectService.ProjectName, FScanService.TotalFiles);
    FRender.RenderTree('function-tree', 'Function Tree', FTreeBuilder.FunctionNodes);
    FRender.RenderTree('module-tree', 'Module Tree', FTreeBuilder.ModuleNodes);
    FRender.RenderTree('view-tree', 'View Tree', FTreeBuilder.ViewNodes);

    // Generate prompts for LLM workflow
    FPrompts.WriteContextPack(FScanService, FProjectService.ProjectName, LType);
    FPrompts.WriteGenerationPrompt(FProjectService.ProjectName, LType);

    FStatus.Progress('scan', 'DeepSpec.Scan', 100, 'Done');
    FStatus.TaskFinish('scan',
      Format('Scan complete: %d files (%d docs, %d code, %d ui, %d config, %d ai_rules)',
        [FScanService.TotalFiles,
         FScanService.CategoryCount(fcDocuments),
         FScanService.CategoryCount(fcCode),
         FScanService.CategoryCount(fcUI),
         FScanService.CategoryCount(fcConfig),
         FScanService.CategoryCount(fcAiRules)]));

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
