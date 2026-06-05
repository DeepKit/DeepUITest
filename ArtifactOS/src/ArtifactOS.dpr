program ArtifactOS;

{ ArtifactOS — Source-to-Artifact Production and Amplification Kernel }
{ Phase 1A: shadow run only.  Target database: artifactos_test. }
{ Modes: (default) CLI dashboard, --desk VCL GUI, --engine background, --smoke-runtime test }

uses
  System.SysUtils,
  Vcl.Forms,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.UI.Intf,
  FireDAC.VCLUI.Wait,
  FireDAC.Phys.Intf,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.DApt,
  FireDAC.DApt.Intf,
  FireDAC.Comp.Client,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  DeepBase.AutoFix,
  DeepBase.AutoFix.VclHook,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Core.Dashboard,
  ArtifactOS.Core.Runtime.Smoke,
  ArtifactOS.Core.Runtime.Engine,
  ArtifactOS.Core.Runtime.EngineCallbacks,
  ArtifactOS.Core.AutoFix.Scenarios,
  ArtifactOS.Services.ChainRunner,
  ArtifactOS.Services.DeepLLMProxy,
  ArtifactOS.Services.GenerationService,
  ArtifactOS.Services.TopicFunnel,
  ArtifactOS.Services.PublicationBridge,
  ArtifactOS.Services.CognitiveGovernance,
  ArtifactOS.Services.PerformanceCollector,
  ArtifactOS.Services.FeedbackEvolution,
  ArtifactOS.Desk.MainForm in 'Desk\ArtifactOS.Desk.MainForm.pas' {DeskMainForm},
  ArtifactOS.Desk.Services in 'Desk\ArtifactOS.Desk.Services.pas',
  ArtifactOS.Desk.Commands in 'Desk\ArtifactOS.Desk.Commands.pas',
  ArtifactOS.Desk.Providers in 'Desk\ArtifactOS.Desk.Providers.pas',
  ArtifactOS.Desk.EvolutionConsole in 'Desk\ArtifactOS.Desk.EvolutionConsole.pas';

{$R *.res}

begin
  try
    FDManager().SilentMode := True;
    AutoFix.Install;
    TAutoFixVclHook.Install;
    DeepBase.Manager.DeepBase.InitializeOrRaise;
    try
      // --smoke-runtime: CLI smoke test mode
      if FindCmdLineSwitch('smoke-runtime', True) then
      begin
        var SmokeMessage: string;
        if TRuntimeSmoke.Run(SmokeMessage) then
        begin
          WriteLn('Runtime smoke PASS: ', SmokeMessage);
          ExitCode := 0;
        end
        else
        begin
          WriteLn('Runtime smoke FAIL: ', SmokeMessage);
          ExitCode := 1;
        end;
        Exit;
      end;

      // --engine: background engine mode
      if FindCmdLineSwitch('engine', True) then
      begin
        var Config := DefaultEngineConfig;
        Config.AppVersion := '1.0';
        WriteLn(Format('Engine idle timeout: %d minutes', [Config.IdleTimeoutMs div 60000]));
        TRuntimeEngine.Create(Config).Run(
          procedure(const ACmdId, ACmdType, APayload: string)
          begin
            TEngineCallbacks.DispatchCommand(ACmdId, ACmdType, APayload);
          end);
        Exit;
      end;

      // --desk: VCL GUI mode (DeepShell)
      if FindCmdLineSwitch('desk', True) then
      begin
        Application.Initialize;
        Application.MainFormOnTaskbar := True;
        Application.Title := 'ArtifactOS Desk';

        RegisterArtifactOSAutoFixScenarios;

        Application.CreateForm(TDeskMainForm, DeskMainForm);
        DeepBase.Manager.DeepBase.FireReadyCallbacks;
        Application.Run;
        Exit;
      end;

      // Default: CLI dashboard mode
      WriteLn('ArtifactOS Phase 1A');
      WriteLn('==================');
      WriteLn;
      WriteLn('Usage: ArtifactOS.exe [--desk] [--engine] [--smoke-runtime]');
      WriteLn;

      TArtifactOSDashboard.Run;

      var CanStart: Boolean;
      var Reason: string;
      TArtifactOSDashboard.RunShadowStartCheck(CanStart, Reason);
      WriteLn;
      WriteLn('Shadow Run Ready: ', CanStart, ' (', Reason, ')');

      if CanStart then
      begin
        var R: TChainResult;
        if TChainRunner.RunFullChain('Shadow Run Test: AI and Structural Transformation',
          'AI is not just a productivity tool. It represents a structural transformation ' +
          'in how we think about knowledge work. The fundamental shift is from executing ' +
          'procedures to defining desired outcomes. ' +
          'At the cognitive level, AI forces us to distinguish between procedural knowledge ' +
          'and outcome-oriented reasoning. What matters is no longer knowing the steps, but ' +
          'understanding the constraint space within which those steps must operate. ' +
          'At the organizational level, AI reshapes how teams coordinate. The bottleneck ' +
          'shifts from individual productivity to collective sense-making and alignment. ' +
          'These dimensions together suggest a future where human expertise is redirected ' +
          'from execution to definition, from coding to constraint articulation.',
          R) then
        begin
          WriteLn;
          WriteLn('Full Chain Created:');
          WriteLn('  Case:      ', R.CaseId);
          WriteLn('  Studio:    ', R.StudioId);
          WriteLn('  Artifact:  ', R.ArtifactId);
          WriteLn('  Version:   ', R.VersionId);
          WriteLn('  Quality:   ', R.SnapshotId);
          WriteLn('  Package:   ', R.PackageId);

          ArtifactOS_DB.Connect;
          try
            WriteLn;
            WriteLn('Verification:');
            WriteLn('  Artifact:          ', ArtifactOS_DB.ExecuteScalarJson('SELECT status::text FROM artifactos.artifact WHERE id=:id::uuid', '{"id":"' + R.ArtifactId + '"}'));
            WriteLn('  Quality:           ', ArtifactOS_DB.ExecuteScalarJson('SELECT qualified_status::text FROM artifactos.quality_snapshot WHERE id=:id::uuid', '{"id":"' + R.SnapshotId + '"}'));
            WriteLn('  Package:           ', ArtifactOS_DB.ExecuteScalarJson('SELECT status::text FROM artifactos.publication_package WHERE id=:id::uuid', '{"id":"' + R.PackageId + '"}'));
            WriteLn('  RealPublishGate:   ', ArtifactOS_DB.ExecuteScalarJson('SELECT (artifactos.check_real_publish_gate() ->> ''gate_status'')::text', ''));
            WriteLn('  State machine:     ', ArtifactOS_DB.ExecuteScalarJson('SELECT COUNT(*)::text FROM artifactos.substudio_execution_task', ''), ' tasks');
            WriteLn('  Event ledger:      ', ArtifactOS_DB.ExecuteScalarJson('SELECT COUNT(*)::text FROM artifactos.event_ledger', ''), ' entries');
          finally
            ArtifactOS_DB.Disconnect;
          end;

          TChainRunner.CleanupChain(R);
          WriteLn;
          WriteLn('Test chain cleaned up.');
        end
        else
          WriteLn('Chain creation failed: ES gate rejected the content.');
      end;
    finally
      DeepBase.Manager.DeepBase.Finalize;
    end;
  except
    on E: Exception do
    begin
      WriteLn('FATAL: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.