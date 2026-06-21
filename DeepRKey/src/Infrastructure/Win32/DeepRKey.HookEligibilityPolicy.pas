unit DeepRKey.HookEligibilityPolicy;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections,
  DeepRKey.Types;

type
  THookEligibilityPolicy = class
  private
    FExcludedProcesses: TList<string>;
    FExcludedClasses: TList<string>;
    function GetProcessName(Pid: DWORD): string;
    function GetClassName(hWnd: HWND): string;
    function GetIntegrityLevel(Pid: DWORD): DWORD;
    function IsPPL(Pid: DWORD): Boolean;
    function IsFullScreenWindow(hWnd: HWND): Boolean;
    function IsSecureDesktop: Boolean;
    function GetDpiAwareness(hWnd: HWND): TRKeyDpiAwareness;
  public
    constructor Create;
    destructor Destroy; override;

    function IsHookEligible(hWnd: HWND; out Reason: TRKeySkipReason): Boolean; overload;
    function IsHookEligible(hWnd: HWND): TRKeyHookEligibility; overload;
    function ShouldHookWindow(hWnd: HWND): Boolean;
    procedure AddExcludedProcess(const ProcessName: string);
    procedure AddExcludedClass(const ClassName: string);
  end;

implementation

uses
  Winapi.TlHelp32, Winapi.DwmApi;

const
  // Win32 security constants
  SECURITY_MANDATORY_MEDIUM_RID = $2000;
  SECURITY_MANDATORY_HIGH_RID   = $3000;
  TokenIntegrityLevel = 25;
  // T-011: DPI awareness context values
  DPI_AWARENESS_CONTEXT_UNAWARE              = -1;
  DPI_AWARENESS_CONTEXT_SYSTEM_AWARE         = -2;
  DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE    = -3;
  DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4;

type
  // T-011: Function pointer types for DPI APIs (dynamically loaded)
  TGetWindowDpiAwarenessContextFn = function(targetWnd: HWND): THandle; stdcall;
  TGetAwarenessFromDpiAwarenessContextFn = function(value: THandle): Integer; stdcall;
  TGetProcessDpiAwarenessFn = function(hProcess: THandle; out awarenessValue: Integer): BOOL; stdcall;

type
  /// BUG-P2 修复：TOKEN_MANDATORY_LABEL 包含变长 SID 内联数据（~68 字节），
  /// 不能用固定大小记录。使用足够大的缓冲区防止截断。
  TTokenMandatoryLabelBuf = record
    &Label: TSidAndAttributes;
    _Reserved: array[0..255] of Byte;  // 保留 SID 内联存储空间
  end;
  PTokenMandatoryLabelBuf = ^TTokenMandatoryLabelBuf;

function GetSidSubAuthority(Sid: PSID; nSubAuthority: DWORD): PDWORD; stdcall;
  external 'advapi32.dll' name 'GetSidSubAuthority';
function GetSidSubAuthorityCount(Sid: PSID): PUCHAR; stdcall;
  external 'advapi32.dll' name 'GetSidSubAuthorityCount';

function GetProcessInformation(hProcess: THandle;
  ProcessInformationClass: DWORD; ProcessInformation: Pointer;
  ProcessInformationSize: DWORD): BOOL; stdcall;
  external 'kernel32.dll' name 'GetProcessInformation';

const
  ProcessProtectionLevelInfo = 61;
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

type
  PProcessProtectionLevelInfo = ^TProcessProtectionLevelInfo;
  TProcessProtectionLevelInfo = record
    ProtectionLevel: DWORD;
  end;

{ THookEligibilityPolicy }

constructor THookEligibilityPolicy.Create;
begin
  FExcludedProcesses := TList<string>.Create;
  FExcludedClasses := TList<string>.Create;

  FExcludedProcesses.Add('csrss.exe');
  FExcludedProcesses.Add('smss.exe');
  FExcludedProcesses.Add('winlogon.exe');
  FExcludedProcesses.Add('lsass.exe');
  FExcludedProcesses.Add('services.exe');
  FExcludedProcesses.Add('svchost.exe');
  FExcludedProcesses.Add('System');
  FExcludedProcesses.Add('Idle');

  FExcludedClasses.Add('#32770');
  FExcludedClasses.Add('Progman');
  FExcludedClasses.Add('WorkerW');
  FExcludedClasses.Add('Shell_TrayWnd');
  FExcludedClasses.Add('TaskSwitcherWnd');
end;

destructor THookEligibilityPolicy.Destroy;
begin
  FExcludedProcesses.Free;
  FExcludedClasses.Free;
  inherited;
end;

function THookEligibilityPolicy.ShouldHookWindow(hWnd: HWND): Boolean;
begin
  if not IsWindow(hWnd) then
    Exit(False);

  var style := GetWindowLong(hWnd, GWL_STYLE);
  var exStyle := GetWindowLong(hWnd, GWL_EXSTYLE);

  Result :=
    IsWindowVisible(hWnd) and
    ((style and WS_SYSMENU) <> 0) and
    ((exStyle and WS_EX_TOOLWINDOW) = 0) and
    ((style and WS_CHILD) = 0) and
    ((style and WS_POPUP) = 0);

  // BUG-H9 修复：移除 IsCloakedWindow 检查（跨进程 DWM API 调用），
  // 延迟到 PreInject 时再验证，避免在 EVENT_OBJECT_CREATE 回调中阻塞
end;

function THookEligibilityPolicy.IsHookEligible(hWnd: HWND;
  out Reason: TRKeySkipReason): Boolean;
begin
  Reason := skNone;

  if not IsWindow(hWnd) then
  begin
    Reason := skUnknown;
    Exit(False);
  end;

  if not ShouldHookWindow(hWnd) then
  begin
    var style := GetWindowLong(hWnd, GWL_STYLE);
    if (style and WS_SYSMENU) = 0 then
      Reason := skNoSysMenu
    else if not IsWindowVisible(hWnd) then
      Reason := skNotVisible
    else
      Reason := skNotTopLevel;
    Exit(False);
  end;

  var className := GetClassName(hWnd);
  for var cls in FExcludedClasses do
    if SameText(className, cls) then
    begin
      Reason := skExcludedProcess;
      Exit(False);
    end;

  var pid: DWORD;
  GetWindowThreadProcessId(hWnd, @pid);
  if pid = 0 then
  begin
    Reason := skUnknown;
    Exit(False);
  end;

  var processName := GetProcessName(pid);
  for var proc in FExcludedProcesses do
    if SameText(processName, proc) then
    begin
      Reason := skExcludedProcess;
      Exit(False);
    end;

  var integrity := GetIntegrityLevel(pid);
  if integrity >= SECURITY_MANDATORY_HIGH_RID then
  begin
    Reason := skHighIntegrity;
    Exit(False);
  end;

  if IsPPL(pid) then
  begin
    Reason := skPPL;
    Exit(False);
  end;

  if IsSecureDesktop then
  begin
    Reason := skSecureDesktop;
    Exit(False);
  end;

  if IsFullScreenWindow(hWnd) then
  begin
    Reason := skFullScreen;
    Exit(False);
  end;

  Result := True;
end;

function THookEligibilityPolicy.IsHookEligible(hWnd: HWND): TRKeyHookEligibility;
begin
  var reason: TRKeySkipReason;
  Result.IsEligible := IsHookEligible(hWnd, reason);
  Result.Reason := reason;
  Result.Mode := rkmStandard;
  if not Result.IsEligible then
    Result.Mode := rkmSkip;
  Result.DpiAwareness := rdaUnknown;
  if Result.IsEligible then
    Result.DpiAwareness := GetDpiAwareness(hWnd);
end;

function THookEligibilityPolicy.GetProcessName(Pid: DWORD): string;
begin
  Result := '';
  var snap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if snap = INVALID_HANDLE_VALUE then
    Exit;

  var pe: TProcessEntry32;
  pe.dwSize := SizeOf(TProcessEntry32);
  if Process32First(snap, pe) then
  begin
    repeat
      if pe.th32ProcessID = pid then
      begin
        Result := string(pe.szExeFile);
        Break;
      end;
    until not Process32Next(snap, pe);
  end;
  CloseHandle(snap);
end;

function THookEligibilityPolicy.GetClassName(hWnd: HWND): string;
begin
  SetLength(Result, 256);
  var len := Winapi.Windows.GetClassName(hWnd, PChar(Result), 256);
  SetLength(Result, len);
end;

function THookEligibilityPolicy.GetIntegrityLevel(Pid: DWORD): DWORD;
var
  hProcess, hToken: THandle;
  buf: TTokenMandatoryLabelBuf;
  retLen: DWORD;
  subAuthCount: PUCHAR;
  lastSubAuth: PDWORD;
begin
  // BUG-P2 修复：默认返回 HIGH，fail-safe 而非 fail-open
  Result := SECURITY_MANDATORY_HIGH_RID;

  hProcess := OpenProcess(PROCESS_QUERY_INFORMATION, False, pid);
  if hProcess = 0 then
    Exit;

  try
    if not OpenProcessToken(hProcess, TOKEN_QUERY, hToken) then
      Exit;
    try
      FillChar(buf, SizeOf(buf), 0);
      if not GetTokenInformation(hToken, TTokenInformationClass(TokenIntegrityLevel),
        @buf, SizeOf(buf), retLen) then
        Exit;  // 失败时返回 HIGH（fail-safe）

      subAuthCount := GetSidSubAuthorityCount(buf.&Label.Sid);
      if (subAuthCount = nil) or (subAuthCount^ = 0) then
        Exit;

      lastSubAuth := GetSidSubAuthority(buf.&Label.Sid, subAuthCount^ - 1);
      if lastSubAuth = nil then
        Exit;

      Result := lastSubAuth^;
    finally
      CloseHandle(hToken);
    end;
  finally
    CloseHandle(hProcess);
  end;
end;

function THookEligibilityPolicy.IsPPL(Pid: DWORD): Boolean;
begin
  Result := False;
  var hProcess := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid);
  if hProcess = 0 then
    Exit;

  var protection: TProcessProtectionLevelInfo;
  if GetProcessInformation(hProcess, ProcessProtectionLevelInfo,
    @protection, SizeOf(protection)) then
    Result := protection.ProtectionLevel <> 0;
  CloseHandle(hProcess);
end;

function THookEligibilityPolicy.IsFullScreenWindow(hWnd: HWND): Boolean;
begin
  var rect: TRect;
  if not GetWindowRect(hWnd, rect) then
    Exit(False);

  var screenRect: TRect;
  screenRect.Left := 0;
  screenRect.Top := 0;
  screenRect.Right := GetSystemMetrics(SM_CXSCREEN);
  screenRect.Bottom := GetSystemMetrics(SM_CYSCREEN);

  Result := (rect.Left <= 0) and (rect.Top <= 0) and
    (rect.Right >= screenRect.Right) and (rect.Bottom >= screenRect.Bottom);

  if not Result then
    Exit;

  var style := GetWindowLong(hWnd, GWL_STYLE);
  Result := (style and WS_SYSMENU) = 0;
end;

function THookEligibilityPolicy.IsSecureDesktop: Boolean;
begin
  var desktopName: array[0..255] of Char;
  var hDesk := OpenInputDesktop(0, False, GENERIC_READ);
  if hDesk = 0 then
    Exit(True);

  var len: DWORD;
  Result := GetUserObjectInformation(hDesk, UOI_NAME, @desktopName,
    SizeOf(desktopName), len);
  CloseHandle(hDesk);

  if Result then
    Result := SameText(string(desktopName), 'Winlogon');
end;

function THookEligibilityPolicy.GetDpiAwareness(hWnd: HWND): TRKeyDpiAwareness;
var
  user32: HMODULE;
  getWindowCtx: TGetWindowDpiAwarenessContextFn;
  getAwareness: TGetAwarenessFromDpiAwarenessContextFn;
  ctx: THandle;
  awarenessVal: Integer;
  procHandle: THandle;
  getProcAwareness: TGetProcessDpiAwarenessFn;
  pid: DWORD;
begin
  Result := rdaPerMonitorV2;  // Safe default for Win10/11

  // Strategy 1: Try GetWindowDpiAwarenessContext + GetAwarenessFromDpiAwarenessContext
  // Available on Windows 10 version 1607+
  user32 := GetModuleHandle('user32.dll');
  if user32 <> 0 then
  begin
    @getWindowCtx := GetProcAddress(user32, 'GetWindowDpiAwarenessContext');
    @getAwareness := GetProcAddress(user32, 'GetAwarenessFromDpiAwarenessContext');
    if Assigned(getWindowCtx) and Assigned(getAwareness) then
    begin
      ctx := getWindowCtx(hWnd);
      if ctx <> 0 then
      begin
        awarenessVal := getAwareness(ctx);
        case awarenessVal of
          DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: Exit(rdaPerMonitorV2);
          DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE:    Exit(rdaPerMonitorAware);
          DPI_AWARENESS_CONTEXT_SYSTEM_AWARE:         Exit(rdaSystemAware);
          DPI_AWARENESS_CONTEXT_UNAWARE:              Exit(rdaUnaware);
        end;
      end;
    end;

    // Strategy 2: Fallback to GetProcessDpiAwareness (Windows 8.1+)
    @getProcAwareness := GetProcAddress(user32, 'GetProcessDpiAwareness');
    if Assigned(getProcAwareness) and (hWnd <> 0) then
    begin
      GetWindowThreadProcessId(hWnd, @pid);
      procHandle := OpenProcess($0400 {PROCESS_QUERY_INFORMATION}, False, pid);
      if procHandle <> 0 then
      begin
        try
          if getProcAwareness(procHandle, awarenessVal) then
          begin
            case awarenessVal of
              0: Exit(rdaUnaware);           // PROCESS_DPI_UNAWARE
              1: Exit(rdaSystemAware);       // PROCESS_SYSTEM_DPI_AWARE
              2: Exit(rdaPerMonitorAware);   // PROCESS_PER_MONITOR_DPI_AWARE
            end;
          end;
        finally
          CloseHandle(procHandle);
        end;
      end;
    end;
  end;
end;

procedure THookEligibilityPolicy.AddExcludedProcess(const ProcessName: string);
begin
  if not FExcludedProcesses.Contains(ProcessName) then
    FExcludedProcesses.Add(ProcessName);
end;

procedure THookEligibilityPolicy.AddExcludedClass(const ClassName: string);
begin
  if not FExcludedClasses.Contains(ClassName) then
    FExcludedClasses.Add(ClassName);
end;

end.