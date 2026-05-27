program ArtifactOS;

{ ArtifactOS — Source-to-Artifact Production and Amplification Kernel }
{ Phase 1A: shadow run only.  Target database: artifactos_test. }

uses
  System.SysUtils,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Core.Dashboard,
  ArtifactOS.Core.ChainRunner;

begin
  try
    DeepBase.InitializeOrRaise;
    try
      WriteLn('ArtifactOS Phase 1A');
      WriteLn('==================');
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
          'procedures to defining desired outcomes. This article explores three dimensions ' +
          'of this transformation: cognitive, organizational, and methodological.',
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
            WriteLn('  Artifact:          ', ArtifactOS_DB.ExecuteScalar('SELECT status FROM artifactos.artifact WHERE id=''' + R.ArtifactId + ''''));
            WriteLn('  Quality:           ', ArtifactOS_DB.ExecuteScalar('SELECT qualified_status FROM artifactos.quality_snapshot WHERE id=''' + R.SnapshotId + ''''));
            WriteLn('  Package:           ', ArtifactOS_DB.ExecuteScalar('SELECT status FROM artifactos.publication_package WHERE id=''' + R.PackageId + ''''));
            WriteLn('  RealPublishGate:   ', ArtifactOS_DB.ExecuteScalar('SELECT gate_status::text FROM artifactos.check_real_publish_gate()'));
            WriteLn('  State machine:     ', ArtifactOS_DB.ExecuteScalar('SELECT COUNT(*)::text FROM artifactos.substudio_execution_task'), ' tasks');
            WriteLn('  Event ledger:      ', ArtifactOS_DB.ExecuteScalar('SELECT COUNT(*)::text FROM artifactos.event_ledger'), ' entries');
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
      DeepBase.Finalize;
    end;
  except
    on E: Exception do
    begin
      WriteLn('FATAL: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.