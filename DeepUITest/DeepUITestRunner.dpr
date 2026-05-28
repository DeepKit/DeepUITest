{ ============================================================================
  DeepUITestRunner

  Console runner entry point. Reads a TestCase from DB2, executes it,
  evaluates lamp, and writes results.

  Usage:
    DeepUITestRunner.exe
      --db=<path>               DB2 SQLite file (required)
      --project=<id>            AppProjectId (required)
      --case=<id>               TestCaseId (required)
      --init-demo               Initialise DB schema + insert a demo TestCase

  See: DeepUITest.003 MVP路线图
       DeepUITest.011 DeepLaunch样板测试链
  ============================================================================ }

program DeepUITestRunner;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  DeepUITest.Models,
  DeepUITest.DB,
  DeepUITest.Runner.Core,
  DeepUITest.Lamp;

var
  LDBPath: string;
  LProjectId: string;
  LCaseId: string;
  LInitDemo: Boolean;

procedure ParseArgs;
var
  I: Integer;
  LParam: string;
begin
  for I := 1 to ParamCount do
  begin
    LParam := ParamStr(I);
    if LParam.StartsWith('--db=') then
      LDBPath := LParam.Substring(Length('--db='))
    else if LParam.StartsWith('--project=') then
      LProjectId := LParam.Substring(Length('--project='))
    else if LParam.StartsWith('--case=') then
      LCaseId := LParam.Substring(Length('--case='))
    else if LParam = '--init-demo' then
      LInitDemo := True;
  end;
end;

procedure InitDemoData;
var
  LProject: TAppProject;
  LVersion: TAppVersion;
  LCase: TTestCase;
  LStep: TJourneyStep;
begin
  WriteLn('Initializing DB2 schema...');
  TUITestDB.InitSchema;

  // ---- AppProject ----
  LProject := TAppProject.Create;
  LProject.AppProjectId := 'deeplaunch';
  LProject.Name := 'DeepLaunch';
  LProject.DisplayName := 'DeepLaunch';
  LProject.AppKind := 'VCL';
  LProject.TechStack := 'Delphi';
  LProject.RootPath := 'D:\_Progs\02Business\DeepLaunch';
  LProject.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  TUITestDB.SaveAppProject(LProject);

  // ---- AppVersion ----
  LVersion := TAppVersion.Create;
  LVersion.AppVersionId := 'deeplaunch-v1';
  LVersion.AppProjectId := 'deeplaunch';
  LVersion.VersionName := 'v1';
  LVersion.VersionNo := 1;
  LVersion.BuildNo := 1;
  LVersion.ExecutablePath := 'D:\_Progs\02Business\DeepLaunch\bin\DeepLaunch.exe';
  LVersion.SourceRoot := 'D:\_Progs\02Business\DeepLaunch\src';
  LVersion.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);

  // ---- TestCase: hotkey-launch ----
  LCase := TTestCase.Create;
  LCase.TestCaseId := 'deeplaunch-hotkey-launch';
  LCase.AppVersionId := 'deeplaunch-v1';
  LCase.Title := 'F1+X 遥控启动链';
  LCase.OutputKey := 'hotkey.launch.configured';
  LCase.RiskLevel := 0;
  LCase.Priority := 1;
  LCase.Status := 'active';
  LCase.CreatedBy := 'init-demo';

  // Step 0: PrepareTargetStateGate
  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DL-S0';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 0;
  LStep.GateKey := 'PrepareTargetStateGate';
  LStep.StepName := 'Kill any previous Probe';
  LStep.ActionType := atWriteLog;
  LStep.InputValue := 'PrepareTargetStateGate: starting run';
  LStep.TimeoutMs := 1000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  // Step 1: DeepLaunchReadyGate
  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DL-S1';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 1;
  LStep.GateKey := 'DeepLaunchReadyGate';
  LStep.StepName := 'Ensure DeepLaunch is running';
  LStep.ActionType := atEnsureProcess;
  LStep.TargetRef := 'DeepLaunch.exe';
  LStep.InputValue := '';
  LStep.ExpectedState := 'D:\_Progs\02Business\DeepLaunch\bin\DeepLaunch.exe';
  LStep.TimeoutMs := 10000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  // Step 2: MainWindowGate
  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DL-S2';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 2;
  LStep.GateKey := 'MainWindowGate';
  LStep.StepName := 'Send F1 and wait for main window';
  LStep.ActionType := atSendHotkey;
  LStep.InputValue := 'F1';
  LStep.TimeoutMs := 5000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  // Step 3: GridReadyGate
  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DL-S3';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 3;
  LStep.GateKey := 'GridReadyGate';
  LStep.StepName := 'Wait for DeepLaunch main window';
  LStep.ActionType := atWaitWindow;
  LStep.TargetRef := 'DeepLaunch';
  LStep.TimeoutMs := 10000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  // Step 4: HotkeyActionGate
  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DL-S4';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 4;
  LStep.GateKey := 'HotkeyActionGate';
  LStep.StepName := 'Send X key to launch target';
  LStep.ActionType := atSendKey;
  LStep.InputValue := 'X';
  LStep.TimeoutMs := 5000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  // Step 5: LaunchVerifyGate
  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DL-S5';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 5;
  LStep.GateKey := 'LaunchVerifyGate';
  LStep.StepName := 'Verify Probe process started';
  LStep.ActionType := atVerifyProcess;
  LStep.TargetRef := 'DeepUITestProbe.exe';
  LStep.TimeoutMs := 15000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  // Step 6: TargetIdentityGate
  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DL-S6';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 6;
  LStep.GateKey := 'TargetIdentityGate';
  LStep.StepName := 'Verify Probe window visible';
  LStep.ActionType := atVerifyWindow;
  LStep.TargetRef := 'DeepUITest Probe';
  LStep.TimeoutMs := 10000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  TUITestDB.SaveTestCase(LCase);
  LProject.Free;
  LVersion.Free;
  LCase.Free;

  // ====================================================================
  // DeepCompare
  // ====================================================================
  LProject := TAppProject.Create;
  LProject.AppProjectId := 'deepcompare';
  LProject.Name := 'DeepCompare';
  LProject.DisplayName := 'DeepCompare';
  LProject.AppKind := 'VCL';
  LProject.TechStack := 'Delphi';
  LProject.RootPath := 'D:\_Progs\02Business\DeepCompare';
  LProject.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  TUITestDB.SaveAppProject(LProject);

  LVersion := TAppVersion.Create;
  LVersion.AppVersionId := 'deepcompare-v1';
  LVersion.AppProjectId := 'deepcompare';
  LVersion.VersionName := 'v1';
  LVersion.VersionNo := 1;
  LVersion.BuildNo := 1;
  LVersion.ExecutablePath := 'D:\_Progs\02Business\DeepCompare\delphi\bin\DeepCompare.exe';
  LVersion.SourceRoot := 'D:\_Progs\02Business\DeepCompare\delphi';
  LVersion.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);

  LCase := TTestCase.Create;
  LCase.TestCaseId := 'deepcompare-smoke-test';
  LCase.AppVersionId := 'deepcompare-v1';
  LCase.Title := 'DeepCompare smoke test';
  LCase.OutputKey := 'smoke.window.tabs';
  LCase.RiskLevel := 0;
  LCase.Priority := 1;
  LCase.Status := 'active';
  LCase.CreatedBy := 'init-demo';

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DC-S0';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 0;
  LStep.GateKey := 'PrepareGate';
  LStep.StepName := 'Log start';
  LStep.ActionType := atWriteLog;
  LStep.InputValue := 'DeepCompare smoke test starting';
  LStep.TimeoutMs := 1000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DC-S1';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 1;
  LStep.GateKey := 'ProcessGate';
  LStep.StepName := 'Ensure DeepCompare is running';
  LStep.ActionType := atEnsureProcess;
  LStep.TargetRef := 'DeepCompare.exe';
  LStep.InputValue := '';
  LStep.ExpectedState := 'D:\_Progs\02Business\DeepCompare\delphi\bin\DeepCompare.exe';
  LStep.TimeoutMs := 15000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DC-S2';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 2;
  LStep.GateKey := 'MainWindowGate';
  LStep.StepName := 'Wait for main window';
  LStep.ActionType := atWaitWindow;
  LStep.TargetRef := 'DeepCompare - AI Test Tool';
  LStep.TimeoutMs := 10000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DC-S3';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 3;
  LStep.GateKey := 'TabSwitchGate';
  LStep.StepName := 'Switch to Input tab';
  LStep.ActionType := atSendHotkey;
  LStep.InputValue := 'Ctrl+1';
  LStep.TimeoutMs := 3000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DC-S4';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 4;
  LStep.GateKey := 'ResultTabGate';
  LStep.StepName := 'Switch to Result tab';
  LStep.ActionType := atSendHotkey;
  LStep.InputValue := 'Ctrl+2';
  LStep.TimeoutMs := 3000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DC-S5';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 5;
  LStep.GateKey := 'LogTabGate';
  LStep.StepName := 'Switch to Log tab';
  LStep.ActionType := atSendHotkey;
  LStep.InputValue := 'Ctrl+3';
  LStep.TimeoutMs := 3000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DC-S6';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 6;
  LStep.GateKey := 'DismissGate';
  LStep.StepName := 'Send Escape';
  LStep.ActionType := atSendHotkey;
  LStep.InputValue := 'Escape';
  LStep.TimeoutMs := 3000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  TUITestDB.SaveTestCase(LCase);
  LProject.Free;
  LVersion.Free;
  LCase.Free;

  // ====================================================================
  // DeepSVG
  // ====================================================================
  LProject := TAppProject.Create;
  LProject.AppProjectId := 'deepsvg';
  LProject.Name := 'DeepSVG';
  LProject.DisplayName := 'DeepSVG';
  LProject.AppKind := 'VCL';
  LProject.TechStack := 'Delphi';
  LProject.RootPath := 'D:\_Progs\02Business\DeepSVG';
  LProject.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  TUITestDB.SaveAppProject(LProject);

  LVersion := TAppVersion.Create;
  LVersion.AppVersionId := 'deepsvg-v1';
  LVersion.AppProjectId := 'deepsvg';
  LVersion.VersionName := 'v1';
  LVersion.VersionNo := 1;
  LVersion.BuildNo := 1;
  LVersion.ExecutablePath := 'D:\_Progs\02Business\DeepSVG\bin\DeepSVG.exe';
  LVersion.SourceRoot := 'D:\_Progs\02Business\DeepSVG';
  LVersion.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);

  LCase := TTestCase.Create;
  LCase.TestCaseId := 'deepsvg-smoke-test';
  LCase.AppVersionId := 'deepsvg-v1';
  LCase.Title := 'DeepSVG smoke test';
  LCase.OutputKey := 'smoke.window.shortcuts';
  LCase.RiskLevel := 0;
  LCase.Priority := 1;
  LCase.Status := 'active';
  LCase.CreatedBy := 'init-demo';

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DS-S0';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 0;
  LStep.GateKey := 'PrepareGate';
  LStep.StepName := 'Log start';
  LStep.ActionType := atWriteLog;
  LStep.InputValue := 'DeepSVG smoke test starting';
  LStep.TimeoutMs := 1000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DS-S1';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 1;
  LStep.GateKey := 'ProcessGate';
  LStep.StepName := 'Ensure DeepSVG is running';
  LStep.ActionType := atEnsureProcess;
  LStep.TargetRef := 'DeepSVG.exe';
  LStep.InputValue := '';
  LStep.ExpectedState := 'D:\_Progs\02Business\DeepSVG\bin\DeepSVG.exe';
  LStep.TimeoutMs := 15000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DS-S2';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 2;
  LStep.GateKey := 'MainWindowGate';
  LStep.StepName := 'Wait for main window';
  LStep.ActionType := atWaitWindow;
  LStep.TargetRef := 'SVG';
  LStep.TimeoutMs := 15000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DS-S3';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 3;
  LStep.GateKey := 'RefreshPreviewGate';
  LStep.StepName := 'Refresh preview';
  LStep.ActionType := atSendHotkey;
  LStep.InputValue := 'F5';
  LStep.TimeoutMs := 5000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DS-S4';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 4;
  LStep.GateKey := 'HelpOverlayGate';
  LStep.StepName := 'Show help overlay';
  LStep.ActionType := atSendHotkey;
  LStep.InputValue := 'F1';
  LStep.TimeoutMs := 3000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DS-S5';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 5;
  LStep.GateKey := 'DismissHelpGate';
  LStep.StepName := 'Dismiss help';
  LStep.ActionType := atSendHotkey;
  LStep.InputValue := 'Escape';
  LStep.TimeoutMs := 3000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  TUITestDB.SaveTestCase(LCase);
  LProject.Free;
  LVersion.Free;
  LCase.Free;

  // ====================================================================
  // DeepClip
  // ====================================================================
  LProject := TAppProject.Create;
  LProject.AppProjectId := 'deepclip';
  LProject.Name := 'DeepClip';
  LProject.DisplayName := 'DeepClip';
  LProject.AppKind := 'VCL';
  LProject.TechStack := 'Delphi';
  LProject.RootPath := 'D:\_Progs\02Business\DeepClip';
  LProject.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  TUITestDB.SaveAppProject(LProject);

  LVersion := TAppVersion.Create;
  LVersion.AppVersionId := 'deepclip-v1';
  LVersion.AppProjectId := 'deepclip';
  LVersion.VersionName := 'v1';
  LVersion.VersionNo := 1;
  LVersion.BuildNo := 1;
  LVersion.ExecutablePath := 'D:\_Progs\02Business\DeepClip\bin\DeepClip.exe';
  LVersion.SourceRoot := 'D:\_Progs\02Business\DeepClip\src';
  LVersion.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);

  LCase := TTestCase.Create;
  LCase.TestCaseId := 'deepclip-smoke-test';
  LCase.AppVersionId := 'deepclip-v1';
  LCase.Title := 'DeepClip smoke test';
  LCase.OutputKey := 'smoke.window.hotkey';
  LCase.RiskLevel := 0;
  LCase.Priority := 1;
  LCase.Status := 'active';
  LCase.CreatedBy := 'init-demo';

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DCl-S0';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 0;
  LStep.GateKey := 'PrepareGate';
  LStep.StepName := 'Log start';
  LStep.ActionType := atWriteLog;
  LStep.InputValue := 'DeepClip smoke test starting';
  LStep.TimeoutMs := 1000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DCl-S1';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 1;
  LStep.GateKey := 'ProcessGate';
  LStep.StepName := 'Ensure DeepClip is running';
  LStep.ActionType := atEnsureProcess;
  LStep.TargetRef := 'DeepClip.exe';
  LStep.InputValue := '';
  LStep.ExpectedState := 'D:\_Progs\02Business\DeepClip\bin\DeepClip.exe';
  LStep.TimeoutMs := 10000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DCl-S2';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 2;
  LStep.GateKey := 'MainWindowGate';
  LStep.StepName := 'Wait for main window';
  LStep.ActionType := atWaitWindow;
  LStep.TargetRef := 'DeepClip';
  LStep.TimeoutMs := 10000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DCl-S3';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 3;
  LStep.GateKey := 'QuickPasteGate';
  LStep.StepName := 'Trigger quick paste hotkey';
  LStep.ActionType := atSendHotkey;
  LStep.InputValue := 'F7';
  LStep.TimeoutMs := 5000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DCl-S4';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 4;
  LStep.GateKey := 'DismissPasteGate';
  LStep.StepName := 'Dismiss paste dialog';
  LStep.ActionType := atSendHotkey;
  LStep.InputValue := 'Escape';
  LStep.TimeoutMs := 3000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  TUITestDB.SaveTestCase(LCase);
  LProject.Free;
  LVersion.Free;
  LCase.Free;

  // ====================================================================
  // DeepMoveC
  // ====================================================================
  LProject := TAppProject.Create;
  LProject.AppProjectId := 'deepmovec';
  LProject.Name := 'DeepMoveC';
  LProject.DisplayName := 'DeepMoveC';
  LProject.AppKind := 'VCL';
  LProject.TechStack := 'Delphi';
  LProject.RootPath := 'D:\_Progs\02Business\DeepMoveC';
  LProject.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  TUITestDB.SaveAppProject(LProject);

  LVersion := TAppVersion.Create;
  LVersion.AppVersionId := 'deepmovec-v1';
  LVersion.AppProjectId := 'deepmovec';
  LVersion.VersionName := 'v1';
  LVersion.VersionNo := 1;
  LVersion.BuildNo := 1;
  LVersion.ExecutablePath := 'D:\_Progs\02Business\DeepMoveC\bin\C盘超级瘦身.exe';
  LVersion.SourceRoot := 'D:\_Progs\02Business\DeepMoveC';
  LVersion.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);

  LCase := TTestCase.Create;
  LCase.TestCaseId := 'deepmovec-smoke-test';
  LCase.AppVersionId := 'deepmovec-v1';
  LCase.Title := 'DeepMoveC smoke test';
  LCase.OutputKey := 'smoke.window';
  LCase.RiskLevel := 0;
  LCase.Priority := 1;
  LCase.Status := 'active';
  LCase.CreatedBy := 'init-demo';

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DM-S0';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 0;
  LStep.GateKey := 'PrepareGate';
  LStep.StepName := 'Log start';
  LStep.ActionType := atWriteLog;
  LStep.InputValue := 'DeepMoveC smoke test starting';
  LStep.TimeoutMs := 1000;
  LStep.OnFailPolicy := 'continue';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DM-S1';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 1;
  LStep.GateKey := 'ProcessGate';
  LStep.StepName := 'Ensure DeepMoveC is running';
  LStep.ActionType := atEnsureProcess;
  LStep.TargetRef := #30424#30246#36523#31070#22120'.exe';
  LStep.InputValue := '';
  LStep.ExpectedState := 'D:\_Progs\02Business\DeepMoveC\bin\C盘超级瘦身.exe';
  LStep.TimeoutMs := 10000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  LStep := TJourneyStep.Create;
  LStep.JourneyStepId := 'DM-S2';
  LStep.TestCaseId := LCase.TestCaseId;
  LStep.StepOrder := 2;
  LStep.GateKey := 'MainWindowGate';
  LStep.StepName := 'Wait for main window';
  LStep.ActionType := atWaitWindow;
  LStep.TargetRef := #30424#30246#36523#31070#22120;
  LStep.TimeoutMs := 10000;
  LStep.OnFailPolicy := 'halt';
  LCase.Steps.Add(LStep);

  TUITestDB.SaveTestCase(LCase);
  LProject.Free;
  LVersion.Free;
  LCase.Free;

  WriteLn('Demo data created:');
  WriteLn('  AppProject:  deeplaunch');
  WriteLn('  AppVersion:  deeplaunch-v1');
  WriteLn('  TestCase:    deeplaunch-hotkey-launch (7 steps)');
  WriteLn('  AppProject:  deepcompare');
  WriteLn('  TestCase:    deepcompare-smoke-test (7 steps)');
  WriteLn('  AppProject:  deepsvg');
  WriteLn('  TestCase:    deepsvg-smoke-test (6 steps)');
  WriteLn('  AppProject:  deepclip');
  WriteLn('  TestCase:    deepclip-smoke-test (5 steps)');
  WriteLn('  AppProject:  deepmovec');
  WriteLn('  TestCase:    deepmovec-smoke-test (3 steps)');
  WriteLn('');
  WriteLn('Run with:');
  WriteLn('  DeepUITestRunner.exe --db=<path> --project=<id> --case=<id>');
end;

begin
  LDBPath := '';
  LProjectId := '';
  LCaseId := '';
  LInitDemo := False;
  ParseArgs;

  if LInitDemo then
  begin
    if LDBPath = '' then
    begin
      WriteLn(ErrOutput, 'ERROR: --db=<path> required with --init-demo');
      Halt(1);
    end;
    if not TUITestDB.Initialize(LDBPath) then
    begin
      WriteLn(ErrOutput, 'ERROR: cannot open database: ', LDBPath);
      Halt(1);
    end;
    try
      InitDemoData;
    finally
      TUITestDB.Finalize;
    end;
    Halt(0);
  end;

  if (LDBPath = '') or (LProjectId = '') or (LCaseId = '') then
  begin
    WriteLn('DeepUITest Runner v0.1');
    WriteLn('');
    WriteLn('Usage:');
    WriteLn('  DeepUITestRunner.exe --db=<path> --project=<id> --case=<id>');
    WriteLn('  DeepUITestRunner.exe --db=<path> --init-demo');
    WriteLn('');
    WriteLn('  --db        DB2 SQLite file path');
    WriteLn('  --project   AppProjectId');
    WriteLn('  --case      TestCaseId');
    WriteLn('  --init-demo Create schema + demo TestCase');
    Halt(0);
  end;

  if not TUITestDB.Initialize(LDBPath) then
  begin
    WriteLn(ErrOutput, 'ERROR: cannot open database: ', LDBPath);
    Halt(1);
  end;

  try
    TUITestDB.InitSchema;

    var LResultId := TUITestRunner.Run(LProjectId, LCaseId);
    if LResultId = '' then
    begin
      WriteLn(ErrOutput, 'ERROR: run failed');
      Halt(1);
    end;

    WriteLn('Run complete: ', LResultId);
  finally
    TUITestDB.Finalize;
  end;
end.