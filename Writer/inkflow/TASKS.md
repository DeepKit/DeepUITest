# InkFlow — 当前任务与议题清单

Date: 2026-06-28
Status: v3.18；Schema v19；39 张业务表 + `_schema_meta` 元表；当前阶段：工程投产候选已验证；最近全量验证：`428 passed, 4 warnings`

---

## 1. 当前结论

InkFlow 的生产内核已完成本轮 P0 硬化，进入“工程投产候选”状态。第 2 章本地兜底链路和第 3 章远端 writer/jury 链路已经跑通，`init -> setup --chapter -> run --chapter -> review` 方向成立；accepted canonical 状态机已进入 DB，并影响默认导出、事实锚点和后续上下文。

当前口径：工程层可以进入单书、逐章、人工审稿后的正式生产；不承诺“无人值守批量放量”。文学质量仍以每章人工 `review --accept/--revise/--reject` 为正式门槛。本轮已完成全量回归，并对真实《分流》库完成 v19 迁移/status 健康检查。

本轮已完成 CORE-1/CORE-2/EXPORT-4/REVIEW-1/STATUS-1：

- Schema v18 新增 `writing_chapter_reviews`，记录章节人工审稿 canonical 状态。
- Schema v19 新增 `writing_shots.logical_shot_id`；生产 run 的 `shot_id` 改为 `{logical_shot_id}@{run_id}`，同一章节重写会生成新的 attempt shot，不再复用旧正文。
- `ink review --accept/--revise/--reject` 不再只写 YAML，也会写 DB；`--accept` 必须要求 completed run、无未封板 shot、L3 已通过。
- `--revise/--reject` 会把该 run 本章绿/黄 shot 退回 `redo`，避免继续被当作正式正文。
- 默认 `ink export` 只导出人工 accepted 的正式章节；`ink export --draft` 才导出未 accepted 的审稿稿。
- previous context 只读取当前 run 前序 shot 或人工 accepted 历史章节。
- fact anchors 只读取当前 run、accepted 章节或 locked baseline，避免 rejected/aborted/unaccepted run 污染后续生产。
- `ink status` 显示每章 latest run 与 canonical 审稿状态，减少误把审稿稿当正式稿的操作风险。

---

## 2. 权威文档

| 文档 | 位置 | 当前状态 |
|------|------|:---:|
| 技术设计权威 | `docs/design.md` | 已同步 v3.18 / Schema v19 / accepted canonical / run attempt identity |
| 实现契约 / DDL / 状态机 | `docs/implementation-contract-v0.md` | 已同步 Schema v19、`writing_chapter_reviews` 与 `logical_shot_id` |
| 人机流程 | `docs/flow.md` | 已明确 run 审稿导出 vs accepted 正式导出，以及每章 setup/run/review |
| 三棵树与正文真相源 | `docs/design-3tree-architecture.md` | 已标注 accepted canonical 与 run attempt identity 已落地 |
| 悬疑引擎 | `docs/suspense-engine.md` | 已实施核心闭环，待更多真实章节验证 |
| 开发历史 | `docs/history.md` | 本轮追加 CORE-1-V18 与 CORE-2-V19 |
| Bug 记录 | `docs/bugfix.md` | 本轮追加 B61/B62 |

---

## 3. 已完成任务归档

详细实现记录见 `docs/history.md`。

| 阶段 | 已完成 |
|------|--------|
| P0 纵向闭环 | 导入第 1 章、确认契约、逐 shot 生成第 2 章、scope report |
| 真实章节验证 | 第 2 章本地兜底链路内容基本合格；第 3 章远端 writer/jury 链路 5/5 green 并导出 |
| 工作流收敛 | `init -> setup --chapter -> run --chapter -> review` |
| JURY-V5 | 硬规则 → 类型职责 → 文学 9 维；至少 2 个过线稿；单线返写 |
| 章节契约准入 | B52：旧章节限定、旧段落锁、过期 setup 包、setup/contract shot 数不一致提前失败 |
| 远端评审归因 | B53/B54：gate 淘汰不再显示均分 0；timeout/解析失败不混入文学分；全维度不可评为 `jury_unavailable` |
| PROD-HARDEN-1 | persona prompt、creative_score winner、L4/L3 硬停、当前 run 导出过滤、retry 熔断 |
| CORE-1/CORE-2/EXPORT-4/REVIEW-1/STATUS-1 | `writing_chapter_reviews`、accepted-only 默认导出、review DB 状态机、previous context / fact anchors canonical 过滤、run attempt shot identity、status canonical 可视化 |

---

## 4. 当前 P0 状态

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P0 | PROD-VERIFY-1 | 全量回归 | 已完成 | `python -m pytest -q`：428 passed, 4 warnings |
| P0 | MIGRATE-1 | 既有真实库 Schema v19 升级验证 | 已完成 | 已备份 `D:\_Progs\.Story\《分流》\.inkflow\inkflow.db.bak-v19-20260628`；`ink status "分流"` 通过；真实库 `_schema_meta.version=19`，`logical_shot_id` 无空值 |
| P0 | PROD-READY-1 | 投产状态结论 | 已完成 | 工程层可逐章投产；每章仍需人工审稿 accepted |

---

## 5. 当前 P1 待办

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P1 | CHAPTER-3-REVIEW | 第 3 章人工审阅 | 待人工 | 审阅 `D:\_Progs\.Story\《分流》\正文\分流_v01.c03_导出.md`，用 `ink review "分流" --chapter v01.c03 --accept/--revise/--reject` 记录结论 |
| P1 | CHAPTER-4-SETUP | 第 4 章生产前校准 | 待第 3 章审阅后执行 | 先吸收第 3 章审阅结论，再 `ink setup "分流" --chapter v01.c04 --force` |
| P1 | JURY-V5-REAL | 分层裁判真实项目持续观测 | 已有第 3 章样本 | 每章记录硬规则失败数、类型 gate 触发数、文学 9 维分布、过线稿数量和单线返写次数 |
| P1 | CREATIVE-3-EVAL | 留白创意评审效果评估 | 已修正 score_key | 比较标准 winner 与 creative winner 的高光率、合规风险和人工偏好 |
| P1 | STYLE-1 | 议论性/系统解释文本抑制评估 | L4 已硬化 | 统计 narrator intrusion、system voice、explanation 触发率，验证不再出现大段机制议论 |

---

## 6. 当前验证命令

```powershell
cd D:\_Progs\02Business\Writer\inkflow
python -m py_compile src\inkflow\cli.py src\inkflow\db\migration.py src\inkflow\export\exporter.py src\inkflow\services\fact_anchor_extractor.py
python -m pytest tests\test_shot_id.py tests\test_session_manager.py tests\test_baseline_importer.py tests\test_schema.py tests\test_migration.py tests\test_cli.py tests\test_cli_happy_path.py -q
python -m pytest -q
python -m inkflow.cli status "分流"
```
