# DeepUITest.005 - 系统架构与数据模型

> 状态：开发文档初版
> 用途：整理 DeepUITest 的模块边界、核心对象和第一版数据库表

---

## 1. 系统模块

```text
DeepUITest Designer
DeepUITest Runner
DeepUITest DB
DeepUITestProbe.exe
AI Config Generator
BugRecordLibrary
DeepBase DB1 / DB2 Adapter
DeepUITest Cloud API Client
```

---

## 1.1 数据部署边界

DeepUITest 采用 DeepBase 的 DB1 + DB2 + DB3 + DB4 口径：

```text
DB1：本地 config.db，只放配置、路径、偏好和 API 端点。
DB2：本地 SQLite 业务库，放 AppProject / TestCase / RunnerResult / BugRecord 等第一版核心表。
DB3：公网业务后端 PG，只由后端服务访问；桌面端通过 HTTPS API 使用共享项目、样板库和 BugPattern。
DB4：认证、支付、权益后端库，由 DeepBase Commerce/Auth 框架统一封装；DeepUITest 只集成框架客户端，不自建 DB4 访问层。
```

第一阶段系统架构不依赖 DB3 / DB4：

```text
Designer / Runner
  -> DB1 config.db
  -> DB2 local SQLite
```

后续云端能力再扩展为：

```text
Designer / Runner
  -> HTTPS API
  -> DeepUITest Backend
  -> DB3 PG

Designer / Runner
  -> HTTPS API
  -> DeepBase Commerce/Auth Backend
  -> DB4
```

桌面端不得直连公网 PG，不得保存支付密钥。

---

## 2. Designer 职责

Designer 负责配置、审核和查看结果。

第一版页面建议：

```text
1. 项目页
2. 源码 / 文档索引页
3. 测试用例页
4. Runner 执行页
5. 失败诊断页
```

第一版能力：

```text
1. 新建 AppProject / AppVersion。
2. 手工创建 TestCase。
3. 手工编辑 JourneyStep。
4. 手工编辑 AssertRule。
5. 查看 RunnerResult / RunnerStepResult。
6. 查看 LampEvaluation。
7. 查看 BugDiagnosis。
8. 记录 HumanDecisionLog。
```

暂缓：

```text
复杂权限
完整报表
批量回归中心
完整 BugPattern 管理
```

---

## 3. Runner 职责

Runner 负责执行测试任务。

第一版执行流程：

```text
1. 加载 RunnerBatch。
2. 读取 TestCase / JourneyStep / AssertRule。
3. 准备运行目录。
4. 启动或定位被测程序。
5. 执行动作。
6. 采集截图、日志、信号文件。
7. 执行断言。
8. 写 RunnerResult / RunnerStepResult。
9. 生成 LampEvaluation。
10. 失败时生成 BugRecord / BugDiagnosis。
```

---

## 4. 核心对象关系

```text
AppProject
  -> AppVersion
     -> TestCase
        -> JourneyStep
        -> AssertRule
        -> LampEvaluation
        -> RunnerResult
           -> RunnerStepResult
        -> BugRecord
           -> BugDiagnosis
           -> BugObjectLink
```

源码与 UI 索引：

```text
AppVersion
  -> SourceFileIndex
  -> WindowDef
     -> ControlDef
```

决策留痕：

```text
HumanDecisionLog 可挂 AppProject / AppVersion / TestCase / BugDiagnosis / LampEvaluation。
```

---

## 5. 第一版数据库表

第一版控制在 16 张核心表以内：

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

---

## 6. 表字段草案

### AppProject

```text
AppProjectId
Name
DisplayName
AppKind
TechStack
RootPath
Description
CreatedAt
UpdatedAt
```

### AppVersion

```text
AppVersionId
AppProjectId
VersionName
VersionNo
BuildNo
ExecutablePath
SourceRoot
IsSealed
SealedAt
CreatedAt
```

### SourceFileIndex

```text
SourceFileIndexId
AppVersionId
FilePath
FileKind
Encoding
Hash
IndexedAt
EvidenceScore
```

### WindowDef

```text
WindowDefId
AppVersionId
WindowName
WindowTitle
ClassName
SourceFileIndexId
LocatorHint
EvidenceScore
```

### ControlDef

```text
ControlDefId
WindowDefId
ControlName
ControlText
ControlClass
ControlKind
TestId
OCGSId
LocatorType
LocatorValue
FallbackLocators
EvidenceScore
```

### TestCase

```text
TestCaseId
AppVersionId
Title
OutputKey
RiskLevel
Priority
Status
IsSealed
CreatedBy
CreatedAt
```

### JourneyStep

```text
JourneyStepId
TestCaseId
StepOrder
GateKey
StepName
ActionType
TargetRef
InputValue
TimeoutMs
ExpectedState
OnFailPolicy
```

### AssertRule

```text
AssertRuleId
TestCaseId
JourneyStepId
AssertType
TargetRef
ExpectedValue
Tolerance
RequiredLevel
EvidenceKind
```

### LampEvaluation

```text
LampEvaluationId
TestCaseId
RunnerResultId
LampState
RiskLevel
ReasonCode
ReasonText
EvidenceSummary
CreatedAt
```

### RunnerBatch

```text
RunnerBatchId
AppVersionId
BatchName
RunMode
StartedAt
FinishedAt
Status
Operator
```

### RunnerResult

```text
RunnerResultId
RunnerBatchId
TestCaseId
RunId
Status
LampState
StartedAt
FinishedAt
WorkingDir
LogPath
ScreenshotDir
```

### RunnerStepResult

```text
RunnerStepResultId
RunnerResultId
JourneyStepId
StepOrder
Status
ActualValue
ErrorCode
ErrorMessage
EvidencePath
StartedAt
FinishedAt
```

### BugRecord

```text
BugRecordId
RunnerResultId
TestCaseId
Title
BugType
ObservedFailurePoint
RootCausePoint
Severity
Status
CreatedAt
```

### BugDiagnosis

```text
BugDiagnosisId
BugRecordId
CandidateNo
DiagnosisText
SelectedByUser
UserChoiceValue
Confidence
CreatedAt
```

### BugObjectLink

```text
BugObjectLinkId
BugRecordId
ObjectType
ObjectId
LinkRole
Note
```

### HumanDecisionLog

```text
HumanDecisionLogId
ScopeType
ScopeId
DecisionKey
DecisionText
Options
SelectedOption
Reason
CreatedAt
```

---

## 7. 后续扩展表

暂缓到 MVP-5 后：

```text
BugPattern
BugLearningRule
BugKnowledgeHit
BugPatternFeedback
BugResolution
BugAttachment
LampRule
EvidenceChain
MockDataSet
```
