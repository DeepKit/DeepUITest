unit uModels;

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  TVerifyState = (
    vsIdle,
    vsWelcome,
    vsCodeInput,
    vsFileLoaded,
    vsAnalyzing,
    vsContractReady,
    vsConfirmed,
    vsGeneratingTest,
    vsRunningTest,
    vsFixing,
    vsPassed,
    vsFailed,
    vsOutputting
  );

  TSourceLanguage = (
    slUnknown,
    slPython,
    slJavaScript,
    slTypeScript,
    slGo,
    slJava,
    slCSharp,
    slRuby,
    slPHP,
    slSwift,
    slKotlin,
    slCPP,
    slRust,
    slDart
  );

  TScenarioType = (stNormal, stEdge, stError);

  TScenarioStatus = (ssPass, ssFail, ssSkip);

  TContractScenario = record
    ID: string;
    Desc: string;
    ScenType: TScenarioType;
    Input: string;
    Expected: string;
    Status: TScenarioStatus;
    ResponseMS: Integer;
    Detail: string;
    procedure Clear;
  end;

  TContract = record
    ID: string;
    Title: string;
    Language: TSourceLanguage;
    Purpose: string;
    Scenarios: TArray<TContractScenario>;
    CreatedAt: TDateTime;
    ConfirmedAt: TDateTime;
    IsConfirmed: Boolean;
    procedure Clear;
    function ToYAML: string;
  end;

  TScenarioResult = record
    ID: string;
    Passed: Boolean;
    Detail: string;
  end;

  TTestResults = record
    ScenarioResults: TArray<TScenarioResult>;
    OverallPassed: Boolean;
    RawOutput: string;
    ExecutionMS: Integer;
    procedure Clear;
    function GetPassCount: Integer;
    function GetTotalCount: Integer;
  end;

  TVerificationReport = record
    ReportID: string;
    ProjectNameZH: string;
    SourceFileName: string;
    SourceLang: TSourceLanguage;
    VerifiedAt: TDateTime;
    AIModel: string;
    AuthorizedBy: string;
    SealHash: string;
    Scenarios: TArray<TContractScenario>;
    IsSealed: Boolean;
    procedure Clear;
    function GetPassRate: Integer;
    function GetPassCount: Integer;
    function GetTotalCount: Integer;
  end;

  TAudience = (auGirlfriend, auBoss, auPeer, auSelf);
  TMood = (mdSatisfied, mdProud, mdTired, mdFocused);
  TCardTheme = (ctDark, ctLight, ctNight, ctWarm);

  TSemanticEntry = record
    Icon: string;
    Tag: string;
    Headlines: TArray<string>;
    SubText: string;
  end;

  TCardConfig = record
    ModuleName: string;
    Audience: TAudience;
    Mood: TMood;
    Theme: TCardTheme;
    Headline: string;
    Icon: string;
    Tag: string;
    SubText: string;
    StatPass: string;
    StatMS: string;
    StatCoverage: string;
    GeneratedAt: TDateTime;
    procedure Clear;
  end;

  TSealRecord = record
    ReportID: string;
    SourceFile: string;
    SourceHash: string;
    SealHash: string;
    SealedAt: TDateTime;
    ModelUsed: string;
    RetryCount: Integer;
    ContractFile: string;
    procedure Clear;
  end;

  TAIRetryLevel = (rlTier1, rlTier2, rlTier3);

  TAIConfig = record
    Provider: string;
    APIKey: string;
    BaseURL: string;
    TimeoutSec: Integer;
    ModelTier1: string;
    ModelTier2: string;
    ModelTier3: string;
    procedure Clear;
    function GetModelForLevel(Level: TAIRetryLevel): string;
  end;

const
  SOURCE_LANG_NAMES: array[TSourceLanguage] of string = (
    'Unknown', 'Python', 'JavaScript', 'TypeScript', 'Go', 'Java',
    'CSharp', 'Ruby', 'PHP', 'Swift', 'Kotlin', 'CPP', 'Rust', 'Dart'
  );

  SOURCE_LANG_EXTS: array[TSourceLanguage] of string = (
    '', '.py', '.js', '.ts', '.go', '.java',
    '.cs', '.rb', '.php', '.swift', '.kt', '.cpp', '.rs', '.dart'
  );

  RUN_COMMANDS: array[TSourceLanguage] of string = (
    '',
    'python "%s"',
    'node "%s"',
    'ts-node "%s"',
    'go run "%s"',
    'java "%s"',
    'dotnet script "%s"',
    'ruby "%s"',
    'php "%s"',
    'swift "%s"',
    'kotlin "%s"',
    'g++ "%s" -o temp && ./temp',
    'rustc "%s" -o temp && ./temp',
    'dart "%s"'
  );

function StrToSourceLanguage(const S: string): TSourceLanguage;
function SourceLanguageToStr(L: TSourceLanguage): string;
function GetLangExt(L: TSourceLanguage): string;
function DetectLanguage(const FilePath: string): TSourceLanguage;
function VerifyStateToStr(S: TVerifyState): string;

implementation

function StrToSourceLanguage(const S: string): TSourceLanguage;
var
  U: string;
begin
  U := UpperCase(S);
  if U = 'PYTHON' then Result := slPython
  else if U = 'JAVASCRIPT' then Result := slJavaScript
  else if U = 'TYPESCRIPT' then Result := slTypeScript
  else if U = 'GO' then Result := slGo
  else if U = 'JAVA' then Result := slJava
  else if U = 'CSHARP' then Result := slCSharp
  else if U = 'RUBY' then Result := slRuby
  else if U = 'PHP' then Result := slPHP
  else if U = 'SWIFT' then Result := slSwift
  else if U = 'KOTLIN' then Result := slKotlin
  else if U = 'CPP' then Result := slCPP
  else if U = 'RUST' then Result := slRust
  else if U = 'DART' then Result := slDart
  else Result := slUnknown;
end;

function SourceLanguageToStr(L: TSourceLanguage): string;
begin
  Result := SOURCE_LANG_NAMES[L];
end;

function GetLangExt(L: TSourceLanguage): string;
begin
  Result := SOURCE_LANG_EXTS[L];
end;

function DetectLanguage(const FilePath: string): TSourceLanguage;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FilePath));
  if Ext = '.py' then Result := slPython
  else if Ext = '.js' then Result := slJavaScript
  else if Ext = '.ts' then Result := slTypeScript
  else if Ext = '.go' then Result := slGo
  else if Ext = '.java' then Result := slJava
  else if Ext = '.cs' then Result := slCSharp
  else if Ext = '.rb' then Result := slRuby
  else if Ext = '.php' then Result := slPHP
  else if Ext = '.swift' then Result := slSwift
  else if Ext = '.kt' then Result := slKotlin
  else if Ext = '.cpp' then Result := slCPP
  else if Ext = '.rs' then Result := slRust
  else if Ext = '.dart' then Result := slDart
  else Result := slUnknown;
end;

function VerifyStateToStr(S: TVerifyState): string;
begin
  case S of
    vsIdle: Result := 'idle';
    vsWelcome: Result := 'welcome';
    vsCodeInput: Result := 'code_input';
    vsFileLoaded: Result := 'file_loaded';
    vsAnalyzing: Result := 'analyzing';
    vsContractReady: Result := 'contract_ready';
    vsConfirmed: Result := 'confirmed';
    vsGeneratingTest: Result := 'generating_test';
    vsRunningTest: Result := 'running_test';
    vsFixing: Result := 'fixing';
    vsPassed: Result := 'passed';
    vsFailed: Result := 'failed';
    vsOutputting: Result := 'outputting';
  else
    Result := 'unknown';
  end;
end;

{ TContractScenario }

procedure TContractScenario.Clear;
begin
  ID := '';
  Desc := '';
  ScenType := stNormal;
  Input := '';
  Expected := '';
  Status := ssSkip;
  ResponseMS := 0;
  Detail := '';
end;

{ TContract }

procedure TContract.Clear;
begin
  ID := '';
  Title := '';
  Language := slUnknown;
  Purpose := '';
  SetLength(Scenarios, 0);
  CreatedAt := 0;
  ConfirmedAt := 0;
  IsConfirmed := False;
end;

function TContract.ToYAML: string;
var
  SB: TStringBuilder;
  S: TContractScenario;
  TypeStr: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# DeepDevLite Contract File');
    SB.AppendLine('# Generated: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', CreatedAt));
    SB.AppendLine('---');
    SB.AppendLine('contract:');
    SB.AppendLine(Format('  title: "%s"', [Title]));
    SB.AppendLine(Format('  language: "%s"', [SourceLanguageToStr(Language)]));
    SB.AppendLine(Format('  purpose: "%s"', [Purpose]));
    SB.AppendLine('  scenarios:');
    
    for S in Scenarios do
    begin
      case S.ScenType of
        stNormal: TypeStr := 'normal';
        stEdge: TypeStr := 'edge';
        stError: TypeStr := 'error';
      else
        TypeStr := 'normal';
      end;
      
      SB.AppendLine(Format('    - id: %s', [S.ID]));
      SB.AppendLine(Format('      desc: "%s"', [S.Desc]));
      SB.AppendLine(Format('      type: %s', [TypeStr]));
      SB.AppendLine(Format('      input: "%s"', [S.Input]));
      SB.AppendLine(Format('      expected: "%s"', [S.Expected]));
    end;
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TTestResults }

procedure TTestResults.Clear;
begin
  SetLength(ScenarioResults, 0);
  OverallPassed := False;
  RawOutput := '';
  ExecutionMS := 0;
end;

function TTestResults.GetPassCount: Integer;
var
  R: TScenarioResult;
begin
  Result := 0;
  for R in ScenarioResults do
    if R.Passed then
      Inc(Result);
end;

function TTestResults.GetTotalCount: Integer;
begin
  Result := Length(ScenarioResults);
end;

{ TVerificationReport }

procedure TVerificationReport.Clear;
begin
  ReportID := '';
  ProjectNameZH := '';
  SourceFileName := '';
  SourceLang := slUnknown;
  VerifiedAt := 0;
  AIModel := '';
  AuthorizedBy := '';
  SealHash := '';
  SetLength(Scenarios, 0);
  IsSealed := False;
end;

function TVerificationReport.GetPassCount: Integer;
var
  S: TContractScenario;
begin
  Result := 0;
  for S in Scenarios do
    if S.Status = ssPass then
      Inc(Result);
end;

function TVerificationReport.GetTotalCount: Integer;
begin
  Result := Length(Scenarios);
end;

function TVerificationReport.GetPassRate: Integer;
begin
  if GetTotalCount = 0 then
    Result := 0
  else
    Result := Round(GetPassCount / GetTotalCount * 100);
end;

{ TCardConfig }

procedure TCardConfig.Clear;
begin
  ModuleName := '';
  Audience := auSelf;
  Mood := mdSatisfied;
  Theme := ctDark;
  Headline := '';
  Icon := '';
  Tag := '';
  SubText := '';
  StatPass := '0/0';
  StatMS := '0ms';
  StatCoverage := '0%';
  GeneratedAt := 0;
end;

{ TSealRecord }

procedure TSealRecord.Clear;
begin
  ReportID := '';
  SourceFile := '';
  SourceHash := '';
  SealHash := '';
  SealedAt := 0;
  ModelUsed := '';
  RetryCount := 0;
  ContractFile := '';
end;

{ TAIConfig }

procedure TAIConfig.Clear;
begin
  Provider := 'anthropic';
  APIKey := '';
  BaseURL := 'http://localhost:8000';
  TimeoutSec := 120;
  ModelTier1 := 'claude-sonnet-4-6';
  ModelTier2 := 'claude-sonnet-4-6';
  ModelTier3 := 'claude-sonnet-4-6';
end;

function TAIConfig.GetModelForLevel(Level: TAIRetryLevel): string;
begin
  case Level of
    rlTier1: Result := ModelTier1;
    rlTier2: Result := ModelTier2;
    rlTier3: Result := ModelTier3;
  else
    Result := ModelTier1;
  end;
end;

end.
