# DeepFlow Bug 修复记录

> 记录开发过程中发现和修复的 Bug
>
> 最后更新: 2026-08-08

---

## 已修�?Bug

### BUG-001: Source 目录未持久化
- **发现/修复日期**: 2024-12-05
- **严重程度**: Medium
- **影响范围**: 项目结构
- **问题描述**: 会话中断导致文件系统操作未完�?
- **修复方案**: 重新创建目录结构和所有源文件

---

## Delphi 12 兼容性修�?

> �?78 个文件修复，详见 `../bugfix.md` 主文�?

### 已修复模�?

| 模块 | 修复内容 | 日期 |
|------|----------|------|
| DeepBase.IoC.pas | PTypeInfo 本地变量, TValue.AsType<T> | 2025-12-05 |
| DeepBase.StateMachine.pas | 本地过程重构为私有方�?| 2025-12-05 |
| DeepBase.Diff.pas | TObjectList �?TList (记录类型) | 2025-12-05 |
| DeepBase.FileWatcher.pas | TEvent 替代 TTimer, TTask.Create | 2025-12-05 |
| DeepBase.Template.pas | 内联变量声明, 属性访问器 | 2025-12-05 |
| DeepBase.CloudSync.pas | HTTP 空请求体, TThread.Queue | 2025-12-05 |

### 常见修复模式

```pascal
// 1. TStringDynArray 缺少单元
uses System.Types;

// 2. 线程同步
TThread.Synchronize(nil, proc) �?TThread.Queue(nil, proc)

// 3. 异步任务
TTask.Run(proc) �?TTask.Create(proc).Start

// 4. 泛型类中本地过程 (E2570)
procedure TMyClass<T>.Method;
  function LocalFunc: string; // 禁止!
end;
�?重构为私有类方法

// 5. 记录类型容器
TObjectList<TMyRecord> �?TList<TMyRecord>

// 6. 记录属�?Inc
Inc(LRecord.Count) �?
  LCount := LRecord.Count; Inc(LCount); LRecord.Count := LCount;

// 7. 注释格式
{*...*} �?(*...*)
```

---

## 已修�?Bug (Delphi 12 兼容�?

### BUG-038: Graph.pas 泛型类中的本地过�?�?
- **发现/修复日期**: 2025-12-05
- **严重程度**: High
- **影响范围**: DeepBase.Graph.pas
- **问题描述**: TTree.Traverse 等方法中包含本地过程，触�?NI19024 错误
- **修复方案**: 将所有递归遍历重构为迭代式实现 (Stack/Queue)
- **修复内容**:
  - `TTree.Traverse` 使用 TStack/TQueue 迭代
  - `TTree.ToArray` 使用 TStack/TQueue 迭代
  - `TTree.Find` 使用 TStack 迭代
  - `TTree.NodeCount` 使用 TStack 迭代
  - `TGraph.FindCycle` 使用 TStack 迭代 DFS
  - `TGraph.StronglyConnectedComponents` 使用 TStack 迭代 Kosaraju

### BUG-039: Net.pas Indy DNS API 变更 �?
- **发现/修复日期**: 2025-12-05
- **严重程度**: High
- **影响范围**: DeepBase.Net.pas
- **问题描述**: QueryTimeout/qtCNAME/TCNAMERecord 在新�?Indy 中不存在
- **修复方案**: 使用新版 Indy API
- **修复内容**:
  - `QueryTimeout` �?`WaitingTime`
  - `qtCNAME` �?`qtName`
  - `TCNAMERecord` �?`TCNRecord`

### BUG-040: Serialization.pas 接口泛型方法限制 �?
- **发现/修复日期**: 2025-12-05
- **严重程度**: High
- **影响范围**: DeepBase.Serialization.pas
- **问题描述**: E2535 Interface methods must not have parameterized methods
- **修复方案**: 接口移除泛型方法，保留在类中实现
- **修复内容**:
  - `ISerializer` 接口只包含非泛型方法
  - `TBaseSerializer` 类保留泛型方�?(Delphi 12 允许类有泛型方法)
  - 添加 `TSerializer` 静态帮助类提供泛型入口

---

## 代码审查 Bug (2025-12-05)

### BUG-041: JSON Unicode 转义处理不完�?�?
- **发现/修复日期**: 2025-12-05
- **严重程度**: Medium
- **影响范围**: UniFlow.Performance.JSON.pas
- **问题描述**: `TJSONStreamReader.ReadString` �?`\uXXXX` 未转换为字符
- **修复方案**: 解析 4 位十六进制并转换�?Char

### BUG-042: TJSONObjectPool 重置器内存泄�?�?
- **发现/修复日期**: 2025-12-05
- **严重程度**: Medium
- **影响范围**: UniFlow.Performance.Pool.pas
- **问题描述**: `RemovePair().Free` 正序删除可能导致索引错误
- **修复方案**: 使用倒序删除并正确释�?Pair

### BUG-043: TWorkStealingQueue Pop 竞态条�?�?
- **发现/修复日期**: 2025-12-05
- **严重程度**: High
- **影响范围**: UniFlow.Performance.Concurrent.pas
- **问题描述**: Pop 方法在只有一个元素时逻辑错误
- **修复方案**: 简�?Pop 逻辑，先检查空再弹�?

### BUG-044: TPoolStats.HitRate 除零风险 �?
- **发现/修复日期**: 2025-12-05
- **严重程度**: Low
- **影响范围**: UniFlow.Performance.Pool.pas
- **问题描述**: `TotalAcquired = 0` 时除�?
- **修复方案**: 添加除零保护

---

## 分角色代码审�?Bug (2025-12-05)

### BUG-045: SEC-001 表达式注入风�?�?
- **发现/修复日期**: 2025-12-05
- **严重程度**: High (Security)
- **影响范围**: UniFlow.Workflow.Context.pas
- **问题描述**: `TExpressionEvaluator` 未限制可执行表达式，存在注入风险
- **修复方案**: 添加 `TExpressionWhitelist` 白名单类，启�?`SafeMode` 默认验证

### BUG-046: SEC-002 审计日志敏感信息泄露 �?
- **发现/修复日期**: 2025-12-05
- **严重程度**: High (Security)
- **影响范围**: UniFlow.Audit.Manager.pas
- **问题描述**: 审计日志可能记录用户输入中的敏感信息
- **修复方案**: 添加 `SanitizeMessage` 方法，默认启用脱�?

### BUG-047: SEC-003 租户隔离可被绕过 �?
- **发现/修复日期**: 2025-12-05
- **严重程度**: High (Security)
- **影响范围**: UniFlow.Tenant.pas
- **问题描述**: `IsTenantFlow` 仅检查前缀，可伪�?FlowId
- **修复方案**: 添加 `SignFlowId`/`VerifyFlowId` HMAC 签名验证

### BUG-048: SEC-005 配额检查竞态条�?�?
- **发现/修复日期**: 2025-12-05
- **严重程度**: Medium (Security)
- **影响范围**: UniFlow.Tenant.pas
- **问题描述**: `CheckQuota` �?`IncrementUsage` 非原子操�?
- **修复方案**: 添加 `TCriticalSection` 互斥锁，新增 `CheckAndIncrementQuota` 原子方法

### BUG-049: ARCH-002 TTenantEventStore 接口不一�?�?
- **发现/修复日期**: 2025-12-05
- **严重程度**: High (Architecture)
- **影响范围**: UniFlow.Tenant.pas
- **问题描述**: `SaveSnapshot` 返回 `procedure` �?`IEventStore.SaveSnapshot: Boolean` 不匹�?
- **修复方案**: 修改返回类型�?`Boolean`

### BUG-050: CODE-001 TStepResult.Output 所有权不明 �?
- **发现/修复日期**: 2025-12-05
- **严重程度**: High (Memory)
- **影响范围**: UniFlow.Workflow.Executor.pas
- **问题描述**: 谁负责释�?`Output` �?`TJSONValue` 不明�?
- **修复方案**: 添加 `OwnsOutput` 属性和 `ReleaseOutput` 方法，明确文档化

### BUG-051: CODE-003 缺少 try-finally 资源释放保护 �?
- **发现/修复日期**: 2025-12-05
- **严重程度**: High (Memory)
- **影响范围**: UniFlow.Workflow.Executor.pas
- **问题描述**: `ExecuteAction`/`ExecuteCondition` 等缺少异常保�?
- **修复方案**: 添加 `try-except` 保护，异常时释放已创建的结果

### BUG-052: CODE-005 子工作流变量污染父上下文 �?
- **发现/修复日期**: 2025-12-05
- **严重程度**: Medium
- **影响范围**: UniFlow.Workflow.Executor.pas
- **问题描述**: 子工作流变量可能泄漏到父上下�?
- **修复方案**: 子工作流创建独立�?`TWorkflowContext`，仅显式传递输�?输出

### BUG-053: SEC-004 Skill 服务缺少身份认证 �?
- **发现/修复日期**: 2025-12-05
- **严重程度**: Medium (Security)
- **影响范围**: UniFlow.Skill.Client.pas
- **问题描述**: `TSkillClient` �?Skill 服务通信无身份认证，任何人可调用
- **修复方案**: 
  - 新增 `TSkillAuthType` 枚举 (None/ApiKey/Bearer/Basic)
  - `TSkillClientConfig` 添加认证配置 (ApiKey/BearerToken/BasicAuth)
  - `ApplyAuthentication` 方法在请求中添加认证�?
  - 401/403 错误不重试直接抛�?

### BUG-054: CODE-004 HTTP/重试超时硬编�?�?
- **发现/修复日期**: 2025-12-05
- **严重程度**: Low
- **影响范围**: UniFlow.Skill.Client.pas
- **问题描述**: 超时、重试次数、延迟等参数硬编码，无法根据环境调整
- **修复方案**: 
  - `TSkillClientConfig` 新增高级配置 (RetryBackoffMultiplier/MaxRetryDelayMs/EnableRetryOnTimeout/EnableRetryOn5xx)
  - 添加 `LoadFromJSON`/`ToJSON`/`LoadFromFile`/`SaveToFile` 方法
  - `CalculateRetryDelay` 实现指数退避算�?
  - `ShouldRetry` 根据配置判断是否重试

### BUG-055: ARCH-004 并行执行为串行实�?�?
- **发现/修复日期**: 2025-12-06
- **严重程度**: Medium (Architecture)
- **影响范围**: UniFlow.Workflow.Executor.pas
- **问题描述**: `ExecuteParallel` 使用串行实现，无法利用多核性能
- **修复方案**: 使用 `TTask` 为每个分支创建独立上下文并行执行，支�?`FailFast/WaitAll`

### BUG-056: QA-001 缺少核心单元测试 �?
- **发现/修复日期**: 2025-12-06
- **严重程度**: Critical (QA)
- **影响范围**: Tests
- **问题描述**: 缺少 `Executor/Context/Definition` 核心单元测试
- **修复方案**: 新增 `UniFlow.Tests.Executor.pas`，覆盖基础执行/条件/循环/并行/上下文等场景

### BUG-057: UX-001 错误信息不够友好 �?
- **发现/修复日期**: 2025-12-06
- **严重程度**: High (UX)
- **影响范围**: 错误展示
- **问题描述**: 错误代码直出，缺少用户友好描述和建议
- **修复方案**: 新增 `UniFlow.Workflow.Errors.pas` 提供友好错误映射、多语言与建议输�?

### BUG-058: ARCH-001 缺少依赖注入容器 �?
- **发现/修复日期**: 2025-12-06
- **严重程度**: Medium (Architecture)
- **影响范围**: Core
- **问题描述**: 组件创建硬编码，缺少统一依赖管理
- **修复方案**: 新增 `UniFlow.DI.pas` 轻量级容器，支持单例/瞬�?工厂/作用�?

### BUG-059: QA-002~004 边界/并发/恢复测试 �?
- **发现/修复日期**: 2025-12-06
- **严重程度**: High (QA)
- **影响范围**: Tests
- **问题描述**: 缺少边界条件、并发场景、错误恢复测�?
- **修复方案**: 新增 `TBoundaryConditionTests`/`TConcurrencyTests`/`TErrorRecoveryTests` 测试套件

### BUG-060: ARCH-003 Skill URL 配置硬编�?�?
- **发现/修复日期**: 2025-12-06
- **严重程度**: Low
- **影响范围**: UniFlow.Skill.Executor.pas
- **问题描述**: Skill 服务 URL 硬编码在构造函数，无法通过配置调整
- **修复方案**: 
  - 新增 `TSkillServiceConfig` 配置�?
  - 支持�?JSON/环境变量/配置文件加载
  - 环境变量前缀: `UNIFLOW_SKILL_URL/TIMEOUT/RETRY_COUNT/RETRY_DELAY`
  - `TSkillActionExecutor.CreateDefault` 使用全局默认配置

### BUG-061: CODE-002 ExecuteLoop 对象频繁创建 �?
- **发现/修复日期**: 2025-12-06
- **严重程度**: Medium
- **影响范围**: UniFlow.Performance.Pool.pas
- **问题描述**: 循环每次迭代都创建新�?`TVariableValue`，GC 压力�?
- **修复方案**: 
  - 新增 `TPooledLoopVar` 轻量级循环变量类
  - 新增 `TVariableValuePool` 对象�?
  - 支持整数/字符�?JSON 值的池化复用
  - 预热 16 个整�?+ 8 个字符串对象

### BUG-062: UX-002 缺少工作流模�?�?
- **发现/修复日期**: 2025-12-06
- **严重程度**: Low (UX)
- **影响范围**: Templates
- **问题描述**: 新用户缺少参考模板，上手困难
- **修复方案**: 
  - 新建 `Templates/` 目录
  - 添加 3 个常用模�?
    - `01-sequential-approval.json` - 顺序审批流程
    - `02-data-sync.json` - ETL 数据同步
    - `03-ai-chat.json` - AI 智能对话
  - 添加 `README.md` 模板使用指南

### BUG-063: UX-003 缺少调试器可视化 �?
- **发现/修复日期**: 2025-12-06
- **严重程度**: Medium (UX)
- **影响范围**: Debug
- **问题描述**: 工作流执行时缺少调试工具，难以排查问�?
- **修复方案**: 
  - 新增 `UniFlow.Debug.Debugger.pas` (~1350 �?
  - `TWorkflowDebugger` 工作流调试器
  - `TBreakpoint` 断点管理 (普�?条件/监视)
  - `TStackFrame` 调用栈查�?
  - `TDebugConsole` 文本调试控制�?
  - 支持 Step Over/Into/Out 单步执行
  - 支持变量监视和修�?
  - 支持执行历史回溯

### BUG-064: UX-004 缺少性能分析面板 �?
- **发现/修复日期**: 2025-12-06
- **严重程度**: Low (UX)
- **影响范围**: Debug
- **问题描述**: 缺少性能分析工具，难以识别瓶�?
- **修复方案**: 
  - 新增 `UniFlow.Debug.Profiler.pas` (~1170 �?
  - `TWorkflowProfiler` 性能分析�?
  - `TStepProfile` 步骤性能数据
  - `THotspot` 热点检�?(慢步�?高频/内存/易错)
  - `TProfileReport` 性能报告 (JSON/Text/HTML/CSV)
  - `TProfilerPanel` 文本监控面板
  - 支持实时统计和历史分�?

---

## P5-A 生产加固 (2025-12-06)

### TASK-2001: 端到端集成测�?�?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: Tests
- **内容**: 
  - 新增 `UniFlow.Tests.E2E.pas` (~1040 �?
  - `TMockLLMProvider` / `TMockSkillService` Mock 组件
  - `TWorkflowE2ETests` 完整工作流测试套�?
  - `TSessionE2ETests` 会话管理测试套件
  - `TFullIntegrationTests` 集成场景测试
  - 覆盖: LLM集成/Skill调用/条件分支/状态持久化

### TASK-2002: 压力测试与基�?�?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: Tests
- **内容**: 
  - 新增 `UniFlow.Tests.Benchmark.pas` (~1270 �?
  - `TBenchmarkRunner` / `TBenchmarkReport` 基准测试框架
  - `TMemoryMonitor` 内存监控�?
  - `TThroughputBenchmarkTests` 吞吐量测�?
  - `TConcurrencyBenchmarkTests` 并发压力测试 (10/50/100 并发)
  - `TMemoryBenchmarkTests` 内存泄漏检�?
  - `TStabilityBenchmarkTests` 稳定性测�?
  - `TObjectPoolBenchmarkTests` 对象池效�?
  - JSON 格式基准报告输出

### TASK-2003: 生产部署脚本 �?
- **完成日期**: 2025-12-06
- **优先�?*: Low
- **影响范围**: Deploy
- **内容**: 
  - 新建 `Deploy/` 目录
  - `docker-compose.prod.yml` 生产环境配置
  - `nginx.conf` 反向代理配置 (HTTPS/限流/CORS)
  - `.env.example` 环境变量模板
  - `deploy.sh` 一键部署脚�?

### TASK-2004: 监控告警集成 �?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: Monitoring
- **内容**: 
  - `Deploy/monitoring/prometheus.yml` Prometheus 配置
  - `Deploy/monitoring/grafana/dashboards/DeepFlow.json` Grafana 仪表�?
  - 仪表板包�? 工作流统�?LLM指标/Skill指标/系统指标
  - 告警阈�? 错误�?延迟/并发�?

---

## P5-B 功能增强 (2025-12-06)

### TASK-2010: 工作流版本控�?�?
- **完成日期**: 2025-12-06
- **优先�?*: High
- **影响范围**: Workflow/Editor
- **内容**: 
  - 新增 `UniFlow.Workflow.Version.pas` (~1236 �?
  - `TSemVer` 语义化版本号支持
  - `TWorkflowVersion` 版本实体 (草稿/激�?归档/废弃)
  - `TVersionComparator` JSON 深度比较�?
  - `TVersionDiff` 版本差异 (Markdown/Text/JSON)
  - `TVersionManager` 版本管理�?(创建/激�?回滚)
  - `IVersionStore` / `TMemoryVersionStore` 存储�?
  - 新增 `UniFlow.Workflow.Version.API.pas` (~788 �?
  - `TVersionAPIService` REST API 服务
  - 支持分页/筛�?排序/标签
  - 新增 `Source/Editor/version-hiDeepStory.html` (~1220 �?
  - 版本历史列表与详情面�?
  - Diff 可视化查看器
  - 版本时间�?
  - 回滚确认对话�?

### TASK-2011: 可视化编辑器增强 �?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: Editor
- **内容**: 
  - 新增 `Source/Editor/workflow-editor-enhanced.html` (~1474 �?
  - 增强节点类型: Start/End/Action/Condition/Loop/Parallel/SubWorkflow/LLM/Skill
  - 改进拖拽体验: 网格对齐 (20px)、智能贝塞尔曲线连线
  - Command Pattern 撤销/重做系统
  - 完整快捷键支�?(Ctrl+Z/Y/C/V/A/S, Delete, Esc, ?)
  - 节点复制/粘贴、批量选择
  - 画布缩放 (25%-200%)、迷你地�?
  - 节点对齐/分布工具
  - 属性面�? 节点配置编辑

### TASK-2012: 更多 Skill 模板 �?
- **完成日期**: 2025-12-06
- **优先�?*: Low
- **影响范围**: Skill/Templates
- **内容**: 
  - 新建 `Source/Skill/Templates/` 目录
  - `python-http-client.py` (~295 �?: HTTP GET/POST/PUT/DELETE/PATCH，自动重试，超时处理
  - `python-data-transformer.py` (~418 �?: 数据转换 (map/filter/reduce/sort/group/flatten/unique/pick/omit/rename/convert/validate)
  - `nodejs-file-utils.js` (~517 �?: 文件操作 (read/write/delete/copy/move)，目录操作，Glob 匹配
  - `README.md` (~187 �?: 模板文档与使用指�?

### TASK-2013: 工作流导�?导出 �?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: Workflow
- **内容**: 
  - 新增 `UniFlow.Workflow.ImportExport.pas` (~1256 �?
  - `TExportOptions` / `TImportOptions` 导入导出选项
  - `TExportResult` / `TImportResult` 操作结果
  - `TExportPackage` 导出�?(多工作流 + 依赖打包)
  - `TValidationResult` 导入验证
  - `TWorkflowImportExport` 导入导出服务
  - 支持: 单个/批量导出、JSON/Package 格式
  - 支持: 冲突策略 (Skip/Overwrite/Rename/Version)
  - 支持: 导入前验证、试运行模式、跨租户迁移

---

## P5-C 平台集成 (2025-12-06)

### TASK-2020: MCP 协议完整支持 �?
- **完成日期**: 2025-12-06
- **优先�?*: High
- **影响范围**: MCP
- **内容**: 
  - 新建 `Source/MCP/` 目录
  - `UniFlow.MCP.Types.pas` (~1158 �?: MCP 协议类型定义
    - JSON-RPC 2.0 基础类型
    - `TMCPTool` / `TMCPResource` / `TMCPPrompt` 定义
    - 请求/响应消息类型 (Initialize/ListTools/CallTool/ListResources/ReadResource/ListPrompts/GetPrompt)
    - MCP 通知类型
  - `UniFlow.MCP.Server.pas` (~752 �?: MCP Server 实现
    - `TMCPServer` 服务器核心类
    - `IMCPToolHandler` / `IMCPResourceProvider` / `IMCPPromptProvider` 提供器接�?
    - `TMCPSession` 会话管理
    - JSON-RPC 请求路由与响�?
    - `TLambdaToolHandler` Lambda 工具处理�?
  - `UniFlow.MCP.Client.pas` (~769 �?: MCP Client 实现
    - `TMCPClient` 客户端核心类
    - HTTP 传输�?
    - Tool/Resource/Prompt 缓存
    - `TMCPClientManager` 多服务器管理
  - 支持 MCP 协议版本 2024-11-05

### TASK-2021: 更多 LLM 提供�?�?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: AI
- **内容**: 
  - 新增 `UniFlow.LLM.Providers.pas` (~1078 �?
  - `ILLMProvider` 提供商接�?
  - `TOpenAIProvider` - OpenAI GPT-4/GPT-3.5
  - `TClaudeProvider` - Anthropic Claude 3.5/3
  - `TGeminiProvider` - Google Gemini Pro/Flash
  - `TOllamaProvider` - 本地模型 (Ollama/LM Studio)
  - `TAzureOpenAIProvider` - Azure OpenAI
  - `TDeepSeekProvider` - DeepSeek
  - `TLLMProviderManager` 多提供商管理�?

### TASK-2022: 消息队列集成 �?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: Queue
- **内容**: 
  - 新建 `Source/Queue/` 目录
  - `UniFlow.Queue.Types.pas` (~953 �?: 消息队列类型定义
    - `TQueueMessage` / `TMessageHeaders` 消息类型
    - `TQueueConfig` / `TExchangeConfig` / `TBindingConfig` 配置
    - `TKafkaRecord` / `TKafkaTopicConfig` / `TKafkaConsumerConfig` Kafka 类型
    - `TWorkflowTriggerMessage` 工作流触发消�?
  - `UniFlow.Queue.RabbitMQ.pas` (~1479 �?: RabbitMQ 集成
    - `IRabbitMQConnection` / `IRabbitMQChannel` 接口
    - `TRabbitMQConnection` / `TRabbitMQChannel` 实现
    - `TRabbitMQProducer` / `TRabbitMQConsumer` 生产�?消费�?
    - `TRabbitMQWorkflowTrigger` 工作流触发器
    - `TRabbitMQConnectionPool` 连接�?
  - `UniFlow.Queue.Kafka.pas` (~300 �?: Kafka 集成
    - `IKafkaProducer` / `IKafkaConsumer` 接口
    - `TKafkaProducer` / `TKafkaConsumer` REST Proxy 实现
    - `TKafkaWorkflowTrigger` 工作流触发器
  - 支持异步工作流触发、延迟消息、消息优先级

### TASK-2023: 数据库存储后�?�?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: Storage
- **内容**: 
  - 新建 `Source/Storage/` 目录
  - `UniFlow.Storage.Types.pas` (~1293 �?: 存储类型定义
    - `TDatabaseConfig` / `TPostgreSQLConfig` 数据库配�?
    - `TResultRow` / `TResultSet` 查询结果
    - `TQueryBuilder` 查询构建�?(Select/Insert/Update/Delete)
    - `TStorageEntity` / `TWorkflowEntity` / `TSessionEntity` / `TSkillEntity` 存储实体
    - `TPagination` / `TSortField` / `TFilterCondition` 分页/排序/筛�?
  - `UniFlow.Storage.PostgreSQL.pas` (~1663 �?: PostgreSQL 实现
    - `IDbConnection` / `TPostgreSQLConnection` 数据库连�?
    - `TConnectionPool` 连接�?
    - `IRepository<T>` 仓库接口
    - `TWorkflowRepository` / `TSessionRepository` / `TSkillRepository` 仓库实现
    - `TPostgreSQLStorageBackend` 存储后端
    - `TSchemaMigrator` Schema 迁移�?
  - 支持事务、连接池、多租户

---

## P6-A 云原生支�?(2025-12-06)

### TASK-3001: Kubernetes 部署模板 �?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: Deploy
- **内容**: 
  - 新建 `Deploy/k8s/` 目录
  - `DeepFlow-deployment.yaml` (~587 �?: 主部署清�?
    - Namespace / ConfigMap / Secret
    - Deployment (API) + initContainers
    - Service (ClusterIP + Headless)
    - HPA (CPU/Memory/RPS 自动伸缩)
    - PDB (Pod 中断预算)
    - ServiceAccount / RBAC
    - Ingress (TLS + 限流)
    - PVC (持久化存�?
  - `DeepFlow-worker.yaml` (~435 �?: Worker 部署
    - Worker Deployment + HPA
    - Scheduler Deployment (单实�?+ Leader Election)
    - Leader Election RBAC
  - `kustomization.yaml` Kustomize 入口

### TASK-3002: Helm Chart �?�?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: Deploy
- **内容**: 
  - 新建 `Deploy/helm/DeepFlow/` 目录
  - `Chart.yaml` Chart 定义 (依赖 PostgreSQL/Redis/RabbitMQ)
  - `values.yaml` (~337 �?: 完整配置
    - API/Worker/Scheduler 配置
    - 应用配置 (Server/Workflow/Cache/Queue/Monitoring/Tracing/Security)
    - Secrets 配置 (Database/Redis/RabbitMQ/JWT/LLM)
    - 子图表配�?(PostgreSQL/Redis/RabbitMQ)
  - `templates/_helpers.tpl` (~282 �?: 模板助手函数
  - `templates/api-deployment.yaml` API Deployment 模板
  - `templates/service.yaml` / `templates/ingress.yaml`
  - `templates/hpa.yaml` / `templates/rbac.yaml`
  - `templates/configmap.yaml` / `templates/secrets.yaml`

### TASK-3003: Service Mesh 集成 �?
- **完成日期**: 2025-12-06
- **优先�?*: High
- **影响范围**: Deploy
- **内容**: 
  - 新建 `Deploy/istio/` 目录
  - `DeepFlow-mesh.yaml` (~407 �?: Istio 配置
    - Gateway (HTTP/HTTPS 入口)
    - VirtualService (路由规则 + 重试 + 超时)
    - DestinationRule (负载均衡 + 熔断 + 子集)
    - PeerAuthentication (mTLS 强制)
    - AuthorizationPolicy (API 访问控制)
    - RequestAuthentication (JWT 验证)
    - ServiceEntry (外部 LLM 提供商访�?
    - Sidecar (出站流量限制)
    - EnvoyFilter (本地限流)
    - Telemetry (追踪 + 日志 + 指标)

### TASK-3004: 分布式追�?(OpenTelemetry) �?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: Cloud
- **内容**: 
  - 新建 `Source/Cloud/` 目录
  - `UniFlow.Cloud.Telemetry.Types.pas` (~1507 �?: OTel 类型
    - Trace 类型: TSpan / TTraceContext / TSpanEvent / TSpanLink
    - Metrics 类型: TCounter / TGauge / THistogramMetric
    - Logs 类型: TLogRecord / TLogSeverity
    - 资源配置: TResource / TExporterConfig / TSamplerConfig / TOTelConfig
    - 工作流属�? TWorkflowTraceAttributes / TWorkflowMetrics
  - `UniFlow.Cloud.Telemetry.SDK.pas` (~1689 �?: OTel SDK
    - TracerProvider / Tracer / 采样�?(AlwaysOn/Off/Ratio/ParentBased)
    - MeterProvider / Meter
    - LoggerProvider / Logger
    - 批处理处理器 (TBatchSpanProcessor)
    - OTLP HTTP 导出�?(Traces/Metrics/Logs)
    - 控制台导出器
    - TOpenTelemetry 全局单例

---

## P6-B AI Enhancement (2025-12-06)

### TASK-3010: 智能工作流推�?�?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: AI
- **内容**: 
  - `UniFlow.AI.Recommendation.pas` (~2228 �?
    - `TRecommendation` / `TUserPreferences` / `TWorkflowFeatures` 基础类型
    - `TFeatureExtractor` 特征提取�?(执行频率/平均时间/错误率等)
    - `TCollaborativeFilter` 协同过滤推荐 (用户-物品矩阵)
    - `TContentBasedRecommender` 基于内容推荐 (余弦相似�?
    - `THybridRecommender` 混合推荐引擎
    - `TOptimizationAnalyzer` 优化建议分析 (并行�?缓存/批处�?错误处理)
    - `TErrorPatternAnalyzer` 错误模式分析
    - `TRecommendationService` 推荐服务 (模板/优化/类似工作�?
    - `TTemplateRecommender` 模板推荐

### TASK-3011: 自然语言工作流生�?�?
- **完成日期**: 2025-12-06
- **优先�?*: High
- **影响范围**: AI
- **内容**: 
  - `UniFlow.AI.NLWorkflowGen.pas` (~1641 �?
    - `TIntentType` / `TEntityType` / `TParsedIntent` 意图解析类型
    - `TIntentParser` 意图解析�?(正则模式匹配)
    - `TSkillDefinition` / `TSkillMatcher` Skill 匹配�?
    - `TWorkflowGenerator` 基础工作流生成器 (意图→步�?
    - `TLLMWorkflowGenerator` LLM 增强生成�?(低置信度时调�?LLM)
    - `TConversationalBuilder` 对话式工作流构建�?
    - `TTemplateManager` 模板管理�?

### TASK-3012: AI 异常检�?�?
- **完成日期**: 2025-12-06
- **优先�?*: High
- **影响范围**: AI
- **内容**: 
  - `UniFlow.AI.AnomalyDetection.pas` (~2297 �?
    - `TAnomalyType` / `TAnomalySeverity` / `TDetectedAnomaly` 异常类型
    - `TSlidingWindowStats` 滑动窗口统计 (Mean/Variance/Percentile)
    - `TEWMACalculator` 指数加权移动平均
    - `IAnomalyDetector` 检测器接口
    - `TZScoreDetector` Z-Score 检测器
    - `TIQRDetector` 四分位距检测器
    - `TEWMADetector` EWMA 检测器
    - `TIsolationForestDetector` Isolation Forest (简化版)
    - `TSeasonalDetector` 季节性分解检测器
    - `TMultiDimensionalDetector` 多维度异常检�?
    - `TCorrelationMatrix` 相关性矩�?
    - `TRootCauseAnalyzer` 根因分析�?
    - `TAdaptiveThresholdManager` 自适应阈�?
    - `TAnomalyDetectionService` 异常检测服�?
    - `TWorkflowAnomalyMonitor` 工作流健康监�?

### TASK-3013: 智能重试策略 �?
- **完成日期**: 2025-12-06
- **优先�?*: Medium
- **影响范围**: AI
- **内容**: 
  - `UniFlow.AI.SmartRetry.pas` (~2080 �?
    - `TErrorCategory` / `TErrorSeverity` / `TErrorClassification` 错误分类
    - `TErrorClassifier` 错误分类�?(正则模式+HTTP状态码+学习)
    - `TBackoffType` 退避策�?(Fixed/Linear/Exponential/Fibonacci/Decorrelated)
    - `IRetryStrategy` 重试策略接口
    - `TFixedDelayStrategy` / `TExponentialBackoffStrategy` / `TAdaptiveRetryStrategy`
    - `TCircuitBreaker` 熔断�?(Closed/Open/HalfOpen)
    - `TCircuitBreakerRegistry` 熔断器注册表
    - `TRetryExecutor` 重试执行�?(泛型执行)
    - `TSmartStrategySelector` 智能策略选择�?(历史分析+启发�?
    - `TSmartRetryService` 智能重试服务
    - `TRetryStrategyBuilder` 策略构建�?(Fluent API)

---

## Bug 统计

| 严重程度 | 已修�?| 待修�?| 合计 |
|----------|--------|--------|------|
| Critical | 2 | 0 | 2 |
|| High | 95 | 0 | 95 |
|| Medium | 23 | 0 | 23 |
|| Low | 7 | 0 | 7 |
|| **合计** | **127** | **0** | **127** |

*注: 包含 P5-A/B/C (12任务) + P6-A 云原生(4任务) + P6-B AI增强 (4任务)*

---

### BUG-2026-008: bugfix.md 文件因错误写入导致完全损坏 (P0)
- **发现日期**: 2026-08-07
- **严重程度**: Critical
- **影响范围**: bugfix.md 自身
- **问题描述**: 
  - commit 68d54c2a 中 bugfix.md 被错误写入, 每行被追加 "| 已修复 | 待修复 | 合计 |" 格式, 导致 781 行全部不可读
  - 中文 UTF-8 字符被截断为单字节, 产生大量乱码
  - 根本原因: 写入操作时编码处理错误, 在已存在 UTF-8 损坏的文件上执行了错误的字符串操作
- **修复方案**: 
  - 从 commit c251e04c 恢复 bugfix.md (最后一个正确版本)
  - 重新应用 BUG-2026-007 状态更新和统计表修正
  - 确保 UTF-8 无 BOM 编码写入
- **状态**: 已修复 (2026-08-07)

---

## 回归测试清单

- [x] Workflow 定义加载测试
- [x] 变量引用解析测试
- [x] 步骤执行流程测试
- [x] 状态持久化测试
- [x] 错误处理测试
- [x] 编辑器单元测�?
- [x] CI/CD 自动化测�?

---

## 2026-08-06: DeepFlow 正名期间发现/修复的 Bug

### BUG-2026-001: DeepDeep 乱码 (P1)
- **发现/修复日期**: 2026-08-06
- **严重程度**: High
- **影响范围**: 25 个文件, 73 处
- **问题描述**: "Deep"被重复 5 次 (如 DeepDeepDeepDeepDeepInsight, DeepDeepDeepDeepDeepStory), 系生成/转换脚本缺陷
- **修复方案**: 全文搜索替换, 9 种形态全部纠正
- **状态**: 已修复 (f7a9b2f2)

### BUG-2026-002: 03.07 自指错误 (P1)
- **发现/修复日期**: 2026-08-06
- **严重程度**: Medium
- **影响范围**: 文档 03.07
- **问题描述**: 标题"DeepFlow与DeepFlow关系说明"(自指), 正文"UniFlow 与 uniFlow 关系说明"(概念混淆)
- **修复方案**: 修正为两层架构说明, 标题/对比表/命名约定全部修正
- **状态**: 已修复 (f7a9b2f2)

### BUG-2026-003: .pas UTF-8 损坏 (P0)
- **发现/修复日期**: 2026-08-06
- **严重程度**: Critical (24个阻碍编译)
- **影响范围**: 41 个 .pas 文件, 其中 24 个阻碍编译
- **问题描述**: 入库时即存在的 UTF-8 损坏, 中文/全角字符第三字节转为 0x3f, 部分伴随闭合引号塌缩。不可逆(0x3f 推不回原字节), 需按上下文语义逐字还原
- **修复方案**: simple_qa.workflow.json 已修复(23处, 77b750c6); .pas 的 41 个文件需另起独立任务逐字语义还原
- **状态**: 部分修复 (simple_qa 已修, .pas 待办 TASK-0102)

### BUG-2026-004: 文档 UTF-8 损坏 (P2)
- **发现/修复日期**: 2026-08-06
- **严重程度**: Medium
- **影响范围**: tasks.md / history.md / bugfix.md 自身 (2025-12 版)
- **问题描述**: 三归档文件 UTF-8 损坏, 中文标点被替换为 U+FFFD, 部分文字丢失
- **修复方案**: 2026-08-07 归档对齐时重新写入 UTF-8 无 BOM 版本
- **状态**: 已修复 (2026-08-07)

### BUG-2026-005: 仓库根 tasks.md index 脱节 (P2)
- **发现/修复日期**: 2026-08-07
- **严重程度**: Medium
- **影响范围**: 02Business 仓库根 tasks.md/history.md/bugfix.md
- **问题描述**: git index 与 HEAD 不一致 (index 冻结在旧版, HEAD 已更新), git status 沉默
- **修复方案**: git update-index --refresh 强制对齐 index 到 HEAD
- **状态**: 已修复 (2026-08-07)


### BUG-2026-006: 类型标识符保留导致命名不一致 (P2)
- **发现/修复日期**: 2026-08-07
- **严重程度**: Medium
- **影响范围**: 25 个文件, 477 处
- **问题描述**: ADR-002 正名后 unit/文件名已改 DeepFlow.*, 但类型标识符 (TUniFlowXxx/IUniFlow) 仍 560 处, 与 unit 名不一致
- **修复方案**: Tools/rename-identifiers.py 字节级替换 (不依赖编码, 可处理曾阻碍文本替换的损坏文件), 25 文件 477 处改完
- **验证**: 零残留 UniFlow 引用; 旧类型 0 / 新类型 493; 枚举值缩写保留
- **状态**: 已修复 (commit fb6fbadf, 2026-08-07)

---

## 2026-08-07: 工作区发现的新问题

### BUG-2026-007: 39 个.pas 文件 UTF-8 损坏 (新增发现) (P0)
- **发现日期**: 2026-08-07
- **严重程度**: Critical (24 个阻碍编译)
- **影响范围**: 39 个 .pas 文件（相比 commit fb6fbadf 的工作区差异）
- **问题描述**: 
  - git diff HEAD 显示 39 个文件有修改，经检查均为注释中文 UTF-8 损坏
  - 例如：`值？` → `值？`,冒号缺失，行末字符塌缩等
  - 这是入库时即存在的已有损坏，之前未被 rename-identifiers.py 工具处理
- **已发现示例**:
  - `DeepFlow.AI.Adapter.pas`: `使用默认?` → 应为 `使用默认值`
  - `DeepFlow.Workflow.Executor.pas`: `线性步骤执？` → 应为 `线性步骤执行`
- **修复方案**: 
  - 需像 simple_qa.workflow.json 一样逐字语义还原
  - 先统计所有 39 个文件的损坏点，再按上下文逐字修复
  - 预计需要大量手工工作（参考简单 QA 的 23 处修复）
- **关联任务**: 这是 TASK-0102 的一部分，但现在已明确是工作区未 committed 状态的问题
- **状态**: 已修复 (git checkout HEAD 恢复 39 个文件，commit ea96fdc6, 2026-08-07)

---

## 2026-08-07: Delphi 编译完整修复期间发现的问题

> **背景**: Source\Tests 三文件 (Benchmark/E2E/Executor) 编译错误集中在 API 误用

### BUG-2026-009: TWorkflowStep.Action 只读属性误用 (P1)
- **发现/修复日期**: 2026-08-07
- **严重程度**: High
- **影响范围**: Benchmark.pas (L659/685/711), E2E.pas (L479/491/503/546/559/581/593/604), 共 11 处
- **问题描述**: 
  - 测试代码创建 LAction: TActionDefinition 变量并赋值 `LStep.Action := LAction`
  - 但 TWorkflowStep.Action 为 read only，构造函数已自动创建 FAction 实例
- **修复方案**: 
  - 删除 LAction 变量声明和赋值语句
  - 直接操作 LStep.Action 的子对象 (`LStep.Action.ActionType := ...; LStep.Action.Params := TJSONObject.Create; ...`)
- **验证**: 编译通过，零 Error
- **经验**: 只读属性只能访问，不能赋值；子对象由构造函数初始化

### BUG-2026-010: TConditionExpression/TConditionBranch API 不匹配 (P0)
- **发现/修复日期**: 2026-08-07
- **严重程度**: Critical
- **影响范围**: Benchmark.pas (L694-700), 共 6 处
- **问题描述**: 
  - 测试代码使用不存在的 API:`TConditionExpression.Expression/Branches/DefaultStep`
  - `TConditionBranch.Operator/Value/NextStep`
  - 实际 API:TConditionExpression.Operator/LeftExpr/RightExpr/SubConditions; TConditionBranch.Id/WhenValue/MatchExpr/IsDefault/Condition/Steps
- **修复方案**: 
  - `LStep.Condition.Expression := '...'` → `LStep.Expression := '{{ vars.var_1 }}'`
  - `LStep.Condition.Branches/DefaultStep` → `LStep.Branches.Add(LBranch)` + 第二个 IsDefault 分支
  - `LBranch.Operator := coEquals` → `LBranch.MatchExpr := '> 5'`
  - `LBranch.Value` / `LBranch.NextStep` 删除
- **验证**: 编译通过，E2003 全部消除
- **经验**: 
  - 条件步骤 API: `LStep.Expression` (文本表达式) + `LStep.Branches` + `LBranch.MatchExpr`
  - TConditionBranch.Steps 是嵌入步骤列表，不是 NextStep 字符串引用

### BUG-2026-011: TWorkflowContext.Create 参数不足 (P1)
- **发现/修复日期**: 2026-08-07
- **严重程度**: High
- **影响范围**: Benchmark.pas (10 处), E2E.pas (1 处), Executor.pas (多处), 共 12+ 处
- **问题描述**: 
  - `TWorkflowContext.Create`需要 `(AWorkflowId, AInstanceId: string)` 两个参数
  - 测试代码仅使用单参或无参构造
- **修复方案**: 
  - `TWorkflowContext.Create('benchmark', TGUID.NewGuid.ToString)`
  - `TWorkflowContext.Create('e2e', TGUID.NewGuid.ToString)`
- **验证**: E2035 Not enough actual parameters 消除
- **经验**: Context 必须提供 WorkflowId 和 InstanceId，前者标识工作流类型，后者唯一实例 ID

### BUG-2026-012: TJSONObject.EnumerateNames 不存在 (P1)
- **发现/修复日期**: 2026-08-07
- **严重程度**: Medium
- **影响范围**: E2E.pas (L619)
- **问题描述**: 
  - TJSONObject 没有 EnumerateNames 方法
  - 尝试遍历 JSON 输入参数失败
- **修复方案**: 
  - `for LKey in AInput.EnumerateNames do` → `for LPair in AInput do`
  - `AInput[LKey]` → `LPair.JsonValue`
  - `LKey` → `LPair.JsonString.Value`
- **验证**: E2003 Undeclared identifier 消除
- **经验**: TJSONObject迭代使用`for LPair in AInput`(返回 TJSONPair)+LPair.JsonString.Value/LPair.JsonValue.Clone

### BUG-2026-013: Assert.WillRaise DUnitX 重载问题 (P1)
- **发现/修复日期**: 2026-08-07
- **严重程度**: Medium
- **影响范围**: Executor.pas (L1021/1066/1083), 共 3 处
- **问题描述**: 
  - `Assert.WillRaise<Exception>(proc)`泛型版报 E2250 No matching overload
  - `Assert.WillRaise(proc, Exception, msg)`非泛型三参版也报 E2250
  - 只有 `Assert.WillRaise(LProc)`单参版成功
- **修复方案**: 
  - 局部 TProc 变量承接匿名过程:`var LProc: TProc; LProc := procedure ... end;`
  - 传入 `Assert.WillRaise(LProc)`
- **验证**: E2250 All eliminated
- **经验**: DUnitX 的 WillRaise 在 Delphi 37 下，局部 TProc 变量是唯一可靠方式

### BUG-2026-014: TTask.Create vs TTask.Run 模式错误 (P1)
- **发现/修复日期**: 2026-08-07
- **严重程度**: Medium
- **影响范围**: Executor.pas (Test_Parallel_RaceCondition_Safe, Test_MultipleExecutors_Concurrent, Test_ContextClone_ThreadSafe, Test_SharedResource_NoDeadlock), 共 4 处
- **问题描述**: 
  - `Tasks[I] := TTask.Create(TProc(...))`语法在 Delphi 37 下解析冲突
  - E2029 ')' expected but ';' found, E2070 Syntax error, E2382 Method or procedure expected
  - TTask.Create 构造函数返回 TTask 对象，不是 ITask 接口
- **修复方案**: 
  - `Tasks[I] := TTask.Run(procedure ... end)`
  - TTask.Run 静态方法返回 ITask，可直接赋给接口数组元素
  - 删除多余的 `Task.Start` (TTask.Run 已自动启动)
- **验证**: E2029/E2070/E2382 消除
- **经验**: TTask.Run()优于 TTask.Create(), 返回 ITask 接口且自动启动

### BUG-2026-015: System.SyncObjs/System.Threading uses 缺失 (P0)
- **发现/修复日期**: 2026-08-07
- **严重程度**: High
- **影响范围**: Executor.pas (L1-L30)
- **问题描述**: 
  - TCriticalSection 未声明 → 来自 System.SyncObjs
  - ITask/TTask 未声明 → 来自 System.Threading
- **修复方案**: 
  - uses 增加 `System.SyncObjs, System.Threading,`
- **验证**: E2003 Undeclared identifier 消除
- **经验**: 并发相关类型必须显式引入对应系统单元

### BUG-2026-016: dcu 目录未加入-U 搜索路径 (P0)
- **发现/修复日期**: 2026-08-07
- **严重程度**: Critical (阻止编译继续)
- **影响范围**: dcc32.exe 编译配置
- **问题描述**: 
  - `dcu\DeepBase.Exceptions.dcu` 存在但编译时报 F2613 Unit not found
  - `-NU"dcu"`只指定输出目录，不自动加入搜索路径
- **修复方案**: 
  - `-U"Source;...;dcu"`末尾显式添加`;dcu`
- **验证**: F2613消除，编译继续进入后续错误列表
- **经验**: DCU 不在-source 路径时，必须在-U 中显式包含其位置

### BUG-2026-017: TWorkflowDefinition.Validate 参数不足 (P1)
- **发现/修复日期**: 2026-08-07
- **严重程度**: Medium
- **影响范围**: Executor.pas (Test_Validate_ValidWorkflow_ReturnsTrue, Test_Validate_InvalidWorkflow_ReturnsFalse), 2 处
- **问题描述**: 
  - `FDefinition.Validate`无参数调用
  - 实际签名：`function Validate(out AErrors: TArray<string>): Boolean;`
  - 缺少 out 参数，且未声明 AErrors 变量
- **修复方案**: 
  - 添加`var AErrors: TArray<string>;`
  - `FDefinition.Validate` → `FDefinition.Validate(AErrors)`
- **验证**: E2035 Not enough actual parameters 和 E2003 AErrors undeclared 消除
- **经验**: Validate 方法必须有 out 参数接收错误列表

---

## 2026-08-07~08: DUnitX 测试驱动功能修复 (44→104 全绿)

> **背景**: DUnitX 测试运行器 (DeepFlow.Tests.Runner.dpr) 建立后，55 个 Executor 测试 44 过 11 失败；
> 逐项修复后全部套件 **104/104 通过**（Executor 55 + WorkflowE2E 19 + SessionE2E 6 + FullIntegration 4 + Benchmark 20），0 失败/0 泄漏/0 错误。

### BUG-2026-018: SetVariable 作用域重定向缺失 (P1)
- **发现/修复日期**: 2026-08-07
- **严重程度**: High
- **影响范围**: DeepFlow.Workflow.Context.pas (SetVariable)
- **问题描述**: 无前缀变量写入栈顶 vsInput（只读输入区），与文档契约不符——SetVariable('user_name', ...) 后应可用 `{{ vars.user_name }}` 读取（quick-start.md L111）
- **修复方案**: 栈顶为 vsInput 且栈深 >= 2 时，重定向到倒数第二层（vsWorkflow）
- **验证**: Test_SetVariable_PrefersWorkflowScope 通过

### BUG-2026-019: 执行器正序遍历致内置执行器抢注册 (P1)
- **发现/修复日期**: 2026-08-07
- **严重程度**: High
- **影响范围**: DeepFlow.Workflow.Executor.pas (ExecuteAction)
- **问题描述**: ExecuteAction 正序遍历 FActionExecutors，内置 TSkillActionExecutor 总是先命中 atSkill，用户注册的同类型执行器永不生效
- **修复方案**: 改倒序遍历（后注册优先，允许覆盖内置）
- **验证**: Test_ExecuteAction_UserExecutorOverridesBuiltIn 通过

### BUG-2026-020: AsString 对 JSON 标量返回带引号文本 (P1)
- **发现/修复日期**: 2026-08-08
- **严重程度**: High
- **影响范围**: DeepFlow.Workflow.Context.pas (TVariableValue.AsString 'j' 分支)
- **问题描述**: `Expected [deep] but got ["deep"]` / `Expected [42] but got ["42"]` —— TJSONString.ToJSON 带引号
- **修复方案**: 按 JSON 标量类型返回：TJSONString→.Value、TJSONNumber→ToJSON、TJSONBool→BoolToStr、其他→ToJSON
- **验证**: Test_DeepNesting_Expression / Test_ResolveString_NestedPath 通过

### BUG-2026-021: EvaluateValue 对已含 `{{ }}` 的表达式嵌套包裹 (P1)
- **发现/修复日期**: 2026-08-08
- **严重程度**: High
- **影响范围**: DeepFlow.Workflow.Context.pas (EvaluateValue else 分支)
- **问题描述**: AExpr 已含 `{{ }}` 时被再包一层变成 `{{ {{ vars.flag }} }}`，正则非贪婪匹配把 `{{ vars.flag` 当路径，解析失败（Boolean/Comparison 表达式全挂）
- **修复方案**: 已含 `{{` 直接 ResolveString，否则才包裹
- **验证**: Test_Expression_Evaluate_Boolean/Comparison 通过

### BUG-2026-022: Loop 工作流 Start 结果丢失 Output (P0)
- **发现/修复日期**: 2026-08-08
- **严重程度**: Critical
- **影响范围**: DeepFlow.Workflow.Executor.pas (Start/Resume)
- **问题描述**: Test_Loop_CollectsResults Success=True 但 Output=nil —— 循环内每步 StepResult 被 Free，最终返回 TStepResult.OK 不带输出
- **修复方案**: Start/Resume 保留最后一步结果（FreeAndNil(Result); Result := StepResult; StepResult := nil;）；NeedsWait/Error 分支 Exit 前 FreeAndNil(Result) 防泄漏
- **验证**: Test_Loop_CollectsResults 通过
- **经验**: 工作流最终 Result 携带最后一步结果（含 Output）；失败/取消/等待分支单独返回

### BUG-2026-023: Parallel 分支闭包共享捕获 + 执行器顺序 (P0)
- **发现/修复日期**: 2026-08-08
- **严重程度**: Critical
- **影响范围**: DeepFlow.Workflow.Executor.pas (ExecuteParallel)
- **问题描述**: 双根因——(1) `var BranchIdx := I` 在 Delphi 匿名方法中共享捕获，所有闭包看到同一索引；(2) 正序遍历 FActionExecutors 内置执行器抢 atSkill
- **修复方案**: 抽 MakeParallelTask 私有方法，按值传参（AIndex/TArray/PBoolean），匿名方法内声明局部变量；内部倒序遍历执行器
- **验证**: Test_Parallel_AllBranches / Test_Parallel_WaitAll 通过
- **经验**: Delphi 匿名方法循环体内 `var X := I` 被所有闭包共享；E1019 for 控制变量须为被捕获作用域内简单局部变量；E2081 嵌套 for 不可复用控制变量；解法=抽方法+按值参数+局部变量声明在匿名方法 var 块

### BUG-2026-024: Guard 忽略 expression 守卫 (P1)
- **发现/修复日期**: 2026-08-08
- **严重程度**: High
- **影响范围**: DeepFlow.Workflow.Executor.pas (TGuardActionExecutor.Execute) + Errors.pas + Context.pas
- **问题描述**: Test_E2E_SimpleQA_WithValidation 的 `{{ vars.question | length > 0 }}` 守卫被忽略（GuardType 空走 else→OK）
- **修复方案**: 加 expression 分支（TExpressionEvaluator.Evaluate，false 时 Fail(ERR_GUARD_EXPRESSION)）+ 新增错误码 + ResolveString 加 length 过滤器
- **验证**: Test_E2E_SimpleQA_WithValidation 通过

### BUG-2026-025: TSessionManager 清理定时器死锁 (P0)
- **发现/修复日期**: 2026-08-08
- **严重程度**: Critical
- **影响范围**: DeepFlow.Session.Manager.pas (StartCleanupTimer)
- **问题描述**: 匿名线程 `Sleep(CleanupIntervalMinutes * 60 * 1000)`（默认 5 分钟），Destroy 时 WaitFor 长时间阻塞 → TSessionE2ETests 卡死
- **修复方案**: 改 100ms 小步等待循环（及时响应 Terminate）
- **验证**: TSessionE2ETests 6/6 通过

### BUG-2026-026: Runner 编译路径缺 Source\Session (P0)
- **发现/修复日期**: 2026-08-08
- **严重程度**: Critical
- **影响范围**: 构建配置
- **问题描述**: Runner 的 -U 缺 Source\Session，链接 dcu 目录旧单元，Session 修复不生效（诊断程序显式加路径才通过）
- **修复方案**: 编译命令统一加 Source\Session
- **经验**: 编译命令必须含全部源目录；缺路径时 dcc32 静默链接旧 dcu，修复无效且难排查

### BUG-2026-027: TMockActionExecutor 无锁并发写日志 (P2)
- **发现/修复日期**: 2026-08-08
- **严重程度**: Medium
- **影响范围**: DeepFlow.Tests.Executor.pas
- **问题描述**: 并行分支并发 FExecutionLog.Add，可能交错损坏
- **修复方案**: 加 FLock (TCriticalSection) 保护

### BUG-2026-028: TMemoryMonitor 匿名线程悬垂句柄 (P0)
- **发现/修复日期**: 2026-08-08
- **严重程度**: Critical
- **影响范围**: DeepFlow.Tests.Benchmark.pas (TMemoryMonitor)
- **问题描述**: `Thread Error: 无效句柄 (6)` —— TThread.CreateAnonymousThread 默认 FreeOnTerminate=True，线程结束后自我释放，Stop 的 WaitFor 访问悬垂对象
- **修复方案**: 创建后 `FThread.FreeOnTerminate := False;`，Stop 中 WaitFor 后 `FThread.Free; FThread := nil;`
- **验证**: Benchmark_Memory_WorkflowExecution 通过
- **经验**: 对匿名线程做 WaitFor 前必须先置 FreeOnTerminate := False，否则 WaitFor/句柄操作存在竞态

### BUG-2026-029: LargeContext 基准测试 TJSONString 泄漏 (P1)
- **发现/修复日期**: 2026-08-08
- **严重程度**: High
- **影响范围**: DeepFlow.Tests.Benchmark.pas (Benchmark_Memory_LargeContext)
- **问题描述**: `SetVariable('var_'+I, TJSONString.Create(...))` 每轮创建 100 个对象从不释放（TVariableValue.Create(TJSONValue) 内部 Clone 存值、不接管所有权）→ 1000 轮 ≈ 110MB 泄漏 → 断言 < 200MB 失败
- **修复方案**: 局部变量 + try/finally 释放原对象
- **验证**: Benchmark_Memory_LargeContext 通过
- **经验**: SetVariable(TJSONValue) 是 Clone 语义，调用方保留所有权，必须自行释放

### BUG-2026-030: LeakDetection 测试同样泄漏 (P2)
- **发现/修复日期**: 2026-08-08
- **严重程度**: Medium
- **影响范围**: DeepFlow.Tests.Benchmark.pas (Benchmark_Memory_LeakDetection)
- **问题描述**: `SetVariable('test', TJSONString.Create('value'))` 同模式泄漏
- **修复方案**: 改用 string 重载（直接存值，无 clone 开销）

---

## 2026-08-08: Python Skill 服务真实联调 (Delphi ↔ FastAPI 打通)

背景：首次真实启动 Python Skill Service（Skills/，FastAPI + LiteLLM）并与 Delphi TSkillClient 联调，发现 2 个仅真实联调才能暴露的接口契约 bug（mock 测试全绿掩盖）。

### BUG-2026-031: DoRequest 强转 TJSONObject 导致 /skills 数组响应崩溃 (P0)
- **发现/修复日期**: 2026-08-08
- **严重程度**: High
- **影响范围**: DeepFlow.Skill.Client.pas (DoRequest/DoRequestAsync 及全部调用方)
- **问题描述**: `DoRequest` 用 `TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject` 强转，但 Python 服务 `/skills` 返回裸 JSON 数组 → `Invalid class typecast` 异常（Demo 2 ListSkills 崩溃）
- **修复方案**: DoRequest 返回类型 TJSONObject → TJSONValue（保留原始类型）；ListSkills 优先处理 TJSONArray，兼容旧格式 `{"skills":[...]}`；其余调用方 `as TJSONObject`；异步回调签名同步 TProc<TJSONValue>
- **验证**: DeepFlowSkillE2E Demo 2 通过；全量回归 104/104 仍全绿
- **经验**: 客户端解析不能假设响应恒为 JSON 对象；真实联调能暴露 mock 测不到的类型契约问题

### BUG-2026-032: TSkillInfo.FromJSON 不兼容 JSON Schema 格式 parameters (P1)
- **发现/修复日期**: 2026-08-08
- **严重程度**: Medium
- **影响范围**: DeepFlow.Skill.Types.pas (TSkillInfo.FromJSON)
- **问题描述**: Python 服务 `/skills` 返回 parameters 为 JSON Schema 对象 `{type, properties, required}`，Delphi 期待数组 `[{name,type,description,required},...]` → 参数列表解析为空
- **修复方案**: 兼容两种格式——数组走原逻辑；对象则解析 properties 子对象（type/description），required 数组决定必填标记
- **验证**: DeepFlowSkillE2E Demo 2 正确列出 code_executor 参数；全量回归 104/104 仍全绿
- **经验**: 跨语言接口契约须实测验证，Schema 对象 vs 数组是最常见的格式漂移点

---
