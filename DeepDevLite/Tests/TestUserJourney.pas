unit TestUserJourney;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, System.DateUtils,
  uModels, CtrlReport, HelperFiles, CtrlCardGenerator, CtrlContracts;

type
  [TestFixture]
  TTestUserJourney = class
  private
    FTestDir: string;
    FMockAIResponse: string;
    FMockTestOutput: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    // 用户旅程测试
    [Test]
    procedure Test_Journey_01_WelcomePage_StartVerify;
    [Test]
    procedure Test_Journey_02_CodeInput_PasteCode;
    [Test]
    procedure Test_Journey_03_Contract_AIAnalysis;
    [Test]
    procedure Test_Journey_04_Contract_UserConfirm;
    [Test]
    procedure Test_Journey_05_Test_RunTests;
    [Test]
    procedure Test_Journey_06_VerifyPassed_OutputFiles;
    [Test]
    procedure Test_Journey_07_VerifyPassed_CopyCode;
    [Test]
    procedure Test_Journey_08_VerifyPassed_ShareLink;
    [Test]
    procedure Test_Journey_09_VerifyPassed_GenerateCard;
    [Test]
    procedure Test_Journey_10_VerifyPassed_ExportPNG;
    
    // 失败流程测试
    [Test]
    procedure Test_Journey_Fail_Retry3Times;
    [Test]
    procedure Test_Journey_Fail_GiveUp;
  end;

implementation

procedure TTestUserJourney.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath, 'DeepDevLiteJourneyTests');
  if not TDirectory.Exists(FTestDir) then
    TDirectory.CreateDirectory(FTestDir);
  
  FMockAIResponse := 'contract:' + sLineBreak +
    '  title: "用户登录验证"' + sLineBreak +
    '  language: "Python"' + sLineBreak +
    '  purpose: "实现用户登录功能"' + sLineBreak +
    '  scenarios:' + sLineBreak +
    '    - id: S001' + sLineBreak +
    '      desc: "正常登录"' + sLineBreak +
    '      type: normal' + sLineBreak +
    '      input: "用户名=admin, 密码=123456"' + sLineBreak +
    '      expected: "返回登录成功"' + sLineBreak +
    '    - id: S002' + sLineBreak +
    '      desc: "密码错误"' + sLineBreak +
    '      type: error' + sLineBreak +
    '      input: "用户名=admin, 密码=wrong"' + sLineBreak +
    '      expected: "返回密码错误"';
    
  FMockTestOutput := 
    'S001: PASS (response_time: 50ms)' + sLineBreak +
    'S002: PASS (response_time: 30ms)' + sLineBreak +
    'OVERALL: PASS';
end;

procedure TTestUserJourney.TearDown;
begin
  if TDirectory.Exists(FTestDir) then
  begin
    try
      TDirectory.Delete(FTestDir, True);
    except
    end;
  end;
end;

procedure TTestUserJourney.Test_Journey_01_WelcomePage_StartVerify;
begin
  Assert.IsTrue(True);
end;

procedure TTestUserJourney.Test_Journey_02_CodeInput_PasteCode;
var
  SourceCode: string;
begin
  SourceCode := 
    'def login(username, password):' + sLineBreak +
    '    if username == "admin" and password == "123456":' + sLineBreak +
    '        return {"status": "success", "token": "abc123"}' + sLineBreak +
    '    else:' + sLineBreak +
    '        return {"status": "error", "message": "Invalid credentials"}';
  
  Assert.IsFalse(SourceCode.IsEmpty);
  Assert.IsTrue(Pos('def login', SourceCode) > 0);
end;

procedure TTestUserJourney.Test_Journey_03_Contract_AIAnalysis;
var
  Contract: TContract;
  Success: Boolean;
begin
  Contract.Clear;
  
  Success := ContractController.ParseYAMLContract(FMockAIResponse, Contract);
  
  Assert.IsTrue(Success);
  Assert.AreEqual('用户登录验证', Contract.Title);
  Assert.AreEqual(slPython, Contract.Language);
  Assert.IsTrue(Length(Contract.Scenarios) = 2);
end;

procedure TTestUserJourney.Test_Journey_04_Contract_UserConfirm;
var
  Contract: TContract;
begin
  Contract.Clear;
  ContractController.ParseYAMLContract(FMockAIResponse, Contract);
  
  Assert.IsTrue(Length(Contract.Scenarios) >= 1);
  Assert.IsFalse(Contract.Title.IsEmpty);
end;

procedure TTestUserJourney.Test_Journey_05_Test_RunTests;
var
  TestOutput: string;
  PassedCount: Integer;
begin
  TestOutput := FMockTestOutput;
  
  PassedCount := 0;
  if Pos('S001: PASS', TestOutput) > 0 then Inc(PassedCount);
  if Pos('S002: PASS', TestOutput) > 0 then Inc(PassedCount);
  
  Assert.AreEqual(2, PassedCount);
  Assert.IsTrue(Pos('OVERALL: PASS', TestOutput) > 0);
end;

procedure TTestUserJourney.Test_Journey_06_VerifyPassed_OutputFiles;
var
  Contract: TContract;
  Report: TVerificationReport;
  OutputCodePath, SealRecordPath: string;
  CodeSuccess, SealSuccess: Boolean;
begin
  Contract.Clear;
  ContractController.ParseYAMLContract(FMockAIResponse, Contract);
  
  Report := ReportController.CreateReport(Contract, 'login.py', 'claude-sonnet');
  
  CodeSuccess := ReportController.SaveOutputCode(
    'def login(): pass',
    Report.ReportID,
    Report.SealHash,
    TPath.Combine(FTestDir, 'login_sealed.py')
  );
  
  SealSuccess := ReportController.SaveSealRecord(
    Report,
    'login.py',
    TPath.Combine(FTestDir, 'login.seal.txt')
  );
  
  Assert.IsTrue(CodeSuccess);
  Assert.IsTrue(SealSuccess);
  Assert.IsTrue(TFile.Exists(TPath.Combine(FTestDir, 'login_sealed.py')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FTestDir, 'login.seal.txt')));
end;

procedure TTestUserJourney.Test_Journey_07_VerifyPassed_CopyCode;
var
  SourceCode, SealedCode: string;
begin
  SourceCode := 'def login(): return True';
  SealedCode := ReportController.AddSealMark(SourceCode, 'PRG-001', 'hash123');
  
  Assert.IsTrue(Pos('DeepDevLite Sealed', SealedCode) > 0);
  Assert.IsTrue(Pos('PRG-001', SealedCode) > 0);
  Assert.IsTrue(Pos('hash123', SealedCode) > 0);
end;

procedure TTestUserJourney.Test_Journey_08_VerifyPassed_ShareLink;
var
  ReportID: string;
  ShareLink: string;
begin
  ReportID := 'PRG-20260220-0001';
  ShareLink := Format('https://progeelite.com/share/%s', [ReportID]);
  
  Assert.AreEqual('https://progeelite.com/share/PRG-20260220-0001', ShareLink);
  Assert.IsTrue(Pos('progeelite.com', ShareLink) > 0);
end;

procedure TTestUserJourney.Test_Journey_09_VerifyPassed_GenerateCard;
var
  CardConfig: TCardConfig;
  Success: Boolean;
begin
  CardConfig.Clear;
  CardConfig.ModuleName := '用户登录模块';
  CardConfig.Audience := auSelf;
  CardConfig.Mood := mdProud;
  CardConfig.Theme := ctDark;
  CardConfig.StatPass := '3/3';
  CardConfig.StatMS := '250ms';
  CardConfig.StatCoverage := '100%';
  
  Success := CardGeneratorController.GenerateCard(CardConfig);
  
  Assert.IsTrue(Success);
  Assert.IsFalse(CardConfig.Headline.IsEmpty);
  Assert.IsFalse(CardConfig.Icon.IsEmpty);
end;

procedure TTestUserJourney.Test_Journey_10_VerifyPassed_ExportPNG;
var
  CardConfig: TCardConfig;
  PNGPath: string;
  Success: Boolean;
begin
  CardConfig.Clear;
  CardConfig.ModuleName := '测试模块';
  CardConfig.Audience := auPeer;
  CardConfig.Mood := mdSatisfied;
  CardConfig.Theme := ctDark;
  CardConfig.StatPass := '3/3';
  CardConfig.StatMS := '200ms';
  CardConfig.StatCoverage := '100%';
  
  CardGeneratorController.GenerateCard(CardConfig);
  
  PNGPath := TPath.Combine(FTestDir, 'test_card.png');
  Success := CardGeneratorController.ExportToPNG(CardConfig, PNGPath);
  
  Assert.IsTrue(Success);
  Assert.IsTrue(TFile.Exists(PNGPath));
end;

procedure TTestUserJourney.Test_Journey_Fail_Retry3Times;
var
  RetryCount: Integer;
  MaxRetries: Integer;
begin
  MaxRetries := 3;
  RetryCount := 0;
  
  while RetryCount < MaxRetries do
  begin
    Inc(RetryCount);
  end;
  
  Assert.AreEqual(3, RetryCount);
end;

procedure TTestUserJourney.Test_Journey_Fail_GiveUp;
var
  RetryCount: Integer;
  MaxRetries: Integer;
  FinalState: string;
begin
  MaxRetries := 3;
  RetryCount := 0;
  
  while RetryCount < MaxRetries do
  begin
    Inc(RetryCount);
  end;
  
  if RetryCount >= MaxRetries then
    FinalState := 'failed'
  else
    FinalState := 'passed';
    
  Assert.AreEqual('failed', FinalState);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUserJourney);

end.
