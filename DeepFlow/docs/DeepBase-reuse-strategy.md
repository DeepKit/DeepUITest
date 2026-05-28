# UniFlow 复用 DeepBase 模块策略

> 版本: 1.0  
> 更新日期: 2025-01-XX  
> 状�? 待审�?

## 1. 背景

UniFlow 作为 DeepBase 生态系统的工作流引擎，应最大化复用 DeepBase Core 已有的成熟模块，避免重复造轮子，确保架构一致性和维护效率�?

## 2. 可复用的 DeepBase 核心模块

### 2.1 LLM 集成（高优先�?- 必须复用�?

| 模块 | 路径 | 复用价�?|
|------|------|----------|
| `DeepBase.LLM.pas` | `Core/DeepBase.LLM.pas` | ★★★★�?|
| `DeepBase.LLM.Manager.pas` | `Core/DeepBase.LLM.Manager.pas` | ★★★★�?|

**DeepBase.LLM.pas 提供�?*
- �?Provider 支持：OpenAI、Anthropic、Azure、LiteLLM、Ollama
- `TDeepBaseLLM` 类：统一�?LLM 调用接口
- `TLLMConfig`：配置管理（从数据库读取�?
- `TLLMMessage`、`TLLMChatResponse`：消息和响应类型
- `TLLMPromptTemplate`：Prompt 模板（支持继承）
- 调用历史记录、成本估�?
- 流式响应支持

**DeepBase.LLM.Manager.pas 提供�?*
- `TLLMManager`：全局 Prompt 管理�?
- 4 �?Prompt 分类 (Category/Type/Function/Variant)
- 每个 Prompt 最�?4 个版�?
- Meta-Prompt 合并 (PREFIX/SUFFIX/WRAP)
- BoundQuery 上下文注�?
- 测试支持

**UniFlow 集成方式�?*
```pascal
// 不要创建新的 LLM 客户端，直接使用 DeepBase.LLM
uses DeepBase.LLM, DeepBase.LLM.Manager;

// �?Workflow Action 中调�?LLM
procedure TLLMCallAction.Execute(Context: TWorkflowContext);
var
  LLM: TDeepBaseLLM;
  Response: TLLMChatResponse;
begin
  LLM := TDeepBaseLLM.Create(Context.GetVariable('llm.provider'));
  try
    Response := LLM.Chat([
      TLLMMessage.System(Context.GetVariable('system_prompt')),
      TLLMMessage.User(Context.GetVariable('user_input'))
    ]);
    Context.SetVariable('llm_response', Response.Content);
  finally
    LLM.Free;
  end;
end;
```

---

### 2.2 事件总线（高优先级）

| 模块 | 路径 | 复用价�?|
|------|------|----------|
| `DeepBase.EventBus.pas` | `Core/DeepBase.EventBus.pas` | ★★★★�?|

**功能�?*
- 发布/订阅模式
- 事件优先�?(Critical/High/Normal/Low)
- 事件过滤�?
- 同步/异步分发
- 单次订阅 (SubscribeOnce)

**UniFlow 使用场景�?*
- 工作流状态变更通知
- 步骤执行事件广播
- 跨工作流通信
- 外部系统集成

**集成方式�?*
```pascal
uses DeepBase.EventBus;

// 发布工作流事�?
EventBus.Publish<TWorkflowEvent>(TWorkflowEvent.Create(
  'workflow.step.completed',
  WorkflowId,
  StepId
));

// 订阅事件
EventBus.Subscribe<TWorkflowEvent>(
  procedure(const Event: TWorkflowEvent)
  begin
    // 处理事件
  end,
  'workflow.*'  // 过滤�?
);
```

---

### 2.3 状态机（高优先级）

| 模块 | 路径 | 复用价�?|
|------|------|----------|
| `DeepBase.StateMachine.pas` | `Core/DeepBase.StateMachine.pas` | ★★★★�?|

**功能�?*
- 泛型状态机 `TStateMachine<TState, TTrigger>`
- 状态转�?Guard 条件
- 进入/退�?Actions
- 层级状态支�?
- 状态变更事�?

**UniFlow 使用场景�?*
- 工作流实例状态管�?(Created �?Running �?Paused �?Completed)
- 步骤执行状态追�?
- 审批流程状态控�?

**集成方式�?*
```pascal
uses DeepBase.StateMachine;

type
  TWorkflowState = (wsCreated, wsRunning, wsPaused, wsCompleted, wsFailed);
  TWorkflowTrigger = (wtStart, wtPause, wtResume, wtComplete, wtFail);

// 配置状态机
FSM := TStateMachine<TWorkflowState, TWorkflowTrigger>.Create(wsCreated);
FSM.Configure(wsCreated)
   .Permit(wtStart, wsRunning);
FSM.Configure(wsRunning)
   .Permit(wtPause, wsPaused)
   .Permit(wtComplete, wsCompleted)
   .Permit(wtFail, wsFailed)
   .OnEntry(procedure begin Log('Workflow started'); end);
```

---

### 2.4 数据验证（中优先级）

| 模块 | 路径 | 复用价�?|
|------|------|----------|
| `DeepBase.Validation.pas` | `Core/DeepBase.Validation.pas` | ★★★☆�?|

**功能�?*
- 流式验证 API `TValidator<T>`
- 内置验证器：NotEmpty, MinLength, MaxLength, Range, Email, URL, Regex
- 自定义验证规�?
- 批量验证
- 本地化错误消�?

**UniFlow 使用场景�?*
- 工作流输入参数验�?
- 步骤输出数据校验
- LLM 响应格式验证

**集成方式�?*
```pascal
uses DeepBase.Validation;

// 验证工作流输�?
var Validator := TValidator<TWorkflowInput>.Create;
Validator
  .RuleFor('Name').NotEmpty.MinLength(3)
  .RuleFor('Email').Email
  .RuleFor('Age').Range(0, 150);

var Result := Validator.Validate(Input);
if not Result.IsValid then
  raise EValidationError.Create(Result.Errors);
```

---

### 2.5 日志系统（中优先级）

| 模块 | 路径 | 复用价�?|
|------|------|----------|
| `DeepBase.Logging.pas` | `Core/DeepBase.Logging.pas` | ★★★☆�?|

**功能�?*
- 多级日志 (Debug/Info/Warn/Error/Fatal)
- 多目标输�?(Database/File/Both)
- JSON 结构化日�?
- 异步写入队列
- 日志轮转
- 聚合器集�?

**UniFlow 使用方式�?*
```pascal
uses DeepBase.Logging;

// 直接使用全局 Logger
Logger.Info('Workflow started', 'UniFlow.Executor');
Logger.Debug('Step executing: ' + StepName, 'UniFlow.Step');
Logger.Error('Step failed: ' + ErrMsg, 'UniFlow.Error');
```

---

### 2.6 配置管理（中优先级）

| 模块 | 路径 | 复用价�?|
|------|------|----------|
| `DeepBase.Config.pas` | `Core/DeepBase.Config.pas` | ★★★☆�?|

**功能�?*
- 类型安全的配置读�?
- 内存缓存
- 线程安全
- 分类管理
- 变更事件

**UniFlow 使用方式�?*
```pascal
uses DeepBase.Config;

// 读取 UniFlow 配置
var MaxRetries := GetConfigInt('UniFlow.MaxRetries', 3);
var DefaultTimeout := GetConfigInt('UniFlow.DefaultTimeoutMs', 30000);
var LLMProvider := GetConfig('UniFlow.LLM.DefaultProvider', 'openai');
```

---

### 2.7 任务调度（低优先级）

| 模块 | 路径 | 复用价�?|
|------|------|----------|
| `DeepBase.Scheduler.pas` | `Core/DeepBase.Scheduler.pas` | ★★☆☆�?|

**功能�?*
- Cron 表达式支�?
- 延迟任务
- 周期任务
- 重试机制（指数退避）
- 任务优先级和依赖
- 线程池执�?

**UniFlow 潜在使用场景�?*
- 定时触发工作�?
- 延迟步骤执行
- 超时检�?

---

### 2.8 基础类型（必须复用）

| 模块 | 路径 | 复用价�?|
|------|------|----------|
| `DeepBase.Types.pas` | `Core/DeepBase.Types.pas` | ★★★★�?|

**提供�?*
- `TLogLevel` 枚举
- `TLLMCompleteEvent` 事件类型
- 其他共享类型定义

---

## 3. 需要删�?重构�?UniFlow 重复文件

以下文件�?DeepBase Core 功能重复，应该删除或重构�?

### 3.1 待删除文�?

| 文件 | 行数 | 重复内容 | 处理方式 |
|------|------|----------|----------|
| `Source/AI/UniFlow.AI.Types.pas` | ~1198 | 重复 DeepBase.LLM 类型定义 | **删除** |
| `Source/AI/UniFlow.AI.LLMClient.pas` | ~707 | 重复 DeepBase.LLM 客户�?| **删除** |

### 3.2 需要创建的适配�?

为了�?UniFlow Workflow 能优雅调�?DeepBase.LLM，创建轻量级适配器：

```
Source/AI/UniFlow.AI.Adapter.pas  (~200�?
  - TUniFlowLLMAdapter
    - 封装 DeepBase.LLM 调用
    - �?Workflow Context 变量映射�?LLM 参数
    - 处理响应并写�?Context
```

---

## 4. 集成架构�?

```
┌─────────────────────────────────────────────────────────────────�?
�?                         UniFlow                                �?
├─────────────────────────────────────────────────────────────────�?
�? UniFlow.Workflow.*          UniFlow.AI.Adapter                 �?
�? (工作流引�?                  (轻量适配�?                       �?
└───────────────────────────────┬─────────────────────────────────�?
                                �?调用
                                �?
┌─────────────────────────────────────────────────────────────────�?
�?                      DeepBase Core                              �?
├─────────────────────────────────────────────────────────────────�?
�? DeepBase.LLM         DeepBase.EventBus      DeepBase.StateMachine �?
�? DeepBase.LLM.Manager DeepBase.Validation    DeepBase.Logging      �?
�? DeepBase.Types       DeepBase.Config        DeepBase.Scheduler    �?
└─────────────────────────────────────────────────────────────────�?
```

---

## 5. 迁移步骤

### Phase 3.1: 清理重复代码
1. �?删除 `UniFlow.AI.Types.pas`
2. �?删除 `UniFlow.AI.LLMClient.pas`
3. �?创建 `UniFlow.AI.Adapter.pas`

### Phase 3.2: 集成 DeepBase 模块
1. �?�?Workflow Executor 中集�?`DeepBase.EventBus`
2. �?使用 `DeepBase.StateMachine` 管理 Workflow Instance 状�?
3. �?使用 `DeepBase.Validation` 进行输入/输出验证

### Phase 3.3: 测试验证
1. �?编写集成测试
2. �?验证 LLM 调用功能
3. �?验证事件发布/订阅

---

## 6. 注意事项

### 6.1 命名空间
- UniFlow 专属模块使用 `UniFlow.*` 命名空间
- 复用 DeepBase 模块时直�?`uses DeepBase.*`

### 6.2 依赖管理
- UniFlow 依赖 DeepBase Core，反之不成立
- 避免循环依赖

### 6.3 版本兼容
- 确保 UniFlow �?DeepBase Core 版本兼容
- 重大更新时同步更新两�?

---

## 7. 附录：DeepBase Core 模块完整列表

以下�?DeepBase Core 可能�?UniFlow 有用的其他模块（按需评估）：

- `DeepBase.Security.pas` - 安全相关（DPAPI 加密等）
- `DeepBase.Crypto.pas` - 加密算法
- `DeepBase.Cache.pas` - 缓存系统
- `DeepBase.Metrics.pas` - 指标收集
- `DeepBase.Plugin.pas` - 插件系统
- `DeepBase.HttpServer.pas` - HTTP 服务�?
- `DeepBase.Database.pas` - 数据库抽象层
