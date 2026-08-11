{ ============================================================================
  DeepSpec

  AI-native requirement specification tool.
  Based on DeepBase / DeepShell.
  ============================================================================ }

program DeepSpec;

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.Dialogs,
  FireDAC.VCLUI.Wait,
  FireDAC.Comp.UI,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  DeepBase.AutoFix,
  DeepBase.AutoFix.VclHook,
  DeepBase.AIErrorHandler.Bootstrap,
  DeepSpec.MainForm in 'src\app\DeepSpec.MainForm.pas',
  DeepSpec.Commands in 'src\app\DeepSpec.Commands.pas',
  DeepSpec.Services in 'src\app\DeepSpec.Services.pas',
  DeepSpec.Providers in 'src\app\DeepSpec.Providers.pas',
  DeepSpec.Services.Project in 'src\services\DeepSpec.Services.Project.pas',
  DeepSpec.Services.Scan in 'src\services\DeepSpec.Services.Scan.pas',
  DeepSpec.Services.SpecStore in 'src\services\DeepSpec.Services.SpecStore.pas',
  DeepSpec.Services.Render in 'src\services\DeepSpec.Services.Render.pas',
  DeepSpec.Services.TreeBuilder in 'src\services\DeepSpec.Services.TreeBuilder.pas',
  DeepSpec.Services.Prompts in 'src\services\DeepSpec.Services.Prompts.pas',
  DeepSpec.Services.Decisions in 'src\services\DeepSpec.Services.Decisions.pas',
  DeepSpec.Services.LLM in 'src\services\DeepSpec.Services.LLM.pas',
  DeepSpec.Services.LLMConfig in 'src\services\DeepSpec.Services.LLMConfig.pas',
  DeepSpec.Services.Context in 'src\services\DeepSpec.Services.Context.pas',
  DeepSpec.Models in 'src\models\DeepSpec.Models.pas',
  DeepSpec.Hash in 'src\core\DeepSpec.Hash.pas',
  DeepSpec.Yaml.Writer in 'src\core\DeepSpec.Yaml.Writer.pas',
  DeepSpec.Yaml.Parser in 'src\core\DeepSpec.Yaml.Parser.pas',
  DeepSpec.Delphi.DfmParser in 'src\core\DeepSpec.Delphi.DfmParser.pas',
  DeepSpec.Delphi.PasParser in 'src\core\DeepSpec.Delphi.PasParser.pas',
  DeepSpec.Validation in 'src\core\DeepSpec.Validation.pas',
  DeepSpec.Controller in 'src\controllers\DeepSpec.Controller.pas',
  DeepSpec.Providers.Structure in 'src\providers\DeepSpec.Providers.Structure.pas',
  DeepSpec.Providers.MainView in 'src\providers\DeepSpec.Providers.MainView.pas',
  DeepSpec.Providers.Inspector in 'src\providers\DeepSpec.Providers.Inspector.pas';

{$R *.res}

var
  GErrorMsg: string;

begin
  ReportMemoryLeaksOnShutdown := True;
  InstallAIErrorHandler;                     // AI runtime error handler (chains to AutoFix below)
  AutoFix.Install;
  TAutoFixVclHook.Install;             // VCL: hook Application.OnException (no-op unless --autofix-mode)
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'DeepSpec';

  // DeepBase init - best effort, but never silent (BUG-7): the user must
  // see a failure instead of a debugger-only OutputDebugString line.
  if not DeepBase.Manager.DeepBase.InitializeEx(GErrorMsg) then
    ShowMessage('DeepBase initialization failed: ' + GErrorMsg + sLineBreak +
      'Settings persistence and LLM features may be unavailable. ' +
      'The application will continue without them.');

  try
    try
      Application.CreateForm(TDeepSpecMainForm, DeepSpecMainForm);
    except
      on E: Exception do
      begin
        ShowMessage('FATAL: Form creation failed: ' + E.ClassName + ': ' + E.Message);
        Exit;
      end;
    end;
    AutoFix.RegisterScenario('smoke',
      procedure
      begin
        // smoke: verify AutoFix infrastructure is alive
      end);
    Application.Run;
  finally
    DeepBase.Manager.DeepBase.Finalize;
  end;
end.
