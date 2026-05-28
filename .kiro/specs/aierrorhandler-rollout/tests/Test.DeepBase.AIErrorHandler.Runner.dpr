program Test.DeepBase.AIErrorHandler.Runner;

{ ============================================================================
  Test.DeepBase.AIErrorHandler.Runner

  DUnitX console runner for spec aierrorhandler-rollout 的 13 条 PBT (阶段一/
  二/三 各 *-标记子任务):
    Property 2, 3, 13      -> Test.DeepBase.AIErrorHandler.SilentMode
    Property 7, 8, E1      -> Test.DeepBase.AIErrorHandler.LLMBridge
    Property 1, 4, 5, 10,
             11, 12        -> Test.DeepBase.AIErrorHandler.Bootstrap
    Property 6             -> Test.DeepBase.AIErrorHandler.Static

  Each test runs at least 100 random iterations matching the pattern in
  02Business\DeepBase\Tests\Test.DeepBase.Cache.PBT.pas (Property25).

  Run:
    Test.DeepBase.AIErrorHandler.Runner.exe
  Returns ExitCode = 0 on success, 1 on test failure, 2 on uncaught error.
  ============================================================================ }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  // 被测代码 (DeepBase 子树, 通过 -U path 解析)
  DeepBase.AIErrorHandler,
  DeepBase.AIErrorHandler.LLMBridge,
  DeepBase.AIErrorHandler.Bootstrap,
  // 测试单元
  Test.DeepBase.AIErrorHandler.SilentMode in 'Test.DeepBase.AIErrorHandler.SilentMode.pas',
  Test.DeepBase.AIErrorHandler.LLMBridge  in 'Test.DeepBase.AIErrorHandler.LLMBridge.pas',
  Test.DeepBase.AIErrorHandler.Bootstrap  in 'Test.DeepBase.AIErrorHandler.Bootstrap.pas',
  Test.DeepBase.AIErrorHandler.Static     in 'Test.DeepBase.AIErrorHandler.Static.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
  NUnitLogger: ITestLogger;

begin
  ReportMemoryLeaksOnShutdown := False;
  try
    TDUnitX.CheckCommandLine;

    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := False;

    Logger := TDUnitXConsoleLogger.Create(True);
    Runner.AddLogger(Logger);

    if TDUnitX.Options.XMLOutputFile <> '' then
    begin
      NUnitLogger := TDUnitXXMLNUnitFileLogger.Create(
        TDUnitX.Options.XMLOutputFile);
      Runner.AddLogger(NUnitLogger);
    end;

    Results := Runner.Execute;

    if not Results.AllPassed then
      System.ExitCode := 1
    else
      System.ExitCode := 0;
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := 2;
    end;
  end;
end.
