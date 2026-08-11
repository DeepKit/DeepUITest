
{ ============================================================================
  DeepSpec.MainForm

  Main form for DeepSpec - inherits TDeepMainForm from DeepShell.
  Only registers services, commands, and providers. No business logic here.
  ============================================================================ }

unit DeepSpec.MainForm;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.FileCtrl,
  Vcl.Buttons,
  Vcl.Shell.ShellCtrls,
  DeepBase.VCL.DeepShell.MainForm,
  DeepBase.VCL.DeepShell.Intf,
  DeepBase.VCL.DeepShell.Types,
  DeepSpec.Controller,
  DeepSpec.Services.Project,
  DeepSpec.Services.Scan,
  DeepSpec.Services.SpecStore,
  DeepSpec.Services.Render,
  DeepSpec.Services.TreeBuilder,
  DeepSpec.Services.Prompts,
  DeepSpec.Services.Decisions,
  DeepSpec.Services.LLM,
  DeepSpec.Services.Settings,
  DeepSpec.Models;

type
  TDeepSpecMainForm = class(TDeepMainForm)
  private
    FController: TDeepSpecController;
    FProjectService: TDeepSpecProjectService;
    FScanService: TDeepSpecScanService;
    FSpecStore: TDeepSpecStoreService;
    FRender: TDeepSpecRenderService;
    FTreeBuilder: TDeepSpecTreeBuilder;
    FPrompts: TDeepSpecPromptService;
    FDecisions: TDeepSpecDecisionsService;
    FLLMService: TDeepSpecLLMService;
    FSettings: TDeepSpecSettingsService;
    FLLMOwned: TObject;
    // UI: Left panel tabs
    FLeftPages: TPageControl;
    FTabDirs: TTabSheet;
    FTabFunc: TTabSheet;
    FTabModule: TTabSheet;
    FTabView: TTabSheet;
    // Directory tab controls
    FDriveCombo: TComboBox;
    FBtnVisualize: TSpeedButton;
    FMruCombo: TComboBox;
    FShellTree: TShellTreeView;
    // Tree tabs
    FFuncTree: TTreeView;
    FModuleTree: TTreeView;
    FViewTree: TTreeView;
    // Lower panel memos
    FScanLogMemo: TMemo;
    FDocsMemo: TMemo;
    FScanEventToken: string;
    procedure HandleScanEvent(const AEvent: TDeepShellEvent);
    procedure PopulateTreeFromSpec(ATree: TTreeView; ANodes: TList<TSpecNode>);
    procedure PopulateDocsPanel;
    /// <summary>Tree node click: render node-detail.html and open it in the
    ///  main view (the tree pages were dead before — clicking did nothing).</summary>
    procedure DoSpecTreeChange(Sender: TObject; Node: TTreeNode);
  private
    procedure BuildLeftPanelUI;
    procedure PopulateMruCombo;
    procedure DoDriveChange(Sender: TObject);
    procedure DoShellTreeChange(Sender: TObject; Node: TTreeNode);
    procedure DoBtnVisualizeClick(Sender: TObject);
    procedure DoMruSelect(Sender: TObject);
  protected
    procedure InitializeShell; override;
    procedure RegisterServices; override;
    procedure RegisterCommands; override;
    procedure RegisterProviders; override;
    procedure AfterShellShown; override;
    procedure ShutdownShell; override;
  public
    property Controller: TDeepSpecController read FController;
    function LLMInstance: TObject;
  end;

var
  DeepSpecMainForm: TDeepSpecMainForm;

implementation

uses
  System.IOUtils,
  Winapi.Windows,
  DeepSpec.Commands,
  DeepSpec.Providers,
  DeepSpec.Localization,
  DeepSpec.DeepBaseServices,
  DeepSpec.SettingsProvider,
  DeepBase.LLM,
  DeepBase.Manager,
  DeepBase.VCL.DeepShell.Localization,
  DeepBase.VCL.DeepShell.ToolWindow,
  DeepBase.AutoFix.ErrorRecorder,
  DeepBase.AutoFix.ScenarioRunner,
  DeepBase.AutoFix.HealthSignal;

{ TDeepSpecMainForm }

procedure TDeepSpecMainForm.InitializeShell;

  procedure CleanupCreatedServices;
  begin
    FreeAndNil(FProjectService);
    FreeAndNil(FScanService);
    FreeAndNil(FSpecStore);
    FreeAndNil(FRender);
    FreeAndNil(FTreeBuilder);
    FreeAndNil(FPrompts);
    FreeAndNil(FDecisions);
    FreeAndNil(FSettings);
    FreeAndNil(FLLMService);
    FreeAndNil(FLLMOwned);
  end;

begin
  inherited;
  Caption := 'DeepSpec';

  FProjectService := nil;
  FScanService := nil;
  FSpecStore := nil;
  FRender := nil;
  FTreeBuilder := nil;
  FPrompts := nil;
  FDecisions := nil;
  FSettings := nil;
  FLLMService := nil;
  FLLMOwned := nil;

  try
    FProjectService := TDeepSpecProjectService.Create;
    FScanService := TDeepSpecScanService.Create;
    FSpecStore := TDeepSpecStoreService.Create;
    FRender := TDeepSpecRenderService.Create;
    FTreeBuilder := TDeepSpecTreeBuilder.Create;
    FPrompts := TDeepSpecPromptService.Create;
    FDecisions := TDeepSpecDecisionsService.Create;
    FSettings := TDeepSpecSettingsService.Create;

    try
      var LDeepBaseLLM := TDeepBaseLLM.Create(nil);
      FLLMOwned := LDeepBaseLLM;
      FLLMService := TDeepSpecLLMService.Create(LDeepBaseLLM, True);
    except
      FLLMService := TDeepSpecLLMService.Create(nil, False);
      FLLMOwned := nil;
    end;
  except
    CleanupCreatedServices;
    raise;
  end;
end;

procedure TDeepSpecMainForm.RegisterServices;
begin
  inherited;

  // DeepBase 深度集成：用 DB1(ConfigDB) 持久化实现替换 DeepShell 默认的
  // 内存态 Recent / Settings / Layout 服务（MRU 下拉、窗口位置、布局在
  // 重启后保留）。DeepShell 的 ResolveServicesFromRegistry 会在本方法
  // 之后自动替换 FRecent/FSettings/FLayout。
  Services.RegisterService(CAP_SHELL_RECENT, TDeepSpecDbRecentService.Create);
  Services.RegisterService(CAP_SHELL_SETTINGS, TDeepSpecDbSettingsStore.Create);
  Services.RegisterService(CAP_SHELL_LAYOUT, TDeepSpecDbLayoutService.Create);

  // Detect the Windows UI language at startup and auto-switch the shell
  // localization service to it (DeepSpec + DeepShell zh-CN/zh-TW tables).
  var LLocSvc := Localization as TShellDefaultLocalizationService;
  if LLocSvc <> nil then
    DeepSpecApplyLocale(LLocSvc);

  // DeepBase.Logger 落盘关键生命周期消息（深度集成：状态栏之外有持久日志）。
  try
    var LLang := DeepSpecDetectLocale;
    if DeepBase.Manager.DeepBase <> nil then
      DeepBase.Manager.DeepBase.Logger.Info(
        'DeepSpec startup, locale=' + LLang, 'DeepSpec');
  except
    // Logger 不可用不阻塞启动
  end;

  Services.RegisterService('deepspec.project', FProjectService);
  Services.RegisterService('deepspec.scan', FScanService);
  Services.RegisterService('deepspec.specstore', FSpecStore);
  Services.RegisterService('deepspec.render', FRender);
  Services.RegisterService('deepspec.treebuilder', FTreeBuilder);
  Services.RegisterService('deepspec.prompts', FPrompts);
  Services.RegisterService('deepspec.decisions', FDecisions);
  Services.RegisterService('deepspec.llm', FLLMService);
  Services.RegisterService('deepspec.settings', FSettings);

  FController := TDeepSpecController.Create(
    FProjectService, FScanService, FSpecStore, FRender, FTreeBuilder,
    FPrompts, FDecisions, FLLMService, FSettings,
    Status, Context, EventBus);
end;

procedure TDeepSpecMainForm.RegisterCommands;
begin
  inherited;
  DeepSpec.Commands.RegisterAllCommands(Commands, Self);
end;

procedure TDeepSpecMainForm.RegisterProviders;
begin
  inherited;
  DeepSpec.Providers.RegisterAllProviders(Self, FProjectService,
    FScanService, FTreeBuilder, FController);

  // DeepBase 61 号文档 §7: 下游业务设置页（扫描配置 + LLM 配置）挂进
  // DeepShell 设置对话框。
  RegisterSettingsPageProvider(TDeepSpecSettingsProvider.Create(
    TDeepBaseLLM(FLLMOwned)));
end;

procedure TDeepSpecMainForm.AfterShellShown;
var
  LMainLeft, LMainTop, LMainWidth, LMainHeight: Integer;
begin
  inherited;

  // --- Main form: reduce default size by 1/3 ---
  LMainWidth := MulDiv(Screen.Width, 1, 2);  // half screen width
  LMainHeight := MulDiv(Screen.Height, 2, 3); // 2/3 screen height
  LMainLeft := (Screen.Width - LMainWidth) div 2;
  LMainTop := (Screen.Height - LMainHeight) div 2;
  SetBounds(LMainLeft, LMainTop, LMainWidth, LMainHeight);

  // --- Resize tool windows to 2/3 of default, dock to main form edges ---
  // Set position BEFORE showing to avoid flicker
  if StructureWindow <> nil then
  begin
    StructureWindow.Width := MulDiv(StructureWindow.Width, 2, 3);
    StructureWindow.Height := MulDiv(LMainHeight, 2, 3);
    StructureWindow.Left := LMainLeft - StructureWindow.Width;
    StructureWindow.Top := LMainTop;
  end;

  if InspectorWindow <> nil then
  begin
    InspectorWindow.Width := MulDiv(InspectorWindow.Width, 2, 3);
    InspectorWindow.Height := MulDiv(LMainHeight, 2, 3);
    InspectorWindow.Left := LMainLeft + LMainWidth;
    InspectorWindow.Top := LMainTop;
  end;

  // --- Build left panel PageControl UI ---
  BuildLeftPanelUI;

  // Now show (after all layout is done)
  if StructureWindow <> nil then
    StructureWindow.Show;
  if InspectorWindow <> nil then
    InspectorWindow.Show;

  // --- AutoFix ---
  TAutoFixHealthSignal.Emit;
  if TAutoFixErrorRecorder.Active then
  begin
    // Crash-recovery scenarios. The project to re-open comes from the
    // DEEPSPEC_AUTOFIX_PROJECT env var (no machine-specific path in code);
    // 'scan' refreshes the already-open project.
    var LAutoFixProject := GetEnvironmentVariable('DEEPSPEC_AUTOFIX_PROJECT');
    if LAutoFixProject <> '' then
      TAutoFixScenarioRunner.RegisterScenario('open-project', procedure
      begin
        FController.OpenAndScan(LAutoFixProject);
      end);
    TAutoFixScenarioRunner.RegisterScenario('scan', procedure
    begin
      FController.RunScan;
    end);
    TAutoFixScenarioRunner.Run;
  end
  else
    Status.Info('DeepSpec', ShellText('deepspec.status.ready',
      'DeepSpec ready. Open a project folder to begin.'));

  // --- 恢复上次会话（DeepBase 59 号文档 §7）：Settings 开关 → Recent
  // 上次项目 → 校验路径存在 → OpenAndScan。任何失败不阻塞启动（§8）。---
  try
    var LRestore := True;
    if SettingsStore <> nil then
      LRestore := SettingsStore.ReadBool('deepspec.session.restore', True);
    if LRestore and (Recent <> nil) and (not FController.IsProjectOpen) then
    begin
      var LItems := Recent.GetRecentProjects;
      for var LItem in LItems do
        if (not LItem.Invalid) and TDirectory.Exists(LItem.Path) then
        begin
          Status.Info('DeepSpec', 'Restoring last session: ' + LItem.Path);
          FController.OpenAndScan(LItem.Path);
          PopulateMruCombo;
          Break;
        end;
    end;
  except
    on E: Exception do
      Status.LogError('DeepSpec', 'Session restore failed: ' + E.Message,
        E.ClassName);
  end;
end;

procedure TDeepSpecMainForm.BuildLeftPanelUI;
begin
  if StructureWindow = nil then Exit;

  // Create PageControl in the Upper panel of StructureWindow
  FLeftPages := TPageControl.Create(StructureWindow);
  FLeftPages.Parent := StructureWindow.Upper;
  FLeftPages.Align := alClient;

  // Tab 1: Drives + Directory
  FTabDirs := TTabSheet.Create(FLeftPages);
  FTabDirs.PageControl := FLeftPages;
  FTabDirs.Caption := ShellText('deepspec.tab.dirs', 'Directory');

  // Top bar: Drive combo + Visualize button
  var LTopBar := TPanel.Create(FTabDirs);
  LTopBar.Parent := FTabDirs;
  LTopBar.Align := alTop;
  LTopBar.Height := 28;
  LTopBar.BevelOuter := bvNone;

  FDriveCombo := TComboBox.Create(LTopBar);
  FDriveCombo.Parent := LTopBar;
  FDriveCombo.Align := alLeft;
  FDriveCombo.Width := 60;
  FDriveCombo.Style := csDropDownList;
  FDriveCombo.OnChange := DoDriveChange;

  FBtnVisualize := TSpeedButton.Create(LTopBar);
  FBtnVisualize.Parent := LTopBar;
  FBtnVisualize.Align := alRight;
  FBtnVisualize.Width := 70;
  FBtnVisualize.Caption := ShellText('deepspec.btn.visualize', 'Visualize');
  FBtnVisualize.OnClick := DoBtnVisualizeClick;

  // MRU combo below top bar
  FMruCombo := TComboBox.Create(FTabDirs);
  FMruCombo.Parent := FTabDirs;
  FMruCombo.Align := alTop;
  FMruCombo.Style := csDropDownList;
  FMruCombo.TextHint := ShellText('deepspec.mru.hint', 'Recent projects...');
  FMruCombo.OnChange := DoMruSelect;

  // Shell tree (native VCL - full file system browsing)
  FShellTree := TShellTreeView.Create(FTabDirs);
  FShellTree.Parent := FTabDirs;
  FShellTree.Align := alClient;
  FShellTree.OnChange := DoShellTreeChange;
  // Don't set Root here - let it default to Desktop/My Computer
  // User selects drive from combo to navigate

  // Populate drives
  var LDrives := TDirectory.GetLogicalDrives;
  for var LD in LDrives do
    FDriveCombo.Items.Add(LD);
  var LIdx := FDriveCombo.Items.IndexOf('C:\');
  if LIdx >= 0 then FDriveCombo.ItemIndex := LIdx else FDriveCombo.ItemIndex := 0;

  // Tab 2: Function Tree
  FTabFunc := TTabSheet.Create(FLeftPages);
  FTabFunc.PageControl := FLeftPages;
  FTabFunc.Caption := ShellText('deepspec.tab.func', 'Functions');
  FFuncTree := TTreeView.Create(FTabFunc);
  FFuncTree.Parent := FTabFunc;
  FFuncTree.Align := alClient;
  FFuncTree.ReadOnly := True;

  // Tab 3: Module Tree
  FTabModule := TTabSheet.Create(FLeftPages);
  FTabModule.PageControl := FLeftPages;
  FTabModule.Caption := ShellText('deepspec.tab.module', 'Modules');
  FModuleTree := TTreeView.Create(FTabModule);
  FModuleTree.Parent := FTabModule;
  FModuleTree.Align := alClient;
  FModuleTree.ReadOnly := True;

  // Tab 4: View Tree (UI Tree)
  FTabView := TTabSheet.Create(FLeftPages);
  FTabView.PageControl := FLeftPages;
  FTabView.Caption := ShellText('deepspec.tab.view', 'Views');
  FViewTree := TTreeView.Create(FTabView);
  FViewTree.Parent := FTabView;
  FViewTree.Align := alClient;
  FViewTree.ReadOnly := True;

  // MRU
  PopulateMruCombo;

  // --- Left Lower panel: scan log ---
  if StructureWindow.Lower <> nil then
  begin
    FScanLogMemo := TMemo.Create(StructureWindow);
    FScanLogMemo.Parent := StructureWindow.Lower;
    FScanLogMemo.Align := alClient;
    FScanLogMemo.ReadOnly := True;
    FScanLogMemo.ScrollBars := ssVertical;
    FScanLogMemo.Font.Size := 8;
    FScanLogMemo.Color := clBtnFace;
    FScanLogMemo.Lines.Add('(scan log)');
  end;

  // --- Right Lower panel: docs list ---
  if InspectorWindow.Lower <> nil then
  begin
    FDocsMemo := TMemo.Create(InspectorWindow);
    FDocsMemo.Parent := InspectorWindow.Lower;
    FDocsMemo.Align := alClient;
    FDocsMemo.ReadOnly := True;
    FDocsMemo.ScrollBars := ssVertical;
    FDocsMemo.Font.Size := 8;
    FDocsMemo.Color := clBtnFace;
    FDocsMemo.Lines.Add('(docs summary)');
  end;

  // Subscribe to scan-complete events
  if EventBus <> nil then
    FScanEventToken := EventBus.Subscribe(sekProjectOpened,
      HandleScanEvent);
end;

procedure TDeepSpecMainForm.PopulateMruCombo;
begin
  FMruCombo.Items.Clear;
  if Recent = nil then Exit;
  var LItems := Recent.GetRecentProjects;
  for var LItem in LItems do
    FMruCombo.Items.Add(LItem.DisplayName);
  if FMruCombo.Items.Count > 0 then
    FMruCombo.ItemIndex := 0;
end;

procedure TDeepSpecMainForm.DoMruSelect(Sender: TObject);
begin
  if (FMruCombo.ItemIndex < 0) or (Recent = nil) then Exit;
  var LItems := Recent.GetRecentProjects;
  if FMruCombo.ItemIndex > High(LItems) then Exit;
  var LPath := LItems[FMruCombo.ItemIndex].ItemKey;
  if TDirectory.Exists(LPath) then
  begin
    // Navigate shell tree to the selected path
    try
      FShellTree.Path := LPath;
    except
      // Path may not be navigable in shell tree
    end;
    FController.OpenAndScan(LPath);
    FBtnVisualize.Enabled := False;
    // Note: RebuildStructureTree + tree refresh handled by HandleScanEvent
  end;
end;

procedure TDeepSpecMainForm.DoDriveChange(Sender: TObject);
begin
  if (FDriveCombo.ItemIndex >= 0) and (FShellTree <> nil) then
  begin
    try
      FShellTree.Root := FDriveCombo.Text;
    except
      // Some drives may not be accessible
    end;
  end;
end;

procedure TDeepSpecMainForm.DoShellTreeChange(Sender: TObject; Node: TTreeNode);
begin
  if (Node = nil) or (FShellTree = nil) then Exit;
  var LPath := FShellTree.Path;
  // Enable whenever a real folder is selected — re-scanning an existing
  // DeepSpec project is allowed (spec files are snapshotted before
  // overwrite). Previously the button stayed disabled for folders that
  // already had a .deepspec, which read as "clicking does nothing".
  FBtnVisualize.Enabled := TDirectory.Exists(LPath);
end;

procedure TDeepSpecMainForm.DoBtnVisualizeClick(Sender: TObject);
begin
  if FShellTree = nil then Exit;
  if FShellTree.Selected = nil then Exit;

  var LPath := FShellTree.Path;
  if (LPath = '') or (not TDirectory.Exists(LPath)) then
  begin
    Status.Warning('DeepSpec', 'Please select a folder in the directory tree.');
    Exit;
  end;

  FController.OpenAndScan(LPath);

  if Recent <> nil then
  begin
    Recent.AddRecentProject(LPath, LPath,
      ExtractFileName(ExcludeTrailingPathDelimiter(LPath)), '');
    PopulateMruCombo;
  end;

  FBtnVisualize.Enabled := False;
  // Note: RebuildStructureTree + tree refresh handled by HandleScanEvent
end;

procedure TDeepSpecMainForm.ShutdownShell;
begin
  if (FScanEventToken <> '') and (EventBus <> nil) then
  begin
    EventBus.Unsubscribe(FScanEventToken);
    FScanEventToken := '';
  end;
  FreeAndNil(FController);
  inherited;
end;

function TDeepSpecMainForm.LLMInstance: TObject;
begin
  Result := FLLMOwned;
end;

procedure TDeepSpecMainForm.HandleScanEvent(const AEvent: TDeepShellEvent);
begin
  // Scan completed — refresh all panels
  RebuildStructureTree;
  PopulateTreeFromSpec(FFuncTree, FTreeBuilder.FunctionNodes);
  PopulateTreeFromSpec(FModuleTree, FTreeBuilder.ModuleNodes);
  PopulateTreeFromSpec(FViewTree, FTreeBuilder.ViewNodes);
  PopulateDocsPanel;

  // Live scan log (was a dead "(scan log)" placeholder — never updated).
  if FScanLogMemo <> nil then
  begin
    FScanLogMemo.Lines.BeginUpdate;
    try
      FScanLogMemo.Lines.Clear;
      if FController.IsProjectOpen then
      begin
        FScanLogMemo.Lines.Add('Project: ' + FProjectService.ProjectPath);
        FScanLogMemo.Lines.Add(Format(
          'Scan: %d files (docs %d, code %d, ui %d, config %d, ai_rules %d)',
          [FScanService.TotalFiles,
           FScanService.CategoryCount(fcDocuments),
           FScanService.CategoryCount(fcCode),
           FScanService.CategoryCount(fcUI),
           FScanService.CategoryCount(fcConfig),
           FScanService.CategoryCount(fcAiRules)]));
        FScanLogMemo.Lines.Add(Format(
          'Trees: function %d / module %d / view %d / data %d',
          [FTreeBuilder.FunctionNodes.Count, FTreeBuilder.ModuleNodes.Count,
           FTreeBuilder.ViewNodes.Count, FTreeBuilder.DataNodes.Count]));
        FScanLogMemo.Lines.Add('Type: ' + FProjectService.ProjectType);
      end
      else
        FScanLogMemo.Lines.Add('(no project)');
    finally
      FScanLogMemo.Lines.EndUpdate;
    end;
  end;

  // Re-enable Visualize so the project can be re-scanned (it was
  // disabled forever after the first scan before).
  FBtnVisualize.Enabled := True;

  // 扫描完成写 DeepBase.Logger（持久日志）。
  try
    if DeepBase.Manager.DeepBase <> nil then
      DeepBase.Manager.DeepBase.Logger.Info(Format(
        'Scan complete: %d files | func %d / mod %d / view %d / data %d | %s',
        [FScanService.TotalFiles, FTreeBuilder.FunctionNodes.Count,
         FTreeBuilder.ModuleNodes.Count, FTreeBuilder.ViewNodes.Count,
         FTreeBuilder.DataNodes.Count, FProjectService.ProjectType]),
        'DeepSpec.Scan');
  except
  end;

  // Auto-open HTML index in main view
  if FController.IsProjectOpen then
  begin
    var LHtmlPath := TPath.Combine(
      FProjectService.DeepSpecPath, 'html\index.html');
    if TFile.Exists(LHtmlPath) then
    begin
      var LRef := TShellObjectRef.Make('index-html', 'html', '',
        LHtmlPath);
      OpenView(LRef);
    end;
  end;
end;

procedure TDeepSpecMainForm.DoSpecTreeChange(Sender: TObject; Node: TTreeNode);
var
  LList: TList<TSpecNode>;
  LIdx: Integer;
begin
  if (Node = nil) or (FProjectService = nil) or (not FProjectService.IsOpen) then
    Exit;
  LList := nil;
  if Sender = FFuncTree then
    LList := FTreeBuilder.FunctionNodes
  else if Sender = FModuleTree then
    LList := FTreeBuilder.ModuleNodes
  else if Sender = FViewTree then
    LList := FTreeBuilder.ViewNodes;
  if LList = nil then Exit;

  LIdx := Integer(Node.Data);
  if (LIdx < 0) or (LIdx >= LList.Count) then Exit;

  try
    var LNode := LList[LIdx];
    FRender.RenderNodeDetail(LNode);
    var LRef := TShellObjectRef.Make('node-detail', 'html', LNode.Title,
      TPath.Combine(FProjectService.DeepSpecPath, 'html\node-detail.html'));
    OpenView(LRef);
  except
    on E: Exception do
      Status.LogError('DeepSpec', 'Node detail failed: ' + E.Message,
        E.ClassName);
  end;
end;

procedure TDeepSpecMainForm.PopulateTreeFromSpec(ATree: TTreeView;
  ANodes: TList<TSpecNode>);

  procedure AddNodes(const AParentId: string; AParentNode: TTreeNode);
  var
    LNode: TTreeNode;
    I: Integer;
  begin
    for I := 0 to ANodes.Count - 1 do
    begin
      if ANodes[I].ParentId = AParentId then
      begin
        LNode := ATree.Items.AddChild(AParentNode, ANodes[I].Title);
        LNode.Data := Pointer(I);
        AddNodes(ANodes[I].Id, LNode);
      end;
    end;
  end;

begin
  if (ATree = nil) or (ANodes = nil) then Exit;
  ATree.OnChange := DoSpecTreeChange;
  ATree.Items.BeginUpdate;
  try
    ATree.Items.Clear;
    AddNodes('', nil);
    ATree.FullExpand;
  finally
    ATree.Items.EndUpdate;
  end;
end;

procedure TDeepSpecMainForm.PopulateDocsPanel;
var
  LDocs: TArray<string>;
begin
  if FDocsMemo = nil then Exit;
  FDocsMemo.Lines.BeginUpdate;
  try
    FDocsMemo.Lines.Clear;
    if FController = nil then Exit;
    LDocs := FController.DocsFiles;
    if Length(LDocs) = 0 then
    begin
      FDocsMemo.Lines.Add('(no docs found)');
      Exit;
    end;
    FDocsMemo.Lines.Add(Format('Documents (%d):', [Length(LDocs)]));
    for var LDoc in LDocs do
      FDocsMemo.Lines.Add('  ' + ExtractFileName(LDoc));
  finally
    FDocsMemo.Lines.EndUpdate;
  end;
end;

end.
