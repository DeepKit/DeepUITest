# DeepBase 增强计划 — 来自 Group B 下游项目的需求

> 来源：Stream（流）Worker 在 Delphi 13.1 迁移过程中的代码审查
> 涉及项目：Assayer / DeepCompare / DeepInsight / DeepInput
> 原则：共用部分统一到 DeepBase，不满足就增强 DeepBase，让框架越来越完善
> 日期：2026-05-09

---

## 一、DeepBase.Manager 需要 Headless 初始化模式

### 问题

`DeepBase.Manager.Initialize` 会加载所有子系统（Theme、Hotkeys、FormState、i18n、MRU 等），
但控制台进程（如 AssayerProxy）不需要 UI 相关子系统。当前 AssayerProxy.dpr 调用完整初始化后，
大量 UI 子系统白白占用内存和启动时间。

### 需求方

| 项目 | 场景 |
|---|---|
| Assayer | `AssayerProxy.exe` 是纯控制台进程，不需要 Theme/Hotkeys/FormState |
| DeepInsight | 后端 `backend/` 目录有独立服务脚本，未来可能拆出 headless 进程 |

### 建议实现

```pascal
// DeepBase.Manager.pas 新增：
class function InitializeHeadless: Boolean;
// 只初始化：Logger + DB(ConfigDB) + Config + AppLifecycle + Security
// 跳过：Theme + Hotkeys + FormState + MRU + SplashScreen + TrayIcon + i18n(可选)

// 调用方式：
if not DeepBase.Manager.DeepBase.InitializeHeadless then
  WriteLn('[WARN] DeepBase headless init failed');
```

### 优先级：P0（阻塞 Proxy 启动优化）

---

## 二、DeepBase.Resilience 增强：多级熔断器

### 问题

Assayer 自己实现了 `ProxyCircuitBreaker.pas`（5 级指数退避：GREEN→YELLOW→OPEN1/2/3→BLACK），
而 DeepBase 已有 `DeepBase.Resilience.CircuitBreaker.pas` 但只支持标准三态（Closed/Open/HalfOpen）。

### 需求方

| 项目 | 场景 |
|---|---|
| Assayer | 账号级熔断，5 级退避，BLACK 需人工/探活恢复 |
| DeepCompare | `DeepCompare.ParallelTest.pas` 有自己的 `FCircuitBreakerThreshold` 逻辑 |

### 建议增强

```pascal
// DeepBase.Resilience.CircuitBreaker.pas 增强：
TCircuitBreakerLevel = (cblClosed, cblHalfOpen, cblOpen1, cblOpen2, cblOpen3, cblBlack);

TCircuitBreakerConfig = record
  FailureThreshold: Integer;      // 连续失败触发阈值
  SuccessThreshold: Integer;      // 恢复所需连续成功次数
  RecoveryBaseMinutes: Integer;   // 基础恢复时间
  RecoveryMultiplier: Double;     // 退避倍数（默认 5.0）
  MaxLevel: Integer;              // 最大退避级别（默认 3）
  BlackAutoRecoveryHours: Integer;// BLACK 自动恢复时间（0=永不）
end;

TCircuitBreaker = class
  function CanExecute: Boolean;
  procedure RecordSuccess;
  procedure RecordFailure;
  procedure ForceReset;
  procedure ProbeSuccess;  // 探活成功，从 BLACK 恢复
  property Level: TCircuitBreakerLevel;
  property RecoveryTime: TDateTime;
end;
```

### 优先级：P1

---

## 三、DeepBase.Resilience 增强：条件降级规则引擎

### 问题

Assayer 的 `ProxyFallback.pas` 实现了条件降级规则（from_model→to_model + 触发条件），
DeepBase 的 `DeepBase.Resilience.Fallback.pas` 只是简单的 fallback 函数包装。

### 需求方

| 项目 | 场景 |
|---|---|
| Assayer | 模型降级：gpt-4→gpt-3.5，条件：provider_down / rate_limit / circuit_open |
| DeepInsight | Gemini API 失败时降级到 DeepSeek（当前硬编码在 CtrlLlm.pas） |

### 建议增强

```pascal
// DeepBase.Resilience.Fallback.pas 增强：
TFallbackCondition = (fcAlways, fcProviderDown, fcRateLimit, fcCircuitOpen, fcTimeout);

TFallbackRule = record
  FromKey: string;        // 源标识（模型名/服务名）
  ToKey: string;          // 降级目标
  Condition: TFallbackCondition;
  Priority: Integer;
end;

TFallbackRuleEngine = class
  procedure AddRule(const ARule: TFallbackRule);
  function GetFallback(const AFromKey: string; ACondition: TFallbackCondition): string;
  property OnFallbackTriggered: TFallbackEvent;
end;
```

### 优先级：P2

---

## 四、DeepBase.Logging 增强：结构化 JSON 输出

### 问题

Assayer 的 `ProxyLogger.pas` 在 `DeepBase.Logging` 之上加了一层 JSON 格式化（key=value pairs），
DeepInsight 的 `LG001_Logger.pas` 也是对 `DeepBase.Logging` 的薄封装。
如果 DeepBase.Logging 原生支持结构化输出，这些封装层就不需要了。

### 需求方

| 项目 | 场景 |
|---|---|
| Assayer | ProxyLogger 输出 JSON 格式日志（request_id, duration_ms, status 等） |
| DeepInsight | LG001_Logger 委托给 DeepBase.Logging，加了 category 字段 |
| DeepCompare | 直接用 DeepBase.Logging，但缺少结构化字段 |

### 建议增强

```pascal
// DeepBase.Logging.pas 增强：
TLogOutputFormat = (lofText, lofJson, lofKeyValue);

// 新增结构化日志方法：
procedure LogStructured(ALevel: TLogLevel; const AMessage: string;
  const AFields: array of const; const ACategory: string = '');

// 使用示例：
Logger.LogStructured(llInfo, 'Request completed',
  ['request_id', LRequestId, 'duration_ms', LDuration, 'status', 200],
  'Proxy');
// 输出: {"ts":"...","level":"INFO","cat":"Proxy","msg":"Request completed","request_id":"abc","duration_ms":42,"status":200}
```

### 优先级：P2

---

## 五、DeepBase.LLM.Types 统一

### 问题

Assayer 的 `ModelTypes.pas` 定义了 `TLLMProviderType`、`TApiFormat`、`TLLMMessages`、`TLLMResponse` 等核心类型。
DeepBase 的 `DeepBase.LLM.Types.pas` 也有类似定义。两者存在重复和潜在不一致。

### 需求方

| 项目 | 场景 |
|---|---|
| Assayer | 核心类型定义在 ModelTypes.pas（本地） |
| DeepInsight | CtrlLlm.pas 自己定义了 LLM 配置结构 |
| DeepCompare | ModelProvider.pas 自己定义了 Provider 类型 |

### 建议

将以下类型统一定义在 `DeepBase.LLM.Types.pas`：

```pascal
TLLMProviderType = (ptOpenAI, ptAnthropic, ptDeepSeek, ptOllama, ptGemini,
  ptGroq, ptNvidia, ptMoonshot, ptZhipu, ptAlibaba, ptTencent, ptBaidu,
  ptXunfei, ptAugment, ptDuojie, ptIFlow, ptCustom, ptLiteLLM);

TApiFormat = (afUnknown, afOpenAI, afAnthropic, afOllama, afUnified);

TLLMMessage = record
  Role: TLLMRole;
  Content: string;
end;
TLLMMessages = TArray<TLLMMessage>;

TLLMResponse = record
  Success: Boolean;
  Content: string;
  Model: string;
  FinishReason: string;
  Usage: TLLMUsage;
  ErrorKind: TLLMErrorKind;
  ErrorMessage: string;
  DurationMs: Integer;
  // ...
end;
```

下游项目通过 `uses DeepBase.LLM.Types` 引用，不再各自定义。

### 优先级：P1

---

## 六、DeepBase.FileWatcher 替代自造监控

### 问题

Assayer 的 `ProxyConfigWatcher.pas` 自己实现了文件变更监控（轮询 + LastWriteTime 比较），
而 DeepBase 已有 `DeepBase.FileWatcher.pas`。

### 需求方

| 项目 | 场景 |
|---|---|
| Assayer | 监控 config/*.yaml 变更，触发热重载 |

### 建议

Assayer 直接使用 `DeepBase.FileWatcher`，删除 `ProxyConfigWatcher.pas` 中的自造监控逻辑。
如果 DeepBase.FileWatcher 缺少某些能力（如 debounce、多文件 glob 匹配），增强它。

### 优先级：P3

---

## 七、DeepBase.RateLimiter 增强：多维度滑动窗口

### 问题

Assayer 的 `ProxyRateLimiter.pas` 实现了 RPM（每分钟）+ RPD（每天）+ 自定义窗口 + per-account 隔离。
DeepBase 有 `DeepBase.RateLimiter.pas` 但能力不明确。

### 需求方

| 项目 | 场景 |
|---|---|
| Assayer | 上游 provider 限流（per-account RPM/RPD） + 下游客户端入口限流 |
| DeepCompare | ParallelTest 有 `FMaxConcurrent` 并发控制 |

### 建议增强

```pascal
// DeepBase.RateLimiter.pas 增强：
TRateLimitWindow = (rlwPerSecond, rlwPerMinute, rlwPerHour, rlwPerDay, rlwCustom);

TRateLimitConfig = record
  Key: string;              // 限流维度标识（account_id / client_ip / token）
  Window: TRateLimitWindow;
  CustomWindowSec: Integer; // rlwCustom 时使用
  MaxRequests: Integer;
  BurstAllowance: Integer;  // 突发容忍
end;

TRateLimiter = class
  function TryAcquire(const AKey: string): Boolean;
  function GetRemaining(const AKey: string): Integer;
  procedure Reset(const AKey: string);
  // 持久化支持（重启不丢状态）
  procedure SaveState(const AFilePath: string);
  procedure LoadState(const AFilePath: string);
end;
```

### 优先级：P2

---

## 八、DeepInput 的特殊情况

DeepInput 当前 **零 DeepBase 依赖**（纯 VCL 工具）。但按照"共用部分统一到 DeepBase"的原则：

| DeepInput 现有实现 | 可统一到 DeepBase |
|---|---|
| `uConfig.pas`（INI 文件读写） | 可以用 `DeepBase.Config`（如果支持 INI 后端） |
| `uSecretStore.pas`（DPAPI 加密） | 应该用 `DeepBase.Security.DPAPI` |
| `uHotkey.pas`（全局热键） | 应该用 `DeepBase.Hotkeys` |

### 建议

DeepInput 下一步迁移时引入 DeepBase 依赖，统一使用框架的 Config/Security/Hotkeys 模块。
这需要 DeepBase 的 `InitializeHeadless` 或 `InitializeMinimal` 就绪后再做。

### 优先级：P3（等 DeepBase headless 模式就绪后）

---

## 执行路线图

```
Phase 1（DeepBase 迁移期间）:
  ├── DeepBase.Manager.InitializeHeadless        [P0]
  ├── DeepBase.LLM.Types 统一定义               [P1]
  └── DeepBase.Resilience.CircuitBreaker 增强    [P1]

Phase 2（DeepBase 迁移完成后）:
  ├── DeepBase.Resilience.Fallback 规则引擎      [P2]
  ├── DeepBase.Logging 结构化输出               [P2]
  ├── DeepBase.RateLimiter 多维度滑动窗口       [P2]
  └── Assayer 切换到 DeepBase 模块（删除自造轮子）

Phase 3（稳定后）:
  ├── DeepBase.FileWatcher 替代 ProxyConfigWatcher [P3]
  ├── DeepInput 引入 DeepBase 依赖              [P3]
  └── DeepCompare/DeepInsight 清理冗余封装层     [P3]
```

---

## 各项目当前 DeepBase 使用概况

| 项目 | 使用的 DeepBase 模块 | 自造轮子（应统一） |
|---|---|---|
| **Assayer** | Manager, Logging, DB.Pool, DB.DoQry, DB.Factory, DB.Migrations, Config, AppLifecycle, Security.DPAPI, LLM.Types, Exceptions, Resilience(引用但未用) | CircuitBreaker, Fallback, RateLimiter, ConfigWatcher, Logger(JSON层), ModelTypes |
| **DeepCompare** | Manager, Logging, DB.DoQry, MRU, Types, Config | NetworkRetry(应统一到Resilience.Retry), ParallelTest.CircuitBreaker |
| **DeepInsight** | Manager, Logging, DB.DoQry, Config, i18n | LG001_Logger(封装层), CtrlLlm 中的 LLM 类型定义 |
| **DeepInput** | （无） | Config(INI), SecretStore(DPAPI), Hotkey |

---

## 九、DeepBase.LLM.SSE — 原生 SSE 流式能力（来自 Group C）

> 来源：Coder Worker 圆桌会议 2026-05-09
> 涉及项目：DeepDev / Assayer / DeepStory / DeepCompare

### 问题

Delphi 13.1 引入原生 SSE 支持（`System.Net.HttpSse`，`THTTPEventSource`）。当前 `DeepBase.LLM.HTTP` 是纯同步调用，所有需要 LLM 的 Deep* 项目都缺少流式能力。

### 建议新增单元

| 单元 | 职责 |
|------|------|
| `DeepBase.LLM.SSE` | TLLMStreamClient — SSE 连接管理 + 流式/同步双模接口 |
| `DeepBase.LLM.Providers` | TProviderStreamParser — Provider 帧格式解析 |

### DeepBase.LLM.SSE 接口

```pascal
type
  TSSEChunkEvent = procedure(const AText: string) of object;
  TSSEDoneEvent = procedure(const AFullText: string; AInputTokens, AOutputTokens: Integer) of object;
  TSSEErrorEvent = procedure(const AError: string; ARetryable: Boolean) of object;

  TLLMStreamRequest = record
    URL: string;
    ApiKey: string;
    Body: string;
    TimeoutMs: Integer;
    Headers: TArray<TPair<string, string>>;
    ProviderKind: TProviderKind;
  end;

  TLLMStreamResult = record
    Success: Boolean;
    FullText: string;
    ErrorMessage: string;
    InputTokens: Integer;
    OutputTokens: Integer;
    DurationMs: Integer;
  end;

  TLLMStreamClient = class
    procedure Execute(const ARequest: TLLMStreamRequest;
      AOnChunk: TSSEChunkEvent; AOnDone: TSSEDoneEvent; AOnError: TSSEErrorEvent);
    function ExecuteSync(const ARequest: TLLMStreamRequest): TLLMStreamResult;
    procedure Cancel;
  end;
```

### DeepBase.LLM.Providers 接口

```pascal
type
  TProviderKind = (pkOpenAI, pkAnthropic, pkGeneric);

  TProviderStreamParser = class
    class function ParseDelta(AKind: TProviderKind; const ARawData: string): string;
    class function ParseUsage(AKind: TProviderKind; const ARawData: string;
      out AInputTokens, AOutputTokens: Integer): Boolean;
    class function IsDoneSignal(AKind: TProviderKind; const ARawData: string): Boolean;
    class function InferKind(const AProviderName: string): TProviderKind;
  end;
```

### DeepBase.LLM.Config 扩展

```pascal
// TModelConfig 新增字段
property SupportsStream: Boolean;
property DefaultStream: Boolean;
property ProviderKind: TProviderKind;
```

### 技术选型

- 底层：原生 `THTTPEventSource`（`System.Net.HttpSse`），ICS 作为 fallback
- 线程模型：每次调用创建独立实例，不跨线程共享
- UI 回调：通过 `TThread.Queue` 投递到主线程

### 帧格式差异（DeepBase 封装）

| Provider | delta 位置 | 结束信号 | Token 用量 |
|----------|-----------|----------|-----------|
| OpenAI | `choices[0].delta.content` | `data: [DONE]` | 最后 chunk 的 `usage` |
| Anthropic | `content_block_delta.delta.text` | `event: message_stop` | `message_delta.usage` |
| Generic | 同 OpenAI | 同 OpenAI | 同 OpenAI |

### 优先级：P0（与 DeepBase.LLM.Types 统一同步推进）


---

## 九、DeepBase.Net.SSE — 原生流式 SSE 收发模块

### 问题

Assayer 的 SSE 流式转发存在潜在的"伪流式"风险：`THTTPClient.Post` 返回后用 `TStreamReader.ReadLine` 读取，可能整个响应已缓冲在内存中才开始读取，导致用户感知的 TTFT（首 Token 延迟）= 整个响应生成时间。

### 圆桌讨论结论

13.1 的 `THTTPClient.Post(url, source, responseStream, headers)` 重载支持传入自定义 `TStream`，底层 WinHTTP 在收到每个 TCP chunk 时会调用 `TStream.Write`。利用这个机制可以实现真正的增量流式接收，零第三方依赖。

### 建议 DeepBase 提供

```pascal
// DeepBase.Net.SSE.pas

/// TSSEReceiveStream — 将 THTTPClient 的 chunked 响应转为逐行回调
TSSEReceiveStream = class(TStream)
private
  FBuffer: TStringBuilder;
  FOnLine: TProc<string>;
  FAborted: Boolean;
public
  function Write(const Buffer; Count: Longint): Longint; override;
  function Read(const Buffer; Count: Longint): Longint; override;
  procedure Abort;
  property OnLine: TProc<string> read FOnLine write FOnLine;
  property Aborted: Boolean read FAborted;
end;

/// TSSEPipe — 读写解耦的线程安全管道（Phase 2，多租户场景）
TSSEPipe = class
private
  FQueue: TThreadedQueue<string>;
public
  procedure Push(const ALine: string);
  function Pop(out ALine: string; ATimeoutMs: Integer = 100): Boolean;
  procedure SignalDone;
end;
```

### 使用方式（Assayer 切换后）

```pascal
// Phase 1：同步模式（个人版，并发 < 10）
var LStream := TSSEReceiveStream.Create;
LStream.OnLine := procedure(const ALine: string)
begin
  if not ACallback(ALine) then
    LStream.Abort;
end;
FHttpClient.Post(LUrl, LRequestContent, LStream, LHeaderList);

// Phase 2：Pipe 解耦模式（多租户/公网部署）
var LPipe := TSSEPipe.Create;
var LStream := TSSEReceiveStream.Create;
LStream.OnLine := procedure(const ALine: string)
begin
  LPipe.Push(ALine);
end;
// 线程 1：FHttpClient.Post(LUrl, LRequestContent, LStream, LHeaderList);
// 线程 2：while LPipe.Pop(LLine) do WriteSSEToClient(LLine);
```

### 需求方

| 项目 | 场景 |
|---|---|
| Assayer | 上游 LLM SSE 流式转发（核心路径） |
| DeepInsight | 未来如果从 REST 切到 SSE 流式调用 Gemini |
| DeepCompare | 未来如果从 WebView2 切到 API 直连 |

### 前置验证

在实现前需先验证：当前 `TStreamReader.ReadLine(Resp.ContentStream)` 在 13.1 WinHTTP 后端下是否已经是增量阻塞读取。如果是，则 `TSSEReceiveStream` 只是备选优化；如果不是，则为必须修复项。

### 设计原则

- 零第三方依赖，纯 Delphi 13.1 RTL
- `TSSEReceiveStream` 约 50 行，放入 DeepBase.Net.SSE
- `TSSEPipe` 基于 `System.Generics.Collections.TThreadedQueue<string>`
- SSE 协议解析仍由各项目自己的 Parser 负责（Assayer 的 `ProxySSE.TSSEParser` 不下沉）

### 优先级：P1（影响用户体验核心指标 TTFT）


---

## 十、DeepBase.Pipeline — 通用请求管道框架

### 问题

Assayer 的 `TRequestPipeline` 有 15 个串行阶段，存在以下问题：
1. 无 try/except — 任何阶段抛异常整个请求挂掉
2. 无阶段分类 — 不区分"安全门禁必须通过"和"优化类可跳过"
3. 无可观测性 — StageTimings 记录了但没输出
4. ErrorHint 预注入浪费 Token — 应改为 Forward 失败后才触发

### 建议 DeepBase 提供

```pascal
// DeepBase.Pipeline.pas

TStageCategory = (
  scCritical,    // 失败 = 请求中止，返回错误
  scBestEffort,  // 失败 = 记录日志，跳过继续
  scRetryable    // 失败 = 可重试（换参数/换路径）
);

TStageResult = record
  Success: Boolean;
  ErrorMessage: string;
  DurationMs: Int64;
end;

TStage<TContext> = record
  Name: string;
  Category: TStageCategory;
  Handler: TFunc<TContext, Boolean>;
end;

TPipelineResult = record
  Success: Boolean;
  FailedStage: string;
  TotalDurationMs: Int64;
  StageDurations: TArray<TPair<string, Int64>>;
end;

TPipeline<TContext> = class
  procedure AddStage(const AName: string; ACategory: TStageCategory;
    AHandler: TFunc<TContext, Boolean>);
  function Execute(var AContext: TContext): TPipelineResult;
  // 内部保证：
  //   - 每个阶段 try/except
  //   - Critical 失败 → 立即中止
  //   - BestEffort 失败 → 日志 + 跳过
  //   - Retryable 失败 → 调用 OnRetry 回调
  //   - 自动记录每阶段耗时
  //   - 总耗时超阈值自动输出 slow-pipeline 日志
  property SlowThresholdMs: Integer;  // 默认 200ms（不含 Retryable 阶段）
  property OnSlowPipeline: TProc<TPipelineResult>;
end;
```

### Assayer 切换后的阶段分类

| 阶段 | 类别 | 备注 |
|---|---|---|
| Constitution | Critical | ODD 绝对门禁 |
| Auth | Critical | 认证必须通过 |
| Sanitize | Critical | 输入清理 |
| RiskGuard | Critical | 风险检测 |
| SelectAcct | Critical | 无账号则无法转发 |
| Validate | Critical | 输出校验 |
| Forward | Retryable | 网络失败可换账号重试 |
| Challenge | BestEffort | ODD 质疑（辅助） |
| ContextAssemble | BestEffort | 上下文组装 |
| GoalInject | BestEffort | 意图守护 |
| Compress | BestEffort | Token 压缩 |
| SynthUserMsg | BestEffort | 消息修复 |
| ThinkingBlock | BestEffort | Thinking 标签处理 |
| TruncRecovery | BestEffort | 截断续写 |
| ErrorHint | 移除出管道 | 改为 Forward 重试时注入 |

### 需求方

| 项目 | 场景 |
|---|---|
| Assayer | 15 阶段请求管道 |
| DeepInsight | 未来 LLM 调用流程（当前是简单的 try/except） |
| 其他 Deep* | 任何需要多步骤处理 + 容错的场景 |

### 优先级：P1（稳定性核心）


---

## 十一、DeepBase.DB.WriteQueue — 异步批量写入队列

### 问题

Assayer 的 uDM.pas 有大量"记录"类写操作（RecordAccountUsage、RecordAuditEvent 等），每个请求触发 3-5 次 SQLite 写入。在 40 线程并发下，WAL 模式的写锁竞争成为瓶颈。

### 建议 DeepBase 提供

```pascal
// DeepBase.DB.WriteQueue.pas

TDBWriteQueue = class
private
  FQueue: TThreadedQueue<TWriteItem>;
  FWorker: TThread;
  FConnection: TFDConnection;
  FBatchSize: Integer;       // 默认 50
  FFlushIntervalMs: Integer; // 默认 100ms
public
  constructor Create(AConnection: TFDConnection);
  destructor Destroy; override;

  /// 非阻塞入队
  procedure Enqueue(const ASQL: string; const AParams: TArray<Variant>);

  /// 手动刷新（关闭前调用）
  procedure Flush;

  /// 内部：单线程消费，batch BEGIN/COMMIT
  /// 保证写入顺序，减少锁竞争从 N 次/请求 降为 1 次 batch/100ms
end;
```

### 需求方

| 项目 | 场景 |
|---|---|
| Assayer | RecordAccountUsage / RecordAuditEvent / RecordHealthPoint 等高频写入 |
| DeepInsight | 会话日志写入 |
| DeepCompare | 测试结果批量写入 |

### 优先级：P2（性能优化，非阻塞项）

---

## 十二、DeepBase 通用 Repository 接口

### 问题

Assayer 的 `ProxyPool.pas` 已经定义了 `IAccountRepository` 接口并通过构造函数注入。但这个接口定义在 Assayer 本地。DeepCompare 也有账号/Provider 管理需求，各自定义了不同的数据访问模式。

### 建议 DeepBase 提供

```pascal
// DeepBase.Repository.Interfaces.pas

IRepository<T> = interface
  function GetAll: TArray<T>;
  function GetById(const AId: string): T;
  function Add(const AItem: T): Boolean;
  function Update(const AItem: T): Boolean;
  function Delete(const AId: string): Boolean;
end;

// 具体领域接口（LLM 相关项目共用）
ILLMAccountRepository = interface(IRepository<TLLMAccount>)
  function GetByProvider(AProvider: TLLMProviderType): TArray<TLLMAccount>;
  function UpdateStatus(const AId: string; AStatus: TAccountStatus): Boolean;
  function RecordUsage(const AId: string; ATokens: Integer; ACost: Double): Boolean;
end;
```

### 迁移策略

- 不做大重构
- 新方法写在 Repository 实现里
- uDM 逐步变为纯 Facade（一行委托）
- 通过 `DeepBase.IoC` 注册和解析

### 优先级：P2


---

## 十三、DeepBase.ActionMap — 可配置的运行时行为引擎（核心框架）

### 问题

所有 Deep* 项目都有"上帝类膨胀"问题：一个中心类承担分发 + 处理，每加功能就改中心类。
根因是 if/else 分发逻辑和处理逻辑混在一起，没有"注册 + 配置 + 分发"的分离。

### 设计目标

1. 编译期静态注册（代码声明所有可能的 Action）
2. 运行时动态配置（DB/文件控制启用/禁用/优先级/参数）
3. 热更新（配置变更自动生效，不重启进程）
4. 安全锁定（关键 Action 不可运行时禁用）
5. 双模式分发（精确匹配 + 全量按序执行）
6. 容错（Handler 异常不崩溃整个链）
7. 可观测（内置 Metrics + 慢 Action 告警 + DryRun）
8. 可回滚（版本化配置 + 审计日志）
9. 线程安全（Copy-on-Write 快照，零锁竞争）

### 容错设计

| 风险场景 | 解决方案 |
|---|---|
| Handler 抛异常 | 每个 Handler 自动 try/except + ErrorStrategy（Abort/Skip/Retry/Fallback） |
| 配置源不可用（DB 断连） | 保持"最后已知良好配置"继续运行 |
| 热更新与分发并发 | Copy-on-Write 不可变快照，遍历中替换不影响当前执行 |
| 注册顺序依赖 | 依赖声明 + 启动时拓扑排序 |
| 循环调用 | ThreadVar 递归深度检测，超限自动中止 |
| 热更新出错需回退 | 版本化配置 + action_config_history 表 + Rollback API |

### 核心 API

```pascal
// DeepBase.ActionMap.pas

TErrorStrategy = (esAbort, esSkip, esRetry, esFallback);
TActionFlag = (afLocked, afHidden, afDeprecated);
TActionFlags = set of TActionFlag;

TActionEntry<TContext> = record
  Key: string;
  Group: string;
  Description: string;
  Priority: Integer;
  Enabled: Boolean;
  Flags: TActionFlags;
  ErrorStrategy: TErrorStrategy;
  DependsOn: TArray<string>;
  Handler: TProc<TContext>;
  Fallback: TProc<TContext>;
end;

TActionMetrics = record
  Key: string;
  CallCount: Int64;
  ErrorCount: Int64;
  TotalDurationMs: Int64;
  AvgDurationMs: Integer;
  LastCallTime: TDateTime;
  LastErrorMessage: string;
end;

TActionMap<TContext> = class
public
  // === 编译期注册 ===
  procedure Register(const AKey: string; AHandler: TProc<TContext>;
    AErrorStrategy: TErrorStrategy = esSkip;
    AFlags: TActionFlags = []); overload;
  procedure Register(const AKey, AGroup, ADescription: string;
    APriority: Integer; AErrorStrategy: TErrorStrategy;
    AFlags: TActionFlags; ADependsOn: TArray<string>;
    AHandler: TProc<TContext>; AFallback: TProc<TContext> = nil); overload;
  procedure RegisterPrefix(const APrefix: string; AHandler: TProc<TContext>);

  // === 运行时配置 ===
  procedure BindConfigSource(ASource: IActionConfigSource);
  procedure ReloadConfig;
  procedure SetEnabled(const AKey: string; AEnabled: Boolean);
  procedure SetPriority(const AKey: string; APriority: Integer);
  procedure Rollback(const AKey: string; AToVersion: Integer);

  // === 分发 ===
  function Dispatch(const AKey: string; var AContext: TContext): Boolean;
  function DispatchAll(var AContext: TContext): Integer;

  // === 可观测 ===
  function GetAll: TArray<TActionEntry<TContext>>;
  function GetMetrics: TArray<TActionMetrics>;
  function GetMetrics(const AKey: string): TActionMetrics;
  function DryRun(const AKey: string): TArray<string>;
  function DryRunAll: TArray<string>;
  function IsEnabled(const AKey: string): Boolean;

  // === 告警 ===
  property SlowThresholdMs: Integer;
  property OnSlowAction: TProc<string, Int64>;
  property OnError: TProc<string, Exception>;
end;
```

### 配置持久化

```sql
-- action_configs 表
CREATE TABLE action_configs (
  key TEXT PRIMARY KEY,
  enabled INTEGER DEFAULT 1,
  priority INTEGER DEFAULT 100,
  params TEXT,
  flags INTEGER DEFAULT 0,
  version INTEGER DEFAULT 1,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_by TEXT DEFAULT 'system'
);

-- 变更历史（支持回滚 + 审计）
CREATE TABLE action_config_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  key TEXT NOT NULL,
  enabled INTEGER,
  priority INTEGER,
  params TEXT,
  version INTEGER,
  changed_at TEXT DEFAULT CURRENT_TIMESTAMP,
  changed_by TEXT
);
```

### 线程安全实现

```pascal
// Copy-on-Write 快照模式
procedure TActionMap<TContext>.ReloadConfig;
begin
  var LNewSnapshot := BuildSnapshot(FRegistry, FConfigSource.LoadAll);
  TMonitor.Enter(FSnapshotLock);
  try
    FSnapshot := LNewSnapshot;  // 原子替换引用
  finally
    TMonitor.Exit(FSnapshotLock);
  end;
end;

function TActionMap<TContext>.DispatchAll(var AContext: TContext): Integer;
begin
  var LSnapshot := FSnapshot;  // 取引用（Delphi 动态数组引用计数，无拷贝）
  for var Entry in LSnapshot do
    if Entry.Enabled then
      ExecuteOne(Entry, AContext);
end;
```

### 通用性验证

| 项目 | 场景 | 模式 | ErrorStrategy |
|---|---|---|---|
| Assayer ProxyServer | HTTP 端点路由 | Dispatch | esAbort |
| Assayer Pipeline | 管道阶段 | DispatchAll | Critical=esAbort, Enhance=esSkip |
| Assayer FeatureFlags | 功能开关 | SetEnabled | — |
| DeepSVG 主窗体 | 菜单/工具栏 | Dispatch | esSkip |
| DeepStory 写作服务 | 30+ 服务调度 | DispatchAll | esSkip |
| DeepConfig 设置面板 | 配置项处理 | Dispatch | esSkip |
| DeepCompare 测试 | 策略选择 | Dispatch | esFallback |
| DeepInsight LLM | API 调用链 | DispatchAll | esRetry |
| 任何项目插件系统 | 动态加载 | Register + SetEnabled | esSkip |

### 实现规模

| 文件 | 行数 | 职责 |
|---|---|---|
| DeepBase.ActionMap.pas | ~400 | 核心引擎（注册/分发/容错/快照） |
| DeepBase.ActionMap.Config.pas | ~100 | IActionConfigSource + TActionConfig |
| DeepBase.ActionMap.DBSource.pas | ~120 | SQLite 配置源 + history + polling |
| DeepBase.ActionMap.FileSource.pas | ~60 | JSON 文件配置源 + FileWatcher |
| DeepBase.ActionMap.Metrics.pas | ~80 | 统计 + 慢告警 + DryRun |
| **总计** | **~760** | |

### 优先级：P0（框架核心能力，解决所有项目的"上帝类"问题 + 运行时热配置）
