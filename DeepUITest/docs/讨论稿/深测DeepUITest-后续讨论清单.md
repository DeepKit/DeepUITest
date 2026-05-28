# 深测 DeepUITest 后续讨论清单

> 用途：用于下一轮会话继续推进。  
> 原则：先不推进细节代码，先把产品边界、MVP、模块、数据结构和样板链路逐步定清楚。  

---

## 一、优先级最高的后续讨论

### 1. Runner 最小执行器设计

需要讨论：

```text
1. Runner MVP 支持哪些动作？
2. 如何启动被测程序？
3. 如何发送 F1 + X？
4. 如何等待窗口出现？
5. 如何执行进程 / 窗口 / 文件断言？
6. 如何截图和写日志？
7. 如何生成 RunnerStepResult？
8. 如何与 BugRecord / 失败诊断卡连接？
```

建议先定最小动作集：

```text
1. StartProcess
2. EnsureProcess
3. WaitWindow
4. SendHotkey
5. SendKey
6. VerifyProcess
7. VerifyWindow
8. VerifyFile
9. TakeScreenshot
10. WriteLog
```

---

### 2. MVP-1 失败诊断卡完整设计

需要讨论：

```text
1. Runner 失败后用户看到什么？
2. 如何显示失败位置 Gate / Step？
3. 如何显示预期结果和实际结果？
4. AI 候选原因怎么生成？
5. 历史 Bug 命中如何显示？
6. 用户如何用 1-9 / 0 选择？
7. 选择后写入哪些表？
8. 哪些选择会生成 BugPatternCandidate？
```

DeepLaunch MVP-1 失败候选可先用：

```text
1. X 键没有绑定目标程序
2. DeepLaunch 没有捕获 X 键
3. 目标程序路径无效
4. Runner 发送按键失败
5. 目标程序启动太慢
6. DeepLaunch 主界面未获得焦点
7. 目标程序已运行，断言误判
8. 权限不足
9. 暂时不确定
0. 返回
```

---

### 3. DeepLaunch 配置生效测试 JourneyStep

这是 MVP-2。

需要讨论：

```text
1. 如何从“已配置启动测试”升级到“配置后启动测试”？
2. 如何找到空格子？
3. 如何进入编辑窗体？
4. 如何选择或填写程序路径？
5. 如何保存？
6. 如何断言配置写入？
7. 如何断言 Grid 显示更新？
8. 如何断言 KeyMap / 运行时映射刷新？
9. 如何最终按 F1 + X 启动？
10. 失败时如何进入 Bug 库？
```

核心宝物：

```text
用户把 X 程序绑定到 DeepLaunch 某个键后，
以后按 F1 + X 能启动该程序。
```

---

### 4. Designer 创建测试用例界面

需要讨论：

```text
1. 项目页怎么设计？
2. 测试用例页怎么设计？
3. JourneyStep 怎么编辑？
4. AssertRule 怎么编辑？
5. 红绿灯怎么展示？
6. 如何用数字候选降低配置负担？
7. 如何支持“手工创建 → AI 补全 → Runner 验证”？
```

建议第一版 5 个页面：

```text
1. 项目页
2. 源码 / 文档索引页
3. 测试用例页
4. Runner 执行页
5. 失败诊断页
```

---

### 5. 共享数据库第一版 16 张表结构

需要讨论字段细节：

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

需要明确：

```text
1. 主键命名规则；
2. App / Version / TestCase 之间关系；
3. JourneyStep 如何挂 Gate；
4. AssertRule 如何挂 State；
5. RunnerResult 如何回写灯色；
6. BugRecord 如何多点挂载；
7. HumanDecisionLog 如何记录用户选择；
8. 是否需要 VersionNo / IsSealed 字段。
```

---

## 二、第二优先级讨论

### 6. VCL 代码读取规则

需要讨论：

```text
1. 如何索引 .pas / .dfm？
2. 如何识别 Form？
3. 如何识别控件 Name / Caption / Class？
4. 如何识别 ActionList？
5. 如何识别 OnClick / OnExecute？
6. 如何生成 WindowDef / ControlDef？
7. 如何生成候选 Action？
8. 如何给代码证据打分？
```

---

### 7. FMX 代码读取规则

需要讨论：

```text
1. 如何索引 .pas / .fmx？
2. 如何识别 Name / StyleName？
3. 如何识别 OnClick / OnTap？
4. 如何处理 LiveBindings？
5. 如何设计 TestId 建议规范？
6. FMX 无 TestId 时如何标黄？
7. 哪些 FMX 控件第一版支持，哪些暂缓？
```

---

### 8. 红绿灯评估算法第一版

需要讨论：

```text
1. DocumentEvidence 如何评分？
2. CodeEvidence 如何评分？
3. UIEvidence 如何评分？
4. AssertEvidence 如何评分？
5. RunnerEvidence 如何评分？
6. HistoryBugEvidence 如何评分？
7. 哪些情况直接红灯？
8. 哪些情况黄灯？
9. 如何从黄灯恢复绿灯？
```

---

### 9. Bug 库第一版数据流

需要讨论：

```text
1. Runner 失败如何生成 BugRecord？
2. AI 如何生成候选原因？
3. 用户选择后如何写 BugDiagnosis？
4. BugObjectLink 如何挂 Gate / Step / Assert / Locator / CodeRef？
5. 什么时候生成 BugPatternCandidate？
6. BugPattern 什么时候影响下一次配置生成？
7. BugPatternFeedback 如何避免误伤？
```

---

### 10. DeepUITestProbe.exe 实现草案

需要讨论：

```text
1. 用 Delphi VCL 还是 FMX 写？
2. 命令行参数怎么解析？
3. signal.json 怎么写？
4. 窗口标题怎么生成？
5. stay-seconds 如何处理？
6. 是否支持 delay-ms？
7. 是否支持 no-signal / wrong-run-id 等失败模拟？
8. Probe 是否作为 DeepUITest 内置工具打包？
```

---

## 三、第三优先级讨论

### 11. AI 配置生成器的提示词与约束

需要讨论：

```text
1. AI 读取文档时输出什么结构？
2. AI 读取源码时输出什么结构？
3. AI 如何生成 TestCase / JourneyStep / AssertRule？
4. AI 如何输出 EvidenceChain？
5. AI 不能直接绿灯的情况有哪些？
6. AI 生成草稿如何进入人工审核？
```

---

### 12. TestId / OCGSId 工程规范

需要讨论：

```text
1. VCL 控件如何加 TestId？
2. FMX 控件如何加 TestId？
3. TestId 命名规则是什么？
4. TestId 与 OCGSId / GateId / AbilityId 的关系？
5. 老项目如何渐进式补 TestId？
6. 没有 TestId 的控件如何降级定位？
```

---

### 13. DeepUITest 与善用 / DeepLaunch 的关系

需要讨论：

```text
1. DeepUITest 是否可以测试善用图卡播放链？
2. DeepUITest 是否可以测试 DeepLaunch F2 语义遥控？
3. DeepLaunch 是否可以作为 DeepUITest 的启动入口？
4. 善用图卡是否可以复用 DeepUITest 的 JourneyStep？
5. 三者是否共享 OCGS Gate / Output / Action 术语？
```

---

### 14. DeepUITest 第一版文件体系

需要讨论是否撰写以下文件：

```text
1. DeepUITest.001-产品定位与边界.md
2. DeepUITest.003-MVP路线图.md
3. DeepUITest.005-Designer配置端PRD.md
4. DeepUITest.007-Runner测试端PRD.md
5. DeepUITest.009-共享数据库Schema.md
6. DeepUITest.011-红绿灯机制说明.md
7. DeepUITest.013-Bug记录库设计.md
8. DeepUITest.015-DeepLaunch样板测试链.md
9. DeepUITest.017-VCL-FMX代码读取规则.md
10. DeepUITest.019-DeepUITestProbe设计.md
```

---

## 四、建议下一轮开场问题

下一轮可以从以下问题中选一个：

```text
1. 请继续讨论 Runner 最小执行器设计。
2. 请继续讨论 MVP-1 的失败诊断卡。
3. 请继续讨论 DeepLaunch 配置生效测试 JourneyStep。
4. 请继续讨论 Designer 配置端界面草图。
5. 请继续讨论共享数据库 16 张表结构。
6. 请开始撰写 DeepUITest.001-产品定位与边界.md。
7. 请开始撰写 DeepUITest.003-MVP路线图.md。
```

如果要最稳推进，建议顺序是：

```text
1. Runner 最小执行器设计
2. MVP-1 失败诊断卡
3. 共享数据库 16 张表结构
4. DeepLaunch 配置生效测试 JourneyStep
5. Designer 配置端界面草图
6. VCL / FMX 代码读取规则
7. AI 配置生成器规则
```

---

## 五、给下一会话的提醒

```text
1. 不要把 DeepUITest 做成万能自动化测试平台。
2. 第一版只做 Windows 桌面程序，优先 VCL，再 FMX。
3. 不要先做 AI 全自动生成，先跑通人工配置测试链。
4. DeepLaunch F1 + X 是第一条样板链。
5. 红绿灯是减少人工审核的机制，不是装饰。
6. Bug 库要从 Runner 失败中自然生长，不要一开始做重知识库。
7. 所有用户选择继续沿用 1-9 / 0 的数字候选原则。
8. 重要选择继续记录 HumanDecisionLog。
```
