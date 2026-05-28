# GuidedUse.005 - GuidePackage 数据模型

> 状态：开发文档初版
> 用途：定义善用包的第一版 JSON 对象结构

---

## 1. 善用包定义

```text
GuidePackage = 一个软件的一组任务旅程 + 场域图 + 步骤说明 + 视觉锚点 + 路由 + 迷路恢复 + 执行记录。
```

示例：

```text
DeepLaunch 善用包
Cursor 善用包
ChatGPT 善用包
某自研软件善用包
```

---

## 2. 对象结构

```text
GuidePackage
  -> SoftwareProfile
  -> TaskJourney[]
     -> GuideStep[]
        -> StepInstruction
        -> SceneVisual
        -> VisualAnchor[]
        -> RouteRule[]
        -> LostRecovery[]
  -> TraceEvent[]
```

数据落点：

```text
MVP 阶段 GuidePackage 可以先作为本地 JSON 文件存在。
DB2 后续保存本地索引、草稿、TraceEvent 和离线同步队列。
DB3 后续保存云端发布包、版本、模板、统计和 AI 任务记录。
DB4 不保存 GuidePackage 内容，只保存账号、支付和权益；GuidedUse 通过 DeepBase Commerce/Auth 统一模块使用这些能力。
```

---

## 3. GuidePackage

字段：

```text
packageId
packageName
displayName
version
language
softwareProfile
taskJourneys[]
createdAt
updatedAt
isSealed
```

说明：

```text
packageId：稳定 ID，例如 guideduse.deeplaunch.intro。
isSealed：样板包封版后置为 true。
```

---

## 4. SoftwareProfile

字段：

```text
softwareId
softwareName
processName
windowTitlePattern
supportedVersions[]
launchHint
homepage
notes
```

用途：

```text
描述目标软件，帮助播放器绑定目标窗口或提示用户打开软件。
```

---

## 5. TaskJourney

字段：

```text
journeyId
title
description
outputKey
riskLevel
startStepId
steps[]
```

示例：

```text
journeyId: deeplaunch.bind-first-program
title: 绑定第一个快速启动程序
outputKey: deeplaunch.grid.program_binding.ready
riskLevel: L1
```

---

## 6. GuideStep

字段：

```text
stepId
stepOrder
gateKey
fieldKey
title
instruction
sceneVisualId
primaryAnchorId
routeRules[]
lostRecoveryIds[]
expectedResult
```

原则：

```text
每个步骤必须有一个主目标 PrimaryAnchor。
每个步骤必须有 ExpectedResult。
关键步骤必须有 LostRecovery。
```

---

## 7. SceneVisual

字段：

```text
sceneVisualId
visualType
title
canvasWidth
canvasHeight
backgroundRef
anchors[]
```

visualType：

```text
ScreenshotVisual
SketchVisual
FocusSketch
RecoverySketch
HybridVisual
```

原则：

```text
运行时默认使用 FocusSketch，不追求完整复刻 UI。
```

---

## 8. VisualAnchor

字段：

```text
anchorId
anchorType
label
x
y
width
height
colorRole
targetHint
boundStepId
```

anchorType：

```text
PrimaryFocus
CandidateTarget
ContextFrame
ExpectedResult
RiskArea
MutedArea
RecoveryTarget
```

colorRole：

```text
pink-solid      当前唯一主操作目标
pink-dashed     候选目标
blue-frame      当前场域范围
yellow-warning  注意 / 风险
green-success   成功状态
gray-muted      背景弱化
```

---

## 9. RouteRule

字段：

```text
routeId
fromStepId
trigger
condition
toStepId
fallbackStepId
message
```

trigger：

```text
Completed
Lost
CannotFindButton
PageDifferent
Back
Skip
Restart
Exit
```

---

## 10. LostRecovery

字段：

```text
lostRecoveryId
question
possibleReasons[]
options[]
recommendedOption
returnStepId
riskLevel
```

原则：

```text
LostRecovery 必须能回到某个步骤、进入风险分支或退出任务。
```

---

## 11. TraceEvent

字段：

```text
traceId
packageId
journeyId
stepId
eventType
eventValue
createdAt
note
```

eventType：

```text
StepShown
CompletedClicked
LostClicked
OptionSelected
RecoveryShown
TaskCompleted
TaskExited
```

---

## 12. 最小 JSON 骨架

```json
{
  "packageId": "guideduse.deeplaunch.intro",
  "displayName": "DeepLaunch 入门善用包",
  "version": "0.1.0",
  "softwareProfile": {},
  "taskJourneys": [],
  "isSealed": false
}
```
