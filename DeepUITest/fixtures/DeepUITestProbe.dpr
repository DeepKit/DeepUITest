{ ============================================================================
  DeepUITestProbe

  Headless VCL test-target fixture for the DeepUITest Runner.

  When launched with expected parameters the probe creates a minimal window,
  writes signal.json under the caller-specified path, stays alive for N
  seconds, then exits.

  When failure-simulation flags are passed it skips the signal, writes a
  wrong run-id, or exits with a configurable non-zero exit code so the
  Runner can be tested against predictable failures.

  Commands:
    DeepUITestProbe.exe
      --case-id=<id>
      --run-id=<id>
      --signal-file=<path>
      --stay-seconds=<N>      (default 30)
    Optional failure injection:
      --no-signal
      --wrong-run-id
      --wrong-case-id
      --delay-ms=<N>
      --exit-code=<N>

  See: DeepUITest.007  Runner与Probe设计.md
  ============================================================================ }

program DeepUITestProbe;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  Winapi.Windows,
  Winapi.Messages;

type
  TProbeArgs = record
    CaseId: string;
    RunId: string;
    SignalFile: string;
    StaySeconds: Integer;
    DelayMs: Integer;
    NoSignal: Boolean;
    WrongRunId: Boolean;
    WrongCaseId: Boolean;
    ExitCodeOverride: Integer;
  end;

function ParseArgs: TProbeArgs;
var
  I: Integer;
  LParam: string;
begin
  Result := default(TProbeArgs);
  Result.StaySeconds := 30;
  Result.ExitCodeOverride := -1;

  for I := 1 to ParamCount do
  begin
    LParam := ParamStr(I);
    if LParam.StartsWith('--case-id=') then
      Result.CaseId := LParam.Substring(Length('--case-id='))
    else if LParam.StartsWith('--run-id=') then
      Result.RunId := LParam.Substring(Length('--run-id='))
    else if LParam.StartsWith('--signal-file=') then
      Result.SignalFile := LParam.Substring(Length('--signal-file='))
    else if LParam.StartsWith('--stay-seconds=') then
      Result.StaySeconds := StrToIntDef(LParam.Substring(Length('--stay-seconds=')), 30)
    else if LParam.StartsWith('--delay-ms=') then
      Result.DelayMs := StrToIntDef(LParam.Substring(Length('--delay-ms=')), 0)
    else if LParam = '--no-signal' then
      Result.NoSignal := True
    else if LParam = '--wrong-run-id' then
      Result.WrongRunId := True
    else if LParam = '--wrong-case-id' then
      Result.WrongCaseId := True
    else if LParam.StartsWith('--exit-code=') then
      Result.ExitCodeOverride := StrToIntDef(LParam.Substring(Length('--exit-code=')), -1);
  end;
end;

function BuildSignal(const AArgs: TProbeArgs): string;
begin
  Result := '{' +
    '"app":"DeepUITestProbe",' +
    '"caseId":"' + AArgs.CaseId + '",' +
    '"runId":"' + AArgs.RunId + '",' +
    '"processId":' + IntToStr(GetCurrentProcessId) + ',' +
    '"startedAt":"' + FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now) + '",' +
    '"status":"started"' +
    '}';
end;

procedure WriteSignal(const AArgs: TProbeArgs);
var
  LJson: string;
begin
  if AArgs.NoSignal then Exit;

  LJson := BuildSignal(AArgs);

  var LFile := ExpandFileName(AArgs.SignalFile);
  var LDir := ExtractFilePath(LFile);
  ForceDirectories(LDir);
  TFile.WriteAllText(LFile, LJson, TEncoding.UTF8);
end;

function GetWindowTitle(const AArgs: TProbeArgs): string;
begin
  Result := 'DeepUITest Probe ' + AArgs.RunId;
end;

var
  LArgs: TProbeArgs;
  LMsg: TMsg;
  LWindowClass: TWndClass;
  LHwnd: HWND;
  LDeadline: Int64;
begin
  LArgs := ParseArgs;

  if LArgs.DelayMs > 0 then
    Sleep(LArgs.DelayMs);

  // Create directory and write signal.json
  if LArgs.SignalFile <> '' then
    WriteSignal(LArgs);

  // Register a window class so Runner can verify title and process
  FillChar(LWindowClass, SizeOf(LWindowClass), 0);
  LWindowClass.lpfnWndProc := @DefWindowProc;
  LWindowClass.hInstance := HInstance;
  LWindowClass.lpszClassName := 'DeepUITestProbe';

  Winapi.Windows.RegisterClass(LWindowClass);

  LHwnd := CreateWindowEx(
    0,
    'DeepUITestProbe',
    PChar(GetWindowTitle(LArgs)),
    WS_OVERLAPPEDWINDOW,
    100, 100, 400, 200,
    0, 0, HInstance, nil);

  if LHwnd = 0 then
  begin
    WriteLn(ErrOutput, 'ERROR: failed to create probe window');
    Halt(1);
  end;

  ShowWindow(LHwnd, SW_SHOW);
  UpdateWindow(LHwnd);

  // Stay alive until deadline or window is closed
  LDeadline := GetTickCount64 + Cardinal(LArgs.StaySeconds * 1000);

  while GetTickCount64 < LDeadline do
  begin
    while PeekMessage(LMsg, 0, 0, 0, PM_REMOVE) do
    begin
      if LMsg.message = WM_QUIT then
        Break;
      TranslateMessage(LMsg);
      DispatchMessage(LMsg);
    end;
    Sleep(50);

    if not IsWindow(LHwnd) then
      Break;
  end;

  if IsWindow(LHwnd) then
    DestroyWindow(LHwnd);

  if LArgs.ExitCodeOverride >= 0 then
    Halt(LArgs.ExitCodeOverride);
end.