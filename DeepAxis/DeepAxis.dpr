program DeepAxis;

{$APPTYPE GUI}

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.ComCtrls,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Phys.SQLite,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  Winapi.Windows,
  DeepAxis.Core.Base in 'src\core\DeepAxis.Core.Base.pas',
  DeepAxis.Core.DataTypes in 'src\core\DeepAxis.Core.DataTypes.pas',
  DeepAxis.Core.SendModes in 'src\core\DeepAxis.Core.SendModes.pas',
  DeepAxis.Core.Contracts in 'src\core\DeepAxis.Core.Contracts.pas',
  DeepAxis.Core.Config in 'src\core\DeepAxis.Core.Config.pas',
  DeepAxis.Config.DB1 in 'src\config\DeepAxis.Config.DB1.pas',
  DeepAxis.Core.Profile in 'src\core\DeepAxis.Core.Profile.pas',
  DeepAxis.Core.Governance in 'src\core\DeepAxis.Core.Governance.pas',
  DeepAxis.WeChat.Adapter in 'src\wechat\DeepAxis.WeChat.Adapter.pas',
  DeepAxis.WeChat.Adapter411053 in 'src\wechat\DeepAxis.WeChat.Adapter411053.pas',
  DeepAxis.WeChat.Reader in 'src\wechat\DeepAxis.WeChat.Reader.pas',
  DeepAxis.WeChat.Decrypt in 'src\wechat\DeepAxis.WeChat.Decrypt.pas',
  DeepAxis.WeChat.Scanner in 'src\wechat\DeepAxis.WeChat.Scanner.pas',
  DeepAxis.WeChat.Zstd in 'src\wechat\DeepAxis.WeChat.Zstd.pas',
  DeepAxis.WeChat.MsgParser in 'src\wechat\DeepAxis.WeChat.MsgParser.pas',
  DeepAxis.Pipeline.Metrics in 'src\pipeline\DeepAxis.Pipeline.Metrics.pas',
  DeepAxis.Pipeline.Radar in 'src\pipeline\DeepAxis.Pipeline.Radar.pas',
  DeepAxis.Pipeline.Evidence in 'src\pipeline\DeepAxis.Pipeline.Evidence.pas',
  DeepAxis.Pipeline.TagEngine in 'src\pipeline\DeepAxis.Pipeline.TagEngine.pas',
  DeepAxis.Pipeline.IdleFunnel in 'src\pipeline\DeepAxis.Pipeline.IdleFunnel.pas',
  DeepAxis.Pipeline.AdTracker in 'src\pipeline\DeepAxis.Pipeline.AdTracker.pas',
  DeepAxis.Pipeline.ContactOverlay in 'src\pipeline\DeepAxis.Pipeline.ContactOverlay.pas',
  DeepAxis.Pipeline.SendResultPoller in 'src\pipeline\DeepAxis.Pipeline.SendResultPoller.pas',
  DeepAxis.Pipeline.StateMachine in 'src\pipeline\DeepAxis.Pipeline.StateMachine.pas',
  DeepAxis.Pipeline.Privacy in 'src\pipeline\DeepAxis.Pipeline.Privacy.pas',
  DeepAxis.Pipeline.BodyZero in 'src\pipeline\DeepAxis.Pipeline.BodyZero.pas',
  DeepAxis.Pipeline.ScriptEngine in 'src\pipeline\DeepAxis.Pipeline.ScriptEngine.pas',
  DeepAxis.Pipeline.Boundary in 'src\pipeline\DeepAxis.Pipeline.Boundary.pas',
  DeepAxis.Pipeline.SendQueue in 'src\pipeline\DeepAxis.Pipeline.SendQueue.pas',
  DeepAxis.Pipeline.Calibration in 'src\pipeline\DeepAxis.Pipeline.Calibration.pas',
  DeepAxis.Pipeline.TagManager in 'src\pipeline\DeepAxis.Pipeline.TagManager.pas',
  DeepAxis.Pipeline.Tier in 'src\pipeline\DeepAxis.Pipeline.Tier.pas',
  DeepAxis.UI.SetupForm in 'src\ui\DeepAxis.UI.SetupForm.pas',
  DeepAxis.UI.RadarPanel in 'src\ui\DeepAxis.UI.RadarPanel.pas',
  DeepAxis.UI.TierPanel in 'src\ui\DeepAxis.UI.TierPanel.pas',
  DeepAxis.UI.TagMatrixPanel in 'src\ui\DeepAxis.UI.TagMatrixPanel.pas',
  DeepAxis.UI.ScriptPanel in 'src\ui\DeepAxis.UI.ScriptPanel.pas',
  DeepAxis.UI.SendQueuePanel in 'src\ui\DeepAxis.UI.SendQueuePanel.pas',
  DeepAxis.UI.IdleFunnelPanel in 'src\ui\DeepAxis.UI.IdleFunnelPanel.pas',
  DeepAxis.UI.TagSuggestPanel in 'src\ui\DeepAxis.UI.TagSuggestPanel.pas',
  DeepAxis.UI.MainForm in 'src\ui\DeepAxis.UI.MainForm.pas',
  DeepAxis.Tests.Phases in 'src\DeepAxis.Tests.Phases.pas',
  DeepAxis.UIA.Engine in 'src\uia\DeepAxis.UIA.Engine.pas',
  DeepAxis.UIA.ContactOps in 'src\uia\DeepAxis.UIA.ContactOps.pas',
  // DeepBase 集成 — AIErrorHandler + AutoFix (最小依赖)
  DeepBase.AIErrorHandler in '..\DeepBase\Core\DeepBase.AIErrorHandler.pas',
  DeepBase.AutoFix in '..\DeepBase\Core\DeepBase.AutoFix.pas',
  DeepBase.AutoFix.ErrorRecorder in '..\DeepBase\Core\DeepBase.AutoFix.ErrorRecorder.pas',
  DeepBase.AutoFix.ScenarioRunner in '..\DeepBase\Core\DeepBase.AutoFix.ScenarioRunner.pas',
  DeepBase.AutoFix.HealthSignal in '..\DeepBase\Core\DeepBase.AutoFix.HealthSignal.pas',
  DeepBase.AutoFix.SelfTerminator in '..\DeepBase\Core\DeepBase.AutoFix.SelfTerminator.pas',
  DeepBase.AutoFix.StackWalker in '..\DeepBase\Core\DeepBase.AutoFix.StackWalker.pas',
  DeepBase.Logging in '..\DeepBase\Core\DeepBase.Logging.pas';

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;

  // ── DeepBase AutoFix: 默认启用运行时错误捕获 (BUG-048/049) ──
  // AutoFix 设计为 --autofix-mode 才激活 (写 autofix-output/runtime-errors.jsonl,
  // 捕获 EAccessViolation 等运行时错误并走 SelfTerminator 可控退出)。
  // 若用户未传该参数, 在 Application.Initialize 之前 (无窗口) 以带参方式
  // 重启自身, 保证日常双击运行时错误也有记录, 不再裸崩。
  var LHasAutoFixMode := False;
  for var I := 1 to ParamCount do
    if ParamStr(I).StartsWith('--autofix-mode') then
      LHasAutoFixMode := True;

  if not LHasAutoFixMode then
  begin
    var LCmdLine: string := GetCommandLine + ' --autofix-mode';
    var LStartInfo: TStartupInfo;
    var LProcInfo: TProcessInformation;
    FillChar(LStartInfo, SizeOf(LStartInfo), 0);
    LStartInfo.cb := SizeOf(LStartInfo);
    if CreateProcess(nil, PChar(LCmdLine), nil, nil, False,
      0, nil, nil, LStartInfo, LProcInfo) then
    begin
      CloseHandle(LProcInfo.hThread);
      CloseHandle(LProcInfo.hProcess);
    end;
    Exit;
  end;

  // ── DeepBase 集成: AutoFix + AIErrorHandler (需在 Application.Initialize 前 Install) ──
  AutoFix.Install;
  TAIErrorHandler.Install;
  RegisterGovernanceActions;

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := APP_TITLE;

  Application.CreateForm(TDeepAxisMainForm, DeepAxisMainForm);
  Application.Run;
end.