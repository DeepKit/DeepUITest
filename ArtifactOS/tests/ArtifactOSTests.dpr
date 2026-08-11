program ArtifactOSTests;

{$APPTYPE CONSOLE}

{ ArtifactOS DUnitX test runner — Delphi 37.0 compatible. }

uses
  System.SysUtils,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  ArtifactOS.Core.DB.Connection,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys.Intf,
  FireDAC.Phys,
  FireDAC.Phys.PG,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.DApt,
  FireDAC.DApt.Intf,
  FireDAC.Comp.Client,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  DUnitX.TestRunner,
  ArtifactOS.Tests.E2EChain,
  ArtifactOS.Tests.QualityGate,
  ArtifactOS.Tests.StateMachine,
  ArtifactOS.Tests.ShadowRun,
  ArtifactOS.Tests.LegacyImport,
  ArtifactOS.Tests.Integration,
  ArtifactOS.Tests.DBIntegrity,
  ArtifactOS.Tests.StrategyUnit,
  ArtifactOS.Tests.LegacyExit,
  ArtifactOS.Tests.CandidatePackImporter,
  ArtifactOS.Tests.SharedKnowledge;

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  try
    // Initialize DeepBase so LoadSecret/GetConfig work for DB password
    DeepBase.Manager.DeepBase.InitializeOrRaise;
    try
      TDUnitX.CheckCommandLine;
      Runner := TDUnitX.CreateRunner;
      Runner.UseRTTI := True;
      Runner.FailsOnNoAsserts := False;
      Runner.AddLogger(TDUnitXConsoleLogger.Create(False));
      Results := Runner.Execute;

      if not Results.AllPassed then
      begin
        WriteLn('========================================');
        WriteLn('  SOME TESTS FAILED');
        WriteLn('========================================');
        ExitCode := 1;
      end
      else
      begin
        WriteLn('========================================');
        WriteLn('  ALL TESTS PASSED');
        WriteLn('========================================');
      end;
    finally
      DeepBase.Manager.DeepBase.Finalize;
    end;
  except
    on E: Exception do
    begin
      WriteLn('FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
