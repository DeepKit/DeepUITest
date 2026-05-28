# OCGS-se Delphi 软件优化讨论纪要 v2

> 版本：v2.0  
> 主题：Delphi 软件如何按 OCGS-se 进行重构  
> 核心口径：OCGSRuntime → AccessGateTree（门禁树）→ 各类 Set 挂接  
> 新增修正：UI 不是宿主，UI 是属集的投射；OCGSRuntime 是入口；AccessGateTree 是软件能力世界的进入秩序树。

---

## 1. 总定位

OCGS-se 是 OCGS 在软件领域的展开，是软件创作从“功能生产”走向“能力治理”的范式级理论框架。

在 Delphi 场景中，它不是要推翻 Delphi、VCL、FMX 或 TActionList，而是要把原来混在主窗体和事件代码中的能力、目的、投射、门禁、状态、合当治理重新分层。

传统 Delphi 常见结构：

```text
Application
  → MainForm
    → ButtonClick / MenuClick / ActionExecute
      → Handler / Service / DataModule
```

OCGS-se 建议结构：

```text
OCGSRuntime
  → AccessGateTree / 门禁树
    → ProjectionSet / PurposeSet / AbilitySet / DueSet / ContextSet / StateSet / EventSet / ResourceSet / FeedbackSet / TraceSet
```

核心转向：

> Delphi 软件应从 Form-centered / Event-driven 走向 OCGSRuntime-centered / AccessGateTree-guided / Purpose-oriented / Capability-governed / Due-constrained。

---

## 2. UI 是属集的投射，不是宿主

新的口径必须修正：

> UI 不是宿主，UI 是属集状态的投射。

因此：

- 主窗体不是系统大脑；
- 主窗体不是 PurposeSet 的宿主；
- Frame 不是功能宿主；
- Panel 不是功能容器；
- Button 不是功能；
- MenuItem 不是功能；
- TAction 不是功能本体。

它们都属于 ProjectionSet 的投射节点或投射绑定。

它们承接的是：

```text
PurposeState
AccessGateState
DueProjectionState
RuntimeState
FeedbackState
```

---

## 3. OCGSRuntime 是入口和运行时根

在 Delphi 中，`.dpr` 与 `Application.Initialize` 只是程序启动入口。

OCGS-se 的运行时入口应是：

```text
OCGSRuntime
```

Delphi 类名可暂定：

```pascal
TOCGSRuntime
```

它不是新的上帝类，不生产控件，不写业务逻辑，不替代 Service / DataModule。

它是：

```text
运行时秩序入口
多树多图协调器
Set 注册与解析中心
AccessGateTree 管理者
```

它负责协调：

- AccessGateTree；
- ProjectionSet；
- PurposeSet；
- AbilitySet；
- DueSet；
- ContextSet；
- StateSet；
- EventSet；
- ResourceSet；
- FeedbackSet；
- TraceSet；
- PersistenceSet。

---

## 4. AccessGateTree：门禁树

### 4.1 为什么需要门禁树

软件不是单纯功能列表，也不是单纯 UI 树。

用户、AI 或系统事件进入软件时，真实经历的是：

```text
进入应用
  → 打开窗口
    → 进入区域
      → 打开面板
        → 触发控件
          → 经过状态 / 权限 / 门禁
            → 调用能力
              → 产生结果
```

这就像进入一栋大楼：

```text
大门
  → 房间门
    → 内部门
      → 守卫
        → 密码
          → 虹膜
            → 保险柜
```

所以软件里存在一棵“门禁树”。

### 4.2 定义

> AccessGateTree（门禁树）是 OCGSRuntime 下的软件进入路径总树。它以“门”为界面、窗口、区域、面板、控件、命令、AI入口等可进入界面路径，以“禁”为权限、上下文、状态、风险、契约、门禁、证据、封存、责任、能力可用性等不可见治理条件，管理人、AI、系统事件如何逐层进入软件能力世界。

更短：

> 门禁树 = 软件能力世界的进入秩序树。

---

## 5. “门”与“禁”

### 5.1 门：可进入界面路径

“门”包括：

- AppGate：应用入口；
- WorkspaceGate：工作区入口；
- ProjectGate：项目入口；
- WindowGate：窗口入口；
- FrameGate：Frame 入口；
- RegionGate：区域入口；
- PanelGate：面板入口；
- TabGate：页签入口；
- MenuGate：菜单入口；
- ActionGate：TAction 入口；
- ControlGate：按钮 / 控件入口；
- DialogGate：弹窗确认入口；
- CommandGate：命令面板入口；
- AIGate：AI 可读入口。

### 5.2 禁：治理条件与不可见运作体系

“禁”包括：

- PermissionGate：权限门；
- ContextGate：上下文门；
- StateGate：状态门；
- RiskGate：风险门；
- ContractGate：契约门；
- AcceptanceGate：验收门；
- EvidenceGate：证据门；
- SealGate：封存门；
- AccountabilityGate：责任门；
- AbilityGate：能力可用门；
- SystemGate：系统环境门。

---

## 6. AccessGateTree 与其它 Set 的关系

新的结构不是简单并列：

```text
OCGSRuntime
  ├── PurposeSet
  ├── ProjectionSet
  ├── AbilitySet
  ├── DueSet
  └── AccessGateTree
```

而应理解为：

```text
OCGSRuntime
  → AccessGateTree
      → 每个 AccessGateNode 挂接 / 引用各类 Set
```

每个 AccessGateNode 可引用：

```text
ProjectionRef
PurposeRef
AbilityRefs
DueRefs
ContextRefs
StateRefs
ResourceRefs
EventRefs
FeedbackRef
TracePolicy
PersistencePolicy
```

各类 Set 的分工：

- ProjectionSet 回答：这道门投射成什么界面；
- PurposeSet 回答：这道门是为了什么目的；
- AbilitySet 回答：这道门通过后可调用什么能力；
- DueSet 回答：这道门凭什么能过；
- ContextSet 回答：当前处于什么对象、用户、项目、文档；
- StateSet 回答：当前处于什么状态；
- EventSet 回答：什么事件会打开、关闭、刷新这道门；
- ResourceSet 回答：图标、文案、快捷键、主题等资源；
- FeedbackSet 回答：为什么不能进，下一步去哪；
- TraceSet 回答：谁进入、谁被挡、谁放行、谁触发能力。

---

## 7. 不是功能树，也不是契约树

### 7.1 不是传统功能树

传统功能树容易把功能、菜单、页面、按钮、接口、权限、流程、日志、契约混在一起。

OCGS-se 中，传统“功能树”应上提为：

```text
PurposeTree
```

PurposeTree 只是 AccessGateTree 中某些门节点背后的目的结构，不是全部。

### 7.2 不是契约树

契约只是 DueSet 中的 ContractSet。DueSet 还包括：

```text
OutputSet
GateSet
EvidenceSet
SealSet
AccountabilitySet
BoundarySet
RiskSet
AcceptanceSet
```

所以契约树不能代表整体软件结构。

### 7.3 正确表达

整个软件应理解为：

```text
OCGSRuntime 管理 AccessGateTree；
AccessGateTree 连接 ProjectionSet、PurposeSet、AbilitySet、DueSet、ContextSet、StateSet 等各类 Set。
```

---

## 8. Delphi 中各类对象的归属

### 8.1 多功能

归入：

```text
PurposeSet / PurposeTree
```

例如：

```text
file.save
file.export
project.build
output.quality_check
artifact.seal
ai.code.apply
```

### 8.2 多窗体

归入：

```text
ProjectionSet / AccessGateTree
```

窗体是投射表面，也是 WindowGate。

### 8.3 Frame / Panel / 界面区域

归入：

```text
ProjectionSet / AccessGateTree
```

Frame 可是 FrameGate，Panel 可是 PanelGate / RegionGate。

### 8.4 面板组件集合

归入：

```text
ProjectionPanel / PanelGate
```

它是某个 PurposeGroup 或 StateGroup 的投射组合。

### 8.5 原生可见组件

例如：

```text
TButton
TMenuItem
TToolButton
TTreeView
TListView
TPageControl
TStatusBar
```

归入：

```text
ProjectionNode / ControlGate / RegionGate
```

### 8.6 原生不可见组件

不可一概而论，应按职责归属。

| 组件 | 归属 |
|---|---|
| TActionList | ProjectionBinding / CommandGate 容器 |
| TTimer | EventSet / Trigger |
| TImageList | ResourceSet / ProjectionResource |
| TDataSource | ContextSet / DataBinding |
| THTTPClient | AbilityProvider |
| TApplicationEvents | EventSet |
| 数据库连接 | AbilityProvider / InfrastructureResource |

### 8.7 API 能力

归入：

```text
AbilitySet / AbilityGraph
```

例如：

```text
file.write
db.query
http.request
ai.generate
evidence.write
seal.create
```

API 不应裸露给 AI 或 UI，应通过 AccessGateTree → PurposeSet → AbilitySet 进入。

---

## 9. AccessGateNode 建议字段

一个门禁节点至少应包含：

```text
GateKey
GateName
GateType
ParentGateKey
ChildGateKeys

ProjectionRef
PurposeRef
AbilityRefs
DueRefs
ContextRefs
StateRefs
ResourceRefs
EventRefs

AccessState
AccessMode
RiskLevel
BlockedReason
BlockedSource
RequiredConditions
NextGates
FeedbackMessage
TracePolicy
PersistencePolicy
```

### 9.1 GateType

可包括：

```text
AppGate
WorkspaceGate
ProjectGate
WindowGate
FrameGate
RegionGate
PanelGate
TabGate
MenuGate
ActionGate
ControlGate
DialogGate
CommandGate
AIGate
DueGate
AbilityGate
```

### 9.2 AccessState

可包括：

```text
Open
Closed
Hidden
Disabled
Locked
Blocked
Waiting
Running
Passed
Failed
Frozen
Conflict
```

---

## 10. 例子：artifact.seal

### 10.1 门禁树路径

```text
AppGate
  → MainWindowGate
    → OutputReviewRegionGate
      → ArtifactPanelGate
        → SealControlGate
          → SealDueGate
            → SealAbilityGate
```

### 10.2 挂接关系

```text
SealControlGate
  projection_ref: btnSeal / miSeal / cmdSeal
  purpose_ref: artifact.seal
  context_ref: current_artifact
  state_ref: output.acceptance_passed
  due_ref: acceptance_gate, evidence_required, accountability_required
  ability_ref: artifact.hash, evidence.write, seal.create
  feedback_ref: seal_disabled_feedback
```

### 10.3 解释

- SealControlGate 是可见门；
- SealDueGate 是不可见治理门；
- SealAbilityGate 是能力执行门；
- artifact.seal 是目的；
- artifact.hash / evidence.write / seal.create 是能力；
- acceptance_gate / evidence_required / accountability_required 是治理条件。

---

## 11. Delphi 重构的最新方向

在这个新口径下，Delphi 重构不再是：

```text
先整理功能树
```

也不是：

```text
先整理界面树
```

而是：

```text
先建立 AccessGateTree / 门禁树。
```

重构目标变成：

```text
把 Form、Frame、Panel、TAction、Button、MenuItem、Dialog、CommandPalette 等界面入口重建为 AccessGateNode；
每个 AccessGateNode 再引用 Purpose、Ability、Due、Context、State、Feedback、Trace。
```

这样，Delphi 软件就从：

```text
窗体事件驱动
```

转为：

```text
门禁树驱动的能力治理软件。
```

---

## 12. 当前冻结句

> 在 OCGS-se 的软件结构中，OCGSRuntime 之下应首先挂 AccessGateTree（门禁树）。门禁树中的“门”是界面、窗口、区域、面板、控件、命令、AI入口等可进入界面路径；“禁”是权限、上下文、状态、风险、契约、门禁、证据、封存、责任、能力可用性等不可见治理条件。AccessGateTree 不是单纯功能树，也不是单纯契约树，而是软件能力世界的进入秩序树；ProjectionSet、PurposeSet、AbilitySet、DueSet、ContextSet、StateSet、EventSet、ResourceSet、FeedbackSet、TraceSet 等都作为门节点背后的引用系统和支撑属集挂接其上。

---

## 13. 下一步问题

接下来应讨论：

> 如果要重构 Delphi 软件，应如何按 OCGSRuntime → AccessGateTree → 各类 Set 的结构推进？

重点包括：

1. 如何盘点现有 Form / Frame / Panel / Button / TAction；
2. 如何把它们转换为 AccessGateNode；
3. 如何建立 GateKey；
4. 如何绑定 PurposeRef；
5. 如何逐步注册 AbilitySet；
6. 如何给高风险 Gate 接入 DueSet；
7. 如何不推倒重来；
8. 如何选择第一个试点模块。
