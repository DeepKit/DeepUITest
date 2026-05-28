# Intent Map System × ASTO 融合论

> 将 ASTO（属集变迁存在论）的哲学框架与 IMS（Intent Map System）的工程实现进行深度对接
> 日期：2026-05-09
> 状态：初稿，待圆桌讨论

---

## 一、核心同构：IMS 是 ASTO 在软件工程中的一个实例化

### ASTO 的核心公式

```
世界 = 属集（属性集合）在时间中的变迁
变迁 = 扰动（改变属性变化率的事件）在场域中的传播
```

### IMS 的核心公式

```
软件行为 = Intent（意图属性集）在运行时的解析
行为变迁 = Policy 变更（改变 Intent 启用/优先级/参数的事件）在系统中的传播
```

### 同构映射

| ASTO 概念 | IMS 对应 | 关系 |
|---|---|---|
| 属集（Attribute-Set） | Intent Entry（意图条目的完整属性集） | 一个 Intent = 一个属集切片 |
| 属性（Property） | Props（caption, icon, enabled, priority, handler...） | Intent 的每个字段 = 一个属性 |
| 变迁（Transition） | Policy 变更导致属性从初始态到当前态 | SetPolicy = 触发属集变迁 |
| 扰动（Perturbation） | Run / Resolve（执行一个意图） | 用户操作 = 对系统的扰动 |
| 场域（Field） | TContext（意图执行时的上下文环境） | Context = 扰动发生的活空间 |
| 五态 | Intent 的生命周期 | 见下文 |
| 六阶 | 系统的演化节律 | 见下文 |
| 七序 | 开发者使用 IMS 的行动步骤 | 见下文 |
| 动变性（Motility） | 热配置 + 版本化 + 回滚 | 系统行为的可变性 |
| 基元 | afLocked 的 Intent（不可禁用） | 系统生存的最低条件 |
| 禁行红线 | ErrorStrategy = esAbort | 绝对不可违反的边界 |
| 风险层 | 熔断机制 + 人类裁决接口 | 当系统进入悖论态时的保护 |

---

## 二、五态在 IMS 中的展开

一个 Intent 从"脑中想法"到"运行时行为"的演化过程，精确对应 ASTO 的五态：

| 五态 | IMS 中的表现 | 示例 |
|---|---|---|
| **自在态** | 开发者脑中的模糊需求："这里需要一个保存功能" | 未写代码，未声明 |
| **共识态** | 团队讨论确认："保存按钮放在工具栏，快捷键 Ctrl+S" | 口头约定，未形式化 |
| **编码态** | `Grid.Declare('file.save').Handler(DoSave).Shortcut('Ctrl+S')` | 代码声明，可编译 |
| **物化态** | `Grid.BindTo(btnSave, 'file.save')` — 界面上出现了按钮 | 用户可见可交互 |
| **定向维** | `Grid.BindConfig(DBSource)` — 行为可被运行时配置驱动 | 自演化，元规则生效 |

**关键洞察**：传统 Delphi 开发直接从"自在态"跳到"物化态"（在 DFM 里放按钮 + 写 OnClick），跳过了"编码态"的形式化声明。这导致行为和界面焊死在一起，无法独立演化。

IMS 强制插入"编码态"（Declare），使得行为可以独立于界面存在、独立于运行时配置存在。这正是 ASTO 所说的"介质代际跃迁"——从第三代（代码即行为）到第四代（属性集即行为）。

---

## 三、六阶在 IMS 中的展开

一个使用 IMS 的系统在时间中的演化节律：

| 六阶 | IMS 系统的表现 | 信号 |
|---|---|---|
| **混沌** | 项目初期，行为散落在各处 if/else 中 | 无法说清"系统能做什么" |
| **秩序** | 引入 IMS，所有行为注册到 Grid | `DryRunAll` 能列出完整行为清单 |
| **流变** | 需求变化，不断 Add 新 Intent，调整 Priority | Metrics 显示某些 Intent 调用频率变化 |
| **脉冲** | 某个关键 Intent 的 ErrorStrategy 频繁触发 | 慢告警 + 错误率飙升 = 跃迁信号 |
| **崩解** | 旧的 Intent 组合无法满足新需求，需要重构 | 大量 Intent 被 SetEnabled(False) |
| **归元** | 重新 Declare 一组新 Intent，旧的 Deprecated | 新的 DryRunAll 输出稳定 |

**关键洞察**：IMS 的 Metrics 和 DryRun 能力，使得六阶的"节律"变得**可观测**。传统代码中，你无法知道系统处于哪个阶段；有了 IMS，你可以通过 Metrics 数据判断系统是否进入了"流变"或"脉冲"阶段。

---

## 四、七序在 IMS 中的展开

开发者使用 IMS 重构一个上帝类的行动步骤：

| 七序 | IMS 中的行动 | 产出 |
|---|---|---|
| **感知** | 发现 ProxyServer.pas 有 3678 行，无法维护 | 问题意识 |
| **解析** | 分析发现：30 个 Admin handler + 15 个管道阶段混在一起 | 定位主要矛盾 |
| **干预** | 决定引入 IMS，把 if/else 分发替换为 Grid.Run | 方案选择 |
| **设计** | 为每个 handler 设计 Intent Entry（Key, Priority, ErrorStrategy） | 属集模式设计 |
| **物化** | 编写代码：`Grid.Declare(...)` + `Grid.BindTo(...)` | 落地执行 |
| **回溯** | 运行 DryRunAll 验证执行计划，检查 Metrics | 效果验证 |
| **消解** | 删除旧的 if/else 代码，标记旧方法为 Deprecated | 扬弃旧属集模式 |

---

## 五、ASTO 公理对 IMS 设计的约束

### 公理零（环境熵增）→ IMS 必须有"最后已知良好配置"

不维护的系统默认崩溃。如果 IMS 的配置源（DB）不可用，系统不能停止工作。必须保持上一次成功加载的配置继续运行。

### 公理一（属集切片）→ IMS 是系统行为的"低熵孤岛"

IMS 的注册表就是系统行为的有序描述。没有 IMS，行为散落在代码各处（高熵）；有了 IMS，行为被集中管理（低熵）。维持这个低熵状态需要持续投入（Metrics 监控、配置维护）。

### 公理三（合规性传递）→ IMS 的 API 必须是"最低阻抗路径"

如果 `Grid.Add('key', Handler)` 比写 if/else 更麻烦，开发者就不会用它。IMS 的 API 设计必须让"正确的做法"比"错误的做法"更简单。这就是为什么核心 API 只有 4 个方法。

### 公理五（属集自指/技术债）→ IMS 本身也会积累技术债

随着 Intent 数量增长，IMS 的注册表本身也会变得复杂。需要定期审计（哪些 Intent 从未被调用？哪些 ErrorStrategy 从未触发？）。Metrics 就是这个审计工具。

### 公理六（规范跃迁）→ IMS 支持"版本化 + 回滚"

当系统需要跃迁（大版本升级），旧的 Intent 配置需要被整体替换。版本化配置 + Rollback API 就是为跃迁准备的"备用胎"。

### 公理八（实践回路）→ IMS 的 Metrics 是实践回路的反馈环

```
Declare（属集模式）→ Run（实践）→ Metrics（反馈）→ SetPolicy/调整（修正属集模式）
```

没有 Metrics，IMS 就是一个静态注册表。有了 Metrics，它变成了一个活的实践回路。

### 公理九（内在张力）→ IMS 允许矛盾共存

同一个 Key 可以有多个 Handler（通过 When 条件区分）。不同 Intent 之间可能有优先级冲突。这不是 bug，是系统保持活力的内在张力。

### 公理十一（自由）→ IMS 的 SetEnabled 是"边界内的自由"

管理员可以在运行时启用/禁用任何非 Locked 的 Intent。这是在 afLocked 边界内的自由。没有 afLocked，自由就没有边界，系统就会崩溃。

### 公理十二（悖论熔断）→ IMS 的 esAbort + 人类裁决

当一个 Critical Intent（如 Auth）失败时，系统不能"智能地绕过"，必须中止并等待人类裁决。这就是 `esAbort` + `afLocked` 的组合——悖论熔断的工程实现。

---

## 六、IMS 作为 ASTO 第四代介质的工程实现

ASTO P04 提出了介质的代际跃迁：

| 代际 | 介质 | 特性 |
|---|---|---|
| 第一代 | 口头语言 | 瞬时、易变 |
| 第二代 | 文字/法律 | 持久、需阐释 |
| 第三代 | 代码/算法 | 精确、可执行 |
| **第四代** | **属性集** | **结构化、可迁移、自演化** |

IMS 的 Intent Entry 就是第四代介质的一个实例：

- **结构化**：每个 Intent 有明确的属性集（Key, Props, Handler, Priority, ErrorStrategy, When）
- **可迁移**：Intent 的定义可以从代码迁移到数据库，从一个项目迁移到另一个项目
- **自演化**：通过 Metrics + 自适应优先级，Intent 的行为可以从历史数据中学习

传统代码（第三代介质）只记录"做什么"，不记录"为什么做"和"什么条件下做"。
IMS（第四代介质）同时记录：能力（Handler）+ 意图（Key/Description）+ 条件（When）+ 策略（Priority/ErrorStrategy）+ 历史（Metrics）。

---

## 七、IMS 的"属集"本质——每个 Intent 是一个活的属集

这是 ASTO 给 IMS 最深刻的启示。

一个 Intent Entry 不是一个"函数指针"，它是一个**完整的属集**：

```pascal
TIntentEntry = record
  // 硬属性（不可由运行时配置改变）
  Key: string;           // 身份标识
  Handler: TProc<T>;     // 行为能力
  
  // 软属性（可由 Policy/Resolver 改变）
  Caption: string;       // 当前态 = Resolver(初始态, 语言策略)
  Icon: string;          // 当前态 = Resolver(初始态, 主题策略)
  Enabled: Boolean;      // 当前态 = When条件 × Policy配置
  Priority: Integer;     // 当前态 = 基础值 × 自适应调整
  
  // 元属性（描述属集本身的属性）
  Metrics: TMetrics;     // 调用次数、错误率、平均耗时
  Version: Integer;      // 配置版本
  UpdatedAt: TDateTime;  // 最后变更时间
end;
```

**初始态**是代码声明的默认值（编码态）。
**当前态**是经过所有 Resolver（策略解析器）计算后的实际值（物化态）。
**变迁**发生在 Policy 变更时（语言切换、主题切换、功能开关切换）。

这意味着：
- i18n 不是独立子系统，而是 `Caption` 属性的 Resolver
- Theme 不是独立子系统，而是 `Icon`/`Color` 属性的 Resolver
- FeatureFlags 不是独立子系统，而是 `Enabled` 属性的 Policy

**一个 IMS 统一了所有这些"子系统"——因为它们本质上都是"属集属性在不同策略下的变迁"。**

---

## 八、待讨论问题（圆桌议题）

1. **IMS 的"观察者效应"**：当 Admin 查看 Metrics 时，是否会影响系统行为？（如：Metrics 收集本身有性能开销）
2. **IMS 的"不可约性"**：哪些行为决策是 IMS 无法自动化的，必须保留人类裁决？
3. **IMS 的"跃迁临界"**：当 Intent 数量超过某个阈值，IMS 本身是否需要"跃迁"（重构为分布式/分层结构）？
4. **IMS 与 ASTO 的"双重时间"**：τ-time（配置版本号）和 χ-time（团队对系统行为的理解演化）如何在 IMS 中体现？
5. **IMS 的"自指性"**：IMS 能否管理自己？（用一个 Intent 来控制 IMS 自身的行为）
6. **IMS 的"介质跃迁"**：从代码声明（第三代）到数据库配置（第四代）的迁移路径是什么？渐进式还是一次性？


---

## 九、圆桌讨论：ASTO 对软件设计的通用性与指导性

### 三个核心命题（周教授）

1. **存在即属集，属集即变迁** → 不要设计"完美终态"，要设计"可变迁的结构"
2. **改造即调速，不是创造** → 好架构不是发明新东西，而是让正确的事更容易发生
3. **二元是认知代价，三元是介入最小完备结构** → 理解系统需要对象化，改变系统需要扰动者+场域+介质

### 指导性的三个层次

| 层次 | 适用范围 | ASTO 公理 | 工程表现 |
|---|---|---|---|
| 普适 | 所有软件 | 零（熵增）、三（阻抗）、五（技术债）、八（实践回路） | 持续维护、API 易用性、测试验证 |
| 有条件 | 中大型系统 | 六（跃迁）、九（张力） | 版本升级策略、矛盾管理 |
| 特定场景 | 高变迁系统 | 十二（熔断）、十一（自由） | 安全熔断、人机分工 |

### 六条普适工程原则（从 ASTO 推导）

1. **设计可变迁的结构，而非完美的终态**（五态思维）
2. **降低正确路径的阻抗，提高错误路径的阻抗**（公理三）
3. **让系统行为可观测、可审计、可回滚**（实践回路）
4. **区分"必须人类裁决的"和"可以自动化的"**（不可约性）
5. **接受矛盾存在，管理张力而非消除张力**（公理九）
6. **知道何时该"维护"，何时该"跃迁"**（公理五→六临界判断）

### 工程检查清单（阿杰）

| 公理 | 每天问自己的问题 |
|---|---|
| 零 | 系统 3 个月没人碰，还能正常运行吗？ |
| 一 | 能用一句话说清系统边界在哪里吗？ |
| 三 | 新人加入后，做对的事比做错的事更容易吗？ |
| 五 | 知道系统里哪些代码维护成本最高吗？ |
| 六 | 如果要重写核心模块，有回滚方案吗？ |
| 八 | 设计假设有自动化测试验证吗？ |
| 九 | 能说出系统里最大的"矛盾"是什么吗？ |

### 关键洞察

**小林**：ASTO 给了"何时引入复杂度"的判断标尺——看五态阶段。自在态硬编码，共识态声明注册，物化态可配置，定向维自演化。

**苏姐**：界面设计中"观察即扰动"——每个按钮的位置/颜色/大小都在"调速"用户行为。IMS 让这种调速变得显式、可审计、可调整。

**韩工**：AI 系统应遵循"AI 调场域，人做裁决"——AI 调整优先级排序（改变河道），人通过 afLocked 保留最终决策权（不可约性）。

### 通用性边界结论

ASTO 不是"万能理论"。它的指导性随系统复杂度递增而逐步适用：
- 5 人以下小项目：用检查清单就够
- 中型项目（10-50 人）：需要 IMS 的核心形态
- 大型系统（50+ 人/多项目生态）：需要 IMS 完整形态 + ASTO 的跃迁/熔断机制


---

## 十、圆桌讨论：IMS 如何重画 DeepBase 的子系统边界

### 核心洞察（周教授）

DeepBase 的 i18n / Theme / Config / Hotkeys / FeatureFlags 本质上都在做同一件事：**根据某个策略（Policy），解析某个属性的当前值。** 它们不是五个独立系统，而是同一个"属性解析引擎"的五种特化。

### 分层统一方案（小林）

```
底层：TPropertyResolver 接口（通用属性解析）
  ├── TDictResolver（i18n，纯字典 O(1)）
  ├── TThemeResolver（Theme，样式表查找）
  ├── TConfigResolver（Config，DB + 缓存）
  └── THotkeyResolver（Hotkeys，快捷键映射）

中层：TIntentMap（IMS 核心）
  - 每个 Intent 的每个 Prop 绑定一个 Resolver
  - 统一的是接口，不是实现

上层：PolicyBus（策略变更通知）
  - SetPolicy → 通知所有 Resolver 刷新 → 界面自动更新
```

### 两阶段初始化（阿杰）

```pascal
// 阶段 1：纯内存（编码态）
FIntentMap := TIntentMap<TAppContext>.Create;
// 只有代码声明的默认值

// 阶段 2：绑定数据源（物化态）
DeepBase.Manager.Initialize;
FIntentMap.BindResolver('caption', TDictResolver.Create(Manager.ConfigDB));
FIntentMap.BindResolver('icon', TThemeResolver.Create(ThemeFile));
// 属性从初始态变迁到当前态
```

### 设计师工作流变化（苏姐）

设计师不再设计"一个界面"，而是设计"一个意图在所有可能状态下的表现"：

```
Intent: 'file.save'
  ├── 默认态：Caption='Save', Icon='save.png', Enabled=true
  ├── 中文态：Caption='保存'
  ├── 暗色态：Icon='save_dark.png'
  ├── 无修改态：Enabled=false, Caption='已保存'
  └── 保存中态：Caption='保存中...', Icon='spinner.gif'
```

### AI 学习可能性（韩工）

当所有属性在统一 IntentMap 中，AI 可以发现属性间的关联模式：
- 主题切换 → 字体偏好关联
- Intent 禁用 → 替代 Intent 使用率上升
- ErrorStrategy 频繁触发 → 优先级调整建议

### 对 DeepBase 架构的影响

| 变化 | 旧架构 | 新架构 |
|---|---|---|
| 初始化 | Manager 分别初始化 5 个子系统 | IntentMap 两阶段初始化 |
| 策略变更 | 每个子系统自己处理 | PolicyBus 统一通知 |
| 界面绑定 | 每个子系统自己的 BindXxx | IntentMap.BindTo 统一绑定 |
| 可观测性 | 各自独立的日志 | IntentMap.Metrics 统一度量 |
| 热更新 | 各自独立的 Reload | IntentMap.ReloadConfig 统一刷新 |


---

## 十一、圆桌讨论：IMS 的自指性

### 问题

IMS 管理所有行为。IMS 自身的行为（ReloadConfig、Metrics、SlowAlert）是否也应该被注册为 Intent？

### 结论：可以，且应该

IMS 的元行为注册为 Intent，放在 `_meta` 分组：

```pascal
FMap.Declare('_meta.reload_config', DoReload, [afLocked, afHidden]);
FMap.Declare('_meta.metrics', DoMetrics, [afLocked, afHidden]);
FMap.Declare('_meta.slow_alert', DoSlowAlert, [afLocked, afHidden]);
```

### 安全保障

| 风险 | 解决方案 | ASTO 对应 |
|---|---|---|
| 无限递归 | `GDispatchDepth > 8` 熔断 | 公理十二（悖论熔断） |
| 误禁用 | `afLocked` 不允许运行时禁用 | 基元保护 |
| 界面混乱 | `afHidden` 不在普通 Admin 显示 | 信息分层 |
| 维护成本 | Metrics 自身也被 Metrics 度量 | 公理五（自指代价可管理） |

### ASTO 映射

公理五说"属集自指不可避免，代价是维护成本递增"。IMS 管理自己的代价是每次 Run 多一次字典查找（微秒级），可接受。承认自指，管理其成本，不试图消除它。


---

## 十二、圆桌讨论：双重时间、跃迁临界与介质跃迁

### 双重时间在 IMS 中的体现

| 时间类型 | IMS 对应 | 可逆性 | 记录方式 |
|---|---|---|---|
| τ-time（技术时间） | 配置版本号、Rollback | 可回滚 | action_grid_history 表 |
| χ-time（存在时间） | 团队认知、用户习惯、信任 | 不可逆 | action_grid_impact_log 表（人工填写） |

**关键原则**：Rollback 只能回滚 τ-time，不能回滚 χ-time。重大变更的 Rollback 前应提示 χ-time 影响。

### 跃迁临界信号

| 信号 | 阈值 | 行动 |
|---|---|---|
| DryRunAll 输出行数 | > 50 | 引入分组 |
| ReloadConfig 耗时 | > 100ms | 优化配置加载 |
| 同前缀 Intent 数量 | > 20 | 该前缀独立为子 Grid |
| 从未被调用的 Intent 占比 | > 80% | 清理死 Intent |

**跃迁方案**：从单 Grid 到 Grid 树（`Mount` 子 Grid），渐进迁移，不一次性重构。

### 介质跃迁的渐进路径

```
阶段 1：纯代码声明（小项目）
阶段 2：代码 + JSON 文件配置（需要简单热更新）
阶段 3：代码 + DB 配置（需要持久化 + 多人管理）
阶段 4：代码 + DB + Admin UI（需要非开发者可操作）
```

每个阶段独立可用，按需演进。

### 硬属性 vs 软属性（最深层设计约束）

```
代码声明 = 一元（先在的、不可协商的）
  → Handler、Key 不可由配置改变
  → 即使 DB 清空，系统仍以默认值运行

数据库配置 = 三元（可通过扰动调速的）
  → Priority、Enabled、Params 可由配置改变
  → 配置是调速器，不是创造器
```

**ASTO 映射**：你不能通过配置"创造"新行为（违反一元先在性），只能"调速"已有行为的表现（三元调速本质）。


---

## 十三、开放讨论：落地陷阱、协作影响与终极质疑

### 设计师协作问题（苏姐）

IMS 应支持从 YAML 文件加载 Intent 属性定义，让设计师可以直接编辑视觉属性：

```yaml
# intents/file.save.yaml
key: file.save
caption: { default: Save, zh: 保存 }
icon: { light: save_light.png, dark: save_dark.png }
shortcut: Ctrl+S
```

开发者只负责 Handler 和 When 条件。CI 脚本校验 YAML 与代码的一致性。

### 性能陷阱：批量刷新（阿杰）

SetPolicy 不应同步触发所有控件刷新。正确方式：
1. SetPolicy 标记为"脏"
2. PostMessage 延迟到下一个 UI 周期
3. 批量 Resolve 所有脏属性（Resolver 有缓存）
4. 一次性通知所有绑定控件

### IMS 会不会成为新的上帝对象？（韩工）

预防措施：
- 每个项目不超过 3 个 Grid 实例
- 每个 Grid 不超过 100 个 Intent
- 定期审计 Metrics，清理死 Intent
- IMS 框架代码不超过 800 行

### ASTO 的终极警告（周教授）

IMS 本身也是属集，也会积累技术债，也终将面对跃迁。不要试图让它"永远不腐烂"，而是让它的腐烂可观测（Metrics）、可管理（审计）、可替代（不为桥立碑）。

### 设计哲学总结（小林）

> IMS 是一座临时的桥。
> 它连接代码的确定性与运行时的灵活性。
> 当更好的方案出现时，它应该让位。
> 不要为桥立碑。

---

## 十四、下一步行动

| 优先级 | 行动 | 负责 | 产出 |
|---|---|---|---|
| P0 | 实现 IMS 最小核心（4 方法，~100 行） | DeepBase 团队 | `DeepBase.IntentMap.pas` |
| P0 | 在 Assayer ProxyServer 上验证（接入 AdminRouter） | Stream Worker | ProxyServer 瘦身 70% |
| P1 | 实现 PolicyBus（~60 行） | DeepBase 团队 | `DeepBase.PolicyBus.pas` |
| P1 | 实现 Resolver 接口 + DictResolver | DeepBase 团队 | `DeepBase.IntentMap.Resolver.pas` |
| P2 | 实现 DBConfigSource + Metrics | DeepBase 团队 | 完整形态 |
| P2 | 在 DeepSVG 上验证（菜单/命令） | Pixel Worker | 界面解耦验证 |
| P3 | YAML Intent 定义 + CI 校验 | 工具链团队 | 设计师协作流程 |
| P3 | Admin UI 面板 | FMX UI 团队 | 可视化管理 |


---

## 十五、深度讨论：界面与行为的一体性

### 核心命题

界面和行为不是"分开再绑定的两个东西"，而是**同一个意图（Intent）的不同面向**。

ASTO 映射：显三元（视觉/行为/条件），本一元（Intent）。

### 从分离论到一体论

| | 分离论（旧） | 一体论（IMS） |
|---|---|---|
| 本体 | 界面和行为是两个独立实体 | Intent 是不可分割的整体 |
| 关系 | 通过"绑定"连接 | 界面是 Intent 的"投影" |
| 设计问题 | "这个按钮绑定到哪个 Action？" | "这个意图在界面上怎么显现？" |
| 设计师角色 | 设计按钮的样子 | 设计投影规则 |
| AI 生成 | 分别生成 UI + 逻辑（易不一致） | 生成 Intent 声明（天然一致） |

### 投影模型

```
Intent('file.save') = { caption, icon, handler, when, shortcut, priority }
  → ProjectTo(Toolbar)    = 图标按钮
  → ProjectTo(Menu)       = 文字 + 快捷键
  → ProjectTo(RightClick) = 条件可见的文字项
  → ProjectTo(CmdPalette) = 可搜索的结果
```

一个 Intent，多个投影面。Intent 不知道自己被投影到哪里，Projector 不知道 Intent 的业务逻辑。

### API 变化

```pascal
// 旧（分离论暗示）
Grid.BindTo(btnSave, 'file.save');  // 逐个绑定

// 新（一体论暗示）
Grid.ProjectTo(Toolbar, TToolbarProjector);   // 所有 Intent 自动投影
Grid.ProjectTo(PopupMenu, TMenuProjector);    // 一次声明，全部显现
```

### 投影器接口

```pascal
IProjector = interface
  procedure Project(AIntent: TIntentEntry; ATarget: TComponent);
  procedure Refresh(AIntent: TIntentEntry; ATarget: TComponent);
  procedure Remove(AIntent: TIntentEntry; ATarget: TComponent);
end;
```

### 设计师的新角色

设计师不再设计"每个按钮长什么样"，而是设计"投影规则"：
- 工具栏规则：只显示 icon，hover 显示 hint，按 group 分区
- 菜单规则：显示 caption + shortcut，按 group 加分隔线
- 右键规则：只显示 When=True 的 Intent，按 priority 排序

### 哲学警告（周教授）

投影不是无损的。每种投影面都会丢失一些属性。设计师管理的是"简洁 vs 完整"的张力——这是不可消除的，只能被优化。

### 对 ASTO 的回应

ASTO 说"显三元，本一元"。IMS 的一体论是这个命题在软件设计中的直接实现：
- 一元 = Intent（不可分割的意图整体）
- 三元 = 视觉属性 / 行为属性 / 条件属性（分析视角）
- 投影 = 二元切分的代价（每种观察方式都有信息丢失）


---

## 十六、核心修正：一元到三元的精确映射

### 老板的修正

IMS 的三元结构不是"视觉/行为/条件"，而是：

```
行为 — 意图 — 界面
```

这三者都是属集。它们的关系是：

```
一元：Intent（意图）— 不可分割的整体
三元显现：
  - 行为（Handler + ErrorStrategy + Priority）= 意图的"动力因"
  - 意图（Key + When + DependsOn + Description）= 意图的"形式因"  
  - 界面（Caption + Icon + Shortcut + Visible）= 意图的"物化因"
```

### ASTO 精确对应

| ASTO 三元 | IMS 三元 | 因果地位 |
|---|---|---|
| 人（目的因） | 行为（Handler）| 发起者，"做什么" |
| 属集（形式因） | 意图（Key + 条件）| 中介，"什么条件下做" |
| 存在（动力因） | 界面（Props）| 显现，"怎么被看见" |

### 关键洞察

**不是"界面绑定行为"，也不是"行为投影到界面"。**

而是：**行为、意图、界面是同一个属集的三个不可分离的面向。**

就像 ASTO 说的"推石头"：
- 石头的重力（行为）= Handler 的执行能力
- 石头在山上的位置（意图）= Intent 的条件和上下文
- 石头被看见的样子（界面）= 用户感知到的视觉表现

你不能把"重力"从石头上拆下来单独讨论。同样，你不能把"Handler"从 Intent 上拆下来单独存在。

### 对设计模式的根本影响

传统设计模式（MVC/MVVM）的前提是"分离"。IMS 的前提是"一体"。

这不是说不需要代码组织——代码仍然可以分文件、分模块。但**概念上**，一个 Intent 是一个不可分割的原子。分文件只是工程管理的便利，不是本体论的切割。

### 待继续讨论

1. 如果三元是"行为-意图-界面"，那 IMS 的 API 应该怎么重新设计？
2. "意图"作为一元，它的生命周期（五态）具体怎么展开？
3. 这个一体论对 Delphi 的 DFM/FMX 设计时体验有什么影响？
4. 如何让 AI 理解并生成"一体的 Intent"而非"分离的 UI + 逻辑"？
5. 这个思想能否推广到非 Delphi 的其他技术栈（React/Flutter/SwiftUI）？
