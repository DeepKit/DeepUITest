{ ============================================================================
  DeepSpec.Tests.dpr

  DUnitX console test runner for DeepSpec unit tests.
  ============================================================================ }

program DeepSpec.Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  Test.DeepSpec.Yaml.Parser in 'Test.DeepSpec.Yaml.Parser.pas',
  Test.DeepSpec.Validation in 'Test.DeepSpec.Validation.pas',
  DeepSpec.Yaml.Parser in '..\src\core\DeepSpec.Yaml.Parser.pas',
  DeepSpec.Models in '..\src\models\DeepSpec.Models.pas',
  DeepSpec.Validation in '..\src\core\DeepSpec.Validation.pas';

var
  LRunner: ITestRunner;
  LResults: IRunResults;
  LLogger: ITestLogger;
  LNUnitLogger: ITestLogger;
begin
  try
    TDUnitX.CheckCommandLine;
    LRunner := TDUnitX.CreateRunner;
    LLogger := TDUnitXConsoleLogger.Create(True);
    LRunner.AddLogger(LLogger);

    LNUnitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    LRunner.AddLogger(LNUnitLogger);

    LRunner.FailsOnNoAsserts := False;
    LResults := LRunner.Execute;

    if not LResults.AllPassed then
      System.ExitCode := 1;
  except
    on E: Exception do
    begin
      WriteLn(E.ClassName, ': ', E.Message);
      System.ExitCode := 1;
    end;
  end;
end.
