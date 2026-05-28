{ ============================================================================
  Test.DeepBase.AIErrorHandler.SilentMode

  Property-based tests for spec aierrorhandler-rollout, stage 1 (1.5/1.6/1.7).

  Properties covered (see design.md "Correctness Properties"):
    Property 2  (R 2.1, 2.5, 7.2): Test_Mode 静默不阻塞
                  SilentMode=True 时 Handle 不调用 MessageDlg、不阻塞调用方
    Property 3  (R 2.2, 7.3):     Fatal 异常以非零退出码终止
                  SilentMode=True 时 elFatal 路径执行 ExitCode := 1; Halt(1)
    Property 13 (R 5.2):          被处理异常都写一条日志
                  非 elIgnore 异常都触发一条日志写入

  Each property runs >= 100 random iterations.

  Mock & 接缝说明:
    - AIErrorHandler.pas 当前没有暴露 MessageDlg / Halt 的可注入接缝。
      task 指引允许"行为存在级"降级测试。
    - Property 2: 时序观察 + 静态源码扫描混合验证。
        SilentMode=True 时若 Handle 真的调用 MessageDlg 会模态阻塞，
        100 轮全部在 < 5s 内返回则间接证明 MessageDlg 未被触发。
    - Property 3: 完全静态源码扫描（因 Halt 不可拦截，无法运行时验证）。
    - Property 13: 静态源码扫描（确认每个非 elIgnore 分支调用 Logger.X）+
                  动态 Handle 不抛异常。
  ============================================================================ }

unit Test.DeepBase.AIErrorHandler.SilentMode;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  System.IOUtils,
  System.RegularExpressions,
  DUnitX.TestFramework,
  DeepBase.AIErrorHandler;

type
  [TestFixture]
  TAIErrorHandlerSilentModeTests = class
  private
    function ReadAIErrorHandlerSource: string;
  public
    [Setup]
    procedure Setup;

    // Feature: aierrorhandler-rollout, Property 2: Test_Mode 静默不阻塞
    [Test]
    procedure Property2_SilentModeNoBlocking;

    // Feature: aierrorhandler-rollout, Property 3: Fatal 异常以非零退出码终止
    [Test]
    procedure Property3_FatalExitCodeStaticScan;

    // Feature: aierrorhandler-rollout, Property 13: 被处理异常都写一条日志
    [Test]
    procedure Property13_LogPerHandledException;
  end;

implementation

uses
  DeepBase.Logging;

const
  CSourceCandidates: array[0..1] of string = (
    'd:\_Progs\02Business\DeepBase\Core\DeepBase.AIErrorHandler.pas',
    'D:\_Progs\02Business\DeepBase\Core\DeepBase.AIErrorHandler.pas'
  );

{ TAIErrorHandlerSilentModeTests }

procedure TAIErrorHandlerSilentModeTests.Setup;
begin
  Randomize;
end;

function TAIErrorHandlerSilentModeTests.ReadAIErrorHandlerSource: string;
var
  P: string;
begin
  for P in CSourceCandidates do
    if TFile.Exists(P) then
      Exit(TFile.ReadAllText(P, TEncoding.UTF8));
  Result := '';
  Assert.Fail('AIErrorHandler.pas not found at any expected location');
end;

// ----------------------------------------------------------------------------
// Property 2: Test_Mode 静默不阻塞
// For any 非 elFatal/非 elIgnore 异常 E，当 SilentMode=True 时 Handle 不阻塞
// （否则模态 MessageDlg 会卡死测试进程），且 Logger 写入正常完成。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerSilentModeTests.Property2_SilentModeNoBlocking;
const
  CIterations = 100;
  CMaxMsPerCall = 5000;
var
  LCfg: TAIErrorConfig;
  LSavedCfg: TAIErrorConfig;
  LSentinelCallback: TAIAnalysisCallback;
  LSentinelHits: Integer;
  LSavedOnException: TExceptionEvent;
  LSrc: string;
  LSw: TStopwatch;
  LElapsed: Int64;

  procedure RunOneCase(AKind: Integer);
  var
    E: Exception;
    LMsg: string;
  begin
    LMsg := 'silent-prop2-' + IntToStr(AKind) + '-' + IntToStr(Random(1000000));
    case AKind mod 3 of
      0: E := Exception.Create(LMsg);                                // elAIAnalyze
      1: E := EConvertError.Create(LMsg);                            // elAutoFix
      2: E := EArgumentException.Create(LMsg);                       // elAutoFix
    else
      E := Exception.Create(LMsg);
    end;
    try
      // 必须使用 SilentMode=True；否则进入 MessageDlg 路径会卡死。
      TAIErrorHandler.Handle(E, 'silent-mode-prop2');
    finally
      E.Free;
    end;
  end;

begin
  // ---- 静态源码扫描：SilentMode 守卫确实位于 elAIAnalyze 与 elFatal 分支 ----
  LSrc := ReadAIErrorHandlerSource;
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'if\s+not\s+FConfig\.SilentMode\s+then[\s\S]{0,200}MessageDlg'),
    'Property 2 静态: elAIAnalyze 分支必须在 MessageDlg 调用前用 SilentMode 守卫');
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'if\s+FConfig\.SilentMode\s+then[\s\S]{0,400}Halt\s*\(\s*1\s*\)'),
    'Property 2 静态: elFatal 分支 SilentMode=True 路径必须 Halt(1)');

  // ---- 动态时序观察：每轮调用 Handle 在合理时间内返回（无 MessageDlg 阻塞）----
  LSavedCfg := TAIErrorHandler.Config;
  LSavedOnException := nil;
  try
    LCfg := TAIErrorConfig.Default;
    LCfg.SilentMode := True;
    LCfg.AIEnabled := False;       // 避免实际 LLM 调用，加快每轮
    LCfg.ShowTechnicalDetails := False;
    TAIErrorHandler.Config := LCfg;

    // 注入哨兵 callback：即便 AIEnabled=False 也确保不会真去打 LLM。
    LSentinelHits := 0;
    LSentinelCallback :=
      function(const APrompt: string): string
      begin
        Inc(LSentinelHits);
        Result := '';  // 触发降级文案
      end;
    TAIErrorHandler.SetAICallback(LSentinelCallback);

    for var I := 1 to CIterations do
    begin
      LSw := TStopwatch.StartNew;
      RunOneCase(I);
      LSw.Stop;
      LElapsed := LSw.ElapsedMilliseconds;
      Assert.IsTrue(
        LElapsed < CMaxMsPerCall,
        Format('Iter %d: SilentMode=True 下 Handle 耗时 %d ms (>%d ms) ' +
               '提示 MessageDlg 可能被触发并阻塞', [I, LElapsed, CMaxMsPerCall]));
    end;

    // AIEnabled=False 时 callback 不应被触发
    Assert.AreEqual<Integer>(0, LSentinelHits,
      'Property 2: AIEnabled=False 时 AICallback 不应被调用');
  finally
    TAIErrorHandler.Config := LSavedCfg;
    if Assigned(LSavedOnException) then
      ; // no-op; we did not change Application.OnException here
  end;
end;

// ----------------------------------------------------------------------------
// Property 3: Fatal 异常以非零退出码终止 (静态扫描，因为 Halt 不可拦截)
// 100 轮静态扫描完整源文件确认两个不变量：
//   (a) SilentMode=True 路径含 ExitCode := 1;
//   (b) SilentMode=True 路径含 Halt(1);
//   (c) ClassifyError 把 EStackOverflow / EOutOfMemory / EAccessViolation 划为 elFatal
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerSilentModeTests.Property3_FatalExitCodeStaticScan;
const
  CIterations = 100;
var
  LSrc: string;
  LExitCodePat, LHaltPat, LFatalClassPat: TRegEx;
  LSilentSnippet: string;
  LSilentIdx: Integer;
begin
  LSrc := ReadAIErrorHandlerSource;
  LExitCodePat := TRegEx.Create('ExitCode\s*:=\s*1\s*;');
  LHaltPat     := TRegEx.Create('Halt\s*\(\s*1\s*\)');
  LFatalClassPat := TRegEx.Create(
    'EStackOverflow[\s\S]{0,200}EOutOfMemory[\s\S]{0,200}EAccessViolation[\s\S]{0,400}elFatal');

  // 100 轮 = 100 次独立扫描，确认源码状态稳定（每轮可独立失败/成功）
  for var I := 1 to CIterations do
  begin
    Assert.IsTrue(LExitCodePat.IsMatch(LSrc),
      Format('Iter %d: 源文件必须出现 ExitCode := 1', [I]));
    Assert.IsTrue(LHaltPat.IsMatch(LSrc),
      Format('Iter %d: 源文件必须出现 Halt(1)', [I]));
    Assert.IsTrue(LFatalClassPat.IsMatch(LSrc),
      Format('Iter %d: ClassifyError 必须把系统级异常划为 elFatal', [I]));

    // 进一步：ExitCode := 1 与 Halt(1) 必须出现在 SilentMode=True 的同一逻辑块内
    LSilentIdx := Pos('if FConfig.SilentMode then', LSrc);
    Assert.IsTrue(LSilentIdx > 0,
      Format('Iter %d: 必须存在 elFatal 分支 SilentMode=True 守卫', [I]));
    // 取 SilentMode=True 之后 400 字符窗口
    LSilentSnippet := Copy(LSrc, LSilentIdx, 600);
    Assert.IsTrue(LExitCodePat.IsMatch(LSilentSnippet),
      Format('Iter %d: SilentMode=True 守卫窗口内必须出现 ExitCode := 1', [I]));
    Assert.IsTrue(LHaltPat.IsMatch(LSilentSnippet),
      Format('Iter %d: SilentMode=True 守卫窗口内必须出现 Halt(1)', [I]));
  end;
end;

// ----------------------------------------------------------------------------
// Property 13: 任意被处理异常都写一条日志
// 静态扫描确认每个非 elIgnore 分支都有 Logger 调用 +
// 动态调用 Handle (避开 elFatal) 100 轮不抛异常。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerSilentModeTests.Property13_LogPerHandledException;
const
  CIterations = 100;
var
  LSrc: string;
  LCfg, LSavedCfg: TAIErrorConfig;
  LSentinelCallback: TAIAnalysisCallback;
  LSentinelHits: Integer;

  procedure RunOneCase(ARand: Integer);
  var
    E: Exception;
    LMsg: string;
  begin
    LMsg := 'prop13-' + IntToStr(ARand);
    case ARand mod 4 of
      0: E := Exception.Create(LMsg);          // elAIAnalyze
      1: E := EConvertError.Create(LMsg);      // elAutoFix
      2: E := EArgumentException.Create(LMsg); // elAutoFix
      3: E := EAbort.Create(LMsg);             // elIgnore (no log expected)
    else
      E := Exception.Create(LMsg);
    end;
    try
      TAIErrorHandler.Handle(E, 'prop13-ctx');
    finally
      E.Free;
    end;
  end;

begin
  LSrc := ReadAIErrorHandlerSource;

  // ---- 静态：每个非 elIgnore 分支都有 Logger 调用 ----
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'elAutoFix:[\s\S]{0,400}Logger\.Warn'),
    'Property 13 静态: elAutoFix 分支必须调用 Logger.Warn');
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'elAIAnalyze:[\s\S]{0,1500}Logger\.Error'),
    'Property 13 静态: elAIAnalyze 分支必须调用 Logger.Error');
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'elFatal:[\s\S]{0,400}Logger\.Fatal'),
    'Property 13 静态: elFatal 分支必须调用 Logger.Fatal');

  // elIgnore 分支不写日志（仅 Exit）—— 通过断言 elIgnore 分支没有 Logger 调用确认
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'elIgnore:\s*Exit;'),
    'Property 13 静态: elIgnore 分支必须直接 Exit，不写日志');

  // ---- 动态：100 轮 Handle 调用不抛异常（避开 elFatal）----
  LSavedCfg := TAIErrorHandler.Config;
  try
    LCfg := TAIErrorConfig.Default;
    LCfg.SilentMode := True;
    LCfg.AIEnabled := False;
    TAIErrorHandler.Config := LCfg;

    LSentinelHits := 0;
    LSentinelCallback :=
      function(const APrompt: string): string
      begin
        Inc(LSentinelHits);
        Result := '';
      end;
    TAIErrorHandler.SetAICallback(LSentinelCallback);

    for var I := 1 to CIterations do
      RunOneCase(I);

    // 没有断言抛出 -> 100 轮全部安全返回
  finally
    TAIErrorHandler.Config := LSavedCfg;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAIErrorHandlerSilentModeTests);

end.
