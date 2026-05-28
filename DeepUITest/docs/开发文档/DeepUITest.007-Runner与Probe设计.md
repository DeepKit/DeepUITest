# DeepUITest.007 - Runner 与 Probe 设计

> 状态：开发文档初版
> 用途：定义 MVP-1 的 Runner 最小执行器和 DeepUITestProbe.exe

---

## 1. Runner MVP 定位

Runner 是深测的执行端，第一版只服务一个目标：

```text
读取一条手工配置的 DeepLaunch 已配置启动链，
执行 F1 + X，
验证 DeepUITestProbe.exe 是否被成功启动。
```

第一版 Runner 不追求通用 UI 自动化能力，只追求稳定跑通第一条行为链。

---

## 2. Runner 最小动作集

MVP 动作集：

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

动作说明：

```text
StartProcess：启动指定进程。
EnsureProcess：确认进程存在，不存在时可按配置启动。
WaitWindow：等待指定窗口标题或类名出现。
SendHotkey：发送组合键，例如 F1。
SendKey：发送单键，例如 X。
VerifyProcess：断言进程存在。
VerifyWindow：断言窗口存在或标题匹配。
VerifyFile：断言文件存在并可读取。
TakeScreenshot：保存当前屏幕或目标窗口截图。
WriteLog：写 Runner 日志。
```

暂缓动作：

```text
Click
InputText
Drag
MenuSelect
ImageMatch
OCR
复杂 UI Automation 控件操作
```

---

## 2.1 无需截图对比的方案依据

Runner 第一阶段不做截图像素对比。理由：

**结构级断言比像素断言更可靠：**

```text
Probe 进程存在
  → Probe 窗口标题包含 run-id
  → signal.json 存在且内容匹配
```

这三个断言不依赖像素、主题、字体渲染、DPI，比截图对比假阳性率低得多。

**截图对比在第一阶段的问题：**

| 问题 | 影响 |
|------|------|
| 窗体位置偏移 2px | 假阳性 |
| 系统主题换色 | 假阳性 |
| DPI 缩放差异 | 假阳性 |
| 需要 baseline 图像 | 维护负担 |
| 字体渲染微调 | 假阳性 |

**替代方案（不需要 baseline 图像）：**

```text
1. VerifyWindowRect — 窗口尺寸合理性检查
   窗口 Width/Height 不小于预期最小值，不超出屏幕尺寸，
   窗口 Left/Top 在可见区域内（非负数，小于屏幕尺寸）
   → GetWindowRect + 纯计算，零像素对比

2. VerifyControlTree（只对 VCL 有效）
   EnumChildWindows 遍历窗口子控件，验证目标控件
   存在性、Text、Enabled 状态
   → 结构检查，不受视觉变化影响

3. VerifyRegionNonEmpty（只在怀疑渲染空白时做）
   截取目标区域截图，只验证 RGB 值不是全白/全黑/全透明
   → 不对比内容，只验证"画了东西" vs "什么都没画"
```

三者在第一阶段都可用，且不需要 baseline 图像维护。真正的截图对比只在以下条件触发时才引入：

```text
1. 出现纯视觉 Bug 但结构断言全部通过（控件重叠、文本截断）
2. Skia/自绘控件需要验证画布内容
3. DeepUITest 升级为 CI 级门禁，需要"肉眼可交付"级封版证据
```

---

## 3. Runner 执行流程

```text
1. 创建 RunnerBatch。
2. 为 TestCase 生成 run-id。
3. 创建工作目录：
   %TEMP%\DeepUITest\Runs\{run-id}
4. 准备 Probe 参数和 signal-file 路径。
5. 确认 DeepLaunch 已运行或启动 DeepLaunch。
6. 发送 F1。
7. 等待 DeepLaunch 主界面 / Grid 出现。
8. 发送目标键 X。
9. 等待 Probe 进程、窗口、signal.json。
10. 执行 AssertRule。
11. 写 RunnerStepResult。
12. 汇总 RunnerResult。
13. 生成 LampEvaluation。
14. 失败时生成 BugRecord / BugDiagnosis。
```

---

## 4. MVP-1 JourneyStep 草案

```text
0. PrepareTargetStateGate
   清理旧 Probe 进程，准备 signal-file 目录，避免误判。

1. DeepLaunchReadyGate
   确认 DeepLaunch 已运行或可启动。

2. MainWindowGate
   发送 F1，验证 DeepLaunch 主界面出现。

3. GridReadyGate
   验证 60 格 Grid 可见或主界面已处于可接收目标键状态。

4. HotkeyActionGate
   发送目标键 X。

5. LaunchVerifyGate
   验证目标程序进程 / 窗口 / signal 文件出现。

6. TargetIdentityGate
   验证 signal.json 中 runId / caseId 与当前测试匹配。
```

---

## 5. DeepUITestProbe.exe 定位

DeepUITestProbe.exe 是深测内置测试靶子程序。

用途：

```text
验证 DeepLaunch / 启动器 / 工作流 / 快捷键是否真的启动了指定程序。
```

不优先使用 notepad.exe / calc.exe 的原因：

```text
1. 目标程序可能已经在运行。
2. 目标程序可能单实例。
3. 窗口标题不稳定。
4. 启动速度不稳定。
5. 程序可能弹更新框。
6. 断言容易误判。
```

Probe 的价值：

```text
启动后留下可验证证据。
```

---

## 6. Probe 必须能力

```text
1. 接收 case-id。
2. 接收 run-id。
3. 接收 signal-file 路径。
4. 启动后显示固定窗口。
5. 启动后写入 signal.json。
6. 保持运行一段时间。
7. 支持 Runner 根据进程、窗口、signal 文件进行强断言。
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

可选扩展：

```text
--delay-ms=1000
--no-signal
--wrong-run-id
--wrong-case-id
--exit-code=1
--fmx-probe-port=8089     // FMX: 指定 FmxProbe HTTP 端口（Runner 用于 /tree /tap /state）
```

扩展用途：

```text
模拟启动慢、未写 signal、runId 错误、caseId 错误、异常退出等失败场景。
--fmx-probe-port 为 FMX 目标程序提供控件定位通道，见 DeepUITest.017-FMX探针策略.md。
```

---

## 7. signal.json 格式

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

---

## 8. Runner 断言

强断言：

```text
1. 进程 DeepUITestProbe.exe 存在。
2. 窗口标题包含 run-id。
3. signal.json 存在。
4. signal.json 中 runId = 当前 Runner runId。
5. signal.json 中 caseId = 当前 TestCaseId / CaseKey。
```

弱断言：

```text
1. 只看到进程。
2. 只看到窗口。
3. signal.json 存在但内容不完整。
```

红灯断言：

```text
1. signal.json runId 不匹配。
2. signal.json caseId 不匹配。
3. 启动了错误程序。
4. 等待超时后仍无进程、窗口和 signal。
```

---

## 9. Runner 输出

每次执行必须输出：

```text
RunnerBatch
RunnerResult
RunnerStepResult[]
LampEvaluation
日志文件
截图
必要时 BugRecord / BugDiagnosis
```

Runner 不直接修改测试配置。配置修正由 Designer 或人工审核流程完成。

