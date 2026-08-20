unit DeepAxis.UI.MainForm;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils, System.Math,
  System.Hash,
  Winapi.Windows, Winapi.Messages, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.ComCtrls, Vcl.Dialogs,
  Vcl.Graphics,
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Phys.SQLite,
  FireDAC.Comp.UI, FireDAC.VCLUI.Wait,
  DeepBase.AIErrorHandler,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.Core.Audit,
  DeepAxis.Core.Config, DeepAxis.Core.Profile, DeepAxis.Core.Governance,
  DeepAxis.WeChat.Adapter, DeepAxis.WeChat.Adapter411053,
  DeepAxis.WeChat.Reader, DeepAxis.WeChat.Decrypt, DeepAxis.WeChat.Scanner,
  DeepAxis.Pipeline.Metrics, DeepAxis.Pipeline.Radar, DeepAxis.Pipeline.Evidence,
  DeepAxis.Pipeline.TagEngine, DeepAxis.Pipeline.TagManager, DeepAxis.Pipeline.IdleFunnel,
  DeepAxis.Pipeline.StateMachine, DeepAxis.Pipeline.Boundary,
  DeepAxis.Pipeline.ScriptEngine, DeepAxis.Pipeline.SendQueue,
  DeepAxis.Pipeline.Calibration, DeepAxis.Pipeline.AdTracker,
  DeepAxis.Pipeline.ContactOverlay,
  DeepAxis.Pipeline.SendResultPoller,
  DeepAxis.Pipeline.ChurnDetector,  // ← NEW: Churn detection engine
  DeepAxis.UI.RadarPanel, DeepAxis.UI.TierPanel, DeepAxis.UI.TagMatrixPanel,
  DeepAxis.UI.ScriptPanel, DeepAxis.UI.SendQueuePanel,
  DeepAxis.UI.IdleFunnelPanel, DeepAxis.UI.TagSuggestPanel, DeepAxis.UI.SetupForm,
  DeepAxis.UIA.Engine, DeepAxis.UIA.ContactOps, DeepAxis.Core.SendModes,
  DeepAxis.Tests.Phases,
  DeepAxis.Core.DataStore.Manager, DeepAxis.Config.DB1,
  DeepAxis.UI.ChurnMonitorPanel;  // ← NEW: Churn Monitor UI panel

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
    FContactOps: TContactOps;
    FResultPoller: TSendResultPoller;
    FDBPollerThread: TDBPollerThread;
    FOverlayStore: TContactOverlayStore;
    FKeyMonitorTimer: TTimer;
    FKeyMonitorAttempts: Integer;
    FRadarPanel: TDeepAxisRadarPanel;
    FTierPanel: TDeepAxisTierPanel;
    FTagMatrixPanel: TDeepAxisTagMatrixPanel;
    FIdleFunnelPanel: TIdleFunnelPanel;
    FTagManager: TTagManager;
    FTagSuggestPanel: TTagSuggestPanel;
    FLastContacts: TArray<TContact>;
    FScriptPanel: TScriptPanel;
    FSendQueuePanel: TSendQueuePanel;
    FChurnMonitorPanel: TChurnMonitorPanel;  // ← NEW: Churn monitor panel
    FChurnDetector: IChurnDetector;  // ← NEW: Churn detection engine
    FCurrentLayout: TDeepAxisLayout;
    FViewModeTier: Boolean;  // True = tier workbench visible, False = radar view
    FWeChatWindowHandle: HWND;
    FWeChatHook: THandle;
    FLogMemo: TMemo;
    FWarningPanel: TPanel;
    FWarningLabel: TLabel;
    FHotKeyIds: array[0..5] of Integer;

    procedure EnterScanMiniMode;
    procedure ExitScanMiniMode;
    procedure FormShowPhase2;
    procedure InitDB2;
    procedure InitBusinessServices;
    procedure InitBusinessServicesWithDB1Stores;
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
    procedure DoToggleView(Sender: TObject);
    procedure DoPasteScript(const AScript: string);
    procedure DoPasteScriptInner(const AScript: string);
    /// <summary>带模式的三模式发送入口 (docs/03 §4.4)。</summary>
    procedure DoPasteScriptWithMode(const AScript: string; AMode: TSendMode);
    procedure DoSkipContact;
    procedure DoNextVariant;
    procedure DoPrevVariant;
    procedure DoVariant1; procedure DoVariant2; procedure DoVariant3;
    procedure DoSettings(Sender: TObject);
    procedure DoAbout(Sender: TObject);
    procedure DoRunPhaseTests(Sender: TObject);
    procedure DoDeleteCandidate(const AContactId: string; AMode: TSendMode);
    /// <summary>L2a 标签建议写回: 经确认框调 FContactOps.UpdateRemarkWithEvidence 追加标准化备注字段 (docs/08 §3.2/§3.3)。</summary>
    procedure ApplyTagSuggestion(const ASuggestion: TTagSuggestion);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
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
  // BUG-041 fix: 默认布局改 dlCompact。原默认 dlDock 在 FormShow 里会立即
  // 设 FScriptPanel.Visible:=True,启动期父句柄链未就绪 → 'no parent window' 崩溃。
  // dlDock 改由用户 Ctrl+L 手动切换 (此时窗口已完全创建，安全)。
  FCurrentLayout := dlCompact;
  FWeChatWindowHandle := 0;
  FWeChatHook := 0;
  FDB2Connection := nil;
  FDBPollerThread := nil;
  FOverlayStore := nil;
  
  // 标准日志: Log() 写入 FLogMemo + DeepAxis.log (GLogFile), 不依赖外部 TLogger
  try
    var LDataStoreMgr := GetDeepAxisDataStoreManager;
    LDataStoreMgr.Initialize;
    Log('✓ DeepBase DataStore initialized');
  except
    on E: Exception do
      Log(Format('✗ Failed to init DataStore: %s', [E.Message]));
  end;
  
  InitDB2;
  InitBusinessServices; // Adapter and Reader initialization
  InitBusinessServicesWithDB1Stores; // Pipeline components with DB1Store
  try
    InitUI;
  except
    on E: Exception do
      Log('InitUI EXCEPTION: ' + E.ClassName + ': ' + E.Message);
  end;
  InitHotKeys;
end;

procedure TDeepAxisMainForm.FormDestroy(Sender: TObject);
var I: Integer;
begin
  // BUG-052 fix: 必须先停轮询线程再释放 store (原顺序颠倒, 轮询线程
  // 可能在 store 释放后仍访问 → Runtime error 217 on close)。
  StopPolling;
  for I := 0 to 5 do
    if FHotKeyIds[I] <> 0 then
      UnregisterHotKey(Handle, FHotKeyIds[I]);
  if FWeChatHook <> 0 then
  begin UnhookWinEvent(FWeChatHook); FWeChatHook := 0; end;

  // Shutdown all DB1Stores (轮询已停, 无并发访问)
  ReleaseDeepAxisDataStoreManager;
  ReleaseDeepAxisConfigDB1;
  
  FDBPollerThread := nil;
  FWeChatScanner.Free;
  FAdapterRegistry.Free;
  FOverlayStore.Free;
  FDB2Connection.Free;
  FFDWait.Free;
  FScriptEngine.Free;
  FBoundaryEngine.Free;
  FSendQueue.Free;
  FCalibrationEngine.Free;
  FUiaEngine.Free;
  FContactOps.Free;
  FResultPoller.Free;
  FTagManager.Free;
  FChurnDetector := nil;  // 接口引用, 置 nil 自动释放
end;

procedure TDeepAxisMainForm.FormShow(Sender: TObject);
begin
  // BUG-041 fix: 启动默认 dlCompact(全部子面板 Visible:=False,不触发句柄创建)。
  // 不在此处立即切 dlDock,避免启动期 'no parent window' 崩溃。用户可手动 Ctrl+L 切换。
  ApplyLayout(dlCompact);
  // BUG-041/050 fix: 父句柄链就绪后, 初始化子面板中句柄敏感控件
  if FScriptPanel <> nil then FScriptPanel.EnsureModeInitialized;
  InitWeChatHook;

  // BUG-041/043 fix: 首次启动向导 + 微信连接/密钥流程延后到下一消息帧。
  // 原在 FormShow 同步执行时,主窗句柄链尚未完全就绪,弹模态 ShowModal 会
  // 触发子控件(TScriptPanel)'no parent window'(经 .map 定位 RVA 0x2163ED
  // → Vcl.Controls.TControl.SetVisible +0xD)。延后后主窗已 WM_SHOW 完毕、
  // 句柄全就绪,ShowModal 与后续 Visible 切换均安全。
  TThread.Queue(nil,
    procedure
    begin
      try
        FormShowPhase2;
      except
        // BUG-050 fix: FormShowPhase2 异常会冒泡到 Application 关闭主窗体。
        // 记录后继续运行, 不让首次启动流程杀死主界面。
        on E: Exception do
          Log('FormShowPhase2 EXCEPTION (已兜底继续): ' + E.ClassName + ': ' + E.Message);
      end;
    end);
end;

procedure TDeepAxisMainForm.FormShowPhase2;
var LPid: Cardinal; LSetup: TDeepAxisSetupForm;
begin
  // ── 首次启动: 弹出配置向导 ──
  if TDeepAxisConfig.GetWeChatDataPath = '' then
  begin
    LSetup := TDeepAxisSetupForm.Create(Self);
    try
      if LSetup.ShowModal = mrOk then
      begin
        Log('初始设置完成: ' + TDeepAxisConfig.GetWeChatDataPath);
        // After wizard, try auto-detect keys
        if FWeChatScanner.TrySavedKeysOnly then
        begin
          HideWarning;
          Log(Format('已加载 %d 个密钥', [FWeChatScanner.KeyManager.GetKeyCount]));
          var LCP2 := FWeChatScanner.DecryptedContactPath;
          var LMP2 := FWeChatScanner.DecryptedMessage0Path;
          var LSP2 := FWeChatScanner.DecryptedSessionPath;
          if (LCP2 <> '') and (LMP2 <> '') and FWeChatReader.OpenPaths(LCP2, LMP2, LSP2) then
          begin
            FRadarPanel.SetWeChatConnected(True); FTierPanel.SetWeChatConnected(True);
            Log('已自动连接微信数据');
            FStatusBar.SimpleText := '已连接 — 正在首次分析...';
            StartPolling;
            FDBPollerThread.ForcePoll;
          end;
        end;
      end
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
        FRadarPanel.SetWeChatConnected(True); FTierPanel.SetWeChatConnected(True);
        Log('已连接微信数据');
        StartPolling;
        FDBPollerThread.ForcePoll;  // immediate first analysis
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
    LQuery.SQL.Text := 'CREATE TABLE IF NOT EXISTS ' + DB2_TABLE_AUDIT + ' (audit_id TEXT PRIMARY KEY, event_type INTEGER NOT NULL, previous_audit_hash TEXT, source_account_id TEXT, data_categories TEXT, body_columns_seen INTEGER DEFAULT 0, body_columns_queried INTEGER DEFAULT 0, write_attempts INTEGER DEFAULT 0, uia_calls INTEGER DEFAULT 0, created_at DATETIME)'; LQuery.ExecSQL;
    LQuery.SQL.Text := 'CREATE TABLE IF NOT EXISTS ' + DB2_TABLE_CURSORS + ' (contact_id TEXT PRIMARY KEY, last_local_id INTEGER DEFAULT 0)'; LQuery.ExecSQL;
  finally LQuery.Free; end;
  // 本地 DB1 contact overlay 读写器 (复用已建 contacts 表; #74 ad_track 持久化)
  FOverlayStore := TContactOverlayStore.Create(FDB2Connection);
end;

procedure TDeepAxisMainForm.InitBusinessServices;
begin
  FAdapterRegistry := TSchemaAdapterRegistry.Create;
  FSchemaAdapter := TWeChat411053Adapter.Create;
  FAdapterRegistry.RegisterAdapter(FSchemaAdapter);
  FWeChatReader := TWeChatReader.Create(FSchemaAdapter);
  
  // Initialize Pipeline components with DB1Store injection (moved to new procedure)
end;

procedure TDeepAxisMainForm.InitBusinessServicesWithDB1Stores;
var
  LDataStoreMgr: TDeepAxisDataStoreManager;
begin
  LDataStoreMgr := GetDeepAxisDataStoreManager;
  
  // Initialize Pipeline components with DB1Store injection
  FMetricCalculator := TMetricCalculator.Create(True, LDataStoreMgr.MetricStore);
  FRadarEngine := TRadarEngine.Create(True, LDataStoreMgr.RadarHintStore);
  FEvidenceBuilder := TEvidenceBuilder.Create(True, LDataStoreMgr.EvidenceStore);
  FTagEngine := TTagEngine.Create; // TODO: Add tag profile persistence later
  FTagManager := TTagManager.Create;
  FIdleFunnel := TIdleFunnel.Create;
  FStateMachine := TContactStateMachine.Create;
  FScriptEngine := TScriptEngine.Create;
  FBoundaryEngine := TBoundaryEngine.Create;
  FSendQueue := TSendQueue.Create;
  FCalibrationEngine := TCalibrationEngine.Create;
  FUiaEngine := TUiaEngine.Create;
  FContactOps := TContactOps.Create(FUiaEngine);
  // Poller getter: 走 IWxReader.GetSessionLastMessageTime (session.last_message_time 推进判定)
  // Reader 未开/未找到/异常时返回 0 → Poller 判 srUnknown (宁缺勿造，不臆测成功)
  FResultPoller := TSendResultPoller.Create(
    function(const AContactId: string): Int64
    begin
      Result := 0;
      if (FWeChatReader <> nil) and FWeChatReader.IsOpen then
        Result := FWeChatReader.GetSessionLastMessageTime(AContactId);
    end, 8000, 1000);
  FWeChatScanner := TWeChatScanner.Create;
  FWeChatScanner.OnStateChanged := OnScannerStateChanged;
  // FOverlayStore 已在 InitDB2 用 FDB2Connection 创建 (contact overlay 读写器)

  // ← NEW: Initialize churn detection system (Decision #1 in IDOC)
  FChurnDetector := TChurnDetector.Create(LDataStoreMgr.ChurnMonitorStore);
  FChurnDetector.Initialize;

  Log('✓ All pipeline components initialized with DB1Store backing');
  Log('✓ Churn detection engine initialized');
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
  // BUG-052: 启动即小窗 (560×220, 只显示按钮+日志, 不挡其它操作);
  // 解密成功后才放大到全尺寸 (见 DoConnectDecrypted → EnlargeAfterDecrypt)。
  Width := 560; Height := 220;
  KeyPreview := True;
  OnKeyDown := FormKeyDown;

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
  LItem := TMenuItem.Create(Self); LItem.Caption := '分级视图/雷达视图'; LItem.ShortCut := TextToShortCut('Ctrl+T'); LItem.OnClick := DoToggleView; LMenuView.Add(LItem);

  LMenuData := TMenuItem.Create(Self); LMenuData.Caption := '数据'; FMainMenu.Items.Add(LMenuData);
  LItem := TMenuItem.Create(Self); LItem.Caption := '刷新数据'; LItem.OnClick := DoRefreshData; LMenuData.Add(LItem);

  LMenuOther := TMenuItem.Create(Self); LMenuOther.Caption := '其它'; FMainMenu.Items.Add(LMenuOther);
  LItem := TMenuItem.Create(Self); LItem.Caption := '设置'; LItem.OnClick := DoSettings; LMenuOther.Add(LItem);
  LItem := TMenuItem.Create(Self); LItem.Caption := '-'; LMenuOther.Add(LItem);
  LItem := TMenuItem.Create(Self); LItem.Caption := '运行阶段测试 (1-5)'; LItem.OnClick := DoRunPhaseTests; LMenuOther.Add(LItem);
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
  FRadarPanel := TDeepAxisRadarPanel.Create(Self);
  FRadarPanel.Parent := Self;
  FRadarPanel.Align := alClient;

  // Tier workbench (main area, toggle view — contact-centric vs hint-centric)
  FTierPanel := TDeepAxisTierPanel.Create(Self);
  FTierPanel.Parent := Self;
  FTierPanel.Align := alClient;
  FTierPanel.Visible := False;
  FViewModeTier := False;

  // Script panel (right)
  FScriptPanel := TScriptPanel.Create(Self);
  FScriptPanel.Parent := Self;
  FScriptPanel.Align := alRight;
  FScriptPanel.OnPasteWithMode := DoPasteScriptWithMode;
  FScriptPanel.OnSkip := DoSkipContact;

  // Send queue panel (bottom)
  FSendQueuePanel := TSendQueuePanel.Create(Self); FSendQueuePanel.Parent := Self; FSendQueuePanel.Align := alBottom; FSendQueuePanel.Height := 150; FSendQueuePanel.Visible := False;
  FSendQueuePanel.SetQueue(FSendQueue);

  // Tag matrix (bottom)
  FTagMatrixPanel := TDeepAxisTagMatrixPanel.Create(Self); FTagMatrixPanel.Parent := Self; FTagMatrixPanel.Align := alBottom; FTagMatrixPanel.Height := 250; FTagMatrixPanel.Visible := False;

  // Idle funnel (候选删除, 全屏布局显示)
  FIdleFunnelPanel := TIdleFunnelPanel.Create(Self); FIdleFunnelPanel.Parent := Self; FIdleFunnelPanel.Align := alBottom; FIdleFunnelPanel.Height := 200; FIdleFunnelPanel.Visible := False;
  FIdleFunnelPanel.OnDeleteCandidate := DoDeleteCandidate;

  // Tag suggest (L0-L1 标签/备注整理建议，全屏布局显示)
  FTagSuggestPanel := TTagSuggestPanel.Create(Self); FTagSuggestPanel.Parent := Self; FTagSuggestPanel.Align := alBottom; FTagSuggestPanel.Height := 200; FTagSuggestPanel.Visible := False;
  FTagSuggestPanel.OnApplySuggestion := ApplyTagSuggestion;
  
  // ← NEW: Churn monitor panel (Decision #1 in IDOC - lead with USP!)
  FChurnMonitorPanel := TChurnMonitorPanel.Create(Self);
  FChurnMonitorPanel.Parent := Self;
  FChurnMonitorPanel.Align := alRight;
  FChurnMonitorPanel.Width := 450;
  FChurnMonitorPanel.Visible := True;  // Always visible for beta testing
  FChurnMonitorPanel.ChurnDetector := FChurnDetector;  // Connect churn engine
  
  Log('✓ Churn Monitor Panel integrated into MainForm layout');
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
  // BUG-041 fix: 注册热键需访问 Self.Handle,会触发 MainForm 句柄提前创建;
  // 此时子控件(如 FScriptPanel)的父句柄链尚未就绪,后续 ApplyLayout 设
  // Visible:=True 会抛 'no parent window' → 二次 AccessViolation(乱码弹窗)。
  // 推迟到下一消息帧(窗口已完整创建后再注册)。
  TThread.Queue(nil,
    procedure
    begin
      if FHotKeyIds[0] = 0 then Exit;  // Form 已销毁则跳过
      RegisterHotKey(Handle, WM_HOTKEY_SPACE, MOD_CONTROL or MOD_SHIFT, Ord(' '));
      RegisterHotKey(Handle, WM_HOTKEY_ESC,   MOD_CONTROL or MOD_SHIFT, Ord('S'));
      RegisterHotKey(Handle, WM_HOTKEY_VAR1,  MOD_CONTROL or MOD_SHIFT, Ord('1'));
      RegisterHotKey(Handle, WM_HOTKEY_VAR2,  MOD_CONTROL or MOD_SHIFT, Ord('2'));
      RegisterHotKey(Handle, WM_HOTKEY_VAR3,  MOD_CONTROL or MOD_SHIFT, Ord('3'));
      RegisterHotKey(Handle, WM_HOTKEY_LAYOUT, MOD_CONTROL, Ord('L'));
    end);
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
  // BUG-041 fix: 启动期子面板父句柄链未就绪时设 Visible 可能抛
  // EInvalidOperation 'no parent window'。SafeSetVisible 兜住降级记日志,
  // 不阻断布局流程。(实测 ApplyLayout 本身未抛——真凶在 FormShow 的
  // 模态向导 ShowModal,见 FormShow 的 Queue 延迟修复。此处保留为兜底。)
  procedure SafeSetVisible(AControl: TControl; AVisible: Boolean);
  begin
    if AControl = nil then Exit;
    try
      AControl.Visible := AVisible;
    except
      on E: EInvalidOperation do
        Log('布局跳过可见性切换(EInvalidOperation): ' + E.Message);
    end;
  end;
begin
  FCurrentLayout := ALayout;
  case ALayout of
    // BUG-052 fix: dlCompact 不再压扁主窗 (原 Height:=120 导致启动窗口仅 3-4cm)。
    // dlCompact 语义 = 仅隐藏扩展面板, 保留主窗尺寸 (启动时由 InitUI 决定)。
    dlCompact:    begin SafeSetVisible(FScriptPanel, False); SafeSetVisible(FTagMatrixPanel, False); SafeSetVisible(FIdleFunnelPanel, False); SafeSetVisible(FTagSuggestPanel, False); end;
    dlDock:       begin Width := DEEPAXIS_STRIP_WIDTH; Height := 1000; SafeSetVisible(FScriptPanel, True); SafeSetVisible(FTagMatrixPanel, False); SafeSetVisible(FIdleFunnelPanel, False); SafeSetVisible(FTagSuggestPanel, False); DockToWeChatWindow; end;
    dlFullScreen: begin WindowState := wsMaximized; SafeSetVisible(FScriptPanel, True); SafeSetVisible(FTagMatrixPanel, True); SafeSetVisible(FIdleFunnelPanel, True); SafeSetVisible(FTagSuggestPanel, True); end;
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
  // BUG-041 fix: 启动期主窗句柄未就绪时 Visible:=True 会崩 (见 ApplyLayout 注释)
  try
    FWarningPanel.Visible := True;
  except
    on E: EInvalidOperation do
      Log('警告面板可见性跳过: ' + E.Message);
  end;
  FStatusBar.SimpleText := AMsg;
end;

procedure TDeepAxisMainForm.HideWarning;
begin
  FWarningPanel.Visible := False;
end;

// ── Step operations ────────────────────────────────────────────────

procedure TDeepAxisMainForm.EnterScanMiniMode;
begin
  // BUG-052: 确保扫描期间小窗 (启动即 560×220; 若用户手动放大过则临时缩回)
  if WindowState = wsMaximized then
    WindowState := wsNormal;
  if (Width > 560) or (Height > 220) then
  begin
    Width := 560;
    Height := 220;
  end;
  FStatusBar.SimpleText := '正在扫描密钥... (完成后自动恢复窗口)';
end;

procedure TDeepAxisMainForm.ExitScanMiniMode;
begin
  // BUG-052: 解密成功后的放大 — 恢复全尺寸 (1600×1000)。
  Width := 1600;
  Height := 1000;
  // 移到屏幕中央
  Left := (Screen.WorkAreaRect.Right - Screen.WorkAreaRect.Left - Width) div 2;
  Top := (Screen.WorkAreaRect.Bottom - Screen.WorkAreaRect.Top - Height) div 2;
end;

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

    // BUG-052: 启动即小窗, 扫描期间保持小窗不挡操作; 无需在此缩窗
    Log('开始扫描内存密钥...');
    FStatusBar.SimpleText := '正在扫描密钥...';
    Application.ProcessMessages;

    // BUG-052 fix: 先内存扫描 (不重启微信)。失败后询问用户是否允许
    // HybridTap (会杀进程重启微信, 打断已登录会话)。
    var LResult := FWeChatScanner.StartScan(False);
    if (not LResult.IsSuccess) and (FWeChatScanner.FindWeChatProcess <> 0) then
    begin
      // 内存扫描失败 → 提示用户可选重启抓取
      var LMsg := LResult.ErrorMessage + #13#10#13#10 +
        '是否允许重启微信 (HybridTap 抓密钥)?' + #13#10 +
        '重启会打断当前登录会话, 需重新扫码登录。';
      if Application.MessageBox(PChar(LMsg), '密钥抓取需重启微信',
        MB_YESNO or MB_ICONQUESTION) = ID_YES then
      begin
        Log('用户允许重启微信, 走 HybridTap...');
        LResult := FWeChatScanner.StartScan(True);
      end
      else
      begin
        Log('用户拒绝重启微信: ' + LResult.ErrorMessage);
        ShowWarning('密钥扫描未成功: ' + LResult.ErrorMessage);
        RefreshStepButtons;
        Exit;
      end;
    end;

    if LResult.IsSuccess then
    begin
      HideWarning;
      Log('密钥捕获成功！');
      FStatusBar.SimpleText := '密钥已就绪 — 请点击"3. 连接解密"';
      // BUG-051 #83: 审计 — 密钥扫描成功
      AuditAppend(aetScan, 'wechat-scan', ['key_scan'], False, False);
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
        FRadarPanel.SetWeChatConnected(True); FTierPanel.SetWeChatConnected(True);
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

    // BUG-052 fix: 自动监控只试 2 次 (登录等待), 失败即停 —
    // 旧实现每 3 秒全量读微信内存循环 60 次, UI 卡死 + 弹确认框。
    if FKeyMonitorAttempts > 2 then
    begin
      FKeyMonitorTimer.Enabled := False;
      Log('自动密钥监控已停止 — 请登录微信后点击"2. 扫描密钥"');
      ShowWarning('请确保微信已登录，然后点击"2. 扫描密钥"手动触发');
      Exit;
    end;

    Log('正在扫描密钥... (自动尝试 ' + IntToStr(FKeyMonitorAttempts) + '/2)');
    try
      var LResult := FWeChatScanner.StartScan;
      if LResult.IsSuccess then
      begin
        FKeyMonitorTimer.Enabled := False;
        Log('密钥捕获成功！自动连接解密数据库...');
        FStatusBar.SimpleText := '密钥已捕获 — 自动连接中...';
        Application.ProcessMessages;
        DoConnectDecrypted(nil);
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
    // BUG-052: 解密成功 → 放大窗口到全尺寸 (启动小窗至此结束)
    ExitScanMiniMode;
    FRadarPanel.SetWeChatConnected(True); FTierPanel.SetWeChatConnected(True);
    Log('已连接解密数据库');
    FStatusBar.SimpleText := '已连接 — 正在首次分析...';
    StartPolling;
    FDBPollerThread.ForcePoll;  // immediate first analysis instead of waiting 30s
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

procedure TDeepAxisMainForm.DoToggleView(Sender: TObject);
begin
  FViewModeTier := not FViewModeTier;
  FTierPanel.Visible := FViewModeTier;
  FRadarPanel.Visible := not FViewModeTier;
  if FViewModeTier then
  begin
    FTierPanel.BringToFront;
    FTierPanel.SetWeChatConnected(FRadarPanel.IsConnected);
  end
  else
    FRadarPanel.BringToFront;
  if FViewModeTier then
    Log('视图: 分级工作台')
  else
    Log('视图: 雷达提示');
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
            FRadarPanel.SetWeChatConnected(True); FTierPanel.SetWeChatConnected(True);
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

procedure TDeepAxisMainForm.DoRunPhaseTests(Sender: TObject);
var
  LTests: TPhaseTests;
  LResult: string;
begin
  LTests := TPhaseTests.Create;
  try
    LResult := LTests.RunAll;
  finally
    LTests.Free;
  end;
  Log(LResult);
  // 失败时弹窗提醒
  if Pos('FAIL 0', LResult) = 0 then
    MessageDlg(LResult, mtWarning, [mbOK], 0)
  else
    MessageDlg(LResult, mtInformation, [mbOK], 0);
end;

procedure TDeepAxisMainForm.DoDeleteCandidate(const AContactId: string; AMode: TSendMode);
var
  LContact: TContact;
  LFound: Boolean;
  I: Integer;
  LAll: TArray<TContact>;
  LEvidence: TContactOpEvidence;
begin
  // 从缓存找联系人 (用于显示名 + 候选确认)
  LFound := False;
  LContact := Default(TContact);
  LAll := FLastContacts;
  for I := 0 to Length(LAll) - 1 do
    if LAll[I].ContactId = AContactId then
    begin LContact := LAll[I]; LFound := True; Break; end;

  if not LFound then
  begin Log('未找到联系人: ' + AContactId); Exit; end;

  if AMode = smAssist then
  begin
    // 仅生成建议: 不触发 UIA, 仅记录
    Log(Format('已生成删除建议: %s (关联产品 %d, 闲人=%s)',
      [LContact.DisplayNameRedacted, LContact.ProductCount, BoolToStr(LContact.IsIdle, True)]));
    Exit;
  end;

  // smFinal: 执行 UIA 删除 (需 Profile 开关 + 最终模式确认)
  if not TDeepAxisProfile.IsWeChatFinalSend then
  begin Log('当前 Profile 未启用最终发送, 无法执行删除'); Exit; end;

  if Application.MessageBox(
    PChar(Format('确认删除联系人 %s? 此操作将调用微信 UIA 执行删除。', [LContact.DisplayNameRedacted])),
    '最终删除确认', MB_YESNO or MB_ICONWARNING) <> ID_YES then
  begin Log('用户取消删除'); Exit; end;

  LEvidence := FContactOps.DeleteWithEvidence(AContactId);
  if LEvidence.Success then
  begin
    Log(Format('已删除联系人: %s', [LContact.DisplayNameRedacted]));
    // BUG-051 #83: 审计 — 删除成功
    AuditAppend(aetDeletion, 'wechat-delete', ['contact_delete'], False, False, 0, 1);
  end
  else
  begin
    // #76 降级: UIA 删除失败属预期 (强依赖微信版本逆向), 自动降级为"仅建议手动删除"
    // 面板标状态列 + Log 提示手动, 避免用户反复尝试注定失败的 UIA 操作
    if Assigned(FIdleFunnelPanel) then
      FIdleFunnelPanel.MarkDeleteFailed(AContactId, LEvidence.ErrorMessage);
    if LEvidence.CircuitTripped then
      Log(Format('删除失败: %s [熔断触发] — 已降级为仅建议, 请在微信手动删除 %s',
        [LEvidence.ErrorMessage, LContact.DisplayNameRedacted]))
    else
      Log(Format('删除失败: %s — 已降级为仅建议, 请在微信手动删除 %s (UIA 强依赖微信版本, 失败属预期)',
        [LEvidence.ErrorMessage, LContact.DisplayNameRedacted]));
  end;
end;

procedure TDeepAxisMainForm.ApplyTagSuggestion(const ASuggestion: TTagSuggestion);
var
  LContact: TContact;
  LFound: Boolean;
  I: Integer;
  LValue, LOrigRemark, LNewRemark: string;
  LEvidence: TContactOpEvidence;
begin
  // docs/08 §3.2: 不自动写备注 (必须用户确认) → 最终模式守卫 + 确认框
  if not TDeepAxisProfile.IsWeChatFinalSend then
  begin Log('当前 Profile 未启用最终发送, L2a 写回需最终模式'); Exit; end;

  // 反查原 Contact 取 Remark (追加基础)
  LFound := False;
  LContact := Default(TContact);
  for I := 0 to Length(FLastContacts) - 1 do
    if FLastContacts[I].ContactId = ASuggestion.ContactId then
    begin LContact := FLastContacts[I]; LFound := True; Break; end;
  if not LFound then
  begin Log(Format('L2a 写回失败: 联系人 %s 不在当前缓存, 请刷新数据后重试', [ASuggestion.ContactId])); Exit; end;

  LOrigRemark := LContact.Remark;
  LValue := ASuggestion.Value;

  // add 类 (空备注, 无预设值) → 弹框让用户填
  if LValue = '' then
  begin
    if not InputQuery('L2a 备注补全', Format('为联系人 %s 输入备注内容:', [LContact.DisplayNameRedacted]), LValue) then
    begin Log('用户取消备注补全'); Exit; end;
    if LValue = '' then
    begin Log('备注补全内容为空, 跳过'); Exit; end;
  end;

  // 构造新备注 (字段级去重: 同字段已存在则原样返回)
  LNewRemark := TTagManager.BuildAppendRemark(LOrigRemark, ASuggestion.Field, LValue);
  if LNewRemark = LOrigRemark then
  begin Log(Format('L2a 跳过: 联系人 %s 备注已含字段 ┊%s:, 不重复写入', [LContact.DisplayNameRedacted, ASuggestion.Field])); Exit; end;

  // 确认框 (不修改用户原文, 仅展示追加片段)
  if Application.MessageBox(
    PChar(Format('确认修改 %s 的备注?%s%s原: %s%s新: %s%s%s(┊ 之前内容不改动)',
      [LContact.DisplayNameRedacted, sLineBreak, sLineBreak, LOrigRemark, sLineBreak, LOrigRemark, sLineBreak, LNewRemark.Substring(Length(LOrigRemark))])),
    'L2a 写回确认', MB_YESNO or MB_ICONQUESTION) <> ID_YES then
  begin Log('用户取消 L2a 写回'); Exit; end;

  LEvidence := FContactOps.UpdateRemarkWithEvidence(ASuggestion.ContactId, LNewRemark);
  if LEvidence.Success then
    Log(Format('L2a 已写回备注: %s (┊%s:%s)', [LContact.DisplayNameRedacted, ASuggestion.Field, LValue]))
  else
  begin
    if LEvidence.CircuitTripped then
      Log(Format('L2a 写回失败: %s [熔断触发] (UIA 强依赖微信版本, 失败属预期降级)', [LEvidence.ErrorMessage]))
    else
      Log(Format('L2a 写回失败: %s (UIA 强依赖微信版本, 失败属预期降级)', [LEvidence.ErrorMessage]));
  end;
end;

// ── Keyboard shortcuts ─────────────────────────────────────────────

procedure TDeepAxisMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // F1-F5: step buttons
  case Key of
    VK_F1: begin DoLaunchWeChat(Sender); Key := 0; end;
    VK_F2: begin DoScanKey(Sender); Key := 0; end;
    VK_F3: begin DoConnectDecrypted(Sender); Key := 0; end;
    VK_F4: begin DoReadContacts(Sender); Key := 0; end;
    VK_F5: begin DoRefreshData(Sender); Key := 0; end;
    Ord('F'):
      if ssCtrl in Shift then
      begin
        // Ctrl+F: focus search in RadarPanel
        if FRadarPanel <> nil then
          FRadarPanel.FocusSearch;
        Key := 0;
      end;
  end;
end;

// ── Send workflow ──────────────────────────────────────────────────

procedure TDeepAxisMainForm.UpdateWorkflow;
begin
  if FRadarPanel.SelectedContactIndex < 0 then Exit;
end;

procedure TDeepAxisMainForm.DoPasteScriptInner(const AScript: string);
begin
  // 向后兼容: 热键/旧调用入口默认走辅助模式
  DoPasteScriptWithMode(AScript, smAssist);
end;

procedure TDeepAxisMainForm.DoPasteScriptWithMode(const AScript: string; AMode: TSendMode);
var
  LScript: string;
  LBoundary: TBoundaryResult;
  LContact: TContact;
  LItemId: string;
  LEvidence: TSendEvidence;
  LNeedPaste: Boolean;
  LNeedEnter: Boolean;
  LUiaResult: TUiaResult;
  LBaseline: Int64;
  LConfirmMsg: string;
begin
  // 能力开关: 辅助/最终需 UIA 粘贴; 手动不需要
  if (AMode in [smAssist, smFinal]) and (not TDeepAxisProfile.IsWeChatM3UiaPaste) then
  begin Log('当前 Profile 未启用微信 UIA 粘贴能力'); Exit; end;

  // 最终模式需额外开关
  if (AMode = smFinal) and (not TDeepAxisProfile.IsWeChatFinalSend) then
  begin Log('当前 Profile 未启用最终发送 (模拟 Enter) 能力, 请改用辅助/手动模式'); Exit; end;

  if not FRadarPanel.TryGetSelectedContact(LContact) then
  begin Log('未选择可验证联系人，已取消粘贴'); Exit; end;

  if AScript <> '' then
    LScript := AScript
  else
    LScript := FScriptPanel.GetCurrentScript;
  if LScript = '' then begin Log('无话术可粘贴'); Exit; end;

  LBoundary := FBoundaryEngine.CheckScript(LScript, LContact);
  case LBoundary.Classification of
    bcRed:
    begin Log('话术被禁止: ' + LBoundary.Reason); Exit; end;
    bcYellow:
    begin
      // 黄灯: 最终/辅助模式需用户前置确认 (docs/03 §4.4)
      LConfirmMsg := '话术为黄灯边界, 需人工确认:' + #13#10 + LBoundary.Reason +
                     #13#10#13#10 + '确认继续发送?';
      if Application.MessageBox(PChar(LConfirmMsg), '黄灯确认',
        MB_YESNO or MB_ICONQUESTION) <> ID_YES then
      begin Log('用户取消黄灯话术发送'); Exit; end;
      Log('用户已确认黄灯话术, 继续');
    end;
    bcGreen: Log('话术通过审核');
  end;

  LNeedPaste := AMode.RequiresPaste;   // smManual=False
  LNeedEnter := AMode.RequiresSystemEnter; // 仅 smFinal

  // 入队 (带模式 + 确认标记)
  LItemId := FSendQueue.Enqueue(LContact.ContactId, LContact.DisplayNameRedacted,
    LScript, LBoundary.Classification, AMode,
    LBoundary.Classification = bcYellow); // 黄灯已确认
  FSendQueuePanel.Refresh;

  // 构造证据骨架
  LEvidence := TSendEvidence.CreateBlank;
  LEvidence.Mode := AMode;
  case LBoundary.Classification of
    bcGreen:  LEvidence.BoundaryClass := 'Green';
    bcYellow: LEvidence.BoundaryClass := 'Yellow';
    bcRed:    LEvidence.BoundaryClass := 'Red';
  end;
  LEvidence.ContactId := LContact.ContactId;
  LEvidence.ScriptHash := THashSHA2.GetHashString(LScript, SHA256).Substring(0, 16);
  LEvidence.Timestamp := Now;
  LEvidence.PreConfirm := (LBoundary.Classification = bcYellow);

  // 手动模式: 不粘贴不导航, 仅入队 + 事后检测
  if not LNeedPaste then
  begin
    Log('手动模式: 请在微信手动发送, DeepAxis 将事后检测');
    LBaseline := FResultPoller.CaptureBaseline(LContact.ContactId);
    LEvidence := FResultPoller.BuildEvidence(LContact.ContactId, LEvidence.ScriptHash,
      LBaseline, AMode, LEvidence.BoundaryClass);
    FSendQueue.UpdateEvidence(LItemId, LEvidence);
    FSendQueue.UpdateStatus(LItemId, ssSent, '手动模式-用户自行发送');
    FSendQueuePanel.Refresh;
    Exit;
  end;

  // 辅助/最终: 粘贴
  LUiaResult := FUiaEngine.PasteScript(LScript);
  if not LUiaResult.Success then
  begin
    FSendQueue.UpdateStatus(LItemId, ssFailed, LUiaResult.ErrorMessage);
    LEvidence.ResultDetected := False;
    LEvidence.ResultNote := '粘贴失败: ' + LUiaResult.ErrorMessage;
    FSendQueue.UpdateEvidence(LItemId, LEvidence);
    Log('粘贴失败: ' + LUiaResult.ErrorMessage);
    FSendQueuePanel.Refresh;
    Exit;
  end;

  // 最终模式: 模拟 Enter
  if LNeedEnter then
  begin
    LUiaResult := FUiaEngine.PressEnter;
    if not LUiaResult.Success then
    begin
      FSendQueue.UpdateStatus(LItemId, ssFailed, 'Enter 失败: ' + LUiaResult.ErrorMessage);
      LEvidence.ResultNote := 'Enter 发送失败: ' + LUiaResult.ErrorMessage;
      FSendQueue.UpdateEvidence(LItemId, LEvidence);
      Log('Enter 发送失败: ' + LUiaResult.ErrorMessage);
      FSendQueuePanel.Refresh;
      Exit;
    end;
    // 广告计数: 最终发送对闲人计数 (docs/03 §2.6)
    LContact := TAdTracker.OnAdSent(LContact);
    // 持久化 ad_track 到本地 DB1 (修复 #74: 轮询复位); 静默兜底
    // BUG-044 Phase 3: 优先参数化 tag_profiles 表, overlay JSON 为兼容兜底
    if FOverlayStore <> nil then
      FOverlayStore.UpsertTagProfile(LContact.ContactId, TAdTracker.BuildOverlayJson(LContact));
    try
      var LTagStore := GetDeepAxisDataStoreManager.TagProfileStore;
      if Assigned(LTagStore) then
      begin
        var LProfile := TTagProfile.CreateClean(LContact.ContactId);
        LProfile.AdCount := LContact.AdCount;
        LProfile.LastAdAt := LContact.LastAdAt;
        LProfile.ProductCount := LContact.ProductCount;
        LProfile.IsUserPreserved := LContact.IsUserPreserved;
        LProfile.MarketingKeywordHitCount := LContact.MarketingKeywordHitCount;
        LProfile.LastInteractionAt := LContact.LastInteractionAt;
        LTagStore.SaveForContact(LContact.ContactId, LProfile);
      end;
    except
      // 静默: TagProfile 持久化失败不阻断发送主流程
    end;
    Log('最终模式: 已模拟 Enter 发送');
  end
  else
    Log('辅助模式: 已粘贴到微信输入框，请按 Enter 发送');

  // 事后检测 (宁缺勿造: getter 未接入时返回 srUnknown, 不臆测)
  LBaseline := FResultPoller.CaptureBaseline(LContact.ContactId);
  LEvidence := FResultPoller.BuildEvidence(LContact.ContactId, LEvidence.ScriptHash,
    LBaseline, AMode, LEvidence.BoundaryClass);
  FSendQueue.UpdateEvidence(LItemId, LEvidence);

  // BUG-051 #87: 校准点 — 发送成功 = 边界判断准确 (预测=分类数值, 实际=1.0)
  var LPredicted: Double;
  if LEvidence.BoundaryClass = 'Green' then LPredicted := 1.0
  else if LEvidence.BoundaryClass = 'Yellow' then LPredicted := 0.5
  else LPredicted := 0.0;
  FCalibrationEngine.RecordPoint('boundary_' + LEvidence.BoundaryClass,
    LPredicted, 1.0);

  FSendQueue.UpdateStatus(LItemId, ssSent, '');
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
  FDBPollerThread := TDBPollerThread.Create(FWeChatReader, FMetricCalculator, FRadarEngine, FEvidenceBuilder, FTagEngine, FIdleFunnel, FOverlayStore);
  FDBPollerThread.OnDataReady := OnPollResultReady;
  FDBPollerThread.Start;
end;

procedure TDeepAxisMainForm.StopPolling;
var
  LWaitStart: Cardinal;
begin
  if FDBPollerThread <> nil then
  begin
    FDBPollerThread.OnDataReady := nil;
    FDBPollerThread.Terminate;
    FDBPollerThread.ForcePoll;
    // BUG-052 fix: 先摘除队列回调再等待 — 轮询线程可能正 TThread.Queue
    // 等待主线程处理, 若直接 WaitFor 会死锁 (主线程等线程, 线程等主线程)。
    TThread.RemoveQueuedEvents(FDBPollerThread);
    // 带超时等待: 最多 3 秒, 超时强制放行 (防关闭卡死)。
    // 不用 ProcessMessages (FormClose 期间重入有风险), 线程正常几毫秒退出。
    LWaitStart := GetTickCount;
    while FDBPollerThread.Finished = False do
    begin
      if (GetTickCount - LWaitStart) > 3000 then
        Break;
      Sleep(50);
    end;
    FDBPollerThread.Free;
    FDBPollerThread := nil;
  end;
end;

procedure TDeepAxisMainForm.OnPollResultReady(Sender: TObject; const AData: TPollResult);
var LContact: TContact; LContactFound: Boolean; I: Integer;
begin
  FRadarPanel.SetData(AData);
  FTierPanel.SetData(AData);
  FTagMatrixPanel.SetContacts(AData.Contacts);
  // 闲人删除候选 (docs/03 §2.6)
  FIdleFunnelPanel.SetCandidates(FIdleFunnel.GetDeletionCandidates(AData.Contacts));
  // 标签/备注整理建议 L0-L1 (docs/08 §1)
  FTagSuggestPanel.SetSuggestions(FTagManager.GenerateL0Report(AData.Contacts));
  FLastContacts := AData.Contacts; // 缓存供 DoDeleteCandidate 反查
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
  // BUG-051 #82: body-zero 审计报告日志 (M0 纯元数据应 queried=false; M1 授权后真实计数)
  if AData.NewMessageCount >= 0 then
  begin
    Log(Format('body-zero审计: 正文列=%s 正文读取=%s (%d次) 写库=%d UIA=%d',
      [BoolToStr(AData.BodyZero.BodyColumnsSeen, True),
       BoolToStr(AData.BodyZero.BodyColumnsQueried, True),
       AData.BodyZero.BodyQueriedCount,
       AData.BodyZero.WriteAttempts,
       AData.BodyZero.UiaCalls]));
    // BUG-051 #83: 审计 — 每轮轮询写入审计事件 (含 body-zero 快照)
    AuditAppend(aetRead, 'wechat-poll', ['poll_cycle'],
      AData.BodyZero.BodyColumnsSeen, AData.BodyZero.BodyColumnsQueried,
      AData.BodyZero.WriteAttempts, AData.BodyZero.UiaCalls);
  end;
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
          begin FRadarPanel.SetWeChatConnected(True); FTierPanel.SetWeChatConnected(True); Log('密钥验证成功！开始分析...'); StartPolling; end;
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

  // BUG-049 fix: FLogMemo 在 InitUI 才创建, FormCreate 早期 Log() 时仍为 nil。
  // nil 访问 Lines.Add 会触发 AccessViolation (read 0x530)。
  if FLogMemo <> nil then
    FLogMemo.Lines.Add(LLine);

  if not GLogFileInitialized then
  begin
    GLogFilePath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'DeepAxis.log');
    GLogFileInitialized := True;
  end;

  // BUG-049 fix: 原 Writeln(GLogFile, ...) 按 ANSI 写 UTF-8 中文字符串 → 日志乱码。
  // 改 UTF-8 追加 (不依赖 TextFile 编码), 中文正常可读。
  try
    TFile.AppendAllText(GLogFilePath, LLine + sLineBreak, TEncoding.UTF8);
  except
  end;
end;

end.