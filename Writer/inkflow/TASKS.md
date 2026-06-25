# InkFlow — 当前任务与议题清单

Date: 2026-06-25
Status: v3.12；Schema v16；38 张业务表 + `_schema_meta` 元表；最近全量验证：`361 passed, 4 warnings`

---

## 1. 当前结论

P0 单书纵向闭环已经完成：`import-baseline -> setup -> confirm-contract -> constitution -> run -> scope report` 可跑通。L0 全书宪法、L0.5 卷部节奏、L1 章级节奏、三棵树架构、正文真相源、D-25 悬疑可靠性、风格偏好学习、反契约沙盒、CREATIVE-1 意外价值维度、CREATIVE-2 二次精修和 CREATIVE-3 留白创意评审均已落地。

当前任务不再是补 P0 阻塞项，而是进入真实项目验证与效果评估阶段：用真实《分流》项目跑完整流程，收集 prompt caching / polish / 留白创意评审 / 风格学习的实际收益。

设计审阅结论不变：当前方向 near-optimal，不建议推倒重做。下一步应避免继续堆检查项，重点把“约束保下限 + 留白出上限 + 评审学偏好”跑成可验证闭环。

---

## 2. 权威文档

| 文档 | 位置 | 状态 |
|------|------|:---:|
| 技术设计权威 | `docs/design.md` | ✅ v3.12 / Schema v16 |
| 实现契约 / DDL / 状态机 | `docs/implementation-contract-v0.md` | ✅ Schema v16 / 38 业务表 |
| 三棵树与正文真相源 | `docs/design-3tree-architecture.md` | ✅ |
| 8 层层级 | `docs/design-8layer-hierarchy.md` | ✅ |
| 悬疑引擎 | `docs/suspense-engine.md` | ✅ 已实施核心闭环，待实战验证 |
| 开发历史 | `docs/history.md` | ✅ 本轮新增 2026-06-25 归档 |
| Bug 记录 | `docs/bugfix.md` | ✅ 本轮新增 B37/B38/B39/B40/B41 |

---

## 3. 已完成任务归档

已完成项不再放在待办区，详细实现记录见 `docs/history.md`。

| 阶段 | 已完成 |
|------|--------|
| P0 纵向闭环 | 导入第 1 章、确认契约、逐 shot 生成第 2 章、scope report |
| 数据/LLM/CLI 修复 | DB-1~7、LLM-1~6、CLI-1~5、DOC-1~4 |
| 管线质量优化 | OPT-1~7 |
| AI 架构师治理 | ARCH-1/2/3/4/5/6/7R/8/9/10/11/12/13 |
| D-25 悬疑引擎 | Jury 悬疑维度、悬疑蓝图、信息差表与服务、重试预算/熔断、benchmark 样本 |
| 正文读取治理 | TS-1 `TextRepository` 统一正文读取入口 |
| Prompt caching | B23-P1 上下文降级与 token budget 裁剪 |
| 创作质量 | CREATIVE-1 `unexpected_value`；CREATIVE-2 `write_polish`；CREATIVE-3 留白创意评审 |
| 文档与测试对齐 | B37/B38/B39/B40/B41：Schema v16 / 表数 / 索引 / CREATIVE 测试、配置兼容、模型审计与权威契约口径同步 |

---

## 4. 当前待办

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| 高 | VAL-1 | 真实项目实战验证 | 待执行 | 用真实《分流》项目跑完 `ink run` 全流程，记录绿/黄/红、重试预算、prompt token、文本质量问题 |
| 中 | CREATIVE-2-EVAL | polish 效果评估 | 已有保守精修链路，待真实文本验证 | 统计 polish 应用率、段落重排率、失败率，确认没有改变硬事实 |
| 中 | CREATIVE-3-EVAL | 留白创意评审效果评估 | 已有 `creative_review=True` 评分路径，待真实文本验证 | 比较标准 winner 与 creative winner 的高光率、合规风险和人工偏好 |
| 中 | PERF-1 | Prompt caching 性能基线 | 待测量 | 在真实 prompt 上记录 B23-P1 降级前后 token 节省量与 cacheable 比例 |
| 中 | ARCH-10-EVAL | 风格偏好反馈效果评估 | 待样本积累 | 验证 `get_effective_temperature()` 是否提高 winner 稳定性或降低红灯率 |
| 中 | TS-2 | 正文读取调用点审计 | 待复核 | 新增代码不得绕过 `TextRepository` 读取正文真相源 |
| 低 | X-17 | 已有作品章节识别 | 非阻塞 | 导入已有作品时自动识别章/节边界并给出人工确认界面 |

---

## 5. 创作质量方法论

| 问题 | 已落地 | 剩余任务 |
|------|--------|----------|
| Jury 偏重合规 | CREATIVE-3 已对留白 shot 使用独立创意评审，提高 `unexpected_value` 权重 | 评估真实文本中创意 winner 是否更受人类偏好 |
| 重写是修复不是升华 | CREATIVE-2 已新增 polish：基于 winner 写 `write_polish` 子 revision | 评估 polish 对真实文本质量的收益 |
| deviation_budget 被层层压缩 | L0.5 -> L1 -> L2 已传递；每 5 shot 留白一次 | 评估真实文本中留白 shot 是否提高高光率 |
| 四轨赛马选“最安全” | CREATIVE-3 已在留白 shot 降低常规合规权重并改用创意评审 | 跟踪合规风险，不让硬事实被破坏 |

**留白节奏：每 5 个 shot 留白 1 次。**

- 留白 shot 的 `deviation_budget = 常规 × 2`。
- 留白 shot 的 temperature 上限放宽到 `1.4`。
- 硬事实仍强制；软约束是建议，不是命令。
- 下一步重点不是继续放宽，而是评估留白 shot 是否真的产出更好的文本。

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
