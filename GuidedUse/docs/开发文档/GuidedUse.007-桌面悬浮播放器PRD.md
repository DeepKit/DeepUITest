# GuidedUse.007 - 桌面悬浮播放器 PRD

> 状态：开发文档初版
> 用途：定义善用第一版播放器的界面、交互和验收标准

---

## 1. 产品目标

播放器负责把 GuidePackage 播给用户看。

第一版目标：

```text
加载本地 GuidePackage，
绑定或提示打开目标软件，
显示当前步骤、FocusSketch、操作提示和恢复入口，
带用户完成一个真实任务。
```

---

## 2. 不做范围

第一版播放器不做：

```text
1. 自动点击目标软件。
2. 自动填写目标软件。
3. 复杂窗口坐标映射。
4. 复杂 UI Automation。
5. 云端账号登录。
6. 多人协作。
7. 模板市场。
```

---

## 3. 核心界面

第一版界面由四块组成：

```text
1. 顶部任务栏
   显示任务名、当前步骤序号、目标软件状态。

2. 步骤提示区
   显示当前 StepInstruction。

3. FocusSketch 区
   显示当前步骤的聚焦线框图。

4. 操作区
   已完成 / 我迷路了 / 找不到按钮 / 上一步 / 退出。
```

---

## 4. 悬浮行为

播放器应支持：

```text
1. TopMost 置顶。
2. 可拖动位置。
3. 可折叠为小浮条。
4. 可展开 FocusSketch。
5. 可保持在目标窗口旁边。
6. 不默认遮挡用户主要操作区域。
```

第一版可以不做精准贴边，允许用户手动移动。

---

## 5. 目标窗口绑定

第一版绑定方式：

```text
1. 根据 SoftwareProfile.processName 查找进程。
2. 根据 windowTitlePattern 查找窗口。
3. 找不到时提示用户打开目标软件。
4. 允许用户手动选择窗口。
```

绑定状态：

```text
Bound       已绑定目标窗口
NotFound    未找到目标窗口
Changed     目标窗口变化
Unknown     未检测
```

目标窗口丢失时：

```text
提示用户重新打开或重新选择目标窗口，不自动退出任务。
```

---

## 6. 步骤播放

用户点击“已完成”：

```text
1. 写 TraceEvent: CompletedClicked。
2. 根据 RouteRule 找到下一步。
3. 切换到下一 GuideStep。
4. 渲染新的 StepInstruction 和 FocusSketch。
```

用户点击“上一步”：

```text
1. 返回前一个 GuideStep。
2. 写 TraceEvent: BackClicked。
```

用户点击“退出”：

```text
1. 确认退出。
2. 写 TraceEvent: TaskExited。
```

---

## 7. 迷路入口

第一版固定入口：

```text
我迷路了
找不到按钮
页面不一样
重新选择目标
```

触发后：

```text
1. 显示当前步骤绑定的 LostRecovery。
2. 如果没有专用 LostRecovery，显示通用恢复。
3. 用户选择恢复项。
4. 根据 RouteRule 回到主路径、进入风险分支或退出。
```

---

## 8. TraceEvent

播放器必须记录：

```text
StepShown
CompletedClicked
LostClicked
OptionSelected
RecoveryShown
BackClicked
TaskCompleted
TaskExited
```

第一版先写本地 JSONL 或 SQLite 均可，具体实现后续定。

---

## 9. 验收标准

播放器 MVP 验收：

```text
1. 能打开本地 GuidePackage。
2. 能显示任务列表。
3. 能进入一个 TaskJourney。
4. 能显示当前步骤文本。
5. 能渲染 FocusSketch。
6. 能点击已完成进入下一步。
7. 能点击我迷路了进入恢复。
8. 能从恢复回到主路径。
9. 能记录 TraceEvent。
10. 能完成 DeepLaunch 样板任务全流程播放。
```

