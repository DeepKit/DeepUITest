unit TestOutputFunctions;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, System.DateUtils,
  uModels, CtrlReport, HelperFiles;

type
  [TestFixture]
  TTestOutputFunctions = class
  private
    FTestDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Test_AddSealMark_AddsComment;
    [Test]
    procedure Test_SaveOutputCode_CreatesFile;
    [Test]
    procedure Test_SaveSealRecord_CreatesFile;
    [Test]
    procedure Test_SaveSealRecord_ContainsReportID;
    [Test]
    procedure Test_SaveSealRecord_ContainsSealHash;
  end;

implementation

procedure TTestOutputFunctions.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath, 'DeepDevLiteOutputTests');
  if not TDirectory.Exists(FTestDir) then
    TDirectory.CreateDirectory(FTestDir);
end;

procedure TTestOutputFunctions.TearDown;
begin
  if TDirectory.Exists(FTestDir) then
  begin
    try
      TDirectory.Delete(FTestDir, True);
    except
    end;
  end;
end;

procedure TTestOutputFunctions.Test_AddSealMark_AddsComment;
var
  SourceCode, SealedCode: string;
begin
  SourceCode := 'def hello():' + sLineBreak + '    print("Hello")';
  
  SealedCode := ReportController.AddSealMark(SourceCode, 'PRG-20260220-0001', 
    'abc123def456');
  
  Assert.IsTrue(Pos('DeepDevLite Sealed', SealedCode) > 0);
  Assert.IsTrue(Pos('PRG-20260220-0001', SealedCode) > 0);
  Assert.IsTrue(Pos('abc123def456', SealedCode) > 0);
  Assert.IsTrue(Pos('def hello():', SealedCode) > 0);
end;

procedure TTestOutputFunctions.Test_SaveOutputCode_CreatesFile;
var
  SourceCode, FilePath: string;
  Success: Boolean;
begin
  SourceCode := 'print("test")';
  FilePath := TPath.Combine(FTestDir, 'output_test.py');
  
  Success := ReportController.SaveOutputCode(SourceCode, 'PRG-001', 'hash123', FilePath);
  
  Assert.IsTrue(Success);
  Assert.IsTrue(TFile.Exists(FilePath));
end;

procedure TTestOutputFunctions.Test_SaveSealRecord_CreatesFile;
var
  Report: TVerificationReport;
  FilePath: string;
  Success: Boolean;
begin
  Report.Clear;
  Report.ReportID := 'PRG-20260220-0001';
  Report.ProjectNameZH := 'Test Project';
  Report.SourceLang := slPython;
  Report.AIModel := 'claude-sonnet';
  Report.SealHash := 'abc123def456';
  Report.VerifiedAt := Now;
  SetLength(Report.Scenarios, 2);
  Report.Scenarios[0].ID := 'S1';
  Report.Scenarios[0].Desc := 'Scenario 1';
  Report.Scenarios[0].Status := ssPass;
  Report.Scenarios[1].ID := 'S2';
  Report.Scenarios[1].Desc := 'Scenario 2';
  Report.Scenarios[1].Status := ssPass;
  
  FilePath := TPath.Combine(FTestDir, 'seal_test.txt');
  
  Success := ReportController.SaveSealRecord(Report, 'test.py', FilePath);
  
  Assert.IsTrue(Success);
  Assert.IsTrue(TFile.Exists(FilePath));
end;

procedure TTestOutputFunctions.Test_SaveSealRecord_ContainsReportID;
var
  Report: TVerificationReport;
  FilePath, Content: string;
begin
  Report.Clear;
  Report.ReportID := 'PRG-20260220-TEST';
  Report.ProjectNameZH := 'My Project';
  Report.SourceLang := slPython;
  Report.AIModel := 'test-model';
  Report.SealHash := 'testhash123';
  Report.VerifiedAt := Now;
  
  FilePath := TPath.Combine(FTestDir, 'seal_content_test.txt');
  ReportController.SaveSealRecord(Report, 'app.py', FilePath);
  
  Content := TFile.ReadAllText(FilePath);
  
  Assert.IsTrue(Pos('PRG-20260220-TEST', Content) > 0);
end;

procedure TTestOutputFunctions.Test_SaveSealRecord_ContainsSealHash;
var
  Report: TVerificationReport;
  FilePath, Content: string;
begin
  Report.Clear;
  Report.ReportID := 'PRG-001';
  Report.ProjectNameZH := 'Test';
  Report.SourceLang := slPython;
  Report.AIModel := 'model';
  Report.SealHash := 'UNIQUE_HASH_12345';
  Report.VerifiedAt := Now;
  
  FilePath := TPath.Combine(FTestDir, 'seal_hash_test.txt');
  ReportController.SaveSealRecord(Report, 'test.py', FilePath);
  
  Content := TFile.ReadAllText(FilePath);
  
  Assert.IsTrue(Pos('UNIQUE_HASH_12345', Content) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestOutputFunctions);

end.
