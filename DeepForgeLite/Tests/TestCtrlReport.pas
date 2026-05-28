unit TestCtrlReport;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.DateUtils, System.Hash, uModels, CtrlReport;

type
  [TestFixture]
  TTestCtrlReport = class
  public
    [Test]
    procedure Test_GenerateReportID_Format;
    [Test]
    procedure Test_GenerateReportID_Uniqueness;
    [Test]
    procedure Test_GenerateSealHash_Consistent;
    [Test]
    procedure Test_GenerateSealHash_Different;
    [Test]
    procedure Test_CreateReport_Basic;
  end;

implementation

procedure TTestCtrlReport.Test_GenerateReportID_Format;
var
  ID: string;
begin
  ID := TReportController.GenerateReportID;
  
  Assert.IsTrue(ID.StartsWith('PRG-'));
  Assert.AreEqual(17, ID.Length);
  Assert.IsTrue(ID.Contains('-'));
end;

procedure TTestCtrlReport.Test_GenerateReportID_Uniqueness;
var
  IDs: TArray<string>;
  I: Integer;
begin
  Randomize;
  SetLength(IDs, 100);
  
  for I := 0 to High(IDs) do
    IDs[I] := TReportController.GenerateReportID;
  
  for I := 0 to High(IDs) - 1 do
    Assert.AreNotEqual(IDs[I], IDs[I + 1]);
end;

procedure TTestCtrlReport.Test_GenerateSealHash_Consistent;
var
  Report: TVerificationReport;
  Hash1, Hash2: string;
begin
  Report.Clear;
  Report.ReportID := 'PRG-20260220-0001';
  Report.ProjectNameZH := 'TestProject';
  Report.VerifiedAt := EncodeDateTime(2026, 2, 20, 10, 30, 0, 0);
  SetLength(Report.Scenarios, 2);
  Report.Scenarios[0].ID := 'S1';
  Report.Scenarios[0].Desc := 'Scenario 1';
  Report.Scenarios[1].ID := 'S2';
  Report.Scenarios[1].Desc := 'Scenario 2';
  
  Hash1 := ReportController.GenerateSealHash(Report);
  Hash2 := ReportController.GenerateSealHash(Report);
  
  Assert.AreEqual(Hash1, Hash2);
  Assert.AreEqual(64, Hash1.Length);
end;

procedure TTestCtrlReport.Test_GenerateSealHash_Different;
var
  Report1, Report2: TVerificationReport;
  Hash1, Hash2: string;
begin
  Report1.Clear;
  Report1.ReportID := 'PRG-20260220-0001';
  Report1.ProjectNameZH := 'ProjectA';
  Report1.VerifiedAt := Now;
  
  Report2.Clear;
  Report2.ReportID := 'PRG-20260220-0002';
  Report2.ProjectNameZH := 'ProjectB';
  Report2.VerifiedAt := Now;
  
  Hash1 := ReportController.GenerateSealHash(Report1);
  Hash2 := ReportController.GenerateSealHash(Report2);
  
  Assert.AreNotEqual(Hash1, Hash2);
end;

procedure TTestCtrlReport.Test_CreateReport_Basic;
var
  Contract: TContract;
  Report: TVerificationReport;
  S: TContractScenario;
begin
  Contract.Clear;
  Contract.Title := 'Test Module';
  Contract.Language := slPython;
  
  S.Clear;
  S.ID := 'S1';
  S.Desc := 'Test scenario';
  S.ScenType := stNormal;
  SetLength(Contract.Scenarios, 1);
  Contract.Scenarios[0] := S;
  
  Report := ReportController.CreateReport(Contract, 'test.py', 'claude-sonnet');
  
  Assert.IsTrue(Report.ReportID.StartsWith('PRG-'));
  Assert.AreEqual('Test Module', Report.ProjectNameZH);
  Assert.AreEqual('test.py', Report.SourceFileName);
  Assert.AreEqual(slPython, Report.SourceLang);
  Assert.AreEqual('claude-sonnet', Report.AIModel);
  Assert.IsTrue(Report.IsSealed);
  Assert.AreEqual(64, Report.SealHash.Length);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCtrlReport);

end.
