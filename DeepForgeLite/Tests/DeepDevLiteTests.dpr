program DeepDevLiteTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  DUnitX.Windows.Console,
  TestModels in 'TestModels.pas',
  TestHelperJson in 'TestHelperJson.pas',
  TestHelperFiles in 'TestHelperFiles.pas',
  TestCtrlReport in 'TestCtrlReport.pas',
  TestOutputFunctions in 'TestOutputFunctions.pas',
  TestUserJourney in 'TestUserJourney.pas',
  uModels in '..\uModels.pas',
  uConstants in '..\uConstants.pas',
  CtrlReport in '..\CtrlReport.pas',
  CtrlContracts in '..\CtrlContracts.pas',
  CtrlCardGenerator in '..\CtrlCardGenerator.pas',
  HelperFiles in '..\HelperFiles.pas',
  uDM in '..\uDM.pas' {DM: TDataModule},
  DeepBase.Manager in '..\..\DeepBase\Core\DeepBase.Manager.pas',
  DeepBase.Config in '..\..\DeepBase\Core\DeepBase.Config.pas',
  DeepBase.Logging in '..\..\DeepBase\Core\DeepBase.Logging.pas',
  DeepBase.DB.DoQry in '..\..\DeepBase\Persistence\DeepBase.DB.DoQry.pas',
  DeepBase.Security in '..\..\DeepBase\Core\DeepBase.Security.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;

begin
  try
    TDUnitX.CheckCommandLine;
    runner := TDUnitX.CreateRunner;
    runner.AddLogger(TDUnitXConsoleLogger.Create(true));
    
    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(
      TPath.Combine(ExtractFilePath(ParamStr(0)), 'TestResults.xml'));
    runner.AddLogger(nunitLogger);
    
    runner.FailsOnNoAsserts := True;
    results := runner.Execute;
    
    if not results.AllPassed then
      System.ExitCode := 1
    else
      System.ExitCode := 0;
      
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := 1;
    end;
  end;
end.
