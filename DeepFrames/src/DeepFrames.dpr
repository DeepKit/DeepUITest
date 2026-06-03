program DeepFrames;

uses
  Vcl.Forms,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  DeepFrames.App.Bootstrap in 'App\DeepFrames.App.Bootstrap.pas',
  DeepFrames.App.Constants in 'App\DeepFrames.App.Constants.pas',
  DeepFrames.App.Services in 'App\DeepFrames.App.Services.pas',
  DeepFrames.Shared.Consts in 'Shared\DeepFrames.Shared.Consts.pas',
  DeepFrames.Domain.Types in 'Domain\DeepFrames.Domain.Types.pas',
  DeepFrames.Domain.Project in 'Domain\DeepFrames.Domain.Project.pas',
  DeepFrames.Persistence.Connection in 'Persistence\DeepFrames.Persistence.Connection.pas',
  DeepFrames.Persistence.Migrations in 'Persistence\DeepFrames.Persistence.Migrations.pas',
  DeepFrames.Persistence.Repository in 'Persistence\DeepFrames.Persistence.Repository.pas',
  DeepFrames.Workflow.Preprocess in 'Workflow\DeepFrames.Workflow.Preprocess.pas',
  DeepFrames.Workflow.DocumentChain in 'Workflow\DeepFrames.Workflow.DocumentChain.pas',
  DeepFrames.Workflow.AgentChain in 'Workflow\DeepFrames.Workflow.AgentChain.pas',
  DeepFrames.Workflow.AudioChain in 'Workflow\DeepFrames.Workflow.AudioChain.pas',
  DeepFrames.Workflow.VideoChain in 'Workflow\DeepFrames.Workflow.VideoChain.pas',
  DeepFrames.Workflow.PackageChain in 'Workflow\DeepFrames.Workflow.PackageChain.pas',
  DeepFrames.UI.MainForm in 'UI\DeepFrames.UI.MainForm.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;

  DeepBase.Manager.DeepBase.InitializeOrRaise;
  try
    TDeepFramesBootstrap.RegisterServices;
    Application.CreateForm(TMainForm, MainForm);
    DeepBase.Manager.DeepBase.FireReadyCallbacks;
    Application.Run;
  finally
    TDeepFramesBootstrap.Shutdown;
    DeepBase.Manager.DeepBase.Finalize;
  end;
end.
