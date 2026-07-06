program DeepAxisTestRunner;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  Test.Contracts in 'Test.Contracts.pas',
  Test.Metrics in 'Test.Metrics.pas',
  Test.Radar in 'Test.Radar.pas',
  Test.Base in 'Test.Base.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  // Force linking of test fixture classes
  TTestContracts.ClassName;
  TTestMetrics.ClassName;
  TTestRadar.ClassName;

  TDUnitX.CheckCommandLine;
  Runner := TDUnitX.CreateRunner;
  Runner.UseRTTI := True;
  Runner.FailsOnNoAsserts := False;
  Runner.AddLogger(TDUnitXConsoleLogger.Create(True));

  Results := Runner.Execute;

  if not Results.AllPassed then
    ExitCode := 1;
end.