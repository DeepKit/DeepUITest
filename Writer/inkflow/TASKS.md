# InkFlow — 当前任务与议题清单

Date: 2026-06-28
Status: v3.17；Schema v18；39 张业务表 + `_schema_meta` 元表；当前阶段：生产内核硬化中；最近全量验证：`414 passed, 4 warnings`

---

## 1. 当前结论

InkFlow 仍不能按“已经正式投产”判断。第 2 章本地兜底链路和第 3 章远端 writer/jury 链路已经跑通，`init -> setup --chapter -> run --chapter -> review` 方向成立；本轮又补齐了 accepted canonical 状态机，使人工审稿结果进入 DB 并影响默认导出、事实锚点和后续上下文。

当前状态是“受控试跑”，不是批量无人值守生产。主要剩余风险是同一章节重写时 `shot_id` 仍是稳定逻辑 ID，run attempt 身份还没有完全拆开；该问题需要单独 schema/迁移级改造，不能混在小步修复里。

本轮已完成 CORE-1/EXPORT-4/REVIEW-1：

- Schema v18 新增 `writing_chapter_reviews`，记录章节人工审稿 canonical 状态。
- `ink review --accept/--revise/--reject` 不再只写 YAML，也会写 DB；`--accept` 必须要求 completed run、无未封板 shot、L3 已通过。
- `--revise/--reject` 会把该 run 本章绿/黄 shot 退回 `redo`，避免继续被当作正式正文。
- 默认 `ink export` 只导出人工 accepted 的正式章节；`ink export --draft` 才导出未 accepted 的审稿稿。
- previous context 只读取当前 run 前序 shot 或人工 accepted 历史章节。
- fact anchors 只读取当前 run、accepted 章节或 locked baseline，避免 rejected/aborted/unaccepted run 污染后续生产。

---

## 2. 权威文档

| 文档 | 位置 | 当前状态 |
|------|------|:---:|
| 技术设计权威 | `docs/design.md` | 已同步 v3.17 / Schema v18 / accepted canonical |
| 实现契约 / DDL / 状态机 | `docs/implementation-contract-v0.md` | 已同步 Schema v18 与 `writing_chapter_reviews` |
| 人机流程 | `docs/flow.md` | 已明确 run 审稿导出 vs accepted 正式导出 |
| 三棵树与正文真相源 | `docs/design-3tree-architecture.md` | 已标注 accepted canonical 已落地，CORE-2 未落地 |
| 悬疑引擎 | `docs/suspense-engine.md` | 已实施核心闭环，待更多真实章节验证 |
| 开发历史 | `docs/history.md` | 本轮追加 CORE-1 canonical 状态机 |
| Bug 记录 | `docs/bugfix.md` | 本轮追加 B61 |

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
| CORE-1/EXPORT-4/REVIEW-1 | `writing_chapter_reviews`、accepted-only 默认导出、review DB 状态机、previous context / fact anchors canonical 过滤 |

---

## 4. 当前 P0 待办

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P0 | CORE-2 | run/shot identity 重构 | 待开发 | 同一章节多次重写不能复用旧 `shot_id` 跳过旧正文；需要区分 logical shot 与 run attempt shot |
| P0 | VALID-1 | accepted canonical 真实小样验证 | 单元/集成回归已通过，待真实运行 | 用当前代码跑一个小章节/单 shot 远端 writer+jury，人工 `review --accept` 后验证默认 `ink export` 只出 accepted 正文 |
| P0 | MIGRATE-1 | 既有真实库 Schema v18 升级验证 | 待执行 | 对《分流》现有 `.inkflow/inkflow.db` 执行迁移/健康检查，不破坏已有章节 run 与审稿导出 |
| P0 | STATUS-1 | canonical 状态可视化 | 待开发 | `ink status` 能显示各章 latest run 与 accepted/rejected/needs_revision 状态，减少误操作 |

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
python -m pytest tests\test_schema.py tests\test_migration.py tests\test_cli.py tests\test_fact_anchor.py -q
python -m pytest -q
```
