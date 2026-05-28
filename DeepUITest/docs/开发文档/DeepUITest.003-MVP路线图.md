# DeepUITest.003 - MVP 路线图

> 状态：开发文档初版
> 用途：把讨论稿中的 MVP 阶段整理成开发可执行路线

---

## 1. MVP 总原则

第一版不是万能测试平台，而是一个能跑通闭环的 Windows 桌面程序 UI 行为测试台。

MVP 目标：

```text
一个软件
一个测试目标
一条行为链
一次 Runner 回放
一次红绿灯
一次失败诊断
一次 Bug 入库
一次可追溯 HumanDecisionLog
```

第一阶段成功标准：

```text
DeepLaunch 的已配置启动链可被 Runner 自动回放；
目标程序使用 DeepUITestProbe.exe；
Runner 能写结果、出灯色、失败时生成诊断卡和 BugRecord。
```

---

## 2. 阶段划分

### MVP-0：数据库与双端骨架

目标：

```text
Designer 与 Runner 能连接同一个数据库。
```

验收：

```text
1. Designer 能新建 AppProject。
2. Runner 能读取 AppProject。
3. 能写 HumanDecisionLog。
4. 核心对象具备 ID、VersionNo、IsSealed。
5. 能手工录入一个 TestCase / JourneyStep / AssertRule。
```

不做：

```text
AI 生成
复杂 UI
批量执行
BugPattern
完整报表
```

---

### MVP-1：DeepLaunch 已配置启动测试

目标：

```text
验证已配置好的 DeepLaunch 格子，是否能通过 F1 + X 启动目标程序。
```

测试链：

```text
准备 Probe
  -> 确认 DeepLaunch 可响应
  -> 发送 F1
  -> 等待主界面 / Grid
  -> 发送 X
  -> 验证 DeepUITestProbe.exe 启动
  -> 验证 signal.json
  -> 写 Runner 结果
```

最小验收：

```text
1. Runner 能自动执行 F1 + X。
2. Runner 能验证 DeepUITestProbe.exe 进程。
3. Runner 能验证 Probe 窗口标题包含 run-id。
4. Runner 能验证 signal.json 存在。
5. Runner 能验证 signal.json 的 runId / caseId。
6. 通过时生成 Green。
7. 失败时生成 Red 或 Yellow，并生成诊断卡。
8. 失败写入 BugRecord。
```

---

### MVP-2：DeepLaunch 配置生效测试

目标：

```text
验证从绑定程序到启动程序的完整链路。
```

测试链：

```text
绑定程序
  -> 保存
  -> 断言配置写入
  -> 断言 Grid 显示更新
  -> 断言运行时映射刷新
  -> F1 + X
  -> DeepUITestProbe.exe 启动
```

战略价值：

```text
普通 UI 测试只看保存提示；
DeepUITest 要验证配置是否真的转化成用户可调用能力。
```

后置原因：

```text
它比 MVP-1 多了 UI 定位、编辑窗体、配置写入、运行时刷新等风险点，应在 Runner / Probe / 结果链稳定后推进。
```

---

### MVP-3：红绿灯与失败诊断卡增强

目标：

```text
Runner 失败后，不只显示失败，而是生成可处理的诊断卡。
```

输出：

```text
BugRecord
BugDiagnosis
BugObjectLink
HumanDecisionLog
LampEvaluation
```

验收：

```text
1. 用户能看到失败步骤、预期、实际、证据。
2. 用户能用 1-9 / 0 选择候选原因。
3. 选择写入 BugDiagnosis 和 HumanDecisionLog。
4. BugRecord 能挂到 TestCase / Step / Assert / Environment。
```

---

### MVP-4：AI 读取 VCL 代码 / 文档生成测试草稿

目标：

```text
AI 基于文档、源码、窗体结构和已有样板生成候选测试配置。
```

原则：

```text
AI 生成候选配置，不生成可信最终脚本；
必须经过红绿灯、人工审核和 Runner 回放。
```

顺序：

```text
先 VCL，后 FMX。
```

---

### MVP-5：Bug 经验反哺

目标：

```text
一次失败经验能影响下一次测试配置生成和红绿灯建议。
```

验收：

```text
历史失败
  -> 用户确认原因
  -> 系统记录 BugPatternCandidate
  -> 下次同类测试提醒补断言
  -> 用户接受后配置增强
  -> 灯色变化可追溯
```

---

### MVP-6：FMX 支持增强（FmxProbe 方案）

具体方案见 `DeepUITest.017-FMX探针策略.md`。

```text
1. 实现 DeepBase.UITest.FmxProbe 单元
2. FmxProbe.Install 集成模式（仿 AutoFix *.Install）
3. 控件树 HTTP API：GET /tree / POST /tap / GET /state
4. 配合 DeepDev / DeepSync / DeepInsight / Assayer 等 FMX 项目
5. 黄灯规则：StyleName 不稳定时赵轻易绿灯
```

原则：

```text
FMX 无稳定 StyleName / TestId 时，默认不轻易绿灯。
FMX 探针 HTTP 不可达时，Runner 报灰灯而非红灯。
```

---

### MVP-7：AutoFix 联动与回归闭环

具体方案见 `DeepUITest.018-AutoFix联动与反哺.md`。

```text
1. DeepUITest 红灯 → 触发 AutoFix 修复循环
2. AutoFix 修复完成 → DeepUITest 重跑回归
3. 绿灯 → 自动 commit 封版
4. 共享 dedup_key 与 BugRecord 映射
5. 历史 crash 热点反哺测试链生成
```

第一阶段不做。等 Runner 三条命脉链稳定后再联动。

---

## 3. 当前开发优先级

```text
P0：MVP-0 数据库与手工配置骨架
P0：DeepUITestProbe.exe
P0：Runner MVP-1
P0：MVP-1 灯色与失败诊断
P1：共享数据库字段细化
P1：Designer 最小 UI
P2：MVP-2 配置生效链
P3：VCL 代码读取
P4：AI 配置生成器
P5：FMX 增强
```

---

## 4. 第一阶段不做清单

```text
1. 不做大规模批量回归。
2. 不做完整知识图谱。
3. 不做自动修复代码。
4. 不自动提升全局 BugPattern。
5. 不做复杂拖拽。
6. 不做复杂图像识别。
7. 不做多人权限协作。
8. 不做 Web / 移动端测试。
9. 不做全控件覆盖。
10. 不做完整报表中心。
```

