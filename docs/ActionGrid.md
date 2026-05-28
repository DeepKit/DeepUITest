# ActionGrid 设计模式

> 将系统行为从"硬编码在代码流程中"转变为"声明在注册表中、由运行时配置驱动"的设计模式。

---

## 核心公式

```
行为 = 能力（代码注册） × 意愿（运行时配置）
```

- **能力**：编译期确定，代码声明"我能做什么"
- **意愿**：运行时确定，配置决定"现在做什么、按什么顺序做、用什么参数"

---

## 解决的根本问题

传统 Delphi 程序的通病：**中心类膨胀**。

每加一个功能，开发者唯一的选择是在中心类里加一个方法 + 在分发逻辑里加一行 if。
日积月累，中心类变成 3000-7000 行的上帝类，无法维护。

ActionGrid 的解法：**中心类只做注册和分发，永远不写业务逻辑。** 业务逻辑分散在各自的模块里，通过注册接入系统。加 100 个新功能，中心类也不变。

---

## 适用场景

任何存在"一个中心点分发多个操作"的地方：

| 场景 | 传统做法 | ActionGrid 做法 |
|---|---|---|
| HTTP 路由 | if path = '/a' then ... else if ... | `Grid.Run(path, ctx)` |
| 请求管道 | 15 个阶段硬编码顺序 | `Grid.RunAll(ctx)` 按优先级 |
| UI 菜单/命令 | case CommandId of ... | `Grid.Run(cmdId, ctx)` |
| 配置面板 | 每个设置项一个 handler 方法 | `Grid.Run(settingKey, ctx)` |
| 插件系统 | 手动加载 + 手动调用 | `Grid.Add` + `SetEnabled` |
| 定时任务 | TTimer 堆积 | `Grid.RunAll(timerCtx)` |
| 事件处理 | OnXxx 事件堆积 | `Grid.Run(eventName, ctx)` |
| 工作流引擎 | 硬编码步骤 | `Grid.RunAll` + 动态调序 |

---

## 最简形态：4 个方法

```pascal
TActionGrid<TContext> = class
  procedure Add(const AKey: string; AHandler: TProc<TContext>; APriority: Integer = 0);
  function Run(const AKey: string; var AContext: TContext): Boolean;
  function RunAll(var AContext: TContext): Integer;
  procedure SetEnabled(const AKey: string; AEnabled: Boolean);
end;
```

这 4 个方法覆盖了 80% 的使用场景。核心实现约 100 行。

- `Add`：声明一个能力
- `Run`：精确匹配执行一个（路由模式）
- `RunAll`：按优先级执行所有启用的（管道模式）
- `SetEnabled`：运行时开关（热配置）

---

## 完整形态：按需启用

```pascal
TGridFeature = (
  gfMetrics,    // 调用统计 + 慢告警
  gfConfig,     // DB/文件配置源 + 热更新
  gfAudit,      // 版本历史 + 回滚
  gfPrefix,     // 前缀匹配（/admin/* 模式）
  gfFallback,   // 备用 Handler
  gfDeps        // 依赖声明 + 拓扑排序
);
TGridFeatures = set of TGridFeature;

constructor TActionGrid<TContext>.Create(AFeatures: TGridFeatures = []);
```

| 功能集 | 代码量 | 适用项目 |
|---|---|---|
| `[]` 纯核心 | ~100 行 | DeepInput、DeepClip 等小工具 |
| `[gfMetrics]` | ~180 行 | 需要监控的服务 |
| `[gfConfig]` | ~280 行 | 需要热更新的服务 |
| `[gfMetrics, gfConfig, gfAudit]` | ~500 行 | Assayer 等核心服务 |
| 全功能 | ~760 行 | 框架内部 / 复杂场景 |

---

## 容错设计

### Handler 异常处理

每个 Handler 注册时声明错误策略：

```pascal
TErrorStrategy = (
  esAbort,      // 异常 → 中止整个链，向上抛出
  esSkip,       // 异常 → 记录日志，跳过继续下一个
  esRetry,      // 异常 → 重试 N 次
  esFallback    // 异常 → 执行备用 Handler
);

Grid.Add('auth', DoAuth, 10, esAbort);        // 认证失败必须中止
Grid.Add('compress', DoCompress, 50, esSkip); // 压缩失败可跳过
Grid.Add('forward', DoForward, 80, esRetry);  // 转发失败可重试
```

框架自动 try/except，开发者不需要在每个 Handler 里写容错代码。

### 配置源故障

```
正常：DB 可用 → 加载最新配置
故障：DB 不可用 → 保持"最后已知良好配置"继续运行
恢复：DB 恢复 → 下次 polling 自动加载最新配置
```

永远不会因为配置源故障导致系统停止工作。

### 热更新竞态

使用 Copy-on-Write 不可变快照：

```
线程 A（处理请求）：取快照引用 → 遍历执行（不受干扰）
线程 B（热更新）：构建新快照 → 原子替换引用
```

Delphi 动态数组是引用计数的，取引用 = 零拷贝。替换引用 = 原子操作。
正在执行的请求用旧快照跑完，新请求用新快照。零锁竞争。

### 循环调用检测

```pascal
[ThreadVar] GDispatchDepth: Integer;

function Run(const AKey: string; var AContext: TContext): Boolean;
begin
  if GDispatchDepth > 8 then
  begin
    Logger.Error('ActionGrid circular dispatch: ' + AKey);
    Exit(False);
  end;
  Inc(GDispatchDepth);
  try
    // 正常分发
  finally
    Dec(GDispatchDepth);
  end;
end;
```

---

## 可观测性

### 内置 Metrics（无需外部 APM）

```pascal
TActionMetrics = record
  Key: string;
  CallCount: Int64;
  ErrorCount: Int64;
  TotalDurationMs: Int64;
  AvgDurationMs: Integer;
  LastCallTime: TDateTime;
  LastErrorMessage: string;
end;

// Admin 界面直接调用
var AllMetrics := Grid.GetMetrics;
```

### 慢 Action 告警

```pascal
Grid.SlowThresholdMs := 500;
Grid.OnSlowAction := procedure(AKey: string; ADurationMs: Int64)
begin
  Logger.Warn(Format('Slow action: %s took %dms', [AKey, ADurationMs]));
end;
```

### DryRun（调试预览）

```pascal
// 不执行，只返回"如果执行会命中哪些 Action、什么顺序"
var Plan := Grid.DryRunAll;
// 输出: ['auth(P10)', 'sanitize(P20)', 'forward(P80)', 'validate(P90)']
```

---

## 运行时热配置

### 配置源接口

```pascal
IGridConfigSource = interface
  function LoadAll: TArray<TActionConfig>;
  procedure Save(const AKey: string; const AConfig: TActionConfig);
  procedure OnChanged(ACallback: TProc);
end;
```

### 内置实现

```pascal
// SQLite 配置源（适合有数据库的项目）
TDBGridConfigSource = class(TInterfacedObject, IGridConfigSource)
  // 从 action_grid_configs 表读取
  // 每 5 秒 polling max(updated_at)
end;

// JSON 文件配置源（适合轻量项目）
TFileGridConfigSource = class(TInterfacedObject, IGridConfigSource)
  // 从 grid.json 读取
  // FileWatcher 监控变更
end;
```

### 配置表结构

```sql
CREATE TABLE action_grid_configs (
  key TEXT PRIMARY KEY,
  enabled INTEGER DEFAULT 1,
  priority INTEGER DEFAULT 100,
  params TEXT,              -- JSON，每个 Action 自己解释
  error_strategy INTEGER DEFAULT 1,  -- 0=Abort 1=Skip 2=Retry 3=Fallback
  locked INTEGER DEFAULT 0,          -- 1=不允许运行时修改
  version INTEGER DEFAULT 1,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_by TEXT DEFAULT 'system'
);

CREATE TABLE action_grid_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  key TEXT NOT NULL,
  old_enabled INTEGER,
  new_enabled INTEGER,
  old_priority INTEGER,
  new_priority INTEGER,
  version INTEGER,
  changed_at TEXT DEFAULT CURRENT_TIMESTAMP,
  changed_by TEXT,
  reason TEXT
);
```

### 热更新 API

```pascal
// 管理员通过 Admin API 调用
Grid.SetEnabled('goal_inject', False);   // 立即生效
Grid.SetPriority('compress', 30);        // 调整顺序
Grid.Rollback('goal_inject', 2);         // 回滚到版本 2
```

---

## 安全边界

```pascal
TActionFlag = (
  afLocked,       // 不允许运行时禁用（如 Auth、Constitution）
  afHidden,       // 不在 Admin 界面显示
  afDeprecated    // 标记为废弃，下版本移除
);

Grid.Add('auth', DoAuth, 10, esAbort, [afLocked]);
// Admin 界面显示为灰色，不可操作
```

---

## 使用示例

### Assayer — HTTP 路由

```pascal
// ProxyServer.pas（永远不超过 50 行路由代码）
FRoutes := TActionGrid<THttpContext>.Create([gfMetrics, gfConfig]);

// 各 Controller 自注册
TChatCtrl.Register(FRoutes);       // '/v1/chat/completions'
THealthCtrl.Register(FRoutes);     // '/health', '/models'
TAdminCtrl.Register(FRoutes);      // '/admin/*'

// 请求到达
procedure HandleRequest(ACtx: THttpContext);
begin
  if not FRoutes.Run(ACtx.Path, ACtx) then
    ACtx.Response.Status := 404;
end;
```

### Assayer — 请求管道

```pascal
FPipeline := TActionGrid<TPipelineContext>.Create([gfMetrics, gfConfig]);
FPipeline.Add('constitution', DoConstitution, 10, esAbort, [afLocked]);
FPipeline.Add('auth', DoAuth, 20, esAbort, [afLocked]);
FPipeline.Add('sanitize', DoSanitize, 30, esAbort);
FPipeline.Add('goal_inject', DoGoalInject, 50, esSkip);
FPipeline.Add('compress', DoCompress, 60, esSkip);
FPipeline.Add('forward', DoForward, 80, esRetry);
FPipeline.Add('validate', DoValidate, 90, esAbort);

// 执行
var Count := FPipeline.RunAll(PipelineCtx);
```

### DeepSVG — 菜单命令

```pascal
FCommands := TActionGrid<TCommandContext>.Create;
FCommands.Add('file.open', DoFileOpen);
FCommands.Add('file.save', DoFileSave);
FCommands.Add('edit.undo', DoUndo);
FCommands.Add('view.zoom_in', DoZoomIn);
// ... 50 个命令，主窗体代码不变

// 菜单点击
procedure OnMenuClick(Sender: TObject);
begin
  FCommands.Run(TMenuItem(Sender).Tag, CommandCtx);
end;
```

### DeepConfig — 设置面板

```pascal
FSettings := TActionGrid<TSettingContext>.Create([gfConfig]);
FSettings.Add('general.language', HandleLanguage);
FSettings.Add('general.theme', HandleTheme);
FSettings.Add('proxy.url', HandleProxy);
FSettings.Add('ai.model', HandleAIModel);

// 用户修改设置
procedure OnSettingChanged(const AKey, AValue: string);
var Ctx: TSettingContext;
begin
  Ctx.Key := AKey;
  Ctx.Value := AValue;
  FSettings.Run(AKey, Ctx);
end;
```

### DeepStory — 写作服务调度

```pascal
FServices := TActionGrid<TWriteContext>.Create([gfMetrics]);
FServices.Add('grammar_check', DoGrammar, 10);
FServices.Add('style_polish', DoStyle, 20);
FServices.Add('fact_verify', DoFactCheck, 30);
FServices.Add('ai_expand', DoAIExpand, 40);
// 30+ 服务，主窗体不变

// 一键优化（按序执行所有启用的服务）
FServices.RunAll(WriteCtx);
```

---

## 渐进式迁移策略

不需要一次性重构。对现有项目的迁移步骤：

```
第 1 步：创建 Grid，把现有 if/else 里的 handler 逐个 Add 进去
第 2 步：把 if/else 分发替换为 Grid.Run / Grid.RunAll
第 3 步：把 handler 方法移到独立的 Controller/Module 文件
第 4 步：（可选）接入 ConfigSource，启用热配置
```

每一步都是独立可验证的，不会破坏现有功能。

---

## 与其他模式的关系

| 已知模式 | ActionGrid 的对应 | 区别 |
|---|---|---|
| 命令模式 | Handler = Command | ActionGrid 加了注册表 + 配置 + 容错 |
| 中介者模式 | Grid = Mediator | ActionGrid 是声明式的，不需要中介者知道所有模块 |
| 责任链 | RunAll = Chain | ActionGrid 的链是可配置的，不是硬编码的 |
| 策略模式 | 同 Key 可替换 Handler | ActionGrid 支持运行时替换 |
| 服务定位器 | Run(key) = Locate | ActionGrid 加了优先级 + 容错 + Metrics |
| 插件架构 | Add + SetEnabled | ActionGrid 是轻量级插件系统 |
| 微内核 | Grid = Kernel, Handlers = Plugins | ActionGrid 不需要 IPC，同进程内 |

**ActionGrid 不是发明新模式，而是把 6 种模式的精华融合成一个 Delphi 原生的、100-760 行的实用框架。**

---

## 设计原则

1. **最小核心**：4 个方法就能用，不强制启用任何高级功能
2. **按需扩展**：通过 Feature Flags 启用 Metrics/Config/Audit
3. **零第三方依赖**：纯 Delphi RTL（TDictionary + TList + TMonitor + TThreadVar）
4. **编译期安全**：泛型 TContext，Handler 签名不对立即报错
5. **运行时灵活**：配置驱动，热更新，不重启
6. **容错优先**：每个 Handler 自动 try/except，不会因为一个模块崩溃整个系统
7. **可观测**：内置 Metrics，不需要外部工具就能看到系统行为
8. **可回滚**：配置版本化，出问题秒级回退

---

## 实现文件清单

| 文件 | 行数 | 职责 | 依赖 |
|---|---|---|---|
| `DeepBase.ActionGrid.pas` | ~400 | 核心引擎 | System.Generics.Collections |
| `DeepBase.ActionGrid.Config.pas` | ~100 | IGridConfigSource + TActionConfig | System.JSON |
| `DeepBase.ActionGrid.DBSource.pas` | ~120 | SQLite 配置源 + history | DeepBase.DB.DoQry |
| `DeepBase.ActionGrid.FileSource.pas` | ~60 | JSON 文件配置源 | DeepBase.FileWatcher |
| `DeepBase.ActionGrid.Metrics.pas` | ~80 | 统计 + 慢告警 | DeepBase.Logging |
| **总计** | **~760** | | |

---

## 各项目重构计划

| 项目 | 重构目标 | Grid 用法 | 预期效果 |
|---|---|---|---|
| Assayer | ProxyServer 3678 行 → ~500 行 | Routes + Pipeline | 中心类瘦身 70% |
| DeepSVG | ViewMainSVG 膨胀 | Commands | 菜单/工具栏解耦 |
| DeepStory | 主窗体 30+ 服务 | Services | 写作服务可配置 |
| DeepConfig | 设置面板 50+ 项 | Settings | 设置项热插拔 |
| DeepCompare | ParallelTest 策略 | Strategies | 测试策略可切换 |
| DeepInsight | LLM 调用链 | Pipeline | 调用链容错 |
| DeepLaunch | 启动器动作 | Actions | 启动项可配置 |
| DeepDev | LSP 命令分发 | Commands | 命令注册解耦 |
| DeepMoveC | 清理规则 | Rules | 规则热更新 |
| DeepShine | 多 App 调度 | Apps | App 启停控制 |
| DeepClip | 剪贴板处理 | Processors | 处理器可选 |
| DeepInput | 输入法模块 | Modules | 模块开关 |
| DeepSync | 同步任务 | Tasks | 任务调度 |
| DeepRenew | 重构规则 | Rules | 规则可配置 |
| DeepCharset | 编码检测 | Detectors | 检测器优先级 |
| DeepDevLite | 精简命令集 | Commands | 继承 DeepDev 的 Grid |


---

## 进化方向讨论（2026-05-09 圆桌会议）

> 状态：发散讨论，未定稿。待人类确认后决定哪些纳入实现。

---

### 进化 1：Condition Guard（条件前置声明）

**问题**：当前每个 handler 内部自己判断"我能不能处理这个 context"，导致重复代码。

**建议**：注册时声明前置条件，Grid 自动跳过不满足的 handler。

```pascal
Grid.Add('retry_backoff', DoRetryWithBackoff, 10, esSkip)
  .When(function(const Ctx: TRecoveryContext): Boolean
  begin
    Result := Ctx.ErrorKind in [ekTransient, ekRateLimit];
  end);
```

**好处**：
- handler 代码更纯粹（只做动作，不做条件判断）
- `DryRun` 能准确预览哪些 handler 会被跳过
- 条件本身可被 Metrics 统计（"被条件跳过了多少次"）

**复杂度**：低（注册时多一个 lambda 字段）

---

### 进化 2：RunUntilResolved 模式

**问题**：在错误恢复场景中，一旦某个 handler 解决了问题，后面的不需要再跑。当前需要每个 handler 自己检查 `Ctx.Resolved`。

**建议**：加执行模式参数。

```pascal
type
  TRunMode = (
    rmAll,            // 执行所有（管道模式，当前行为）
    rmUntilResolved,  // 执行到 Resolved=True 就停（恢复模式）
    rmFirst           // 只执行第一个匹配的（路由模式）
  );

function RunAll(var AContext: TContext; AMode: TRunMode = rmAll): Integer;
```

**需要 Context 满足的约定**：有一个 `IsResolved: Boolean` 字段或接口。

**复杂度**：低（RunAll 循环里加一个 break 条件）

---

### 进化 3：Grid 级总超时

**问题**：如果整个恢复链跑了太久（3 次重试 + 切模型 + 再重试 = 可能 2 分钟），应该有总超时保护。

**建议**：

```pascal
FRecoveryGrid.MaxDurationMs := 120000;  // 整个链最多 2 分钟
// 超时后自动中止当前 handler，走最后的 escalate
```

**实现**：RunAll 开始时记录 StartTime，每个 handler 执行前检查是否超时。

**复杂度**：低

---

### 进化 4：Sub-Grid（子网格 / 条件分叉）

**问题**：当分支很多时，所有 handler 都注册在一个 Grid 里，大部分被 skip，遍历浪费。

**建议**：支持嵌套 Grid。

```pascal
FRecoveryGrid.AddSubGrid('network_recovery', FNetworkGrid, 10)
  .When(function(const Ctx): Boolean begin
    Result := Ctx.ErrorKind in [ekTransient, ekRateLimit]
  end);

FRecoveryGrid.AddSubGrid('model_recovery', FModelGrid, 20)
  .When(function(const Ctx): Boolean begin
    Result := Ctx.ErrorKind = ekModelLimit
  end);
```

**本质**：把线性链变成条件树，但仍然是声明式的。

**复杂度**：中（需要递归执行 + 子 Grid 的 Metrics 汇总）

---

### 进化 5：并行组（AddParallel）

**问题**：有些 handler 之间没有依赖关系，串行执行浪费时间。

**场景**：上下文 17 层组装中，L3/L5/L8 互不依赖，可以并行加载。

**建议**：

```pascal
Grid.Add('L1_security', DoL1, 10);
Grid.Add('L2_architecture', DoL2, 20);
Grid.AddParallel('context_parallel', ['L3_project', 'L5_decisions', 'L8_history'], 30);
Grid.Add('L14_task_spec', DoL14, 40);
```

**约束**：
- 并行 handler 必须操作 Context 的不同字段（线程安全）
- 或者 Context 提供线程安全的写入方法
- 全部完成后才继续下一个优先级

**实现**：用 `TTask.WhenAll` 或 `TParallel.For`。

**复杂度**：中（线程安全是主要挑战）

---

### 进化 6：事件绑定（Reactive Grid）

**问题**：当前 Grid 是"主动调用"模式。有些场景是"事件发生时自动触发"。

**建议**：

```pascal
Grid.BindEvent('file_changed', FCodeScanGrid);
Grid.BindEvent('heartbeat_timeout', FWorkshopRecoveryGrid);
Grid.BindEvent('config_changed', FHotReloadGrid);

// 事件发生时
EventBus.Fire('file_changed', FileCtx);
// → 自动触发 FCodeScanGrid.RunAll(FileCtx)
```

**本质**：Grid 从"被动工具"变成"事件驱动的执行引擎"。

**需要配合**：一个轻量级 EventBus（可以是 DeepBase 已有的，或新建）。

**复杂度**：中

---

### 进化 7：自适应优先级（成功率学习）

**问题**：handler 的最优执行顺序应该从历史数据中学习，而不是人工固定。

**建议**：

```pascal
// 每次恢复完成后自动更新统计
// 定期重新计算有效优先级：
EffectivePriority := BasePriority - Round(SuccessRate * 50);
// 成功率越高 → 数字越小 → 越靠前执行
```

**安全边界**：
- `afLocked` 的 handler 不参与自适应排序
- 自适应调整幅度有上限（不能偏离 BasePriority 超过 ±30）
- 样本量不足时（< 10 次调用）不调整

**作为 Feature Flag**：`gfAdaptive`

**复杂度**：中

---

### 进化 8：自省（Describe / 行为地图）

**问题**：复杂系统有多个 Grid，管理员需要"看到"整个系统的行为拓扑。

**建议**：

```pascal
function Grid.Describe: TGridDescription;

TGridDescription = record
  Name: string;
  HandlerCount: Integer;
  EnabledCount: Integer;
  Handlers: TArray<THandlerDescription>;
end;

THandlerDescription = record
  Key: string;
  Priority: Integer;
  Enabled: Boolean;
  Locked: Boolean;
  ErrorStrategy: TErrorStrategy;
  Metrics: TActionMetrics;  // 调用次数、成功率、平均耗时
  HasCondition: Boolean;
end;
```

**用途**：Admin UI 展示、Dashboard 行为地图、调试时快速了解系统配置。

**复杂度**：低（纯数据导出，不改执行逻辑）

---

### 进化 9：A/B 测试（版本化执行对比）

**问题**：修改了策略配置后，想对比新旧配置的效果。

**建议**：

```pascal
Grid.SetABTest('recovery_v2', 0.2);  // 20% 流量走新配置版本
// 自动统计两个版本的成功率
// 一周后可以看对比报告，决定是否全量切换
```

**适用场景**：
- Token 预算策略调整（新预算 vs 旧预算的返工率对比）
- 恢复策略优先级调整
- 上下文层组合实验

**复杂度**：高（需要配置快照 + 流量分配 + 对比统计）

---

### 进化 10：多 Grid 编排（Grid Composition）

**问题**：复杂流程可能需要多个 Grid 串联——Grid A 的输出作为 Grid B 的输入。

**场景**：
```
RequestPipeline Grid → 产出 ProcessedRequest
  → RecoveryGrid（如果 Pipeline 失败）
  → AuditGrid（无论成功失败都执行）
```

**建议**：

```pascal
type
  TGridChain<TContext> = class
    procedure Add(AGrid: TActionGrid<TContext>; ARunMode: TRunMode);
    procedure AddOnError(AGrid: TActionGrid<TContext>);
    procedure AddAlways(AGrid: TActionGrid<TContext>);  // finally 语义
    function Execute(var AContext: TContext): Boolean;
  end;
```

**本质**：Grid 的 Grid——用同样的声明式思路编排多个 Grid。

**复杂度**：中

---

### 派生场景汇总（ActionGrid 在 DeepDev 中的应用）

| 场景 | Grid 类型 | Context | 执行模式 |
|------|-----------|---------|----------|
| 错误恢复 | RecoveryGrid | TRecoveryContext | RunUntilResolved |
| 质量门禁链 | QualityGateGrid | TQualityContext | RunAll + esAbort |
| 上下文组装 | ContextAssemblyGrid | TContextBuildContext | RunAll + Parallel |
| 军帐角色响应 | TentRoleGrid | TTentContext | RunUntilResolved |
| 契约清晰度评估 | ClarityCheckGrid | TClarityContext | RunAll |
| Dashboard 数据聚合 | DashboardGrid | TDashboardContext | RunAll + esSkip |
| 任务分解策略 | DecomposeGrid | TDecomposeContext | RunFirst |
| 代码扫描规则 | ScanRuleGrid | TScanContext | RunAll |
| 通知路由 | NotificationGrid | TNotifyContext | RunAll |
| 车间调度策略 | ScheduleGrid | TScheduleContext | RunFirst |

---

### 设计原则补充

基于以上讨论，ActionGrid 的设计原则从 8 条扩展为：

9. **渐进复杂度**：核心 4 方法覆盖 80% 场景；进化能力按需启用，不强制
10. **组合优于继承**：Sub-Grid、GridChain、Parallel 都是组合方式，不需要子类化
11. **学习优于配置**：自适应优先级让系统从数据中学习最优行为，减少人工调参
12. **可观测优于可控制**：先让行为可见（Describe、Metrics），再考虑控制（A/B、热更新）


---

## 深度优化讨论（圆桌第二轮）

### 质疑与回应

| 质疑 | 提出者 | 结论 |
|---|---|---|
| 扁平字典性能退化（200+ Action 线性扫描） | 阿杰 | 桌面应用微秒级，不是瓶颈。Trie 是过度工程。 |
| 单一职责违反（注册+配置+执行+监控+审计塞一个类） | 老陈 | 用 Feature Flags 内部控制，不用装饰器（Delphi 泛型限制） |
| 一维列表不够，应该是二维 Grid（Key × Context 条件） | 老陈 | `When` 条件作为可选第二维，不用时零开销 |
| Strategy 暴露增加使用者认知负担 | 阿杰 | Strategy 作为内部实现，不暴露（除 `ExecuteWith` 逃生舱） |

### 最终设计原则：表面极简，内部可扩展

```
使用者看到的：4 个方法（Add / Run / RunAll / SetEnabled）
高级用户看到的：Builder 模式（AddEx + TActionDef）+ 配置方法
框架开发者看到的：Strategy + Feature Flags + Copy-on-Write
```

### 最优 API 设计

```pascal
TActionGrid<T> = class
public
  // ═══ 核心 API（30 秒上手）═══
  procedure Add(const AKey: string; AHandler: TProc<T>; APriority: Integer = 0);
  function Run(const AKey: string; var AContext: T): Boolean;
  function RunAll(var AContext: T): Integer;
  procedure SetEnabled(const AKey: string; AEnabled: Boolean);

  // ═══ 高级注册（Builder 模式，需要时用）═══
  procedure AddEx(ADef: TActionDef<T>);

  // ═══ 高级配置（独立方法，不污染核心）═══
  procedure BindConfig(ASource: IGridConfigSource);
  procedure EnableMetrics;
  procedure EnableAudit;

  // ═══ 查询（Admin UI / 调试）═══
  function GetAll: TArray<TActionInfo>;
  function GetMetrics: TArray<TActionMetrics>;
  function DryRunAll: TArray<string>;

  // ═══ 逃生舱（1% 高级场景）═══
  function ExecuteWith(AStrategy: IExecutionStrategy<T>; var AContext: T): Integer;
end;
```

### Builder 模式（高级注册）

```pascal
TActionDef<T> = record
  function Key(const AKey: string): TActionDef<T>;
  function Handler(AHandler: TProc<T>): TActionDef<T>;
  function Priority(APriority: Integer): TActionDef<T>;
  function Group(const AGroup: string): TActionDef<T>;
  function Caption(const ACaption: string): TActionDef<T>;
  function Shortcut(const AShortcut: string): TActionDef<T>;
  function When(ACondition: TFunc<Boolean>): TActionDef<T>;
  function OnError(AStrategy: TErrorStrategy): TActionDef<T>;
  function Fallback(AHandler: TProc<T>): TActionDef<T>;
  function Locked: TActionDef<T>;
  function DependsOn(const AKeys: TArray<string>): TActionDef<T>;
end;

// 使用
Grid.AddEx(
  TActionDef<TCtx>.Create('edit.copy')
    .Handler(DoCopy)
    .Priority(10)
    .Caption('复制')
    .Shortcut('Ctrl+C')
    .When(function: Boolean begin Result := HasSelection end)
    .OnError(esSkip)
);
```

### 为什么这是最优解

1. **简单的事简单做** — `Grid.Add('key', Handler)` 一行搞定，比 if/else 还短
2. **复杂的事也能做** — Builder 模式支持任意元数据，不限制上限
3. **不强制复杂度** — 不用 Builder 就不用，核心 4 方法零认知负担
4. **内部可演进** — 未来加 Trie、加并行 Strategy、加分布式配置，API 表面不变
5. **Delphi 原生** — 不依赖 RTTI、不依赖 Attribute、不依赖第三方，纯泛型 + 接口


---

## ASTO 哲学升华（2026-05-09 圆桌会议·第二轮）

> 状态：发散讨论，待人类确认。

---

### ActionGrid 在 ASTO 中的定位

ActionGrid 是 **ASTO 公理三（合规性传递）** 的工程化实现：

> "行为倾向于沿阻抗最小的路径流动。规范通过定义低阻抗通道，引导应力有序传递。"

映射关系：
- `Add` = 定义低阻抗通道（注册合规路径）
- `SetEnabled` = 调整阻抗分布（运行时改变哪条路径阻抗最低）
- `RunAll` = 让行为沿低阻抗路径流动
- `esAbort/esSkip/esRetry` = 定义路径断裂时的应力传导方式

### 哲学本质

**ActionGrid 把"改变系统行为"从"改代码"（创造新属性）降维为"改配置"（调整既有属性的变迁路径）。**

这正是 ASTO 三元引擎的核心洞察：**改造不是创造，是调速。**

```
系统行为改变 = 已注册的能力（既有属性）× 配置变更（扰动）× 新的执行路径（变迁路径）
```

### 五态演进视角

| 五态 | ActionGrid 对应 |
|------|-----------------|
| 自在态 | 开发者脑中"需要分发机制"的模糊感觉 |
| 共识态 | 团队约定"用注册表模式" |
| 编码态 | `TActionGrid<TContext>` 的 4 个方法 |
| 物化态 | 配置表 + 热更新 + Metrics 的运行时系统 |
| 定向态 | 自适应优先级 + 自省 + A/B 测试（系统修改自身规则） |

### 动变性四分类视角

| 动变性类型 | ActionGrid 对应 | 状态 |
|-----------|----------------|------|
| 本律式 | `Run(key)` — 确定性路由 | ✅ 已实现 |
| 涌现式 | 多 handler 交互产生的整体行为 | ✅ 已实现 |
| 目标式 | `RunUntilResolved` — 有目标的执行 | 🔶 待实现 |
| 建模式 | 自适应优先级 — 修改自身规则 | 🔶 待实现 |

### 升华后的命名与定位

- **设计模式**：场域构造器（Field Constructor）
- **设计思想**：改造即调速（Transformation as Acceleration）
- **设计哲学**：能力先在 + 扰动调速 + 定向自演化

### 通用方法论（ASTO 版）

```
任何复杂系统的治理：
1. 识别既有属性（能力注册）— 一元：存在先在
2. 定义阻抗分布（配置意愿）— 二元：观看切分
3. 施加精确扰动（执行/热更新）— 三元：改造调速
4. 观测变迁结果（Metrics/自省）— 回溯
5. 修改阻抗分布（自适应学习）— 定向态
```

---

## 应用到程序开发：哪些方面可以用 ActionGrid 思想简化？

> 状态：待讨论确认。

### 核心判断标准

一个程序中，凡是存在以下信号的地方，都适合用 ActionGrid 思想重构：

1. **一个中心点分发多个操作**（if/else 或 case 膨胀）
2. **加新功能需要改中心类**（违反开闭原则）
3. **关闭某功能需要改代码而非改配置**
4. **无法回答"系统现在启用了哪些行为"**
5. **测试一个功能需要启动整个系统**

### DeepDev 中的具体应用场景

| 场景 | 当前实现 | ActionGrid 重构后 | 简化效果 |
|------|----------|-------------------|----------|
| **AI 错误恢复** | 分散在 3 个文件的 if/else | RecoveryGrid.RunUntilResolved | 加新策略=一行 Add |
| **质量门禁链** | CtrlWorkshopThread 硬编码阶段 | QualityGateGrid.RunAll | 门禁可配置、可跳过、可热更新 |
| **上下文 17 层组装** | CtrlContextAssembler 逐层 if | ContextGrid.RunAll + Parallel | 层可配置启用/禁用，可并行 |
| **Provider 路由** | CtrlBigModelCall if/else | ProviderGrid.Run(kind) | 加 provider=一行 Add |
| **ViewMain 按钮分发** | 50+ BtnXxxClick 方法 | CommandGrid.Run(cmdId) | 主窗体永远不变 |
| **Dashboard 数据聚合** | PresenterDashboard 串行查询 | DashboardGrid.RunAll(esSkip) | 慢查询自动跳过，不阻塞 |
| **契约清晰度检查** | quality_score 计算逻辑 | ClarityGrid.RunAll | 检查项可配置、可扩展 |
| **通知路由** | CtrlNotificationService if/else | NotifyGrid.Run(type) | 通知渠道可热插拔 |
| **代码扫描规则** | CtrlSecurityScanner 硬编码规则 | ScanRuleGrid.RunAll | 规则可热更新、可禁用 |
| **军帐角色响应** | FraTent 硬编码角色逻辑 | TentRoleGrid.RunUntilResolved | 角色可配置、可扩展 |

### 简化程度量化预估

| 指标 | 当前 | ActionGrid 后 | 改善 |
|------|------|---------------|------|
| ViewMain 逻辑行数 | ~1500 行 | ~200 行（纯委托） | -87% |
| 加一个新 provider | 改 3 个文件 | 1 行 Add | -67% 文件改动 |
| 加一个恢复策略 | 改 CtrlWorkshopThread | 1 行 Add | 零改动中心类 |
| 关闭变异测试 | 改代码 + 重编译 | SetEnabled('mutation', False) | 零编译 |
| 查看系统当前行为 | 读代码 | Grid.Describe | 秒级可见 |

### 渐进式迁移路径（DeepDev 专用）

```
Phase 1（低风险，立即可做）：
  ├── ViewMain 按钮分发 → CommandGrid
  ├── Provider 路由 → ProviderGrid
  └── 通知路由 → NotifyGrid

Phase 2（中风险，13.1 迁移后）：
  ├── AI 错误恢复 → RecoveryGrid
  ├── 质量门禁链 → QualityGateGrid
  └── 代码扫描规则 → ScanRuleGrid

Phase 3（需要设计，稳定后）：
  ├── 上下文组装 → ContextGrid + Parallel
  ├── Dashboard 聚合 → DashboardGrid
  └── 军帐角色 → TentRoleGrid
```


---

## IntentMap：ActionGrid 在 UI 层的延伸（2026-05-09 圆桌会议·第三轮）

> 状态：发散讨论，待人类确认。

### 核心洞察

ActionGrid 管理"系统做什么"（行为），IntentMap 管理"系统看起来什么样"（表现）。两者是同一思想的两面：

```
ActionGrid: 行为 = 能力 × 意愿
IntentMap:  外观 = 属性集 × 状态条件
```

### 传统流程 vs IntentMap 流程

| | 传统 | IntentMap |
|---|---|---|
| 设计师产出 | 静态界面图 | Intent 属性集（多状态声明） |
| 开发者实现 | DFM + if/else 状态逻辑 | Declare + BindTo |
| 运行时 | 不变 | 可变（语言/主题/状态自动切换） |
| AI 可生成 | 困难（逻辑散落） | 容易（结构化声明） |

### Intent 声明示例

```
Intent: 'file.save'
├── 默认态：Caption='Save', Icon='save.png', Enabled=true
├── 中文态：Caption='保存'
├── 暗色态：Icon='save_dark.png'
├── 无修改态：Enabled=false, Caption='已保存'（灰色）
└── 保存中态：Caption='保存中...', Icon='spinner.gif'
```

### 对 DeepDev 的具体价值

| 痛点 | IntentMap 解法 |
|------|---------------|
| 50+ 按钮状态散落在代码各处 | 每个 Intent 一个声明 |
| i18n (`T()`) 和 Theme (Palette) 分离 | Intent 属性集包含语言和主题层 |
| 状态灯（白/绿闪/红闪/长绿）分散在多个 Presenter | Intent 状态声明统一管理 |
| AI 难以生成散落的 UI 逻辑 | AI 直接生成 Intent 声明 |
| ViewMain 组件声明不能移动 | 组件只是容器，动态属性由 IntentMap 驱动 |

### 契约与界面的关联性：显三元，本一元

**核心洞察**：

> Intent 是一元（用户意图的不可分割整体）。
> 视觉/行为/条件是显三元（工程分析视角）。

传统开发把一个"保存"拆成三个独立的东西：视觉（设计师管）、行为（开发者管）、条件（产品经理管）。三个人各管一块，三份文档，三处代码。

但用户感知到的从来不是三个东西。用户感知到的是"保存"这个意图——一个不可分割的整体。

```
一元（Intent）：'file.save' — 用户的完整意图
    │
    ├── 显三元（分析视角）：
    │   ├── 视觉面：Caption, Icon, Color, Animation
    │   ├── 行为面：Handler, ErrorStrategy, Priority
    │   └── 条件面：When(state), Enabled, Visible
    │
    └── 运行时三者合一为一个原子体验
```

**代码表达**：

```pascal
// 一个 Intent = 一个注册 = 一个原子单元
Intent.Register('file.save')
  .Action(DoSave)                    // 行为面
  .Caption('Save').Icon('save.png')  // 视觉面
  .EnabledWhen(FileModified)         // 条件面
  .Locale('zh-CN', Caption := '保存')
  .State('saving', Caption := '保存中...', Enabled := False);

Intent.BindTo(BtnSave);  // 绑定到控件
```

**对契约的影响**：

契约以 Intent 为单位，不再分"功能契约"和"UI 规格"：

```
契约: '文件保存'
└── Intent: 'file.save'
    ├── AC-001: 点击时保存文件（行为面）
    ├── AC-002: 未修改时禁用（条件面 + 视觉面）
    └── AC-003: 保存中显示进度（条件面 + 视觉面）
```

**设计原则**：

1. 契约以 Intent 为单位（不分功能/UI 两份文档）
2. 代码以 Intent 为单位注册（视觉/行为/条件同一声明）
3. 验收以 Intent 为单位（一个 Intent 所有状态要么全过要么全不过）
4. AI 生成以 Intent 为单位（一次生成完整声明）

**ASTO 映射**：

- 本一元 = Intent（用户意图的不可分割整体）
- 显三元 = 视觉/行为/条件（工程化的必要切分）
- ActionGrid + Intent 的统一 = 让三元在代码中重新合一为一元
