# InkFlow — 当前任务与议题清单

Date: 2026-06-26
Status: v3.14；Schema v16；38 张业务表 + `_schema_meta` 元表；最近全量验证：`379 passed, 4 warnings`

---

## 1. 当前结论

P0 单书纵向闭环已经完成：`import-baseline -> setup -> confirm-contract -> constitution -> run -> scope report` 可跑通。L0 全书宪法、L0.5 卷部节奏、L1 章级节奏、三棵树架构、正文真相源、D-25 悬疑可靠性、风格偏好学习、反契约沙盒、CREATIVE-1 意外价值维度、CREATIVE-2 二次精修和 CREATIVE-3 留白创意评审均已落地。

2026-06-26 的 QUAL-1/VAL-2 修复结果：第 2 章重写链路已用真实《分流》库复跑通过（`ink run "分流" --chapter v01.c02 --resume --local-jury`），4 个 shot 结果为 Green 2 / Yellow 2 / Red 0，L3 章末钩子已触发并通过。根因是本地 jury 在存在 providers 时仍误走远端评分路径，以及 `LocalDefaultGenerator` 未按 prompt 的 opening/POV/must_land 生成正文。

当前结论：工程链路已达到“受控生产试跑”标准；本地兜底可用于验证 gate、恢复和归因。正式批量生产仍需要远端 writer/jury 可用性验证与人工审稿确认，本地兜底文本不能作为最终文学质量基线。

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
| 开发历史 | `docs/history.md` | ✅ 本轮新增 2026-06-26 归档 |
| Bug 记录 | `docs/bugfix.md` | ✅ 本轮新增 B43/B44/B45/B46/B47/B48 |

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
| 文档与测试对齐 | B37/B38/B39/B40/B41/B42：Schema v16 / 表数 / 索引 / CREATIVE 测试、配置兼容、模型审计、后续章节契约抽取与权威契约口径同步 |
| VAL-1 工程补齐 | B43/B44/B45/B46：L3 章末钩子硬 gate、session 恢复/失败归因、章节重写入口、模型错误审计与本地 jury 运行开关 |
| QUAL-1 / VAL-2 修复 | B47/B48：本地 jury 路由修复、本地写手按 opening/POV/must_land 生成；真实《分流》v01.c02 复跑 Green 2 / Yellow 2 / Red 0，L3 通过 |

---

## 4. 当前待办

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| 高 | REMOTE-PROD | 远端 writer/jury 生产验证 | 待执行 | 使用真实供应商模型跑通 v01.c02 单章，确认无订阅/超时会被审计并快速失败，远端输出不低于本地兜底 gate 结果 |
| 高 | CHAPTER-2-REVIEW | 第 2 章人工审稿定稿 | 待执行 | 人工审读本轮 Green/Yellow 稿件，记录是否可作为第二章重写基线；不合格则走有目标的 rewrite，而不是继续堆 gate |
| 中 | JURY-REMOTE | 远端 Jury 配置治理 | 待执行 | 明确 `.models` 中远端 jury 可用性；无有效订阅时不应阻塞生产链路 |
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
