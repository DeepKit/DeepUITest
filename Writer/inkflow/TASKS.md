# InkFlow — 当前任务与议题清单

Date: 2026-06-24
Status: v3.12；Schema v9；35 张业务表；最近全量验证：`309 passed, 4 warnings`

---

## 1. 当前结论

P0 单书纵向闭环已经完成：`import-baseline -> setup -> confirm-contract -> run -> scope report` 可跑通。L0 全书宪法（ARCH-4）、L1 章级节奏（ARCH-6）、三棵树架构（ARCH-12）和正文真相源锚定（ARCH-13）已经实现并归档到 `docs/history.md`。

当前任务不再是修 P0 阻塞项，而是补齐分层治理链中仍缺的 L0.5 卷部节奏、剩余 CLI/runtime 集成、D-25 悬疑引擎可靠性闭环，以及后续学习机制。

设计审阅结论：当前方向是 near-optimal，不建议推倒重做。需要收紧的点是“不要继续堆检查项”，而要把 L0/L0.5/L1 的自由度预算真实传递到写手和 gate。

---

## 2. 权威文档

| 文档 | 位置 | 状态 |
|------|------|:---:|
| 技术设计权威 | `docs/design.md` | ✅ v3.12 / Schema v9 |
| 实现契约 / DDL / 状态机 | `docs/implementation-contract-v0.md` | ✅ Schema v9 |
| 三棵树与正文真相源 | `docs/design-3tree-architecture.md` | ✅ |
| 8 层层级 | `docs/design-8layer-hierarchy.md` | ✅ |
| 悬疑引擎 | `docs/suspense-engine.md` | ✅ 部分实施，剩余项在待办 |
| 开发历史 | `docs/history.md` | ✅ |
| Bug 记录 | `docs/bugfix.md` | 本轮新增 B35/B36 |

---

## 3. 已完成任务归档

已完成项不再放在待办区，详细实现记录见 `docs/history.md`。

| 阶段 | 已完成 |
|------|--------|
| P0 纵向闭环 | 导入第 1 章、确认契约、逐 shot 生成第 2 章、scope report |
| 数据/LLM/CLI 修复 | DB-1~7、LLM-1~6、CLI-1~5、DOC-1~4 |
| 管线质量优化 | OPT-1~7 |
| AI 架构师治理 | ARCH-1/2/3/4/6/8/9/12/13 |
| D-25 悬疑引擎 | Jury 第四维度、悬疑蓝图注入、信息差表与服务、悬疑预设已落地；可靠性与 benchmark 未完成 |

---

## 4. 到 optimal 的差距清单

| 优先级 | 优化点 | 现状 | 对应任务 |
|--------|--------|------|----------|
| 最高 | L0.5 Volume Rhythm | L0 全书宪法到 L1 章级节奏之间缺少卷部战术层，长卷会让 L1 过度局部化 | ARCH-5 |
| 最高 | Runtime 约束传递 | `ink constitution` 已有，但 run 还没有完整消费 L0/L0.5 的 chapter role、tension、deviation range | ARCH-7R |
| 最高 | D-25 可靠性闭环 | 悬疑维度、信息差和预设已落地，但缺全局重试预算、`failure_signature`、同类失败熔断 | D25-R1 |
| 中 | Prompt caching 实做 | 当前只有 warning/cacheable 标志，长契约项目还没有拆段缓存和摘要降级 | B23-P1 |
| 中 | 悬疑 benchmark | `suspense_effectiveness` 缺人工标注样本验证，尚不能证明评分和读者悬疑感相关 | D25-R2 |
| 中 | 正文真相源读取审计 | `shot_revisions.text` 已是唯一真相源，但还需要系统审计所有 current text 读取路径是否遵守未封版/封版规则 | TS-1 |
| 后续 | 风格偏好学习 | jury winner 尚未回流 persona/model/temperature/style_direction 到后续 shot | ARCH-10 |
| 后续 | 反契约沙盒 | 软约束偏离的“意外价值”还没有进入赛马与人类裁决闭环 | ARCH-11 |

---

## 5. 当前待办

### P0 / 下一编码优先级

| ID | 任务 | 说明 | 涉及文件 |
|----|------|------|----------|
| ARCH-5 | L0.5 Volume Rhythm 服务 | 读取 L0 宪法和卷内章 events，产出卷内 mini-arc、章角色、张力预算、deviation range。编码前先做存储决策：优先复用三棵树 `contract_versions` 的 L2 volume 节点；只有查询/迁移收益明确时才新增 `writing_volume_rhythms`。 | `services/volume_rhythm.py`, `db/schema.sql`, `db/migration.py`, tests |
| ARCH-7R | CLI/runtime 剩余集成 | L0 `ink constitution` 已实现；剩余是 L0.5 命令、run 前置检查、L0.5 -> L1 `ChapterRhythmService` 的约束传递。 | `cli.py`, `services/chapter_rhythm.py` |
| D25-R1 | 悬疑引擎可靠性闭环 | 实现全局重试预算、`failure_signature`、同类失败 3 次熔断，避免无限 redo 或局部策略打架。 | `quality_controller.py`, `cli.py`, tests |
| TS-1 | 正文真相源读取审计 | 审计所有正文读取路径：未封版必须读 `MAX(revision_sequence)`，封版后读 `is_current=1`；补 repository/helper 避免散落 SQL。 | `session_manager.py`, `cli.py`, services, tests |

### P1

| ID | 任务 | 说明 | 涉及文件 |
|----|------|------|----------|
| B23-P1 | Prompt caching 拆段/摘要降级 | 当前只记录 warning/cacheable；需要实现超限拆段、摘要降级和测试。 | `prompt_compiler.py`, tests |
| D25-R2 | 悬疑 benchmark | 增加高/低/伪悬疑标注样本，验证 `suspense_effectiveness` 与人工判断相关。 | `tests/fixtures/suspense_benchmark/`, tests |

### P2

| ID | 任务 | 说明 | 涉及文件 |
|----|------|------|----------|
| ARCH-10 | 风格偏好学习 | jury 选出 winner 后记录 persona/model/temperature/style_direction，反馈 L0.5/L1 后续预算。 | `jury_service.py`, `prompt_compiler.py`, schema |
| ARCH-11 | 反契约沙盒 | 允许 1 路赛马故意偏离软约束，用“意外价值”评估；明显更好时触发人类裁决。 | `writer_dispatcher.py`, `architect_gate.py` |

---

## 6. 非阻塞议题

| ID | 议题 |
|----|------|
| X-11 | Voice Calibration 样本要求 |
| X-12 | 契约升级三级填充 |
| X-13 | 多 Project 事实锚点同步 |
| X-14 | Prompt Caching 实战验证 |
| X-15 | 反例降温机制参数 |
| X-16 | Voice Drift 告警阈值 |
| X-17 | 导入已有作品章节识别 |

---

## 7. 当前验证命令

```powershell
cd D:\_Progs\02Business\Writer\inkflow
python -m pytest -q
```
