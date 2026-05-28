{ ============================================================================
  DeepUITest.Runner.Actions

  MVP action implementations (10 actions). Pure Win32 — no VCL dependency.

  See: DeepUITest.007 Runner与Probe设计.md
  ============================================================================ }

unit DeepUITest.Runner.Actions;

interface

uses
  System.SysUtils,
  System.Classes,
  DeepUITest.Models;

type
  TUITestAction = class
  public
    class function DoStartProcess(const ATarget, AArgs: string;
      ATimeoutMs: Integer; const AWorkingDir: string): TRunnerStepResult;

    class function DoEnsureProcess(const AProcessName: string;
      ATimeoutMs: Integer; const AStartCmd, AStartArgs: string): TRunnerStepResult;

    class function DoWaitWindow(const AWindowTitle: string;
      ATimeoutMs: Integer): TRunnerStepResult;

    class function DoSendHotkey(const AKeys: string): TRunnerStepResult;

    class function DoSendKey(const AKey: Char): TRunnerStepResult;

    class function DoMouseMove(AX, AY: Integer): TRunnerStepResult;

    class function DoMouseClick(AX, AY: Integer): TRunnerStepResult;

    class function DoMouseDrag(AFromX, AFromY, AToX, AToY: Integer;
      ASteps: Integer = 20): TRunnerStepResult;

    class function DoMouseDblClick(AX, AY: Integer): TRunnerStepResult;

    class function DoVerifyProcess(const AProcessName: string): TRunnerStepResult;

    class function DoVerifyWindow(const AWindowTitle: string): TRunnerStepResult;

    class function DoVerifyFile(const AFilePath, AExpectedContent: string): TRunnerStepResult;

    class function DoWriteLog(const AMessage, ALogPath: string): TRunnerStepResult;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32,
  System.IOUtils;

function NowStr: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
end;

function FindProcessId(const AProcessName: string): DWORD;
var
  LSnap: THandle;
  LPe: TProcessEntry32;
begin
  Result := 0;
  LSnap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if LSnap = INVALID_HANDLE_VALUE then Exit;
  try
    FillChar(LPe, SizeOf(LPe), 0);
    LPe.dwSize := SizeOf(TProcessEntry32);
    if Process32First(LSnap, LPe) then
    repeat
      if SameText(string(LPe.szExeFile), ExtractFileName(AProcessName)) then
        Exit(LPe.th32ProcessID);
    until not Process32Next(LSnap, LPe);
  finally
    CloseHandle(LSnap);
  end;
end;

function WaitForProcess(const AProcessName: string;
  ATimeoutMs: Integer): Boolean;
var
  LDeadline: Cardinal;
begin
  Result := False;
  LDeadline := GetTickCount + Cardinal(ATimeoutMs);
  while GetTickCount < LDeadline do
  begin
    if FindProcessId(AProcessName) <> 0 then
      Exit(True);
    Sleep(200);
  end;
end;

function FindWindowByTitlePartial(const ATitleSub: string): HWND;
var
  LHwnd: HWND;
  LBuf: array[0..1023] of Char;
  LTitle: string;
begin
  Result := FindWindow(nil, PChar(ATitleSub));
  if Result <> 0 then Exit;

  LHwnd := GetWindow(GetDesktopWindow, GW_CHILD);
  while LHwnd <> 0 do
  begin
    if GetWindowText(LHwnd, @LBuf, SizeOf(LBuf)) > 0 then
    begin
      LTitle := string(LBuf);
      if Pos(ATitleSub, LTitle) > 0 then
        Exit(LHwnd);
    end;
    LHwnd := GetWindow(LHwnd, GW_HWNDNEXT);
  end;
  Result := 0;
end;

{ TUITestAction }

class function TUITestAction.DoStartProcess(const ATarget, AArgs: string;
  ATimeoutMs: Integer; const AWorkingDir: string): TRunnerStepResult;
var
  LSI: TStartupInfo;
  LPI: TProcessInformation;
  LCmd: string;
  LDir: PChar;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  FillChar(LSI, SizeOf(LSI), 0);
  LSI.cb := SizeOf(LSI);
  FillChar(LPI, SizeOf(LPI), 0);

  LCmd := '"' + ATarget + '"';
  if AArgs <> '' then
    LCmd := LCmd + ' ' + AArgs;

  if AWorkingDir <> '' then
    LDir := PChar(AWorkingDir)
  else
    LDir := nil;

  if CreateProcess(nil, PChar(LCmd), nil, nil, False,
    CREATE_NEW_CONSOLE, nil, LDir, LSI, LPI) then
  begin
    CloseHandle(LPI.hThread);
    CloseHandle(LPI.hProcess);

    if WaitForProcess(ATarget, ATimeoutMs) then
    begin
      Result.Status := 'pass';
      Result.ActualValue := 'PID=' + IntToStr(FindProcessId(ATarget));
    end
    else
    begin
      Result.Status := 'fail';
      Result.ErrorCode := 'TIMEOUT';
      Result.ErrorMessage := 'Process started but not found within timeout: ' + ATarget;
    end;
  end
  else
  begin
    Result.Status := 'fail';
    Result.ErrorCode := 'START_FAILED';
    Result.ErrorMessage := 'CreateProcess failed: ' + SysErrorMessage(GetLastError);
  end;

  Result.FinishedAt := NowStr;
end;

class function TUITestAction.DoEnsureProcess(const AProcessName: string;
  ATimeoutMs: Integer; const AStartCmd, AStartArgs: string): TRunnerStepResult;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  if FindProcessId(AProcessName) <> 0 then
  begin
    Result.Status := 'pass';
    Result.ActualValue := AProcessName + ' already running';
    Result.FinishedAt := NowStr;
    Exit;
  end;

  if AStartCmd = '' then
  begin
    Result.Status := 'fail';
    Result.ErrorCode := 'PROCESS_NOT_FOUND';
    Result.ErrorMessage := 'Process not found and no start command: ' + AProcessName;
    Result.FinishedAt := NowStr;
    Exit;
  end;

  Result.Free;
  Result := DoStartProcess(AStartCmd, AStartArgs, ATimeoutMs, '');
end;

class function TUITestAction.DoWaitWindow(const AWindowTitle: string;
  ATimeoutMs: Integer): TRunnerStepResult;
var
  LDeadline: Cardinal;
  LHwnd: HWND;
  LBuf: array[0..1023] of Char;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  LDeadline := GetTickCount + Cardinal(ATimeoutMs);

  repeat
    LHwnd := FindWindowByTitlePartial(AWindowTitle);
    if (LHwnd <> 0) and IsWindowVisible(LHwnd) then
    begin
      GetWindowText(LHwnd, @LBuf, SizeOf(LBuf));
      Result.Status := 'pass';
      Result.ActualValue := 'HWND=' + IntToHex(NativeUInt(LHwnd), 8) +
        ', Title=' + string(LBuf);
      Result.FinishedAt := NowStr;
      Exit;
    end;
    Sleep(200);
  until GetTickCount >= LDeadline;

  Result.Status := 'fail';
  Result.ErrorCode := 'WINDOW_NOT_FOUND';
  Result.ErrorMessage := Format('Window "%s" not found within %d ms',
    [AWindowTitle, ATimeoutMs]);
  Result.FinishedAt := NowStr;
end;

class function TUITestAction.DoSendHotkey(const AKeys: string): TRunnerStepResult;
var
  LInputs: array[0..1] of TInput;
  LVk: Word;
  LSent: UINT;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  if SameText(AKeys, 'F1') then LVk := VK_F1
  else if SameText(AKeys, 'F2') then LVk := VK_F2
  else if SameText(AKeys, 'F3') then LVk := VK_F3
  else if SameText(AKeys, 'F4') then LVk := VK_F4
  else if SameText(AKeys, 'F5') then LVk := VK_F5
  else if SameText(AKeys, 'F6') then LVk := VK_F6
  else if SameText(AKeys, 'F7') then LVk := VK_F7
  else if SameText(AKeys, 'F8') then LVk := VK_F8
  else if SameText(AKeys, 'F9') then LVk := VK_F9
  else if SameText(AKeys, 'F10') then LVk := VK_F10
  else if SameText(AKeys, 'F11') then LVk := VK_F11
  else if SameText(AKeys, 'F12') then LVk := VK_F12
  else if (Length(AKeys) = 1) and (AKeys[1] in ['0'..'9']) then
    LVk := Ord(AKeys[1])
  else if (Length(AKeys) = 1) and (UpCase(AKeys[1]) in ['A'..'Z']) then
    LVk := Ord(UpCase(AKeys[1]))
  else
  begin
    Result.Status := 'fail';
    Result.ErrorCode := 'KEY_FAILED';
    Result.ErrorMessage := 'Unsupported hotkey: ' + AKeys;
    Result.FinishedAt := NowStr;
    Exit;
  end;

  FillChar(LInputs[0], SizeOf(TInput), 0);
  LInputs[0].Itype := INPUT_KEYBOARD;
  LInputs[0].ki.wVk := LVk;

  FillChar(LInputs[1], SizeOf(TInput), 0);
  LInputs[1].Itype := INPUT_KEYBOARD;
  LInputs[1].ki.wVk := LVk;
  LInputs[1].ki.dwFlags := KEYEVENTF_KEYUP;

  Sleep(100);
  LSent := SendInput(2, LInputs[0], SizeOf(TInput));
  if LSent = 0 then
  begin
    Result.Status := 'fail';
    Result.ErrorCode := 'KEY_FAILED';
    Result.ErrorMessage := 'SendInput failed for key: ' + AKeys;
  end
  else
  begin
    Result.Status := 'pass';
    Result.ActualValue := 'Sent ' + AKeys;
  end;

  Result.FinishedAt := NowStr;
end;

class function TUITestAction.DoSendKey(const AKey: Char): TRunnerStepResult;
begin
  Result := DoSendHotkey(AKey);
end;

{ ---- Helpers for mouse absolute coordinates ---- }

function ScreenToAbsolute(AX, AY: Integer): TSmallPoint;
var
  LX, LY: Integer;
begin
  LX := MulDiv(AX, 65535, GetSystemMetrics(SM_CXSCREEN) - 1);
  LY := MulDiv(AY, 65535, GetSystemMetrics(SM_CYSCREEN) - 1);
  Result.x := SmallInt(LX);
  Result.y := SmallInt(LY);
end;

procedure SendMouseAbs(AX, AY: Integer; AFlags: DWORD);
var
  LInput: TInput;
  LAbs: TSmallPoint;
begin
  FillChar(LInput, SizeOf(LInput), 0);
  LInput.Itype := INPUT_MOUSE;
  LAbs := ScreenToAbsolute(AX, AY);
  LInput.mi.dx := LAbs.x;
  LInput.mi.dy := LAbs.y;
  LInput.mi.dwFlags := AFlags or MOUSEEVENTF_ABSOLUTE;
  SendInput(1, LInput, SizeOf(TInput));
end;

{ ---- Mouse actions ---- }

class function TUITestAction.DoMouseMove(AX, AY: Integer): TRunnerStepResult;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  Sleep(50);
  SendMouseAbs(AX, AY, MOUSEEVENTF_MOVE);

  Result.Status := 'pass';
  Result.ActualValue := Format('Moved to (%d, %d)', [AX, AY]);
  Result.FinishedAt := NowStr;
end;

class function TUITestAction.DoMouseClick(AX, AY: Integer): TRunnerStepResult;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  Sleep(50);
  SendMouseAbs(AX, AY, MOUSEEVENTF_MOVE);
  Sleep(30);
  SendMouseAbs(AX, AY, MOUSEEVENTF_LEFTDOWN);
  Sleep(30);
  SendMouseAbs(AX, AY, MOUSEEVENTF_LEFTUP);

  Result.Status := 'pass';
  Result.ActualValue := Format('Clicked at (%d, %d)', [AX, AY]);
  Result.FinishedAt := NowStr;
end;

class function TUITestAction.DoMouseDrag(AFromX, AFromY, AToX, AToY: Integer;
  ASteps: Integer): TRunnerStepResult;
var
  I: Integer;
  LX, LY: Integer;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  if ASteps < 1 then ASteps := 1;

  Sleep(50);
  SendMouseAbs(AFromX, AFromY, MOUSEEVENTF_MOVE);
  Sleep(30);
  SendMouseAbs(AFromX, AFromY, MOUSEEVENTF_LEFTDOWN);
  Sleep(50);

  for I := 1 to ASteps do
  begin
    LX := AFromX + MulDiv(AToX - AFromX, I, ASteps);
    LY := AFromY + MulDiv(AToY - AFromY, I, ASteps);
    SendMouseAbs(LX, LY, MOUSEEVENTF_MOVE);
    Sleep(10);
  end;

  Sleep(30);
  SendMouseAbs(AToX, AToY, MOUSEEVENTF_LEFTUP);

  Result.Status := 'pass';
  Result.ActualValue := Format('Dragged from (%d,%d) to (%d,%d) in %d steps',
    [AFromX, AFromY, AToX, AToY, ASteps]);
  Result.FinishedAt := NowStr;
end;

class function TUITestAction.DoMouseDblClick(AX, AY: Integer): TRunnerStepResult;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  Sleep(50);
  SendMouseAbs(AX, AY, MOUSEEVENTF_MOVE);
  Sleep(30);
  // first click
  SendMouseAbs(AX, AY, MOUSEEVENTF_LEFTDOWN);
  Sleep(20);
  SendMouseAbs(AX, AY, MOUSEEVENTF_LEFTUP);
  Sleep(50);
  // second click
  SendMouseAbs(AX, AY, MOUSEEVENTF_LEFTDOWN);
  Sleep(20);
  SendMouseAbs(AX, AY, MOUSEEVENTF_LEFTUP);

  Result.Status := 'pass';
  Result.ActualValue := Format('Double-clicked at (%d, %d)', [AX, AY]);
  Result.FinishedAt := NowStr;
end;

class function TUITestAction.DoVerifyProcess(const AProcessName: string): TRunnerStepResult;
var
  LPid: DWORD;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  LPid := FindProcessId(AProcessName);
  if LPid <> 0 then
  begin
    Result.Status := 'pass';
    Result.ActualValue := AProcessName + ' running (PID=' + IntToStr(LPid) + ')';
  end
  else
  begin
    Result.Status := 'fail';
    Result.ErrorCode := 'PROCESS_NOT_FOUND';
    Result.ErrorMessage := 'Process not found: ' + AProcessName;
  end;

  Result.FinishedAt := NowStr;
end;

class function TUITestAction.DoVerifyWindow(const AWindowTitle: string): TRunnerStepResult;
var
  LHwnd: HWND;
  LRect: TRect;
  LW, LH: Integer;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  LHwnd := FindWindowByTitlePartial(AWindowTitle);
  if (LHwnd <> 0) and IsWindowVisible(LHwnd) then
  begin
    GetWindowRect(LHwnd, LRect);
    LW := LRect.Right - LRect.Left;
    LH := LRect.Bottom - LRect.Top;

    if (LW > 50) and (LH > 50) then
    begin
      Result.Status := 'pass';
      Result.ActualValue := Format('HWND=%s, Size=%dx%d, Visible',
        [IntToHex(NativeUInt(LHwnd), 8), LW, LH]);
    end
    else
    begin
      Result.Status := 'fail';
      Result.ErrorCode := 'ASSERT_FAIL';
      Result.ErrorMessage := Format('Window found but too small: %dx%d', [LW, LH]);
    end;
  end
  else
  begin
    Result.Status := 'fail';
    Result.ErrorCode := 'WINDOW_NOT_FOUND';
    Result.ErrorMessage := 'Window not found or not visible: ' + AWindowTitle;
  end;

  Result.FinishedAt := NowStr;
end;

class function TUITestAction.DoVerifyFile(const AFilePath, AExpectedContent: string): TRunnerStepResult;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  if not TFile.Exists(AFilePath) then
  begin
    Result.Status := 'fail';
    Result.ErrorCode := 'FILE_NOT_FOUND';
    Result.ErrorMessage := 'File not found: ' + AFilePath;
    Result.FinishedAt := NowStr;
    Exit;
  end;

  if AExpectedContent <> '' then
  begin
    Result.ActualValue := TFile.ReadAllText(AFilePath);
    if Pos(AExpectedContent, Result.ActualValue) > 0 then
      Result.Status := 'pass'
    else
    begin
      Result.Status := 'fail';
      Result.ErrorCode := 'ASSERT_FAIL';
      Result.ErrorMessage := 'Expected content not found in: ' + AFilePath;
    end;
  end
  else
    Result.Status := 'pass';

  Result.FinishedAt := NowStr;
end;

class function TUITestAction.DoWriteLog(const AMessage, ALogPath: string): TRunnerStepResult;
var
  LLine: string;
begin
  Result := TRunnerStepResult.Create;
  Result.StartedAt := NowStr;

  try
    LLine := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now) + ' ' + AMessage + sLineBreak;
    TFile.AppendAllText(ALogPath, LLine, TEncoding.UTF8);
    Result.Status := 'pass';
    Result.ActualValue := AMessage;
  except
    on E: Exception do
    begin
      Result.Status := 'fail';
      Result.ErrorCode := 'ACCESS_DENIED';
      Result.ErrorMessage := 'WriteLog failed: ' + E.Message;
    end;
  end;

  Result.FinishedAt := NowStr;
end;

end.