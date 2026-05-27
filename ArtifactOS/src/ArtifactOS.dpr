program ArtifactOS;

{ ArtifactOS — Source-to-Artifact Production and Amplification Kernel }
{ Phase 1A: shadow run only.  Target database: artifactos_test. }

uses
  System.SysUtils,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Core.Dashboard;

begin
  try
    DeepBase.InitializeOrRaise;
    try
      WriteLn('ArtifactOS Phase 1A Dashboard');
      WriteLn('===========================');
      TArtifactOSDashboard.Run;
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