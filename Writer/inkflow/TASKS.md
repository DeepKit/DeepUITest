# InkFlow — 当前任务与议题清单

Date: 2026-06-29
Status: v3.21 半重构落地中；Schema v21；45 张业务表 + `_schema_meta` 元表；当前阶段：全程审计底座与 contract-first 第一版已落地，仍需真实章节返工验证；最近相关验证为 `449 passed, 4 warnings`

---

## 1. 当前结论

InkFlow 的工程内核已完成 accepted canonical、run attempt identity、accepted-only export 和 book_run 编排层。第 2 章本地兜底链路和第 3 章远端 writer/jury 链路证明 `init -> setup --chapter -> run --chapter -> review` 方向成立；但人工审稿和后续复盘证明：旧管线的大纲门禁没有真正阻止契约违规，赛马评估曾把文学上较顺的违约稿选为 winner。

当前口径：**暂不进入正式放量生产**。工程层可继续做受控试跑和小批量验证；正式投产前必须补上“契约优先 / 资格先于 PK”的管线不变量。文学质量仍以每章人工 `review --accept/--revise/--reject` 为正式门槛。第 3 章远端链路虽跑通，但人工审稿发现标题边界、旧称、未授权事实扩写和短 hook 问题，该稿不能 accept，必须按新 gate 返工。

重构策略已经确定为**半重构**：保留现有 DB、Session、Contract、Prompt、Writer、Jury、Gate、Export 服务边界，新增统一审计层与资格记录，不推倒重来。完全重构会丢失已积累的真实库数据和已验证的 accepted canonical / book_run / model_attempts 基础能力；继续打零散补丁又无法保证质量追因。因此 v21 先把全程记录补成横切基础设施，再逐步收紧大纲硬门禁、task card 和草稿资格门禁。

本轮已完成 CORE-1/CORE-2/EXPORT-4/REVIEW-1/STATUS-1/BOOKRUN-1：

- Schema v18 新增 `writing_chapter_reviews`，记录章节人工审稿 canonical 状态。
- Schema v19 新增 `writing_shots.logical_shot_id`；生产 run 的 `shot_id` 改为 `{logical_shot_id}@{run_id}`，同一章节重写会生成新的 attempt shot，不再复用旧正文。
- Schema v20 新增 `writing_book_runs` / `writing_book_run_chapters`，记录一次全书/整卷批处理及逐章状态。
- `ink review --accept/--revise/--reject` 不再只写 YAML，也会写 DB；`--accept` 必须要求 completed run、无未封板 shot、L3 已通过。
- `--revise/--reject` 会把该 run 本章绿/黄 shot 退回 `redo`，避免继续被当作正式正文。
- 默认 `ink export` 只导出人工 accepted 的正式章节；`ink export --draft` 才导出未 accepted 的审稿稿。
- previous context 只读取当前 run 前序 shot 或人工 accepted 历史章节。
- fact anchors 只读取当前 run、accepted 章节或 locked baseline，避免 rejected/aborted/unaccepted run 污染后续生产。
- `ink status` 显示每章 latest run 与 canonical 审稿状态，减少误把审稿稿当正式稿的操作风险。
- 同一 `book_run` 中已完成的前序草稿章节可作为后续章节的临时 draft 上下文；正式导出仍只认 accepted。
- CONTENT-GATE-1 已补强：导出标题可从完整 contract 回退；`confirm/setup/run/L4` 拦截废弃角色名；L4 拦截未经契约授权的医疗/制度事实扩写；L3 拦截有标题但篇幅过薄的独立 shot。
- DESIGN-REVIEW-20260629 已收敛：大纲和草稿必须先通过硬门槛资格检查，只有 eligible 的大纲/草稿才允许进入文学 PK；不合格稿不能靠高文笔均分晋级。
- NOVELIX-RESEARCH-1 已完成外部系统研究：Novelix 的 7 个 truth files、chapter memo、context package、rule stack、review/revise cycle、state validation 和 Studio 可视化对 InkFlow 的 contract-first 管线有直接参考价值。
- AUDIT-1 已完成 v21 全程审计底座：`writing_audit_events`、`writing_setup_snapshots`、`writing_draft_eligibility`、`writing_failure_attributions`；`model_attempts` 保存完整 prompt/response；Gate1 不再清空通过稿审计结果；prompt/context、setup、writer、outline、jury、L3/L4、review、export 均开始写审计事件；新增 `ink audit-report` 读取 run 审计链。
- CONTRACT-FIRST-1 已完成第一版：`setup --chapter` 生成 `fact_manifest`；`run` 在大纲后先跑 outline fact gate，不合格不进入正文；winning outline 生成 `shot_task_card` 并进入写手 prompt/audit；草稿在 Gate1 后、jury 前跑 hard fact gate，不合格稿写入 `writing_draft_eligibility` 与 `writing_failure_attributions`，不得进入文学 PK。
- SETUP-LINT-1 已完成第一版：`run --chapter` 在创建 session 前检查 setup 自相矛盾，拦截 must_land 命中 forbidden phrases、POV 与契约/fact_manifest 不一致、未知类型职责、章节 hook 缺失等问题；失败写入 `contract_conflict` 审计。

---

## 2. 权威文档

| 文档 | 位置 | 当前状态 |
|------|------|:---:|
| 技术设计权威 | `docs/design.md` | 已同步 v3.21 / Schema v21 / contract-first + audit 半重构 |
| 实现契约 / DDL / 状态机 | `docs/implementation-contract-v0.md` | 待完整同步 Schema v21 审计表细节 |
| 人机流程 | `docs/flow.md` | 已同步 run-book / book-report；待补 audit 查询入口 |
| 三棵树与正文真相源 | `docs/design-3tree-architecture.md` | 已标注 accepted canonical 与 run attempt identity 已落地 |
| 悬疑引擎 | `docs/suspense-engine.md` | 已实施核心闭环，待更多真实章节验证 |
| 开发历史 | `docs/history.md` | 本轮追加 DESIGN-REVIEW-20260629、NOVELIX-RESEARCH-1 |
| Bug 记录 | `docs/bugfix.md` | 本轮追加 B65-B69 |
| Novelix 研究记录 | `docs/research-novelix.md` | 新增：外部系统启发与 InkFlow 迁移建议 |

---

## 3. 已完成任务归档

详细实现记录见 `docs/history.md`。

| 阶段 | 已完成 |
|------|--------|
| P0 纵向闭环 | 导入第 1 章、确认契约、逐 shot 生成第 2 章、scope report |
| 真实章节验证 | 第 2 章本地兜底链路内容基本合格；第 3 章远端 writer/jury 链路跑通但人工审稿判定需返工 |
| 工作流收敛 | `init -> setup --chapter -> run --chapter -> review` |
| JURY-V5 | 硬规则 → 类型职责 → 文学 9 维；至少 2 个过线稿；单线返写 |
| 章节契约准入 | B52：旧章节限定、旧段落锁、过期 setup 包、setup/contract shot 数不一致提前失败 |
| 远端评审归因 | B53/B54：gate 淘汰不再显示均分 0；timeout/解析失败不混入文学分；全维度不可评为 `jury_unavailable` |
| PROD-HARDEN-1 | persona prompt、creative_score winner、L4/L3 硬停、当前 run 导出过滤、retry 熔断 |
| CORE-1/CORE-2/EXPORT-4/REVIEW-1/STATUS-1 | `writing_chapter_reviews`、accepted-only 默认导出、review DB 状态机、previous context / fact anchors canonical 过滤、run attempt shot identity、status canonical 可视化 |
| BOOKRUN-1 | `run-book` / `book-report`、book_run DB 编排表、同批次草稿上下文、status 中展示最近 book run |
| CONTENT-GATE-1 | 标题回退、角色名 canonical gate、未授权事实扩写 gate、有标题短 shot density gate |
| DESIGN-REVIEW-20260629 | 确认旧管线核心缺陷在“大纲门禁未起作用 + 赛马资格与文学评分混合”；确定 contract-first 新管线 |
| NOVELIX-RESEARCH-1 | 学习 Novelix 10 Agent、7 truth files、chapter memo、state validation、review/revise cycle 与 Studio 观测设计 |
| AUDIT-1 | Schema v21 全程审计表、模型 prompt/response 完整记录、setup/context/draft eligibility/failure attribution 审计落地 |
| CONTRACT-FIRST-1 | fact_manifest、outline fact gate、shot task card、草稿 hard fact gate 第一版落地 |
| SETUP-LINT-1 | setup 自相矛盾 linter 第一版；preflight 失败归因到 `contract_conflict` |

---

## 4. 当前 P0 状态

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P0 | PROD-VERIFY-1 | 全量回归 | 已完成 | `python -m pytest -q`：449 passed, 4 warnings |
| P0 | MIGRATE-1 | 既有真实库 Schema v21 升级验证 | 已完成 | 已备份 `D:\_Progs\.Story\《分流》\.inkflow\inkflow.db.bak-v21-audit-20260629`；`ink status "分流"` 通过；真实库 `_schema_meta.version=21` |
| P0 | BOOKRUN-VERIFY-1 | 全书编排层回归 | 已完成 | 全量 `pytest` 通过；真实库已创建 plan-only book_run `01KW6JNB3ZR52F2036YH9BDAJB`，3 个 planned chapter |
| P0 | CONTENT-GATE-1 | 第 3 章审稿缺陷硬化 | 已完成 | 标题、旧称、未授权事实扩写、短 hook 均有自动拦截；相关测试与全量回归通过 |
| P0 | AUDIT-1 | 全程审计底座 | 已完成 | Schema v21；关键阶段写 `writing_audit_events`；setup/context/model/draft eligibility/failure attribution 可查；`ink audit-report` 可汇总 run 审计链 |
| P0 | AUDIT-VERIFY-1 | 真实《分流》库 v21 迁移验证 | 待执行 | 打开真实库后 `_schema_meta.version=21`；重跑第 3 章后可查 setup、prompt、task_card、draft eligibility、failure attribution |
| P0 | PROD-READY-1 | 投产状态结论 | 重新打开 | contract-first 新管线落地并用第 3 章返工、第 4 章首跑验证后，才能改回“可投产” |
| P0 | FACT-MANIFEST-1 | 章节事实清单编译 | 已完成第一版 | `setup --chapter` 生成 `inkflow.fact_manifest.v1`，包含废弃角色名、禁词、未授权事实扩写、hook 要求和每 shot authorized corpus |
| P0 | OUTLINE-GATE-1 | 大纲硬门禁 | 已完成第一版 | `run` 在正文写作前执行 outline fact gate；空大纲、缺失契约信号、禁词/旧称/未授权扩写会硬停并写 failure attribution |
| P0 | TASK-CARD-1 | winning outline 编译任务卡 | 已完成第一版 | `shot_task_card` 进入 prompt 与 audit event；写手和门禁共享 fact manifest/outline/task card 输入 |
| P0 | DRAFT-ELIGIBILITY-1 | 草稿资格门禁 | 已完成第一版 | Gate1 后、jury 前执行 hard fact gate；失败稿写 `writing_draft_eligibility(hard_rule)` 和 failure attribution，不进入文学 PK |
| P0 | SETUP-LINT-1 | setup 自相矛盾 linter | 已完成第一版 | run preflight 创建 session 前拦截 setup 自冲突；失败写 `writing_audit_events(setup)` 与 `writing_failure_attributions(contract_conflict)` |
| P0 | FAIL-ATTR-2 | 失败归因与重试上限 | 部分完成 | 已新增 `hard_rule_violation`；setup preflight 归 `contract_conflict`，task card 缺字段归 `task_card_gap`，草稿违约归 `writer_drift`；`gate_false_positive` 仍需真实样本后细分 |

---

## 5. 当前 P1 待办

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P1 | CHAPTER-3-REWRITE | 第 3 章返工重跑 | 等 P0 gate 落地后执行 | 先 `review --reject/--revise` 记录退稿，再按 contract-first gate 重新 `setup/run` |
| P1 | CHAPTER-4-SETUP | 第 4 章生产前校准 | 待第 3 章返工后执行 | 先吸收第 3 章返工结论，再 `ink setup "分流" --chapter v01.c04 --force` |
| P1 | JURY-V5-REAL | 分层裁判真实项目持续观测 | 已有第 3 章样本 | 每章记录硬规则失败数、类型 gate 触发数、文学 9 维分布、过线稿数量和单线返写次数 |
| P1 | CREATIVE-3-EVAL | 留白创意评审效果评估 | 已修正 score_key | 比较标准 winner 与 creative winner 的高光率、合规风险和人工偏好 |
| P1 | STYLE-1 | 议论性/系统解释文本抑制评估 | L4 已硬化 | 统计 narrator intrusion、system voice、explanation 触发率，验证不再出现大段机制议论 |
| P1 | OBSERVABILITY-1 | 管线观测面 | 待设计 | 参考 Novelix Studio，展示章节状态、gate 失败原因、truth/anchor 覆盖、评分分布和人工 review 状态 |
| P1 | TRUTH-FILES-EVAL | Truth files / DB 投影评估 | 待设计 | 评估是否从 DB 生成 5-7 个可读 truth 投影文件，供人类和 LLM 审稿时稳定读取 |

---

## 6. 当前验证命令

```powershell
cd D:\_Progs\02Business\Writer\inkflow
python -m py_compile src\inkflow\cli.py src\inkflow\db\migration.py src\inkflow\export\exporter.py src\inkflow\services\fact_anchor_extractor.py
python -m pytest tests\test_schema.py tests\test_migration.py tests\test_cli.py tests\test_fact_anchor.py -q
python -m pytest -q
python -m inkflow.cli status "分流"
python -m inkflow.cli run-book "分流" --from v01.c04 --to v01.c06 --plan-only
```
