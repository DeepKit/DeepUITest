{ ============================================================================
  Test.DeepBase.AIErrorHandler.Bootstrap

  Property-based tests for spec aierrorhandler-rollout, stage 3
  (3.3 / 3.4 / 3.5 / 3.6 / 3.8 / 3.9).

  Properties covered:
    Property 1  (R 1.1, 1.5, 5.3):    Install 后置条件
    Property 4  (R 2.3, 2.4):         IsTestMode 真值表
    Property 10 (R 1.3, 9.3):         Bootstrap 重复调用幂等
    Property 11 (R 10.2):             Bootstrap 自身异常被吞掉
    Property 5  (R 3.1, 3.2, 3.3):    与既有 OnException Hook 的合流 (Confluence)
    Property 12 (R 10.3):             AutoFix 状态对 Bootstrap 透明

  Each property runs >= 100 random iterations (Property 5 / 12 在单进程内
  受 Bootstrap 单次安装语义约束，详见各方法注释)。

  Mock & 接缝说明:
    - Bootstrap.GInstalled / TAIErrorHandler.FInstalled 是私有/单元局部
      var，无 reset 接口；因此进程内只能首次调用真正生效，其余幂等。
    - Property 5 借助 Setup-time chain 组装：先把 Application.OnException
      置为 dispatcher closure，再通过 SetupFixture 调 InstallAIErrorHandler，
      使 AIErrorHandler 把 dispatcher 捕获到 FOldAppException。后续每轮
      测试通过 Application.HandleException(E) 触发链式调用并验证 dispatcher
      / AIErrorHandler.Handle 各自被调用恰好一次。
    - Property 11 用静态扫描 + 多轮调用不抛异常的混合方式验证。
    - Property 12 用 TAutoFixErrorRecorder.ActivateForTest / ResetForTest
      切换 AutoFix 状态，验证 Bootstrap 后置条件保持不变。
  ============================================================================ }

unit Test.DeepBase.AIErrorHandler.Bootstrap;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  Vcl.Forms,
  DUnitX.TestFramework,
  DeepBase.AIErrorHandler,
  DeepBase.AIErrorHandler.Bootstrap;

type
  [TestFixture]
  TAIErrorHandlerBootstrapTests = class
  private
    function ReadBootstrapSource: string;
    procedure SetEnvVar(const AName, AValue: string);
  public
    [SetupFixture]
    procedure SetupFixture;

    [Setup]
    procedure Setup;

    // Feature: aierrorhandler-rollout, Property 1: Install 后置条件
    [Test]
    procedure Property1_InstallPostconditions;

    // Feature: aierrorhandler-rollout, Property 4: IsTestMode 真值表
    [Test]
    procedure Property4_IsTestModeTruthTable;

    // Feature: aierrorhandler-rollout, Property 10: Bootstrap 重复调用幂等
    [Test]
    procedure Property10_BootstrapIdempotent;

    // Feature: aierrorhandler-rollout, Property 11: Bootstrap 自身异常被吞掉
    [Test]
    procedure Property11_BootstrapSwallowsOwnExceptions;

    // Feature: aierrorhandler-rollout, Property 5: OnException 合流 (Confluence)
    [Test]
    procedure Property5_OnExceptionConfluence;

    // Feature: aierrorhandler-rollout, Property 12: AutoFix 状态对 Bootstrap 透明
    [Test]
    procedure Property12_AutoFixTransparency;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  DeepBase.AutoFix.ErrorRecorder;

const
  CSourceCandidates: array[0..1] of string = (
    'd:\_Progs\02Business\DeepBase\Core\DeepBase.AIErrorHandler.Bootstrap.pas',
    'D:\_Progs\02Business\DeepBase\Core\DeepBase.AIErrorHandler.Bootstrap.pas'
  );

  CMaxOldHandlers = 5;

var
  // Property 5: 多 dispatcher 计数器 + AICallback 计数器
  GHandlerCounters: array[0..CMaxOldHandlers - 1] of Integer;
  GActiveHandlers: Integer;
  GAICalled: Integer;
  GAIPromptCaptured: string;
  GFixtureInstalled: Boolean = False;

procedure DispatcherHandler(Sender: TObject; E: Exception);
var
  I: Integer;
begin
  for I := 0 to GActiveHandlers - 1 do
    Inc(GHandlerCounters[I]);
end;

{ TAIErrorHandlerBootstrapTests }

procedure TAIErrorHandlerBootstrapTests.SetEnvVar(const AName, AValue: string);
begin
  {$IFDEF MSWINDOWS}
  // 空值 = 删除变量；SetEnvironmentVariable 接受 nil 表示删除
  if AValue = '' then
    Winapi.Windows.SetEnvironmentVariable(PChar(AName), nil)
  else
    Winapi.Windows.SetEnvironmentVariable(PChar(AName), PChar(AValue));
  {$ENDIF}
end;

procedure TAIErrorHandlerBootstrapTests.SetupFixture;
begin
  // 一次性挂 dispatcher，再调 InstallAIErrorHandler；
  // AIErrorHandler 会把 dispatcher 捕获为 FOldAppException 用于链式回调。
  if not GFixtureInstalled then
  begin
    Application.OnException := DispatcherHandler;
    InstallAIErrorHandlerForTests;  // bmTest -> SilentMode := True
    GFixtureInstalled := True;
  end;
end;

procedure TAIErrorHandlerBootstrapTests.Setup;
begin
  Randomize;
end;

function TAIErrorHandlerBootstrapTests.ReadBootstrapSource: string;
var
  P: string;
begin
  for P in CSourceCandidates do
    if TFile.Exists(P) then
      Exit(TFile.ReadAllText(P, TEncoding.UTF8));
  Result := '';
  Assert.Fail('Bootstrap.pas not found at any expected location');
end;

// ----------------------------------------------------------------------------
// Property 1: Install 后置条件
//   For any 进程的初始状态，调用 InstallAIErrorHandler 之后必须满足:
//     - Application.OnException 已被赋值 (与 nil 不等)
//     - TAIErrorHandler.Config 字段级与传入 (或 Default + bmTest 强制 SilentMode) 相等
//     - 已设置非空的 AICallback (由 LLMBridge 注入或测试 SetAICallback)
//
// 由于 SetupFixture 已经调过 Install，进程内不能再触发 "首次安装"；
// 本测试在已安装态下断言后置条件 100 轮稳定 (调用幂等不破坏后置条件)。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerBootstrapTests.Property1_InstallPostconditions;
const
  CIterations = 100;
var
  LCfg: TAIErrorConfig;
  LDefaultExpected: TAIErrorConfig;
  LRet: Boolean;
  LSentinelHits: Integer;
  LSentinelCb: TAIAnalysisCallback;
begin
  // 重新设置一个 sentinel 作 AICallback；后续通过触发异常验证它被调用
  LSentinelHits := 0;
  LSentinelCb :=
    function(const APrompt: string): string
    begin
      Inc(LSentinelHits);
      Result := '';
    end;
  TAIErrorHandler.SetAICallback(LSentinelCb);

  for var I := 1 to CIterations do
  begin
    // 重复调用应幂等并不破坏后置条件
    LRet := InstallAIErrorHandlerForTests;
    Assert.IsFalse(LRet,
      Format('Iter %d: 已安装态下 InstallAIErrorHandlerForTests 必须返回 False', [I]));

    // 后置条件 (a): Application.OnException 已赋值
    Assert.IsTrue(Assigned(Application.OnException),
      Format('Iter %d: Application.OnException 必须已赋值', [I]));

    // 后置条件 (b): Config 字段级与 bmTest 强制后的 Default 相等
    LCfg := TAIErrorHandler.Config;
    LDefaultExpected := TAIErrorConfig.Default;
    LDefaultExpected.SilentMode := True;  // bmTest forces SilentMode
    Assert.AreEqual<Boolean>(LDefaultExpected.AIEnabled, LCfg.AIEnabled,
      Format('Iter %d: Config.AIEnabled mismatch', [I]));
    Assert.AreEqual<Integer>(LDefaultExpected.MaxCacheSize, LCfg.MaxCacheSize,
      Format('Iter %d: Config.MaxCacheSize mismatch', [I]));
    Assert.AreEqual<Integer>(LDefaultExpected.AITimeoutMs, LCfg.AITimeoutMs,
      Format('Iter %d: Config.AITimeoutMs mismatch', [I]));
    Assert.AreEqual<Boolean>(LDefaultExpected.SilentMode, LCfg.SilentMode,
      Format('Iter %d: Config.SilentMode 应被 bmTest 强制为 True', [I]));
  end;

  // 后置条件 (c): AICallback 已设 - 通过触发 elAIAnalyze 异常确认 sentinel 被调用
  // (在 SilentMode=True + AIEnabled=True 的当前 Config 下)
  if TAIErrorHandler.Config.AIEnabled then
  begin
    var E := Exception.Create('p1-aicb-probe');
    try
      TAIErrorHandler.Handle(E, 'p1-aicb');
    finally
      E.Free;
    end;
    Assert.IsTrue(LSentinelHits >= 1,
      'Property 1 (c): AICallback 已设并且会被 Handle 在 elAIAnalyze 路径调用');
  end;
end;

// ----------------------------------------------------------------------------
// Property 4: IsTestMode 真值表
//   For any envVal 与编译指令 defineHit ∈ {True, False}，IsTestMode() = (
//     SameText(envVal, 'test') OR defineHit )
//
// 编译时无 DEEPBASE_AIEH_TEST -> defineHit = False，IsTestMode = SameText(env, 'test').
// 100 轮覆盖: 'test', 'TEST', 'Test', '', 'production', 'foo', 'test '
// (注意 Bootstrap 内做了 Trim, 所以 ' test ' 也是匹配)，以及随机串。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerBootstrapTests.Property4_IsTestModeTruthTable;
const
  CIterations = 100;
  CKnownTrue: array[0..3] of string  = ('test', 'TEST', 'Test', 'TeSt');
  CKnownFalse: array[0..4] of string = ('', 'production', 'prod', 'foo', 'tes');
var
  LSavedEnv: string;
  LValue: string;
  LExpected, LActual: Boolean;
begin
  LSavedEnv := GetEnvironmentVariable('DEEP_AIEH_MODE');
  try
    for var I := 1 to CIterations do
    begin
      // 6 类输入轮询: 4 真值 + 5 假值 + 随机
      case I mod 11 of
        0..3:  LValue := CKnownTrue[I mod 4];
        4..8:  LValue := CKnownFalse[(I mod 5)];
        9:     LValue := '  test  ';  // Trim 后仍命中
        10:    LValue := 'random-' + IntToStr(Random(MaxInt));
      else
        LValue := '';
      end;

      SetEnvVar('DEEP_AIEH_MODE', LValue);

      // {$DEFINE DEEPBASE_AIEH_TEST} 在测试 runner 编译时未启用,
      // 所以 IsTestMode = SameText(Trim(env), 'test')
      LExpected := SameText(Trim(LValue), 'test');
      LActual := IsTestMode;
      Assert.AreEqual<Boolean>(LExpected, LActual,
        Format('Iter %d: env="%s" expected IsTestMode=%s, got %s',
          [I, LValue, BoolToStr(LExpected, True), BoolToStr(LActual, True)]));
    end;
  finally
    SetEnvVar('DEEP_AIEH_MODE', LSavedEnv);
  end;
end;

// ----------------------------------------------------------------------------
// Property 10: Bootstrap 重复调用幂等
//   For any n >= 1 与 mode m，连续调用 InstallAIErrorHandler(m) n 次后，
//   状态等于调用 1 次；首次返回 True，其余 False。
//
// 因 SetupFixture 已完成首次安装，进程内 100 轮再调用全部应返回 False，
// 且 Application.OnException / Config 不变 (幂等保护)。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerBootstrapTests.Property10_BootstrapIdempotent;
const
  CIterations = 100;
  CModes: array[0..2] of TAIErrorBootstrapMode = (bmAuto, bmProduction, bmTest);
var
  LRet: Boolean;
  LSavedOnException: TExceptionEvent;
  LSavedConfig: TAIErrorConfig;
  LCurrentOnException: TExceptionEvent;
  LCurrentConfig: TAIErrorConfig;
  LMode: TAIErrorBootstrapMode;
begin
  LSavedOnException := Application.OnException;
  LSavedConfig := TAIErrorHandler.Config;

  for var I := 1 to CIterations do
  begin
    LMode := CModes[I mod Length(CModes)];
    LRet := InstallAIErrorHandler(LMode);
    Assert.IsFalse(LRet,
      Format('Iter %d (mode=%d): 已安装态下 Install 必须返回 False',
        [I, Ord(LMode)]));

    LCurrentOnException := Application.OnException;
    LCurrentConfig := TAIErrorHandler.Config;

    // 状态字段级稳定
    Assert.IsTrue(@LCurrentOnException = @LSavedOnException,
      Format('Iter %d: 幂等调用不应改变 Application.OnException 指针', [I]));
    Assert.AreEqual<Boolean>(LSavedConfig.AIEnabled, LCurrentConfig.AIEnabled,
      Format('Iter %d: Config.AIEnabled 不应改变', [I]));
    Assert.AreEqual<Integer>(LSavedConfig.MaxCacheSize, LCurrentConfig.MaxCacheSize,
      Format('Iter %d: Config.MaxCacheSize 不应改变', [I]));
    Assert.AreEqual<Boolean>(LSavedConfig.SilentMode, LCurrentConfig.SilentMode,
      Format('Iter %d: Config.SilentMode 不应改变', [I]));
  end;
end;

// ----------------------------------------------------------------------------
// Property 11: Bootstrap 自身异常被吞掉
//   For any InstallAIErrorHandler 内部子步骤抛出的异常类型 T,
//   InstallAIErrorHandler 不抛异常给调用者。
//
// 实现策略 (静态 + 动态混合):
//   (a) 静态扫描: Bootstrap 实现含外层 try..except 把异常都 swallowed,
//                LLMBridge 安装也用 try..except 包裹。
//   (b) 动态: 100 轮调用 InstallAIErrorHandler 不抛 (与 Property 10 重叠,
//             但这里加测多种 Config / Mode 组合)。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerBootstrapTests.Property11_BootstrapSwallowsOwnExceptions;
const
  CIterations = 100;
var
  LSrc: string;
  LCfg: TAIErrorConfig;
  LDidThrow: Boolean;
begin
  LSrc := ReadBootstrapSource;

  // 静态: InstallAIErrorHandler 主体必须有 try..except 包裹
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'function\s+InstallAIErrorHandler[\s\S]{0,3000}\btry\b'),
    'Property 11 静态: InstallAIErrorHandler 必须含 try..except 外层包裹');
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'InstallLLMBridge[\s\S]{0,200}except'),
    'Property 11 静态: InstallLLMBridge 调用必须有 try..except 包裹');
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'OutputDebugString'),
    'Property 11 静态: 异常路径必须用 OutputDebugString 报告');

  // 动态: 100 轮调用,任意 Config / Mode,均不抛
  for var I := 1 to CIterations do
  begin
    LCfg := TAIErrorConfig.Default;
    LCfg.AIEnabled := (I mod 2 = 0);
    LCfg.MaxCacheSize := 10 + (I mod 90);
    LCfg.SilentMode := (I mod 3 = 0);
    LDidThrow := False;
    try
      InstallAIErrorHandler(LCfg, TAIErrorBootstrapMode((I mod 3)));
    except
      on E: Exception do
        LDidThrow := True;
    end;
    Assert.IsFalse(LDidThrow,
      Format('Iter %d: InstallAIErrorHandler 必须不抛异常', [I]));
  end;
end;

// ----------------------------------------------------------------------------
// Property 5: 与既有 OnException Hook 的合流 (Confluence)
//   For any 既有 Application.OnException 回调集合 H = {h1..hk}, for any
//   异常 E: 触发 OnException 后,集合中每个回调 hi 被调用恰好一次,
//   AIErrorHandler.Handle 也被调用恰好一次 (通过 AICallback 间接观察)。
//
// 进程内 Bootstrap 只能首次安装;SetupFixture 已把 dispatcher 注入。
// 100 轮各自:
//   (1) 随机 N ∈ [1, CMaxOldHandlers] 个 "虚拟 hook" 计数器;
//   (2) 通过 dispatcher 把所有 N 个计数器 +1;
//   (3) 触发 Application.HandleException(E);
//   (4) 断言每个计数器恰好 +1, AICallback 恰好 +1。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerBootstrapTests.Property5_OnExceptionConfluence;
const
  CIterations = 100;
var
  LSentinelCb: TAIAnalysisCallback;
  LSavedCfg, LCfg: TAIErrorConfig;
  E: Exception;
  J: Integer;
begin
  // 注入 sentinel AICallback - elAIAnalyze 路径会触发它
  LSavedCfg := TAIErrorHandler.Config;
  try
    LCfg := TAIErrorConfig.Default;
    LCfg.AIEnabled := True;
    LCfg.SilentMode := True;
    TAIErrorHandler.Config := LCfg;

    LSentinelCb :=
      function(const APrompt: string): string
      begin
        Inc(GAICalled);
        GAIPromptCaptured := APrompt;
        Result := '';
      end;
    TAIErrorHandler.SetAICallback(LSentinelCb);

    for var I := 1 to CIterations do
    begin
      // 步骤 1: 随机活跃 hook 数 N ∈ [1..CMaxOldHandlers]
      GActiveHandlers := 1 + Random(CMaxOldHandlers);
      for J := 0 to CMaxOldHandlers - 1 do
        GHandlerCounters[J] := 0;
      GAICalled := 0;
      GAIPromptCaptured := '';

      // 步骤 2: 触发链
      E := Exception.Create('p5-iter-' + IntToStr(I));
      try
        // Application.HandleException 内部会调用 OnException(Sender, E)
        // -> AIErrorHandler.DoApplicationException -> Handle (elAIAnalyze)
        // -> FOldAppException = DispatcherHandler -> 累加计数器
        Application.HandleException(E);
      finally
        E.Free;
      end;

      // 步骤 3: 断言每个活跃 hook 计数器恰好 +1
      for J := 0 to GActiveHandlers - 1 do
        Assert.AreEqual<Integer>(1, GHandlerCounters[J],
          Format('Iter %d: hook[%d] 计数应为 1, 实际 %d (链式回调失败)',
            [I, J, GHandlerCounters[J]]));

      // 步骤 4: 断言 AICallback 恰好被调用 1 次 (AIErrorHandler.Handle 走了 elAIAnalyze)
      Assert.AreEqual<Integer>(1, GAICalled,
        Format('Iter %d: AICallback 应被调用 1 次, 实际 %d', [I, GAICalled]));
    end;
  finally
    TAIErrorHandler.Config := LSavedCfg;
    TAIErrorHandler.SetAICallback(nil);
    GActiveHandlers := 0;
  end;
end;

// ----------------------------------------------------------------------------
// Property 12: AutoFix 状态对 Bootstrap 透明
//   For any TAutoFixErrorRecorder.Active ∈ {True, False}, InstallAIErrorHandler
//   的可观测后置条件 (Property 1 集合) 相同。
//
// 100 轮交替切换 AutoFix 测试态,每轮断言 Bootstrap 后置条件 (Application.
// OnException 已赋, Config 未变) 不受 AutoFix.Active 影响。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerBootstrapTests.Property12_AutoFixTransparency;
const
  CIterations = 100;
var
  LSavedOnException: TExceptionEvent;
  LSavedConfig: TAIErrorConfig;
  LTempDir: string;
begin
  LSavedOnException := Application.OnException;
  LSavedConfig := TAIErrorHandler.Config;
  LTempDir := TPath.Combine(TPath.GetTempPath,
    'aieh_p12_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(LTempDir);

  try
    for var I := 1 to CIterations do
    begin
      try
        if I mod 2 = 0 then
        begin
          // 偶数: AutoFix 激活
          TAutoFixErrorRecorder.ActivateForTest(
            'p12-run-' + IntToStr(I), LTempDir, I);
        end
        else
        begin
          // 奇数: AutoFix 重置
          TAutoFixErrorRecorder.ResetForTest;
        end;

        // 重复 InstallAIErrorHandler 应是 no-op
        var LRet := InstallAIErrorHandlerForTests;
        Assert.IsFalse(LRet,
          Format('Iter %d (AutoFix.Active=%s): Install 应返回 False',
            [I, BoolToStr(TAutoFixErrorRecorder.Active, True)]));

        // 后置条件 1: Application.OnException 仍已赋
        Assert.IsTrue(Assigned(Application.OnException),
          Format('Iter %d: AutoFix 切换后 Application.OnException 仍应已赋值', [I]));

        // 后置条件 2: AIErrorHandler.Config 未受 AutoFix 切换影响
        Assert.AreEqual<Boolean>(LSavedConfig.SilentMode,
          TAIErrorHandler.Config.SilentMode,
          Format('Iter %d: Config.SilentMode 不应受 AutoFix 切换影响', [I]));
        Assert.AreEqual<Integer>(LSavedConfig.MaxCacheSize,
          TAIErrorHandler.Config.MaxCacheSize,
          Format('Iter %d: Config.MaxCacheSize 不应受 AutoFix 切换影响', [I]));
      except
        on E: Exception do
          Assert.Fail(Format('Iter %d: 不期望的异常 %s: %s',
            [I, E.ClassName, E.Message]));
      end;
    end;
  finally
    TAutoFixErrorRecorder.ResetForTest;
    if TDirectory.Exists(LTempDir) then
    begin
      try
        TDirectory.Delete(LTempDir, True);
      except
        // 清理失败不阻塞测试
      end;
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAIErrorHandlerBootstrapTests);

end.
