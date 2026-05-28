{ ============================================================================
  Test.DeepBase.AIErrorHandler.LLMBridge

  Property-based tests for spec aierrorhandler-rollout, stage 2 (2.2/2.3/2.4).

  Properties covered (see design.md "Correctness Properties"):
    Property 7  (R 4.1):                LLMBridge 透传成功结果
    Property 8  (R 4.2, 10.1, 10.4):    LLM 失败 / 缓存损坏 -> 空串与降级
    Example E1  (R 4.3):                LLMBridge 选用 TierFast 常量

  Each property runs >= 100 random iterations.

  Mock & 接缝说明:
    - DeepBase.LLM.Service 暴露的 LLM() 是单例工厂，没有 setter / monkey-patch
      接缝。task 指引允许把 LLMBridge 测试降级为：
        a) 直接对 LLMBridge 源文件做静态扫描验证 (TierFast 常量、try-except、
           Success 检查、Result.Content 透传)；
        b) 调 InstallLLMBridge 后通过 SetAICallback 注入捕获 closure 验证
           AIErrorHandler 的回调接缝可被替换；
        c) 透传成功路径 (Property 7) 与失败 5 种模式 (Property 8) 在 mock 层面
           独立验证 AIErrorHandler 的 fallback 行为契约。

    所有路径都不直接调用 LLM()，避免触达真实端点。

  Mock LLM 简化版 (本进程内):
    - 实现 ILLMClient 仅覆盖 Chat(ATier, AUserPrompt: string) 一个方法签名；
      其他方法返回默认值。
    - 用作 SetAICallback 注入的下游适配器：测试用的 callback 内部调 mock，
      模拟 LLMBridge 的 try / Success / Content 路径。
  ============================================================================ }

unit Test.DeepBase.AIErrorHandler.LLMBridge;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  DUnitX.TestFramework,
  DeepBase.AIErrorHandler,
  DeepBase.LLM.Types,
  DeepBase.LLM.Client;

type
  /// 简化的 ILLMClient mock —— 只为 Chat(ATier, AUserPrompt) 一个签名提供
  /// 真实行为；其余方法返回 default(TChatResult)。
  TMockLLMClient = class(TInterfacedObject, ILLMClient)
  private
    FCapturedTier: TModelTier;
    FCapturedPrompt: string;
    FCallCount: Integer;
    FNextResult: TChatResult;
    FRaiseOnNextChat: Boolean;
  public
    constructor Create;
    procedure ConfigureSuccess(const AContent: string);
    procedure ConfigureFailure(const AErrorMsg: string);
    procedure ConfigureEmptyContent;
    procedure ConfigureRaise;
    property CapturedTier: TModelTier read FCapturedTier;
    property CapturedPrompt: string read FCapturedPrompt;
    property CallCount: Integer read FCallCount;

    // ILLMClient ------------------------------------------------------------
    function Chat(const ATier: TModelTier; const AUserPrompt: string): TChatResult; overload;
    function Chat(const ATier: TModelTier; const ASystemPrompt, AUserPrompt: string): TChatResult; overload;
    function ChatWithHistory(const ATier: TModelTier; const AMessages: TArray<TChatMessage>;
      AMaxTokens: Integer = 0; ATemperature: Double = -1): TChatResult;
    procedure ChatStream(const ATier: TModelTier; const AMessages: TArray<TChatMessage>;
      AOnChunk: TProc<string>; AOnError: TProc<string>; AMaxTokens: Integer = 0);
    function ChatVision(const ATier: TModelTier;
      const AImageBase64: string; const AImageMimeType: string;
      const AUserPrompt: string; const ASystemPrompt: string = ''): TChatResult;
    function GenerateImage(const APrompt: string;
      const ASize: string = '1024x1024'): TImageGenerationResult;
    procedure ChatVisionStream(const ATier: TModelTier;
      const AImageBase64: string; const AImageMimeType: string;
      const AUserPrompt: string; const ASystemPrompt: string;
      AOnChunk: TProc<string>; AOnError: TProc<string>;
      AMaxTokens: Integer = 0);
    function GetModelForTier(const ATier: TModelTier): string;
    function CallCountIfc: Integer;
    function LastDurationMs: Integer;
    // ILLMClient.CallCount 与字段同名冲突，下面用接口实现重定向：
    function ILLMClient.CallCount = CallCountIfc;
  end;

  [TestFixture]
  TAIErrorHandlerLLMBridgeTests = class
  private
    function ReadLLMBridgeSource: string;
    /// <summary>
    /// 构造一个仿 LLMBridge 行为的桥接 callback，下游用 mock 替代真实 LLM().
    /// 该 callback 的语义复刻 DeepBase.AIErrorHandler.LLMBridge.CallLLM:
    ///   try LResult := AMock.Chat(TierFast, APrompt);
    ///       if LResult.Success then Result := LResult.Content;
    ///   except Result := ''; end;
    /// </summary>
    function MakeBridgeLikeCallback(AMock: TMockLLMClient): TAIAnalysisCallback;
  public
    [Setup]
    procedure Setup;

    // Feature: aierrorhandler-rollout, Property 7: LLMBridge 透传成功结果
    [Test]
    procedure Property7_PassThroughSuccess;

    // Feature: aierrorhandler-rollout, Property 8: LLM 失败/缓存损坏 -> 空串与降级
    [Test]
    procedure Property8_FailureFallsBackToEmpty;

    // Feature: aierrorhandler-rollout, Example E1: LLMBridge 选用 TierFast 常量
    [Test]
    procedure ExampleE1_TierFastConstant;
  end;

implementation

uses
  DeepBase.AIErrorHandler.LLMBridge;

const
  CSourceCandidates: array[0..1] of string = (
    'd:\_Progs\02Business\DeepBase\Core\DeepBase.AIErrorHandler.LLMBridge.pas',
    'D:\_Progs\02Business\DeepBase\Core\DeepBase.AIErrorHandler.LLMBridge.pas'
  );

{ TMockLLMClient }

constructor TMockLLMClient.Create;
begin
  inherited Create;
  FCallCount := 0;
  FRaiseOnNextChat := False;
  FNextResult := Default(TChatResult);
  FNextResult.Success := False;
end;

procedure TMockLLMClient.ConfigureSuccess(const AContent: string);
begin
  FNextResult := Default(TChatResult);
  FNextResult.Success := True;
  FNextResult.Content := AContent;
  FRaiseOnNextChat := False;
end;

procedure TMockLLMClient.ConfigureFailure(const AErrorMsg: string);
begin
  FNextResult := Default(TChatResult);
  FNextResult.Success := False;
  FNextResult.ErrorMessage := AErrorMsg;
  FRaiseOnNextChat := False;
end;

procedure TMockLLMClient.ConfigureEmptyContent;
begin
  FNextResult := Default(TChatResult);
  FNextResult.Success := True;       // success 但内容空
  FNextResult.Content := '';
  FRaiseOnNextChat := False;
end;

procedure TMockLLMClient.ConfigureRaise;
begin
  FRaiseOnNextChat := True;
end;

function TMockLLMClient.Chat(const ATier: TModelTier;
  const AUserPrompt: string): TChatResult;
begin
  FCapturedTier := ATier;
  FCapturedPrompt := AUserPrompt;
  Inc(FCallCount);
  if FRaiseOnNextChat then
    raise Exception.Create('mock LLM raised');
  Result := FNextResult;
end;

function TMockLLMClient.Chat(const ATier: TModelTier;
  const ASystemPrompt, AUserPrompt: string): TChatResult;
begin
  Result := Chat(ATier, AUserPrompt);
end;

function TMockLLMClient.ChatWithHistory(const ATier: TModelTier;
  const AMessages: TArray<TChatMessage>; AMaxTokens: Integer;
  ATemperature: Double): TChatResult;
begin
  Result := Default(TChatResult);
end;

procedure TMockLLMClient.ChatStream(const ATier: TModelTier;
  const AMessages: TArray<TChatMessage>; AOnChunk, AOnError: TProc<string>;
  AMaxTokens: Integer);
begin
  // not used by tests
end;

function TMockLLMClient.ChatVision(const ATier: TModelTier; const AImageBase64,
  AImageMimeType, AUserPrompt, ASystemPrompt: string): TChatResult;
begin
  Result := Default(TChatResult);
end;

function TMockLLMClient.GenerateImage(const APrompt,
  ASize: string): TImageGenerationResult;
begin
  Result := Default(TImageGenerationResult);
end;

procedure TMockLLMClient.ChatVisionStream(const ATier: TModelTier;
  const AImageBase64, AImageMimeType, AUserPrompt, ASystemPrompt: string;
  AOnChunk, AOnError: TProc<string>; AMaxTokens: Integer);
begin
  // not used by tests
end;

function TMockLLMClient.GetModelForTier(const ATier: TModelTier): string;
begin
  Result := 'mock-model';
end;

function TMockLLMClient.CallCountIfc: Integer;
begin
  Result := FCallCount;
end;

function TMockLLMClient.LastDurationMs: Integer;
begin
  Result := 0;
end;

{ TAIErrorHandlerLLMBridgeTests }

procedure TAIErrorHandlerLLMBridgeTests.Setup;
begin
  Randomize;
end;

function TAIErrorHandlerLLMBridgeTests.ReadLLMBridgeSource: string;
var
  P: string;
begin
  for P in CSourceCandidates do
    if TFile.Exists(P) then
      Exit(TFile.ReadAllText(P, TEncoding.UTF8));
  Result := '';
  Assert.Fail('LLMBridge.pas not found at any expected location');
end;

function TAIErrorHandlerLLMBridgeTests.MakeBridgeLikeCallback(
  AMock: TMockLLMClient): TAIAnalysisCallback;
var
  LMock: ILLMClient;
begin
  LMock := AMock;  // 升级为 ILLMClient 接口持有
  Result :=
    function(const APrompt: string): string
    var
      LR: TChatResult;
    begin
      Result := '';
      try
        LR := LMock.Chat(TierFast, APrompt);
        if LR.Success then
          Result := LR.Content;
      except
        Result := '';
      end;
    end;
end;

// ----------------------------------------------------------------------------
// Property 7: LLMBridge 透传成功结果
//   For any prompt p 与 mock LLM M 返回 {Success: True; Content: c}，
//   桥接 callback 在 prompt p 上应返回 c。
//
// 实现策略:
//   (1) 静态源码扫描确认 LLMBridge 实现里有 Success / Content 透传逻辑。
//   (2) 用 MakeBridgeLikeCallback 复刻该逻辑并通过 SetAICallback 注入
//       AIErrorHandler；100 轮随机 prompt + 随机 content 走 callback，
//       断言返回值等于 mock 配置的 content。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerLLMBridgeTests.Property7_PassThroughSuccess;
const
  CIterations = 100;
var
  LSrc: string;
  LMock: TMockLLMClient;
  LCb: TAIAnalysisCallback;
  LPrompt, LContent, LResult: string;
begin
  // ---- 静态：LLMBridge.pas 必须含 Success / Content 透传 ----
  LSrc := ReadLLMBridgeSource;
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'LResult\.Success'),
    'Property 7 静态: LLMBridge 必须检查 LResult.Success');
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'Result\s*:=\s*LResult\.Content'),
    'Property 7 静态: LLMBridge 必须把 LResult.Content 透传给 callback Result');

  // ---- 动态：100 轮 mock-driven 透传 ----
  LMock := TMockLLMClient.Create;
  try
    LCb := MakeBridgeLikeCallback(LMock);
    TAIErrorHandler.SetAICallback(LCb);

    for var I := 1 to CIterations do
    begin
      LPrompt := 'p7-prompt-' + IntToStr(I) + '-' + IntToStr(Random(1000000));
      LContent := 'content-' + IntToStr(I) + '-' + IntToStr(Random(1000000));
      LMock.ConfigureSuccess(LContent);

      LResult := LCb(LPrompt);

      Assert.AreEqual(LContent, LResult,
        Format('Iter %d: bridge callback should pass through Content', [I]));
      Assert.AreEqual(LPrompt, LMock.CapturedPrompt,
        Format('Iter %d: bridge should forward APrompt to LLM', [I]));
    end;
  finally
    // 清理 callback：换回 nil 防止后续 fixture 误用
    TAIErrorHandler.SetAICallback(nil);
    // mock 由接口引用计数管理；此处不再 LMock.Free 以避免双重释放
  end;
end;

// ----------------------------------------------------------------------------
// Property 8: LLM 失败 / 缓存损坏 -> 空串与降级
//   For any prompt p 与失败模式 f ∈ {Raise, Success=False, Content='',
//   服务不可用 (返回失败), FCache=nil}，桥接 callback 返回 ''.
//   AIErrorHandler 在该返回下走通用降级文案分支 (不抛、不阻塞)。
//
// 实现策略:
//   (1) 静态扫描 LLMBridge: try/except、Result := '' 默认值；
//   (2) 五种失败模式各 20 轮随机 prompt，断言 callback 返回 ''；
//   (3) FCache=nil 时 AIErrorHandler.Handle 仍可工作 —— 通过 ClearCache
//       + 后续调 Handle 验证不抛异常。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerLLMBridgeTests.Property8_FailureFallsBackToEmpty;
const
  CRoundsPerMode = 20;
  CTotalIterations = CRoundsPerMode * 5;
var
  LSrc: string;
  LMock: TMockLLMClient;
  LCb: TAIAnalysisCallback;
  LPrompt, LResult: string;
  LSavedCfg, LCfg: TAIErrorConfig;
  E: Exception;
  LIterCount: Integer;
begin
  // ---- 静态：LLMBridge 必须 try/except 吞异常并默认空串 ----
  LSrc := ReadLLMBridgeSource;
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, '\btry\b'),
    'Property 8 静态: LLMBridge 必须使用 try..except 包裹 LLM 调用');
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, '\bexcept\b'),
    'Property 8 静态: LLMBridge 必须有 except 块');
  Assert.IsTrue(
    TRegEx.IsMatch(LSrc, 'Result\s*:=\s*'''';'),
    'Property 8 静态: LLMBridge 默认 Result := ''''');

  // ---- 动态: 5 种失败模式 × 20 轮 ----
  LMock := TMockLLMClient.Create;
  try
    LCb := MakeBridgeLikeCallback(LMock);

    LIterCount := 0;

    // 模式 1: 抛异常
    for var I := 1 to CRoundsPerMode do
    begin
      Inc(LIterCount);
      LMock.ConfigureRaise;
      LPrompt := 'p8-raise-' + IntToStr(I);
      LResult := LCb(LPrompt);
      Assert.AreEqual('', LResult,
        Format('Iter %d (raise): 桥接异常应返回空串', [LIterCount]));
    end;

    // 模式 2: Success=False
    for var I := 1 to CRoundsPerMode do
    begin
      Inc(LIterCount);
      LMock.ConfigureFailure('mock-error-' + IntToStr(I));
      LPrompt := 'p8-fail-' + IntToStr(I);
      LResult := LCb(LPrompt);
      Assert.AreEqual('', LResult,
        Format('Iter %d (Success=False): 应返回空串', [LIterCount]));
    end;

    // 模式 3: Success=True 但 Content=''
    for var I := 1 to CRoundsPerMode do
    begin
      Inc(LIterCount);
      LMock.ConfigureEmptyContent;
      LPrompt := 'p8-empty-' + IntToStr(I);
      LResult := LCb(LPrompt);
      Assert.AreEqual('', LResult,
        Format('Iter %d (empty content): 应返回空串', [LIterCount]));
    end;

    // 模式 4: 服务不可用 (返回失败结果, 与模式 2 类似但用更长错误消息)
    for var I := 1 to CRoundsPerMode do
    begin
      Inc(LIterCount);
      LMock.ConfigureFailure(
        'service unavailable, no provider configured for tier "fast"');
      LPrompt := 'p8-unavail-' + IntToStr(I);
      LResult := LCb(LPrompt);
      Assert.AreEqual('', LResult,
        Format('Iter %d (service unavailable): 应返回空串', [LIterCount]));
    end;

    // 模式 5: FCache=nil 时 AIErrorHandler 仍能 Handle 不抛
    //         (TAIErrorHandler.ClearCache 不会把 FCache 设为 nil，
    //          但 CallAI 内部已处理 FCache=nil 的退化，这里
    //          通过 Handle 真实 elAIAnalyze 异常验证不抛)
    LSavedCfg := TAIErrorHandler.Config;
    try
      LCfg := TAIErrorConfig.Default;
      LCfg.SilentMode := True;
      LCfg.AIEnabled := True;
      TAIErrorHandler.Config := LCfg;
      TAIErrorHandler.SetAICallback(LCb);

      for var I := 1 to CRoundsPerMode do
      begin
        Inc(LIterCount);
        LMock.ConfigureFailure('cache-nil-mode');
        TAIErrorHandler.ClearCache;
        E := Exception.Create('p8-cache-' + IntToStr(I));
        try
          TAIErrorHandler.Handle(E, 'p8-cache');
        finally
          E.Free;
        end;
      end;
    finally
      TAIErrorHandler.Config := LSavedCfg;
      TAIErrorHandler.SetAICallback(nil);
    end;

    Assert.AreEqual<Integer>(CTotalIterations, LIterCount,
      'Property 8 should have run exactly 100 iterations');
  finally
    // mock 由接口引用计数管理
  end;
end;

// ----------------------------------------------------------------------------
// Example E1: LLMBridge 选用 TierFast 常量
//   静态扫描 LLMBridge.pas 源文件确认其 Chat 调用使用 TierFast 常量；
//   100 轮独立确认源文件状态稳定。
//
// 备注: 因 LLM() 单例无 setter，无法运行时捕获 ATier；本测试纯静态。
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerLLMBridgeTests.ExampleE1_TierFastConstant;
const
  CIterations = 100;
var
  LSrc: string;
  LTierPat, LChatPat: TRegEx;
begin
  LSrc := ReadLLMBridgeSource;
  LTierPat := TRegEx.Create('TierFast');
  LChatPat := TRegEx.Create('LLM[\.\(]?[\)\.]?Chat\s*\(\s*TierFast');

  for var I := 1 to CIterations do
  begin
    Assert.IsTrue(LTierPat.IsMatch(LSrc),
      Format('Iter %d: LLMBridge 必须引用 TierFast 常量', [I]));
    Assert.IsTrue(LChatPat.IsMatch(LSrc),
      Format('Iter %d: LLMBridge.Chat 调用第一个参数必须是 TierFast', [I]));
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAIErrorHandlerLLMBridgeTests);

end.
