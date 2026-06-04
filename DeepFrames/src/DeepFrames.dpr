program DeepFrames;

uses
  Vcl.Forms,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  DeepFrames.App.Bootstrap in 'App\DeepFrames.App.Bootstrap.pas',
  DeepFrames.App.Constants in 'App\DeepFrames.App.Constants.pas',
  DeepFrames.App.Services in 'App\DeepFrames.App.Services.pas',
  DeepFrames.Shared.Consts in 'Shared\DeepFrames.Shared.Consts.pas',
  DeepFrames.Shared.JsonSchema in 'Shared\DeepFrames.Shared.JsonSchema.pas',
  DeepFrames.Domain.Types in 'Domain\DeepFrames.Domain.Types.pas',
  DeepFrames.Domain.Project in 'Domain\DeepFrames.Domain.Project.pas',
  DeepFrames.Domain.VoiceProfile in 'Domain\DeepFrames.Domain.VoiceProfile.pas',
  DeepFrames.Persistence.Connection in 'Persistence\DeepFrames.Persistence.Connection.pas',
  DeepFrames.Persistence.Migrations in 'Persistence\DeepFrames.Persistence.Migrations.pas',
  DeepFrames.Persistence.Repository in 'Persistence\DeepFrames.Persistence.Repository.pas',
  DeepFrames.Workflow.Preprocess in 'Workflow\DeepFrames.Workflow.Preprocess.pas',
  DeepFrames.Workflow.DocumentChain in 'Workflow\DeepFrames.Workflow.DocumentChain.pas',
  DeepFrames.Workflow.AgentChain in 'Workflow\DeepFrames.Workflow.AgentChain.pas',
  DeepFrames.Workflow.AudioChain in 'Workflow\DeepFrames.Workflow.AudioChain.pas',
  DeepFrames.Workflow.VideoChain in 'Workflow\DeepFrames.Workflow.VideoChain.pas',
  DeepFrames.Workflow.PackageChain in 'Workflow\DeepFrames.Workflow.PackageChain.pas',
  DeepFrames.Workflow.ExtensionChain in 'Workflow\DeepFrames.Workflow.ExtensionChain.pas',
  DeepFrames.Provider.Types in 'Provider\DeepFrames.Provider.Types.pas',
  DeepFrames.Provider.Intf in 'Provider\DeepFrames.Provider.Intf.pas',
  DeepFrames.Provider.Registry in 'Provider\DeepFrames.Provider.Registry.pas',
  DeepFrames.Provider.Fake in 'Provider\DeepFrames.Provider.Fake.pas',
  DeepFrames.Provider.StepFun in 'Provider\DeepFrames.Provider.StepFun.pas',
  DeepFrames.Workflow.VideoCompiler in 'Workflow\DeepFrames.Workflow.VideoCompiler.pas',
  DeepFrames.Workflow.GateEvaluator in 'Workflow\DeepFrames.Workflow.GateEvaluator.pas',
  DeepFrames.Workflow.StyleKeeper in 'Workflow\DeepFrames.Workflow.StyleKeeper.pas',
  DeepFrames.Workflow.Resume in 'Workflow\DeepFrames.Workflow.Resume.pas',
  DeepFrames.Workflow.PromptVersion in 'Workflow\DeepFrames.Workflow.PromptVersion.pas',
  DeepFrames.Workflow.AudioProcessor in 'Workflow\DeepFrames.Workflow.AudioProcessor.pas',
  DeepFrames.Workflow.SubtitleEngine in 'Workflow\DeepFrames.Workflow.SubtitleEngine.pas',
  DeepFrames.Workflow.AssetRetention in 'Workflow\DeepFrames.Workflow.AssetRetention.pas',
  DeepFrames.Workflow.PackageExporter in 'Workflow\DeepFrames.Workflow.PackageExporter.pas',
  DeepFrames.Workflow.WorkerProtocol in 'Workflow\DeepFrames.Workflow.WorkerProtocol.pas',
  DeepFrames.Workflow.ReadinessChecker in 'Workflow\DeepFrames.Workflow.ReadinessChecker.pas',
  DeepFrames.Workflow.DocumentExport in 'Workflow\DeepFrames.Workflow.DocumentExport.pas',
  DeepFrames.Workflow.BgmManager in 'Workflow\DeepFrames.Workflow.BgmManager.pas',
  DeepFrames.Workflow.ArtifactOSBridge in 'Workflow\DeepFrames.Workflow.ArtifactOSBridge.pas',
  DeepFrames.Workflow.EventLog in 'Workflow\DeepFrames.Workflow.EventLog.pas',
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