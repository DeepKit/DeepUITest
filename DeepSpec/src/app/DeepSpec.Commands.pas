{ ============================================================================
  DeepSpec.Commands

  Registers all DeepSpec commands into the DeepShell command manager.
  Commands delegate to TDeepSpecController via the MainForm reference.
  ============================================================================ }

unit DeepSpec.Commands;

interface

uses
  DeepBase.VCL.DeepShell.Intf,
  DeepBase.VCL.DeepShell.Types,
  Vcl.Forms;

procedure RegisterAllCommands(const ACommands: IShellCommandManager;
  AForm: TForm);

implementation

uses
  System.SysUtils,
  Vcl.FileCtrl,
  Vcl.Dialogs,
  DeepBase.LLM,
  DeepSpec.Services.LLMConfig,
  DeepSpec.MainForm;

procedure RegisterAllCommands(const ACommands: IShellCommandManager;
  AForm: TForm);
var
  LCmd: TShellCommand;
  LForm: TDeepSpecMainForm;
begin
  LForm := AForm as TDeepSpecMainForm;

  LCmd := TShellCommand.Make('deepspec.project.open', 'Open Project');
  LCmd.Category := 'File';
  LCmd.ShortcutText := 'Ctrl+O';
  LCmd.RiskLevel := rlLow;
  LCmd.Handler := procedure
    begin
      var LDir := '';
      if SelectDirectory('Select project folder', '', LDir) then
      begin
        LForm.Controller.OpenAndScan(LDir);
        if LForm.Recent <> nil then
          LForm.Recent.AddRecentProject(LDir, LDir,
            ExtractFileName(ExcludeTrailingPathDelimiter(LDir)), '');
        // RebuildStructureTree is triggered by HandleScanEvent via sekProjectOpened
      end;
    end;
  ACommands.RegisterCommand(LCmd);

  LCmd := TShellCommand.Make('deepspec.scan.run', 'Run Scan');
  LCmd.Category := 'Run';
  LCmd.ShortcutText := 'F5';
  LCmd.RiskLevel := rlLow;
  LCmd.Handler := procedure
    begin
      LForm.Controller.RunScan;
    end;
  ACommands.RegisterCommand(LCmd);

  LCmd := TShellCommand.Make('deepspec.spec.generate', 'Generate B');
  LCmd.Category := 'Run';
  LCmd.RiskLevel := rlMedium;
  LCmd.Handler := procedure
    begin
      LForm.Controller.GenerateB;
    end;
  ACommands.RegisterCommand(LCmd);

  LCmd := TShellCommand.Make('deepspec.html.render', 'Render HTML');
  LCmd.Category := 'View';
  LCmd.RiskLevel := rlLow;
  LCmd.Handler := procedure
    begin
      LForm.Controller.RenderAll;
    end;
  ACommands.RegisterCommand(LCmd);

  LCmd := TShellCommand.Make('deepspec.html.refresh-from-yaml', 'Refresh HTML from YAML');
  LCmd.Category := 'View';
  LCmd.RiskLevel := rlLow;
  LCmd.Handler := procedure
    begin
      LForm.Controller.RefreshFromYaml;
    end;
  ACommands.RegisterCommand(LCmd);

  LCmd := TShellCommand.Make('deepspec.decisions.promote', 'Promote Pending Decisions');
  LCmd.Category := 'Tools';
  LCmd.RiskLevel := rlLow;
  LCmd.Handler := procedure
    begin
      LForm.Controller.PromotePendingDecisions;
    end;
  ACommands.RegisterCommand(LCmd);

  LCmd := TShellCommand.Make('deepspec.prompt.export', 'Export Prompt');
  LCmd.Category := 'Tools';
  LCmd.RiskLevel := rlLow;
  LCmd.Handler := procedure
    begin
      LForm.Controller.ExportPrompt;
    end;
  ACommands.RegisterCommand(LCmd);

  LCmd := TShellCommand.Make('deepspec.data.render', 'Render Data Tree');
  LCmd.Category := 'View';
  LCmd.RiskLevel := rlLow;
  LCmd.Handler := procedure
    begin
      LForm.Controller.RenderAll;
    end;
  ACommands.RegisterCommand(LCmd);

  LCmd := TShellCommand.Make('deepspec.llm.setup', 'Setup LLM (ModelScope)');
  LCmd.Category := 'Tools';
  LCmd.RiskLevel := rlLow;
  LCmd.Handler := procedure
    var
      LApiKey, LModel: string;
      LDeepBaseLLM: TDeepBaseLLM;
    begin
      LApiKey := '';
      if not InputQuery('LLM Setup',
        'Enter ModelScope API Key (will be stored securely):', LApiKey) then
        Exit;
      if LApiKey.Trim = '' then Exit;

      LModel := 'Qwen/Qwen2.5-72B-Instruct';
      if not InputQuery('LLM Setup',
        'Model name (default: Qwen/Qwen2.5-72B-Instruct):', LModel) then
        Exit;
      if LModel.Trim = '' then
        LModel := 'Qwen/Qwen2.5-72B-Instruct';

      LDeepBaseLLM := LForm.LLMInstance as TDeepBaseLLM;
      if LDeepBaseLLM = nil then
      begin
        ShowMessage('DeepBase LLM not initialized. Check root.txt and DB1.');
        Exit;
      end;

      try
        TDeepSpecLLMConfigHelper.SaveModelScopeConfig(
          LDeepBaseLLM, LApiKey.Trim, LModel.Trim);
        ShowMessage('LLM configured successfully. Use Generate B to call it.');
      except
        on E: Exception do
          ShowMessage('Failed to save LLM config: ' + E.Message);
      end;
    end;
  ACommands.RegisterCommand(LCmd);

  // -------------------------------------------------------------------------
  // Debug commands — pilot smoke test for AIErrorHandler integration.
  // Trigger an unhandled exception to verify the AIErrorHandler chain works:
  //   - elAutoFix path  (EConvertError)  : silent log only
  //   - elAIAnalyze path (Exception)     : friendly MessageDlg via AIEH
  // Removed once rollout pilot is validated; safe to keep around since
  // they are only reachable via the command palette.
  // -------------------------------------------------------------------------
  LCmd := TShellCommand.Make('deepspec.debug.inject-convert-error',
    'Debug: Inject EConvertError (elAutoFix path)');
  LCmd.Category := 'Debug';
  LCmd.RiskLevel := rlLow;
  LCmd.Handler := procedure
    begin
      // Goes through AIErrorHandler classifier as elAutoFix
      // (logged silently, no dialog shown).
      raise EConvertError.Create('Pilot smoke: forced EConvertError');
    end;
  ACommands.RegisterCommand(LCmd);

  LCmd := TShellCommand.Make('deepspec.debug.inject-generic-error',
    'Debug: Inject generic Exception (elAIAnalyze path)');
  LCmd.Category := 'Debug';
  LCmd.RiskLevel := rlLow;
  LCmd.Handler := procedure
    begin
      // Goes through AIErrorHandler classifier as elAIAnalyze
      // (LLM-friendly MessageDlg or fallback friendly message).
      raise Exception.Create('Pilot smoke: forced generic exception for AI analysis');
    end;
  ACommands.RegisterCommand(LCmd);
end;

end.
