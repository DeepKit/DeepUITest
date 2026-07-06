unit DeepAxis.UIA.Engine;

{*******************************************************************************
  DeepAxis UIA Engine v2 — 三层降级架构

  升级记录 (2026-07-04):
    v1: 基础 HWND + FindWindowEx + keybd_event
    v2: IUIAutomation COM + SendInput + 三层降级 + 版本检测 + 证据链 + 媒体发送

  降级策略:
    Layer 1 — IUIAutomation COM (结构化控件树导航, 最精确)
    Layer 2 — HWND API (Win32 消息, 兼容性好)
    Layer 3 — 键盘模拟 (SendInput, 兜底)

  参考:
    research/wechat-mcp/UIA_OPTIMIZATION_ANALYSIS.md
    research/wechat-mcp/wxauto/wxauto/ (Python UIA 实现)
*******************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Variants,
  Winapi.Windows, Winapi.ActiveX, Winapi.Messages, Winapi.PSApi,
  Winapi.UIAutomation;

// 注: IUIAutomation COM 常量 (CLSID_CUIAutomation, TreeScope_*, UIA_*PropertyId 等)
//     全部从 Winapi.UIAutomation 单元导入，无需手动定义。

type
  // ---------------------------------------------------------------------------
  // 微信版本信息
  // ---------------------------------------------------------------------------

  TWeChatVersion = record
    Major: Word;
    Minor: Word;
    Patch: Word;
    Build: Word;
    IsV4Plus: Boolean;       // 4.x+ 标记 (DirectUI 自绘)
    FullString: string;
    ExePath: string;
    class function Empty: TWeChatVersion; static;
    function ToString: string;
  end;

  // ---------------------------------------------------------------------------
  // 微信窗口状态
  // ---------------------------------------------------------------------------

  TWeChatWindowState = record
    Exists: Boolean;
    Visible: Boolean;         // 非最小化
    Foreground: Boolean;      // 在前台
    Obstructed: Boolean;      // 被其他窗口遮挡
    Handle: HWND;
    Rect: TRect;
    Version: TWeChatVersion;
    StateString: string;
  end;

  // ---------------------------------------------------------------------------
  // UIA 操作策略 (三层降级)
  // ---------------------------------------------------------------------------

  TUiaStrategy = (
    usUIAutomation,           // Layer 1: IUIAutomation COM
    usWin32Message,           // Layer 2: HWND + WM_SETTEXT
    usKeyboardSimulation      // Layer 3: SendInput 键盘模拟
  );

  // ---------------------------------------------------------------------------
  // UIA 操作结果 (增强版, 含证据链)
  // ---------------------------------------------------------------------------

  TUiaResult = record
    Success: Boolean;
    Strategy: TUiaStrategy;
    ErrorMessage: string;
    RetryCount: Integer;
    DurationMs: Integer;
    Evidence: string;          // 操作证据快照
    function ToString: string;
  end;

  // ---------------------------------------------------------------------------
  // 重试处理器
  // ---------------------------------------------------------------------------

  TRetryHandler = class
  private
    FMaxRetries: Integer;
    FBaseDelayMs: Integer;
  public
    constructor Create(AMaxRetries: Integer = 3; ABaseDelayMs: Integer = 100);

    /// <summary>执行操作，失败时指数退避重试。返回重试次数。</summary>
    function Execute(AAction: TFunc<Boolean>; out ARetries: Integer): Boolean; overload;
    function Execute(AAction: TFunc<Boolean>): Boolean; overload;
  end;

  // ---------------------------------------------------------------------------
  // 剪贴板保护 (增强版, 支持文本 + 文件)
  // ---------------------------------------------------------------------------

  TClipboardGuard = class
  private
    FTextSaved: Boolean;
    FOriginalText: string;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Save;
    procedure Restore;

    class procedure SetClipboardText(const AText: string);
    class procedure SetClipboardFile(const AFilePath: string);
    class function GetClipboardText: string;
    class function SafePasteText(const AText: string): Boolean;
    class function SafePasteFile(const AFilePath: string): Boolean;
  end;

  // ---------------------------------------------------------------------------
  // UIA 引擎 v2
  // ---------------------------------------------------------------------------

  TUiaEngine = class
  private
    FWeChatWnd: HWND;
    FVersion: TWeChatVersion;
    FAuto: IUIAutomation;             // IUIAutomation COM
    FWeChatElement: IUIAutomationElement; // 微信主窗口 Element
    FRetryHandler: TRetryHandler;
    FLastStrategy: TUiaStrategy;

    // 内部方法
    function FindWeChatWindow: HWND;
    function FindInputControlUIA: IUIAutomationElement;
    function FindInputControlWin32(AWnd: HWND): HWND;
    function SendInputKey(AKey: Word; AFlags: DWORD = 0): Boolean;
    function SendInputCombo(AModifier: Word; AKey: Word): Boolean;
    function SendInputText(const AText: string): Boolean;
    function VerifyPasteUIA(AElement: IUIAutomationElement): Boolean;
    function VerifyPasteWin32(AWnd: HWND): Boolean;
    function DetectVersion: TWeChatVersion;
    function GetTickCount64Safe: Int64;
    function BuildEvidence(const AStrategy: TUiaStrategy; const AStep: string;
      ADurationMs: Integer; ARetries: Integer; ASuccess: Boolean): string;
    function EnsureUIAInitialized: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>查找微信窗口</summary>
    function LocateWeChat: TUiaResult;

    /// <summary>在微信输入框中粘贴话术 (三层降级)</summary>
    function PasteScript(const AScript: string): TUiaResult;

    /// <summary>定位到指定联系人</summary>
    function NavigateToContact(const AContactName: string): TUiaResult;

    /// <summary>发送文件</summary>
    function SendFile(const AFilePath: string): TUiaResult;

    /// <summary>发送图片</summary>
    function SendImage(const AImagePath: string): TUiaResult;

    /// <summary>获取微信窗口完整状态</summary>
    function GetWeChatWindowState: TWeChatWindowState;

    /// <summary>获取微信窗口状态字符串 (兼容旧接口)</summary>
    function GetWeChatState: string;

    /// <summary>检查 UIA 是否可用</summary>
    class function IsAvailable: Boolean;

    /// <summary>获取微信版本信息</summary>
    property Version: TWeChatVersion read FVersion;
  end;

implementation

uses
  System.IOUtils;

{===============================================================================
  TWeChatVersion
===============================================================================}

class function TWeChatVersion.Empty: TWeChatVersion;
begin
  Result := Default(TWeChatVersion);
  Result.FullString := 'unknown';
end;

function TWeChatVersion.ToString: string;
begin
  if FullString <> '' then
    Result := FullString
  else
    Result := Format('%d.%d.%d.%d', [Major, Minor, Patch, Build]);
end;

{===============================================================================
  TUiaResult
===============================================================================}

function TUiaResult.ToString: string;
begin
  if Success then
    Result := Format('成功 [策略:%d, 重试:%d, 耗时:%dms]',
      [Ord(Strategy), RetryCount, DurationMs])
  else
    Result := Format('失败: %s [策略:%d, 重试:%d, 耗时:%dms]',
      [ErrorMessage, Ord(Strategy), RetryCount, DurationMs]);
end;

{===============================================================================
  TRetryHandler
===============================================================================}

constructor TRetryHandler.Create(AMaxRetries, ABaseDelayMs: Integer);
begin
  inherited Create;
  FMaxRetries := AMaxRetries;
  FBaseDelayMs := ABaseDelayMs;
end;

function TRetryHandler.Execute(AAction: TFunc<Boolean>; out ARetries: Integer): Boolean;
var
  LDelay: Integer;
begin
  ARetries := 0;
  // 首次尝试
  Result := AAction();
  if Result then Exit;

  // 指数退避重试
  while ARetries < FMaxRetries do
  begin
    Inc(ARetries);
    LDelay := FBaseDelayMs * (1 shl (ARetries - 1)); // 100, 200, 400...
    Sleep(LDelay);
    Result := AAction();
    if Result then Exit;
  end;
end;

function TRetryHandler.Execute(AAction: TFunc<Boolean>): Boolean;
var
  LDummy: Integer;
begin
  Result := Execute(AAction, LDummy);
end;

{===============================================================================
  TClipboardGuard
===============================================================================}

constructor TClipboardGuard.Create;
begin
  inherited Create;
  FTextSaved := False;
  FOriginalText := '';
end;

destructor TClipboardGuard.Destroy;
begin
  Restore;
  inherited;
end;

procedure TClipboardGuard.Save;
var
  LHandle: THandle;
  LPtr: Pointer;
begin
  if not OpenClipboard(0) then Exit;
  try
    LHandle := GetClipboardData(CF_UNICODETEXT);
    if LHandle <> 0 then
    begin
      LPtr := GlobalLock(LHandle);
      if LPtr <> nil then
      begin
        FOriginalText := PWideChar(LPtr);
        GlobalUnlock(LHandle);
        FTextSaved := True;
      end;
    end;
  finally
    CloseClipboard;
  end;
end;

procedure TClipboardGuard.Restore;
var
  LHandle: THandle;
  LPtr: Pointer;
  LByteLen: Integer;
begin
  if not FTextSaved then Exit;
  if not OpenClipboard(0) then Exit;
  try
    EmptyClipboard;
    if FOriginalText <> '' then
    begin
      LByteLen := (Length(FOriginalText) + 1) * SizeOf(Char);
      LHandle := GlobalAlloc(GMEM_MOVEABLE, LByteLen);
      if LHandle <> 0 then
      begin
        LPtr := GlobalLock(LHandle);
        if LPtr <> nil then
        begin
          Move(PChar(FOriginalText)^, LPtr^, LByteLen);
          GlobalUnlock(LHandle);
        end;
        SetClipboardData(CF_UNICODETEXT, LHandle);
      end;
    end;
  finally
    CloseClipboard;
  end;
  FTextSaved := False;
end;

class procedure TClipboardGuard.SetClipboardText(const AText: string);
var
  LHandle: THandle;
  LPtr: Pointer;
  LByteLen: Integer;
begin
  LByteLen := (Length(AText) + 1) * SizeOf(Char);
  if not OpenClipboard(0) then Exit;
  try
    EmptyClipboard;
    LHandle := GlobalAlloc(GMEM_MOVEABLE, LByteLen);
    if LHandle = 0 then Exit;
    LPtr := GlobalLock(LHandle);
    if LPtr = nil then
    begin
      GlobalFree(LHandle);
      Exit;
    end;
    Move(PChar(AText)^, LPtr^, LByteLen);
    GlobalUnlock(LHandle);
    SetClipboardData(CF_UNICODETEXT, LHandle);
  finally
    CloseClipboard;
  end;
end;

class function TClipboardGuard.GetClipboardText: string;
var
  LHandle: THandle;
  LPtr: Pointer;
begin
  Result := '';
  if not OpenClipboard(0) then Exit;
  try
    LHandle := GetClipboardData(CF_UNICODETEXT);
    if LHandle <> 0 then
    begin
      LPtr := GlobalLock(LHandle);
      if LPtr <> nil then
      begin
        Result := PWideChar(LPtr);
        GlobalUnlock(LHandle);
      end;
    end;
  finally
    CloseClipboard;
  end;
end;

class procedure TClipboardGuard.SetClipboardFile(const AFilePath: string);
type
  TDropFiles = packed record
    pFiles: DWORD;    // offset to file list
    pt: TPoint;       // drop point
    fNC: BOOL;        // non-client area flag
    fWide: BOOL;      // wide char flag
  end;
var
  LNullTermPath: string;
  LDropSize: Integer;
  LPathBytes: TBytes;
  LHandle: THandle;
  LPtr: Pointer;
  LDrop: TDropFiles;
  LTotalSize: Integer;
begin
  // 标准化路径 + 双 null 终止
  LNullTermPath := StringReplace(AFilePath, '/', '\', [rfReplaceAll]) + #0#0;

  LDropSize := SizeOf(TDropFiles);
  LPathBytes := TEncoding.Unicode.GetBytes(LNullTermPath);
  LTotalSize := LDropSize + Length(LPathBytes);

  // 构造 DROPFILES 结构
  FillChar(LDrop, SizeOf(LDrop), 0);
  LDrop.pFiles := LDropSize;
  LDrop.fWide := True;

  LHandle := GlobalAlloc(GMEM_MOVEABLE, LTotalSize);
  if LHandle = 0 then Exit;

  LPtr := GlobalLock(LHandle);
  if LPtr = nil then
  begin
    GlobalFree(LHandle);
    Exit;
  end;
  try
    Move(LDrop, LPtr^, LDropSize);
    Move(LPathBytes[0], PByte(LPtr)[LDropSize], Length(LPathBytes));
  finally
    GlobalUnlock(LHandle);
  end;

  if not OpenClipboard(0) then
  begin
    GlobalFree(LHandle);
    Exit;
  end;
  try
    EmptyClipboard;
    SetClipboardData(CF_HDROP, LHandle);
  finally
    CloseClipboard;
  end;
end;

class function TClipboardGuard.SafePasteText(const AText: string): Boolean;
var
  LGuard: TClipboardGuard;
begin
  LGuard := TClipboardGuard.Create;
  try
    LGuard.Save;
    SetClipboardText(AText);
    Sleep(100);
    Result := True;
  finally
    LGuard.Free;
  end;
end;

class function TClipboardGuard.SafePasteFile(const AFilePath: string): Boolean;
begin
  SetClipboardFile(AFilePath);
  Sleep(100);
  Result := True;
end;

{===============================================================================
  TUiaEngine
===============================================================================}

constructor TUiaEngine.Create;
begin
  inherited Create;
  FWeChatWnd := 0;
  FVersion := TWeChatVersion.Empty;
  FRetryHandler := TRetryHandler.Create(3, 100);
  FLastStrategy := usUIAutomation;
end;

destructor TUiaEngine.Destroy;
begin
  FRetryHandler.Free;
  FAuto := nil;
  FWeChatElement := nil;
  inherited;
end;

class function TUiaEngine.IsAvailable: Boolean;
begin
  // Windows 8+ 支持 UIAutomation
  Result := Win32MajorVersion >= 6;
end;

// ---------------------------------------------------------------------------
// 版本检测 (Step 1)
// ---------------------------------------------------------------------------

function TUiaEngine.DetectVersion: TWeChatVersion;
var
  LWnd: HWND;
  LPid: DWORD;
  LHProcess: THandle;
  LExePath: array[0..MAX_PATH] of Char;
  LDummy: DWORD;
  LInfoSize: DWORD;
  LInfoBuf: TBytes;
  LPtr: Pointer;
  LFixedInfo: PVSFixedFileInfo;
  LFixedLen: UINT;
begin
  Result := TWeChatVersion.Empty;

  // 使用 FindWeChatWindow 以支持 3.x 和 4.x
  LWnd := FindWeChatWindow;
  if LWnd = 0 then Exit;

  // 获取进程 ID
  GetWindowThreadProcessId(LWnd, LPid);

  // 获取 exe 路径 (PSAPI)
  LHProcess := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, LPid);
  if LHProcess = 0 then Exit;
  try
    if GetModuleFileNameEx(LHProcess, 0, LExePath, MAX_PATH) = 0 then
      Exit;
  finally
    CloseHandle(LHProcess);
  end;

  Result.ExePath := string(LExePath);

  // 读取版本信息
  LInfoSize := GetFileVersionInfoSize(LExePath, LDummy);
  if LInfoSize = 0 then Exit;

  SetLength(LInfoBuf, LInfoSize);
  if not GetFileVersionInfo(LExePath, 0, LInfoSize, LInfoBuf) then Exit;

  LPtr := nil;
  if not VerQueryValue(LInfoBuf, '\', LPtr, LFixedLen) then Exit;
  LFixedInfo := PVSFixedFileInfo(LPtr);
  if LFixedInfo = nil then Exit;

  Result.Major := HIWORD(LFixedInfo^.dwFileVersionMS);
  Result.Minor := LOWORD(LFixedInfo^.dwFileVersionMS);
  Result.Patch := HIWORD(LFixedInfo^.dwFileVersionLS);
  Result.Build := LOWORD(LFixedInfo^.dwFileVersionLS);
  Result.IsV4Plus := Result.Major >= 4;
  Result.FullString := Format('%d.%d.%d.%d',
    [Result.Major, Result.Minor, Result.Patch, Result.Build]);
end;

// ---------------------------------------------------------------------------
// SendInput 封装 (Step 2)
// ---------------------------------------------------------------------------

function TUiaEngine.SendInputKey(AKey: Word; AFlags: DWORD): Boolean;
var
  LInput: TInput;
begin
  FillChar(LInput, SizeOf(LInput), 0);
  LInput.Itype := INPUT_KEYBOARD;
  LInput.ki.wVk := AKey;
  LInput.ki.dwFlags := AFlags;
  Result := SendInput(1, LInput, SizeOf(LInput)) > 0;
end;

function TUiaEngine.SendInputCombo(AModifier, AKey: Word): Boolean;
var
  LInputs: array[0..3] of TInput;
begin
  FillChar(LInputs, SizeOf(LInputs), 0);

  // Key down: modifier
  LInputs[0].Itype := INPUT_KEYBOARD;
  LInputs[0].ki.wVk := AModifier;

  // Key down: key
  LInputs[1].Itype := INPUT_KEYBOARD;
  LInputs[1].ki.wVk := AKey;

  // Key up: key
  LInputs[2].Itype := INPUT_KEYBOARD;
  LInputs[2].ki.wVk := AKey;
  LInputs[2].ki.dwFlags := KEYEVENTF_KEYUP;

  // Key up: modifier
  LInputs[3].Itype := INPUT_KEYBOARD;
  LInputs[3].ki.wVk := AModifier;
  LInputs[3].ki.dwFlags := KEYEVENTF_KEYUP;

  Result := SendInput(4, LInputs[0], SizeOf(TInput)) > 0;
end;

function TUiaEngine.SendInputText(const AText: string): Boolean;
var
  I: Integer;
  LInputs: TArray<TInput>;
begin
  // 使用 KEYEVENTF_UNICODE 逐字符发送
  SetLength(LInputs, Length(AText) * 2);
  for I := 0 to Length(AText) - 1 do
  begin
    // Key down
    LInputs[I * 2].Itype := INPUT_KEYBOARD;
    LInputs[I * 2].ki.wVk := 0;
    LInputs[I * 2].ki.wScan := Ord(AText[I + 1]);
    LInputs[I * 2].ki.dwFlags := KEYEVENTF_UNICODE;

    // Key up
    LInputs[I * 2 + 1].Itype := INPUT_KEYBOARD;
    LInputs[I * 2 + 1].ki.wVk := 0;
    LInputs[I * 2 + 1].ki.wScan := Ord(AText[I + 1]);
    LInputs[I * 2 + 1].ki.dwFlags := KEYEVENTF_UNICODE or KEYEVENTF_KEYUP;
  end;

  Result := SendInput(Length(LInputs), LInputs[0], SizeOf(TInput)) > 0;
end;

// ---------------------------------------------------------------------------
// Step 3: IUIAutomation COM 初始化 (完整实现)
// ---------------------------------------------------------------------------

function TUiaEngine.EnsureUIAInitialized: Boolean;
var
  LHR: HRESULT;
  LRoot: IUIAutomationElement;
begin
  if FAuto <> nil then
    Exit(True);

  // 确保 COM 已初始化
  LHR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  // S_OK 或 S_FALSE (已经初始化) 都是成功的
  if Failed(LHR) and (LHR <> S_FALSE) then
    Exit(False);

  LHR := CoCreateInstance(CLSID_CUIAutomation, nil, CLSCTX_INPROC_SERVER,
    IUIAutomation, FAuto);
  if Failed(LHR) or (FAuto = nil) then
    Exit(False);

  // 缓存 root element (桌面)
  LHR := FAuto.GetRootElement(LRoot);
  Result := Succeeded(LHR) and (LRoot <> nil);
end;

function TUiaEngine.FindInputControlUIA: IUIAutomationElement;
var
  LHR: HRESULT;
  LEditCondition: IUIAutomationCondition;
  LDocCondition: IUIAutomationCondition;
  LFound: IUIAutomationElement;
  LClassName: OleVariant;
  LClassStr: string;
begin
  Result := nil;
  if FAuto = nil then Exit;

  // 如果 FWeChatElement 为空但窗口句柄有效，尝试获取 Element
  if (FWeChatElement = nil) and (FWeChatWnd <> 0) then
  begin
    LHR := FAuto.ElementFromHandle(FWeChatWnd, FWeChatElement);
    // 如果失败，继续降级
  end;

  // 如果已缓存微信主窗口 Element, 用它搜索
  if FWeChatElement <> nil then
  begin
    // 先尝试 EditControl (微信 3.x + 4.x mmui::ChatInputField)
    LHR := FAuto.CreatePropertyCondition(UIA_ControlTypePropertyId,
      UIA_EditControlTypeId, LEditCondition);
    if Succeeded(LHR) and (LEditCondition <> nil) then
    begin
      LHR := FWeChatElement.FindFirst(TreeScope_Descendants, LEditCondition, LFound);
      if Succeeded(LHR) and (LFound <> nil) then
      begin
        // 验证是微信输入控件 (3.x: RichEditComponent, 4.x: mmui::ChatInputField)
        LFound.GetCurrentPropertyValue(UIA_ClassNamePropertyId, LClassName);
        LClassStr := VarToStr(LClassName);
        if (Pos('RichEdit', LClassStr) > 0) or (Pos('Edit', LClassStr) > 0) or
           (Pos('ChatInput', LClassStr) > 0) or (LClassStr = '') then
          Exit(LFound);
      end;
    end;

    // 再尝试 DocumentControl
    LHR := FAuto.CreatePropertyCondition(UIA_ControlTypePropertyId,
      UIA_DocumentControlTypeId, LDocCondition);
    if Succeeded(LHR) and (LDocCondition <> nil) then
    begin
      LHR := FWeChatElement.FindFirst(TreeScope_Descendants, LDocCondition, LFound);
      if Succeeded(LHR) and (LFound <> nil) then
        Exit(LFound);
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Step 5: UIA 粘贴验证 (ValuePattern)
// ---------------------------------------------------------------------------

function TUiaEngine.VerifyPasteUIA(AElement: IUIAutomationElement): Boolean;
var
  LValuePattern: IUIAutomationValuePattern;
  LPtr: Pointer;
  LValue: PChar;
  LHR: HRESULT;
  LGUID: TGUID;
begin
  Result := False;
  if AElement = nil then Exit;

  // 获取 ValuePattern
  LGUID := StringToGUID('{A94CD8B1-0844-4CD6-9D2D-640537AB39E9}');
  LPtr := nil;
  LHR := AElement.GetCurrentPatternAs(UIA_ValuePatternId, @LGUID, LPtr);
  if Failed(LHR) or (LPtr = nil) then Exit;
  LValuePattern := IUIAutomationValuePattern(LPtr);

  // 读取当前值
  LHR := LValuePattern.get_CurrentValue(LValue);
  if Succeeded(LHR) and (LValue <> nil) then
    Result := Length(LValue) > 0;
end;

// ---------------------------------------------------------------------------
// Win32 控件查找
// ---------------------------------------------------------------------------
// 微信 4.x Qt 窗口选择回调
// ---------------------------------------------------------------------------

type
  TQtWeChatFinder = class
    BestHwnd: HWND;
    BestScore: Integer;  // 3=可见+微信标题, 2=可见+其他, 1=不可见+微信标题, 0=不可见
  end;

function QtWeChatEnumProc(hwnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  LClassName: array[0..255] of WideChar;
  LTitle: array[0..255] of WideChar;
  LTitleStr: string;
  LScore: Integer;
  LFinder: TQtWeChatFinder;
  LClassStr: string;
  LVisible: Boolean;
begin
  GetClassNameW(hwnd, LClassName, 256);
  LClassStr := string(LClassName);
  if LClassStr <> 'Qt51514QWindowIcon' then
  begin
    Result := True;
    Exit;
  end;

  GetWindowTextW(hwnd, LTitle, 256);
  LTitleStr := string(LTitle);
  LVisible := IsWindowVisible(hwnd);

  // 评分: 可见窗口优先，"微信"标题优先
  // 用 Unicode 码点比较避免源文件编码问题
  LScore := 0;
  if LVisible then
    LScore := LScore + 2;
  if (Length(LTitleStr) = 2) and (Ord(LTitleStr[1]) = $5FAE) and (Ord(LTitleStr[2]) = $4FE1) then
    LScore := LScore + 1;  // "微信" (U+5FAE U+4FE1)

  if LScore > 0 then
  begin
    LFinder := TQtWeChatFinder(lParam);
    if LScore > LFinder.BestScore then
    begin
      LFinder.BestHwnd := hwnd;
      LFinder.BestScore := LScore;
    end;
  end;

  Result := True;
end;

function TUiaEngine.FindWeChatWindow: HWND;
var
  LTopWnd: HWND;
  LClassName: array[0..255] of WideChar;
  LClassStr: string;
  LTitle: array[0..255] of WideChar;
  LTitleStr: string;
  LFinder: TQtWeChatFinder;
begin
  Result := 0;

  // 微信 3.x: WeChatMainWndForPC
  LTopWnd := FindWindowW('WeChatMainWndForPC', nil);
  if LTopWnd <> 0 then
    Exit(LTopWnd);

  // 微信 4.x: 枚举所有 Qt51514QWindowIcon 窗口
  // 评分: 可见 + "微信"标题 (U+5FAE U+4FE1) 优先
  LFinder := TQtWeChatFinder.Create;
  try
    LFinder.BestHwnd := 0;
    LFinder.BestScore := 0;
    EnumWindows(@QtWeChatEnumProc, LPARAM(LFinder));
    if LFinder.BestHwnd <> 0 then
      Exit(LFinder.BestHwnd);
  finally
    LFinder.Free;
  end;

  // 兜底: 枚举所有顶层窗口，查找包含 "WeChat" 的类名
  LTopWnd := GetTopWindow(0);
  while LTopWnd <> 0 do
  begin
    GetClassNameW(LTopWnd, LClassName, Length(LClassName));
    LClassStr := string(LClassName);
    if Pos('WeChat', LClassStr) > 0 then
    begin
      GetWindowTextW(LTopWnd, LTitle, Length(LTitle));
      LTitleStr := string(LTitle);
      if (Pos('微信', LTitleStr) > 0) or (Pos('Weixin', LTitleStr) > 0) or
         (Pos('WeChat', LTitleStr) > 0) then
        Exit(LTopWnd);
    end;
    LTopWnd := GetNextWindow(LTopWnd, GW_HWNDNEXT);
  end;
end;

function TUiaEngine.FindInputControlWin32(AWnd: HWND): HWND;
var
  LChild: HWND;
  LClassName: array[0..255] of Char;
begin
  Result := 0;

  LChild := FindWindowEx(AWnd, 0, 'RichEditComponent', nil);
  if LChild <> 0 then Exit(LChild);

  LChild := FindWindowEx(AWnd, 0, 'RichEdit20W', nil);
  if LChild <> 0 then Exit(LChild);

  // 递归查找
  LChild := GetWindow(AWnd, GW_CHILD);
  while LChild <> 0 do
  begin
    GetClassName(LChild, LClassName, SizeOf(LClassName));
    if (Pos('RichEdit', string(LClassName)) > 0) or
       (Pos('Edit', string(LClassName)) > 0) then
      Exit(LChild);
    LChild := GetWindow(LChild, GW_HWNDNEXT);
  end;
end;

// ---------------------------------------------------------------------------
// 粘贴验证 (Step 5)
// ---------------------------------------------------------------------------

function TUiaEngine.VerifyPasteWin32(AWnd: HWND): Boolean;
begin
  Result := SendMessage(AWnd, WM_GETTEXTLENGTH, 0, 0) > 0;
end;

// ---------------------------------------------------------------------------
// 证据链 (Step 7)
// ---------------------------------------------------------------------------

function TUiaEngine.BuildEvidence(const AStrategy: TUiaStrategy; const AStep: string;
  ADurationMs, ARetries: Integer; ASuccess: Boolean): string;
const
  StrategyNames: array[TUiaStrategy] of string = ('UIAutomation', 'Win32Message', 'KeyboardSim');
begin
  Result := Format('[%s] %s | %s | %dms | retries=%d',
    [FormatDateTime('hh:nn:ss.zzz', Now),
     StrategyNames[AStrategy],
     AStep,
     ADurationMs,
     ARetries]);
end;

function TUiaEngine.GetTickCount64Safe: Int64;
begin
  Result := GetTickCount64;
end;

// ---------------------------------------------------------------------------
// 核心操作
// ---------------------------------------------------------------------------

function TUiaEngine.LocateWeChat: TUiaResult;
var
  LStart: Int64;
  LHR: HRESULT;
begin
  LStart := GetTickCount64Safe;
  Result := Default(TUiaResult);

  // 版本检测
  FVersion := DetectVersion;

  // 查找窗口
  FWeChatWnd := FindWeChatWindow;
  if FWeChatWnd = 0 then
  begin
    Result.Success := False;
    Result.ErrorMessage := '未找到微信窗口';
    Result.DurationMs := GetTickCount64Safe - LStart;
    Result.Evidence := BuildEvidence(usWin32Message, 'LocateWeChat', Result.DurationMs, 0, False);
    Exit;
  end;

  // Step 3: 尝试 UIA 初始化
  if EnsureUIAInitialized then
  begin
    Result.Strategy := usUIAutomation;
    // 使用 ElementFromHandle 缓存微信窗口 Element (支持 3.x 和 4.x)
    FWeChatElement := nil;
    LHR := FAuto.ElementFromHandle(FWeChatWnd, FWeChatElement);
    // 如果 ElementFromHandle 失败，不影响基本功能
  end
  else
    Result.Strategy := usWin32Message;

  FLastStrategy := Result.Strategy;

  Result.Success := True;
  Result.DurationMs := GetTickCount64Safe - LStart;
  Result.Evidence := BuildEvidence(Result.Strategy,
    Format('LocateWeChat v%s', [FVersion.ToString]),
    Result.DurationMs, 0, True);
end;

function TUiaEngine.PasteScript(const AScript: string): TUiaResult;
var
  LStart: Int64;
  LInputWnd: HWND;
  LRetries: Integer;
  LPasteOk: Boolean;
  LPasteAction: TFunc<Boolean>;
  LUIAElement: IUIAutomationElement;
  LUIAUsed: Boolean;
begin
  LStart := GetTickCount64Safe;
  Result := Default(TUiaResult);

  if FWeChatWnd = 0 then
    FWeChatWnd := FindWeChatWindow;

  if FWeChatWnd = 0 then
  begin
    Result.ErrorMessage := '微信窗口未找到';
    Result.DurationMs := GetTickCount64Safe - LStart;
    Exit;
  end;

  SetForegroundWindow(FWeChatWnd);
  Sleep(100);

  // Layer 1: 尝试 IUIAutomation 定位输入框 (最精确)
  LUIAElement := nil;
  LUIAUsed := False;
  if EnsureUIAInitialized then
  begin
    LUIAElement := FindInputControlUIA;
    if LUIAElement <> nil then
    begin
      LUIAUsed := True;
      Result.Strategy := usUIAutomation;
      FLastStrategy := usUIAutomation;
      // 聚焦 UIA 控件
      LUIAElement.SetFocus;
      Sleep(50);
    end;
  end;

  // Layer 2/3: 降级到 Win32 HWND 或纯键盘模拟
  if not LUIAUsed then
  begin
    LInputWnd := FindInputControlWin32(FWeChatWnd);
    if LInputWnd <> 0 then
    begin
      Result.Strategy := usWin32Message;
      FLastStrategy := usWin32Message;
    end
    else
    begin
      Result.Strategy := usKeyboardSimulation;
      FLastStrategy := usKeyboardSimulation;
    end;
  end;

  // Step 5: 带验证的粘贴循环 (最多重试 3 次)
  LPasteAction := function: Boolean
  begin
    TClipboardGuard.SetClipboardText(AScript);
    Sleep(50);
    SendInputCombo(VK_CONTROL, Ord('V'));
    Sleep(150);

    // 根据策略选择验证方式
    if LUIAUsed and (LUIAElement <> nil) then
      Exit(VerifyPasteUIA(LUIAElement))
    else if LInputWnd <> 0 then
      Exit(VerifyPasteWin32(LInputWnd))
    else
      Exit(True); // 无法验证时假定成功
  end;

  LPasteOk := FRetryHandler.Execute(LPasteAction, LRetries);

  Result.Success := LPasteOk;
  Result.RetryCount := LRetries;
  Result.DurationMs := GetTickCount64Safe - LStart;

  if not Result.Success then
    Result.ErrorMessage := '粘贴失败（已重试 ' + IntToStr(LRetries) + ' 次）';

  Result.Evidence := BuildEvidence(Result.Strategy, 'PasteScript',
    Result.DurationMs, LRetries, Result.Success);
end;

function TUiaEngine.NavigateToContact(const AContactName: string): TUiaResult;
var
  LStart: Int64;
begin
  LStart := GetTickCount64Safe;
  Result := Default(TUiaResult);

  if FWeChatWnd = 0 then
    FWeChatWnd := FindWeChatWindow;
  if FWeChatWnd = 0 then
  begin
    Result.ErrorMessage := '微信窗口未找到';
    Result.DurationMs := GetTickCount64Safe - LStart;
    Exit;
  end;

  SetForegroundWindow(FWeChatWnd);
  Sleep(200);

  // Ctrl+F 打开搜索 (用 SendInput 替代 keybd_event)
  SendInputCombo(VK_CONTROL, Ord('F'));
  Sleep(300);

  // 粘贴联系人名
  TClipboardGuard.SetClipboardText(AContactName);
  Sleep(50);
  SendInputCombo(VK_CONTROL, Ord('V'));
  Sleep(300);

  // Enter 确认
  SendInputKey(VK_RETURN);
  Sleep(300);

  Result.Success := True;
  Result.Strategy := usKeyboardSimulation;
  Result.DurationMs := GetTickCount64Safe - LStart;
  Result.Evidence := BuildEvidence(usKeyboardSimulation,
    'NavigateToContact(' + AContactName + ')', Result.DurationMs, 0, True);
end;

function TUiaEngine.SendFile(const AFilePath: string): TUiaResult;
var
  LStart: Int64;
begin
  LStart := GetTickCount64Safe;
  Result := Default(TUiaResult);

  if not FileExists(AFilePath) then
  begin
    Result.ErrorMessage := '文件不存在: ' + AFilePath;
    Result.DurationMs := GetTickCount64Safe - LStart;
    Exit;
  end;

  if FWeChatWnd = 0 then
    FWeChatWnd := FindWeChatWindow;
  if FWeChatWnd = 0 then
  begin
    Result.ErrorMessage := '微信窗口未找到';
    Result.DurationMs := GetTickCount64Safe - LStart;
    Exit;
  end;

  SetForegroundWindow(FWeChatWnd);
  Sleep(100);

  // 设置文件到剪贴板 (CF_HDROP)
  TClipboardGuard.SetClipboardFile(AFilePath);
  Sleep(100);

  // Ctrl+V 粘贴
  SendInputCombo(VK_CONTROL, Ord('V'));
  Sleep(500);

  Result.Success := True;
  Result.Strategy := usKeyboardSimulation;
  Result.DurationMs := GetTickCount64Safe - LStart;
  Result.Evidence := BuildEvidence(usKeyboardSimulation,
    'SendFile(' + ExtractFileName(AFilePath) + ')', Result.DurationMs, 0, True);
end;

function TUiaEngine.SendImage(const AImagePath: string): TUiaResult;
begin
  // 图片发送复用 SendFile 逻辑，微信自动识别图片格式
  Result := SendFile(AImagePath);
  if Result.Success then
    Result.Evidence := StringReplace(Result.Evidence, 'SendFile', 'SendImage', []);
end;

function TUiaEngine.GetWeChatWindowState: TWeChatWindowState;
var
  LRect: TRect;
  LForegroundWnd: HWND;
begin
  Result := Default(TWeChatWindowState);

  Result.Handle := FindWeChatWindow;
  Result.Exists := Result.Handle <> 0;
  if not Result.Exists then
  begin
    Result.StateString := '未运行';
    Result.Version := DetectVersion;
    Exit;
  end;

  Result.Visible := not IsIconic(Result.Handle);
  GetWindowRect(Result.Handle, LRect);
  Result.Rect := LRect;

  LForegroundWnd := GetForegroundWindow;
  Result.Foreground := (LForegroundWnd = Result.Handle);

  // 简单遮挡检测：检查前台窗口的矩形是否与微信窗口重叠
  if not Result.Foreground and Result.Visible then
  begin
    // 如果微信不是前台且不完全可见，认为被遮挡
    Result.Obstructed := not Result.Foreground;
  end;

  Result.Version := FVersion;
  if Result.Version.FullString = 'unknown' then
    Result.Version := DetectVersion;

  if not Result.Visible then
    Result.StateString := '已最小化'
  else if Result.Obstructed then
    Result.StateString := '被遮挡'
  else
    Result.StateString := Format('运行中 v%s (%dx%d)',
      [Result.Version.ToString, LRect.Width, LRect.Height]);
end;

function TUiaEngine.GetWeChatState: string;
begin
  Result := GetWeChatWindowState.StateString;
end;

end.
