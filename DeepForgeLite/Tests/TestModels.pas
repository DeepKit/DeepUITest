unit TestModels;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.DateUtils, uModels;

type
  [TestFixture]
  TTestModels = class
  public
    [Test]
    procedure Test_StrToSourceLanguage_Python;
    [Test]
    procedure Test_StrToSourceLanguage_JavaScript;
    [Test]
    procedure Test_StrToSourceLanguage_Unknown;
    [Test]
    procedure Test_DetectLanguage_Py;
    [Test]
    procedure Test_DetectLanguage_Js;
    [Test]
    procedure Test_DetectLanguage_Ts;
    [Test]
    procedure Test_DetectLanguage_Go;
    [Test]
    procedure Test_DetectLanguage_Unknown;
    [Test]
    procedure Test_SourceLanguageToStr;
    [Test]
    procedure Test_GetLangExt;
    [Test]
    procedure Test_Contract_Clear;
    [Test]
    procedure Test_Contract_ToYAML;
    [Test]
    procedure Test_TestResults_GetPassCount;
    [Test]
    procedure Test_TestResults_GetTotalCount;
    [Test]
    procedure Test_VerificationReport_GetPassRate;
    [Test]
    procedure Test_AIConfig_GetModelForLevel;
    [Test]
    procedure Test_VerifyStateToStr;
  end;

implementation

procedure TTestModels.Test_StrToSourceLanguage_Python;
begin
  Assert.AreEqual(slPython, StrToSourceLanguage('Python'));
  Assert.AreEqual(slPython, StrToSourceLanguage('PYTHON'));
  Assert.AreEqual(slPython, StrToSourceLanguage('python'));
end;

procedure TTestModels.Test_StrToSourceLanguage_JavaScript;
begin
  Assert.AreEqual(slJavaScript, StrToSourceLanguage('JavaScript'));
  Assert.AreEqual(slJavaScript, StrToSourceLanguage('JAVASCRIPT'));
end;

procedure TTestModels.Test_StrToSourceLanguage_Unknown;
begin
  Assert.AreEqual(slUnknown, StrToSourceLanguage(''));
  Assert.AreEqual(slUnknown, StrToSourceLanguage('UnknownLang'));
  Assert.AreEqual(slUnknown, StrToSourceLanguage('xyz'));
end;

procedure TTestModels.Test_DetectLanguage_Py;
begin
  Assert.AreEqual(slPython, DetectLanguage('test.py'));
  Assert.AreEqual(slPython, DetectLanguage('/path/to/file.PY'));
end;

procedure TTestModels.Test_DetectLanguage_Js;
begin
  Assert.AreEqual(slJavaScript, DetectLanguage('app.js'));
  Assert.AreEqual(slJavaScript, DetectLanguage('App.JS'));
end;

procedure TTestModels.Test_DetectLanguage_Ts;
begin
  Assert.AreEqual(slTypeScript, DetectLanguage('main.ts'));
end;

procedure TTestModels.Test_DetectLanguage_Go;
begin
  Assert.AreEqual(slGo, DetectLanguage('server.go'));
end;

procedure TTestModels.Test_DetectLanguage_Unknown;
begin
  Assert.AreEqual(slUnknown, DetectLanguage('readme.txt'));
  Assert.AreEqual(slUnknown, DetectLanguage('data.json'));
  Assert.AreEqual(slUnknown, DetectLanguage('noext'));
end;

procedure TTestModels.Test_SourceLanguageToStr;
begin
  Assert.AreEqual('Python', SourceLanguageToStr(slPython));
  Assert.AreEqual('JavaScript', SourceLanguageToStr(slJavaScript));
  Assert.AreEqual('Unknown', SourceLanguageToStr(slUnknown));
end;

procedure TTestModels.Test_GetLangExt;
begin
  Assert.AreEqual('.py', GetLangExt(slPython));
  Assert.AreEqual('.js', GetLangExt(slJavaScript));
  Assert.AreEqual('.ts', GetLangExt(slTypeScript));
  Assert.AreEqual('.go', GetLangExt(slGo));
  Assert.AreEqual('', GetLangExt(slUnknown));
end;

procedure TTestModels.Test_Contract_Clear;
var
  C: TContract;
begin
  C.ID := 'test-id';
  C.Title := 'Test Title';
  C.Language := slPython;
  SetLength(C.Scenarios, 3);
  
  C.Clear;
  
  Assert.AreEqual('', C.ID);
  Assert.AreEqual('', C.Title);
  Assert.AreEqual(slUnknown, C.Language);
  Assert.IsTrue(Length(C.Scenarios) = 0);
end;

procedure TTestModels.Test_Contract_ToYAML;
var
  C: TContract;
  S: TContractScenario;
  YAML: string;
begin
  C.Clear;
  C.ID := 'CTR-001';
  C.Title := 'Test Module';
  C.Language := slPython;
  C.Purpose := 'Test purpose';
  C.CreatedAt := EncodeDateTime(2026, 2, 20, 10, 30, 0, 0);
  
  S.Clear;
  S.ID := 'S1';
  S.Desc := 'Scenario 1';
  S.ScenType := stNormal;
  S.Input := 'input1';
  S.Expected := 'output1';
  SetLength(C.Scenarios, 1);
  C.Scenarios[0] := S;
  
  YAML := C.ToYAML;
  
  Assert.IsTrue(Pos('Test Module', YAML) > 0);
  Assert.IsTrue(Pos('Python', YAML) > 0);
  Assert.IsTrue(Pos('Scenario 1', YAML) > 0);
  Assert.IsTrue(Pos('S1', YAML) > 0);
end;

procedure TTestModels.Test_TestResults_GetPassCount;
var
  R: TTestResults;
begin
  R.Clear;
  SetLength(R.ScenarioResults, 3);
  R.ScenarioResults[0].Passed := True;
  R.ScenarioResults[1].Passed := False;
  R.ScenarioResults[2].Passed := True;
  
  Assert.AreEqual(2, R.GetPassCount);
end;

procedure TTestModels.Test_TestResults_GetTotalCount;
var
  R: TTestResults;
begin
  R.Clear;
  SetLength(R.ScenarioResults, 5);
  
  Assert.AreEqual(5, R.GetTotalCount);
end;

procedure TTestModels.Test_VerificationReport_GetPassRate;
var
  R: TVerificationReport;
begin
  R.Clear;
  SetLength(R.Scenarios, 4);
  R.Scenarios[0].Status := ssPass;
  R.Scenarios[1].Status := ssPass;
  R.Scenarios[2].Status := ssPass;
  R.Scenarios[3].Status := ssFail;
  
  Assert.AreEqual(75, R.GetPassRate);
end;

procedure TTestModels.Test_AIConfig_GetModelForLevel;
var
  C: TAIConfig;
begin
  C.Clear;
  C.ModelTier1 := 'model-tier1';
  C.ModelTier2 := 'model-tier2';
  C.ModelTier3 := 'model-tier3';
  
  Assert.AreEqual('model-tier1', C.GetModelForLevel(rlTier1));
  Assert.AreEqual('model-tier2', C.GetModelForLevel(rlTier2));
  Assert.AreEqual('model-tier3', C.GetModelForLevel(rlTier3));
end;

procedure TTestModels.Test_VerifyStateToStr;
begin
  Assert.AreEqual('idle', VerifyStateToStr(vsIdle));
  Assert.AreEqual('file_loaded', VerifyStateToStr(vsFileLoaded));
  Assert.AreEqual('analyzing', VerifyStateToStr(vsAnalyzing));
  Assert.AreEqual('passed', VerifyStateToStr(vsPassed));
  Assert.AreEqual('failed', VerifyStateToStr(vsFailed));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestModels);

end.
