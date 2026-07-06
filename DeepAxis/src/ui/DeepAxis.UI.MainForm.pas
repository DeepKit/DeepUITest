unit DeepAxis.UI.MainForm;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils, System.Math,
  Winapi.Windows, Winapi.Messages, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.ComCtrls, Vcl.Dialogs,
  Vcl.Graphics,
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Phys.SQLite,
  FireDAC.Comp.UI, FireDAC.VCLUI.Wait,
  DeepBase.AIErrorHandler,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.Core.Config, DeepAxis.Core.Profile, DeepAxis.Core.Governance,
  DeepAxis.WeChat.Adapter, DeepAxis.WeChat.Adapter411053,
  DeepAxis.WeChat.Reader, DeepAxis.WeChat.Decrypt, DeepAxis.WeChat.Scanner,
  DeepAxis.Pipeline.Metrics, DeepAxis.Pipeline.Radar, DeepAxis.Pipeline.Evidence,
  DeepAxis.Pipeline.TagEngine, DeepAxis.Pipeline.IdleFunnel,
  DeepAxis.Pipeline.StateMachine, DeepAxis.Pipeline.Boundary,
  DeepAxis.Pipeline.ScriptEngine, DeepAxis.Pipeline.SendQueue,
  DeepAxis.Pipeline.Calibration,
  DeepAxis.UI.RadarPanel, DeepAxis.UI.TagMatrixPanel,
  DeepAxis.UI.ScriptPanel, DeepAxis.UI.SendQueuePanel,
  DeepAxis.UI.SetupForm,
  DeepAxis.UIA.Engine;

type
  TDeepAxisMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    FMainMenu: TMainMenu;
    FToolPanel: TPanel;
    FStatusBar: TStatusBar;
    FWeChatScanner: TWeChatScanner;
    FWeChatReader: IWxReader;
    FSchemaAdapter: ISchemaAdapter;
    FAdapterRegistry: TSchemaAdapterRegistry;
    FDB2Connection: TFDConnection;
    FFDWait: TFDGUIxWaitCursor;
    FRadarEngine: IRadarEngine;
    FEvidenceBuilder: IEvidenceBuilder;
    FMetricCalculator: IMetricCalculator;
    FTagEngine: ITagEngine;
    FIdleFunnel: IIdleFunnel;
    FStateMachine: IStateMachine;
    FScriptEngine: TScriptEngine;
    FBoundaryEngine: TBoundaryEngine;
    FSendQueue: TSendQueue;
    FCalibrationEngine: TCalibrationEngine;
    FUiaEngine: TUiaEngine;
    FDBPollerThread: TDBPollerThread;
    FKeyMonitorTimer: TTimer;
    FKeyMonitorAttempts: Integer;
    FRadarPanel: TDeepAxisRadarPanel;
    FTagMatrixPanel: TDeepAxisTagMatrixPanel;
    FScriptPanel: TScriptPanel;
    FSendQueuePanel: TSendQueuePanel;
    FCurrentLayout: TDeepAxisLayout;
    FWeChatWindowHandle: HWND;
    FWeChatHook: THandle;
    FLogMemo: TMemo;
    FWarningPanel: TPanel;
    FWarningLabel: TLabel;
    FHotKeyIds: array[0..5] of Integer;

    procedure InitDB2;
    procedure InitBusinessServices;
    procedure InitUI;
    procedure InitToolPanel;
    procedure InitHotKeys;
    procedure InitWeChatHook;
    procedure StartPolling;
    procedure StopPolling;
    procedure OnPollResultReady(Sender: TObject; const AData: TPollResult);
    procedure OnScannerStateChanged(const AState: TWeChatProcessState);
    procedure OnKeyMonitorTimer(Sender: TObject);
    procedure DockToWeChatWindow;
    procedure ApplyLayout(ALayout: TDeepAxisLayout);
    procedure DoLaunchWeChat(Sender: TObject);
    procedure DoScanKey(Sender: TObject);
    procedure DoConnectDecrypted(Sender: TObject);
    procedure DoReadContacts(Sender: TObject);
    procedure DoSetWeChatDataPath(Sender: TObject);
    procedure DoRefreshData(Sender: TObject);
    procedure DoToggleLayout(Sender: TObject);
    procedure DoPasteScript(const AScript: string);
    procedure DoPasteScriptInner(const AScript: string);
    procedure DoSkipContact;
    procedure DoNextVariant;
    procedure DoPrevVariant;
    procedure DoVariant1; procedure DoVariant2; procedure DoVariant3;
    procedure DoSettings(Sender: TObject);
    procedure DoAbout(Sender: TObject);
    procedure Log(const AMsg: string);
    procedure UpdateWorkflow;
    procedure ShowWarning(const AMsg: string);
    procedure HideWarning;
    procedure RefreshStepButtons;
  protected
    procedure WndProc(var Msg: TMessage); override;
  public
    procedure HandleWeChatWinEvent(AEvent: DWORD; Ahwnd: HWND;
      AidObject: LONG; AidChild: LONG);
  end;

var
  DeepAxisMainForm: TDeepAxisMainForm;

procedure WeChatWinEventCallback(hWinEventHook: THandle; event: DWORD;
  hwnd: HWND; idObject: LONG; idChild: LONG; dwEventThread: DWORD;
  dwms: DWORD); stdcall;

implementation

{$R *.dfm}

var
  GLogFile: TextFile;
  GLogFilePath: string;
  GLogFileInitialized: Boolean = False;

const
  WM_HOTKEY_SPACE = 1;
  WM_HOTKEY_ESC   = 2;
  WM_HOTKEY_VAR1  = 3;
  WM_HOTKEY_VAR2  = 4;
  WM_HOTKEY_VAR3  = 5;
  WM_HOTKEY_LAYOUT = 6;

procedure WeChatWinEventCallback(hWinEventHook: THandle; event: DWORD;
  hwnd: HWND; idObject: LONG; idChild: LONG; dwEventThread: DWORD;
  dwms: DWORD);
begin
  if (DeepAxisMainForm <> nil) and (idObject = OBJID_WINDOW) then
    DeepAxisMainForm.HandleWeChatWinEvent(event, hwnd, idObject, idChild);
end;

{ TDeepAxisMainForm }

procedure TDeepAxisMainForm.FormCreate(Sender: TObject);
begin
  FFDWait := TFDGUIxWaitCursor.Create(nil);
  FCurrentLayout := dlDock;
  FWeChatWindowHandle := 0;
  FWeChatHook := 0;
  FDB2Connection := nil;
  FDBPollerThread := nil;
  InitDB2;
  InitBusinessServices;
  InitUI;
  InitHotKeys;
end;

procedure TDeepAxisMainForm.FormDestroy(Sender: TObject);
var I: Integer;
begin
  if GLogFileInitialized then
  try CloseFile(GLogFile); except end;

  StopPolling;
  for I := 0 to 5 do
    if FHotKeyIds[I] <> 0 then
      UnregisterHotKey(Handle, FHotKeyIds[I]);
  if FWeChatHook <> 0 then
  begin UnhookWinEvent(FWeChatHook); FWeChatHook := 0; end;
  FDBPollerThread := nil;
  FWeChatScanner.Free;
  FAdapterRegistry.Free;
  FDB2Connection.Free;
  FFDWait.Free;
  FScriptEngine.Free;
  FBoundaryEngine.Free;
  FSendQueue.Free;
  FCalibrationEngine.Free;
  FUiaEngine.Free;
end;

procedure TDeepAxisMainForm.FormShow(Sender: TObject);
var LPid: Cardinal; LSetup: TDeepAxisSetupForm;
begin
  ApplyLayout(dlDock);
  InitWeChatHook;

  // ── 首次启动: 弹出配置向导 ──
  if TDeepAxisConfig.GetWeChatDataPath = '' then
  begin
    LSetup := TDeepAxisSetupForm.Create(Self);
    try
      if LSetup.ShowModal = mrOk then
        Log('初始设置完成: ' + TDeepAxisConfig.GetWeChatDataPath)
      else
        Log('初始设置已取消');
    finally
      LSetup.Free;
    end;
  end;

  LPid := FWeChatScanner.FindWeChatProcess;
  if LPid = 0 then
  begin
    ShowWarning('未检测到微信进程！请点击"1. 启动微信"或确保微信已安装');
    Log('警告: 未检测到微信进程 (Weixin.exe)');
  end
  else
    Log('检测到微信已在运行 (PID: ' + IntToStr(LPid) + ')');

  if FWeChatScanner.TrySavedKeysOnly then
  begin
    HideWarning;
    Log(Format('已加载 %d 个密钥', [FWeChatScanner.KeyManager.GetKeyCount]));
    var LCP := FWeChatScanner.DecryptedContactPath;
    var LMP := FWeChatScanner.DecryptedMessage0Path;
    var LSP := FWeChatScanner.DecryptedSessionPath;
    if (LCP <> '') and (LMP <> '') then
    begin
      if FWeChatReader.OpenPaths(LCP, LMP, LSP) then
      begin
        FRadarPanel.SetWeChatConnected(True);
        Log('已连接微信数据');
        StartPolling;
      end;
    end;
  end
  else
  begin
    Log('未找到已保存的密钥');
    if LPid <> 0 then
    begin
      Log('自动启动密钥监控...');
      FKeyMonitorAttempts := 0;
      if FKeyMonitorTimer = nil then
      begin
        FKeyMonitorTimer := TTimer.Create(Self);
        FKeyMonitorTimer.OnTimer := OnKeyMonitorTimer;
      end;
      FKeyMonitorTimer.Interval := 3000;
      FKeyMonitorTimer.Enabled := True;
    end;
  end;

  RefreshStepButtons;
end;

procedure TDeepAxisMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  StopPolling;
end;

// ── DB2 ──────────────────────────────────────────────────────────

procedure TDeepAxisMainForm.InitDB2;
var LDB2Path: string; LQuery: TFDQuery;
begin
  LDB2Path := TDeepAxisConfig.GetDB2Path;
  ForceDirectories(TPath.GetDirectoryName(LDB2Path));
  FDB2Connection := TFDConnection.Create(nil);
  FDB2Connection.DriverName := 'SQLite';
  FDB2Connection.Params.Database := LDB2Path;
  FDB2Connection.Params.Add('OpenMode=CreateUTF8');
  FDB2Connection.Params.Add('LockingMode=Normal');
  FDB2Connection.Open;
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := FDB2Connection;
    LQuery.SQL.Text := 'CREATE TABLE IF NOT EXISTS ' + DB2_TABLE_KEY_REFS + ' (source_account_id TEXT PRIMARY KEY, secret_ref TEXT, salt_hex TEXT, db_path TEXT, captured_at INTEGER, verified INTEGER DEFAULT 0)'; LQuery.ExecSQL;
    LQuery.SQL.Text := 'CREATE TABLE IF NOT EXISTS ' + DB2_TABLE_CONTACTS + ' (contact_id TEXT PRIMARY KEY, display_name_hash TEXT, display_name_redacted TEXT, privacy TEXT, tag_profile TEXT, updated_at TEXT)'; LQuery.ExecSQL;
    LQuery.SQL.Text := 'CREATE TABLE IF NOT EXISTS ' + DB2_TABLE_METRICS + ' (metric_id TEXT PRIMARY KEY, contact_id TEXT, inbound_count INTEGER, outbound_count INTEGER, data_quality TEXT, computed_at TEXT)'; LQuery.ExecSQL;
    LQuery.SQL.Text := 'CREATE TABLE IF NOT EXISTS ' + DB2_TABLE_HINTS + ' (hint_id TEXT PRIMARY KEY, contact_id TEXT, hint_type TEXT, confidence REAL, created_at TEXT)'; LQuery.ExecSQL;
    LQuery.SQL.Text := 'CREATE TABLE IF NOT EXISTS ' + DB2_TABLE_EVIDENCE + ' (evidence_id TEXT PRIMARY KEY, hint_id TEXT, summary TEXT, contains_body INTEGER DEFAULT 0)'; LQuery.ExecSQL;
    LQuery.SQL.Text := 'CREATE TABLE IF NOT EXISTS ' + DB2_TABLE_AUDIT + ' (audit_id TEXT PRIMARY KEY, event_type TEXT, body_columns_queried INTEGER DEFAULT 0)'; LQuery.ExecSQL;
    LQuery.SQL.Text := 'CREATE TABLE IF NOT EXISTS ' + DB2_TABLE_CURSORS + ' (contact_id TEXT PRIMARY KEY, last_local_id INTEGER DEFAULT 0)'; LQuery.ExecSQL;
  finally LQuery.Free; end;
end;

procedure TDeepAxisMainForm.InitBusinessServices;
begin
  FAdapterRegistry := TSchemaAdapterRegistry.Create;
  FSchemaAdapter := TWeChat411053Adapter.Create;
  FAdapterRegistry.RegisterAdapter(FSchemaAdapter);
  FWeChatReader := TWeChatReader.Create(FSchemaAdapter);
  FMetricCalculator := TMetricCalculator.Create;
  FRadarEngine := TRadarEngine.Create;
  FEvidenceBuilder := TEvidenceBuilder.Create;
  FTagEngine := TTagEngine.Create;
  FIdleFunnel := TIdleFunnel.Create;
  FStateMachine := TContactStateMachine.Create;
  FScriptEngine := TScriptEngine.Create;
  FBoundaryEngine := TBoundaryEngine.Create;
  FSendQueue := TSendQueue.Create;
  FCalibrationEngine := TCalibrationEngine.Create;
  FUiaEngine := TUiaEngine.Create;
  FWeChatScanner := TWeChatScanner.Create;
  FWeChatScanner.OnStateChanged := OnScannerStateChanged;
end;

// ── UI ───────────────────────────────────────────────────────────

procedure TDeepAxisMainForm.InitToolPanel;
var
  LBtn: TButton;
  LLeft: Integer;
begin
  FToolPanel := TPanel.Create(Self);
  FToolPanel.Parent := Self;
  FToolPanel.Align := alTop;
  FToolPanel.Height := 36;
  FToolPanel.BevelOuter := bvNone;
  FToolPanel.BorderWidth := 3;

  LLeft := 4;

  // 1. 启动微信
  LBtn := TButton.Create(FToolPanel);
  LBtn.Parent := FToolPanel;
  LBtn.Top := 3; LBtn.Left := LLeft; LBtn.Height := 28; LBtn.Width := 95;
  LBtn.Caption := '1. 启动微信';
  LBtn.OnClick := DoLaunchWeChat;
  LBtn.Tag := 1;
  Inc(LLeft, 100);

  // 2. 扫描密钥
  LBtn := TButton.Create(FToolPanel);
  LBtn.Parent := FToolPanel;
  LBtn.Top := 3; LBtn.Left := LLeft; LBtn.Height := 28; LBtn.Width := 95;
  LBtn.Caption := '2. 扫描密钥';
  LBtn.OnClick := DoScanKey;
  LBtn.Tag := 2;
  Inc(LLeft, 100);

  // 3. 连接解密
  LBtn := TButton.Create(FToolPanel);
  LBtn.Parent := FToolPanel;
  LBtn.Top := 3; LBtn.Left := LLeft; LBtn.Height := 28; LBtn.Width := 95;
  LBtn.Caption := '3. 连接解密';
  LBtn.OnClick := DoConnectDecrypted;
  LBtn.Tag := 3;
  Inc(LLeft, 100);

  // 4. 读取联系人
  LBtn := TButton.Create(FToolPanel);
  LBtn.Parent := FToolPanel;
  LBtn.Top := 3; LBtn.Left := LLeft; LBtn.Height := 28; LBtn.Width := 105;
  LBtn.Caption := '4. 读取联系人';
  LBtn.OnClick := DoReadContacts;
  LBtn.Tag := 4;
  Inc(LLeft, 110);

  // 刷新
  LBtn := TButton.Create(FToolPanel);
  LBtn.Parent := FToolPanel;
  LBtn.Top := 3; LBtn.Left := LLeft; LBtn.Height := 28; LBtn.Width := 60;
  LBtn.Caption := '刷新';
  LBtn.OnClick := DoRefreshData;
  Inc(LLeft, 66);

  // 设置
  LBtn := TButton.Create(FToolPanel);
  LBtn.Parent := FToolPanel;
  LBtn.Top := 3; LBtn.Left := LLeft; LBtn.Height := 28; LBtn.Width := 60;
  LBtn.Caption := '设置';
  LBtn.OnClick := DoSettings;
end;

procedure TDeepAxisMainForm.RefreshStepButtons;
begin
  if FToolPanel = nil then Exit;
  var LWeChatRunning := (FWeChatScanner.FindWeChatProcess <> 0);
  var LKeysLoaded := FWeChatScanner.KeyManager.HasKeys;
  var LConnected := (FWeChatReader <> nil) and FWeChatReader.IsOpen;

  for var I := 0 to FToolPanel.ControlCount - 1 do
  begin
    if FToolPanel.Controls[I] is TButton then
    begin
      var LBtn := TButton(FToolPanel.Controls[I]);
      case LBtn.Tag of
        1: LBtn.Enabled := True;
        2: LBtn.Enabled := LWeChatRunning;
        3: LBtn.Enabled := LKeysLoaded;
        4: LBtn.Enabled := LConnected;
      end;
    end;
  end;
end;

procedure TDeepAxisMainForm.InitUI;
var
  LMenuWeChat, LMenuView, LMenuData, LMenuOther: TMenuItem;
  LItem: TMenuItem;
begin
  Caption := APP_TITLE + ' ' + APP_TITLE_ZH + ' v' + APP_VERSION;
  Width := 1600; Height := 1000;

  // Menu
  FMainMenu := TMainMenu.Create(Self); Self.Menu := FMainMenu;

  LMenuWeChat := TMenuItem.Create(Self); LMenuWeChat.Caption := '微信'; FMainMenu.Items.Add(LMenuWeChat);
  LItem := TMenuItem.Create(Self); LItem.Caption := '启动微信'; LItem.OnClick := DoLaunchWeChat; LMenuWeChat.Add(LItem);
  LItem := TMenuItem.Create(Self); LItem.Caption := '扫描密钥'; LItem.OnClick := DoScanKey; LMenuWeChat.Add(LItem);
  LItem := TMenuItem.Create(Self); LItem.Caption := '连接解密数据'; LItem.OnClick := DoConnectDecrypted; LMenuWeChat.Add(LItem);
  LItem := TMenuItem.Create(Self); LItem.Caption := '读取联系人'; LItem.OnClick := DoReadContacts; LMenuWeChat.Add(LItem);
  LItem := TMenuItem.Create(Self); LItem.Caption := '-'; LMenuWeChat.Add(LItem);
  LItem := TMenuItem.Create(Self); LItem.Caption := '指定微信数据目录...'; LItem.OnClick := DoSetWeChatDataPath; LMenuWeChat.Add(LItem);

  LMenuView := TMenuItem.Create(Self); LMenuView.Caption := '视图'; FMainMenu.Items.Add(LMenuView);
  LItem := TMenuItem.Create(Self); LItem.Caption := '切换布局'; LItem.ShortCut := TextToShortCut('Ctrl+L'); LItem.OnClick := DoToggleLayout; LMenuView.Add(LItem);

  LMenuData := TMenuItem.Create(Self); LMenuData.Caption := '数据'; FMainMenu.Items.Add(LMenuData);
  LItem := TMenuItem.Create(Self); LItem.Caption := '刷新数据'; LItem.OnClick := DoRefreshData; LMenuData.Add(LItem);

  LMenuOther := TMenuItem.Create(Self); LMenuOther.Caption := '其它'; FMainMenu.Items.Add(LMenuOther);
  LItem := TMenuItem.Create(Self); LItem.Caption := '设置'; LItem.OnClick := DoSettings; LMenuOther.Add(LItem);
  LItem := TMenuItem.Create(Self); LItem.Caption := '-'; LMenuOther.Add(LItem);
  LItem := TMenuItem.Create(Self); LItem.Caption := '关于 DeepAxis'; LItem.OnClick := DoAbout; LMenuOther.Add(LItem);

  // Toolbar
  InitToolPanel;

  // Warning banner
  FWarningPanel := TPanel.Create(Self);
  FWarningPanel.Parent := Self;
  FWarningPanel.Align := alTop;
  FWarningPanel.Height := 36;
  FWarningPanel.Visible := False;
  FWarningPanel.Color := $004080FF;
  FWarningPanel.BevelOuter := bvNone;
  FWarningLabel := TLabel.Create(FWarningPanel);
  FWarningLabel.Parent := FWarningPanel;
  FWarningLabel.Align := alClient;
  FWarningLabel.Alignment := taCenter;
  FWarningLabel.Layout := tlCenter;
  FWarningLabel.Font.Color := clWhite;

  // StatusBar
  FStatusBar := TStatusBar.Create(Self); FStatusBar.Parent := Self; FStatusBar.SimplePanel := True; FStatusBar.SimpleText := '就绪';

  // Log
  FLogMemo := TMemo.Create(Self); FLogMemo.Parent := Self; FLogMemo.Align := alBottom; FLogMemo.Height := 100; FLogMemo.ReadOnly := True; FLogMemo.ScrollBars := ssVertical;

  // Radar panel (main area)
  FRadarPanel := TDeepAxisRadarPanel.Create(Self); FRadarPanel.Parent := Self; FRadarPanel.Align := alClient;

  // Script panel (right)
  FScriptPanel := TScriptPanel.Create(Self); FScriptPanel.Parent := Self; FScriptPanel.Align := alRight; FScriptPanel.Width := 500; FScriptPanel.Visible := False;
  FScriptPanel.OnPaste := DoPasteScript;
  FScriptPanel.OnSkip := DoSkipContact;

  // Send queue panel (bottom)
  FSendQueuePanel := TSendQueuePanel.Create(Self); FSendQueuePanel.Parent := Self; FSendQueuePanel.Align := alBottom; FSendQueuePanel.Height := 150; FSendQueuePanel.Visible := False;
  FSendQueuePanel.SetQueue(FSendQueue);

  // Tag matrix (bottom)
  FTagMatrixPanel := TDeepAxisTagMatrixPanel.Create(Self); FTagMatrixPanel.Parent := Self; FTagMatrixPanel.Align := alBottom; FTagMatrixPanel.Height := 250; FTagMatrixPanel.Visible := False;
end;

// ── Hotkeys ───────────────────────────────────────────────────────

procedure TDeepAxisMainForm.InitHotKeys;
begin
  FHotKeyIds[0] := GlobalAddAtom('DeepAxis_Space');
  FHotKeyIds[1] := GlobalAddAtom('DeepAxis_Esc');
  FHotKeyIds[2] := GlobalAddAtom('DeepAxis_Var1');
  FHotKeyIds[3] := GlobalAddAtom('DeepAxis_Var2');
  FHotKeyIds[4] := GlobalAddAtom('DeepAxis_Var3');
  FHotKeyIds[5] := GlobalAddAtom('DeepAxis_Layout');
  RegisterHotKey(Handle, WM_HOTKEY_SPACE, MOD_CONTROL or MOD_SHIFT, Ord(' '));
  RegisterHotKey(Handle, WM_HOTKEY_ESC,   MOD_CONTROL or MOD_SHIFT, Ord('S'));
  RegisterHotKey(Handle, WM_HOTKEY_VAR1,  MOD_CONTROL or MOD_SHIFT, Ord('1'));
  RegisterHotKey(Handle, WM_HOTKEY_VAR2,  MOD_CONTROL or MOD_SHIFT, Ord('2'));
  RegisterHotKey(Handle, WM_HOTKEY_VAR3,  MOD_CONTROL or MOD_SHIFT, Ord('3'));
  RegisterHotKey(Handle, WM_HOTKEY_LAYOUT, MOD_CONTROL, Ord('L'));
end;

procedure TDeepAxisMainForm.WndProc(var Msg: TMessage);
begin
  if Msg.Msg = WM_HOTKEY then
  begin
    case Msg.WParam of
      WM_HOTKEY_SPACE:  DoPasteScript('');
      WM_HOTKEY_ESC:    DoSkipContact;
      WM_HOTKEY_VAR1:   DoVariant1;
      WM_HOTKEY_VAR2:   DoVariant2;
      WM_HOTKEY_VAR3:   DoVariant3;
      WM_HOTKEY_LAYOUT: DoToggleLayout(nil);
    end;
  end;
  inherited;
end;

// ── WeChat Hook ────────────────────────────────────────────────────

procedure TDeepAxisMainForm.InitWeChatHook;
begin
  FWeChatHook := SetWinEventHook(EVENT_OBJECT_LOCATIONCHANGE, EVENT_OBJECT_LOCATIONCHANGE,
    0, @WeChatWinEventCallback, 0, 0, WINEVENT_OUTOFCONTEXT or WINEVENT_SKIPOWNPROCESS);
end;

procedure TDeepAxisMainForm.HandleWeChatWinEvent(AEvent: DWORD; Ahwnd: HWND;
  AidObject: LONG; AidChild: LONG);
var LClassName: array[0..255] of Char;
begin
  if AidObject = OBJID_WINDOW then
  begin
    GetClassName(Ahwnd, LClassName, SizeOf(LClassName));
    if Pos('WeChat', string(LClassName)) > 0 then
    begin FWeChatWindowHandle := Ahwnd; if FCurrentLayout = dlDock then DockToWeChatWindow; end;
  end;
end;

// ── Layout ─────────────────────────────────────────────────────────

procedure TDeepAxisMainForm.ApplyLayout(ALayout: TDeepAxisLayout);
begin
  FCurrentLayout := ALayout;
  case ALayout of
    dlCompact:    begin Width := DEEPAXIS_STRIP_WIDTH; Height := DEEPAXIS_COMPACT_HEIGHT; FScriptPanel.Visible := False; FTagMatrixPanel.Visible := False; end;
    dlDock:       begin Width := DEEPAXIS_STRIP_WIDTH; Height := 1000; FScriptPanel.Visible := True; FTagMatrixPanel.Visible := False; DockToWeChatWindow; end;
    dlFullScreen: begin WindowState := wsMaximized; FScriptPanel.Visible := True; FTagMatrixPanel.Visible := True; end;
  end;
end;

procedure TDeepAxisMainForm.DockToWeChatWindow;
var LWeChatRect: TRect;
begin
  if FWeChatWindowHandle = 0 then Exit;
  if GetWindowRect(FWeChatWindowHandle, LWeChatRect) then
  begin Self.Left := LWeChatRect.Right; Self.Top := LWeChatRect.Top; Self.Height := LWeChatRect.Height; end;
end;

// ── Warning ────────────────────────────────────────────────────────

procedure TDeepAxisMainForm.ShowWarning(const AMsg: string);
begin
  FWarningLabel.Caption := AMsg;
  FWarningPanel.Visible := True;
  FStatusBar.SimpleText := AMsg;
end;

procedure TDeepAxisMainForm.HideWarning;
begin
  FWarningPanel.Visible := False;
end;

// ── Step operations ────────────────────────────────────────────────

procedure TDeepAxisMainForm.DoScanKey(Sender: TObject);
begin
  SafeRun('扫描密钥', procedure
  begin
    var LPid := FWeChatScanner.FindWeChatProcess;
    if LPid = 0 then
    begin
      ShowWarning('未检测到微信进程！请先点击"1. 启动微信"');
      Log('扫描失败: 微信未运行');
      Exit;
    end;

    if FKeyMonitorTimer <> nil then
    begin
      FKeyMonitorTimer.Enabled := False;
      FKeyMonitorTimer := nil;
    end;

    Log('开始扫描内存密钥...');
    FStatusBar.SimpleText := '正在扫描密钥...';
    Application.ProcessMessages;

    var LResult := FWeChatScanner.StartScan;
    if LResult.IsSuccess then
    begin
      HideWarning;
      Log('密钥捕获成功！');
      FStatusBar.SimpleText := '密钥已就绪 — 请点击"3. 连接解密"';
    end
    else
    begin
      ShowWarning('密钥扫描失败: ' + LResult.ErrorMessage + ' — 请确保微信已登录');
      Log('密钥扫描失败: ' + LResult.ErrorMessage);
    end;
    RefreshStepButtons;
  end);
end;

procedure TDeepAxisMainForm.DoReadContacts(Sender: TObject);
begin
  SafeRun('读取联系人', procedure
  begin
    if (FWeChatReader = nil) or (not FWeChatReader.IsOpen) then
    begin
      ShowWarning('数据库未连接！请先完成步骤 1-3');
      Log('读取失败: 数据库未连接');
      Exit;
    end;

    Log('读取联系人...');
    FStatusBar.SimpleText := '正在读取联系人...';
    Application.ProcessMessages;

    var LContacts := FWeChatReader.ReadContacts;
    Log(Format('读取到 %d 个联系人', [Length(LContacts)]));

    if Length(LContacts) > 0 then
    begin
      for var I := 0 to Min(4, Length(LContacts) - 1) do
        Log(Format('  示例: %s (hash:%s)', [LContacts[I].DisplayNameRedacted, Copy(LContacts[I].DisplayNameHash, 1, 16)]));

      if not FRadarPanel.IsConnected then
      begin
        FRadarPanel.SetWeChatConnected(True);
        FStatusBar.SimpleText := Format('已连接 — %d 个联系人。点击"刷新"开始轮询', [Length(LContacts)]);
      end;
    end
    else
      ShowWarning('联系人列表为空 — 请检查数据库是否正确解密');

    RefreshStepButtons;
  end);
end;

// ── Commands ───────────────────────────────────────────────────────

procedure TDeepAxisMainForm.DoLaunchWeChat(Sender: TObject);
begin
  var LPid := FWeChatScanner.FindWeChatProcess;
  if LPid = 0 then
  begin
    Log('正在启动微信...');
    FStatusBar.SimpleText := '正在启动微信...';
    Application.ProcessMessages;

    if not FWeChatScanner.LaunchWeChat then
    begin
      ShowWarning('无法启动微信！请检查路径: ' + TDeepAxisConfig.GetWeChatPath);
      Log('无法启动微信，请手动启动');
      Exit;
    end;
    Log('微信正在启动，请扫码登录...');
    ShowWarning('请在弹出的微信窗口中扫码登录，登录后点击"2. 扫描密钥"');
  end
  else
  begin
    Log('微信已在运行 (PID: ' + IntToStr(LPid) + ')');
    HideWarning;
    FStatusBar.SimpleText := '微信已运行 — 请点击"2. 扫描密钥"';
  end;
  RefreshStepButtons;
end;

procedure TDeepAxisMainForm.OnKeyMonitorTimer(Sender: TObject);
begin
  SafeRun('密钥监控', procedure
  begin
    Inc(FKeyMonitorAttempts);

    if FKeyMonitorAttempts > 60 then
    begin
      FKeyMonitorTimer.Enabled := False;
      Log('密钥捕获超时，请确保微信已登录后重试');
      Exit;
    end;

    Log('正在扫描密钥... (尝试 ' + IntToStr(FKeyMonitorAttempts) + ')');
    try
      var LResult := FWeChatScanner.StartScan;
      if LResult.IsSuccess then
      begin
        FKeyMonitorTimer.Enabled := False;
        Log('密钥捕获成功！正在解密数据库...');
      end
      else
      begin
        if LResult.ErrorMessage <> '' then
          Log('扫描结果: ' + LResult.ErrorMessage)
        else
          Log('等待用户登录...');
      end;
    except
      on E: Exception do Log('扫描异常: ' + E.Message);
    end;
  end);
end;

procedure TDeepAxisMainForm.DoConnectDecrypted(Sender: TObject);
begin
  var LContactPath := FWeChatScanner.DecryptedContactPath;
  var LMessagePath := FWeChatScanner.DecryptedMessage0Path;
  var LSessionPath := FWeChatScanner.DecryptedSessionPath;

  if (LContactPath = '') or (LMessagePath = '') then
  begin
    ShowWarning('未找到解密数据库。请先点击"2. 扫描密钥"');
    Log('连接失败: 无解密数据');
    Exit;
  end;

  Log('连接解密数据库...');
  FStatusBar.SimpleText := '正在连接解密数据库...';
  Application.ProcessMessages;

  StopPolling;
  if FWeChatReader.OpenPaths(LContactPath, LMessagePath, LSessionPath) then
  begin
    HideWarning;
    FRadarPanel.SetWeChatConnected(True);
    Log('已连接解密数据库');
    FStatusBar.SimpleText := '已连接 — 请点击"4. 读取联系人"';
    StartPolling;
  end
  else
  begin
    ShowWarning('数据库连接失败！请检查密钥是否正确');
    Log('连接失败: 无法打开数据库');
  end;
  RefreshStepButtons;
end;

procedure TDeepAxisMainForm.DoRefreshData(Sender: TObject);
begin if FDBPollerThread <> nil then FDBPollerThread.ForcePoll; end;

procedure TDeepAxisMainForm.DoToggleLayout(Sender: TObject);
begin
  case FCurrentLayout of
    dlCompact: ApplyLayout(dlDock); dlDock: ApplyLayout(dlFullScreen); dlFullScreen: ApplyLayout(dlCompact);
  end;
end;

procedure TDeepAxisMainForm.DoSetWeChatDataPath(Sender: TObject);
var LDialog: TFileOpenDialog; LPath: string;
begin
  LDialog := TFileOpenDialog.Create(Self);
  try
    LDialog.Title := '选择微信原始数据目录（加密数据库所在位置）';
    LDialog.Options := [fdoPickFolders, fdoPathMustExist, fdoForceFileSystem];
    LPath := TDeepAxisConfig.GetWeChatDataPath;
    if TDirectory.Exists(LPath) then LDialog.DefaultFolder := LPath;
    if LDialog.Execute then
    begin
      LPath := LDialog.FileName;
      TDeepAxisConfig.SetWeChatDataPath(LPath);
      Log('已设置微信数据目录: ' + LPath);
      MessageDlg('微信数据目录已保存。此目录用于密钥捕获和解密操作。',
        mtInformation, [mbOK], 0);
    end;
  finally
    LDialog.Free;
  end;
end;

procedure TDeepAxisMainForm.DoSettings(Sender: TObject);
var
  LSetup: TDeepAxisSetupForm;
begin
  LSetup := TDeepAxisSetupForm.Create(Self);
  try
    if LSetup.ShowModal = mrOk then
    begin
      Log('设置已保存: ' + TDeepAxisConfig.GetWeChatDataPath);
      // Retry connection with new path
      if FWeChatScanner.TrySavedKeysOnly then
      begin
        var LCP := FWeChatScanner.DecryptedContactPath;
        var LMP := FWeChatScanner.DecryptedMessage0Path;
        var LSP := FWeChatScanner.DecryptedSessionPath;
        if (LCP <> '') and (LMP <> '') then
        begin
          StopPolling;
          if FWeChatReader.OpenPaths(LCP, LMP, LSP) then
          begin
            FRadarPanel.SetWeChatConnected(True);
            Log('已重新连接微信数据');
            StartPolling;
          end;
        end;
      end;
      RefreshStepButtons;
    end;
  finally
    LSetup.Free;
  end;
end;

procedure TDeepAxisMainForm.DoAbout(Sender: TObject);
begin
  MessageDlg(APP_TITLE + ' ' + APP_TITLE_ZH + #13#10 +
    '版本: ' + APP_VERSION + #13#10#13#10 +
    'WeChat CRM 与销售辅助工具' + #13#10 +
    '基于微信 4.1.10.53 数据库解密技术',
    mtInformation, [mbOK], 0);
end;

// ── Send workflow ──────────────────────────────────────────────────

procedure TDeepAxisMainForm.UpdateWorkflow;
begin
  if FRadarPanel.SelectedContactIndex < 0 then Exit;
end;

procedure TDeepAxisMainForm.DoPasteScriptInner(const AScript: string);
var
  LScript: string;
  LBoundary: TBoundaryResult;
  LContact: TContact;
  LItemId: string;
begin
  if not TDeepAxisProfile.IsWeChatM3UiaPaste then
  begin Log('当前 Profile 未启用微信 UIA 粘贴能力'); Exit; end;

  if not FRadarPanel.TryGetSelectedContact(LContact) then
  begin Log('未选择可验证联系人，已取消粘贴'); Exit; end;

  if AScript <> '' then
    LScript := AScript
  else
    LScript := FScriptPanel.GetCurrentScript;
  if LScript = '' then begin Log('无话术可粘贴'); Exit; end;

  LBoundary := FBoundaryEngine.CheckScript(LScript, LContact);
  case LBoundary.Classification of
    bcRed:    begin Log('话术被禁止: ' + LBoundary.Reason); Exit; end;
    bcYellow: begin Log('话术需人工确认，当前版本未执行粘贴: ' + LBoundary.Reason); Exit; end;
    bcGreen:  Log('话术通过审核');
  end;

  LItemId := FSendQueue.Enqueue(LContact.ContactId, LContact.DisplayNameRedacted,
    LScript, LBoundary.Classification);
  FSendQueuePanel.Refresh;

  var LUiaResult := FUiaEngine.PasteScript(LScript);
  if LUiaResult.Success then
  begin
    FSendQueue.UpdateStatus(LItemId, ssSent, '');
    Log('已粘贴到微信输入框，请按 Enter 发送');
  end
  else
  begin
    FSendQueue.UpdateStatus(LItemId, ssFailed, LUiaResult.ErrorMessage);
    Log('粘贴失败: ' + LUiaResult.ErrorMessage);
  end;
  FSendQueuePanel.Refresh;
end;

procedure TDeepAxisMainForm.DoPasteScript(const AScript: string);
begin
  SafeRun('粘贴话术', procedure begin DoPasteScriptInner(AScript) end);
end;

procedure TDeepAxisMainForm.DoSkipContact;
begin Log('已跳过当前联系人'); DoRefreshData(nil); end;

procedure TDeepAxisMainForm.DoNextVariant;
begin FScriptPanel.NextVariant; end;

procedure TDeepAxisMainForm.DoPrevVariant;
begin FScriptPanel.PrevVariant; end;

procedure TDeepAxisMainForm.DoVariant1;
begin var I: Integer; for I := 0 to 0 do FScriptPanel.NextVariant; end;

procedure TDeepAxisMainForm.DoVariant2;
begin var I: Integer; for I := 0 to 1 do FScriptPanel.NextVariant; end;

procedure TDeepAxisMainForm.DoVariant3;
begin var I: Integer; for I := 0 to 2 do FScriptPanel.NextVariant; end;

// ── Polling ────────────────────────────────────────────────────────

procedure TDeepAxisMainForm.StartPolling;
begin
  if FDBPollerThread <> nil then Exit;
  FDBPollerThread := TDBPollerThread.Create(FWeChatReader, FMetricCalculator, FRadarEngine, FEvidenceBuilder, FTagEngine, FIdleFunnel);
  FDBPollerThread.OnDataReady := OnPollResultReady;
  FDBPollerThread.Start;
end;

procedure TDeepAxisMainForm.StopPolling;
begin
  if FDBPollerThread <> nil then
  begin
    FDBPollerThread.OnDataReady := nil;
    FDBPollerThread.Terminate;
    FDBPollerThread.ForcePoll;
    FDBPollerThread.WaitFor;
    TThread.RemoveQueuedEvents(FDBPollerThread);
    FDBPollerThread.Free;
    FDBPollerThread := nil;
  end;
end;

procedure TDeepAxisMainForm.OnPollResultReady(Sender: TObject; const AData: TPollResult);
var LContact: TContact; LContactFound: Boolean; I: Integer;
begin
  FRadarPanel.SetData(AData);
  FTagMatrixPanel.SetContacts(AData.Contacts);
  if Length(AData.Hints) > 0 then
  begin
    LContact := Default(TContact); LContactFound := False;
    for I := 0 to Length(AData.Contacts) - 1 do
      if AData.Contacts[I].ContactId = AData.Hints[0].ContactId then
      begin LContact := AData.Contacts[I]; LContactFound := True; Break; end;

    if LContactFound then
    begin
      FScriptPanel.GenerateFor(LContact, AData.Hints[0].HintType);
      var LBoundary := FBoundaryEngine.CheckScript(FScriptPanel.GetCurrentScript, LContact);
      FStatusBar.SimpleText := LBoundary.ToEmoji + ' ' + LBoundary.ToChinese + ' | ' + FSendQueue.GetSummary;
    end;
  end;
  FStatusBar.SimpleText := Format('更新: %d条消息, %d条提示 | %s', [AData.NewMessageCount, Length(AData.Hints), FSendQueue.GetSummary]);
end;

procedure TDeepAxisMainForm.OnScannerStateChanged(const AState: TWeChatProcessState);
begin
  Log(WeChatStateToStr(AState));
  FStatusBar.SimpleText := WeChatStateToStr(AState);
  case AState of
    wpsKeyVerified:
      begin
        HideWarning;
        var LCP := FWeChatScanner.DecryptedContactPath;
        var LMP := FWeChatScanner.DecryptedMessage0Path;
        var LSP := FWeChatScanner.DecryptedSessionPath;
        if (LCP <> '') and (LMP <> '') then
        begin
          StopPolling;
          if FWeChatReader.OpenPaths(LCP, LMP, LSP) then
          begin FRadarPanel.SetWeChatConnected(True); Log('密钥验证成功！开始分析...'); StartPolling; end;
        end;
      end;
    wpsFailed: ShowWarning('密钥获取失败 — 请确保微信已登录');
  end;
  RefreshStepButtons;
end;

procedure TDeepAxisMainForm.Log(const AMsg: string);
var LLine: string;
begin
  LLine := DateTimeToStr(Now) + ' ' + AMsg;
  FLogMemo.Lines.Add(LLine);

  if not GLogFileInitialized then
  begin
    GLogFilePath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'DeepAxis.log');
    AssignFile(GLogFile, GLogFilePath);
    if TFile.Exists(GLogFilePath) then Append(GLogFile) else Rewrite(GLogFile);
    GLogFileInitialized := True;
  end;

  try Writeln(GLogFile, LLine); Flush(GLogFile); except end;
end;

end.