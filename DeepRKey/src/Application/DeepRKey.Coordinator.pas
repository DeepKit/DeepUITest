unit DeepRKey.Coordinator;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.StrUtils, System.IOUtils, System.Generics.Collections,
  Vcl.ExtCtrls,
  DeepRKey.Types,
  DeepRKey.HookShared,
  DeepRKey.IPCRouter,
  DeepRKey.SystemMenu,
  DeepRKey.WindowOps,
  DeepRKey.WindowTracker,
  DeepRKey.HookEligibilityPolicy,
  DeepRKey.MenuModel,
  DeepRKey.TitlebarButton,
  DeepRKey.LayoutManager,
  DeepRKey.HelperManager,
  DeepRKey.CommandDispatcher,
  DeepRKey.HookController;

// CryptoAPI declarations for SHA-256 hash verification
const
  PROV_RSA_AES = 24;
  CALG_SHA_256 = $0000800c;
  CRYPT_VERIFYCONTEXT = $F0000000;
  HP_HASHVAL = $0002;
  HP_HASHSIZE = $0004;
  LOAD_LIBRARY_SEARCH_APPLICATION_DIR = $00001000;

type
  HCRYPTPROV = NativeUInt;
  HCRYPTHASH = NativeUInt;

function CryptAcquireContextW(var phProv: HCRYPTPROV; pszContainer: LPCWSTR;
  pszProvider: LPCWSTR; dwProvType: DWORD; dwFlags: DWORD): BOOL; stdcall;
  external advapi32 name 'CryptAcquireContextW';
function CryptCreateHash(hProv: HCRYPTPROV; Algid: LongWord; hKey: HCRYPTHASH;
  dwFlags: DWORD; var phHash: HCRYPTHASH): BOOL; stdcall;
  external advapi32 name 'CryptCreateHash';
function CryptHashData(hHash: HCRYPTHASH; const pbData; dwDataLen, dwFlags: DWORD): BOOL; stdcall;
  external advapi32 name 'CryptHashData';
function CryptGetHashParam(hHash: HCRYPTHASH; dwParam: DWORD; pbData: Pointer;
  var pdwDataLen: DWORD; dwFlags: DWORD): BOOL; stdcall;
  external advapi32 name 'CryptGetHashParam';
function CryptDestroyHash(hHash: HCRYPTHASH): BOOL; stdcall;
  external advapi32 name 'CryptDestroyHash';
function CryptReleaseContext(hProv: HCRYPTPROV; dwFlags: DWORD): BOOL; stdcall;
  external advapi32 name 'CryptReleaseContext';
function SetDefaultDllDirectories(DirectoryFlags: DWORD): BOOL; stdcall;
  external kernel32 name 'SetDefaultDllDirectories';

type
  /// <summary>
  /// 主进程协调器 — 将 IPC / WindowTracker / SystemMenu / WindowOps 串联
  /// </summary>
  TDeepRKeyCoordinator = class
  private
    FGUID: string;
    FAuthCookie: TGUID;
    FIPCHwnd: HWND;
    FEventMsgId: UINT;
    FRouter: TRKeyIPCRouter;
    FMenuRegistry: TRKeyMenuRegistry;
    FMenuInjector: TSystemMenuInjector;
    FWindowOps: TWindowCommandService;
    FTracker: TWindowTracker;
    FPolicy: THookEligibilityPolicy;
    FWinEventHooks: TList<THandle>;
    FActiveTargetHwnd: HWND;
    FLastMenuRefreshTick: UInt64;
    FHookController: THookController;  // T-500: Thread-level hook controller
    FPaused: Boolean;
    FOnPauseStateChanged: TProc;
    FClickThroughTimer: TTimer;
    FClickThroughWindows: TDictionary<NativeUInt, UInt64>;  // BUG-M9: 多窗口超时字典
    FPurgeTimer: TTimer;  // BUG-H7: 定期扫描清理无效窗口句柄
    FDragByMouseEnabled: Boolean;
    FMouseHookHandle: HHOOK;
    FDragTargetHwnd: HWND;
    FTitlebarButton: TTitlebarButton;
    FTitlebarButtonEnabled: Boolean;
    FLayoutManager: TLayoutManager;
    FHotkeyId: Integer;
    FHotkeyRegistered: Boolean;
    FHelperManager: THelperManager;  // T-441: 32-bit Helper32 process manager
    FDispatcher: TCommandDispatcher;  // T-430: 命令分发器

    procedure CreateIPCHiddenWindow;
    procedure DestroyIPCHiddenWindow;
    procedure InstallWinEventHooks;
    procedure UninstallWinEventHooks;
    procedure InitializeHookController;  // T-500: Thread-level hook
    procedure UninstallHookController;   // T-500
    procedure HandleIPCCommand(cmd: WPARAM; lParam: LPARAM);
    procedure HandleIPCNotification;
    procedure ProcessMMFEvents;
    procedure DispatchCommandEvent(hWnd: HWND; CommandId: UInt32);
    procedure DispatchInitMenuEvent(hWnd: HWND);
    function HandleSpecialCommand(hWnd: HWND; CommandId: UInt32): Boolean;  // T-430: 特殊命令处理（ClickThrough/Layout/DragByMouse）
    procedure OnClickThroughTimer(Sender: TObject);
    procedure OnPurgeTimer(Sender: TObject);  // BUG-H7
    procedure InstallMouseHook;
    procedure UninstallMouseHook;
    procedure SetDragByMouseEnabled(Enable: Boolean);
    procedure SetTitlebarButtonEnabled(Enable: Boolean);
    procedure OnTitlebarButtonClick(hWnd: HWND);
    procedure RegisterGlobalHotkey;
    procedure UnregisterGlobalHotkey;
    procedure HandleHotkey;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
    procedure ApplyMenuVisibility;
    procedure RefreshAllMenus;
    procedure ReenumerateAllWindows;  // T-011: Re-scan after sleep/session change
    procedure OnSystemResume;         // T-011: PBT_APMRESUMEAUTOMATIC handler
    procedure OnSessionChange(changeType: Integer);  // T-011: WTS session change

    property ActiveTargetHwnd: HWND read FActiveTargetHwnd;
    property WindowTracker: TWindowTracker read FTracker;
    property MenuInjector: TSystemMenuInjector read FMenuInjector;
    property Router: TRKeyIPCRouter read FRouter;
    property LayoutManager: TLayoutManager read FLayoutManager;
    property HookController: THookController read FHookController;  // T-500
    property SessionGUID: string read FGUID;
    property Paused: Boolean read FPaused write FPaused;
    property DragByMouseEnabled: Boolean read FDragByMouseEnabled;
    property TitlebarButtonEnabled: Boolean read FTitlebarButtonEnabled write SetTitlebarButtonEnabled;
    property OnPauseStateChanged: TProc read FOnPauseStateChanged write FOnPauseStateChanged;
  end;

var
  GCoordinator: TDeepRKeyCoordinator = nil;

/// <summary>IPC 隐藏窗口的窗口过程（全局函数，因为 SetWindowLongPtr 需要函数指针）</summary>
function IPCWindowProc(hWnd: HWND; Msg: UINT; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;

/// <summary>SetWinEventHook 回调</summary>
procedure WinEventProc(hWinEventHook: THandle; event: DWORD;
  hwnd: HWND; idObject, idChild: Longint;
  idEventThread, dwmsEventTime: DWORD); stdcall;

/// <summary>WH_MOUSE_LL 回调 — Alt+左键拖拽窗口</summary>
function MouseHookProc(nCode: Integer; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;

implementation

uses
  DeepRKey.Bootstrap,
  DeepRKey.TransparencyForm,
  DeepRKey.StubAdapter;  // T-451: GetDeepRKeyDataDir

type
  /// <summary>Low-level mouse hook struct — not declared in Delphi's Winapi.Windows</summary>
  TMSLLHookStruct = record
    pt: TPoint;
    mouseData: DWORD;
    flags: DWORD;
    time: DWORD;
    dwExtraInfo: ULONG_PTR;
  end;
  PMSLLHookStruct = ^TMSLLHookStruct;

const
  RK_MMF_MAIN_WND_CLASS = 'DeepRKey_IPC_Wnd_v1';

{ Global callback state — needed because WinEventProc/MouseHookProc are plain stdcall }
// T-434: 减少全局引用，GTrackerRef/GMenuInjectorRef 通过 GCoordinatorRef 访问
var
  GCoordinatorRef: TDeepRKeyCoordinator = nil;

{ IPCWindowProc }

function IPCWindowProc(hWnd: HWND; Msg: UINT; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
begin
  // T-447 修复：WM_COPYDATA 处理器（PID 验证 + GUID 认证）
  // 取代旧的纯 GUID 认证（CD_GUID_QUERY 对任意调用方公开 GUID）
  // 新增：调用方必须提供自己的 PID，服务端通过 GetWindowThreadProcessId 验证

  if Msg = WM_COPYDATA then
  begin
    try
    if (GCoordinatorRef <> nil) and (lParam <> 0) then
    begin
      var cds := PCOPYDATASTRUCT(lParam);

      // T-447: IPC 命令需要 PID 验证 + AuthCookie 验证
      if cds.dwData = CD_IPC_CMD then
      begin
        if cds.cbData >= SizeOf(TRKeyIPCCommand) then
        begin
          var cmd := PRKeyIPCCommand(cds.lpData);

          // BUG-049 fix: PID validation — wParam should be sender HWND per WM_COPYDATA spec.
          // For console apps (CLI) that pass HWND_MESSAGE, GetWindowThreadProcessId returns 0.
          // In that case, trust the CallerPID from the command struct (AuthGUID is primary auth).
          if wParam <> 0 then
          begin
            var senderPid: DWORD := 0;
            GetWindowThreadProcessId(wParam, @senderPid);
            if (senderPid <> 0) and (senderPid <> cmd.CallerPID) then
            begin
              Result := 0;  // PID mismatch — reject
              Exit;
            end;
          end;

          // 验证 AuthGUID 匹配 SessionGUID
          var authStr := string(cmd.AuthGUID);
          if authStr = GCoordinatorRef.SessionGUID then
          begin
            GCoordinatorRef.HandleIPCCommand(cmd.Command, cmd.Param);
            Result := 1;  // 成功
          end
          else
            Result := 0;  // 认证失败
        end
        else
          Result := 0;
        Exit;
      end;

      // T-447: GUID 查询需要 PID 验证（Hook DLL/CLI 使用）
      // BUG-049 fix: WM_COPYDATA is one-way (sender→receiver). Receiver can't write
      // back to sender's buffer. Write GUID to temp file like CMD handler.
      if cds.dwData = CD_GUID_QUERY then
      begin
        if cds.cbData >= SizeOf(TRKeyGUIDQuery) then
        begin
          var query := PRKeyGUIDQuery(cds.lpData);

          // BUG-049 fix: PID validation — trust CallerPID when wParam is not a valid HWND
          if wParam <> 0 then
          begin
            var senderPid: DWORD := 0;
            GetWindowThreadProcessId(wParam, @senderPid);
            if (senderPid <> 0) and (senderPid <> query.CallerPID) then
            begin
              Result := 0;  // PID mismatch — reject
              Exit;
            end;
          end;

          // Write GUID to temp file: DeepRKey_guid_<CallerPID>.txt
          var guidFile := GetEnvironmentVariable('TEMP') +
            '\DeepRKey_guid_' + IntToStr(query.CallerPID) + '.txt';
          var s := GCoordinatorRef.SessionGUID;

          var hFile := CreateFile(PChar(guidFile), GENERIC_WRITE, 0, nil,
            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);

          if hFile <> INVALID_HANDLE_VALUE then
          begin
            // BUG-049 fix: Write as ASCII bytes (GUID is hex-only, no encoding issues)
            var asciiBytes := TEncoding.ASCII.GetBytes(s);
            var written: DWORD := 0;
            if Length(asciiBytes) > 0 then
              WriteFile(hFile, asciiBytes[0], Length(asciiBytes), written, nil);
            CloseHandle(hFile);
          end;

          Result := 1;  // Success — GUID written to temp file
        end
        else
          Result := 0;
        Exit;
      end;
    end;
    except
      on E: Exception do
        ; // BUG-049: prevent crash in window procedure
    end;
    Result := 0;
    Exit;
  end;

  if (GCoordinatorRef <> nil) and (Msg = GCoordinatorRef.FEventMsgId) then
  begin
    if not GCoordinatorRef.FPaused then
      GCoordinatorRef.HandleIPCNotification;
    Result := 0;
    Exit;
  end;

  if Msg = WM_HOTKEY then
  begin
    if (GCoordinatorRef <> nil) then
      GCoordinatorRef.HandleHotkey;
    Result := 0;
    Exit;
  end;

  Result := DefWindowProc(hWnd, Msg, wParam, lParam);
end;

{ WinEventProc — SetWinEventHook callback }

procedure WinEventProc(hWinEventHook: THandle; event: DWORD;
  hwnd: HWND; idObject, idChild: Longint;
  idEventThread, dwmsEventTime: DWORD); stdcall;
begin
  if (idObject <> OBJID_WINDOW) or (idChild <> CHILDID_SELF) then
    Exit;
  // T-434: 通过 GCoordinatorRef 访问 FTracker/FMenuInjector
  if (GCoordinatorRef = nil) or (GCoordinatorRef.FTracker = nil) then
    Exit;
  // When paused, skip PreInject but still track windows for status display
  if GCoordinatorRef.FPaused then
  begin
    if event = EVENT_SYSTEM_FOREGROUND then
      GCoordinatorRef.FTracker.OnForegroundChanged(hwnd);
    Exit;
  end;

  case event of
    EVENT_OBJECT_CREATE:
    begin
      if IsWindow(hwnd) then
      begin
        GCoordinatorRef.FTracker.OnWindowCreated(hwnd);
        // Auto PreInject system menu on eligible windows
        if (GCoordinatorRef.FMenuInjector <> nil) and
           (GCoordinatorRef.FTracker.EligibilityPolicy.IsHookEligible(hwnd).IsEligible) then
        begin
          GCoordinatorRef.FMenuInjector.PreInject(hwnd);
          // T-500: Install per-thread hook for this window's thread
          if GCoordinatorRef.FHookController <> nil then
            GCoordinatorRef.FHookController.EnsureThreadHook(hwnd);
        end;
      end;
    end;
    EVENT_OBJECT_DESTROY:
    begin
      GCoordinatorRef.FTracker.OnWindowDestroyed(hwnd);
      // BUG-H7 修复：同步清理 SystemMenuInjector 状态字典
      if GCoordinatorRef.FMenuInjector <> nil then
        GCoordinatorRef.FMenuInjector.NotifyWindowDestroyed(hwnd);
      // T-500: Notify HookController for ref count decrement
      if GCoordinatorRef.FHookController <> nil then
        GCoordinatorRef.FHookController.NotifyWindowDestroyed(hwnd);
    end;
    EVENT_SYSTEM_FOREGROUND:
    begin
      if IsWindow(hwnd) then
      begin
        GCoordinatorRef.FTracker.OnForegroundChanged(hwnd);
        // Update active target for command dispatch
        GCoordinatorRef.FActiveTargetHwnd := hwnd;
        // Update titlebar button target
        if (GCoordinatorRef.FTitlebarButton <> nil) and
           GCoordinatorRef.FTitlebarButtonEnabled then
          GCoordinatorRef.FTitlebarButton.SetTarget(hwnd);
      end;
    end;
  end;
end;

{ MouseHookProc — WH_MOUSE_LL callback for Alt+Click drag }

function MouseHookProc(nCode: Integer; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
var
  pt: TPoint;
  hWnd: NativeUInt;
  pms: PMSLLHookStruct;
  entry: TWindowEntry;
begin
  if nCode < 0 then
  begin
    Result := CallNextHookEx(0, nCode, wParam, lParam);
    Exit;
  end;

  if (wParam = WM_LBUTTONDOWN) and
     (GCoordinatorRef <> nil) and
     GCoordinatorRef.FDragByMouseEnabled and
     (GetKeyState(VK_MENU) < 0) then
  begin
    pms := PMSLLHookStruct(lParam);
    pt := pms^.pt;
    hWnd := NativeUInt(WindowFromPoint(pt));
    // Walk up to find a top-level tracked window
    while (hWnd <> 0) and ((GetWindowLong(THandle(hWnd), GWL_STYLE) and WS_CHILD) <> 0) do
      hWnd := NativeUInt(GetParent(THandle(hWnd)));

    if (hWnd <> 0) and (GCoordinatorRef.FTracker.GetWindowEntry(THandle(hWnd), entry)) then
    begin
      GCoordinatorRef.FDragTargetHwnd := THandle(hWnd);
      ReleaseCapture;
      SetForegroundWindow(THandle(hWnd));
      PostMessage(THandle(hWnd), WM_SYSCOMMAND, SC_MOVE or $0002, 0);
      Result := 1;  // swallow the click — we handle the drag
      Exit;
    end;
  end;

  Result := CallNextHookEx(0, nCode, wParam, lParam);
end;

{ TDeepRKeyCoordinator }

constructor TDeepRKeyCoordinator.Create;
begin
  FIPCHwnd := 0;
  FEventMsgId := 0;
  FActiveTargetHwnd := 0;
  FLastMenuRefreshTick := 0;
  FHookController := nil;  // T-500: created in InitializeHookController
  FMouseHookHandle := 0;
  FDragByMouseEnabled := False;
  FDragTargetHwnd := 0;
  FWinEventHooks := TList<THandle>.Create;
  FClickThroughTimer := TTimer.Create(nil);
  FClickThroughTimer.Enabled := False;
  FClickThroughTimer.Interval := 5000;  // BUG-M9: 5 秒检查间隔（支持多窗口）
  FClickThroughTimer.OnTimer := OnClickThroughTimer;
  FClickThroughWindows := TDictionary<NativeUInt, UInt64>.Create;
  // BUG-H7: 定期扫描清理无效窗口句柄（30 秒间隔）
  FPurgeTimer := TTimer.Create(nil);
  FPurgeTimer.Enabled := False;
  FPurgeTimer.Interval := 30000;  // 30 seconds
  FPurgeTimer.OnTimer := OnPurgeTimer;
  FHotkeyId := $100;  // unique ID for RegisterHotKey
  FHotkeyRegistered := False;
  FHelperManager := nil;  // T-441: created in InitializeHookController
end;

destructor TDeepRKeyCoordinator.Destroy;
begin
  Stop;
  FWinEventHooks.Free;
  inherited;
end;

procedure TDeepRKeyCoordinator.Start;
begin
  // 1. Generate GUID + AuthCookie
  CreateGUID(FAuthCookie);
  FGUID := GUIDToString(FAuthCookie);
  // Remove { } braces for MMF name compatibility
  FGUID := FGUID.Trim(['{', '}']);

  TBootstrap.Logger.Info(Format('Coordinator: GUID=%s', [FGUID]), 'IPC');

  // 2. Create components
  FPolicy := THookEligibilityPolicy.Create;
  FTracker := TWindowTracker.Create(FPolicy);
  FMenuRegistry := TRKeyMenuRegistry.Create;  // constructor calls BuildDefaultMenu
  FMenuInjector := TSystemMenuInjector.Create(FMenuRegistry);
  FWindowOps := TWindowCommandService.Create(FAuthCookie);

  // T-430: Create command dispatcher
  FDispatcher := TCommandDispatcher.Create(FWindowOps, FMenuInjector);
  FDispatcher.SetSpecialHandler(HandleSpecialCommand);

  // T-434: 设置全局引用（仅 GCoordinatorRef，其他通过它访问）
  GCoordinatorRef := Self;

  // 4. Create IPC hidden window
  CreateIPCHiddenWindow;

  // 5. Create MMF + IPC Router
  FRouter := TRKeyIPCRouter.Create(FGUID, FIPCHwnd, FAuthCookie);
  FRouter.Initialize;
  FEventMsgId := FRouter.EventMessageId;

  // 6. Install WinEvent hooks
  InstallWinEventHooks;

  // 7. T-500: Initialize thread-level hook controller (replaces global hook)
  InitializeHookController;

  // 8. Apply menu visibility from saved config
  ApplyMenuVisibility;

  // 10. Enumerate existing windows AND inject menus into them
  FTracker.ReEnumerateWindows;
  for var entry in FTracker.GetAllWindows do
  begin
    var hWnd := THandle(entry.Hwnd);
    if IsWindow(hWnd) and FPolicy.IsHookEligible(hWnd).IsEligible then
    begin
      FMenuInjector.PreInject(hWnd);
      // T-500: Install per-thread hook for existing eligible windows
      if FHookController <> nil then
        FHookController.EnsureThreadHook(hWnd);
    end;
  end;

  // 11. Create titlebar button (default OFF, enabled via config)
  FTitlebarButton := TTitlebarButton.Create;
  FTitlebarButton.SetMenuCallback(OnTitlebarButtonClick);
  FTitlebarButtonEnabled := TBootstrap.Config.ReadBool('Menu.ShowTitlebarButton', False);
  if FTitlebarButtonEnabled then
    FTitlebarButton.Start;

  // 12. Create layout manager (snapshot storage in user data dir)
  // T-451: 使用用户数据目录，避免写入 EXE 目录（Program Files 不可写）
  var layoutDir := TPath.Combine(GetDeepRKeyDataDir, 'layouts');
  if not TDirectory.Exists(layoutDir) then
    TDirectory.CreateDirectory(layoutDir);
  FLayoutManager := TLayoutManager.Create(layoutDir);

  // 13. Register global hotkey (Ctrl+Alt+Space)
  RegisterGlobalHotkey;

  // 14. BUG-H7: 启动定期扫描清理定时器
  FPurgeTimer.Enabled := True;

  TBootstrap.Logger.Info(
    Format('Coordinator started: %d windows tracked, %d threads',
      [FTracker.WindowCount, FTracker.ThreadCount]), 'Coordinator');
end;

{ T-011: System event handlers }

procedure TDeepRKeyCoordinator.ReenumerateAllWindows;
begin
  if FPaused then Exit;

  TBootstrap.Logger.Info('Re-enumerating all windows', 'Coordinator');

  // Clear stale entries and re-scan
  FTracker.ReEnumerateWindows;

  // Re-inject menus and install hooks for all eligible windows
  for var entry in FTracker.GetAllWindows do
  begin
    var hWnd := THandle(entry.Hwnd);
    if IsWindow(hWnd) and FPolicy.IsHookEligible(hWnd).IsEligible then
    begin
      FMenuInjector.PreInject(hWnd);
      if FHookController <> nil then
        FHookController.EnsureThreadHook(hWnd);
    end;
  end;

  TBootstrap.Logger.Info(
    Format('Re-enumeration complete: %d windows tracked', [FTracker.WindowCount]),
    'Coordinator');
end;

procedure TDeepRKeyCoordinator.OnSystemResume;
begin
  TBootstrap.Logger.Info('System resumed from sleep/suspend', 'Coordinator');

  // Re-enumerate windows and re-install hooks
  // (Hook DLLs in other processes may have lost state during sleep)
  ReenumerateAllWindows;
end;

procedure TDeepRKeyCoordinator.OnSessionChange(changeType: Integer);
const
  WTS_CONSOLE_CONNECT        = 1;
  WTS_CONSOLE_DISCONNECT     = 2;
  WTS_REMOTE_CONNECT         = 3;
  WTS_REMOTE_DISCONNECT      = 4;
  WTS_SESSION_LOGON          = 5;
  WTS_SESSION_LOGOFF         = 6;
  WTS_SESSION_LOCK           = 7;
  WTS_SESSION_UNLOCK         = 8;
begin
  case changeType of
    WTS_SESSION_UNLOCK, WTS_CONSOLE_CONNECT, WTS_REMOTE_CONNECT:
    begin
      TBootstrap.Logger.Info(
        Format('Session change: %d (re-enumerating)', [changeType]), 'Coordinator');
      ReenumerateAllWindows;
    end;
    WTS_SESSION_LOCK:
      TBootstrap.Logger.Info('Session locked', 'Coordinator');
    WTS_SESSION_LOGON:
    begin
      TBootstrap.Logger.Info('Session logged on', 'Coordinator');
      ReenumerateAllWindows;
    end;
    WTS_CONSOLE_DISCONNECT, WTS_REMOTE_DISCONNECT, WTS_SESSION_LOGOFF:
      TBootstrap.Logger.Info(
        Format('Session change: %d', [changeType]), 'Coordinator');
  end;
end;

procedure TDeepRKeyCoordinator.Stop;
begin
  try
    // T-434: 移除全局引用（仅 GCoordinatorRef）
    GCoordinatorRef := nil;

    UninstallHookController;  // T-500: Uninstall thread-level hooks
    UninstallMouseHook;
    UninstallWinEventHooks;

    UnregisterGlobalHotkey;

    FreeAndNil(FClickThroughTimer);
    FreeAndNil(FClickThroughWindows);
    FreeAndNil(FPurgeTimer);
    FreeAndNil(FHelperManager);  // T-441
    FreeAndNil(FTitlebarButton);
    FreeAndNil(FLayoutManager);
    FreeAndNil(FRouter);
    FreeAndNil(FDispatcher);  // T-430: 释放命令分发器

    DestroyIPCHiddenWindow;

    if FWindowOps <> nil then
      FWindowOps.CleanupAll;
    FreeAndNil(FWindowOps);
    FreeAndNil(FMenuInjector);
    FreeAndNil(FMenuRegistry);
    FreeAndNil(FTracker);
    FreeAndNil(FPolicy);

    TBootstrap.Logger.Info('Coordinator stopped', 'Coordinator');
  except
    on E: Exception do
      OutputDebugString(PChar('[DeepRKey] Coordinator.Stop error: ' + E.Message));
  end;
end;

procedure TDeepRKeyCoordinator.ApplyMenuVisibility;
begin
  if FMenuRegistry = nil then Exit;
  var config := TBootstrap.Config;
  if config = nil then Exit;

  for var item in FMenuRegistry.GetItems do
  begin
    case item.CommandId of
      RK_SC_TOPMOST:       item.Visible := config.ReadBool('Menu.ShowTopMost', True);
      RK_SC_TRANS:         item.Visible := config.ReadBool('Menu.ShowTransparency', True);
      RK_SC_MOVE_TO:       item.Visible := config.ReadBool('Menu.ShowMoveToMonitor', True);
      RK_SC_ALIGN:         item.Visible := config.ReadBool('Menu.ShowAlign', True);
      RK_SC_RESIZE:        item.Visible := config.ReadBool('Menu.ShowResize', True);
      RK_SC_ROLLUP:        item.Visible := config.ReadBool('Menu.ShowRollUp', True);
      RK_SC_SEND_TO_BOTTOM:item.Visible := config.ReadBool('Menu.ShowSendToBottom', True);
      RK_SC_CLICK_THROUGH: item.Visible := config.ReadBool('Menu.ShowClickThrough', True);
      RK_SC_INFORMATION:   item.Visible := config.ReadBool('Menu.ShowInformation', True);
      RK_SC_DIMMER:        item.Visible := config.ReadBool('Menu.ShowDimmer', True);
      RK_SC_HIDE_FOR_ALT_TAB: item.Visible := config.ReadBool('Menu.ShowHideAltTab', True);
      RK_SCREENSHOT:       item.Visible := config.ReadBool('Menu.ShowScreenshot', True);
      RK_SC_DRAG_BY_MOUSE: item.Visible := config.ReadBool('Menu.ShowDragByMouse', True);
      RK_SC_RESIZABLE:     item.Visible := config.ReadBool('Menu.ShowResizable', True);
      RK_SC_UNDO:          item.Visible := config.ReadBool('Menu.ShowUndo', True);
      RK_SC_REDO:          item.Visible := config.ReadBool('Menu.ShowRedo', True);
    end;
  end;

  // Load resize presets from config
  if FMenuInjector <> nil then
  begin
    var presets := config.ReadString('Menu.ResizePresets',
      '800x600;1024x768;1280x720;1920x1080');
    FMenuInjector.SetResizePresets(presets);
  end;

  TBootstrap.Logger.Info('Menu visibility applied', 'Coordinator');
end;

procedure TDeepRKeyCoordinator.RefreshAllMenus;
begin
  // BUG-M3 修复：枚举所有跟踪窗口，清理并重新注入菜单
  if (FTracker = nil) or (FMenuInjector = nil) then
    Exit;

  var count := 0;
  for var entry in FTracker.GetAllWindows do
  begin
    var hWnd := THandle(entry.Hwnd);
    if not IsWindow(hWnd) then
      Continue;

    // 清理旧菜单
    FMenuInjector.CleanupMenu(hWnd);
    // 重新注入
    FMenuInjector.PreInject(hWnd);
    // 刷新状态（勾选/灰化等）
    FMenuInjector.RefreshMenuState(hWnd);
    Inc(count);
  end;

  TBootstrap.Logger.Info(
    Format('RefreshAllMenus: %d windows refreshed', [count]), 'Coordinator');
end;

procedure TDeepRKeyCoordinator.CreateIPCHiddenWindow;
var
  wc: TWNDCLASSEX;
  atomResult: Word;
begin
  ZeroMemory(@wc, SizeOf(wc));
  wc.cbSize := SizeOf(wc);
  wc.lpfnWndProc := @IPCWindowProc;
  wc.hInstance := HInstance;
  wc.lpszClassName := RK_MMF_MAIN_WND_CLASS;

  atomResult := RegisterClassEx(wc);
  if atomResult = 0 then
  begin
    TBootstrap.Logger.Error(
      Format('RegisterClassEx failed: %d', [GetLastError]), 'IPC');
    Exit;
  end;

  // Use a hidden top-level window instead of HWND_MESSAGE
  // so Hook DLL can find it via FindWindow
  FIPCHwnd := CreateWindowEx(0, RK_MMF_MAIN_WND_CLASS, '',
    WS_POPUP, 0, 0, 0, 0, HWND_DESKTOP, 0, HInstance, nil);
  if FIPCHwnd = 0 then
    TBootstrap.Logger.Error(
      Format('CreateWindowEx(IPC) failed: %d', [GetLastError]), 'IPC')
  else
    TBootstrap.Logger.Info('IPC hidden window created', 'IPC');
end;

procedure TDeepRKeyCoordinator.DestroyIPCHiddenWindow;
begin
  if FIPCHwnd <> 0 then
  begin
    DestroyWindow(FIPCHwnd);
    FIPCHwnd := 0;
  end;
  UnregisterClass(RK_MMF_MAIN_WND_CLASS, HInstance);
end;

procedure TDeepRKeyCoordinator.InstallWinEventHooks;
const
  HookEvents: array[0..2] of DWORD = (
    EVENT_OBJECT_CREATE,
    EVENT_OBJECT_DESTROY,
    EVENT_SYSTEM_FOREGROUND
  );
var
  i: Integer;
  hook: THandle;
begin
  for i := Low(HookEvents) to High(HookEvents) do
  begin
    hook := SetWinEventHook(HookEvents[i], HookEvents[i],
      0, @WinEventProc, 0, 0,
      WINEVENT_OUTOFCONTEXT or WINEVENT_SKIPOWNPROCESS);
    if hook <> 0 then
      FWinEventHooks.Add(hook)
    else
      TBootstrap.Logger.Warn(
        Format('SetWinEventHook(%d) failed: %d', [HookEvents[i], GetLastError]),
        'Hook');
  end;

  TBootstrap.Logger.Info(
    Format('Installed %d WinEvent hooks', [FWinEventHooks.Count]), 'Hook');
end;

procedure TDeepRKeyCoordinator.UninstallWinEventHooks;
begin
  for var hook in FWinEventHooks do
    UnhookWinEvent(hook);
  FWinEventHooks.Clear;
end;

/// <summary>计算文件 SHA-256 哈希 (hex string)</summary>
function ComputeFileSHA256(const filePath: string): string;
var
  hFile: THandle;
  hProv: HCRYPTPROV;
  hHash: HCRYPTHASH;
  buf: array[0..4095] of Byte;
  bytesRead: DWORD;
  hashBuf: array[0..31] of Byte;
  hashLen: DWORD;
  i: Integer;
  hex: string;
begin
  Result := '';
  hFile := CreateFile(PChar(filePath), GENERIC_READ, FILE_SHARE_READ,
    nil, OPEN_EXISTING, 0, 0);
  if hFile = INVALID_HANDLE_VALUE then Exit;

  try
    if not CryptAcquireContextW(hProv, nil, nil, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) then
      Exit;
    try
      if not CryptCreateHash(hProv, CALG_SHA_256, 0, 0, hHash) then
        Exit;
      try
        while ReadFile(hFile, buf, SizeOf(buf), bytesRead, nil) and (bytesRead > 0) do
          CryptHashData(hHash, buf, bytesRead, 0);

        hashLen := SizeOf(hashBuf);
        if CryptGetHashParam(hHash, HP_HASHVAL, @hashBuf[0], hashLen, 0) then
        begin
          Result := '';
          for i := 0 to Integer(hashLen) - 1 do
          begin
            hex := Format('%.2x', [hashBuf[i]]);
            Result := Result + hex;
          end;
        end;
      finally
        CryptDestroyHash(hHash);
      end;
    finally
      CryptReleaseContext(hProv, 0);
    end;
  finally
    CloseHandle(hFile);
  end;
end;

procedure TDeepRKeyCoordinator.InitializeHookController;
var
  dllPath: string;
  dllHash: string;
  helperPath: string;
  dll32Path: string;
begin
  // T-500: Thread-level hook controller replaces global hook

  // Initialize Helper32 manager first (needed for 32-bit thread routing)
  dll32Path := ExtractFilePath(ParamStr(0)) + 'DeepRKeyHook32.dll';
  helperPath := ExtractFilePath(ParamStr(0)) + 'DeepRKey32.exe';
  if FileExists(dll32Path) and FileExists(helperPath) then
  begin
    FHelperManager := THelperManager.Create;
    FHelperManager.Initialize;
    if not FHelperManager.EnsureRunning then
      TBootstrap.Logger.Warn('Helper32 failed to start, 32-bit windows not covered', 'Hook')
    else
      TBootstrap.Logger.Info('Helper32 started (lazy per-thread routing)', 'Hook');
  end
  else
    TBootstrap.Logger.Info('32-bit Hook DLL/Helper not found, skipping 32-bit support', 'Hook');

  // Load 64-bit Hook DLL
  SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_APPLICATION_DIR);
  dllPath := ExtractFilePath(ParamStr(0)) + 'DeepRKeyHook64.dll';
  if not FileExists(dllPath) then
  begin
    TBootstrap.Logger.Warn(Format('Hook DLL not found: %s', [dllPath]), 'Hook');
    Exit;
  end;

  dllHash := ComputeFileSHA256(dllPath);
  if dllHash <> '' then
    TBootstrap.Logger.Info(Format('Hook DLL SHA-256: %s', [dllHash]), 'Hook');

  FHookController := THookController.Create(FTracker, FHelperManager);
  try
    FHookController.Initialize(dllPath);
    TBootstrap.Logger.Info('Thread-level hook controller initialized (T-500)', 'Hook');
  except
    on E: Exception do
    begin
      TBootstrap.Logger.Error(Format('HookController init failed: %s', [E.Message]), 'Hook');
      FreeAndNil(FHookController);
    end;
  end;
end;

procedure TDeepRKeyCoordinator.UninstallHookController;
begin
  if FHookController <> nil then
  begin
    FHookController.UnloadAllHooks;
    FreeAndNil(FHookController);
    TBootstrap.Logger.Info('Thread-level hooks uninstalled', 'Hook');
  end;
end;

procedure TDeepRKeyCoordinator.HandleIPCCommand(cmd: WPARAM; lParam: LPARAM);
  // Local helper: append a line to the diagnostic temp file
  procedure DiagWrite(const FilePath, S: string);
  var
    hFile: THandle;
    BytesWritten: DWORD;
    Utf8: TBytes;
  begin
    hFile := CreateFile(PChar(FilePath), FILE_APPEND_DATA, FILE_SHARE_READ, nil,
      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    if hFile = INVALID_HANDLE_VALUE then Exit;
    Utf8 := TEncoding.UTF8.GetBytes(S + sLineBreak);
    WriteFile(hFile, Utf8[0], Length(Utf8), BytesWritten, nil);
    CloseHandle(hFile);
  end;
var
  Dst: string;
begin
  // === CLI control commands ===
  case cmd of
    WM_RKEY_CMD_PAUSE:
    begin
      if not FPaused then
      begin
        FPaused := True;
        if Assigned(FOnPauseStateChanged) then FOnPauseStateChanged;
      end;
      Exit;
    end;
    WM_RKEY_CMD_RESUME:
    begin
      if FPaused then
      begin
        FPaused := False;
        if Assigned(FOnPauseStateChanged) then FOnPauseStateChanged;
      end;
      Exit;
    end;
    WM_RKEY_CMD_TOGGLE:
    begin
      FPaused := not FPaused;
      if Assigned(FOnPauseStateChanged) then FOnPauseStateChanged;
      Exit;
    end;
  end;

  // === Diagnostic queries (CLI --diagnostics / --health-check) ===
  // lParam = PID of the CLI process. Main process writes result to a
  // temp file named "DeepRKey_diag_<PID>.txt" which the CLI reads back.
  if (cmd >= 100) and (cmd <= 105) and (lParam <> 0) then
  begin
    Dst := GetEnvironmentVariable('TEMP') +
      '\DeepRKey_diag_' + IntToStr(DWORD(lParam)) + '.txt';

    // Erase any previous content
    DeleteFile(PChar(Dst));

    case cmd of
      100: begin
        if FHookController <> nil then
          DiagWrite(Dst, Format('Thread-level: %d threads, %d active',
            [FHookController.ThreadCount, FHookController.ActiveHookCount]))
        else
          DiagWrite(Dst, 'Not installed');
      end;
      101: DiagWrite(Dst, IntToStr(FTracker.WindowCount));
      102: DiagWrite(Dst, IntToStr(FTracker.ThreadCount));
      103: begin
        if FRouter <> nil then
          DiagWrite(Dst, IntToStr(FRouter.MMFReader.GetDroppedEventCount))
        else
          DiagWrite(Dst, 'N/A');
      end;
      104: DiagWrite(Dst, FGUID);
      105: begin
        if FPaused then DiagWrite(Dst, 'Yes') else DiagWrite(Dst, 'No');
      end;
    end;
  end;
end;

procedure TDeepRKeyCoordinator.HandleIPCNotification;
begin
  // PostMessage from Hook DLL arrived — drain MMF
  ProcessMMFEvents;
end;

procedure TDeepRKeyCoordinator.ProcessMMFEvents;
var
  events: TArray<TRKeyIpcEvent>;
  evt: TRKeyIpcEvent;
begin
  FRouter.ProcessNotification;
  events := FRouter.ReadAllEvents;

  for evt in events do
  begin
    case evt.EventKind of
      RK_EK_INIT_MENU:
        DispatchInitMenuEvent(HWND(evt.Hwnd));
      RK_EK_SYS_COMMAND:
        DispatchCommandEvent(HWND(evt.Hwnd), evt.CommandId);
    end;
  end;

  // Update heartbeat
  if FRouter <> nil then
    FRouter.UpdateHeartbeat;
end;

procedure TDeepRKeyCoordinator.DispatchInitMenuEvent(hWnd: HWND);
begin
  // T-430: 委托给命令分发器
  if FDispatcher <> nil then
    FDispatcher.DispatchInitMenuEvent(hWnd, FLastMenuRefreshTick);
end;

/// <summary>T-430: 处理需要 Coordinator 状态的特殊命令</summary>
function TDeepRKeyCoordinator.HandleSpecialCommand(hWnd: HWND; CommandId: UInt32): Boolean;
begin
  Result := True;

  // ClickThrough (需要定时器和字典跟踪)
  if CommandId = RK_SC_CLICK_THROUGH then
  begin
    FWindowOps.ToggleClickThrough(hWnd);
    // BUG-M9 修复：使用字典跟踪多窗口超时
    if (GetWindowLong(hWnd, GWL_EXSTYLE) and WS_EX_TRANSPARENT) <> 0 then
    begin
      // ClickThrough 启用：记录 60 秒后自动恢复
      FClickThroughWindows.AddOrSetValue(NativeUInt(hWnd),
        GetTickCount64 + 60000);
      FClickThroughTimer.Enabled := True;
      TBootstrap.Logger.Info(
        Format('ClickThrough enabled on $%x - 60s auto-restore started',
          [NativeUInt(hWnd)]), 'Coordinator');
    end
    else
    begin
      // ClickThrough 禁用：移除跟踪
      FClickThroughWindows.Remove(NativeUInt(hWnd));
      if FClickThroughWindows.Count = 0 then
        FClickThroughTimer.Enabled := False;
    end;
    Exit;
  end;

  // Drag by Mouse (需要 FDragByMouseEnabled 状态)
  if CommandId = RK_SC_DRAG_BY_MOUSE then
  begin
    SetDragByMouseEnabled(not FDragByMouseEnabled);
    TBootstrap.Logger.Info(
      Format('DragByMouse toggled: %s',
        [IfThen(FDragByMouseEnabled, 'ON', 'OFF')]), 'Coordinator');
    Exit;
  end;

  // Layout snapshot (需要 FLayoutManager)
  if CommandId = RK_SC_LAYOUT_SAVE then
  begin
    var snapshot := FLayoutManager.Capture;
    MessageBox(hWnd, PChar(Format('Layout saved to slot "%s" (%d windows, %d monitors)',
      [snapshot.SlotName, Length(snapshot.Windows), Length(snapshot.Monitors)])),
      'DeepRKey - Layout Snapshot', MB_OK or MB_ICONINFORMATION);
    TBootstrap.Logger.Info(Format('Layout saved: %d windows, %d monitors',
      [Length(snapshot.Windows), Length(snapshot.Monitors)]), 'Layout');
    Exit;
  end;

  if CommandId = RK_SC_LAYOUT_RESTORE then
  begin
    var count := FLayoutManager.Restore;
    if count > 0 then
    begin
      MessageBox(hWnd, PChar(Format('Restored %d windows from slot "%s"',
        [count, FLayoutManager.ActiveSlot.SlotName])),
        'DeepRKey - Layout Snapshot', MB_OK or MB_ICONINFORMATION);
      TBootstrap.Logger.Info(Format('Layout restored: %d windows', [count]),
        'Layout');
    end
    else
      MessageBox(hWnd, 'No saved layout found or no matching windows.',
        'DeepRKey - Layout Snapshot', MB_OK or MB_ICONWARNING);
    Exit;
  end;

  Result := False;  // 未处理的命令
end;

procedure TDeepRKeyCoordinator.DispatchCommandEvent(hWnd: HWND; CommandId: UInt32);
begin
  // T-430: 委托给命令分发器
  if FDispatcher <> nil then
    FDispatcher.DispatchCommand(hWnd, CommandId);
end;
procedure TDeepRKeyCoordinator.InstallMouseHook;
begin
  if FMouseHookHandle <> 0 then Exit;  // already installed
  FMouseHookHandle := SetWindowsHookEx(WH_MOUSE_LL, @MouseHookProc, HInstance, 0);
  if FMouseHookHandle <> 0 then
    TBootstrap.Logger.Info('Drag-by-mouse mouse hook installed', 'Hook')
  else
    TBootstrap.Logger.Warn(
      Format('SetWindowsHookEx(WH_MOUSE_LL) failed: %d', [GetLastError]), 'Hook');
end;

procedure TDeepRKeyCoordinator.UninstallMouseHook;
begin
  if FMouseHookHandle <> 0 then
  begin
    UnhookWindowsHookEx(FMouseHookHandle);
    FMouseHookHandle := 0;
    TBootstrap.Logger.Info('Mouse hook uninstalled', 'Hook');
  end;
end;

procedure TDeepRKeyCoordinator.SetDragByMouseEnabled(Enable: Boolean);
begin
  FDragByMouseEnabled := Enable;
  if Enable then
    InstallMouseHook
  else
    UninstallMouseHook;
  TBootstrap.Logger.Info(
    Format('DragByMouse %s', [IfThen(Enable, 'enabled', 'disabled')]),
    'Coordinator');
end;

procedure TDeepRKeyCoordinator.SetTitlebarButtonEnabled(Enable: Boolean);
begin
  FTitlebarButtonEnabled := Enable;
  if FTitlebarButton = nil then Exit;
  if Enable then
  begin
    FTitlebarButton.Start;
    // Set current target if there's an active window
    if FActiveTargetHwnd <> 0 then
      FTitlebarButton.SetTarget(FActiveTargetHwnd);
  end
  else
    FTitlebarButton.Stop;
  TBootstrap.Logger.Info(
    Format('TitlebarButton %s', [IfThen(Enable, 'enabled', 'disabled')]),
    'Coordinator');
end;

procedure TDeepRKeyCoordinator.OnTitlebarButtonClick(hWnd: HWND);
begin
  if (FMenuInjector <> nil) and IsWindow(hWnd) then
  begin
    // Show fallback popup menu at the button's position
    var rc: TRect;
    if (FTitlebarButton <> nil) and (FTitlebarButton.TargetHwnd = hWnd) then
    begin
      // Position menu below the button
      if GetWindowRect(FActiveTargetHwnd, rc) then
        FMenuInjector.ShowFallbackMenu(hWnd, rc.Right - 100, rc.Top + 25)
      else
        FMenuInjector.ShowFallbackMenu(hWnd, 100, 100);
    end;
  end;
end;

procedure TDeepRKeyCoordinator.RegisterGlobalHotkey;
begin
  if FHotkeyRegistered then Exit;
  // Ctrl+Alt+Space — doesn't conflict with PowerToys Run (Alt+Space)
  var mods := MOD_CONTROL or MOD_ALT;
  if RegisterHotKey(FIPCHwnd, FHotkeyId, mods, VK_SPACE) then
  begin
    FHotkeyRegistered := True;
    TBootstrap.Logger.Info('Global hotkey registered: Ctrl+Alt+Space', 'Hotkey');
  end
  else
    TBootstrap.Logger.Warn(
      Format('Failed to register global hotkey: %d', [GetLastError]), 'Hotkey');
end;

procedure TDeepRKeyCoordinator.UnregisterGlobalHotkey;
begin
  if FHotkeyRegistered then
  begin
    UnregisterHotKey(FIPCHwnd, FHotkeyId);
    FHotkeyRegistered := False;
    TBootstrap.Logger.Info('Global hotkey unregistered', 'Hotkey');
  end;
end;

procedure TDeepRKeyCoordinator.HandleHotkey;
begin
  if FPaused then Exit;
  if FActiveTargetHwnd = 0 then Exit;
  // Show fallback popup menu at the cursor position
  var pt: TPoint;
  GetCursorPos(pt);
  if (FMenuInjector <> nil) and IsWindow(FActiveTargetHwnd) then
    FMenuInjector.ShowFallbackMenu(FActiveTargetHwnd, pt.X, pt.Y);
end;

procedure TDeepRKeyCoordinator.OnClickThroughTimer(Sender: TObject);
begin
  // BUG-M9 修复：遍历字典，恢复超时的窗口
  var now := GetTickCount64;
  var toRemove: TList<NativeUInt> := nil;

  for var pair in FClickThroughWindows do
  begin
    var hWnd := THandle(pair.Key);
    var restoreAt := pair.Value;

    // 检查是否超时或窗口已销毁
    if (now >= restoreAt) or not IsWindow(hWnd) then
    begin
      if IsWindow(hWnd) then
      begin
        // 超时：检查是否仍处于 click-through 状态
        var exStyle := GetWindowLong(hWnd, GWL_EXSTYLE);
        if (exStyle and WS_EX_TRANSPARENT) <> 0 then
        begin
          FWindowOps.ToggleClickThrough(hWnd);
          TBootstrap.Logger.Info(
            Format('ClickThrough auto-restored on $%x after 60s safety timeout',
              [NativeUInt(hWnd)]), 'Coordinator');
        end;
      end;

      // 标记为待删除
      if toRemove = nil then
        toRemove := TList<NativeUInt>.Create;
      toRemove.Add(pair.Key);
    end;
  end;

  // 删除已处理的窗口
  if toRemove <> nil then
  begin
    for var key in toRemove do
      FClickThroughWindows.Remove(key);
    toRemove.Free;
  end;

  // 没有更多跟踪窗口时停止定时器
  if FClickThroughWindows.Count = 0 then
    FClickThroughTimer.Enabled := False;
end;

/// <summary>BUG-H7: 定期扫描清理无效窗口句柄（安全网）</summary>
procedure TDeepRKeyCoordinator.OnPurgeTimer(Sender: TObject);
begin
  if FMenuInjector <> nil then
    FMenuInjector.PurgeInvalidWindows;
  // T-500: Sweep idle thread hooks
  if FHookController <> nil then
    FHookController.SweepCheck;
end;

end.
