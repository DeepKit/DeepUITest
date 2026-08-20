unit DeepRKey.CommandLine;

interface

uses
  System.SysUtils;

type
  TCommandLine = class
  public
    class procedure Execute;
    class function ParseArgs: TArray<string>;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.IOUtils,
  DeepRKey.Types;

{ TCommandLine }

class function TCommandLine.ParseArgs: TArray<string>;
begin
  SetLength(Result, ParamCount);
  for var i := 1 to ParamCount do
    Result[i - 1] := ParamStr(i);
end;

// === IPC helpers: query running instance ===

function FindIPCWindow: HWND;
begin
  Result := FindWindow('DeepRKey_IPC_Wnd_v1', nil);
end;

/// <summary>
/// Query session GUID from running instance via WM_COPYDATA.
/// BUG-049 fix: Server writes GUID to temp file (WM_COPYDATA is one-way).
/// Returns empty string if not running or query fails.
/// </summary>
function QuerySessionGUID: string;
var
  ipcHwnd: HWND;
  query: TRKeyGUIDQuery;
  cds: TCopyDataStruct;
  sendResult: ULONG_PTR;
  pid: DWORD;
  guidFile: string;
begin
  Result := '';
  ipcHwnd := FindIPCWindow;
  if ipcHwnd = 0 then Exit;

  pid := GetCurrentProcessId;

  // T-447: 构建带 PID 验证的查询结构
  FillChar(query, SizeOf(query), 0);
  query.CallerPID := pid;

  cds.dwData := CD_GUID_QUERY;
  cds.cbData := SizeOf(query);
  cds.lpData := @query;

  // BUG-049 fix: Server writes GUID to temp file instead of writing to cds.lpData
  guidFile := GetEnvironmentVariable('TEMP') +
    '\DeepRKey_guid_' + IntToStr(pid) + '.txt';

  // Delete any stale file
  if FileExists(guidFile) then
    TFile.Delete(guidFile);

  sendResult := 0;
  if SendMessageTimeout(ipcHwnd, WM_COPYDATA, WPARAM(@query), LPARAM(@cds),
    SMTO_ABORTIFHUNG, 2000, @sendResult) = 0 then Exit;
  if sendResult = 0 then Exit;

  // Read GUID from temp file
  if FileExists(guidFile) then
  begin
    try
      Result := TFile.ReadAllText(guidFile);
      TFile.Delete(guidFile);
    except
    end;
  end;
end;

/// <summary>
/// Query diagnostic data from the running instance.
/// The main process writes the result to a temp file named
/// DeepRKey_diag_<PID>.txt which we read back.
/// </summary>
function GetDiagLine(cmd: WPARAM): string;
var
  ipcHwnd: HWND;
  filePath: string;
  pid: DWORD;
  Lines: TArray<string>;
  authGUID: string;
  ipcCmd: TRKeyIPCCommand;
  cds: TCopyDataStruct;
begin
  Result := 'N/A';
  pid := GetCurrentProcessId;
  ipcHwnd := FindIPCWindow;
  if ipcHwnd = 0 then Exit;

  // T-447: 查询 session GUID 用于认证
  authGUID := QuerySessionGUID;
  if authGUID = '' then Exit;

  filePath := GetEnvironmentVariable('TEMP') +
    '\DeepRKey_diag_' + IntToStr(pid) + '.txt';

  // T-447: 构建带 PID 验证的认证命令结构
  FillChar(ipcCmd, SizeOf(ipcCmd), 0);
  ipcCmd.Command := cmd;
  ipcCmd.Param := pid;
  ipcCmd.CallerPID := pid;
  StrPCopy(ipcCmd.AuthGUID, PChar(authGUID));

  cds.dwData := CD_IPC_CMD;
  cds.cbData := SizeOf(ipcCmd);
  cds.lpData := @ipcCmd;

  // BUG-049 fix: wParam = pointer to command struct (CLI has no HWND).
  // Server detects non-HWND wParam and uses CallerPID from struct instead.
  var sendResult: ULONG_PTR := 0;
  SendMessageTimeout(ipcHwnd, WM_COPYDATA, WPARAM(@ipcCmd), LPARAM(@cds),
    SMTO_ABORTIFHUNG, 3000, @sendResult);

  // Read the file written by the main process
  if FileExists(filePath) then
  begin
    try
      Lines := TFile.ReadAllLines(filePath);
      if Length(Lines) > 0 then
        Result := Lines[0];
    except
    end;
    try
      TFile.Delete(filePath);
    except
    end;
  end;
end;

procedure SendIPCCommand(cmd: WPARAM);
var
  ipcHwnd: HWND;
  authGUID: string;
  ipcCmd: TRKeyIPCCommand;
  cds: TCopyDataStruct;
  pid: DWORD;
begin
  ipcHwnd := FindIPCWindow;
  if ipcHwnd = 0 then
  begin
    WriteLn('DeepRKey is not running.');
    Halt(1);
  end;

  // T-447: 查询 session GUID 用于认证（带 PID 验证）
  authGUID := QuerySessionGUID;
  if authGUID = '' then
  begin
    WriteLn('Failed to query session GUID.');
    Halt(1);
  end;

  pid := GetCurrentProcessId;

  // T-447: 构建带 PID 验证的认证命令结构
  FillChar(ipcCmd, SizeOf(ipcCmd), 0);
  ipcCmd.Command := cmd;
  ipcCmd.Param := 0;
  ipcCmd.CallerPID := pid;
  StrPCopy(ipcCmd.AuthGUID, PChar(authGUID));

  cds.dwData := CD_IPC_CMD;
  cds.cbData := SizeOf(ipcCmd);
  cds.lpData := @ipcCmd;

  // BUG-049 fix: wParam = pointer to command struct (CLI has no HWND).
  // Server detects non-HWND wParam and uses CallerPID from struct instead.
  var sendResult: ULONG_PTR := 0;
  if SendMessageTimeout(ipcHwnd, WM_COPYDATA, WPARAM(@ipcCmd), LPARAM(@cds),
    SMTO_ABORTIFHUNG, 3000, @sendResult) = 0 then
  begin
    WriteLn('Warning: IPC command timed out (main process may be hung).');
  end;
end;

{ Command handlers }

class procedure TCommandLine.Execute;
begin
  var args := ParseArgs;
  if Length(args) = 0 then
    Exit;

  // T-450: GUI 子系统下 WriteLn 输出不可靠，需要先分配控制台
  // 只在有实际命令行参数时分配（避免每次启动都弹窗）
  var needsConsole := False;
  for var i := 0 to High(args) do
  begin
    var arg := args[i];
    if arg.StartsWith('--') or arg.StartsWith('-') then
    begin
      needsConsole := True;
      Break;
    end;
  end;

  if needsConsole then
  begin
    // 检查是否已有控制台（调试时可能有）
    if GetStdHandle(STD_OUTPUT_HANDLE) = 0 then
      AllocConsole;
  end;

  var skipNext := False;
  for var i := 0 to High(args) do
  begin
    var arg := args[i];

    // Skip AutoFix value argument (follows an --autofix-* flag without '=')
    if skipNext then
    begin
      skipNext := False;
      Continue;
    end;

    // Skip AutoFix arguments — handled by DeepBase.AutoFix
    if arg.StartsWith('--autofix-', True) then
    begin
      if not arg.Contains('=') then
        skipNext := True;
      Continue;
    end;

    if (arg = '--help') or (arg = '-h') then
    begin
      WriteLn('DeepRKey v0.1.0 — Windows System Menu Enhancement Tool');
      WriteLn;
      WriteLn('Usage: DeepRKey.exe [options]');
      WriteLn;
      WriteLn('Options:');
      WriteLn('  --help, -h           Show this help');
      WriteLn('  --pause              Pause DeepRKey (disable hooks on running instance)');
      WriteLn('  --resume             Resume DeepRKey (re-enable hooks)');
      WriteLn('  --toggle             Toggle pause/resume');
      WriteLn('  --diagnostics, -d    Show current hook status');
      WriteLn('  --health-check       Verify IPC channel + hook status');
      WriteLn;
      WriteLn('AutoFix (DeepBase):');
      WriteLn('  --autofix-mode                Enable AutoFix runtime diagnostics');
      WriteLn('  --autofix-scenario=s1,s2      Run named scenarios after shell shown');
      WriteLn('  --autofix-output=DIR          Output directory (default: autofix-output)');
      WriteLn('  --autofix-run-id=ID           Run identifier (auto-generated if omitted)');
      WriteLn('  --autofix-iteration=N         Iteration number (default: 1)');
      WriteLn;
      Halt(0);
    end;

    if (arg = '--pause') then
    begin
      SendIPCCommand(WM_RKEY_CMD_PAUSE);
      WriteLn('DeepRKey paused.');
      Halt(0);
    end;

    if (arg = '--resume') then
    begin
      SendIPCCommand(WM_RKEY_CMD_RESUME);
      WriteLn('DeepRKey resumed.');
      Halt(0);
    end;

    if (arg = '--toggle') then
    begin
      SendIPCCommand(WM_RKEY_CMD_TOGGLE);
      WriteLn('DeepRKey toggled.');
      Halt(0);
    end;

    if (arg = '--diagnostics') or (arg = '-d') then
    begin
      WriteLn('DeepRKey Diagnostics');
      WriteLn('====================');
      var ipcHwnd := FindIPCWindow;
      if ipcHwnd = 0 then
      begin
        WriteLn('Status: Not running');
        WriteLn;
        Halt(0);
      end;
      WriteLn(Format('Status:         Running (IPC hwnd=$%x)', [NativeUInt(ipcHwnd)]));
      WriteLn(Format('Hook:           %s', [GetDiagLine(100)]));
      WriteLn(Format('Windows:        %s', [GetDiagLine(101)]));
      WriteLn(Format('Threads:        %s', [GetDiagLine(102)]));
      WriteLn(Format('MMF drops:      %s', [GetDiagLine(103)]));
      WriteLn(Format('Session GUID:   %s', [GetDiagLine(104)]));
      WriteLn(Format('Paused:         %s', [GetDiagLine(105)]));
      WriteLn;
      Halt(0);
    end;

    if (arg = '--health-check') then
    begin
      WriteLn('DeepRKey Health Check');
      WriteLn('=====================');
      var ipcHwnd := FindIPCWindow;
      if ipcHwnd = 0 then
      begin
        WriteLn('IPC Window: NOT FOUND (DeepRKey is not running)');
        WriteLn;
        Halt(1);
      end;
      WriteLn('IPC Window: FOUND');
      WriteLn(Format('Hook:         %s', [GetDiagLine(100)]));
      WriteLn(Format('MMF drops:    %s', [GetDiagLine(103)]));
      WriteLn(Format('Paused:       %s', [GetDiagLine(105)]));
      WriteLn;
      Halt(0);
    end;

    WriteLn(Format('Unknown option: %s (try --help)', [arg]));
    Halt(1);
  end;
end;

end.
