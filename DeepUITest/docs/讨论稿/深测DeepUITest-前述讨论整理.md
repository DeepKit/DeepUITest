# 深测 DeepUITest 前述讨论整理

> 用途：用于新会话继续讨论或作为产品文档雏形。  
> 范围：本文件整理“深测 DeepUITest”从概念提出到 MVP 样板案例的主要讨论结果。  
> 状态：讨论整理稿，尚非最终 PRD。  

---

## 0. 当前产品矩阵位置

当前这一组讨论属于“个人 / 桌面 / 软件能力治理产品矩阵”，不与小说、营销、ShineOps 等其他项目混在一起。

| 层级 | 产品 / 系统 | 当前定位 | 主要作用 |
|---|---|---|---|
| 1 | OCGS | 能力有序治理系统 / 方法论底座 | 定义宝物、门、场域、能力、动作、状态、断言、路由、风险、留痕等底层思想 |
| 2 | OCGS-d | AI 主持式宝物倒推开发流程 | 用 AI 提问、用户选择、HumanDecisionLog、宝物倒推门禁链来做需求与产品设计 |
| 3 | 深启 DeepLaunch | Windows 遥控器 | F1 调出 60 格 Grid，F1 + X 双键启动程序；F2 做语音 / 文字语义遥控 |
| 4 | 善用 | 桌面悬浮式图卡说明书 / 软件任务陪跑系统 | 用户不会操作软件时，用图卡、聚焦框、提示语、迷路恢复来陪用户完成任务 |
| 5 | 深测 DeepUITest | Windows 桌面程序 UI 行为 Mock / 回归测试系统 | 读取文档、代码、窗体结构、录制轨迹，生成测试配置，用红绿灯、Runner、Bug 库做测试闭环 |

一句话冻结：

```text
OCGS 是底座；
OCGS-d 是设计方法；
DeepLaunch 是遥控器；
善用是陪跑说明书；
DeepUITest 是测试台。
```

---

## 1. 深测 DeepUITest 产品定位

### 1.1 产品名

```text
中文名：深测
英文名：DeepUITest
```

### 1.2 当前定位

```text
深测 DeepUITest：
面向 Windows 桌面程序，尤其是 Delphi VCL / FMX 程序的
AI 辅助 UI 行为 Mock / 回归测试系统。

它读取开发文档、源码、窗体结构、录制轨迹和跨软件 Bug 记录库，
自动生成带证据链的测试配置，
用红绿灯机制减少人工审核，
用 Runner 回放验证真实行为，
并把失败经验沉淀为跨软件 Bug 知识，
让 AI 越测越聪明。
```

### 1.3 第一阶段边界

第一阶段只管：

```text
1. Windows 桌面程序；
2. Delphi VCL 程序；
3. Delphi FMX on Windows 程序；
4. UI 行为 Mock / 回归测试；
5. 配置端和测试端共享数据库。
```

暂不管：

```text
1. Web 自动化测试；
2. 移动端测试；
3. 接口测试；
4. 性能测试；
5. 安全测试；
6. 企业级测试管理大平台。
```

---

## 2. DeepUITest 的系统形态

系统分为两端一库：

```text
1. 配置端 DeepUITest Designer
2. 测试端 DeepUITest Runner
3. 共享数据库 DeepUITest DB
```

### 2.1 配置端 Designer

负责：

```text
1. 登记被测软件；
2. 导入开发文档；
3. 导入 VCL / FMX 源码与窗体文件；
4. 读取或索引窗体、控件、事件；
5. 生成测试配置草稿；
6. 展示红 / 黄 / 绿 / 灰灯；
7. 处理人工审核；
8. 管理测试配置封版；
9. 查看失败诊断与 Bug 记录。
```

### 2.2 测试端 Runner

负责：

```text
1. 加载测试配置；
2. 启动被测程序；
3. 执行 UI 动作；
4. 采集截图、日志、状态；
5. 执行断言；
6. 写入 Runner 结果；
7. 失败时生成诊断卡；
8. 回写灯色与 Bug 信息。
```

### 2.3 共享数据库

负责保存：

```text
1. 软件项目；
2. 软件版本；
3. 源码索引；
4. 窗体和控件；
5. 测试用例；
6. JourneyStep；
7. 断言规则；
8. 红绿灯结果；
9. Runner 执行结果；
10. Bug 记录；
11. Bug 诊断；
12. HumanDecisionLog。
```

---

## 3. DeepUITest 与 OCGS 的关系

DeepUITest 不只是“录制点击脚本”。

它的核心不是：

```text
点击这里；
输入那里；
等 1 秒；
再点那里。
```

而是：

```text
用户要拿到什么宝物 Output？
为了拿到宝物，需要经过哪些门 Gate？
每道门属于什么场域 Field？
需要触发哪些动作 Action？
应该显现什么状态 State？
用什么断言 Assert 验证它？
失败时卡在哪一道门？
如何留痕和修正？
```

也就是说，DeepUITest 是把桌面程序的用户行为链变成：

```text
宝物 → 门 → 场域 → 对象 → 动作 → 状态 → 断言 → 报告 → Bug 经验
```

这正是 OCGS 的能力有序治理思想在测试领域的落地。

---

## 4. AI 读取文档和代码生成测试配置

### 4.1 是否支持

决定：支持。

AI 配置生成器是 DeepUITest 的核心优势之一。

```text
开发文档 + 源码 + 窗体结构 + 运行探测 + 人工录制轨迹 + Bug 记录库
→ AI 生成语义测试配置草稿
→ 附带证据链
→ 红绿灯分流
→ 人工审核关键不确定项
→ Runner 回放验证
→ 通过后封版
```

### 4.2 AI 可读取材料

```text
1. 开发文档
   - 功能说明
   - 用户操作流程
   - 需求文档
   - 更新日志
   - 测试说明
   - OCGS 门禁文档

2. VCL / FMX 源码
   - .pas
   - .dfm
   - .fmx
   - Form 类
   - 控件 Name / Caption / StyleName
   - ActionList
   - OnClick / OnExecute / OnTap

3. 数据库结构
   - 表
   - 字段
   - 状态字段
   - 配置表
   - 路由表

4. 运行时探测结果
   - 窗口标题
   - 控件层级
   - 控件文本
   - 可点击区域
   - UI Automation 信息

5. 人工录制轨迹
   - 用户点了哪里
   - 输入了什么
   - 哪个窗口出现
   - 哪个状态变化

6. 跨软件 Bug 记录库
   - 历史失败模式
   - 修复经验
   - 断言增强规则
```

### 4.3 AI 生成的不是最终脚本

AI 生成的是：

```text
测试配置草稿；
语义测试链；
候选断言；
证据链；
风险与灯色建议。
```

不是直接可信的最终脚本。

硬原则：

```text
AI 生成候选配置；
人确认业务意图；
Runner 验证真实性；
红绿灯负责分流。
```

---

## 5. VCL / FMX 支持策略

### 5.1 VCL 策略

VCL 更适合自动化读取。

优先读取：

```text
.dfm
.pas
TForm
TButton
TEdit
TDBEdit
TComboBox
TCheckBox
TMainMenu
TPopupMenu
TActionList
TStringGrid / TDBGrid 基础定位
OnClick
OnExecute
```

VCL 容易绿灯的原因：

```text
1. DFM 结构较清晰；
2. 控件 Name / Caption 明确；
3. ActionList 可作为能力入口；
4. 外部 UI 识别相对稳定。
```

### 5.2 FMX 策略

FMX 更依赖源码和 TestId。

优先读取：

```text
.fmx
.pas
TForm
TButton
TEdit
TListBox / TGrid 基础结构
Name
StyleName
OnClick
OnTap
LiveBindings
```

FMX 难点：

```text
1. 运行时控件未必能被 Windows UI Automation 稳定识别；
2. 控件渲染和原生句柄关系较弱；
3. DPI / 缩放 / 图像锚点影响更大；
4. 没有 TestId 时定位风险更高。
```

FMX 规则：

```text
FMX 项目如果没有稳定 TestId / Name / StyleName，
AI 可以生成配置草稿，
但默认更容易黄灯，不能轻易绿灯。
```

### 5.3 TestId 机制

建议以后 VCL / FMX 项目逐步加入：

```text
TestId
OCGSId
GateId
AbilityId
```

示例：

```text
deeplaunch.main.grid
deeplaunch.grid.cell.A
deeplaunch.cell.edit.programPath
deeplaunch.cell.edit.save
```

控件最好同时具备：

```text
Name：程序内部名称
Caption：用户看到的文字
TestId：测试稳定标识
OCGSId：门禁 / 能力治理标识
```

---

## 6. 红绿灯机制

红绿灯是 DeepUITest 减少人工审核负担的关键。

它不是装饰，而是：

```text
测试配置可信度门禁系统。
```

流程：

```text
AI 生成测试配置草稿
→ 系统自动收集证据
→ 自动判断可信度
→ 分配红 / 黄 / 绿 / 灰灯
→ 人只重点审核黄灯和红灯
→ Runner 回放后重新计算灯色
→ 绿灯才能封版
```

### 6.1 四种灯色

#### 绿灯 Green

含义：

```text
证据充分；
风险较低；
Runner 已经跑通；
可以进入正式测试库。
```

#### 黄灯 Yellow

含义：

```text
大体可信；
但有关键不确定点；
需要人工重点审核。
```

#### 红灯 Red

含义：

```text
不能执行；
不能封版；
必须修正。
```

#### 灰灯 Gray

含义：

```text
信息不足；
暂时无法判断；
不进入正式测试。
```

### 6.2 证据链

红绿灯判断基于证据链。

```text
EvidenceChain:
1. 文档证据 DocumentEvidence
2. 代码证据 CodeEvidence
3. UI 证据 UIEvidence
4. 断言证据 AssertEvidence
5. 回放证据 RunnerEvidence
6. 历史 Bug 证据 HistoryBugEvidence
```

### 6.3 风险等级与灯色分开

```text
LampState = 配置可信不可信
RiskLevel = 动作危险不危险
```

典型组合：

```text
Green + L0：可以自动回归测试
Green + L2：配置可信，但执行前需要沙箱或 Mock 数据
Yellow + L0：动作安全，但配置要人确认
Red + L3：既不可信又危险，禁止执行
```

### 6.4 沙箱优先原则

凡是涉及新增、修改、删除、提交、发送的测试，默认必须使用：

```text
Mock 数据库 / 测试库 / 临时文件夹 / 沙箱环境
```

没有沙箱：

```text
不能绿灯；
最多黄灯；
高风险时直接红灯。
```

---

## 7. 跨软件 Bug 记录库

### 7.1 新增模块

```text
BugRecordLibrary / 跨软件 Bug 记录库
```

目标：

```text
把多个桌面程序中出现过的 Bug、失败路径、控件识别问题、断言失败、配置错误、历史修复方案沉淀下来，
让 AI 在后续生成测试配置、判断红绿灯、解释失败原因、推荐修复方案时变得更聪明。
```

### 7.2 Bug 库不是缺陷登记表

Bug 库至少有三层：

```text
1. BugRecord：一次具体失败
2. BugPattern：一类失败模式
3. BugLearningRule：让 AI 后续避坑的规则
```

示例：

```text
具体 Bug：
DeepLaunch 绑定程序后，界面显示保存成功，但 F1 + X 启动的还是旧程序。

BugPattern：
配置保存成功，但运行时缓存未刷新。

BugLearningRule：
凡是配置生效类功能，不能只断言“保存成功”，必须追加“运行时行为验证”。
```

### 7.3 Bug 类型

第一版至少区分：

```text
1. ProductBug       软件功能真的有问题
2. TestConfigBug    测试配置错了
3. LocatorBug       控件定位失败
4. AssertBug        断言错误或断言太弱
5. MockDataBug      测试数据问题
6. EnvironmentBug   环境问题
7. PermissionBug    权限问题
8. TimingBug        等待时机 / 窗口加载时序问题
9. Unknown          暂时无法判断
```

### 7.4 BugRecord 多点挂载

Bug 不能只挂在 TestCase 上，还应能挂到：

```text
Output
Journey
Gate
Step
Action
Locator
Control
State
Assert
MockData
Environment
Runner
CodeRef
DocumentRef
```

建议用：

```text
BugRecord + BugObjectLink
```

而不是在 BugRecord 表里塞一堆字段。

LinkRole 包括：

```text
PrimaryFailurePoint       主失败点
AffectedObject            受影响对象
SuspectedCause            疑似原因
ConfirmedRootCause        确认根因
EvidenceSource            证据来源
SuggestedFixTarget        建议修复对象
HistoricalSimilarObject   历史相似对象
```

### 7.5 BugPattern 成熟度

BugPattern 不应从单次失败直接变成全局经验。

成熟度：

```text
Candidate   AI 候选，未确认
Confirmed   人确认过，可影响当前软件或当前功能
Promoted    多次验证，可跨软件影响
Deprecated  已废弃或不再适用
```

作用范围：

```text
CurrentAppOnly    当前软件
SameModuleOnly    当前模块
SameFunctionType  同类功能
SameTechStack     同技术栈
Global            全局通用
```

### 7.6 Bug 库如何影响红绿灯

BugPattern 命中后，不是简单变红灯。

可能结果：

```text
1. 只记录：历史经验命中，但当前配置已覆盖风险；
2. 提醒：建议增加断言或 Mock 数据；
3. 降证据分：例如 AssertEvidence / UIEvidence 降分；
4. 绿转黄：需要人工确认或补强断言；
5. 黄 / 绿转红：当前配置具备高风险条件、Runner 失败、关键断言失败、使用生产环境等；
6. 变绿：用户补充断言，Runner 通过后，黄灯可以恢复绿灯。
```

---

## 8. MVP 范围

### 8.1 MVP 必须做

```text
1. 项目登记
2. VCL / FMX 基础代码读取
3. AI 测试配置草稿生成
4. 行为链 Journey 配置
5. 基础断言 Assert
6. 红绿灯评估
7. Runner 基础回放
8. 失败诊断卡
9. BugRecord 入库
10. HumanDecisionLog
11. 共享数据库
12. DeepLaunch 样板测试案例
```

### 8.2 MVP 暂缓做

```text
1. 大规模批量回归
2. 完整知识图谱
3. 自动修复代码
4. 自动提升全局 BugPattern
5. 复杂拖拽
6. 复杂图像识别
7. 多人权限协作
8. Web / 移动端测试
9. 全控件覆盖
10. 完整报表中心
```

### 8.3 MVP 禁止一开始做重

```text
1. 不做万能 UI 自动化平台
2. 不做完整测试管理系统
3. 不做复杂企业级权限
4. 不做全自动可信 AI
5. 不做大而全数据库
6. 不把 Bug 库做成负担很重的人工知识库
```

---

## 9. MVP 开发阶段

### MVP-0：数据库与 Designer / Runner 双端骨架

目标：

```text
Designer 和 Runner 能连接同一个数据库。
```

验收：

```text
1. Designer 能新建 AppProject；
2. Runner 能读取 AppProject；
3. HumanDecisionLog 能写入；
4. 所有对象有 ID 和版本号。
```

### MVP-1：DeepLaunch 已配置启动测试

目标：

```text
验证已配置好的 DeepLaunch 格子，是否能通过 F1 + X 启动目标程序。
```

测试链：

```text
F1 → X → 检测目标程序启动 → 写入结果
```

### MVP-2：DeepLaunch 配置生效测试

目标：

```text
验证从绑定程序到启动程序的完整链路。
```

测试链：

```text
绑定程序 → 保存 → F1 + X → 程序启动
```

### MVP-3：红绿灯与失败诊断卡

目标：

```text
Runner 失败后，不只显示失败，而是生成诊断卡。
```

输出：

```text
BugRecord
BugDiagnosis
HumanDecisionLog
```

### MVP-4：AI 读取 VCL 代码 / 文档生成测试草稿

目标：

```text
AI 基于已有样板和代码索引生成测试配置草稿。
```

顺序：

```text
先 VCL，后 FMX。
```

### MVP-5：Bug 经验反哺

目标：

```text
一次失败经验能影响下一次测试配置生成。
```

验收：

```text
历史失败 → 用户确认原因 → 系统记录 → 下次同类测试提醒补断言
```

### MVP-6：FMX 支持增强

重点：

```text
TestId
Name
StyleName
OnClick / OnTap
黄灯规则
```

---

## 10. MVP-1：DeepLaunch 已配置启动测试

### 10.1 宝物 Output

```text
用户在 DeepLaunch 中按 F1 + X 后，已绑定的目标程序能够成功启动。
```

### 10.2 前置条件

```text
1. DeepLaunch 可运行；
2. X 键已有绑定；
3. 目标程序路径有效；
4. 目标程序可被进程 / 窗口 / 文件标志识别。
```

### 10.3 倒推门禁链

```text
宝物 Output：
目标程序已成功启动

← 负一号门：
LaunchVerifyGate / 启动验证门
验证目标进程或目标窗口是否出现。

← 负二号门：
HotkeyActionGate / 双键动作门
Runner 成功发送 F1 + X。

← 负三号门：
GridReadyGate / Grid 就绪门
DeepLaunch 主界面与 60 格 Grid 已出现。

← 负四号门：
MainWindowGate / 主界面门
F1 后 DeepLaunch 主界面已被唤出。

← 负五号门：
DeepLaunchReadyGate / 深启运行就绪门
DeepLaunch 程序已启动或后台可响应 F1。
```

### 10.4 JourneyStep 草案

```text
0. PrepareTargetStateGate
   准备目标程序状态，避免误判。

1. DeepLaunchReadyGate
   确认 DeepLaunch 已运行或可启动。

2. MainWindowGate
   发送 F1，验证主界面出现。

3. GridReadyGate
   验证 60 格 Grid 可见。

4. HotkeyActionGate
   发送目标键 X。

5. LaunchVerifyGate
   验证目标程序进程 / 窗口出现。

6. TargetIdentityGate
   验证启动目标与预期路径 / 标题匹配。
```

### 10.5 MVP-1 最小验收

```text
Runner 能自动执行：
F1 → X → 检测目标程序启动 → 写入结果。
```

### 10.6 MVP-1 增强验收

```text
1. 能显示每一步通过 / 失败；
2. 失败后能生成诊断卡；
3. 失败能写入 BugRecord；
4. 用户能用 1-9 / 0 选择失败原因；
5. 结果能触发红 / 黄 / 绿 / 灰灯。
```

---

## 11. DeepUITestProbe.exe 设计

### 11.1 定位

```text
DeepUITestProbe.exe 是深测内置测试靶子程序。
用于验证 DeepLaunch、启动器、快捷键、工作流等功能是否真的启动了指定程序。
```

### 11.2 为什么需要 Probe

如果使用 notepad.exe / calc.exe / 浏览器等真实软件，可能出现：

```text
1. 程序已经在运行；
2. 程序只允许单实例；
3. 窗口标题不稳定；
4. 启动速度不稳定；
5. 程序可能弹更新框；
6. 断言容易误判。
```

Probe 的价值是：

```text
启动后留下可验证证据。
```

### 11.3 MVP 必须能力

```text
1. 接收 case-id；
2. 接收 run-id；
3. 接收 signal-file 路径；
4. 启动后显示固定窗口；
5. 启动后写入 signal.json；
6. 保持运行一段时间；
7. 允许 Runner 根据进程、窗口、signal 文件进行强断言。
```

### 11.4 推荐命令行

```text
DeepUITestProbe.exe
  --case-id=deeplaunch.hotkey.launch.configured
  --run-id=RUN-0001
  --signal-file=%TEMP%\DeepUITest\Probe\RUN-0001\signal.json
  --window-title="DeepUITest Probe RUN-0001"
  --stay-seconds=30
```

### 11.5 signal.json 示例

```json
{
  "app": "DeepUITestProbe",
  "caseId": "deeplaunch.hotkey.launch.configured",
  "runId": "RUN-0001",
  "processId": 12345,
  "startedAt": "2026-05-12T10:30:00",
  "args": "--case-id=... --run-id=...",
  "status": "started"
}
```

### 11.6 Runner 断言

```text
1. 进程 DeepUITestProbe.exe 存在；
2. 窗口标题包含 RUN-0001；
3. signal.json 存在；
4. signal.json 中 runId = RUN-0001；
5. signal.json 中 caseId = 当前 TestCaseID。
```

### 11.7 红绿灯影响

```text
使用 Probe 且 runId / caseId 匹配：
强断言，可绿灯。

只用普通程序进程名：
断言偏弱，可能黄灯。

进程存在但 signal 不存在：
黄灯或红灯。

signal 存在但 runId 不匹配：
红灯。
```

---

## 12. 第一版数据库建议

MVP 第一版控制在 16 张核心表以内：

```text
1. AppProject
2. AppVersion
3. SourceFileIndex
4. WindowDef
5. ControlDef
6. TestCase
7. JourneyStep
8. AssertRule
9. LampEvaluation
10. RunnerBatch
11. RunnerResult
12. RunnerStepResult
13. BugRecord
14. BugDiagnosis
15. BugObjectLink
16. HumanDecisionLog
```

暂缓但预留：

```text
1. BugPattern
2. BugLearningRule
3. BugKnowledgeHit
4. BugPatternFeedback
```

---

## 13. HumanDecisionLog 当前关键记录

```text
HumanDecisionLog-006
产品名：深测 DeepUITest
边界：暂时只管 Windows 桌面程序
形态：配置端 + 测试端 + 共享数据库

HumanDecisionLog-007
支持 AI 读取开发文档和代码生成测试配置。
AI 生成候选配置，人审核关键点，Runner 验证。

HumanDecisionLog-008
增加 FMX 支持与红绿灯机制。
目标：减少人类审核负担。

HumanDecisionLog-009
继续细化红绿灯机制。
红绿灯是 AI 生成配置的证据门禁。

HumanDecisionLog-010
组织 5 位专家讨论 VCL / FMX 读取、红绿灯、AI 配置生成。

HumanDecisionLog-011
增加跨软件 Bug 记录库，让 AI 越测越聪明。

HumanDecisionLog-012
继续讨论 DeepUITest 第一版 MVP 具体模块。
```

---

## 14. 当前冻结句

```text
深测 DeepUITest 第一版不是万能自动化测试平台，
而是一个能跑通闭环的 Windows 桌面程序 UI 行为测试台。

它先从 DeepLaunch 的 F1 + X 启动测试开始，
用 Designer 配置测试链，
用 Runner 回放验证，
用红绿灯判断可信度，
用失败诊断卡记录 Bug，
用跨软件 Bug 库反哺 AI，
逐步扩展到 VCL / FMX 程序的更多行为链测试。
```
