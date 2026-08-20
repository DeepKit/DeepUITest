unit DeepRKey.MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.WTSApi32,
  System.SysUtils, System.Variants, System.Classes, System.StrUtils,
  System.Win.Registry,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls,
  Vcl.Menus;

type
  TfrmMain = class(TForm)
    TrayIcon: TTrayIcon;
    TrayPopupMenu: TPopupMenu;
    miPause: TMenuItem;
    miSettings: TMenuItem;
    miAbout: TMenuItem;
    N1: TMenuItem;
    miExit: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure miPauseClick(Sender: TObject);
    procedure miSettingsClick(Sender: TObject);
    procedure miAboutClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
  private
    FPaused: Boolean;
    FStartTick: UInt64;
    FFirstRunTimer: TObject;
    FStartupTimer: TObject;  // T-010a: 延迟初始���定时器
    FSessionRegistered: Boolean;  // T-011: WTS session notification registered
    procedure UpdateTrayState;
    procedure OnTrayIconDblClick(Sender: TObject);
    procedure LogStartupComplete;
    procedure OnFirstRunTimer(Sender: TObject);
    procedure OnStartupTimer(Sender: TObject);  // T-010a: 延迟启动 Coordinator
    procedure ApplyTheme;  // T-304: Dark Mode
    // T-011: System event handlers
    procedure WMPowerBroadcast(var Msg: TMessage); message WM_POWERBROADCAST;
    procedure WMTSSessionChange(var Msg: TMessage); message WM_WTSSESSION_CHANGE;
    procedure WMDpiChanged(var Msg: TMessage); message WM_DPICHANGED;
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses
  DeepRKey.Bootstrap,
  DeepRKey.AboutForm,
  DeepRKey.SettingsForm,
  DeepRKey.FirstRunForm,
  DeepRKey.Coordinator,
  DeepBase.AutoFix,
  DeepBase.AutoFix.VclHook,
  Vcl.Themes, Vcl.Styles;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FStartTick := GetTickCount64;

  // T-304: Apply theme before showing any UI
  ApplyTheme;

  Self.Visible := False;

  TrayIcon.Visible := True;
  TrayIcon.Hint := 'DeepRKey';
  TrayIcon.OnDblClick := OnTrayIconDblClick;
  UpdateTrayState;

  FPaused := False;

  // T-011: Register for WTS session change notifications
  FSessionRegistered := WTSRegisterSessionNotification(Handle, NOTIFY_FOR_ALL_SESSIONS);

  // T-010a: 托盘图标已显示，记录快速启动时间
  var trayVisibleMs := GetTickCount64 - FStartTick;
  TBootstrap.Logger.Info(
    Format('Tray icon visible: %dms', [trayVisibleMs]), 'Startup');

  // T-010a: 延迟启动 Coordinator（让 UI 线程先处理消息）
  // 创建 Coordinator 对象，但延迟 Start
  GCoordinator := TDeepRKeyCoordinator.Create;

  // 使用 50ms 定时器延迟 Start，让 Windows 先处理托盘图标显示
  var startupTimer := TTimer.Create(Self);
  startupTimer.Interval := 50;
  startupTimer.OnTimer := OnStartupTimer;
  FStartupTimer := startupTimer;

  // Schedule first-run wizard after startup completes (500ms delay)
  var timer := TTimer.Create(Self);
  timer.Interval := 500;
  timer.OnTimer := OnFirstRunTimer;
  FFirstRunTimer := timer;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  // T-011: Unregister WTS session notifications
  if FSessionRegistered then
    WTSUnRegisterSessionNotification(Handle);

  // Uninstall VCL exception hook first to prevent dangling reference
  TAutoFixVclHook.Uninstall;

  // Stop coordinator before destroying the form
  if GCoordinator <> nil then
  begin
    GCoordinator.OnPauseStateChanged := nil;
    GCoordinator.Stop;
    FreeAndNil(GCoordinator);
  end;

  TrayIcon.Visible := False;
  if Assigned(TBootstrap.Logger) then
    TBootstrap.Logger.Info('MainForm destroying', 'UI');
end;

procedure TfrmMain.LogStartupComplete;
begin
  var elapsed := GetTickCount64 - FStartTick;
  TBootstrap.Logger.Info(
    Format('DeepRKey startup complete in %d ms', [elapsed]), 'Bootstrap');
end;

procedure TfrmMain.UpdateTrayState;
begin
  if FPaused then
  begin
    miPause.Caption := 'Resume';
    TrayIcon.Hint := 'DeepRKey (Paused)';
  end
  else
  begin
    miPause.Caption := 'Pause';
    TrayIcon.Hint := 'DeepRKey';
  end;
end;

procedure TfrmMain.OnTrayIconDblClick(Sender: TObject);
begin
  miSettingsClick(Sender);
end;

procedure TfrmMain.miPauseClick(Sender: TObject);
begin
  FPaused := not FPaused;
  UpdateTrayState;

  // Sync coordinator pause state
  if GCoordinator <> nil then
    GCoordinator.Paused := FPaused;

  var status := IfThen(FPaused, 'paused', 'resumed');
  TBootstrap.Logger.Info(Format('DeepRKey %s', [status]), 'UI');
end;

procedure TfrmMain.miSettingsClick(Sender: TObject);
begin
  TBootstrap.Logger.Info('Settings opened', 'UI');
  TfrmSettings.ShowSettings;
end;

procedure TfrmMain.miAboutClick(Sender: TObject);
begin
  TfrmAbout.ShowAbout;
end;

procedure TfrmMain.miExitClick(Sender: TObject);
begin
  TBootstrap.Logger.Info('User requested exit', 'UI');
  Application.Terminate;
end;

procedure TfrmMain.OnFirstRunTimer(Sender: TObject);
var
  timer: TTimer;
begin
  timer := Sender as TTimer;
  timer.Enabled := False;
  timer.Free;
  FFirstRunTimer := nil;

  // Show first-run wizard if this is the first launch
  try
    CheckAndShowFirstRun;
  except
    on E: Exception do
      TBootstrap.Logger.Error(
        Format('First-run wizard failed: %s', [E.Message]), 'Bootstrap');
  end;
end;

procedure TfrmMain.OnStartupTimer(Sender: TObject);
var
  timer: TTimer;
  startMs: UInt64;
begin
  timer := Sender as TTimer;
  timer.Enabled := False;
  timer.Free;
  FStartupTimer := nil;

  // T-010a: 延迟启动 Coordinator（在托盘图标显示后）
  startMs := GetTickCount64;

  try
    // 启动 Coordinator（IPC + WinEvent hooks + menu injection）
    GCoordinator.Start;

    // Register tray state callback for CLI pause/resume commands
    GCoordinator.OnPauseStateChanged := procedure
    begin
      FPaused := GCoordinator.Paused;
      UpdateTrayState;
    end;

    var coordinatorMs := GetTickCount64 - startMs;
    TBootstrap.Logger.Info(
      Format('Coordinator started in %dms', [coordinatorMs]), 'Startup');

    // AutoFix: signal shell is ready, run scenarios on next idle
    AutoFix.NotifyShellShown;

    // Log touch device detection
    if IsTouchDevice then
      TBootstrap.Logger.Info('Touch/pen device detected', 'Bootstrap');

    // 记录功能完全就绪时间
    LogStartupComplete;

  except
    on E: Exception do
      TBootstrap.Logger.Error(
        Format('Coordinator start failed: %s', [E.Message]), 'Bootstrap');
  end;
end;

{ T-304: Dark Mode theme support }

function QuerySystemDarkMode: Boolean;
var
  reg: TRegistry;
begin
  Result := False;
  reg := TRegistry.Create(KEY_READ);
  try
    reg.RootKey := HKEY_CURRENT_USER;
    if reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize') then
    begin
      if reg.ValueExists('AppsUseLightTheme') then
        Result := reg.ReadInteger('AppsUseLightTheme') = 0;
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

procedure TfrmMain.ApplyTheme;
var
  themeName: string;
  styleNames: TArray<string>;
  darkStyle: string;
begin
  themeName := TBootstrap.Config.ReadString('UI.Theme', 'System');

  if SameText(themeName, 'System') then
  begin
    // Follow Windows system theme
    if QuerySystemDarkMode then
    begin
      // Try to find a suitable dark VCL style
      styleNames := TStyleManager.StyleNames;
      darkStyle := '';
      for var sn in styleNames do
      begin
        if SameText(sn, 'Windows10 Dark') or SameText(sn, 'Carbon') then
        begin
          darkStyle := sn;
          Break;
        end;
      end;
      if darkStyle <> '' then
        TStyleManager.SetStyle(darkStyle);
    end;
    // Light mode: use default Windows style (no action needed)
  end
  else if not SameText(themeName, 'Light') then
  begin
    // Explicit style name selected
    TStyleManager.TrySetStyle(themeName);
  end;

  TBootstrap.Logger.Info(
    Format('Theme applied: %s (active: %s)', [themeName, TStyleManager.ActiveStyle.Name]),
    'Theme');
end;

{ T-011: System event handlers }

const
  PBT_APMRESUMEAUTOMATIC = $0012;
  PBT_APMRESUMESUSPEND   = $0007;
  PBT_APMSUSPEND         = $0004;

procedure TfrmMain.WMPowerBroadcast(var Msg: TMessage);
const
  NOTIFY_FOR_THIS_WINDOW = 4;  // Not in Delphi headers
begin
  case Msg.WParam of
    PBT_APMRESUMEAUTOMATIC:
    begin
      TBootstrap.Logger.Info('Power: system resumed from sleep', 'System');
      if GCoordinator <> nil then
        GCoordinator.OnSystemResume;
    end;
    PBT_APMRESUMESUSPEND:
      TBootstrap.Logger.Info('Power: user resumed from suspend', 'System');
    PBT_APMSUSPEND:
      TBootstrap.Logger.Info('Power: system suspending', 'System');
  end;
  // Return TRUE to indicate message was handled
  Msg.Result := 1;
end;

procedure TfrmMain.WMTSSessionChange(var Msg: TMessage);
begin
  if GCoordinator <> nil then
    GCoordinator.OnSessionChange(Msg.WParam);
  Msg.Result := 0;
end;

procedure TfrmMain.WMDpiChanged(var Msg: TMessage);
begin
  TBootstrap.Logger.Info(
    Format('DPI changed: wParam=$%x (DPI=%d)', [Msg.WParam, Msg.WParam and $FFFF]),
    'System');
  // Forward to coordinator for window re-evaluation
  if GCoordinator <> nil then
    GCoordinator.ReenumerateAllWindows;
  inherited;
end;

end.