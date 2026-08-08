program DeepFlow.Tests.Runner;
(*
  DeepFlow DUnitX Test Runner
  ===========================
  Console runner for Executor / E2E / Benchmark test suites.

  Build:
    dcc32 -B -Q -CC -U"Source;Source\Core;Source\Workflow;Source\Tests;dcu;$(BDS)\lib\win32\release" -NU"dcu" -E"bin" Source\Tests\DeepFlow.Tests.Runner.dpr

  Usage:
    DeepFlow.Tests.Runner.exe [--exit:continue]   run all tests
    DeepFlow.Tests.Runner.exe --fixture:TWorkflowExecutorTests
    DeepFlow.Tests.Runner.exe --xml:results.xml
*)

{$APPTYPE CONSOLE}

{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  DUnitX.Windows.Console,
  DeepFlow.Tests.Executor,
  DeepFlow.Tests.E2E,
  DeepFlow.Tests.Benchmark;

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;

begin
  try
    TDUnitX.CheckCommandLine;
    // Create the runner
    runner := TDUnitX.CreateRunner;
    // Test fixtures are registered via TDUnitX.RegisterTestFixture in
    // each test unit's initialization section, so RTTI discovery is off.
    runner.UseRTTI := False;
    runner.FailsOnNoAsserts := True; // Assertions must be made during tests

    // Console logging
    if TDUnitX.Options.ConsoleMode <> TDUnitXConsoleMode.Off then
    begin
      logger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDUnitXConsoleMode.Quiet);
      runner.AddLogger(logger);
    end;

    // XML output for CI
    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);

    // Run tests
    results := runner.Execute;
    runner := nil;

    // CI exit code
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    results := nil;
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
end.
