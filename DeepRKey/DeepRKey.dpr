program DeepRKey;

{$IFDEF USE_STUB}
  {$DEFINE STUB_MODE}
{$ENDIF}

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Vcl.Forms, Vcl.Dialogs,
  DeepBase.AutoFix,
  DeepBase.AutoFix.VclHook,
  DeepRKey.Bootstrap,
  DeepRKey.MainForm,
  DeepRKey.AboutForm,
  DeepRKey.SettingsForm,
  DeepRKey.CommandLine,
  DeepRKey.Types,
  DeepRKey.Interfaces,
  DeepRKey.MenuModel,
  DeepRKey.StubAdapter,
  DeepRKey.IPC.MMF,
  DeepRKey.IPC.Pipe,
  DeepRKey.IPCRouter,
  DeepRKey.HookEligibilityPolicy,
  DeepRKey.WindowTracker,
  DeepRKey.SystemMenu,
  DeepRKey.WindowOps,
  DeepRKey.Coordinator,
  DeepRKey.FirstRunForm,
  DeepRKey.TitlebarButton,
  DeepRKey.LayoutManager,
  DeepRKey.TransparencyForm;

{$R *.res}

var
  _InstanceMutex: THandle;

begin
  // === Single instance check ===
  // CreateMutex with a well-known name; if it already exists, another instance is running.
  // The mutex is created BEFORE TCommandLine.Execute so that --pause/--resume can find
  // the running instance via FindWindowEx(HWND_MESSAGE) even from a second process.
  _InstanceMutex := CreateMutex(nil, True, 'Local\DeepRKey_SingleInstance_v1');
  if ((_InstanceMutex <> 0) and (GetLastError = ERROR_ALREADY_EXISTS)) or
     (_InstanceMutex = 0) then
  begin
    // Another instance is running — try to send CLI command (--pause/--resume/etc.)
    // If no command was handled, silently exit. No MessageBox (can block in headless/RDP).
    TCommandLine.Execute;
    if _InstanceMutex <> 0 then
      CloseHandle(_InstanceMutex);
    Halt(0);
  end;

  // L2 ExceptProc + scenario runner — no-op without --autofix-mode
  AutoFix.Install;
  // L1 Application.OnException hook — self-skips when AutoFix inactive
  TAutoFixVclHook.Install;

  // Diagnostic scenarios for AutoFix loop
  AutoFix.RegisterScenario('smoke',
    procedure
    begin
      // Smoke: app started, facade reachable — clean pass
    end);

  AutoFix.RegisterScenario('probe',
    procedure
    begin
      var LStatus := if AutoFix.Active then 'on' else 'off';
      OutputDebugString(PChar('DeepRKey AutoFix probe: ' + LStatus));
    end);

  TCommandLine.Execute;

  var bootstrapStart := GetTickCount64;
  try
    TBootstrap.Initialize;
    var bootstrapMs := GetTickCount64 - bootstrapStart;
    // Note: Logger not available yet, use OutputDebugString
    OutputDebugString(PChar(Format('Bootstrap initialized in %dms', [bootstrapMs])));
  except
    on E: Exception do
    begin
      var errDetail := Format('[%s] %s at %s', [E.ClassName, E.Message, E.StackTrace]);
      var errFile := GetEnvironmentVariable('TEMP') + '\DeepRKey_startup_error.txt';
      try
        TFile.WriteAllText(errFile, Format('Time: %s'#13#10'Class: %s'#13#10'Message: %s'#13#10'Stack: %s',
          [DateTimeToStr(Now), E.ClassName, E.Message, E.StackTrace]));
      except end;
      OutputDebugString(PChar('DeepRKey Startup Error: ' + errDetail));
      var msg := Format('DeepRKey failed to start:'#13#10#13#10'%s'#13#10#13#10'%s', [E.Message, E.StackTrace]);
      MessageBox(0, PChar(msg), 'DeepRKey - Startup Error',
        MB_ICONERROR or MB_OK or MB_SYSTEMMODAL);
      Exit;
    end;
  end;

  var appInitStart := GetTickCount64;
  Application.Initialize;
  var appInitMs := GetTickCount64 - appInitStart;
  OutputDebugString(PChar(Format('Application.Initialize took %dms', [appInitMs])));

  Application.MainFormOnTaskbar := False;
  // T-452: 根据设置决定是否显示主窗体（默认隐藏，即最小化到托盘）
  Application.ShowMainForm := not TBootstrap.Config.ReadBool('General.StartMinimized', True);

  var createFormStart := GetTickCount64;
  Application.CreateForm(TfrmMain, frmMain);
  var createFormMs := GetTickCount64 - createFormStart;
  OutputDebugString(PChar(Format('CreateForm took %dms', [createFormMs])));

  Application.Run;
  TBootstrap.Finalize;
end.
