# OCGS-se：面向门的 Output-Driven 开发流程

> 版本：v1.0  
> 主题：从产出物倒推门禁路径的软件开发流程  
> 关键词：OCGSRuntime、AccessGateTree、OutputSet、PurposeSet、ProjectionSet、AbilitySet、DueSet、AI 生成 Delphi 软件、人类微调  
> 核心句：先定 Output，再倒推门；用表约束 AI，用 Key 保证二次修改。

---

## 一、为什么需要“面向门”的开发流程

传统 Delphi / 桌面软件开发常从界面和控件开始：

```text
打开 IDE
  → 新建 Form
  → 拖 Button / Panel / PageControl / TabSheet
  → 写 OnClick / OnDragDrop / OnChange
  → 调 Handler
  → 完成功能
```

这种方式在小工具中很快，但在复杂软件、AI 生成软件、可二次修改软件中容易出现问题：

- 控件和功能混在一起；
- 窗体事件越来越胖；
- 控件名被误当成功能名；
- 功能背后的产出物不清楚；
- 拖拽、点击、菜单、快捷键等入口分散；
- AI 直接改 DFM / PAS，二次修改困难；
- 高风险操作缺少门禁、证据、封存和责任；
- 软件可以“跑”，但结构不可解释、不可追踪、不可治理。

OCGS-se 的“面向门开发”希望改变这个入口。

它不从按钮、控件、代码开始，而从用户真正想得到的产出物开始。

---

## 二、核心定义

### 1. OutputSet：产出物集

所谓“宝物”，不新增 TreasureSet，而归入已有的 OutputSet。

OutputSet 定义：

```text
用户最终要得到什么；
这个结果是什么类型；
它怎样才算完成；
它的风险等级是多少；
是否需要证据；
是否需要封存；
是否需要责任锚点。
```

例如：

```text
OutputKey: artifact.sealed_version
OutputType: sealed_artifact
FinalState: sealed
RiskLevel: L3
EvidenceRequired: true
SealRequired: true
```

---

### 2. AccessGateTree：门禁树

AccessGateTree 是 OCGSRuntime 下的软件进入路径总树。

它以“门”为界面、窗口、区域、面板、控件、命令、AI 入口等可进入路径，以“禁”为权限、上下文、状态、风险、契约、门禁、证据、封存、责任、能力可用性等不可见治理条件。

一句话：

```text
门禁树 = 软件能力世界的进入秩序树。
```

---

### 3. 门与禁

“门”包括：

- AppGate：应用入口；
- WindowGate：窗口入口；
- RegionGate：区域入口；
- PanelGate：面板入口；
- TabGate：页签入口；
- ControlGate：控件入口；
- DialogGate：弹窗确认入口；
- CommandGate：命令入口；
- AIGate：AI 可读入口；
- DragGate：拖拽入口；
- DropGate：投放入口。

“禁”包括：

- ContextGate：上下文门；
- StateGate：状态门；
- PermissionGate：权限门；
- RiskGate：风险门；
- ContractGate：契约门；
- AcceptanceGate：验收门；
- EvidenceGate：证据门；
- SealGate：封存门；
- AccountabilityGate：责任门；
- AbilityGate：能力可用门。

---

## 三、面向门开发的总流程

### 第一步：定义 OutputSet

先问：

```text
用户最终要得到什么产出物？
```

Output 表：

```text
OutputKey:
OutputName:
OutputType:
InitialState:
FinalState:
RiskLevel:
EvidenceRequired:
SealRequired:
AcceptanceCriteria:
```

---

### 第二步：定义 Output 状态机

不要把“生成了”误认为“完成了”。

每个 Output 都应有状态迁移：

```text
draft
  → generated
  → quality_checking
  → quality_passed
  → acceptance_passed
  → sealed
```

每个状态变化都应由某道 Gate 触发。

---

### 第三步：倒推 AccessGateTree

从目标 Output 的 FinalState 倒推：

```text
为了得到这个 Output，需要经过哪些门？
```

例如：

```text
AppGate
  → MainWindowGate
    → OutputReviewRegionGate
      → ArtifactPanelGate
        → SealControlGate
          → SealDueGate
            → SealAbilityGate
              → OutputState: sealed
```

---

### 第四步：给操作门挂 PurposeSet

每道操作门都要说明它“为何而设”。

```text
GateKey: main.output_review.artifact.seal
PurposeRef: artifact.seal
OutputRef: artifact.sealed_version
```

规则：

```text
凡是 ControlGate / CommandGate / DragGate / DropGate / AIGate，必须有 PurposeRef。
```

---

### 第五步：给门挂 Projection 参数表

UI 参数不应散落在 DFM 中，而应挂在 Gate 上。

```text
GateKey: main.output_review.artifact.seal
Projection:
  ComponentClass: TButton
  Name: btnSealArtifact
  Caption: 封存
  Parent: OutputReviewFrame
  Left: 150
  Top: 20
  Width: 90
  Height: 32
  Align: none
  Anchors: [akTop, akLeft]
```

人类通过参数接口或自然语言调整，AI 回写参数表，而不是直接乱改 DFM。

---

### 第六步：挂 AbilitySet

能力必须稳定命名，不能使用控件名。

错误：

```text
btnSealClick
Button3Action
DoSeal2
```

正确：

```text
artifact.hash
evidence.write
artifact.seal.create
output.state.update
```

规则：

```text
凡是可执行 Purpose，必须至少有一个 AbilityRef。
```

---

### 第七步：高风险 Output 挂 DueSet

L2 / L3 风险的 Output 必须挂 DueSet。

```text
DueRefs:
  - BoundarySet.no_unaccepted_output_seal
  - GateSet.acceptance_passed
  - EvidenceSet.quality_check_record_required
  - AccountabilitySet.current_user_required
  - SealSet.artifact_manifest_required
```

规则：

```text
RiskLevel = L3 时，必须有 GateSet / EvidenceSet / AccountabilitySet。
SealRequired = true 时，必须有 SealSet。
EvidenceRequired = true 时，必须有 EvidenceSet。
```

---

### 第八步：定义 FeedbackSet

每道门被挡住时，必须告诉人或 AI：

```text
为什么不能进；
缺什么条件；
下一道应去哪里。
```

示例：

```text
BlockedReason:
  Source: DueSet.GateSet
  Message: 当前不能封存，因为验收门禁未通过。
  NextGate: main.output_review.quality_check.run
  AIMessage: Do not run artifact.seal before output.quality_check passes.
```

---

### 第九步：定义 Trace / Evidence

关键门要记录：

```text
谁试图进入；
从哪里进入；
是否被挡；
为什么被挡；
是否调用 Ability；
是否改变 OutputState；
是否写 Evidence；
是否 Seal。
```

---

### 第十步：生成前做完整性校验

AI 每次生成 Delphi 代码前，必须先跑结构校验：

```text
1. 每个 Output 是否有 OutputKey / FinalState / RiskLevel；
2. 每个 Output 是否至少有一条 AccessGatePath；
3. 每个 ControlGate / DropGate 是否有 PurposeRef；
4. 每个 Purpose 是否有 AbilityRefs；
5. 每个 ProjectionRef 是否有合法 Parent；
6. 每个 GateKey 是否唯一；
7. 每个 AbilityRef 是否已注册；
8. L2 / L3 是否有 DueRefs；
9. EvidenceRequired 是否有 EvidenceSet；
10. SealRequired 是否有 SealSet；
11. Blocked Gate 是否有 Feedback；
12. 每个状态迁移是否有触发 Gate；
13. 生成文件与手写文件是否分离。
```

---

## 四、AI 友好的固定表格

### 1. Output 表

```text
OutputKey:
OutputName:
OutputType:
InitialState:
FinalState:
RiskLevel:
EvidenceRequired:
SealRequired:
AcceptanceCriteria:
```

### 2. Output 状态表

```text
FromState:
GateKey:
ToState:
GateResult:
FailureState:
```

### 3. AccessGate 表

```text
GateKey:
GateName:
GateType:
ParentGateKey:
OutputRef:
PurposeRef:
ProjectionRef:
AbilityRefs:
DueRefs:
AccessState:
BlockedReason:
NextGates:
```

### 4. Projection 参数表

```text
ProjectionKey:
GateKey:
ComponentClass:
ParentProjection:
Caption:
Hint:
Left:
Top:
Width:
Height:
Align:
Anchors:
Visible:
EnabledBinding:
```

### 5. Ability 表

```text
AbilityKey:
AbilityName:
Provider:
Handler:
InputSchema:
OutputSchema:
ErrorStrategy:
DryRunSupported:
```

### 6. Due 表

```text
DueKey:
DueType:
AppliesToOutput:
AppliesToGate:
Condition:
PassState:
FailState:
EvidenceRequired:
HumanRequired:
```

### 7. Feedback 表

```text
GateKey:
BlockedSource:
UserMessage:
AIMessage:
NextGate:
Severity:
```

---

## 五、面向门开发中的拖拽操作预留

拖拽不应被理解为简单的 `OnDragDrop` 事件。

在 OCGS-se 中，拖拽应进入 AccessGateTree：

```text
DragSourceGate
  → DragPayloadGate
    → DropTargetGate
      → RouteGate
        → PurposeGate
          → AbilityGate
            → OutputStateChange
```

外部文件拖入软件时，至少要识别：

```text
拖来的是什么；
从哪里拖来；
拖到哪个可投放区域；
当前区域是否接收；
根据什么规则分流；
投放后产生什么 Output 或状态变化；
失败时如何反馈。
```

这为下一轮讨论“拖文件到 PageControl，根据后缀放入不同 TabSheet”提供基础。

---

## 六、当前冻结句

> 面向门的开发流程不需要新增 TreasureSet，目标“宝物”应归入已有 OutputSet。开发从 OutputSet 出发，先定义目标产出物、合格状态、风险等级和证据/封存要求，再倒推出取得该 Output 必须经过的 AccessGateTree。每道门再挂 PurposeRef、ProjectionRef、AbilityRefs、DueRefs、ContextRefs、StateRefs、Feedback 与 Trace。AI 不直接从按钮或代码开始，而是按 Output 表、Gate 表、Projection 参数表、Ability 表、Due 表和 Feedback 表逐项生成与校验，从而减少混层、漏门、漏能力、漏门禁和二次修改困难。

一句话：

> 先定 Output，再倒推门；用表约束 AI，用 Key 保证二次修改。
