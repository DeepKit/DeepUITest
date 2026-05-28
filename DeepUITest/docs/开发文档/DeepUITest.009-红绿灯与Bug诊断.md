# DeepUITest.009 - 红绿灯与 Bug 诊断

> 状态：开发文档初版
> 用途：定义第一版灯色规则、风险等级、失败诊断卡和 Bug 入库边界

---

## 1. 红绿灯定位

红绿灯不是装饰，而是测试配置可信度门禁系统。

目标：

```text
AI 或人工生成测试配置后，不要求人逐条全量审核；
系统用证据和 Runner 结果分流，让人重点处理黄灯和红灯。
```

---

## 2. 灯色定义

```text
Green / 绿灯
证据充分，Runner 通过，可封版。

Yellow / 黄灯
大体可信，但有关键不确定点，需要人工确认。

Red / 红灯
不能执行或不能封版，必须修正。

Gray / 灰灯
信息不足，暂时无法判断，需要补材料。
```

---

## 3. 风险等级与灯色分开

```text
LampState = 配置可信不可信。
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

## 4. MVP-1 灯色规则

### 绿灯

MVP-1 全部满足时绿灯：

```text
1. DeepLaunch 已运行或能被 Runner 启动。
2. F1 后主界面 / Grid 出现或达到可接收目标键状态。
3. Runner 成功发送目标键 X。
4. DeepUITestProbe.exe 进程出现。
5. Probe 窗口标题包含当前 run-id。
6. signal.json 存在。
7. signal.json 中 runId 与当前 run-id 一致。
8. signal.json 中 caseId 与当前 TestCase 一致。
9. 本次测试不使用生产数据，不产生不可逆操作。
```

### 黄灯

典型黄灯：

```text
1. 进程存在，但窗口标题未匹配。
2. 进程存在，但 signal.json 写入延迟，重试后成功。
3. 普通目标程序启动成功，但不是 Probe，断言偏弱。
4. DeepLaunch 主界面识别不稳定，但最终 Probe 启动成功。
5. 历史 Bug 命中，但当前断言已有覆盖。
```

### 红灯

典型红灯：

```text
1. Runner 回放失败。
2. 找不到 DeepLaunch。
3. F1 后主界面未出现。
4. 目标键发送后 Probe 未启动。
5. signal.json 不存在。
6. signal.json runId 不匹配。
7. signal.json caseId 不匹配。
8. 启动了错误程序。
9. 测试可能破坏真实数据。
```

### 灰灯

典型灰灯：

```text
1. 缺测试配置。
2. 缺 DeepLaunch 路径。
3. 缺目标键绑定信息。
4. 缺 Probe 路径。
5. 缺运行环境。
6. 未试跑。
```

---

## 5. 证据链

完整证据链：

```text
1. DocumentEvidence / 文档证据
2. CodeEvidence / 代码证据
3. UIEvidence / 运行时 UI 证据
4. AssertEvidence / 断言证据
5. RunnerEvidence / 回放证据
6. HistoryBugEvidence / 历史 Bug 证据
```

MVP-1 至少记录：

```text
RunnerEvidence
AssertEvidence
UIEvidence
```

---

## 6. 失败诊断卡

Runner 失败后，用户不应看到复杂数据库表，而应看到诊断卡。

诊断卡字段：

```text
测试名称
失败位置 Gate / Step
失败动作
预期结果
实际结果
灯色
风险等级
截图 / 日志 / signal 文件
AI 或规则生成的候选原因
用户 1-9 / 0 选择项
```

MVP-1 失败候选：

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

## 7. BugRecord 第一版边界

Bug 库第一版只做自然生长，不做重知识库。

第一版必须做：

```text
BugRecord
BugDiagnosis
BugObjectLink
HumanDecisionLog
```

第一版暂缓：

```text
BugPattern
BugLearningRule
BugKnowledgeHit
BugPatternFeedback
BugResolution
BugAttachment
```

---

## 8. Bug 类型

第一版至少区分：

```text
ProductBug       软件功能真的有问题
TestConfigBug    测试配置错了
LocatorBug       控件定位失败
AssertBug        断言错误或断言太弱
MockDataBug      测试数据问题
EnvironmentBug   环境问题
PermissionBug    权限问题
TimingBug        等待时机 / 窗口加载时序问题
Unknown          暂时无法判断
```

---

## 9. Bug 多点挂载

Bug 不只挂在 TestCase 上，还应能挂到：

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

LinkRole：

```text
PrimaryFailurePoint
AffectedObject
SuspectedCause
ConfirmedRootCause
EvidenceSource
SuggestedFixTarget
HistoricalSimilarObject
```

第一版最小使用：

```text
PrimaryFailurePoint -> JourneyStep
EvidenceSource -> RunnerStepResult
SuspectedCause -> AssertRule / Environment
```

---

## 10. 用户选择后的写入规则

用户在诊断卡选择 1-9 / 0 后：

```text
1. 写 BugDiagnosis.SelectedByUser = true。
2. 写 HumanDecisionLog，记录候选项、选择、时间。
3. 如果选择明确原因，更新 BugRecord.BugType。
4. 如果选择暂时不确定，BugRecord 保持 Unknown。
5. 不自动提升 BugPattern。
```

