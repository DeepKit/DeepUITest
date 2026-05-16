# DeepBase 增强计划 — 来自 Group B 下游项目的需求

> 来源：Stream（流）Worker 在 Delphi 13.1 迁移过程中的代码审查
> 涉及项目：DeepLLM / DeepCompare / DeepInsight / DeepInput
> 原则：共用部分统一到 DeepBase，不满足就增强 DeepBase，让框架越来越完善
> 日期：2026-05-09

---

## 一、DeepBase.Manager 需要 Headless 初始化模式

### 问题

`DeepBase.Manager.Initialize` 会加载所有子系统（Theme、Hotkeys、FormState、i18n、MRU 等），
但控制台进程（如 DeepLLMProxy）不需要 UI 相关子系统。当前 DeepLLMProxy.dpr 调用完整初始化后，
大量 UI 子系统白白占用内存和启动时间。

### 需求方

| 项目 | 场景 |
|---|---|
| DeepLLM | `DeepLLMProxy.exe` 是纯控制台进程，不需要 Theme/Hotkeys/FormState |
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

DeepLLM 自己实现了 `ProxyCircuitBreaker.pas`（5 级指数退避：GREEN→YELLOW→OPEN1/2/3→BLACK），
而 DeepBase 已有 `DeepBase.Resilience.CircuitBreaker.pas` 但只支持标准三态（Closed/Open/HalfOpen）。

### 需求方

| 项目 | 场景 |
|---|---|
| DeepLLM | 账号级熔断，5 级退避，BLACK 需人工/探活恢复 |
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

DeepLLM 的 `ProxyFallback.pas` 实现了条件降级规则（from_model→to_model + 触发条件），
DeepBase 的 `DeepBase.Resilience.Fallback.pas` 只是简单的 fallback 函数包装。

### 需求方

| 项目 | 场景 |
|---|---|
| DeepLLM | 模型降级：gpt-4→gpt-3.5，条件：provider_down / rate_limit / circuit_open |
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

DeepLLM 的 `ProxyLogger.pas` 在 `DeepBase.Logging` 之上加了一层 JSON 格式化（key=value pairs），
DeepInsight 的 `LG001_Logger.pas` 也是对 `DeepBase.Logging` 的薄封装。
如果 DeepBase.Logging 原生支持结构化输出，这些封装层就不需要了。

### 需求方

| 项目 | 场景 |
|---|---|
| DeepLLM | ProxyLogger 输出 JSON 格式日志（request_id, duration_ms, status 等） |
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

DeepLLM 的 `ModelTypes.pas` 定义了 `TLLMProviderType`、`TApiFormat`、`TLLMMessages`、`TLLMResponse` 等核心类型。
DeepBase 的 `DeepBase.LLM.Types.pas` 也有类似定义。两者存在重复和潜在不一致。

### 需求方

| 项目 | 场景 |
|---|---|
| DeepLLM | 核心类型定义在 ModelTypes.pas（本地） |
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

DeepLLM 的 `ProxyConfigWatcher.pas` 自己实现了文件变更监控（轮询 + LastWriteTime 比较），
而 DeepBase 已有 `DeepBase.FileWatcher.pas`。

### 需求方

| 项目 | 场景 |
|---|---|
| DeepLLM | 监控 config/*.yaml 变更，触发热重载 |

### 建议

DeepLLM 直接使用 `DeepBase.FileWatcher`，删除 `ProxyConfigWatcher.pas` 中的自造监控逻辑。
如果 DeepBase.FileWatcher 缺少某些能力（如 debounce、多文件 glob 匹配），增强它。

### 优先级：P3

---

## 七、DeepBase.RateLimiter 增强：多维度滑动窗口

### 问题

DeepLLM 的 `ProxyRateLimiter.pas` 实现了 RPM（每分钟）+ RPD（每天）+ 自定义窗口 + per-account 隔离。
DeepBase 有 `DeepBase.RateLimiter.pas` 但能力不明确。

### 需求方

| 项目 | 场景 |
|---|---|
| DeepLLM | 上游 provider 限流（per-account RPM/RPD） + 下游客户端入口限流 |
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
  └── DeepLLM 切换到 DeepBase 模块（删除自造轮子）

Phase 3（稳定后）:
  ├── DeepBase.FileWatcher 替代 ProxyConfigWatcher [P3]
  ├── DeepInput 引入 DeepBase 依赖              [P3]
  └── DeepCompare/DeepInsight 清理冗余封装层     [P3]
```

---

## 各项目当前 DeepBase 使用概况

| 项目 | 使用的 DeepBase 模块 | 自造轮子（应统一） |
|---|---|---|
| **DeepLLM** | Manager, Logging, DB.Pool, DB.DoQry, DB.Factory, DB.Migrations, Config, AppLifecycle, Security.DPAPI, LLM.Types, Exceptions, Resilience(引用但未用) | CircuitBreaker, Fallback, RateLimiter, ConfigWatcher, Logger(JSON层), ModelTypes |
| **DeepCompare** | Manager, Logging, DB.DoQry, MRU, Types, Config | NetworkRetry(应统一到Resilience.Retry), ParallelTest.CircuitBreaker |
| **DeepInsight** | Manager, Logging, DB.DoQry, Config, i18n | LG001_Logger(封装层), CtrlLlm 中的 LLM 类型定义 |
| **DeepInput** | （无） | Config(INI), SecretStore(DPAPI), Hotkey |
