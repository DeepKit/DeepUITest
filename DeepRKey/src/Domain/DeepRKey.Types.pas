unit DeepRKey.Types;

interface

uses
  System.SysUtils;

const
  // === 菜单 ID 体系 ===
  // 所有自定义 ID 落在 $7000-$7FF0 范围，低 4 位对齐
  RK_SC_BASE = $7000;
  RK_SC_MAX  = $7FF0;
  RK_SC_STEP = $0010;  // WM_SYSCOMMAND 低 4 位由系统使用

  // === 置顶 ===
  RK_SC_TOPMOST = RK_SC_BASE + $000;

  // === 透明度（5 档命名预设 + 自定义）===
  RK_SC_TRANS         = RK_SC_BASE + $010;  // 透明度组
  RK_SC_TRANS_100     = RK_SC_BASE + $020;  // 不透明 (100%)
  RK_SC_TRANS_75      = RK_SC_BASE + $030;  // 轻度 (75%)
  RK_SC_TRANS_50      = RK_SC_BASE + $040;  // 半透 (50%)
  RK_SC_TRANS_25      = RK_SC_BASE + $050;  // 浅透 (25%)
  RK_SC_TRANS_10      = RK_SC_BASE + $060;  // 几乎隐形 (10%)
  RK_SC_TRANS_CUSTOM  = RK_SC_BASE + $070;  // 自定义透明度对话框

  // === 移动到显示器（动态生成，此为 base）===
  RK_SC_MOVE_TO = RK_SC_BASE + $080;

  // === 对齐（5 位 + 边缘贴靠）===
  RK_SC_ALIGN             = RK_SC_BASE + $100;  // 对齐组
  RK_SC_ALIGN_TOP_LEFT    = RK_SC_BASE + $110;
  RK_SC_ALIGN_TOP_RIGHT   = RK_SC_BASE + $120;
  RK_SC_ALIGN_BOTTOM_LEFT = RK_SC_BASE + $130;
  RK_SC_ALIGN_BOTTOM_RIGHT= RK_SC_BASE + $140;
  RK_SC_ALIGN_CENTER      = RK_SC_BASE + $150;
  RK_SC_ALIGN_SNAP_EDGE   = RK_SC_BASE + $160;

  // === 卷起 ===
  RK_SC_ROLLUP = RK_SC_BASE + $200;

  // === 预设尺寸（动态生成，此为 base）===
  RK_SC_RESIZE = RK_SC_BASE + $300;

  // === 布局快照（v0.2 差异化功能）===
  RK_SC_LAYOUT_SNAPSHOT = RK_SC_BASE + $380;
  RK_SC_LAYOUT_SAVE     = RK_SC_BASE + $390;
  RK_SC_LAYOUT_RESTORE  = RK_SC_BASE + $3A0;

  // === v0.2 功能 ===
  RK_SC_HIDE_FOR_ALT_TAB = RK_SC_BASE + $400;
  RK_SC_CLICK_THROUGH    = RK_SC_BASE + $410;
  RK_SC_SAVE_SCREEN_SHOT = RK_SC_BASE + $420;
  RK_SC_INFORMATION      = RK_SC_BASE + $430;
  RK_SC_SEND_TO_BOTTOM   = RK_SC_BASE + $440;
  RK_SC_DIMMER_ON        = RK_SC_BASE + $450;  // legacy toggle (use submenu)
  RK_SC_DIMMER           = RK_SC_BASE + $500;  // dimmer submenu
  RK_SC_DIMMER_50        = RK_SC_BASE + $510;  // 50% dim
  RK_SC_DIMMER_70        = RK_SC_BASE + $520;  // 70% dim
  RK_SC_DIMMER_90        = RK_SC_BASE + $530;  // 90% dim
  RK_SC_DIMMER_OFF       = RK_SC_BASE + $460;  // legacy off (use 0% item)

  RK_SCREENSHOT          = RK_SC_BASE + $600;  // screenshot submenu
  RK_SC_SCREENSHOT_FILE  = RK_SC_BASE + $610;  // save to file + clipboard
  RK_SC_SCREENSHOT_CLIP  = RK_SC_BASE + $620;  // clipboard only

  RK_SC_DRAG_BY_MOUSE    = RK_SC_BASE + $470;
  RK_SC_RESIZABLE        = RK_SC_BASE + $480;

  // === 撤销/重做 ===
  RK_SC_UNDO = RK_SC_BASE + $800;
  RK_SC_REDO = RK_SC_BASE + $810;

  // === IPC 控制命令（CLI → 运行实例 via WM_APP）===
  WM_RKEY_IPC_CMD   = $B064;   // WM_APP + 100
  WM_RKEY_CMD_PAUSE  = 1;
  WM_RKEY_CMD_RESUME = 2;
  WM_RKEY_CMD_TOGGLE = 3;

  // === GUID 查询 (Hook DLL/CLI → 主进程 via WM_COPYDATA) — T-447 修复 ===
  // 调用方必须提供自己的 PID，服务端验证发送方窗口句柄的进程 PID
  // 取代旧的无验证查询（任意进程可获取 GUID 后伪造命令）
  CD_GUID_QUERY = $44524B47;  // 'DRKG' (DeepRKey GUID)

  // === IPC 命令 (CLI → 主进程 via WM_COPYDATA) — T-447 修复 ===
  // 使用 PID 验证替代纯 GUID 验证，防止跨进程伪造
  CD_IPC_CMD    = $44524B43;  // 'DRKC' (DeepRKey Command)

type
  /// <summary>GUID 查询结构 (T-447: 添加 PID 验证)</summary>
  /// <remarks>调用方必须提供自己的 PID，服务端通过 GetWindowThreadProcessId 验证</remarks>
  TRKeyGUIDQuery = packed record
    CallerPID: UInt32;      // 调用方进程 ID
    Reserved: UInt32;       // 保留字段（对齐）
  end;
  PRKeyGUIDQuery = ^TRKeyGUIDQuery;

  /// <summary>IPC 命令结构 (T-447: 添加 PID 验证)</summary>
  /// <remarks>调用方必须提供自己的 PID，服务端验证发送方窗口句柄的进程 PID</remarks>
  TRKeyIPCCommand = packed record
    Command: UInt32;
    Param: UInt32;
    CallerPID: UInt32;      // T-447: 调用方进程 ID
    Reserved: UInt32;       // 保留字段（对齐）
    AuthGUID: array[0..63] of Char;
  end;
  PRKeyIPCCommand = ^TRKeyIPCCommand;

type
  /// <summary>窗口操作类型</summary>
  TRKeyWindowOp = (
    rwoTopMost,
    rwoTransparency,
    rwoMoveToMonitor,
    rwoAlign,
    rwoRollUp,
    rwoResize,
    rwoLayoutSave,
    rwoLayoutRestore,
    rwoHideForAltTab,
    rwoClickThrough,
    rwoSaveScreenshot,
    rwoInformation,
    rwoSendToBottom,
    rwoDimmerOn,
    rwoDimmerOff,
    rwoDragByMouse,
    rwoResizable,
    rwoUndo,
    rwoRedo
  );

  /// <summary>Hook 准入跳过原因</summary>
  TRKeySkipReason = (
    skNone,
    skNotTopLevel,
    skNotVisible,
    skNoSysMenu,
    skToolWindow,
    skOwnedPopup,
    skCloakedWindow,
    skUAC,
    skSecureDesktop,
    skCredentialUI,
    skLockScreen,
    skFullScreen,
    skExcludedProcess,
    skGameOrAntiCheat,
    skPPL,
    skAVUI,
    skHighIntegrity,
    skUnknown
  );

  /// <summary>Hook 线程状态</summary>
  THookThreadState = (
    hsActive,
    hsPendingUnload,
    hsIdle,
    hsPendingInstall
  );

  /// <summary>事件类型</summary>
  TRKeyEventKind = (
    rekInitMenu,
    rekSysCommand,
    rekThreadHookReady,
    rekThreadHookFailed
  );

  /// <summary>Hook 安装模式</summary>
  TRKeyHookMode = (
    rkmStandard,    // 标准增强：线程级 WH_CALLWNDPROC
    rkmFallback,    // 零注入降级：托盘菜单 / 全局热键
    rkmSkip         // 跳过
  );

  /// <summary>对齐位置</summary>
  TRKeyAlignment = (
    raTopLeft,
    raTopRight,
    raBottomLeft,
    raBottomRight,
    raCenter,
    raSnapEdge
  );

  /// <summary>透明度预设</summary>
  TRKeyTransparencyPreset = (
    rtp100 = 0,
    rtp75  = 1,
    rtp50  = 2,
    rtp25  = 3,
    rtp10  = 4,
    rtpCustom = 5
  );

  /// <summary>Snap 冲突策略</summary>
  TRKeySnapConflictStrategy = (
    scsWindowsSnapPriority,  // 默认：Windows Snap 优先
    scsDeepRKeyPriority      // DeepRKey 对齐优先
  );

  /// <summary>窗口 DPI 感知模式</summary>
  TRKeyDpiAwareness = (
    rdaUnknown,
    rdaUnaware,
    rdaSystemAware,
    rdaPerMonitorAware,
    rdaPerMonitorV2
  );

  /// <summary>准入策略检查结果</summary>
  TRKeyHookEligibility = packed record
    IsEligible: Boolean;
    Reason: TRKeySkipReason;
    Mode: TRKeyHookMode;
    DpiAwareness: TRKeyDpiAwareness;
  end;

  /// <summary>Hook 控制器诊断快照，用于测试验证</summary>
  THookDiagnostics = packed record
    ThreadId: UInt32;
    RefCount: Integer;
    WindowCount: Integer;
    State: THookThreadState;
    LastActiveTick: UInt64;
    IsHotCache: Boolean;
  end;

  THookDiagnosticsSnapshot = TArray<THookDiagnostics>;

  /// <summary>窗口信息记录</summary>
  TRKeyWindowInfo = record
    Hwnd: UInt64;
    ProcessId: UInt32;
    ThreadId: UInt32;
    ClassName: string;
    ProcessName: string;
    IsTopMost: Boolean;
    Transparency: Byte;
    DpiAwareness: TRKeyDpiAwareness;
    procedure Clear;
  end;

implementation

{ TRKeyWindowInfo }

procedure TRKeyWindowInfo.Clear;
begin
  Hwnd := 0;
  ProcessId := 0;
  ThreadId := 0;
  ClassName := '';
  ProcessName := '';
  IsTopMost := False;
  Transparency := 255;
  DpiAwareness := rdaUnknown;
end;

end.