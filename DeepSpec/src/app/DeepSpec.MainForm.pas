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
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
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
  DeepSpec.Services.LLM;

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
  DeepBase.LLM,
  DeepBase.VCL.DeepShell.Localization,
  DeepBase.AutoFix.ErrorRecorder,
  DeepBase.AutoFix.ScenarioRunner,
  DeepBase.AutoFix.HealthSignal;

{ TDeepSpecMainForm }

procedure TDeepSpecMainForm.InitializeShell;
begin
  inherited;
  Caption := 'DeepSpec';

  FProjectService := TDeepSpecProjectService.Create;
  FScanService := TDeepSpecScanService.Create;
  FSpecStore := TDeepSpecStoreService.Create;
  FRender := TDeepSpecRenderService.Create;
  FTreeBuilder := TDeepSpecTreeBuilder.Create;
  FPrompts := TDeepSpecPromptService.Create;
  FDecisions := TDeepSpecDecisionsService.Create;

  try
    var LDeepBaseLLM := TDeepBaseLLM.Create(nil);
    FLLMOwned := LDeepBaseLLM;
    FLLMService := TDeepSpecLLMService.Create(LDeepBaseLLM, True);
  except
    FLLMService := TDeepSpecLLMService.Create(nil, False);
    FLLMOwned := nil;
  end;
end;

procedure TDeepSpecMainForm.RegisterServices;
begin
  inherited;

  // Register Chinese translations via framework localization
  var LLocSvc := Localization as TShellDefaultLocalizationService;
  if LLocSvc <> nil then
  begin
    LLocSvc.RegisterText('zh-CN', 'deepspec.tab.dirs', #$76EE#$5F55);           // 目录
    LLocSvc.RegisterText('zh-CN', 'deepspec.tab.func', #$529F#$80FD#$6811);     // 功能树
    LLocSvc.RegisterText('zh-CN', 'deepspec.tab.module', #$6A21#$5757#$6811);   // 模块树
    LLocSvc.RegisterText('zh-CN', 'deepspec.tab.view', #$754C#$9762#$6811);     // 界面树
    LLocSvc.RegisterText('zh-CN', 'deepspec.btn.visualize', #$53EF#$89C6#$5316);// 可视化
    LLocSvc.RegisterText('zh-CN', 'deepspec.mru.hint', #$6700#$8FD1#$9879#$76EE'...');// 最近项目...
  end;

  Services.RegisterService('deepspec.project', FProjectService);
  Services.RegisterService('deepspec.scan', FScanService);
  Services.RegisterService('deepspec.specstore', FSpecStore);
  Services.RegisterService('deepspec.render', FRender);
  Services.RegisterService('deepspec.treebuilder', FTreeBuilder);
  Services.RegisterService('deepspec.prompts', FPrompts);
  Services.RegisterService('deepspec.decisions', FDecisions);
  Services.RegisterService('deepspec.llm', FLLMService);

  FController := TDeepSpecController.Create(
    FProjectService, FScanService, FSpecStore, FRender, FTreeBuilder,
    FPrompts, FDecisions, FLLMService,
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
  DeepSpec.Providers.RegisterAllProviders(Self, FProjectService);
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
    TAutoFixScenarioRunner.RegisterScenario('open-project', procedure
    begin
      FController.OpenAndScan('D:\_Progs\02Business\DeepSpec');
    end);
    TAutoFixScenarioRunner.RegisterScenario('scan', procedure
    begin
      FController.RunScan;
    end);
    TAutoFixScenarioRunner.Run;
  end
  else
    Status.Info('DeepSpec', 'DeepSpec ready. Open a project folder to begin.');
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
  FDriveCombo.ItemIndex := if LIdx >= 0 then LIdx else 0;

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
    RebuildStructureTree;
    FBtnVisualize.Enabled := False;
    Status.Info('DeepSpec', 'Project opened: ' + LPath);
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
  FBtnVisualize.Enabled := TDirectory.Exists(LPath) and
    not TDirectory.Exists(TPath.Combine(LPath, '.deepspec'));
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

  RebuildStructureTree;
  FBtnVisualize.Enabled := False;
  Status.Info('DeepSpec', 'Project opened: ' + LPath);
end;

procedure TDeepSpecMainForm.ShutdownShell;
begin
  FreeAndNil(FController);
  inherited;
end;

function TDeepSpecMainForm.LLMInstance: TObject;
begin
  Result := FLLMOwned;
end;

end.
