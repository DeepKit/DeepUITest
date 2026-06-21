unit DeepRKey.HelperManager;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections,
  DeepRKey.HookShared,
  DeepRKey.IPC.Pipe;

type
  /// <summary>Helper32 崩溃恢复状态</summary>
  THelperState = (hsNone, hsStarting, hsRunning, hsCrashed, hsStopped);

  /// <summary>Helper32 进程管理器：延迟启动 + 管道通信 + 双向 watchdog</summary>
  THelperManager = class
  private
    FPipeClient: TRKeyPipeClient;
    FHelperProcess: THandle;
    FHelperPath: string;
    FState: THelperState;
    FRestartCount: Integer;
    FRestartWindowStart: UInt64;
    FWatchdogTimer: THandle;
    FHeartbeatCount: Integer;
    FMissedHeartbeats: Integer;
    procedure ExtractHelperExe;
    procedure LaunchHelper;
    function WaitForHelperReady(TimeoutMs: UInt32): Boolean;
    procedure DoHeartbeat;
    procedure HandleCrash;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>初始化：提取 Helper32 EXE，必要时启动</summary>
    procedure Initialize;

    /// <summary>确保 Helper32 正在运行（延迟启动，首个 32 位目标需要时调用）</summary>
    function EnsureRunning: Boolean;

    /// <summary>发送 Hook 安装命令</summary>
    function InstallHook(ThreadId: DWORD): Boolean;

    /// <summary>发送 Hook 卸载命令</summary>
    function UninstallHook(ThreadId: DWORD): Boolean;

    /// <summary>发送退出命令</summary>
    procedure Shutdown;

    /// <summary>检查 Helper32 是否运行中</summary>
    function IsRunning: Boolean;

    /// <summary>当前状态</summary>
    property State: THelperState read FState;

    /// <summary>管道客户端（用于心跳等）</summary>
    property PipeClient: TRKeyPipeClient read FPipeClient;
  end;

const
  RK_HELPER_MAX_RESTARTS = 3;       // 5 分钟内最多重启 3 次
  RK_HELPER_RESTART_WINDOW_MS = 300000; // 5 分钟窗口
  RK_HELPER_HEARTBEAT_INTERVAL_MS = 3000; // 3 秒心跳
  RK_HELPER_HEARTBEAT_TIMEOUT_MS = 2;    // 连续 2 次无响应 = 崩溃

implementation

uses
  System.Zip, System.IOUtils;

{ THelperManager }

constructor THelperManager.Create;
begin
  FPipeClient := nil;
  FHelperProcess := 0;
  FState := hsNone;
  FRestartCount := 0;
  FRestartWindowStart := 0;
  FWatchdogTimer := 0;
  FHeartbeatCount := 0;
  FMissedHeartbeats := 0;
  FHelperPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'DeepRKey32.exe');
end;

destructor THelperManager.Destroy;
begin
  Shutdown;
  if FWatchdogTimer <> 0 then
    CloseHandle(FWatchdogTimer);
  inherited;
end;

procedure THelperManager.ExtractHelperExe;
begin
  if TFile.Exists(FHelperPath) then
    Exit;

  // v0.1: 从外部复制（Phase 1 时已编译到 bin/）
  // v0.2+: 从 RT_RCDATA 资源提取
  var srcPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'DeepRKey32.exe');
  if TFile.Exists(srcPath) and (srcPath <> FHelperPath) then
    TFile.Copy(srcPath, FHelperPath, True);
end;

procedure THelperManager.Initialize;
begin
  ExtractHelperExe;
  var guid := TGUID.NewGuid.ToString;
  guid := guid.Replace('{', '').Replace('}', '').Replace('-', '');
  FPipeClient := TRKeyPipeClient.Create(guid);
end;

procedure THelperManager.LaunchHelper;
begin
  if FHelperProcess <> 0 then
  begin
    CloseHandle(FHelperProcess);
    FHelperProcess := 0;
  end;

  FState := hsStarting;

  // 检查重启频率
  var now := GetTickCount64;
  if now - FRestartWindowStart > RK_HELPER_RESTART_WINDOW_MS then
  begin
    FRestartCount := 0;
    FRestartWindowStart := now;
  end;

  if FRestartCount >= RK_HELPER_MAX_RESTARTS then
  begin
    FState := hsCrashed;
    raise Exception.CreateFmt(
      'Helper32 restarted %d times in 5 minutes, giving up',
      [FRestartCount]);
  end;

  var pi: TProcessInformation;
  var si: TStartupInfo;
  ZeroMemory(@si, SizeOf(si));
  si.cb := SizeOf(si);

  var cmdLine := Format('"%s" --pipe=%s', [FHelperPath, FPipeClient.GUID]);
  if not CreateProcess(nil, PChar(cmdLine), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, si, pi) then
    raise Exception.CreateFmt('Failed to launch Helper32: %s (error %d)',
      [FHelperPath, GetLastError]);

  FHelperProcess := pi.hProcess;
  CloseHandle(pi.hThread);
  Inc(FRestartCount);

  OutputDebugString(PChar(Format('[DeepRKey] Helper32 launched (PID=%d, restart #%d)',
    [pi.dwProcessId, FRestartCount])));
end;

function THelperManager.WaitForHelperReady(TimeoutMs: UInt32): Boolean;
begin
  var start := GetTickCount64;
  Result := False;

  while (GetTickCount64 - start) < TimeoutMs do
  begin
    if FPipeClient.Connect(500) then
    begin
      // 发送握手
      var data: TBytes;
      SetLength(data, 0);
      if FPipeClient.SendFrame(pcHeartbeat, data) then
      begin
        FState := hsRunning;
        FMissedHeartbeats := 0;
        Exit(True);
      end;
    end;
    Sleep(100);
  end;
end;

function THelperManager.EnsureRunning: Boolean;
begin
  // 已运行
  if (FState = hsRunning) and FPipeClient.IsConnected then
    Exit(True);

  // 首次启动
  if FState = hsNone then
  begin
    LaunchHelper;
    Result := WaitForHelperReady(RK_HELPER_HEARTBEAT_INTERVAL_MS * 3);
    if Result then
      FState := hsRunning;
    Exit(Result);
  end;

  // 崩溃恢复
  if FState = hsCrashed then
  begin
    HandleCrash;
    Exit(False);
  end;

  // 重新启动
  LaunchHelper;
  Result := WaitForHelperReady(RK_HELPER_HEARTBEAT_INTERVAL_MS * 3);
  if Result then
    FState := hsRunning;
end;

procedure THelperManager.DoHeartbeat;
begin
  if FState <> hsRunning then
    Exit;

  if not FPipeClient.IsConnected then
  begin
    Inc(FMissedHeartbeats);
    if FMissedHeartbeats >= RK_HELPER_HEARTBEAT_TIMEOUT_MS then
    begin
      FState := hsCrashed;
      HandleCrash;
    end;
    Exit;
  end;

  var data: TBytes;
  SetLength(data, 0);
  if FPipeClient.SendFrame(pcHeartbeat, data) then
  begin
    FMissedHeartbeats := 0;
    Inc(FHeartbeatCount);
  end
  else
  begin
    Inc(FMissedHeartbeats);
    if FMissedHeartbeats >= RK_HELPER_HEARTBEAT_TIMEOUT_MS then
    begin
      FState := hsCrashed;
      HandleCrash;
    end;
  end;
end;

procedure THelperManager.HandleCrash;
begin
  OutputDebugString('[DeepRKey] Helper32 crash detected, attempting restart...');

  // 断开旧连接
  FPipeClient.Disconnect;

  // 终止旧进程
  if FHelperProcess <> 0 then
  begin
    TerminateProcess(FHelperProcess, 0);
    CloseHandle(FHelperProcess);
    FHelperProcess := 0;
  end;

  // 尝试重启
  try
    LaunchHelper;
    if WaitForHelperReady(RK_HELPER_HEARTBEAT_INTERVAL_MS * 3) then
    begin
      FState := hsRunning;
      OutputDebugString('[DeepRKey] Helper32 restarted successfully');
    end
    else
    begin
      FState := hsCrashed;
      OutputDebugString('[DeepRKey] Helper32 restart failed');
    end;
  except
    on E: Exception do
    begin
      FState := hsCrashed;
      OutputDebugString(PChar(Format('[DeepRKey] Helper32 restart error: %s', [E.Message])));
    end;
  end;
end;

function THelperManager.InstallHook(ThreadId: DWORD): Boolean;
begin
  Result := False;
  if not EnsureRunning then
    Exit;

  var data: TBytes;
  SetLength(data, SizeOf(DWORD));
  Move(ThreadId, data[0], SizeOf(DWORD));
  Result := FPipeClient.SendFrame(pcInstallHook, data);
end;

function THelperManager.UninstallHook(ThreadId: DWORD): Boolean;
begin
  Result := False;
  if not EnsureRunning then
    Exit;

  var data: TBytes;
  SetLength(data, SizeOf(DWORD));
  Move(ThreadId, data[0], SizeOf(DWORD));
  Result := FPipeClient.SendFrame(pcUninstallHook, data);
end;

procedure THelperManager.Shutdown;
begin
  if FState = hsRunning then
  begin
    var data: TBytes;
    SetLength(data, 0);
    FPipeClient.SendFrame(pcShutdown, data);
    FPipeClient.Disconnect;
  end;

  if FHelperProcess <> 0 then
  begin
    // T-446: 2 秒内等待优雅退出，超时后强制终止
    if WaitForSingleObject(FHelperProcess, 2000) <> WAIT_OBJECT_0 then
      TerminateProcess(FHelperProcess, 0);
    CloseHandle(FHelperProcess);
    FHelperProcess := 0;
  end;

  FState := hsStopped;
end;

function THelperManager.IsRunning: Boolean;
begin
  Result := (FState = hsRunning) and FPipeClient.IsConnected;
end;

end.