# 深测 DeepUITest：技术与战略讨论总归档

> 用途：用于新会话承接“深测 DeepUITest”后续讨论。  
> 范围：本文件归档本轮关于 DeepUITest 的产品定位、技术结构、MVP、红绿灯机制、跨软件 Bug 库、DeepLaunch 样板链、战略定位、目标客户、护城河与资源节奏等讨论。  
> 注意：本文是结构化归档，不是逐字聊天记录；已保留关键判断、专家共识、冻结句与后续讨论路线。

---

## 0. 当前产品矩阵位置

当前讨论中的核心产品矩阵为：

```text
OCGS
= 能力有序治理系统 / 方法论底座

OCGS-d
= AI 主持式宝物倒推开发流程

深启 DeepLaunch
= Windows 遥控器

善用
= 桌面悬浮式图卡说明书 / 软件任务陪跑系统

深测 DeepUITest
= Windows 桌面程序 UI 行为 Mock / 回归测试系统
```

矩阵关系：

```text
OCGS 是底层方法论；
OCGS-d 是 AI 主持式设计流程；
DeepLaunch 是 Windows 遥控器；
善用是软件任务图卡陪跑系统；
DeepUITest 是行为质量治理 / 测试封版系统。
```

当前战略分工：

```text
DeepLaunch 负责：遥控、启动、快捷执行、F2 语义候选。
善用负责：不能自动安全执行的任务，用图卡陪用户完成。
DeepUITest 负责：验证桌面软件关键行为链是否还能跑通。
OCGS 负责：宝物、门禁、行为链、状态、断言、风险、留痕、封版的底层治理。
```

---

# 第一部分：DeepUITest 技术定位归档

## 1. 产品命名与基本边界

已确定产品名：

```text
深测 DeepUITest
```

基本定位：

```text
面向 Windows 桌面程序的 UI 行为 Mock / 回归测试系统。
```

第一阶段支持范围：

```text
1. Windows 桌面程序；
2. Delphi VCL；
3. Delphi FMX on Windows；
4. 暂不优先支持 Web、移动端、接口测试、性能测试、企业级测试管理平台。
```

系统形态：

```text
1. 配置端 Designer；
2. 测试端 Runner；
3. 共享数据库；
4. AI 配置生成器；
5. 红绿灯可信度机制；
6. 跨软件 Bug 记录库。
```

---

## 2. DeepUITest 的核心区别

普通 UI 自动化测试工具常常关注：

```text
点击按钮；
输入文本；
等待窗口；
截图对比；
脚本回放。
```

DeepUITest 关注：

```text
用户想拿到什么宝物；
必须通过哪些门；
每个场域里有哪些目标对象；
动作是否执行；
状态是否显现；
断言是否可靠；
风险是否可控；
失败是否能归因；
版本是否可以封版。
```

核心差异：

```text
不是测“按钮有没有点到”，
而是测“用户能力链是否还能抵达宝物”。
```

---

## 3. AI 读取文档和代码生成测试配置

已确认：DeepUITest 应支持 AI 读取开发文档和代码生成测试配置草稿。

AI 可读取材料：

```text
1. 开发文档；
2. 功能说明；
3. 使用说明；
4. OCGS 门禁文档；
5. Delphi .pas / .dfm / .fmx；
6. VCL / FMX 窗体结构；
7. ActionList / Menu / PopupMenu；
8. 事件函数 OnClick / OnExecute / OnTap；
9. 数据库结构；
10. 运行时探测结果；
11. 人工录制轨迹；
12. 历史 Bug 记录库。
```

AI 生成内容不应是最终脚本，而是：

```text
语义测试配置草稿。
```

典型生成结构：

```text
ProgramConfig
WindowConfig
ControlMap
OutputDef
GateDef
TestJourney
JourneyStep
AssertRule
MockData
EvidenceChain
LampEvaluation
```

关键原则：

```text
AI 生成的是候选测试配置，不是直接可信的最终配置；
必须经过红绿灯、人工审核、Runner 回放和封版。
```

---

## 4. VCL / FMX 支持策略

### 4.1 VCL 策略

VCL 更容易自动化识别。

优先读取：

```text
.dfm
.pas
TForm
TButton
TEdit
TDBEdit
TStringGrid
TDBGrid
TActionList
TMainMenu
TPopupMenu
OnClick
OnExecute
DataSource / DataSet
```

VCL 优势：

```text
1. 窗体和控件结构清晰；
2. DFM 可解析；
3. ActionList 能暴露能力入口；
4. 外部控件识别相对稳定；
5. 更适合作为第一阶段深度适配对象。
```

### 4.2 FMX 策略

FMX 的运行时外部控件识别比 VCL 更弱。

优先读取：

```text
.fmx
.pas
TForm
TButton
TEdit
TGrid
TListBox
Name
StyleName
LiveBindings
OnClick / OnTap
TestId
```

FMX 规则：

```text
FMX 项目如果没有稳定 TestId / Name / StyleName，默认更容易黄灯。
```

建议未来逐步加入：

```text
TestId
OCGSId
GateId
ActionId
OutputId
StateId
```

目标：

```text
让主产品主动暴露可测试标识，减少脆弱坐标和图像识别。
```

---

# 第二部分：红绿灯机制归档

## 5. 红绿灯机制定位

红绿灯不是装饰，而是：

```text
测试配置可信度门禁系统。
```

目标：

```text
AI 生成 100 条配置，
人不需要逐条全量审核，
而是重点看黄灯和红灯。
```

四类灯色：

```text
Green / 绿灯：证据充分，Runner 通过，可封版。
Yellow / 黄灯：大体可信，但有关键不确定点，需要人工确认。
Red / 红灯：不能执行或不能封版，必须修正。
Gray / 灰灯：信息不足，暂时无法判断，需要补材料。
```

---

## 6. 红绿灯证据链

每条测试配置应有 EvidenceChain：

```text
1. DocumentEvidence / 文档证据；
2. CodeEvidence / 代码证据；
3. UIEvidence / 运行时 UI 证据；
4. AssertEvidence / 断言证据；
5. RunnerEvidence / 回放证据；
6. HistoryBugEvidence / 历史 Bug 证据。
```

绿灯基础条件：

```text
1. 文档证据充分；
2. 代码证据充分；
3. UI 定位稳定；
4. 断言足够强；
5. Runner 回放通过；
6. 风险等级 <= L1；
7. 不使用生产数据；
8. 不涉及未确认高风险动作。
```

黄灯典型原因：

```text
1. 断言偏弱；
2. 控件定位不够稳定；
3. FMX 缺少 TestId；
4. AI 推断业务含义但文档未明确；
5. 测试数据需人工确认；
6. 历史 Bug 命中但配置未补强。
```

红灯典型原因：

```text
1. Runner 回放失败；
2. 找不到关键窗口或控件；
3. 强断言失败；
4. 使用生产环境执行删除 / 覆盖 / 发送 / 提交；
5. 启动了错误程序；
6. 关键动作只能靠绝对坐标且无验证；
7. 测试可能破坏真实数据。
```

灰灯典型原因：

```text
1. 缺文档；
2. 缺源码；
3. 缺运行环境；
4. 缺数据库连接；
5. 缺 Mock 数据；
6. 未试跑。
```

---

## 7. 红绿灯与风险等级的关系

必须区分：

```text
LampState = 配置可信不可信；
RiskLevel = 动作危险不危险。
```

组合示例：

```text
Green + L0：可自动回归。
Green + L2：配置可信，但需沙箱或确认。
Yellow + L0：动作安全，但配置需人审。
Red + L3：既不可信又危险，禁止执行。
```

---

# 第三部分：跨软件 Bug 记录库归档

## 8. Bug 记录库战略意义

新增模块：

```text
BugRecordLibrary / 跨软件 Bug 记录库
```

定位：

```text
不是单软件缺陷表，
而是跨软件、跨版本、跨技术栈的失败经验库。
```

目标：

```text
让 AI 在后续生成测试配置、判断红绿灯、解释失败、推荐修复时变得更聪明。
```

Bug 库进入 DeepUITest 主流程：

```text
开发文档 + 代码 + 窗体结构 + 运行探测 + 录制轨迹 + Bug 记录库
→ AI 生成测试配置
→ 红绿灯分流
→ Runner 回放
→ 失败写入 Bug 库
→ AI 下一次避坑
```

---

## 9. Bug 库三层结构

```text
1. BugRecord：一次具体失败；
2. BugPattern：一类失败模式；
3. BugLearningRule：以后生成测试时如何避坑。
```

示例：

```text
BugRecord：DeepLaunch F1 + X 后目标程序未启动。

BugPattern：配置保存成功但运行时缓存未刷新。

BugLearningRule：凡是配置生效类测试，必须增加运行时生效断言和最终行为断言。
```

---

## 10. BugRecord 多点挂载

Bug 不应只挂在 TestCase 上，而应多点挂载。

可挂载对象：

```text
App
AppVersion
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

建议用关联表：

```text
BugObjectLink
```

LinkRole：

```text
PrimaryFailurePoint       主失败点
AffectedObject            受影响对象
SuspectedCause            疑似原因
ConfirmedRootCause        确认根因
EvidenceSource            证据来源
SuggestedFixTarget        建议修复对象
HistoricalSimilarObject   历史相似对象
```

必须区分：

```text
ObservedFailurePoint：观察到失败的位置；
RootCausePoint：确认根因位置。
```

---

## 11. BugPattern 成熟度

BugPattern 不能由单次失败直接变成全局经验。

建议成熟度：

```text
Candidate：AI 候选，未确认。
Confirmed：人确认过，可影响当前软件或当前功能。
Promoted：多次验证，可跨软件影响。
Deprecated：废弃或不再适用。
```

作用范围 ScopeLevel：

```text
CurrentAppOnly 当前软件
SameModuleOnly 当前模块
SameFunctionType 同类功能
SameTechStack 同技术栈
Global 全局通用
```

必须支持反证与降权：

```text
如果历史 Pattern 经常被标记为“不适用”，应降低其影响权重。
```

---

## 12. Bug 库与红绿灯的关系

BugPattern 命中不等于直接红灯。

它可能产生：

```text
1. 只记录，不影响灯色；
2. 提醒增加断言；
3. 降低某项证据分；
4. Green → Yellow；
5. Yellow / Green → Red；
6. 用户补断言后 Yellow → Green。
```

建议记录：

```text
BugKnowledgeHit
```

字段概念：

```text
命中了哪个 Pattern；
为什么命中；
原灯色；
新灯色；
建议动作；
人是否接受；
是否标记不适用。
```

---

## 13. Bug 诊断卡

Runner 失败后，用户不应看到复杂数据库表，而应看到诊断卡。

诊断卡内容：

```text
测试名称；
失败位置；
失败步骤；
预期结果；
实际结果；
AI 候选诊断；
历史 Bug 命中；
截图 / 日志 / 现场证据；
数字候选处理项。
```

示例：

```text
测试失败：F1 + A 未启动目标程序
失败位置：LaunchVerifyGate / 启动验证门
预期：DeepUITestProbe.exe 启动
实际：未检测到目标进程

可能原因：
1. A 键没有绑定目标程序
2. DeepLaunch 没有捕获 A 键
3. 目标程序路径无效
4. Runner 发送按键失败
5. 目标程序启动太慢
6. DeepLaunch 主界面未获得焦点
0. 返回
```

原则：

```text
用户处理 Bug，不是填数据库；
底层完成复杂挂载和经验沉淀。
```

---

# 第四部分：MVP 技术路线归档

## 14. MVP 核心原则

DeepUITest 第一版不是万能测试平台。

MVP 目标：

```text
一个软件；
一个测试目标；
一条行为链；
一次 Runner 回放；
一次红绿灯；
一次失败诊断；
一次 Bug 入库；
一次经验反哺。
```

必须避免：

```text
1. 一开始做大而全 UI 自动化平台；
2. 一开始支持所有 Windows 技术栈；
3. 一开始追求全量测试覆盖；
4. 一开始做复杂企业级测试管理；
5. 一开始做完整知识图谱。
```

---

## 15. MVP 阶段划分

建议阶段：

```text
MVP-0：数据库与 Designer / Runner 双端骨架

MVP-1：DeepLaunch 已配置启动测试
F1 + X → 指定程序启动

MVP-2：DeepLaunch 配置生效测试
绑定程序 → 保存 → F1 + X → 指定程序启动

MVP-3：红绿灯与失败诊断卡
失败后生成 BugRecord、BugDiagnosis、HumanDecisionLog

MVP-4：AI 读取 VCL 代码 / 文档生成测试草稿
先 VCL，后 FMX

MVP-5：Bug 经验反哺
历史失败影响下一次测试配置生成与红绿灯建议

MVP-6：FMX 支持增强
TestId / Name / StyleName / OnClick / OnTap / 黄灯规则
```

关键判断：

```text
DeepUITest 第一版不要从 AI 开始；
应先从人工配置一条可跑通测试链开始，
再让 AI 逐步接管配置生成。
```

---

## 16. MVP 必须做 / 暂缓做 / 禁止做重

### 必须做

```text
1. 项目登记；
2. VCL / FMX 基础代码读取；
3. AI 测试配置草稿生成；
4. 行为链 Journey 配置；
5. 基础断言 Assert；
6. 红绿灯评估；
7. Runner 基础回放；
8. 失败诊断卡；
9. BugRecord 入库；
10. HumanDecisionLog；
11. 共享数据库；
12. DeepLaunch 样板测试案例。
```

### 暂缓做

```text
1. 大规模批量回归；
2. 完整知识图谱；
3. 自动修复代码；
4. 自动提升全局 BugPattern；
5. 复杂拖拽；
6. 复杂图像识别；
7. 多人权限协作；
8. Web / 移动端测试；
9. 全控件覆盖；
10. 完整报表中心。
```

### 禁止一开始做重

```text
1. 不做万能 UI 自动化平台；
2. 不做完整测试管理系统；
3. 不做复杂企业权限；
4. 不做全自动可信 AI；
5. 不做大而全数据库；
6. 不把 Bug 库做成人工维护负担很重的知识库。
```

---

## 17. MVP 第一批数据库表建议

第一版可控制在 16 张核心表以内：

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

后续扩展：

```text
BugPattern
BugLearningRule
BugKnowledgeHit
BugPatternFeedback
BugResolution
BugAttachment
```

---

# 第五部分：DeepLaunch 作为第一被测对象

## 18. DeepLaunch 三条命脉链

DeepUITest 第一阶段优先守住 DeepLaunch。

DeepLaunch 第一批三条命脉链：

```text
1. 已配置启动链
   F1 → X → 指定程序启动

2. 配置生效链
   绑定程序到格子 → 保存 → F1 + X → 指定程序启动

3. F2 候选执行链
   F2 → 输入 / 转录 → 1-9 候选 → 执行 → 0 返回 / 取消
```

战略顺序：

```text
先验证遥控启动能力；
再验证配置是否真正生效；
最后验证语义遥控候选机制。
```

---

## 19. 第一样板：已配置启动链

样板名称：

```text
DeepLaunch 遥控启动能力封版测试
```

宝物：

```text
用户通过 F1 + X 成功启动指定目标程序。
```

倒推门禁链：

```text
宝物 Output：目标程序成功启动

← 负一号门：LaunchVerifyGate / 启动验证门
← 负二号门：HotkeyActionGate / 热键动作门
← 负三号门：GridReadyGate / Grid 就绪门
← 负四号门：MainWindowGate / 主界面门
← 负五号门：DeepLaunchReadyGate / 深启就绪门
```

最小验收：

```text
Runner 能自动执行：
F1 → X → 检测目标程序启动 → 写入结果。
```

推荐目标程序：

```text
DeepUITestProbe.exe
```

---

## 20. 第二样板：配置生效链

样板名称：

```text
DeepLaunch 配置生效链封版测试
```

宝物：

```text
我把某个程序绑定到 DeepLaunch 的某个键上以后，
按 F1 + X 能启动这个新绑定的程序。
```

战略意义：

```text
验证配置是否真正转化为用户可调用能力。
```

普通 UI 测试只看：

```text
保存提示是否出现。
```

DeepUITest 要看：

```text
配置是否写入；
Grid 是否更新；
运行时映射是否刷新；
F1 + X 是否启动新目标；
启动对象是否与配置对象一致。
```

核心 BugPattern：

```text
保存成功但配置未写入；
配置写入但 UI 未刷新；
UI 刷新但运行时缓存未刷新；
快捷键映射仍指向旧对象；
路径含空格导致启动失败；
保存成功但启动参数丢失；
配置表与内存态不一致。
```

推进方式：

```text
第二样板 A：最小配置生效链；
第二样板 B：完整用户配置链。
```

---

## 21. 第三样板：F2 候选执行链

样板名称：

```text
DeepLaunch F2 语义遥控候选执行封版测试
```

战略意义：

```text
证明 DeepLaunch 不只是快捷启动器，而是 Windows 遥控器。
```

第一版只测：

```text
1. F2 能唤出输入 / 转录小窗；
2. 固定文本输入后能出现候选；
3. 候选项使用 1-9；
4. 用户选择 1 后执行对应动作；
5. 用户选择 0 后取消 / 返回；
6. 执行后可由 Runner 验证结果。
```

第一版不测：

```text
1. 开放式自然语言理解准确率；
2. 真实语音环境鲁棒性；
3. 多轮复杂对话；
4. 习惯链路学习完整机制；
5. 所有 Provider / Executor；
6. 高风险动作自动执行。
```

建议分层：

```text
F2-A：文本候选链
F2-B：取消返回链
F2-C：语音转录链
F2-D：习惯链路学习链
```

---

## 22. DeepUITestProbe.exe

定位：

```text
深测内置测试靶子程序。
用于验证 DeepLaunch / 启动器 / 工作流 / 快捷键是否真的启动了指定程序。
```

MVP 必须能力：

```text
1. 接收 case-id；
2. 接收 run-id；
3. 接收 signal-file 路径；
4. 启动后显示固定窗口；
5. 启动后写入 signal.json；
6. 保持运行一段时间；
7. 允许 Runner 根据进程、窗口、signal 文件进行强断言。
```

推荐命令行：

```text
DeepUITestProbe.exe
  --case-id=deeplaunch.hotkey.launch.configured
  --run-id=RUN-0001
  --signal-file=%TEMP%\DeepUITest\Probe\RUN-0001\signal.json
  --window-title="DeepUITest Probe RUN-0001"
  --stay-seconds=30
```

Runner 断言：

```text
1. 进程 DeepUITestProbe.exe 存在；
2. 窗口标题包含 RUN-0001；
3. signal.json 存在；
4. signal.json 中 runId = RUN-0001；
5. signal.json 中 caseId = 当前 TestCaseID。
```

---

# 第六部分：战略讨论归档

## 23. 第一阶段战略定位

已选择：混合定位。

```text
第一阶段：
自用基础设施 + OCGS 样板工程。

第二阶段：
再包装为 Delphi / VCL / FMX 开发者工具。
```

含义：

```text
短期不急于商业化；
不做大而全测试平台；
先服务自己的 DeepLaunch、善用、UniBase / DeepBase 等桌面软件矩阵；
同时证明 OCGS 的“宝物-门禁-行为链-断言-红绿灯-Bug库-封版”方法论价值。
```

---

## 24. 优先守住哪个软件

专家共识：

```text
DeepUITest 第一阶段优先守住 DeepLaunch。
```

理由：

```text
1. 行为链短；
2. 风险低；
3. 价值直观；
4. OCGS 元素完整；
5. 便于演示；
6. 便于沉淀第一批 Bug 模式；
7. 便于复制到善用和 UniBase。
```

守护顺序：

```text
第一阶段：DeepLaunch
第二阶段：善用
第三阶段：UniBase / DeepBase
第四阶段：OCGS-d 自身流程
第五阶段：对外 Delphi / VCL / FMX 开发者工具化
```

---

## 25. DeepUITest 与 OCGS 的关系

内部定义：

```text
深测 DeepUITest = OCGS 产品矩阵中的能力质量治理系统。
```

对外表达：

```text
深测 DeepUITest：
AI 辅助的 Windows 桌面软件行为回归测试系统。
```

更差异化表达：

```text
为 Windows 桌面软件建立关键行为链的回归封版系统。
```

口语表达：

```text
让你的桌面软件每次修改后，关键操作还能不能跑通，一测就知道。
```

OCGS 体系表达：

```text
深测是 OCGS 在软件质量治理场景中的落地产品，
负责把“宝物-门禁-行为链-状态断言-风险分级-失败留痕-版本封版”转化为可执行的桌面软件行为测试体系。
```

---

## 26. 未来目标客户

客户路径：

```text
第一阶段：
自用，服务自己的 DeepLaunch、善用、UniBase / DeepBase 等桌面软件。

第二阶段：
面向 Delphi / VCL / FMX 老项目开发者和桌面软件小团队。

第三阶段：
再考虑企业测试部门和更广泛 Windows 桌面软件质量治理市场。
```

最适合早期客户：

```text
正在维护老桌面项目、
想用 AI 提升开发效率、
但害怕改坏旧功能的个人开发者和小团队。
```

对外口径：

```text
AI 帮你改代码；
深测帮你确认旧行为有没有坏。
```

---

## 27. 护城河主轴

核心判断：

```text
DeepUITest 的护城河不是“AI 自动生成 UI 测试”，
而是“OCGS 行为链质量治理闭环”。
```

护城河排序：

```text
第一护城河：OCGS 行为链模型
第二护城河：跨软件 Bug 经验库
第三护城河：红绿灯可信度机制
第四护城河：AI 读取代码 / 文档生成测试配置
第五护城河：VCL / FMX 深度适配
```

闭环：

```text
宝物定义
→ 门禁链建模
→ 行为链配置
→ Runner 回放
→ 状态断言
→ 红绿灯可信判断
→ Bug 经验沉淀
→ AI 下次生成更可靠配置
→ 版本封版
```

建议冻结句：

```text
把桌面软件的关键行为链，变成可配置、可回放、可断言、可诊断、可学习、可封版的质量资产。
```

---

## 28. 如何避免拖慢主产品

策略：

```text
伴生开发 + 命脉链守护 + 选择性封版
```

不是：

```text
全面测试平台 + 全量覆盖 + 独立大项目
```

推进原则：

```text
主产品开发一条关键能力；
深测补一条关键行为链。
```

每个产品先守三条命脉链。

DeepLaunch：

```text
1. F1 + X 已配置启动链
2. 绑定程序后配置生效链
3. F2 数字候选执行链
```

善用：

```text
1. 图卡旅程播放链
2. FocusSketch 聚焦框显示链
3. LostRecovery 迷路恢复链
```

UniBase / DeepBase：

```text
1. 打开核心窗体链
2. 保存核心记录链
3. 查询结果链
```

资源占比建议：

```text
80% 精力做主产品；
20% 精力做深测守护链。
```

深测进入条件：

```text
1. 代表产品核心价值；
2. 后续会反复修改；
3. 坏了会严重影响体验；
4. 能形成稳定断言；
5. 对 OCGS 样板有价值。
```

---

# 第七部分：HumanDecisionLog 汇总

```text
HumanDecisionLog-005
状态：暂停“善用 × DeepLaunch 图卡演示案例”。
新话题：多个桌面程序 UI 行为 Mock 测试。

HumanDecisionLog-006
产品名确定：深测 DeepUITest。
范围：Windows 桌面程序；配置端 + 测试端 + 共享数据库。

HumanDecisionLog-007
决定：支持 AI 读取开发文档和代码生成测试配置。
原则：AI 生成候选配置，必须审核与回放验证。

HumanDecisionLog-008
新增支持：VCL + FMX。
新增机制：红绿灯机制，减少人类审核负担。

HumanDecisionLog-009
继续细化红绿灯机制。
目标：减少 AI 生成测试配置后的人工审核负担。

HumanDecisionLog-010
用户要求：由主持人组织 5 个专家继续讨论。
议题：VCL / FMX 读取、配置生成、红绿灯。

HumanDecisionLog-011
新增模块：跨软件 Bug 记录库。
目标：让 AI 变得更聪明。

HumanDecisionLog-012
选择：继续讨论 DeepUITest 第一版 MVP 具体模块。

HumanDecisionLog-013
战略定位选择：5。
第一阶段：自用基础设施 + OCGS 样板。
第二阶段：Delphi / VCL / FMX 开发者工具。

HumanDecisionLog-014
讨论：DeepUITest 第一阶段优先守住哪个软件。
结论：优先守住 DeepLaunch。

HumanDecisionLog-015
讨论：DeepLaunch 三条命脉链中哪条作为第一样板。
结论：已配置启动链。

HumanDecisionLog-016
讨论：DeepUITest 与 OCGS 的关系如何对外表达。
结论：内部是 OCGS 能力质量治理系统；对外是 AI 辅助桌面软件行为回归测试系统。

HumanDecisionLog-017
讨论：第二样板“配置生效链”的战略价值。
结论：它最能体现 DeepUITest 与普通 UI 测试的差异。

HumanDecisionLog-018
讨论：未来对外目标客户。
结论：自用 → Delphi / VCL / FMX 老项目开发者与小团队 → 企业测试部门。

HumanDecisionLog-019
讨论：护城河主轴。
结论：OCGS 行为链质量治理闭环是主护城河。

HumanDecisionLog-020
讨论：如何避免 DeepUITest 拖慢 DeepLaunch 和善用。
结论：伴生开发 + 命脉链守护 + 选择性封版。
```

---

# 第八部分：建议冻结句集合

## DeepUITest 总定位

```text
深测 DeepUITest 是一个面向 Windows 桌面程序，尤其是 Delphi VCL / FMX 项目的 AI 辅助 UI 行为 Mock / 回归测试系统。
```

## OCGS 体系定位

```text
深测 DeepUITest 是 OCGS 在软件质量治理场景中的落地产品，负责把“宝物-门禁-行为链-状态断言-风险分级-失败留痕-版本封版”转化为可执行的桌面软件行为测试体系。
```

## 护城河

```text
深测的护城河不是 AI 自动生成 UI 测试，而是 OCGS 行为链质量治理闭环。
```

## 战略打法

```text
先自用，后外放；
先 VCL / FMX，后泛 Windows；
先关键行为链，后全量测试；
先证明 OCGS 封版价值，后谈商业化。
```

## 伴生开发

```text
深测第一阶段应采用伴生开发模式，不独立膨胀，不追求全量覆盖，只守住每个产品最关键的三条命脉行为链。
```

---

# 第九部分：后续讨论入口

下一步尚未继续展开的问题见单独文件：

```text
深测DeepUITest-后续战略与技术讨论清单.md
```
