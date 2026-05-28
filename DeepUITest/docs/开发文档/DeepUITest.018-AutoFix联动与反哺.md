# DeepUITest.018 - AutoFix 联动与反哺

> 状态：开发文档初版
> 用途：定义 DeepUITest 与 AutoFix 的协同关系，设计串联闭环和共享基础设施

---

## 1. 能力互补

DeepUITest 和 AutoFix 是同一个质量治理体系的阴阳两面：

| 维度 | AutoFix | DeepUITest |
|------|---------|------------|
| 检测对象 | 运行时崩溃（Exception 类） | 行为退化（Assertion 失败） |
| 触发方式 | 程序自身捕获异常 | Runner 主动回放行为链 |
| 证据格式 | `runtime-errors.jsonl` | `RunnerStepResult` + `LampEvaluation` |
| 修复途径 | AI 改源码 → 编译 → 重跑 | 人审诊断卡 → 修正配置或代码 |
| 操作粒度 | 源码行级（RVA → 源文件:行号） | 行为链步骤级（Gate / Step / Action） |
| 隔离策略 | git worktree | `%TEMP%\DeepUITest\Runs\{run-id}` |
| 运行模式 | EXE 内嵌 + PowerShell 编排 | Runner Console + Designer GUI |
| 封版标准 | 场景全部 pass + 零运行时错误 | 全部绿灯 + 关键门禁通过 |

---

## 2. 串联闭环

两条系统可以串联为一个完整的"发现 → 修复 → 验证"自动化流水线：

```text
DeepUITest Runner 回放
  → 断言失败 → 红灯 + BugRecord
  → 触发 AutoFix：解析 .map → RVA 定位源码
  → AI 修改 worktree 内源码
  → 编译 → 目标 EXE 重新运行
  → DeepUITest Runner 重新回放
  → 绿灯 → 封版
```

这不是 AI 代替人做测试设计，而是 AI 在人类定义的断言上做修复，在人类定义的测试链上做验证。

---

## 3. 共享基础设施

两个系统共享以下 DeepBase 基础设施：

### 3.1 信号文件格式

AutoFix 的 `HealthSignal` 和 DeepUITest 的 Probe `signal.json` 使用同构格式：

```json
{
  "run_id": "uuid",
  "case_id": "test-case-key",
  "pid": 12345,
  "status": "started",
  "started_at": "iso-8601"
}
```

Runner 可以统一使用相同的 `VerifyFile` 动作验证 AutoFix 的 health-signal.json 和 DeepUITest 的 signal.json。

### 3.2 去重键

```text
AutoFix dedup_key:  ExceptionClass|Module:RVA|Scenario
DeepUITest dedup:   BugRecord.BugType + TestCaseId + StepKey
```

两者可以统一为 OCGS 级别的去重键：`OutputKey|GateKey|FailureClass|Locator`。当两条系统积累足够多的 BugRecord 后，去重键可以跨系统复用——AI 修复同一个 dedup_key 的 Bug 时，可以直接从缓存取成功的 diff。

### 3.3 boundary.json

AutoFix 的 `boundary.json`（限制 AI 只能改哪些源码目录）对 DeepUITest 也有用：
- Runner 执行测试时，可以用 `boundary.json` 里的 `allowed_paths` 决定哪些文件的变更触发回归测试
- AI 配置生成器读取 `allowed_paths` 避免生成对不可修改文件的断言

### 3.4 DeepBase DB1/DB2

```text
DB1 (config.db): 两个系统共享
  - AutoFix: autofix-output 目录路径
  - DeepUITest: 被测程序路径、Runner 工作目录、API 端点

DB2 (business SQLite):
  - AutoFix: 不直接写入 DB2
  - DeepUITest: 核心 10-16 张业务表
```

---

## 4. 反哺关系

### AutoFix → DeepUITest

```text
1. 历史 crash 热点 → 生成 DeepUITest 测试链候选
   例如：某 Gate 的 EAccessViolation 出现过 3 次
         → 建议在该 Gate 后加 VerifyProcess 断言

2. dedup_key 与 BugRecord 的映射
   同一个 Bug 在 AutoFix 被修过 → DeepUITest 知道它是曾经的高风险点
   → 灯色评估时提升该 Gate 的 Weight
```

### DeepUITest → AutoFix

```text
1. 红灯 + BugRecord → 直接作为 AutoFix 的输入
   BugRecord.RootCausePoint 指向的源文件和 Gate
   → AutoFix 的 map-resolver 可以直接定位

2. 回归测试绿��� → 确认 AutoFix 的修复有效
   避免 "修了 crash 但引入了新行为 bug"

3. 测试配置覆盖率 → AutoFix 的修复边界
   哪些路径有 DeepUITest 覆盖 → AutoFix 可以放心自动 merge
   哪些路径没有 → AutoFix 只输出修复分支，不自动 merge
```

---

## 5. 共享对象映射

| DeepUITest 对象 | AutoFix 对应 | 说明 |
|----------------|-------------|------|
| TestCase.OutputKey | Scenario 名 | 顶层的"要验证什么能力" |
| JourneyStep.GateKey | dedup_key 的 scenario 段 | 步骤级别的失败定位 |
| AssertRule.AssertType | runtime-errors.jsonl 的 level | fatal / error / warning |
| BugRecord.BugType | Exception.ClassName | 失败归类 |
| BugRecord.RootCausePoint | Module:RVA | 源码级定位 |
| LampEvaluation.LampState | exit_code | 最终判决（0=绿, 1=黄, 2=红） |
| HumanDecisionLog | AutoFix 尚未对应 | 人工决策留痕 |

---

## 6. 第一阶段不联动

MVP-1 不做 AutoFix 联动。原因是：

```text
1. DeepUITest 自己的 Runner 闭环还没跑通
2. AutoFix 的边界检查和编译循环需要 worktree，DeepUITest 的结果格式还不稳定
3. 人先跑通一条手工测试链，再看哪些步骤应该自动化
```

当以下条件满足时再启动联动：

```text
1. Runner 能稳定执行 DeepLaunch 三条命脉链
2. LampEvaluation 和 BugRecord 格式稳定
3. AutoFix 的 autofix.ps1 主循环能接受外部输入（不仅限于 runtime-errors.jsonl）
4. DeepUITest BugRecord 的 RootCausePoint 字段能提供 Module:RVA
```

---

*文档版本：v1.0 · 2026-05-27*
