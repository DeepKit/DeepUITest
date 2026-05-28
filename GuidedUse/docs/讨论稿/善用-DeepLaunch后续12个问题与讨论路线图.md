# 善用 × DeepLaunch：后续 12 个关键问题与讨论路线图

> 文档性质：后续讨论路线图  
> 适用范围：善用 / DeepLaunch 演示案例 / OCGS-d 后续推进  
> 版本：v1.0  
> 主持意见：以“先补齐运行体验，再进入能力生成”为主，不急于写代码  
> 前置文件：`OCGS-善用-DeepLaunch宝物倒推门禁讨论全稿-v1.1.md`

---

## 0. 当前阶段位置

前一阶段已经完成了 DeepLaunch 演示案例的宝物倒推门禁链。

当前宝物为：

```text
让一个程序和 DeepLaunch 的某个格子 / 单键建立关联，
并能通过双击格子、键入单键或右键菜单快速启动。
```

当前主链为：

```text
宝物 Output：
  程序已经绑定到 DeepLaunch 的某个格子 / 单键，并可快速启动

← 负一号门：
  LaunchVerifyGate / 启动验证门

← 负二号门：
  GridReadyGate / 格子就绪门

← 负三号门：
  SaveSuccessGate / 保存成功门

← 负四号门：
  SaveCommandGate / 保存提交门

← 负五号门：
  EditFormGate / 编辑窗体门

← 负六号门：
  ContextMenuGate / 右键菜单门

← 负七号门：
  EmptyGridCellTargetGate / 目标空格子定位门

← 负八号门：
  GridAreaGate / 格子区域门

← 负九号门：
  MainWindowGate / DeepLaunch 主界面门

← 负十号门：
  DeepLaunchAppGate / DeepLaunch 启动门
```

并且已经补充：

```text
多个空格子都可用时：
  使用 CandidateTargetGroup / 候选目标组；
  用户在善用线框图里点选一个候选空格子；
  被选中的格子成为 SelectedTarget；
  后续 ContextMenuGate 依附于 SelectedTarget。
```

---

## 1. 后续讨论的总原则

接下来不要急着进入代码实现。

当前真正要做的是：

```text
1. 把每一道门转成用户能理解的善用引导；
2. 把每个容易迷路的点设计成 LostRecovery；
3. 把主路径、分支路径、异常路径整理成 RouteRule；
4. 把视觉表达转成 FocusSketch 规则；
5. 再进入 OCGS-d 第 2 步“生成能力”。
```

我的主持意见：

> **先补体验闭环，再生成能力清单。**

也就是说：

```text
门禁链已经有了；
但用户还不知道每一步看到什么、点哪里、走偏了怎么办。
这些不定，直接写代码会返工。
```

---

# 第一部分：必须优先讨论的 6 个体验闭环问题

---

## 问题 1：SelectedTarget 如何进入 ContextMenuGate

### 1.1 问题说明

当前已经确定：

```text
多个空格子
  → CandidateTargetGroup / 候选目标组
  → 用户在线框图中点选一个空格子
  → 生成 SelectedTarget
```

接下来必须讨论：

```text
用户已经在线框图中选中一个格子后，
善用如何引导用户在真实 DeepLaunch 界面中对这个格子右键，
从而进入 ContextMenuGate？
```

### 1.2 候选方案

```text
A. 纯文字提示
   善用只提示：请对真实界面中对应位置的格子右键。

B. 线框图选中 + 文字提示 + 保持位置提示
   在线框图里保持粉红实线框；
   提示用户在真实界面中对同样位置的格子右键。

C. 真实窗口叠加提示
   把线框图选中的格子映射到真实 DeepLaunch 窗口；
   在真实窗口上显示粉红框或箭头。
```

### 1.3 主持意见

第一版选 **B**。

原因：

```text
1. A 太弱，用户容易找不到真实位置；
2. C 体验最好，但需要窗口坐标映射，复杂度高；
3. B 能保持上下文，又不增加第一版实现难度。
```

### 1.4 应产出材料

```text
1. SelectedTarget → ContextMenuGate 的提示语；
2. 线框图状态变化规则；
3. 用户右键失败时的 LostRecovery；
4. 是否保留“重新选择格子”的返回路径。
```

---

## 问题 2：右键菜单出现后，如何引导点击“编辑”

### 2.1 问题说明

当前链条中：

```text
ContextMenuGate / 右键菜单门
  └─ ClickEdit / 点击编辑
      → EditFormGate / 编辑窗体门
```

其中 `ClickEdit` 不作为主链独立门，而是右键菜单场域内的子动作 / 子路由。

### 2.2 需要讨论的点

```text
1. 右键菜单是否作为临时场域显示 FocusSketch？
2. “编辑”菜单项是否用粉红色框？
3. 右键菜单位置不固定时，线框图如何表达？
4. 如果用户没看到“编辑”，如何恢复？
5. 如果用户右键到了已有格子，菜单内容不同，如何提示？
```

### 2.3 主持意见

采用：

```text
ContextMenuGate:
  用临时菜单线框图表达；
  菜单整体用浅蓝框；
  “编辑”菜单项用粉红实线框；
  菜单位置不固定时，不画死绝对位置，只画“菜单浮层 + 编辑项”的相对结构。
```

### 2.4 应产出材料

```text
1. ContextMenuGate 的 FocusSketch；
2. ClickEdit 子路由定义；
3. “菜单中没有编辑”LostRecovery；
4. “右键菜单没有出现”LostRecovery。
```

---

## 问题 3：编辑窗体内部怎么做善用引导

### 3.1 问题说明

`EditFormGate` 是一个完整场域门。

它内部包含：

```text
程序路径；
参数；
名称；
图标自动获取；
保存按钮；
其它高级设置。
```

这些内容不能连续拆成主链负号门，但必须在编辑窗体场域内部设计清楚。

### 3.2 需要讨论的点

```text
1. 程序路径是否是第一主焦点？
2. 参数如何解释“可选”？
3. 名称如何解释“可选”？
4. 图标自动获取如何提示？
5. 高级设置是否灰化？
6. 保存按钮什么时候成为粉红主焦点？
```

### 3.3 主持意见

编辑窗体内部按“两段式”引导：

```text
第一段：
  主焦点是程序路径 / 浏览按钮。

第二段：
  路径填写后，主焦点转到保存按钮。
```

参数和名称不做主流程必填项，只作为辅助说明：

```text
参数：
  可选，不懂可以先不填。

名称：
  可选，不填时可自动生成或根据程序名显示。

图标：
  通常自动获取，不需要用户手动设置。
```

### 3.4 应产出材料

```text
1. EditFormGate 内部字段优先级；
2. 编辑窗体 FocusSketch；
3. 参数解释文本；
4. 图标自动获取解释文本；
5. 高级设置灰化规则。
```

---

## 问题 4：保存前的条件和阻挡怎么表达

### 4.1 问题说明

`SaveCommandGate` 发生在 `EditFormGate` 内部。

虽然它是动作门，不是界面门，但保存前仍然需要条件判断。

### 4.2 需要讨论的条件

```text
1. 程序路径为空；
2. 程序路径不是 exe；
3. 程序路径不存在；
4. 参数格式不可接受；
5. 目标格子已失效；
6. 保存按钮灰色；
7. 保存报错。
```

### 4.3 主持意见

保存前条件要形成：

```text
Condition
DisabledReason
NextAction
```

例如：

```text
Condition:
  ProgramPathExists = true

DisabledReason:
  还没有选择要启动的程序。

NextAction:
  请点击“浏览”，选择一个 .exe 文件。
```

### 4.4 应产出材料

```text
1. SaveCommandGate 的 Condition 表；
2. DisabledReason 列表；
3. NextAction 列表；
4. 保存失败 LostRecovery。
```

---

## 问题 5：保存成功后，格子就绪状态怎么判断和提示

### 5.1 问题说明

当前倒推链中：

```text
SaveSuccessGate
  → GridReadyGate
```

这里是用户体验关键。

用户必须知道：

```text
保存真的成功了吗？
哪个格子发生变化了？
我现在可以验证启动了吗？
```

### 5.2 需要讨论的点

```text
1. 保存成功后编辑窗体是否关闭？
2. 是否自动回到格子区域？
3. 格子显示什么才算就绪？
4. 图标没获取成功但名称出现，算不算就绪？
5. 名称没出现但图标出现，算不算就绪？
6. 保存成功提示是否需要独立显示？
```

### 5.3 主持意见

`GridReadyGate` 不应只依赖图标。

建议定义为：

```text
格子出现以下任一可识别绑定状态，即可视为就绪：
  A. 有程序图标；
  B. 有程序名称；
  C. 有用户设置的名称；
  D. 有系统显示的绑定标志。
```

但善用对用户应提示：

```text
你应该看到刚才那个格子已经出现名称或图标。
只要能确认它不再是空白格子，就可以进入启动验证。
```

### 5.4 应产出材料

```text
1. GridReadyGate 就绪判定；
2. 保存成功后的提示语；
3. 格子未变化 LostRecovery；
4. 图标获取失败但路径有效的处理方式。
```

---

## 问题 6：启动验证门怎么设计

### 6.1 问题说明

`LaunchVerifyGate` 是宝物前最后一道门。

它决定用户是否真正拿到宝物。

### 6.2 需要讨论的点

```text
1. 第一版主验证方式是什么？
2. 双击格子、键入单键、右键菜单启动，哪个为主？
3. 启动成功如何确认？
4. 启动失败如何恢复？
5. 如果程序已经在后台打开，算不算成功？
```

### 6.3 主持意见

第一版主验证方式：

```text
双击格子启动。
```

补充说明：

```text
如果你已经设置了单键，也可以键入单键启动。
右键菜单启动作为补充，不进入第一主验证。
```

启动成功判定：

```text
用户看到目标程序窗口打开。
```

启动失败恢复：

```text
1. 检查程序路径；
2. 清空参数后再试；
3. 程序文件是否被移动或删除；
4. 回到编辑窗体修正。
```

### 6.4 应产出材料

```text
1. LaunchVerifyGate 提示语；
2. 启动成功 ExpectedResult；
3. 启动失败 LostRecovery；
4. 双击 / 单键 / 右键菜单三种验证方式的层级。
```

---

# 第二部分：分支、风险与外壳链

---

## 问题 7：拖拽 exe 快速绑定路线怎么设计

### 7.1 问题说明

拖拽路线是补充 Route，不是主路径。

当前定义：

```text
从外部拖动一个可执行文件
  → 放到 DeepLaunch 的某个格子
  → 系统自动绑定路径、名称、图标
  → GridReadyGate
  → LaunchVerifyGate
```

### 7.2 需要讨论的点

```text
1. 从哪里拖 exe？
2. 拖到哪个格子？
3. 是否复用 CandidateTargetGroup？
4. 拖到已有格子是否触发覆盖确认？
5. 自动绑定失败怎么办？
6. 是否需要单独做 DropExeGate？
```

### 7.3 主持意见

拖拽路线复用：

```text
GridAreaGate
  → EmptyGridCellTargetGate
  → DropExeGate
  → AutoBindGate
  → GridReadyGate
```

拖拽到已有格子时，不直接覆盖，应进入：

```text
OverwriteConfirmGate
```

### 7.4 应产出材料

```text
1. 拖拽路线 RouteRule；
2. DropExeGate 定义；
3. AutoBindGate 定义；
4. 拖拽失败 LostRecovery；
5. 覆盖已有格子的风险分支。
```

---

## 问题 8：覆盖已有格子的风险分支

### 8.1 问题说明

主路径默认选择空格子。

但用户可能没有空格子，或主动想覆盖已有格子。

### 8.2 风险判断

覆盖已有格子会改变已有启动配置。

因此风险高于普通空格子绑定。

建议：

```text
RiskLevel:
  L2
```

原因：

```text
会覆盖已有配置，可能造成原来的快速启动入口丢失。
```

### 8.3 主持意见

如果用户选择已有格子，应进入：

```text
ExistingGridCellTargetGate
  → OverwriteConfirmGate
  → EditFormGate
```

必须提示：

```text
这个格子已经有内容。
继续编辑可能会替换原来的启动配置。
你确定要使用这个格子吗？
```

### 8.4 应产出材料

```text
1. ExistingGridCellTargetGate 定义；
2. OverwriteConfirmGate 定义；
3. 覆盖确认提示；
4. 取消覆盖后的返回路径；
5. 是否需要备份原配置。
```

---

## 问题 9：善用外壳链是否纳入第一版演示

### 9.1 问题说明

当前主链是 DeepLaunch 内部业务链。

如果要演示善用完整价值，还需要善用外壳链：

```text
ShanYongAppGate
  → GuidePackageSelectGate
    → TaskSelectGate
      → TargetWindowBindGate
        → DeepLaunchAppGate
```

### 9.2 需要讨论的点

```text
1. 第一版演示是否从善用启动开始？
2. 是否需要让用户选择 DeepLaunch 善用包？
3. 是否需要选择“绑定第一个程序”任务？
4. 是否需要绑定 DeepLaunch 窗口？
5. 善用如何提示用户打开 DeepLaunch？
```

### 9.3 主持意见

区分两种演示：

```text
完整产品演示：
  从善用外壳链开始。

短视频 / 说明文演示：
  可以直接假设 DeepLaunch 已打开，从 GridAreaGate 开始。
```

第一版产品内部仍应支持善用外壳链，只是对外演示可裁剪。

### 9.4 应产出材料

```text
1. 善用外壳链 AccessGateTree；
2. 善用包选择界面提示语；
3. 任务选择界面提示语；
4. 目标窗口绑定规则；
5. DeepLaunch 未打开时的提示。
```

---

# 第三部分：视觉、迷路恢复与 OCGS-d 后续

---

## 问题 10：每一道门的 FocusSketch 具体画法

### 10.1 问题说明

当前已有颜色规则：

```text
粉红实线：
  当前唯一主操作目标

粉红虚线：
  候选目标，可任选其一

浅蓝框：
  当前场域范围

浅黄色：
  注意 / 风险 / 不要乱点

灰色：
  背景弱化 / 暂时不用管

浅绿色：
  成功状态
```

但还没有逐门定义具体画法。

### 10.2 需要覆盖的重点门

```text
DeepLaunchAppGate
MainWindowGate
GridAreaGate
EmptyGridCellTargetGate
ContextMenuGate
EditFormGate
SaveCommandGate
GridReadyGate
LaunchVerifyGate
```

### 10.3 主持意见

每道门都按统一模板产出：

```text
1. 场域框：浅蓝
2. 主焦点：粉红实线
3. 候选目标：粉红虚线
4. 成功状态：浅绿色
5. 风险区：浅黄色
6. 无关背景：灰色
7. 独立说明文本框
```

### 10.4 应产出材料

```text
1. 每道门的 FocusSketch 结构表；
2. 每道门的主焦点 Anchor；
3. 每道门的辅助 Anchor；
4. 是否需要独立悬浮文本框；
5. 运行时视觉状态变化。
```

---

## 问题 11：LostRecovery 迷路恢复总表

### 11.1 问题说明

善用区别于普通教程，关键在迷路恢复。

要把用户常见卡点全部整理成恢复路径。

### 11.2 必须覆盖的迷路项

```text
1. 我没看到 DeepLaunch 主界面；
2. 我没看到格子区域；
3. 我找不到空格子；
4. 我不知道选哪个格子；
5. 我右键菜单没出来；
6. 我菜单里没有“编辑”；
7. 我找不到程序路径；
8. 我不知道参数填什么；
9. 保存按钮不能点；
10. 保存后格子没变化；
11. 双击后程序没启动；
12. 我选错格子了。
```

### 11.3 主持意见

每个 LostRecovery 都应包含：

```text
1. 用户问题；
2. 可能原因；
3. 给用户的选择题；
4. 推荐下一步；
5. 回到哪一道门；
6. 是否进入风险分支。
```

示例：

```text
用户问题：
  我找不到空格子。

可能原因：
  当前格子页已满；
  用户没有识别空格子；
  所有格子都有内容。

选择题：
  A. 切换到下一页格子；
  B. 使用已有格子并确认覆盖；
  C. 退出任务，先整理格子。

路由：
  A → GridAreaGate
  B → OverwriteConfirmGate
  C → TaskExitGate
```

### 11.4 应产出材料

```text
1. LostRecovery 总表；
2. 每个恢复项的 RouteRule；
3. 每个恢复项的提示语；
4. 哪些恢复会进入风险分支；
5. 哪些恢复会返回上一道门。
```

---

## 问题 12：进入 OCGS-d 第 2 步：生成能力清单

### 12.1 问题说明

当门禁、提示语、FocusSketch、LostRecovery 都基本冻结后，才进入 OCGS-d 第 2 步：

```text
生成能力
```

### 12.2 善用第一版需要的能力

```text
1. GuidePackage 加载能力；
2. Step 播放能力；
3. FocusSketch 渲染能力；
4. CandidateTargetGroup 展示能力；
5. SelectedTarget 记录能力；
6. RouteRule 执行能力；
7. LostRecovery 显示能力；
8. 用户选择记录能力；
9. 卡点反馈能力；
10. 善用外壳链选择任务能力；
11. DeepLaunch 窗口绑定能力；
12. 本地缓存 / 云端同步预留能力。
```

### 12.3 主持意见

不要一上来生成完整 OCGS-d 工程级能力。

先生成善用第一版轻量能力清单：

```text
GuidePackage
TaskJourney
GuideStep
FieldScene
SceneVisual
VisualAnchor
CandidateTargetGroup
SelectedTarget
RouteRule
Feedback
LostRecovery
TraceEvent
```

### 12.4 应产出材料

```text
1. Action 清单；
2. Ability 清单；
3. RouteRule 草案；
4. Feedback 定义；
5. Projection / FocusSketch 绑定；
6. Trace / Evidence 最小记录；
7. 能力检查规则。
```

---

# 4. 推荐讨论顺序

我建议后续讨论按以下顺序进行：

```text
1. SelectedTarget 如何进入 ContextMenuGate
2. 右键菜单如何引导点击“编辑”
3. 编辑窗体内部引导
4. 保存条件与阻挡反馈
5. 格子就绪与启动验证
6. LostRecovery 迷路恢复总表
7. 拖拽 exe 快速绑定路线
8. 覆盖已有格子的风险分支
9. 每道门 FocusSketch 画法
10. 善用外壳链
11. OCGS-d Step 2 能力清单
12. 测试样例与封版
```

---

## 5. 下一轮建议讨论的问题

下一轮建议先讨论：

# **SelectedTarget 如何进入 ContextMenuGate**

原因：

```text
这是当前链条中第一个还没补齐的运行体验断点。

用户在线框图中选中了一个空格子，
但善用还没有明确说明如何把这个选中对象迁移到真实 DeepLaunch 界面中的右键操作。
```

下一轮的主持问题应为：

```text
用户已经在善用线框图里选中一个空格子。
接下来善用如何引导用户在真实 DeepLaunch 界面中对这个格子右键？

A. 只用文字提示；
B. 线框图保持选中 + 文字提示；
C. 真实窗口上叠加粉红框；
D. 其它方案。
```

主持建议：

```text
第一版选择 B；
第二阶段升级 C。
```

---

## 6. 本文冻结句

> 后续讨论应先补齐善用运行体验闭环，尤其是 SelectedTarget、ContextMenuGate、EditFormGate、SaveCommandGate、GridReadyGate、LaunchVerifyGate、LostRecovery 与 FocusSketch。只有这些体验材料基本冻结后，才进入 OCGS-d 第 2 步“生成能力”。本路线图建议以 SelectedTarget 如何进入 ContextMenuGate 作为下一轮讨论入口。
