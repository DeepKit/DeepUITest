unit DeepRKey.FirstRunForm;

interface

/// <summary>Show first-run welcome dialog. Returns True if shown.</summary>
function CheckAndShowFirstRun: Boolean;

/// <summary>Detect if Microsoft PowerToys Run is running.</summary>
function IsPowerToysRunning: Boolean;

/// <summary>Detect if the system has touch/pen input (tablet mode).</summary>
function IsTouchDevice: Boolean;

implementation

uses
  Winapi.Windows, Winapi.Messages, Winapi.TlHelp32,
  System.SysUtils, System.Win.Registry, System.UITypes,
  Vcl.Dialogs,
  DeepRKey.Bootstrap;

const
  REG_FIRST_RUN_VALUE = 'FirstRunDone';
  SM_DIGITIZERS = 94;
  NID_READY = $80;

function IsPowerToysRunning: Boolean;
var
  hSnap: THandle;
  pe: TProcessEntry32;
begin
  Result := False;
  hSnap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if hSnap = INVALID_HANDLE_VALUE then Exit;
  try
    pe.dwSize := SizeOf(pe);
    if Process32First(hSnap, pe) then
    repeat
      // PowerToys Run process name
      if SameText(pe.szExeFile, 'PowerToys.PowerLauncher.exe') or
         SameText(pe.szExeFile, 'PowerToys.exe') then
      begin
        Result := True;
        Exit;
      end;
    until not Process32Next(hSnap, pe);
  finally
    CloseHandle(hSnap);
  end;
end;

function IsTouchDevice: Boolean;
begin
  // SM_TABLETPC: non-zero if the system has a pen digitizer
  // SM_DIGITIZERS: non-zero if the system has a touch or pen digitizer
  Result := (GetSystemMetrics(SM_TABLETPC) <> 0) or
            (GetSystemMetrics(SM_DIGITIZERS) <> 0);
end;

function CheckAndShowFirstRun: Boolean;
var
  reg: TRegistry;
  firstRun: Boolean;
  msg: string;
begin
  Result := False;
  reg := TRegistry.Create(KEY_READ);
  try
    reg.RootKey := HKEY_CURRENT_USER;
    firstRun := True;
    if reg.OpenKeyReadOnly('SOFTWARE\DeepRKey') then
    begin
      firstRun := not reg.ValueExists(REG_FIRST_RUN_VALUE);
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;

  if not firstRun then Exit;

  // Build the welcome message
  msg := 'Welcome to DeepRKey!' + sLineBreak + sLineBreak +
    'DeepRKey enhances the system menu of every window.' + sLineBreak + sLineBreak +
    'How to access the enhanced menu:' + sLineBreak +
    '  - Right-click on a window title bar' + sLineBreak +
    '  - Ctrl+Alt+Space (global hotkey)' + sLineBreak + sLineBreak;

  if IsPowerToysRunning then
  begin
    msg := msg +
      'WARNING: Microsoft PowerToys appears to be running.' + sLineBreak +
      'PowerToys Run uses Alt+Space by default, but DeepRKey' + sLineBreak +
      'uses Ctrl+Alt+Space, so there is no conflict.' + sLineBreak + sLineBreak;
  end;

  if IsTouchDevice then
  begin
    msg := msg +
      'Touch device detected: you can use the tray icon' + sLineBreak +
      'as an alternative entry point.' + sLineBreak + sLineBreak;
  end;

  msg := msg + 'You can change all settings from the tray icon menu.';

  MessageDlg(msg, mtInformation, [mbOK], 0);

  // Mark first run as done
  reg := TRegistry.Create(KEY_WRITE);
  try
    reg.RootKey := HKEY_CURRENT_USER;
    if reg.OpenKey('SOFTWARE\DeepRKey', True) then
    begin
      reg.WriteBool(REG_FIRST_RUN_VALUE, True);
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;

  if Assigned(TBootstrap.Logger) then
    TBootstrap.Logger.Info('First-run wizard completed', 'UI');

  Result := True;
end;

end.
