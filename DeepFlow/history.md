# DeepFlow 开发历史记录

> 记录已完成的开发任务、里程碑和重要决策

---

### v1.0.0 封版里程碑（2026-08-11）

**交付内容**：六角色治理闭环完整达成 + DeepInsight×DeepFlow 集成 + WiseGateway 多家族 LLM 治理

**质量验证**：v2 冒烟测试 kejian_v2_smoke_test.py 10/10 全绿；E2E 六角色链路降级容错正常

**核心功能**：
- 六角色并行推演（coach/critic/mirror/observer + aggregator）胶片生成与视觉化呈现
- 追问流式输出 + 历史服务端持久化（SQLite WAL CRUD，跨浏览器同步）
- 脑内 X 光片（decision/treehole 双模式）+ 树洞模式 + 跨会话成长对比
- WiseGateway call_by_name 多家族 LLM 治理（GPT/GLM/Kimi/Qwen 等 8 家族）

**已知限制**：GPT 国内网络访问受限导致四视角偶发降级，聚合器仍可用，选择 GLM/Kimi 替代模型即可正常运行。

---

## 2026-08-09: 可鉴决策操作系统 MVP 发布

### 新增模块
- **Web 前端** (`可鉴/`): 单页应用 + 品牌样式 + 六角色并行推演逻辑 + 胶片渲染 + 继续追问（对话式治理）
- **测试工具**: E2E 测试套件（kejian_e2e_test.py）、压力测试工具（stress_test.py）、样本库生成器（generate_samples.py）
- **文档**: 产品定位文档（docs/zh/09.03）、README、实操检验手册、MVP 总结报告

### 技术成就
- 六角色真实真绿验证（0 降级，0 错误）
- Skills 服务契约修正完成（params/context/timeout_ms）
- 结构化胶片产出验证通过
- 追问功能多轮上下文链路验证通过（/llm/chat）
- T8 行业决策场景模板落地：scenarios.py 知识库 + 四角色按 decision_type 差异化注入（修复模板选择形同虚设问题），真实链路验证投资场景输出聚焦回报/退出路径/止损线
- T9 LLM 稳定性：超时默认 40s→90s（实测单角色 48-54s，旧配置随机超时）；ChatResult 增加 truncated 截断检测，六 skill 降级原因区分 llm_response_truncated/not_json，单元 5/5 + 真实链路冒烟通过
- T10 胶片视觉化升级：film_generator 增加 visual fields（key_insights/tradeoffs/emotional_spectrum/decision_readiness），LLM 漏输出时从聚合结果兑底不伪造；前端胶片视觉组件（洞察卡/权衡对比/情绪谱条/成熟度仪表）+分享卡片洞察内容；单测 5/5 + 真实链路验证（LLM 成功输出 3 组权衡/4 种情绪强度/decision_readiness=58）+ 浏览器端到端确认（commit e9a47ec9）
- T11 修复 T10 遗留 UI 缺陷：聚合区对象数组渲染 [object Object]（新增 itemText 智能提取文本字段）+ film 变量作用域缺陷（const 提到 try 外避免异常时未定义），浏览器控制台验证无报错（commit 881ff0fc）
- T12 行业场景模板扩展：新增医疗/法律/教育/家庭四大场景（填补个人生活与专业领域空白），后端 scenarios 四角色聚焦提示 + 前端选择器联动；单测 8 模板全绿 + 前端 8 按钮验证 + medical 真实链路无降级注入生效（commit 34dfa198）
- T13 追问流式输出：client.py stream()（litellm stream=True 异步生成器）+ main.py /llm/chat/stream SSE 端点 + kejian.js fetch ReadableStream 逐字显影 + nonStreamFallback 降级兜底；真实链路 Connection error 根因为 WiseGateway 进程停摆，恢复后流式 28s/35char/deltas=1（commit 8460b9e0）
- T14 决策历史与复盘：localStorage 持久化（kejian_history_v1，上限 30 条，配额超限自动瘦身不静默丢失）+ 历史面板（问题/时间/模板/降级标记/耗时）+ 一键复盘（回放聚合与胶片、同步模板、可继续追问，不调模型）+ 单删/清空；浏览器全回归通过 + 截图留证 ui/T14-history-panel.png（commit 5b31c355）
- T19a 个人决策数据服务端持久化（T19 启动首步）：Skills /governance/history CRUD（SQLite WAL，Skills/data/kejian_history.db）+ 前端端口探测（8001 幽灵进程自动绕行 8002）+ 服务端同步（合并去重/本地回填/删除清空联动）+ JSON 导出导入 + start_skills.bat 端口自适应启动；换浏览器场景全回归通过（commit 4a2bb003）


### 下一步
详见 tasks.md 中的 Kejian-MVP-Release 任务组

---

## Phase 1: 核心框架(Week 1-2)

### 2024-12-04 ~ 2024-12-05

#### 完成项目骨架与基础设施
- 创建 `Source/` 目录结构
- 创建 `Config/workflows/` 配置目录
- 创建 `Config/schemas/` Schema 目录

#### 完成核心消息与角色定义
- `UniFlow.Core.Message.pas` - 消息基类与序列化
- `UniFlow.Core.Role.pas` - 角色基类与接口定义
- `UniFlow.Core.Engine.pas` - 消息驱动引擎核心

#### 完成配置加载系统
- `UniFlow.Config.Loader.pas` - YAML/JSON 配置加载系统
- `UniFlow.Config.Types.pas` - 配置类型定义

---

## Phase 2: 调度能力框架(Week 3)

### 2024-12-05

#### 完成 Workflow 定义数据结构
- `UniFlow.Workflow.Definition.pas` (~2400 行)
  - `TStepType` 枚举 (action, condition, loop, parallel, subworkflow, wait, end)
  - `TActionType` 枚举 (skill, llm, guard, log, assign, http, script)
  - `TConditionOperator` 枚举 (eq, ne, gt, lt, ge, le, contains, startsWith, endsWith, matches, isEmpty, isNotEmpty, in, and, or, not)
  - `TLoopMode`, `TWaitStrategy`, `TFailureStrategy` 枚举
  - `TRetryPolicy` - 重试策略配置
  - `TConditionExpression` - 条件表达式
  - `TOutputConfig` - 输出映射配置
  - `TActionDefinition` - 动作定义
  - `TConditionBranch` - 条件分支
  - `TLoopConfig` - 循环配置
  - `TParallelConfig` - 并行配置
  - `TWaitConfig` - 等待配置
  - `TErrorHandler` - 错误处理机制
- `TWorkflowStep` - 工作流步骤
  - `TWorkflowHook/TWorkflowHooks` - 生命周期钩子
- `TTriggerConfig` - 触发器配置
- `TWorkflowDefinition` - 工作流定义
- 完整 JSON 序列化/反序列化支持
- 验证和克隆方法

#### 完成 Workflow 上下文管理
- 核心`UniFlow.Workflow.Context.pas` (~1400 行)
  - `TVariableScope` 枚举 (global, workflow, step, input, output)
- `TVariableValue` - 多类型变量值存储
  - `TScopeFrame` - 作用域帧
  - `TWorkflowContext` - 上下文管理器
  - `TExpressionEvaluator` - 表达式求值器
  - 变量引用语法 `{{ vars.xxx }}`
- 内置过滤器 `default`, `upper`, `lower`, `trim`, `json`, `truncate`

#### 完成 Workflow 步骤执行器
- 核心`UniFlow.Workflow.Executor.pas` (~1400 行)
  - `TExecutionStatus` 枚举 (idle, running, paused, waiting, completed, failed, cancelled)
  - `TStepResult` - 步骤执行结果
  - `TExecutionCursor` - 执行游标
  - `IActionExecutor` - 可扩展动作执行器接口
- `TWorkflowExecutor` - 主执行引擎
    - 线性步骤执行流程
    - 条件分支求值
    - 循环执行 (forEach, while, repeat)
    - 并行执行 (简化串行实现)
    - Wait/HumanTask 处理
    - 错误处理 (retry, fallback, goto)
    - 快照保存/恢复
- 内置执行器 `TLogActionExecutor`, `TAssignActionExecutor`, `TGuardActionExecutor`

#### 完成 Workflow 状态持久化
- 修`UniFlow.Workflow.State.pas` (~1200 行
  - `TWorkflowInstanceStatus` 枚举 (created, running, paused, waiting, completed, failed, cancelled)
  - `TWorkflowInstance` - 工作流实例
  - `TWorkflowSnapshot` - 状态快照
  - `TWorkflowEvent` - 执行事件
  - `IWorkflowStateStore` - 存储接口
  - `TMemoryWorkflowStateStore` - 内存存储实现
  - `TWorkflowStateManager` - 状态管理器
    - 实例创建与状态更新
    - 检查点保存/恢复
    - 事件记录

#### 完成示例 Workflow 定义
- 修改`Config/workflows/simple_qa.workflow.json`
  - 演示输入验证 与LLM调用 与输出验证完整流程
  - 包含条件分支、错误处理、日志记录
  - 支持重试策略和备选响应

---

## Phase 3: AI 集成阶段 (Week 4)

### 2024-12-05

#### 完成 DeepBase 模块复用分析
- 修分析 `DeepBase.LLM.pas` (~1900 行) - Provider LLM 客户端
- 修分析 `DeepBase.LLM.Manager.pas` (~1700 行) - Prompt 管理器
- 修分析 `DeepBase.EventBus.pas` - 发布/订阅事件总线
- 修分析 `DeepBase.StateMachine.pas` - 泛型状态机
- 修分析 `DeepBase.Validation.pas` - 数据验证框架
- 修分析 `DeepBase.Logging.pas` - 日志系统
- 修分析 `DeepBase.Config.pas` - 配置管理
- 代码分析 `DeepBase.Scheduler.pas` - 任务调度
- 文档创建 `docs/DeepBase-reuse-strategy.md` 复用策略文档

#### 技术决策
- **TD-004**: DeepFlow 复用 DeepBase.LLM 而非自建 LLM 客户端
  - 删除重复文件`UniFlow.AI.Types.pas` 和`UniFlow.AI.LLMClient.pas`
  - 创建轻量级`UniFlow.AI.Adapter.pas` 适配器

### 2025-12-05

#### 完成 LLM 适配器
- 完成**TASK-301R**: 创建 `UniFlow.AI.Adapter.pas` (~460 行)
  - `TLLMExecutionOptions` - LLM 执行选项
  - `TLLMExecutionResult` - 执行结果
  - `TUniFlowLLMAdapter` - 封装 DeepBase.LLM 调用
  - `TLLMActionExecutor` - 实现 IActionExecutor 接口
  - `RegisterLLMExecutor` - 辅助注册函数
- 执行**TASK-302R**: 清理重复文件
  - 删除 `Source/AI/UniFlow.AI.Types.pas` (~1198 行)
  - 删除 `Source/AI/UniFlow.AI.LLMClient.pas` (~707 行)
  - 净减少 ~1900 行重复代码
- 完成**TASK-303**: 创建 Prompt 模板文件
  - `Config/prompts/system_default.txt` - 默认系统 Prompt
  - `Config/prompts/qa_assistant.txt` - 问答助手 Prompt
  - `Config/prompts/code_review.txt` - 代码审查 Prompt (JSON 输出)
- 完成**TASK-305**: `TLLMActionExecutor` 已在 Adapter 中实现
  - 实现 `IActionExecutor` 接口
  - `RegisterLLMExecutor()` 辅助注册函数
- 完成**TASK-306**: JSON 响应解析已在 Adapter 中实现
  - `ExtractJsonValue()` JSON 路径提取
  - `JsonOutputMap` 响应映射配置

#### 完成 Python Skill 服务框架与 Delphi 客户端
- **创建TASK-307**: 创建 Python Skill 服务框架
  - `Skills/src/main.py` (~380 行 - FastAPI 入口
  - `Skills/src/skills/base.py` (~340 行 - Skill 基类
  - `Skills/src/skills/code_executor.py` (~370 行 - 代码执行 Skill
  - `Skills/src/llm/client.py` (~360 行 - LiteLLM 封装
  - `Skills/requirements.txt` - 依赖清单
  - `Skills/Dockerfile` - 容器化部署
- **创建TASK-308**: 创建 Delphi Skill 客户端
  - `Source/Skill/UniFlow.Skill.Types.pas` (~980 行 - 类型定义
  - `Source/Skill/UniFlow.Skill.Client.pas` (~690 行 - HTTP 客户端
  - `Source/Skill/UniFlow.Skill.Executor.pas` (~740 行 - Skill 动作执行器

---

## Phase 4: 校验与安全模块(Week 4)

### 2025-12-05

#### 完成 JSON Schema 校验方法
- **创建TASK-401**: 创建 `UniFlow.Validation.Schema.pas` (~580 行
  - `TSchemaError` - 校验错误记录
  - `TSchemaValidationResult` - 校验结果
  - `TJSONSchema` - JSON Schema 校验器
  - 支持: type, required, properties, items, minLength, maxLength, minimum, maximum, pattern, enum
- **创建TASK-402**: 创建预定义Schema 文件
  - `Config/schemas/workflow_input.schema.json` - 工作流输入模板
  - `Config/schemas/llm_response.schema.json` - LLM 响应模式
  - `Config/schemas/user_request.schema.json` - 用户请求模式

#### 完成输入消毒模块
- **TASK-403**: 创建 `UniFlow.Security.Sanitizer.pas` (~530 行)
  - `TSanitizer` - 输入消毒函数
    - HTML 实体编码
    - SQL 注入防护
    - 路径遍历防护
    - 文件名消毒
    - URL/Email 验证
  - `TPromptGuard` - Prompt 注入检测
    - 22 种危险模式检测
    - Prompt 消毒

#### 完成敏感信息过滤和限流
- **TASK-405**: 创建 `UniFlow.Security.Filter.pas` (~1070 行)
  - `TSensitiveCategory` - 敏感数据分类 (PII/凭证/金融/健康)
  - `TFilterPattern` - 过滤模式定义
  - `TSensitiveWordList` - 敏感词库
  - `TSensitiveFilter` - 敏感信息过滤器
    - 17 种预置模板 (Email, 电话, SSN, 信用卡, API Key, JWT 等)
    - 部分/完全/哈希脱敏模式
  - `TLogSanitizer` - 日志脱敏器
- **TASK-406**: 创建 `UniFlow.Security.RateLimit.pas` (~1360 行)
  - `TRateLimitPolicy` - 限流策略配置
  - `TTokenBucket` - 令牌桶算法
  - `TSlidingWindowCounter` - 滑动窗口计数器
  - `TRateLimiter` - 请求限流器
    - 多种作用域 (Global/User/Session/IP/Endpoint)
    - 多种算法 (固定窗口/滑动窗口/令牌桶/漏桶)
  - `TTokenQuotaManager` - Token 配额管理
    - 每用户配额
    - 自动重置 (周期)

---

## Phase 5: 会话管理 阶段 (Week 4)

### 2025-12-05

#### 完成会话类型定义
- ✔ **TASK-502**: 创建 `UniFlow.Session.Types.pas` (~510 行)
  - `TSessionStatus` - 会话状态枚举
  - `TMessageRole` - 消息角色
  - `TChatMessage` - 聊天消息记录
  - `TSession` - 会话类（消息历史、变量存储、JSON 序列化）
  - `TSessionConfig` - 会话配置

#### 完成会话管理器
- ✔ **TASK-501**: 创建 `UniFlow.Session.Manager.pas` (~660 行)
  - `ISessionStore` - 存储接口
  - `TMemorySessionStore` - 内存存储实现
  - `TFileSessionStore` - 文件存储实现 (JSON)
  - `TSessionManager` - 会话管理器
    - 创建/查找/关闭/删除会话
    - 自动过期清理
    - 用户会话限制
    - 会话事件
    - 统计信息
- ✔ **TASK-503**: 会话上下文已集成到 TSession

#### 完成 Commander 角色
- ✔ **TASK-505**: 创建 `UniFlow.Roles.Commander.pas` (~1080 行)
  - `TUserRequest` / `TCommanderResponse` - 请求响应类型
  - `TIntent` / `TIntentRecognizer` - 意图识别器
    - 正则模式匹配
    - 关键词匹配
    - 优先级排序
  - `TCommander` - 请求入口和路由
    - 意图识别
    - Workflow 路由
    - 响应组装
    - 事件回调
  - `TSimpleWorkflowRegistry` - Workflow 注册表

---

## Phase 6: 集成测试 阶段 (Week 4)

### 2025-12-05

#### 完成测试框架
- **完成TASK-601**: 创建 `UniFlow.Test.Framework.pas` (~620 行
  - `TTestStatus` - 测试状态枚举
  - `TTestResult` / `TTestSuiteResult` - 测试结果
  - `TTestCase` - 测试用例基类 (20+ 断言方法)
  - `TTestRunner` - 测试运行器(RTTI 方法发现)

#### 完成核心测试用例
- **完成TASK-602**: 创建 `UniFlow.Test.Core.pas` (~840 行
  - `TWorkflowContextTest` - 8 个测试(变量、作用域、表达式、过滤器)
  - `TWorkflowDefinitionTest` - 6 个测试(创建、步骤、验证、JSON)
  - `TWorkflowExecutorTest` - 4 个测试(Log、Assign、条件、循环)
  - `TWorkflowStateTest` - 4 个测试(实例、状态、快照、事件)
  - `TSchemaValidationTest` - 8 个测试(JSON Schema 校验)
  - `TSanitizerTest` - 6 个测试(输入消毒)
  - `TSessionTest` - 6 个测试(会话管理)
  - **共计**: 42 个单元测试

#### 完成性能基准测试
- **完成TASK-603**: 创建 `UniFlow.Test.Performance.pas` (~1290 行
  - `TBenchmarkMeasurement` - 基准测量结果
  - `TBenchmarkRunner` - 性能测试运行器
    - 预热执行
    - P50/P95/P99 百分位计算
    - 内存使用跟踪
    - 并发基准测试
  - 5 个测试套件
    - `TContextPerformanceTests` - 上下文操作性能
    - `TWorkflowParsingTests` - Workflow 解析性能
    - `TSessionPerformanceTests` - 会话管理性能
    - `TIntentPerformanceTests` - 意图识别性能
    - `TValidationPerformanceTests` - 校验性能
  - `QuickPerformanceCheck()` - 快速性能检查函数

#### 完成文档和示例
- **TASK-604**: 创建开发文档
  - `docs/api-reference.md` - 完整 API 参考文档
    - 核心组件 API
    - Workflow 定义 API
    - Session 管理 API
    - Commander API
    - AI 集成 API
    - 校验与安全API
    - 事件回调说明
    - 线程安全说明
  - `docs/quick-start.md` - 快速入门指南
    - 5 分钟上手教程
    - 常见模式示例
    - 配置说明
    - 故障排除
- **TASK-605**: 创建示例项目
  - `Examples/QAChatbot/` - Q&A 机器人示例
    - `workflow_qa.json` - Workflow 定义
    - `QAChatbotExample.pas` - 完整示例代码
  - `Examples/CodeAssistant/` - 代码助手示例
    - `workflow_code_assistant.json` - 多分支Workflow
  - `Examples/MultiTurnChat/` - 多轮对话示例
    - `workflow_multiturn.json` - 上下文感知Workflow

---

## 里程碑达成

### M1: Hello World (Week 2 Target) - 已完成
- 已能执行简单硬编码 Workflow
- 已LLM 适配层已完成 (UniFlow.AI.Adapter)
- 已核心模块单元测试通过

### M2: 完整流程 (Week 4 Target) - 已完成
 - ✓支持条件分支、循环、错误处理
 - ✓Commander 请求路由
 - ✓意图识别
 - ✓完整示例项目

### M3: 生产就绪 (Week 6 Target) - 已完成
 - ✓性能基准测试
 - ✓文档完整
 - ✓敏感信息过滤
 - ✓请求限流&Token 配额管理

---

## 技术决策记录

### TD-001: Workflow 定义格式
- **决策**: 同时支持 JSON 或 YAML 格式
- **原因**: JSON 便于程序处理，YAML 便于人工编写
- **日期**: 2024-12-05

### TD-002: 变量引用语法
- **决策**: 采用 `{{ expression }}` 语法，支持过滤器
- **原因**: 与主流模板引擎兼容，学习成本小
- **日期**: 2024-12-05

### TD-003: 状态持久化策略
- **决策**: 先实现内存存储，后续添加 SQLite 实现
- **原因**: 快速验证设计，降低初期复杂度
- **日期**: 2024-12-05

---

## 代码统计

| 模块 | 文件 | 行数 | 状态|
|------|------|------|------|
| Workflow.Definition | pas | ~2400 | ✓|
| Workflow.Context | pas | ~1400 | ✓|
| Workflow.Executor | pas | ~1400 | 字节|
| Workflow.State | pas | ~1200 | 字节|
| AI.Adapter | pas | ~460 | 字节|
| Validation.Schema | pas | ~580 | 字节|
| Security.Sanitizer | pas | ~530 | 字节|
| Session.Types | pas | ~510 | 字节|
| Session.Manager | pas | ~660 | 字节|
| Roles.Commander | pas | ~1080 | 字节|
| Test.Framework | pas | ~620 | 字节|
| Test.Core | pas | ~840 | 字节|
| Test.Performance | pas | ~1290 | 字节|
| Security.Filter | pas | ~1070 | 字节|
| Security.RateLimit | pas | ~1360 | 字节|
| Skill.Types | pas | ~980 | 字节|
| Skill.Client | pas | ~690 | 字节|
| Skill.Executor | pas | ~740 | 字节|
| Audit.Types | pas | ~1,160 | 状态|
| Audit.Store | pas | ~1,020 | 状态|
| Audit.Manager | pas | ~1,050 | 状态|
| **Pascal 合计** | **21 files** | **~21,030** | 状态|

### Python 代码

| 模块 | 文件 | 行数 | 状态|
|------|------|------|------|
| main.py | py | ~380 | 状态|
| skills/base.py | py | ~340 | 状态|
| skills/code_executor.py | py | ~370 | 状态|
| llm/client.py | py | ~360 | 状态|
| **Python 合计** | **4 files** | **~1,450** | 状态|

---

## Phase 7: 可选增强[P2]

### 2025-12-05

#### TASK-701: 审计日志增强 ●
- ●创建 `Source/Audit/UniFlow.Audit.Types.pas` (~1,160 ●
  - `TAuditCategory` - 审计类别 (System/Workflow/Session/Security/LLM/Skill/User/Error)
  - `TAuditSeverity` - 严重级别 (Debug/Info/Warning/Error/Critical)
  - `TAuditAction` - 35+ 审计动作类型
  - `TAuditEntry` - 审计日志条目 (Fluent API)
  - `TAuditQuery` - 查询构建器(时间/类别/严重级别/关键字/分页)
  - `TAuditQueryResult` - 分页查询结果
  - `TAuditStats` - 聚合统计
  - `TAuditReport` - 报告结构
  - 工厂函数: `CreateAuditEntry`, `CreateSystemEntry`, `CreateWorkflowEntry` ●
- ●创建 `Source/Audit/UniFlow.Audit.Store.pas` (~1,020 ●
  - `IAuditStore` - 存储接口
  - `TAuditStoreConfig` - 存储配置 (保留天数/批量大小/自动清理)
  - `TMemoryAuditStore` - 内存存储实现 (完整查询支持)
  - `TSQLiteAuditStore` - SQLite 存储占位 (Schema 已定义)
  - `TFileAuditStore` - JSON Lines 文件存储 (日志轮转)
- 创建 `Source/Audit/UniFlow.Audit.Manager.pas` (~1,050 行)
  - `TAuditManager` - 中央审计管理器
    - 日志级别过滤
    - 默认上下文(用户/会话)
    - 关联 ID 追踪
    - 便捷方法: `LogSystem`, `LogWorkflow`, `LogSession`, `LogSecurity`, `LogLLM`, `LogSkill`, `LogError`
    - 事件订阅 (按类别/严重级别/自定义过滤)
    - 查询 API: `Query`, `GetStats`, `GetRecent`, `GetErrors`, `GetByCorrelation`
  - `TAuditReportGenerator` - 报告生成器
    - 汇总报告(Text/HTML/JSON)
    - 详细报告 (CSV/JSON)
    - 错误报告
    - 性能报告
    - 安全审计报告
    - 导出: CSV, JSON Lines
  - 全局实例: `AuditManager()` 函数
  - 初始化: `InitializeAuditManager`, `FinalizeAuditManager`

#### TASK-702: 监控指标
- 创建 `Source/Metrics/UniFlow.Metrics.Types.pas` (~1,280 行)
  - `TMetricType` - 指标类型 (Counter/Gauge/Histogram/Summary)
  - `TMetricLabels` - 标签键值对
  - `TCounterValue` - 计数器指标
  - `TGaugeValue` - 仪表指标
  - `THistogramValue` - 直方图指标(分桶统计)
  - `TSummaryValue` - 摘要指标 (分位数计算)
  - `TMetricFamily` - 指标组
  - `TDefaultBuckets` - 预定义分桶(HTTP/LLM/Token)
  - `TDefaultQuantiles` - 预定义分位数
  - Prometheus 文本格式导出
  - JSON 格式导出
- 创建 `Source/Metrics/UniFlow.Metrics.Collector.pas` (~910 行)
- `TMetricsRegistry` - 中央指标注册处
- 命名空间/子系统支持
    - Counter/Gauge/Histogram/Summary 注册
    - Prometheus/JSON 导出
- `TUniFlowMetrics` - 预定义DeepFlow 指标
    - Workflow: started/completed/failed/duration/active
    - Step: executed/failed/duration
    - LLM: requests/errors/duration/tokens/cost
    - Skill: invocations/errors/duration
    - Session: active/created/expired/messages
    - RateLimit: hits/quota_exceeded
    - System: uptime
- `TMetricsHTTPHandler` - HTTP 端点处理处
  - `TMetricTimer` - 计时器帮助类
  - 全局实例: `Metrics()` 函数

#### TASK-703: 多语言 Skill 支持
- 创建 Node.js Skill 服务 `Skills/nodejs/`
  - `package.json` - 依赖配置 (Express/Zod/Winston/OpenAI)
- `src/index.js` (~330 行) - Express 服务入口
- 健康检查 /health
- 技能发布 /skills
- 技能执行 /skills/:name/execute
    - 批量执行 /batch/execute
- `src/skills/base.js` (~260 行) - Skill 基类
    - Zod Schema 验证
    - JSON Schema 生成
    - 超时/重试辅助函数
- `src/skills/registry.js` (~86 行) - 技能注册表
- `src/skills/json-transform.js` (~227 行) - JSON 变换技能
- `src/skills/http-request.js` (~177 行) - HTTP 请求技能
- `src/skills/text-process.js` (~194 行) - 文本处理技能
- `Dockerfile` - 容器化部署(Node 20 Alpine)
- 内置技术
  - `json_transform` - JSON 数据变换 (extract/rename/map/filter/merge)
  - `http_request` - HTTP 请求 (GET/POST/超时/重试)
  - `text_process` - 文本处理 (uppercase/replace/template/hash)

---

## TASK-704: Visual Workflow Editor (Web UI)
**Completed**: 2025-12-05

### Files Created (~2,600 lines)

**Editor/index.html** (~220 lines)
- Main HTML structure with header toolbar, node palette sidebar, canvas area, properties panel, status bar
- Node template for drag-drop creation

**Editor/css/editor.css** (~519 lines)
- CSS variables with Catppuccin Mocha dark theme
- Layout styles for header, sidebar, canvas, properties panel
- Toolbar and button styles

**Editor/css/nodes.css** (~299 lines)
- Node card styles with type-specific colors
- Port styles for input/output connections
- Connection path styles and animations

**Editor/js/utils.js** (~238 lines)
- Utility functions: generateId, deepClone, debounce, clamp
- EventEmitter class for pub/sub
- UndoManager with 50-level hiDeepStory
- SVG helper functions for connection paths

**Editor/js/node-types.js** (~746 lines)
- 14 node type definitions: start, end, llm, skill, http, script, assign, log, condition, loop, parallel, wait, subworkflow, guard
- Property schemas with validation
- toWorkflowStep converters for export

**Editor/js/canvas.js** (~578 lines)
- WorkflowCanvas class with pan/zoom/drag
- Node management: add, remove, render, update
- Connection management with bezier paths
- Selection handling for nodes and connections
- Drag-drop from palette, keyboard shortcuts

**Editor/js/properties.js** (~359 lines)
- PropertiesPanel class
- Property editors: string, text, number, boolean, select, json, array, branches
- Real-time property updates with debouncing

**Editor/js/editor.js** (~428 lines)
- WorkflowEditor main controller
- File operations: new, open, save, export
- Undo/redo support
- Keyboard shortcuts (Ctrl+S, Ctrl+Z, etc.)
- localStorage persistence

### Features
- Drag-drop node creation from categorized palette
- Visual connection drawing between ports
- Multi-select with Shift/Ctrl
- Pan with mouse drag, zoom with scroll wheel
- Fit-to-view and zoom controls
- Properties panel with type-specific editors
- Export to DeepFlow workflow JSON format
- Import existing workflow definitions
- Auto-save to browser localStorage
- Undo/redo with 50-level hiDeepStory

---

## Phase 8: 调试与诊断

### 2025-12-05

#### TASK-901: 诊断模块 创建
- 创建 Source/Diagnostics/UniFlow.Diagnostics.pas (~1,200 行)
  - TLogLevel - 日志级别 (Trace/Debug/Info/Warning/Error/Fatal)
  - TTraceLevel - 追踪级别 (Off/Minimal/Normal/Verbose)
  - TLogEntry - 日志条目 (支持 CorrelationId/WorkflowId/StepId)
  - ILogger / ILoggerFactory - 日志接口（宿主可注入）
  - TConsoleLogger - 默认控制台日志（ANSI 彩色）
  - TTraceEntry - 执行追踪条目
  - TErrorContext - 错误上下文（变量/输入/堆栈/执行路径）
  - TUniFlowDiagnostics - 核心诊断类
    - 日志方法: Trace/Debug/Info/Warning/Error/Fatal
    - 步骤追踪: TraceStepEnter/TraceStepExit/TraceStepError
    - 错误上下文 CaptureErrorContext
    - 状态导出 DumpState/ExportTrace
    - 事件钩子: OnBeforeStep/OnAfterStep/OnError
  - 全局实例: Diagnostics() 函数
  - 设计原则: 零侵入、可插拔、低开销

#### TASK-902: CorrelationId 支持 封装
- 创建 Source/Diagnostics/UniFlow.Diagnostics.Integration.pas (~408 行)
  - TWorkflowDiagnostics - 工作流诊断包装器
    - 自动管理 CorrelationId 生命周期
    - StepBegin/StepEnd/StepError 快捷方法
    - CaptureError 错误上下文收集
  - THTTPDiagnostics - HTTP 请求诊断助手
     - AddTraceHeaders - 添加追踪头
    - ExtractCorrelationId - 提取追踪 ID
  - TLLMDiagnostics - LLM 调用诊断助手
    - LogRequest/LogResponse/LogTokenUsage
  - TSkillDiagnostics - Skill 调用诊断助手
  - HTTP 追踪头常量 X-Correlation-ID, X-Trace-ID 等

#### TASK-903: 错误上下文收集模块
- 创建 Source/Diagnostics/UniFlow.Diagnostics.ErrorCollector.pas (~931 行
  - TErrorSeverity - 错误严重级别 (Warning/Error/Critical/Fatal)
  - TErrorCategory - 13种错误分类(Validation/Network/Timeout/LLM/Skill)
  - TEnhancedErrorContext - 增强错误上下文
    - 追踪信息 (CorrelationId/WorkflowId/StepId)
    - 执行路径 (已执行步骤列表)
    - 环境信息 (机器名/进程ID/线程ID)
    - 自动建议生成
  - TErrorCollector - 错误收集器
    - 自动错误分类
    - CorrelationId/WorkflowId/Category/Severity 查询
    - 导出: JSON/Markdown/CSV

#### TASK-904: 执行轨迹导出 模块
- 请创建 Source/Diagnostics/UniFlow.Diagnostics.TraceExporter.pas (~661 行
  - TExecutionSnapshot - 执行快照 (用于复现问题)
  - TTraceExporter - 轨迹导出器
    - 创建/保存/加载快照
    - 多种导出格式 (JSON/Text/Markdown/Timeline)
    - 执行报告生成
    - 时间线报告
    - 性能报告

#### TASK-905: 调试模式 类
- 请创建 Source/Diagnostics/UniFlow.Diagnostics.Debugger.pas (~1,100 行
  - TDebuggerState - 调试器状态(Idlean/Running/Paused/Stepping/Breakpoint)
  - TBreakpointType - 断点类型 (Step/Conditional/Error/Watch)
  - TBreakpoint - 断点定义 (支持忽略计数/命中计数)
  - TDebugFrame - 调试器(调用栈)
  - TWorkflowDebugger - 工作流调试器
    - 断点管理: Add/Remove/Enable/Disable
    - 执行控制: Continue/Pause/StepInto/StepOver/StepOut/Stop
    - 调用栈 GetCallStack/GetCallStackDepth
- 变量检查 GetVariables/GetVariable/EvaluateExpression
  - TDebugConsole - 交互式调试控制台
    - GDB风格命令: c/s/n/o/bt/v/b/d/bl/e

---

### Phase 8 代码统计

| 模块 | 文件 | 行数 |
|------|------|------|
| Diagnostics | pas | ~1,200 |
| Diagnostics.Integration | pas | ~408 |
| Diagnostics.ErrorCollector | pas | ~931 |
| Diagnostics.TraceExporter | pas | ~661 |
| Diagnostics.Debugger | pas | ~1,100 |
| **Phase 8 合计** | **5 files** | **~4,300** |

---

## P3: 后续维护任务

### 2025-12-05

#### TASK-801: SQLite 存储实现 ？
- 新创建 Source/Storage/UniFlow.Storage.SQLite.pas (~2,270 行
  - **SQLite 连接抽象层*
    - `ISQLiteRow` - 结果行接口
    - `ISQLiteResult` - 查询结果接口
    - `ISQLiteStatement` - 预编译语句接口
    - `ISQLiteConnection` - 数据库连接接口
    - `TSQLiteConnectionFactory` - 连接工厂 (可替换为 FireDAC/mORMot)
    - `TMockSQLiteConnection` - Mock 实现 (用于测试/演示)
  - **TSQLiteAuditStore** - 完整审计日志存储
    - `TSQLiteAuditStoreConfig` - 配置项(WAL模式/FTS搜索/连接池大小/保留天数)
    - 完整 `IAuditStore` 接口实现
- 自动 Schema 创建和迁移
- 8 个索引(timestamp/category/severity/action/user_id/session_id/workflow_id/correlation_id)
    - 批量写入 + 事务支持
- 自动清理和保留策略
    - Vacuum/Optimize/GetDatabaseSize 维护方法
    - 导出/导入 JSON 支持
  - **TSQLiteSessionStore** - 完整会话存储
- `TSQLiteSessionStoreConfig` - 配置类
    - 完整 `ISessionStore` 接口实现
    - 4 张表: sessions, session_messages, session_variables, session_metadata
    - 外键级联删除
- 用户会话查询/过期会话清理/状态查询
- Touch/UpdateStatus 等便捷方法
    - GetStats 统计信息
- **TSQLiteConnectionPool** - 连接池
- 预创建连接
    - Acquire/Release
    - 可配置池大小

#### TASK-802: WebSocket 实时推送
- 📝 创建 Source/Realtime/UniFlow.Realtime.WebSocket.pas (~2,310 行)
  - **消息类型**
    - `TWSMessageType` - 协议消息类型 (subscribe/unsubscribe/ping/event/error)
    - `TWorkflowEventType` - 14种工作流事件类型
    - `TWSMessage` - WebSocket 消息结构 (JSON序列化)
    - `TWorkflowEvent` - 工作流事件通知
  - **订阅管理**
     - `TSubscription` - 订阅记录 (支持通配符
     - `TSubscriptionManager` - 主题订阅管理器
    - `TTopicType` - 主题类型 (workflow/session/user/all/custom)
   - **客户端管理**
     - `TWebSocketClient` - 客户端连接包体
- 连接状态/活动追踪/消息队列
    - Send/SendEvent/SendError/SendPong/SendWelcome
  - **消息代理**
- `TMessageBroker` - 消息路由和分发
    - Publish/PublishEvent/Broadcast/SendToClient/SendToUser
    - 消息历史记录
- **WebSocket 服务端**
- `TWebSocketServerConfig` - 服务器配置
- `TWebSocketServer` - 主服务器端
    - 自动 Ping/Pong 心跳
    - 连接清理线程
    - 认证支持
  - **事件桥接**
- `TWorkflowEventBridge` - 工作流事件到 WebSocket 的桥接
    - OnWorkflowStarted/Completed/Failed/Paused/Resumed/Cancelled
    - OnStepStarted/Completed/Failed
    - OnProgressUpdate/OnCustomEvent

#### TASK-803: 编辑器单元测试
- 📄 创建 Editor/tests/test-runner.html (~278 行)
  - HTML 测试运行器页面
  - Catppuccin Mocha 暗色主题
  - 实时统计显示 (total/passed/failed/skipped/duration)
  - Mock DOM 元素支持 canvas/properties/nodeTemplate
- 新建 Editor/tests/test-framework.js (~678 字符
  - 轻量级浏览器端测试框架
  - `describe/it/beforeEach/afterEach` 测试结构
  - 40+ 断言方法 (ok/equal/deepEqual/isTrue/throws/...)
  - 异步测试支持 + 超时处理
  - 实时 UI 更新
- 新建 Editor/tests/utils.test.js (~355 字符
  - generateId() 测试
  - deepClone() 测试
  - debounce()/throttle() 异步测试
  - clamp()/distance()/pointInRect() 测试
  - EventEmitter 测试 (on/off/emit/once)
  - UndoManager 测试 (push/undo/redo/clear)
- 新建 Editor/tests/node-types.test.js (~404 字符
  - 节点类型完整性测试(basic/action/flow/advanced)
  - 节点属性结构测试
  - 端口约束测试 (maxInputs/maxOutputs)
  - toWorkflowStep() 转换测试
  - getDefaultProperties() 测试
- 新建 Editor/tests/canvas.test.js (~450 字符
  - 画布初始化测试
  - 节点管理测试 (addNode/removeNode/事件)
  - 连接管理测试 (addConnection/reDeepMoveConnection/验证)
  - 选择功能测试 (select/deselect/multi-select)
  - 视图控制测试 (zoom/pan/screenToCanvas)
  - 序列化测试(toJSON/fromJSON/toWorkflowDefinition)
- 新建 Editor/tests/properties.test.js (~426 字符
  - 属性面板初始化测试
  - showEmpty()/showNode() 测试
  - 属性输入框创建测试 (text/number/textarea/select/checkbox)
  - 属性值显示测试
  - updateProperty() 测试 (onChange 回调)
  - 数字约束测试 (min/max)
- 新建 Editor/tests/integration.test.js (~435 字符
  - 完整工作流创建测试(线性/分支/循环/并行)
  - 画布与属性面板联动测试
  - 序列化往返测试
  - 节点类型完整性测试
  - 事件流测试
  - 边界情况测试
  - 性能基础检查(100节点/50连接)
  - UndoManager 集成测试

#### TASK-804: CI/CD 集成 ?
- ?创建 .github/workflows/ci.yml (~236 行
  - **Python Skills 测试**
    - pip 依赖缓存
    - ruff 代码检查
    - mypy 类型检查
    - pytest 覆盖率报告+ Codecov
  - **Node.js Skills 测试**
    - npm 依赖缓存
    - ESLint 代码检查
    - Node.js 内置测试运行器
  - **Web Editor 测试**
    - Playwright 浏览器测试
    - 测试结果工件上传
  - **Docker 构建测试**
    - Python/Node.js 镜像构建
    - GitHub Actions 缓存
  - **集成测试**
    - 服务健康检查
    - 技能发现测试
- ?创建 .github/workflows/release.yml (~174 行
  - 版本标签触发 (uniflow-v*)
  - Docker 镜像推送到 ghcr.io
  - 自动生成 GitHub Release
  - 自动生成 Changelog
- ?创建 .github/dependabot.yml (~75 行
  - Python pip 依赖更新
  - Node.js npm 依赖更新
  - GitHub Actions 更新
  - Docker 基础镜像更新
- ?创建 .github/playwright.config.js (~56 行
- Chromium 浏览器配置
  - 测试报告生成 (HTML/JSON)
- ?创建 Editor/tests/editor.spec.js (~153 行)
  - Playwright 测试用例
  - 验证所有测试套件通过
  - 失败详情捕获

#### TASK-805: 多语言文档 (英文) ?
- ?创建 docs/en/README.md (~190 行)
  - 项目概述和架构图
  - 快速入门指南
  - 文档导航
- ?创建 docs/en/quick-start.md (~353 行)
  - 5分钟快速入门教程
  - 完整代码示例
  - 常见模式指南
- ?创建 docs/en/api-reference.md (~757 行)
  - Workflow Definition API
  - Workflow Executor API
  - Session Management API
  - Skill Client API
  - Audit/Metrics API
  - Diagnostics/Debugger API
  - Security API
- ?创建 docs/en/workflow-definition.md (~653 行)
  - 完整 JSON 格式参数
  - 所有步骤类型文档
  - 所有动作类型文档
  - 表达式语法指南
  - 完整工作流示例
- ?创建 docs/en/skills-development.md (~724 行)
- Python Skill 开发指南
- Node.js Skill 开发指南
  - Skill API 契约
  - 最佳实践和测试
  - 部署配置示例
- 新建 docs/en/deployment.md (~858 行)
  - Docker 部署指南
  - Kubernetes 部署指南
  - 环境配置说明
- 监控和安全配置
- 备份恢复和故障排除
  - 性能调优指南

### P3 代码统计

|| 模块 | 文件 | 行数 |
||------|------|------|
|| Storage.SQLite | pas | ~2,270 |
|| Realtime.WebSocket | pas | ~2,310 |
|| Editor Tests | 7 files | ~2,300 |
|| CI/CD | 4 files | ~550 |
|| English Docs | 6 files | ~2,250 |
|| **P3 合计** | **20 files** | **~9,680** |

---

## P4: DeepBase 集成

### 2025-12-05

#### TASK-1001: Facade 单元测试
- 新建 Source/DeepBase.UniFlow.pas (~769 行)
  - **统一导出核心类型**
    - TUniFlowDefinition, TUniFlowStep, TUniFlowStepType
    - TUniFlowExecutor, TUniFlowContext, TUniFlowStepResult
    - TUniFlowSession, TUniFlowSessionManager
    - TUniFlowRequest, TUniFlowResponse, TUniFlowCommander
    - TUniFlowDiagnostics, TUniFlowDebugger, TUniFlowMetrics
- **TUniFlowEngineConfig - 配置项**
    - WorkflowDir, SessionTimeout, MaxSessionsPerUser
    - EnableAudit, EnableMetrics, EnableDiagnostics
    - SkillServiceURL, LLMConfigName
  - **TUniFlowEngine - 主引擎外观类**
    - Initialize/Shutdown 生命周期管理
- LoadWorkflow/LoadWorkflowFromJSON 工作流加载
    - RegisterRoute/RegisterIntent 路由注册
    - ProcessRequest/ProcessRequestObj 请求处理
    - ExecuteWorkflow 直接执行
    - GetOrCreateSession 会话管理
    - CreateDebugger/ExportTrace 诊断调试
  - **全局实例访问**
    - UniFlowEngine() 函数
    - InitializeUniFlow/FinalizeUniFlow
  - **事件类型**
    - OnWorkflowStart, OnWorkflowComplete
    - OnStepExecute, OnError

#### TASK-1002: 集成示例代码
- 新建 Examples/Integration/UniFlowIntegrationDemo.pas (~440 行)
  - **Demo 1: 基础请求处理**
- 打招呼/帮助/再见 意图识别
  - **Demo 2: 工作流加载与执行**
- JSON 加载工作流
- 执行带条件分支的工作流
- 普通用户 vs VIP 用户
  - **Demo 3: 会话管理**
- 创建会话、添加消息
    - 多轮对话演示
  - **Demo 4: 意图识别**
- 自定义意图注册
    - 多种输入测试
- **Demo 5: 诊断与调试**
    - 追踪级别配置
    - 轨迹导出

#### TASK-1003: 端到端验证
- 测试创建 Examples/Integration/UniFlowE2ETest.pas (~727 行)
- **测试工作流定制**
    - WORKFLOW_SIMPLE_QA - 简单问答工作流
- WORKFLOW_CONDITIONAL - 条件分支工作流
- WORKFLOW_LOOP - 循环工作流
- WORKFLOW_ERROR_HANDLING - 错误处理工作流
- **测试用例 (12个？)**
    - Test_SimpleQA_ValidInput - 有效输入测试
    - Test_SimpleQA_EmptyInput - 空输入回退测试
- Test_Conditional_Greeting - 条件分支-问候
    - Test_Conditional_Question - 条件分支-提问
    - Test_Conditional_Unknown - 条件分支-默认
    - Test_ErrorHandling_Success - 错误处理-成功
    - Test_ErrorHandling_Fallback - 错误处理-回退
    - Test_Commander_IntentRecognition - 意图识别
- Test_Session_Persistence - 会话持久化
    - Test_MultiTurn_Conversation - 多轮对话
- Test_Workflow_Registration - 工作流注册
- Test_Diagnostics_Available - 诊断可用性
  - **测试报告**
    - 通过/失败统计
    - 执行时间跟踪
    - 退出码支持 (CI 集成)

### P4 Direction A 代码统计

|| 模块 | 文件 | 行数 |
||------|------|------|
|| DeepBase.UniFlow | pas | ~769 |
|| Integration Demo | pas | ~440 |
|| E2E Test | pas | ~727 |
|| **Direction A 合计** | **3 files** | **~1,940** |

---

## P4 Direction C: Event Sourcing 架构对齐

### 2025-12-05

#### TASK-1020: UniFlowEvent 核心类型 定义
- 已创建 Source/EventSourcing/UniFlow.EventSourcing.Types.pas (~800 行)
  - **基础类型**
    - `TUniFlowType` - 流程类型 (Build/Maintain/NlConvert/SceneChange/CodeChange/Custom)
- `TUniFlowStatus` - 流程状态(Created/Running/WaitingUser/Succeeded/Failed/Cancelled)
    - `TEventStatus` - 事件状态(Started/Succeeded/Failed)
  - **TUniFlowEvent - 事件流**
    - 全局唯一 ID、流程ID、序列号
    - 步骤名、来源模块、时间戳
    - Payload (JSON)、ErrorCode、Metadata
    - 工厂方法: Started/Succeeded/Failed
    - 序列号反序列化/克隆
  - **TUniFlowSnapshot - 快照对象**
    - 版本号、事件序列号、状态JSON
  - **TFlowInstance - 流程实例对象**
    - 状态机迁移规则
    - CreateNew/Fork 工厂方法
  - **TUniFlowNode - 节点对象**
    - 节点路径解析
  - 辅助函数: FlowTypeToString, StringToFlowType ?

#### TASK-1021: Event Store 事件存储 ?
- 创建 Source/EventSourcing/UniFlow.EventSourcing.Store.pas (~1,120 行)
  - **查询参数**
    - `TEventQuery` - 事件查询 (序列号范围/时间范围/步骤/状态)
    - `TSnapshotQuery` - 快照查询 (版本/最新序列号之间)
    - `TAppendResult` - 追加结果
  - **IEventStore - 事件存储接口**
    - Append/AppendBatch - Append-Only 语义
    - ReadEvents/GetLastEvent/GetEventCount
    - SaveSnapshot/GetSnapshot
    - GetAllFlowIds/FlowExists
  - **TMemoryEventStore - 内存实现**
    - 线程安全 (TCriticalSection)
    - 完整查询支持
  - **TFileEventStore - 文件实现**
    - JSON 文件持久化
    - 可选缓存
  - **TSnapshotPolicy - 快照策略**
    - 每N个事件生成快照(默认 10)
- 终态强制生成
- **TSnapshotManager - 快照管理器**
  - **TEventStream - 事件流迭代器**

#### TASK-1022: FlowInstance Manager 流程实例管理 
- 创建 Source/EventSourcing/UniFlow.EventSourcing.Instance.pas (~900 个
  - **结果类型**
    - `TCreateFlowParams` - 创建参数
    - `TEmitResult` - 事件发布结果
- `TTransitionResult` - 状态迁移结果
- **TFlowInstanceManager - 核心管理器**
    - CreateFlow - 创建流程实例
- GetInstance - 获取实例 (从快照/事件重建)
    - EmitEvent - 发布事件 (状态变化的唯一入口)
    - EmitStarted/EmitSucceeded/EmitFailed - 便捷方法
- TransitionTo - 状态迁移
    - StartFlow/CompleteFlow/FailFlow/CancelFlow - 生命周期
    - PauseFlow/ResumeFlow - 暂停/恢复
    - GetAllFlows/GetActiveFlows - 查询
    - 自动快照生成
- **TFlowBuilder - 流式 API 构建器**
    - WithType/WithSource/WithUser/WithSession
    - Build/BuildAndStart
  - **TFlowSession - 流程会话**
    - BeginStep/EndStep/FailStep - 步骤管理
    - Complete/Fail - 流程结束

#### TASK-1023: Event Replay & Fork 事件重放与分叉
- 创建 Source/EventSourcing/UniFlow.EventSourcing.Replay.pas (~1,290 个
  - **状态聚合器**
- `IStateAggregator` - 聚合器接口
    - `TDefaultStateAggregator` - 默认实现 (收集步骤历史)
- `TCustomStateAggregator` - 自定义实现 (回调函数)
- **TEventReplayer - 事件重放器**
    - ReplayAll - 全量重放
    - ReplayTo - 重放到指定序列号
- ReplayFromSnapshot - 从快照开始重放
    - ReplayRange - 范围重放
    - ReplayIncremental - 增量重放
- **TFlowForker - 流程分叉器**
    - `TForkOptions` - 分叉选项
- Fork - 从历史版本分叉
    - ForkAt - 从指定序列号分叉
    - CloneFlow - 完整克隆
    - CreateWhatIf - 创建 what-if 临时分支
- **THiDeepStoryBrowser - 历史浏览器**
- `THiDeepStoryPoint` - 历史节点
    - GetAllPoints/GetPointAt/GetPointsInRange/GetPointsByStep
- **TTimeTravelDebugger - 时间旅行调试器**
- MoveFirst/MoveLast - 跳转到首/末
    - StepForward/StepBackward - 单步前进/后退
    - GoTo - 跳转到指定序列号
- GetCurrentEvent/GetCurrentState - 获取当前状态
- **TDiffCalculator - 差异计算器**
    - CalculateDiff - 计算两个状态的差异
    - CalculateVersionDiff - 计算两个版本间的差异

### P4 Direction C 代码统计

|| 模块 | 文件 | 行数 |
||------|------|------|
|| EventSourcing.Types | pas | ~800 |
|| EventSourcing.Store | pas | ~1,120 |
|| EventSourcing.Instance | pas | ~900 |
|| EventSourcing.Replay | pas | ~1,290 |
|| **Direction C 合计** | **4 files** | **~4,110** |

### Event Sourcing 设计原则

1. **单一事实源** - 所有状态变化通过 UniFlowEvent 体现
2. **Append-Only** - 事件只能追加，不能修改或删除
3. **可重建** - 任何状态都可从事件序列重建
4. **可分叉** - 从历史版本创建新流程
5. **CQRS** - 写路径(EmitEvent) 和读路径 (Snapshot+Replay) 分离
6. **快照策略** - 每10个事件或终态时生成快照

---

## Delphi 12 迁移 [DELPHI12-001]

### 2025-12-05

#### DeepBase Core 模块 Delphi 12 兼容性修复

**进度**: 75/78 (96%)

##### 已修复模块(本次会话)
- •**DeepBase.IoC.pas**
  - 使用 PTypeInfo 本地变量解决 `TypeInfo(T)^.Kind` 问题
  - 使用 `TValue.AsType<T>` 代替直接类型转换 `T(Instance)`
- 简化 RegisterSingleton 方法中的类型检查
- ?**DeepBase.StateMachine.pas**
  - ?`StateToString`/`TriggerToString` 从本地函数重构为私有类方法
  - 修复 E2570 Local procedure in generic method 错误
  - 修复 NI19024 内部编译器错误

##### 已修复模块(前几次会议)
- ?**DeepBase.Template.pas** - 内联变量声明、属性访问器
- ?**DeepBase.CloudSync.pas** - HTTP 空请求体、TThread.Queue
- ?**DeepBase.Diff.pas** - TObjectList → TList (记录类型)
- ?**DeepBase.FileWatcher.pas** - TEvent 替代 TTimer、TTask.Create

##### 待修复模式(3类 - 需较大重构)
- **DeepBase.Graph.pas** - 泛型类中多个本地过程 (TTree.Traverse 遍历
- **DeepBase.Net.pas** - Indy DNS API 完全重写
- **DeepBase.Serialization.pas** - ISerializer 接口架构重新设计

##### 修复模式总结
```
// 1. TStringDynArray 缺少单元
uses System.Types;

// 2. 线程同步
TThread.Synchronize(nil, proc) 或TThread.Queue(nil, proc)

// 3. 异步任务
TTask.Run(proc) 或TTask.Create(proc).Start

// 4. 泛型类中本地过程
procedure TMyClass<T>.Method;
  function LocalFunc: string; // E2570!
end;
建议重构为私有类方法

// 5. 记录类型容器
TObjectList<TMyRecord> 改用TList<TMyRecord>

// 6. 记录属性
Inc(LRecord.Count); LCount := LRecord.Count; Inc(LCount); LRecord.Count := LCount;

// 7. 注释格式
{*...*} (*...*)
```

##### Git 提交
- `3112417` - fix(Core): Delphi 12 compatibility - IoC, StateMachine, Diff, FileWatcher

---

## P4 Direction D: 分析与可视化

### 2025-12-05

#### TASK-1032: Analytics API 后端？
- ?创建 Source/Analytics/UniFlow.Analytics.pas (~1,546 行
  - **时间范围类型**
    - `TTimeRange` - 时间范围 (Today/Yesterday/Last7Days/Last30Days/ThisMonth/LastMonth/Custom)
    - `TTimeGranularity` - 粒度 (Minute/Hour/Day/Week/Month)
  - **统计结构**
    - `TBasicStats` - 基础统计 (Count/Sum/Min/Max/Avg/StdDev)
    - `TWorkflowStats` - 按工作流统计
    - `TStepStats` - 按步骤统计
    - `TTimeBucketStats` - 时序分桶统计
    - `TErrorStats` - 错误统计
    - `TLLMUsageStats` - LLM 使用统计
    - `TExecutionSummary` - 执行摘要
    - `TTrendReport/TTrendPoint` - 趋势报告
  - **TAnalyticsEngine - 核心分析引擎**
    - GetExecutionSummary - 获取执行摘要
    - GetWorkflowStats - 按工作流统计
    - GetStepStats - 按步骤统计
    - GetTimeSeriesStats - 时序统计
    - GetErrorStats - 错误统计
    - GetSuccessRateTrend/GetExecutionCountTrend/GetLatencyTrend - 趋势数据
    - GetHotspotSteps/GetFailureHotspots - 热点分析
    - DetectAnomalies - 异常检测
    - ExportFullReport/ExportHTMLReport - 报告导出
    - 缓存支持 (TTL 可配)
  - **TDashboardAPI - REST 风格 API**
    - /overview - 概览数据
    - /workflows - 工作流统计
    - /timeline - 时间线数据
    - /errors - 错误列表
    - /trends - 趋势数据
    - 参数解析 (时间范围/粒度)

#### TASK-1030: Analytics Dashboard UI？
- ?创建 Analytics/index.html (~235 行
  - 仪表板布局 (Header/Summary Cards/Charts/Tables/Timeline)
   - 时间范围选择器 (Today/7Days/30Days/Custom)
  - 自定义日期范围模态框
  - 导出/刷新按钮
- ?创建 Analytics/css/dashboard.css (~712 行
  - Catppuccin Mocha 暗色主题
  - CSS 变量系统 (语义颜色/间距/圆角)
  - Summary Cards / Chart Cards / Tables 样式
  - Modal / Form / Button / Badge 组件
  - 响应式布局 (1400/1200/768/480 断点)
  - 自定义滚动条样式
- ?创建 Analytics/css/charts.css (~479 行
  - SVG 图表基础样式
  - Line/Bar/Donut/Gauge/Histogram 图表样式
  - Tooltip / Legend / Grid / Axis 样式
   - Loading / Empty 状态
  - Sparkline / Heatmap 样式
  - Progress Bar 样式

#### TASK-1031: Event Timeline UI 组件
- 创建 Analytics/js/utils.js (~451 文件)
  - 日期格式函数(formatDate/formatDuration/relativeTime/getTimeRange)
  - 数字格式工具(formatNumber/formatPercent/formatBytes/compactNumber)
  - 统计计算 (calcStats/percentile)
  - 颜色工具 (getStatusColor/interpolateColor)
  - DOM 工具 (createSVGElement/createElement)
  - 节流/防抖 (debounce/throttle)
  - 数据处理 (groupBy/sortBy/generateTimeBuckets)
  - API 工具 (fetch/buildQueryString)
  - LocalStorage 工具
- 创建 Analytics/js/charts.js (~786 文件)
  - lineChart - 折线图(多系列/面积填充/网格/Tooltip)
  - barChart - 柱状图(水平/垂直/动画)
  - histogram - 用于延迟分布
  - donutChart - 环形图(内径/圆心标签/图例)
- gaugeChart - 仪表盘(阈值颜色)
- sparkline - 迷你趋势图
- stackedBarChart - 堆叠柱状图
- ?创建 Analytics/js/timeline.js (~631 行)
  - Timeline 组件
    - init/setData/setFilter - 初始化与数据设置
    - zoomIn/zoomOut/reset - 缩放控制
    - render/renderEvent/renderAxis - 渲染
    - setupInteractions - 拖拽平移/滚轮缩放
  - Swimlane 分组显示
- 事件状态颜色编码
  - 时间轴自动格式化
- 事件选中与详情面板
- ?创建 Analytics/js/dashboard.js (~641 行)
  - Dashboard 主控制器
- 时间范围选择器
- 自动刷新 (30秒)
- 粒度选择器
    - 导出报告 (JSON)
- Demo 数据生成器
    - 随机执行历史
- 工作流统计
    - 错误统计
- 异常检测
  - UI 更新方法
    - updateSummaryCards - 摘要卡片
    - updateCharts - 图表
- updateWorkflowTable - 工作流表格
    - updateErrorTable - 错误表格
    - updateAnomalies - 异常列表
- updateTimeline - 时间线

### P4 Direction D 代码统计

|| 模块 | 文件 | 行数 |
||------|------|------|
|| UniFlow.Analytics | pas | ~1,546 |
|| index.html | html | ~235 |
|| dashboard.css | css | ~712 |
|| charts.css | css | ~479 |
|| utils.js | js | ~451 |
|| charts.js | js | ~786 |
|| timeline.js | js | ~631 |
|| dashboard.js | js | ~641 |
|| **Direction D 合计** | **8 files** | **~5,481** |

### 分析仪表板功能

1. **摘要卡片** - 总流程数/成功/失败/成功率/平均时长
2. **执行趋势图** - 成功/失败折线图，支持粒度切换
3. **成功率仪表盘** - 环形进度显示
4. **工作流统计表** - 执行次数/成功率/平均时长，支持搜索
5. **延迟分布图** - 直方图分析
6. **错误列表** - 错误率/消息/次数/影响工作流
7. **异常警报** - 自动检测高失败率/慢执行
8. **事件时间轴** - Swimlane 分组/缩放平移/事件选中

---

## P4 Direction F: 多租户支持

### 2025-12-05

#### TASK-1050~1052: 多租户核心功能模块
- 创建 Source/Tenant/UniFlow.Tenant.pas (~1,372 行)
  - **租户类型**
    - `TTenantStatus` - 租户状态(Active/Suspended/Archived/Deleted)
    - `TTenantPlan` - 租户计划 (Free/Basic/Professional/Enterprise)
  - **配额管理**
    - `TTenantQuota` - 配额配置
      - 流程配额: MaxActiveFlows/MaxFlowsPerDay/MaxEventsPerFlow
      - 存储配额: MaxStorageMB/MaxSnapshotsPerFlow
      - API 配额: MaxRequestsPerMinute/MaxRequestsPerDay
      - LLM 配额: MaxLLMRequestsPerDay/MaxTokensPerDay
      - 功能开关 AllowParallelExecution/AllowSubworkflows/AllowCustomSkills
    - 预设配额: Free/Basic/Professional/Enterprise/Unlimited
  - **使用量追踪**
    - `TTenantUsage` - 使用情况记录
      - 流程使用: ActiveFlows/FlowsToday/TotalFlows
      - 存储使用: StorageUsedMB/TotalEvents/TotalSnapshots
      - API 使用: RequestsThisMinute/RequestsToday
      - LLM 使用: LLMRequestsToday/TokensToday
  - **租户信息**
    - `TTenant` - 租户实体
      - Id/Name/DisplayName/Status/Plan
      - Quota/Usage
      - Metadata/Settings/OwnerUserId/ContactEmail
      - CheckQuota/IncrementUsage/IsActive
  - **租户隔离 EventStore**
    - `TTenantEventStore` - 租户隔离的事件存储包装器
      - 实现 IEventStore 接口
      - FlowId 前缀隔离
       - 自动配额检查
  - **租户存储接口**
    - `ITenantStore` - 租户存储接口
    - `TMemoryTenantStore` - 内存实现
  - **租户管理台**
    - `TTenantManager` - 租户管理
      - CreateTenant/GetTenant/UpdateTenant/DeleteTenant
      - SuspendTenant/ActivateTenant
      - ChangePlan/GetAllTenants/GetTenantsByStatus
       - GetEventStoreForTenant - 获取租户隔离的 EventStore
  - **租户上下文**
    - `TTenantContext` - 线程本地租户上下文
      - SetCurrent/GetCurrent/Clear
       - 用于请求处理时透明传递租户信息

### P4 Direction F 代码统计

|| 模块 | 文件 | 行数 |
||------|------|------|
|| UniFlow.Tenant | pas | ~1,372 |
|| **Direction F 后端合计** | **1 file** | **~1,372** |

#### TASK-1053: 租户控制台 Web UI 模块
- 创建 TenantConsole/index.html (~601 行)
  - 侧边栏导航(Dashboard/Tenants/Quotas/Usage/Workflows/Settings)
  - 仪表板视图(摘要卡片/图表/活动表格)
  - 租户管理视图 (筛选/CRUD 操作)
  - 配额管理视图 (按计划配置)
  - 使用统计视图 (趋势/排名)
  - 工作流视图 (状态筛选)
  - 设置视图 (系统配置)
  - 模态对话框 (租户创建/编辑/确认)
- 创建 TenantConsole/css/console.css (~1,176 行)
  - Catppuccin Mocha 暗色主题
  - CSS 变量 (颜色/间距/字体)
  - 侧边栏/头部/卡片/表格/表单/模态框/Toast 样式
  - 响应式断点(1200/768/480px)
  - 进度条/徽章/分页组件
- 创建 TenantConsole/js/utils.js (~658 行)
  - 日期工具 (format/relative/duration/getTimeRange)
  - 数字工具 (format/compact/percent/bytes)
  - DOM 工具 ($/$$, create/show/hide/addClass/reDeepMoveClass)
  - Storage (localStorage 封装)
  - EventBus 模块
  - 验证器(email/tenantName/required/range)
  - StatusMap (租户/计划/工作流状态配置)
  - ChartUtils (createSVG/lineChart/donutChart/barChart)
- 创建 TenantConsole/js/api.js (~646 行)
  - DemoData 生成器(租户/工作流趋势/活动)
  - API 方法: getDashboardOverview/getTenantDistribution/getFlowTrend
  - 租户 CRUD: getTenants/createTenant/updateTenant/deleteTenant/suspend/activate
  - 配额: getPlanQuota/updatePlanQuota
  - 使用: getUsageOverview/getUsageTrend/getUsageRanking
  - 工作流: getWorkflows/cancelWorkflow
  - 设置: getSettings/saveSettings
- 创建 TenantConsole/js/components.js (~512 行)
  - Toast 通知 (success/error/warning/info)
  - Modal (open/close/confirm)
  - Pagination 渲染器
  - 表格行渲染器 (tenant/workflow/activity/usageRanking)
- Loading / Empty 状态
  - Form 工具 (getData/setData/reset/validate)
  - Dropdown 填充辅助函数
- 新建创建 TenantConsole/js/console.js (~623 行)
  - AppState 管理
  - ViewManager 视图切换
- 各视图加载函数(dashboard/tenants/quotas/usage/workflows/settings)
- 事件绑定 (导航/筛选/表单/模态框)
- EventBus 处理逻辑(租户/工作流操作)

### Tenant Console 功能

1. **仪表板** - 租户总数/活跃租户/流程/API 调用数摘要卡片；租户分布环形图；流程趋势折线图；最近活动报表
2. **租户管理** - 状态/计划筛选；搜索；创建/编辑/删除租户；暂停/激活操作
3. **配额管理** - 按计划查看/编辑配额；流量/存储/API/LLM 配额配置
4. **使用统计** - 总览数据；使用趋势图；租户排名表清单
5. **工作流监控** - 状态筛选；搜索；取消操作
6. **系统设置** - 默认计划/会话超时/最大租户数等配置

### P4 Direction F 代码统计

|| 模块 | 文件 | 行数 |
||------|------|------|
|| UniFlow.Tenant | pas | ~1,372 |
|| index.html | html | ~601 |
|| console.css | css | ~1,176 |
|| utils.js | js | ~658 |
|| api.js | js | ~646 |
|| components.js | js | ~512 |
|| console.js | js | ~623 |
|| **Direction F 合计** | **7 files** | **~5,588** |

---

## P4 Direction E: 性能优化

### 2025-12-05

#### TASK-1040: 内存池优化
- 创建 Source/Performance/UniFlow.Performance.Pool.pas (~1,020 行)
  - `IPoolable` - 可池化对象接口
  - `TPoolStats` - 池统计数据
  - `TPoolConfig` - 池配置(Default/Small/Large 预设)
  - `TPooledItem<T>` - 池化对象包装
- `TObjectPool<T>` - 泛型对象池
    - Acquire/Release - 获取/释放对象
    - Warmup/Shrink/Clear - 预热/收缩/清空
- 对象重置器，验证器支持
- 专用类 `TJSONObjectPool`, `TStringBuilderPool`, `TStringListPool`
  - `TPoolManager` - 池管理器
- `TPooledScope<T>` - RAII 风格作用域

#### TASK-1041: JSON 解析加速
- 源创建 Source/Performance/UniFlow.Performance.JSON.pas (~1,760 行)
  - **流式解析**
    - `TJSONToken` - JSON Token 结构
- `TJSONStreamReader` - 流式 JSON 读取器
      - ReadToken - 逐个解析 Token
      - ForEach - 遍历回调
- SkipValue/ReadValue - 跳过/读取值
- `TJSONLinesReader` - JSON Lines 格式读取器
  - **路径提取**
- `TPathSegment` - 路径段(Property/Index/Wildcard/Recursive)
- `TJSONPathExtractor` - JSON Path 提取器
      - 支持 `$.path.to.value` 语法
- Extract/ExtractAll - 单值/多值提取
- ExtractString/Integer/Boolean - 类型化提取
  - **解析缓存**
- `TJSONCacheItem` - 缓存项
    - `TJSONCache` - JSON 解析结果缓存
      - LRU 淘汰策略
      - TTL 过期
- 内容哈希缓存器
  - **高效构建**
- `TJSONBuilder` - 流式 JSON 构建器
      - BeginObject/EndObject - 对象边界
      - BeginArray/EndArray - 数组边界
- WriteString/Integer/Float/Boolean/Null - 值写入
      - WriteJSON/WriteRaw - 原始 JSON 写入
  - 工具函数: EscapeJSONString, UnescapeJSONString, EstimateJSONSize, CloneJSON, MergeJSON

#### TASK-1042: 并发执行优化 任务
- 计划创建 Source/Performance/UniFlow.Performance.Concurrent.pas (~1,600 行)
  - **工作窃取队列**
    - `TWorkStealingQueue<T>` - 双端队列
      - Push - 本地推入
- Pop - 本地弹出 (无竞争)
      - Steal - 远程窃取
- **增强线程池**
- `TWorkItem` - 工作项 (ID/优先级/超时)
    - `TWorkerThread` - 工作线程 (LocalQueue/统计)
- `TThreadPoolStats` - 线程池统计
- `TThreadPoolConfig` - 线程池配置
    - `TEnhancedThreadPool` - 增强线程池
      - Submit - 提交任务
      - SubmitTo - 提交到指定工作线程
      - WaitAll - 等待所有任务
      - 动态线程数调整
      - 工作窃取支持
  - **Future/Promise**
    - `TFutureBase` - Future 基类
    - `TFuture<T>` - 泛型 Future
    - `TPromise<T>` - Promise
  - **并行执行器**
    - `TParallelResult<T>` - 并行结果
    - `TParallelExecutor` - 并行执行器
      - ForEach - 并行遍历
      - Map - 并行映射
      - Any - 任一完成
      - All - 全部完成
      - Batch - 批量执行
  - **异步工作流**
    - `TAsyncStep` - 异步步骤
    - `TAsyncWorkflowExecutor` - 异步工作流执行器
      - AddStep/AddDependency - 步骤/依赖管理
      - Start/WaitAll - 执行控制
  - 全局函数: GlobalThreadPool, ParallelFor

#### TASK-1043: 缓存策略 方案
- 新创建 Source/Performance/UniFlow.Performance.Cache.pas (~1,320 行)
  - **LRU 缓存**
    - `TLRUNode<K,V>` - 双向链表节点
    - `TCacheStats` - 缓存统计
    - `TCacheConfig` - 缓存配置
    - `TLRUCache<K,V>` - 泛型 LRU 缓存
      - Get/Put/Remove - 基本操作
      - TTL 过期
      - 最大字节数限制
      - 淘汰回调
    - `TStringCache` - 字符串缓存(GetOrCompute)
  - **工作流定义缓存**
    - `TCachedWorkflowDef` - 缓存的工作流定义
     - `TWorkflowDefinitionCache` - 工作流定义缓存
       - LoadFromFile - 文件加载 (自动变更检测)
       - LoadFromString - 字符串加载
      - Invalidate/InvalidateAll - 失效
       - Preload - 预加载
  - **Schema 缓存**
     - `TCachedSchema` - 缓存的Schema
    - `TSchemaCache` - Schema 缓存
      - Get/LoadSchema/Register - 获取/加载/注册
  - **多级缓存**
    - `TCacheLevel` - 缓存级别 (L1/L2/L3)
     - `TMultiLevelCache` - 多级字符串缓存
       - 命中时自动提升级别
   - **缓存管理器**
    - `TCacheManager` - 统一缓存管理
      - WorkflowCache/SchemaCache/StringCache - 内置缓存
       - RegisterCache - 注册自定义缓存
      - Warmup - 预热
      - GetAllStats - 统计信息

### P4 Direction E 代码统计

|| 模块 | 文件 | 行数 |
||------|------|------|
|| UniFlow.Performance.Pool | pas | ~1,020 |
|| UniFlow.Performance.JSON | pas | ~1,760 |
|| UniFlow.Performance.Cache | pas | ~1,320 |
|| UniFlow.Performance.Concurrent | pas | ~1,600 |
||| **Direction E 合计** | **4 files** | **~5,700** |

---

## P4 Direction G: 插件系统

### 2025-12-05

#### TASK-1060: 插件接口定义
- 创建 Source/Plugin/UniFlow.Plugin.Intf.pas (~830 行)
  - **基础类型**
    - `TPluginCapability` - 能力标记 (ActionExecutor/Validator/EventHandler/Transformer)
     - `TPluginStatus` - 插件状态(Unloaded/Loaded/Active/Failed/Disabled)
     - `TPluginInfo` - 插件元数据(Id/Name/Version/Dependencies)
    - `TPluginResult` - 执行结果 (OK/Fail 工厂方法)
   - **上下文接口**
    - `IPluginLogger` - 日志接口 (Trace/Debug/Info/Warning/Error)
    - `IPluginConfig` - 配置接口 (GetString/Integer/Boolean/JSON)
- `IPluginServices` - 服务定位器
    - `IPluginContext` - 运行时上下文
  - **插件接口**
- `IUniFlowPlugin` - 主插件接口(Initialize/Finalize/GetExecutors)
- `IPluginActionExecutor` - 自定义Action执行器
    - `IPluginValidator` - 自定义验证器
- `IPluginEventHandler` - 事件处理器
- `IPluginTransformer` - 数据变换器
  - **基类**
    - `TBaseUniFlowPlugin` - 插件基类 (RegisterActionExecutor/Validator/...)
  - 常量: UNIFLOW_PLUGIN_VERSION = 1

#### TASK-1061: 插件加载
- 请创建 Source/Plugin/UniFlow.Plugin.Loader.pas (~1,604 行)
- **上下文实现**
    - `TPluginLogger` - 默认日志实现
    - `TPluginConfig` - JSON 配置实现 (LoadFromFile/SaveToFile)
- `TPluginServices` - 服务定位器实现
- `TPluginContextImpl` - 上下文实现
- **BPL 加载器**
    - `TBPLPluginLoader` - Delphi 包加载器
      - LoadPackage/UnloadPackage
      - 线程安全
- **DLL 加载器**
- `TDLLPluginLoader` - 原生 DLL 加载器
      - 导出函数: GetUniFlowPlugin
      - LoadLibrary/FreeLibrary
- **统一加载器**
    - `TPluginLoader` - 统一加载接口
      - LoadPlugin/UnloadPlugin/UnloadAll
      - ScanDirectory/DiscoverPlugins
      - GetAllActionExecutors/Validators/EventHandlers/Transformers
      - FindActionExecutor/FindValidator
- 版本兼容性检测
  - 异常隔离

#### TASK-1062: 插件注册表
- 请创建 Source/Plugin/UniFlow.Plugin.Registry.pas (~1,338 行)
  - **依赖解析**
    - `TDependencyNode` - 依赖图节点
    - `TDependencyResult` - 解析结果 (MissingDeps/CircularDeps)
    - `TPluginDependencyResolver` - 依赖解析器
      - BuildGraph - 构建依赖图
      - DetectCycle - 环检测
      - TopologicalSort - 拓扑排序
  - **生命周期管理**
    - `TLifecycleState` - 状态枚举*
    - `TPluginLifecycleManager` - 生命周期管理器
      - BeginInitialize/EndInitialize
      - BeginFinalize/EndFinalize
      - GetInitOrder/GetFinalizeOrder
  - **插件注册表**
    - `TPluginRegistry` - 中央插件管理器
      - RegisterPlugin/UnregisterPlugin/UnregisterAll
      - LoadAndRegister/DiscoverAndRegister
      - EnablePlugin/DisablePlugin
      - GetPluginsByCapability
      - GetActionExecutors/Validators/EventHandlers/Transformers
  - 全局实例: PluginRegistry()/InitializePluginRegistry/FinalizePluginRegistry

#### TASK-1063: 示例插件清单
- 请创建 Source/Plugin/UniFlow.Plugin.Examples.pas (~873 行)
  - **自定义Action执行器**
    - `TDelayActionExecutor` - 延迟执行 Action
      - 参数: milliseconds (0-60000)
      - 返回: delayed_ms, actual_ms
    - `TEmailActionExecutor` - 邮件发送Action (Mock)
      - 参数: to, subject, body
      - 返回: message_id, sent_at
    - `THttpGetActionExecutor` - HTTP GET Action
      - 参数: url, timeout_ms
      - 返回: status_code, body
  - **自定义验证器**
    - `TChinaPhoneValidator` - 中国手机号验证器
      - 11位数字、以1开头
      - 严格模式: 运营商前缀检测
- `TIDCardValidator` - 中国身份证验证
      - 18位、校验码计算
      - 出生日期验证
    - `TEmailValidator` - 邮箱格式验证
  - **示例插件**
- `TCustomActionsPlugin` - 自定义Action 插件
    - `TCustomValidatorsPlugin` - 自定义验证器插件
    - `TCombinedExamplePlugin` - 组合示例插件
  - 工厂函数: CreateCustomActionsPlugin/CreateCustomValidatorsPlugin/CreateCombinedExamplePlugin

### 插件系统设计原则

1. **最小侵入** - 插件不修改核心代码
2. **安全隔离** - 插件错误不影响宿主
3. **版本兼容** - 接口版本化，向后兼容
4. **热加载** - 支持运行时加载/卸载
5. **依赖注入** - 通过 Context 提供服务

### P4 Direction G 代码统计

|| 模块 | 文件 | 行数 |
||------|------|------|
|| UniFlow.Plugin.Intf | pas | ~830 |
|| UniFlow.Plugin.Loader | pas | ~1,604 |
|| UniFlow.Plugin.Registry | pas | ~1,338 |
|| UniFlow.Plugin.Examples | pas | ~873 |
|| **Direction G 合计** | **4 files** | **~4,645** |

---

## P4 Direction B: 中文文档补全

### 2025-12-05

#### TASK-1010: 中文快速入门指南
- 新建创建 docs/zh/quick-start.md (~353 字)
  - 翻译完整快速入门指南
  - 包含安装、工作流创建、LLM 集成
- 包含会话管理、错误处理、诊断
- 保留所有代码示例

#### TASK-1011: 中文 Workflow 格式定义
- 创建 docs/zh/workflow-definition.md (~653 字符)
- 翻译完整工作流 JSON 格式参数类型
- 翻译所有步骤类型（Action/Condition/Loop/Parallel/Wait/Subworkflow/End 等）
- 翻译所有动作类型（LLM/Skill/HTTP/Script/Assign/Log/Guard 类型）
- 翻译表达式语法、触发器、钩子
- 包含完整客户支持工作流示例

#### TASK-1012: 中文 Skill 开发指南
- 任务创建 docs/zh/skills-development.md (~724 字)
- 翻译 Python Skill 开发指南
- 翻译 Node.js Skill 开发指南
- 翻译 API 契约、注册、最佳实践
- 翻译测试、部署（Docker Compose/Kubernetes示例）
- 包含代码执行和知识搜索示例 Skill

#### TASK-1013: 中文部署指南
- ✓创建 docs/zh/deployment.md (~858 字)
  - 翻译架构概览
  - 翻译 Docker 部署（docker-compose.yml、Nginx 配置）
  - 翻译 Kubernetes 部署（Namespace/ConfigMap/Secrets/Deployment/Ingress/HPA）
  - 翻译环境配置、监控（Prometheus/Grafana）
  - 翻译安全（网络策略、Pod 安全、API 认证）
  - 翻译备份恢复、故障排除、性能调优
  - 包含部署检查清单

### P4 Direction B 代码统计

|| 文件 | 类型 | 行数 |
||------|------|------|
|| quick-start.md | 中文文档 | ~353 |
|| workflow-definition.md | 中文文档 | ~653 |
|| skills-development.md | 中文文档 | ~724 |
|| deployment.md | 中文文档 | ~858 |
|| **Direction B 合计** | **4 files** | **~2,588** |

---

## 项目完成总结

### 2025-12-05 - DeepFlow v1.0 开发完毕 🎉

#### 已完成里程碑

| 里程碑| 内容 | 状态|
|---------|------|------|
| M1 | 核心框架 (Phase 1-3) | 完成|
| M2 | 完整流程 (Phase 4-6) | 完成|
| M3 | 生产就绪 (Phase 7-8) | 完成|
| P2 | 可选增强(Audit/Metrics/Skills/Editor) | 完成|
| P3 | 维护任务 (SQLite/WebSocket/CI/Docs) | 完成|
| P4-A | DeepBase 集成 | 完成|
| P4-B | 中文文档 | 完成|
| P4-C | Event Sourcing | 完成|
| P4-D | 分析与可视化 | 完成|
| P4-E | 性能优化 | 完成|
| P4-F | 多租户支持| 完成|
| P4-G | 插件系统 | 完成|

#### 最终代码统计

**总计: ~82,000 行*

| 类型 | 文件名| 行数 |
|------|--------|------|
| Pascal (Source) | 42 | ~48,000 |
| Pascal (Examples/Tests) | 6 | ~3,500 |
| Python Skills | 4 | ~1,450 |
| Node.js Skills | 7 | ~1,100 |
| Web Editor | 11 | ~4,500 |
| Editor Tests | 7 | ~2,300 |
| Analytics Dashboard | 8 | ~4,900 |
| Tenant Console | 6 | ~4,200 |
| CI/CD | 4 | ~550 |
| English Docs | 6 | ~2,250 |
| Chinese Docs | 4 | ~2,590 |

#### 核心模块

1. **Workflow Engine** - 工作流定义、执行、状态管理
2. **AI Adapter** - LLM 提供商集成 (OpenAI/Anthropic/Azure/Ollama)
3. **Session Manager** - 多轮会话管理
4. **Skill System** - Python/Node.js 外部技能服务
5. **Security** - 输入过滤、速率限制、内容安全
6. **Diagnostics** - 追踪、调试、错误收集
7. **Audit** - 审计日志记录
8. **Metrics** - 性能指标收集
9. **Event Sourcing** - 事件存储与回放
10. **Multi-Tenant** - 租户隔离与配置
11. **Plugin System** - 动态插件加载
12. **Performance** - 缓存、连接池、并发优化

#### Web 前端

1. **Workflow Editor** - JSON 工作流编辑器
2. **Analytics Dashboard** - 执行分析仪表板
3. **Tenant Console** - 多租户管理控制台

#### 文档

- 英文文档: Quick Start / Workflow Definition / Skills Development / Deployment
- 中文文档: 快速入门 / 工作流定义 / Skill 开发 / 部署指南

---

**DeepFlow Workflow Engine v1.0 - 开发完成*

---

## 2026-08-06: DeepFlow 正名 + 术语纠正 (工单 WO-20260806-0001-luoji)

### 背景
项目从代号 UniFlow 正名为 DeepFlow，文件名/目录/分支已更新，但文档正文与代码 unit 名未跟上。核查发现文档概念层确有两层架构：上层角色协作引擎 UpFlow(原 UniFlow 大写)、下层事件溯源引擎 deepFlow(原 uniFlow 小写)。

### 完成内容
- **文档正名**: 73 篇 .md 正文语义替换，项目名 DeepFlow、上层 UpFlow、下层 deepFlow
- **03.07 自指修复**: 标题修正为两层关系说明，修正对比表/命名约定
- **代码 unit 改名**: 68 个 .pas 的 unit/program 声明 + uses 引用(127处) + 注释项目名全改 DeepFlow.*
  - 类型标识符 560 处保留 (TUniFlowXxx/UniFlowClient 等，另起任务)
- **schema URI 纠正**: $id uniflow:// 转 deepflow://、URL 转 docs.deepflow.ai、author 转 DeepFlow Team
- **DeepDeep 乱码修复**: 9 形态 73 处 (DeepDeepDeepDeepDeepInsight 转 DeepInsight 等)
- **simple_qa 修复**: 23 处 UTF-8 损坏逐字节还原 + 补引号
- **冗余清理**: 3 个冗余 prompt 删除 + Editor 加 favicon
- **ADR 备案**: ADR-002 已批准

### 验证
- tools/verify-term-rename.py 确定性脚本 T1-T6 全 PASS
- dcc32 编译验证零改名回归 (T7)
- release_ready = true

### 交付 commit
- f7a9b2f2: 术语纠正 + 两层命名 + ADR-002
- 77b750c6: unit 改名 + simple_qa 修复
- 3902526a: 冗余清理 + favicon

---

## 2026-08-07: 类型标识符重命名 (TASK-0101)

### 背景
ADR-002 正名后，68 个 .pas 的 unit/program/uses 已改 DeepFlow.*，但类型标识符 (TUniFlowXxx/IUniFlow/etc.) 560 处保留，与文件名/unit 名不一致。本任务统一类型标识符。

### 方法与工具
- 新建 `Tools/rename-identifiers.py`: 字节级替换 (UniFlow 是纯 ASCII, 不依赖文件编码)
- 作用域: Source/ + Examples/ 下 .pas/.py/.js/.html/.md
- 规则: UniFlow→DeepFlow, UNIFLOW→DEEPFLOW, uniflow→deepflow

### 完成内容
- **25 个文件, 477 处替换** (440 .pas + 37 .py/.html/.js/.md)
- 类型: TUniFlowType→TDeepFlowType, TUniFlowEvent→TDeepFlowEvent, TUniFlowAdapter→TDeepFlowLLMAdapter 等
- 枚举值 (uftBuild/ufsCreated) 保留 (缩写, 非 UniFlow 扩展)
- `--verify`: 零残留 UniFlow 引用

### 验证
- 一致性校验: 旧类型 0 处, 新类型 493 处
- 字节级替换不触碰编码, 未引入新乱码

### 交付
- 本分支 (deepframes-docs-review-fixes) 待 commit

---

## 2025-12-07: P7 远期规划 (未启动，归档备查)

> 以下为 2025-12 规划的 P7 企业级远期任务，从未启动。TASK-4000 编号为旧体系，已由 2026 年 TASK-01xx 新体系取代。归档备查。

### P7-A: 企业级功能
| 任务 | 描述 | 复杂度 |
|------|------|--------|
| TASK-4001 | SSO/SAML/OAuth2 集成 | High |
| TASK-4002 | 工作流审核/人工介入节点 | Medium |
| TASK-4003 | 企业级审计合规(SOC2/GDPR) | High |
| TASK-4004 | 多数据中心容灾 | High |

### P7-B: 开发体验优化
| 任务 | 描述 | 复杂度 |
|------|------|--------|
| TASK-4010 | 工作流 DSL 语言设计 | High |
| TASK-4011 | VS Code / IDE 插件 | Medium |
| TASK-4012 | CLI 工具完善 | Low |
| TASK-4013 | SDK (Python/Go/TypeScript) | Medium |

### P7-C: 生态集成
| 任务 | 描述 | 复杂度 |
|------|------|--------|
| TASK-4020 | Webhook 运营商集成(Stripe/Twilio/SendGrid) | Medium |
| TASK-4021 | 低代码平台集成(Retool/Appsmith) | Medium |
| TASK-4022 | BI 工具集成(Metabase/Superset) | Low |
| TASK-4023 | 工单系统集成(Jira/ServiceNow) | Medium |

### P7-D: 性能与质量
| 任务 | 描述 | 复杂度 |
|------|------|--------|
| TASK-4030 | 工作流执行回放(Replay/Debug) | High |
| TASK-4031 | 性能基线自动化 | Medium |
| TASK-4032 | 混沌工程测试 | High |
| TASK-4033 | 全链路压测平台 | Medium |

---

## 2026-08-07: 文档与代码状态对齐完成

> **任务**: 将已完成的任务从 tasks.md 移入 history.md，记录新发现的 bug 到 bugfix.md，更新 tasks.md 为待办状态

### 完成情况总结

#### ✅ 已归档的工单 (WO-20260806-0001-luoji)
**执行日期**: 2026-08-06  
**提交 commit**: f7a9b2f2, 77b750c6, 3902526a

| 子任务 | 状态 | Commit |
|--------|------|--------|
| R1 | 文档正文项目名统一 (73 篇 .md) | 已完成 | f7a9b2f2 |
| R2 | 修复 03.07 自指错误 | 已完成 | f7a9b2f2 |
| R3 | 代码 unit 名同步改名 (68 个.pas) | 已完成 | 77b750c6 |
| R4 | uses 引用同步改名 (127 处) | 已完成 | 77b750c6 |
| R5 | schema URI 与 URL 纠正 | 已完成 | f7a9b2f2 |
| R6 | 组件名中英并列 | 已完成 | f7a9b2f2 |
| R7 | 术语表扩写为权威基准 | 已完成 | f7a9b2f2 |
| R8 | ADR 备案 | 已完成 | f7a9b2f2 |

#### ✅ 已完成任务 (TASK-0104)
**提交 commit**: 3902526a
- 清理 code_review/qa_assistant/system_default 3 个冗余 prompt
- Editor/index.html 添加 favicon

#### ✅ 已完成任务 (TASK-0101)
**提交 commit**: fb6fbadf
- 25 个代码/模板文件 477 处类型标识符重命名
- TUniFlowXxx → TDeepFlowXxx 字节级替换，零残留
- Tools/rename-identifiers.py 专用工具脚本验证

### 发现的新问题

#### 🐛 BUG-2026-007: 39 个.pas 文件 UTF-8 损坏 (新增发现)
- **严重程度**: Critical (24 个阻碍编译)
- **状态**: pending (已在 bugfix.md 详细记录)
- **关联任务**: TASK-0102 的一部分

### 下一步待办

详见 updated [tasks.md](d:\_Progs\02Business\DeepFlow\tasks.md):
- **TASK-0102**: .pas UTF-8 损坏修复 (高优先级)
- **TASK-0103**: 外部 DeepBase.*依赖配置

---

## 2026-08-07: Delphi 编译完整修复里程碑

> **执行任务**: TASK-0104 (Source 目录全量编译) + 9 个子任务
> **提交 commit**: 本次会话完成所有修复

### 背景与挑战

**初始状态**: Source 目录 128 个 .pas 文件，编译错误集中在 Tests 三文件 (Benchmark/E2E/Executor)，共 38+ 处 API 误用。

**核心问题**: 
- TWorkflowStep.Action/Branches/Expression 只读属性误写赋值
- TConditionExpression/TConditionBranch API 不匹配 (使用不存在的 Expression/Branches/DefaultStep/Operator/Value/NextStep)
- TWorkflowContext.Create 参数不足 (缺 WorkflowId/InstanceId)
- TJSONObject.EnumerateNames 不存在 (应为 TJSONPair 迭代)
- Assert.WillRaise DUnitX 重载匹配失败
- TTask.Create→TTask.Run 模式转换
- System.SyncObjs/System.Threading uses 缺失
- dcu 目录未加入 -U 搜索路径导致 F2613

### 修复记录

#### ✅ TASK-0104: Source 目录全量编译通过
**最终状态**: `dcc32.exe` 编译 `Source\DeepBase.DeepFlow.pas`,零 Error,仅 Warnings/Hints(W1057/H2077/H2164)

#### 子任务完成情况

| 子任务 | 主要修复内容 | 结果 |
|--------|-------------|------|
| fix-nlwf | NLWorkflowGen.pas implicit forward + trailing comma | 已修复 |
| fix-utf8 | 128 处代码字符串 UTF-8 损坏批量修复 | 已修复 |
| fix-reco | Recommendation.pas TComparer/API mismatch 修复 | 已修复 |
| fix-rabbitmq | RabbitMQ.pas 接口声明顺序修复 | 已修复 |
| fix-kafka | Kafka.pas cross-unit reference + E2251 cascade 修复 | 已修复 |
| fix-benchmark | Benchmark.pas Tests API 不匹配修复 (13 处 E2129/E2003/E2035) | 已修复 |
| fix-e2e | E2E.pas Tests API 不匹配修复 (15 处) | 已修复 |
| fix-executor | Executor.pas Uses/WillRaise/TTask.Run 修复 (多轮迭代) | 已修复 |
| dcu-search-path | 添加 dcu 到 -U 搜索路径 | 已修复 |

#### 关键技术决策

1. **dcu 目录搜索路径**: `-U"...;dcu"` 显式包含 dcu 目录，解决 F2613 Unit not found
2. **只读属性处理**: TWorkflowStep.Action/Branches/Expression由构造函数自动创建，直接访问子对象而非赋值整个属性
3. **条件步骤 API**: `LStep.Expression := '...'` + `LStep.Branches.Add(LBranch)` + `LBranch.MatchExpr/IsDefault`
4. **TTask.Run vs Create**: `TTask.Run(...)` 返回 ITask 可直接赋给接口变量，避免 TTask.Create 的构造/接口转换问题
5. **Assert.WillRaise**: 局部 TProc 变量承接匿名过程再传入 `WillRaise(LProc)` (单参版唯一可行)
6. **DUnitX 类型系统**: WillRaise 泛型版和非泛型三参版均报 E2250,仅单参版成功

#### 发现的 API 知识 (可用于后续开发)

- TWorkflowStep.Action/Branches/ParallelConfig/LoopConfig/Expression 均为只读，子对象由 Constructor 创建
- TConditionBranch.Steps 是嵌入步骤 (TObjectList<TWorkflowStep>),不是 NextStep 字符串引用
- TWorkflowDefinition.Validate 必须有 out TArray<string>参数
- TExpressionEvaluator 需独立创建，非 TWorkflowContext 属性
- TJSONObject迭代使用`for LPair in AInput`(TJSONPair)+LPair.JsonString.Value/LPair.JsonValue.Clone

### 经验总结

**Delphi 37 ( dcc32.exe ) 注意事项**:
- DCU 输出目录 (-NU) 与搜索目录 (-U) 必须区分，DCU 不在-source 路径时需在-U 中显式添加
- 只读属性不能赋值，应直接操作构造函数的初始化对象
- TTask.Run 优于 TTask.Create(后者返回对象，前者返回接口)
- Assert.WillRaise 优先使用局部过程变量传递匿名函数

**TConditionExpression/Bran ches API 记忆**:
- Expression: string (条件表达式文本)
- Branches: TObjectList<TConditionBranch>
- MatchExpr: string (如"> 5"或"== True")
- IsDefault: Boolean (默认分支标记)
- 无 SubConditions/Operator/Value/NextStep 属性


---

## 2026-08-07~08: DUnitX 测试驱动修复里程碑 (44 → 104 全绿)
> **执行任务**: TASK-0105~0108 (测试运行器 + 测试驱动功能修复)
> **提交 commit**: 工作区修改（未提交）
> **最终状态**: 全部套件 104/104 通过，0 失败 / 0 泄漏 / 0 错误

### 背景与挑战
**初始状态**: 上会话建立 DUnitX 运行器后 55 个 Executor 测试 44 过 11 失败；随后 E2E（3 个 fixture）和 Benchmark（6 个 fixture）也暴露真实功能缺陷。
**核心问题**（12 个 bug，详见 bugfix.md BUG-2026-018~030）:
- SetVariable 无前缀写入 vsInput 而非 vsWorkflow（文档契约不符）
- 执行器正序遍历导致内置执行器抢占用户注册
- TVariableValue.AsString 对 JSON 标量返回带引号文本
- EvaluateValue 对已含 `{{ }}` 的表达式嵌套包裹导致正则解析失败
- Loop 工作流 Start 结果丢失 Output（StepResult 每步被 Free）
- Parallel 分支闭包共享捕获（`var BranchIdx := I`）+ 执行器顺序双根因
- Guard 忽略 expression 守卫；ResolveString 缺 length 过滤器
- TSessionManager 清理定时器长 Sleep 死锁
- Runner 编译路径缺 Source\Session（静默链接旧 dcu）
- TMemoryMonitor 匿名线程 FreeOnTerminate=True 悬垂（无效句柄）
- LargeContext/LeakDetection 测试 TJSONString 泄漏（SetVariable 是 Clone 语义）

### 修复记录
| 套件 | 结果 | 关键修复 |
|------|------|----------|
| TWorkflowExecutorTests | 44 → 55/55 | SetVariable 重定向、AsString 标量、EvaluateValue 防嵌套、Start/Resume 保留最后一步结果、MakeParallelTask 按值参数+倒序遍历、Mock 加锁 |
| TWorkflowE2ETests | → 19/19 | Guard expression 守卫 + ERR_GUARD_EXPRESSION + length 过滤器 |
| TSessionE2ETests | → 6/6 | 清理定时器 100ms 小步等待（修 Destroy 死锁） |
| TFullIntegrationTests | → 4/4 | — |
| TMemoryBenchmarkTests 等 | → 20/20 | TMemoryMonitor FreeOnTerminate := False + WaitFor 后 Free；JSON 泄漏 try/finally |

### 关键技术决策
1. **Start/Resume 输出语义**: 工作流最终 Result 携带最后一步结果（含 Output）；失败/取消/等待分支单独返回；分支 Exit 前 FreeAndNil(Result) 防泄漏
2. **并行实现**: 匿名方法循环体内 `var X := I` 共享捕获 → 抽私有方法 MakeParallelTask，按值传参（TArray 引用语义共享数组、PBoolean 共享取消标志），局部变量声明在匿名方法 var 块内
3. **执行器注册语义**: 后注册优先（倒序遍历），允许用户覆盖内置执行器
4. **SetVariable(TJSONValue) 契约**: Clone 语义，调用方保留所有权（测试曾因此泄漏 110MB）
5. **匿名线程 WaitFor**: CreateAnonymousThread 默认 FreeOnTerminate=True，WaitFor 前必须置 False 并手动 Free

### 经验总结（Delphi 37 匿名方法坑族）
- E2555: 匿名方法不能捕获 var/out 参数、局部函数参数
- 循环体内内联 `var Idx := I` 被所有闭包共享（经典坑）
- E1019: for 控制变量必须是被捕获作用域内的简单局部变量（匿名方法内联 `for var J` 也触发）
- E2081: 嵌套 for 循环不能复用同一控制变量
- 解法统一: 抽普通方法 + 按值参数 + 局部变量声明在匿名方法 var 块 + 索引循环替代 for-in

### 测试运行方法（可复用）
- 编译: `dcc32 -B -Q -CC -U"Source;Source\Core;Source\Session;Source\Workflow;Source\Tests;dcu;D:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win32\release" -NU"dcu" -E"bin" Source\Tests\DeepFlow.Tests.Runner.dpr`（必须含 Source\Session）
- 运行: `.\bin\DeepFlow.Tests.Runner.exe -b --exit:continue`（全套）或 `--run:<fixture 前缀>`（单个）
- 全套运行后若 XML 被占用：`Get-Process -Name 'DeepFlow.Tests.Runner' | Stop-Process -Force`
- 基准报告写入仓库根（benchmark_*.json，相对路径随 cwd）


---

## 2026-08-08: Python Skill Service 真实联调里程碑 (Delphi ↔ FastAPI 打通)

### 背景
MVP 端到端闭环关键一步：首次真实启动 Python Skill Service 并与 Delphi TSkillClient 联调。
此前所有 Skill 相关测试均使用 mock，接口契约问题被全绿测试掩盖。

### 执行过程
1. 环境检查：Python 3.13 + fastapi/uvicorn/pydantic 已装；补装 litellm/structlog/RestrictedPython
2. 发现 Skills/src/llm/ 目录缺失（main.py import 崩溃）→ 创建 llm/client.py（LiteLLM 异步客户端）
3. 启动服务：/health healthy、/skills 列出 code_executor、/skills/execute 沙箱执行 5050、import os 安全拦截
4. 修复损坏 packaging 安装（packaging.version 模块缺失）
5. 创建 Delphi E2E 演示（DeepFlowSkillE2E.pas）四连验证全部通过
6. 修复 2 个真实契约 bug（BUG-2026-031/032）
7. 全量回归 104/104 仍全绿

### 关键技术决策
1. **DoRequest 返回 TJSONValue**：客户端不能假设响应恒为 JSON 对象；/skills 返回裸数组是常见跨语言契约漂移
2. **FromJSON 双格式兼容**：JSON Schema 对象 {type,properties,required} 与旧数组格式并存
3. **LLM 客户端用 LiteLLM acompletion**：异步 + 多模型统一接口 + num_retries 重试

### 联调验证结果
| 端点 | 结果 |
|------|------|
| GET /health | healthy, 1 skill loaded |
| GET /skills | code_executor 参数 Schema 正确解析 |
| POST /skills/execute (求和) | success, value=5050 |
| POST /skills/execute (import os) | blocked: Import of 'os' is not allowed |
| POST /llm/chat | 代码路径就绪；需有效 OPENAI_API_KEY（当前环境网络受限） |

### 待办
- /llm/chat 真实调用需有效 OPENAI_API_KEY（代码已就绪）
- 下一步：Workflow 引擎 + Skill Executor 全链路编排验证（insight_decision_gold.json）
