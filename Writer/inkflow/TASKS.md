# InkFlow — 当前任务与议题清单

Date: 2026-07-01
Status: v3.23 配置项 DB 强制化方案已决策；TITLE-FIX-1 已落地；Schema v22；45 张业务表 + `_schema_meta` 元表

---

## 1. 当前结论

InkFlow 的工程内核已完成 accepted canonical、run attempt identity、accepted-only export 和 book_run 编排层。合同优先（contract-first）管线、全程审计底座、契约审计师两轮复审、大纲硬门禁、草稿资格门禁均已落地。

**《白灯法则》第 2 章生产验证**暴露了 6 个管线缺陷（B76-B81），已全部修复或记录。同时完成悬疑约束架构决策：**DB 字段级线束**——所有 AI 生成的配置项必须有结构化 DB 表接收，DB NOT NULL + CHECK + FK 硬拦，AI 无法绕过。JSON blob 仅保留给日志/快照/审计。

当前口径：**暂不进入正式放量生产**。正式投产前必须完成配置项 DB 强制化（CONFIG-ENFORCE），并用《白灯法则》第 3 章返工验证新门禁。

详细开发记录见 `docs/history.md`；Bug 记录见 `docs/bugfix.md`（当前至 B81）。

---

## 2. 权威文档

| 文档 | 位置 | 当前状态 |
|------|------|:---:|
| 技术设计权威 | `docs/design.md` | 已同步 v3.23 / Schema v22 |
| 实现契约 / DDL / 状态机 | `docs/implementation-contract-v0.md` | 已同步 Schema v22 |
| 人机流程 | `docs/flow.md` | 已同步 run-book / book-report |
| 三棵树与正文真相源 | `docs/design-3tree-architecture.md` | 已标注 accepted canonical 与 run attempt identity 已落地 |
| 悬疑引擎 | `docs/suspense-engine.md` | 已实施核心闭环，待 DB 强制化后增强 |
| 开发历史 | `docs/history.md` | 本轮追加 v3.23 |
| Bug 记录 | `docs/bugfix.md` | 本轮追加 B76-B81 |
| Novelix 研究记录 | `docs/research-novelix.md` | 外部系统启发与 InkFlow 迁移建议 |

---

## 3. 已完成任务归档

| 阶段 | 已完成 |
|------|--------|
| P0 纵向闭环 | 导入第 1 章、确认契约、逐 shot 生成第 2 章、scope report |
| 真实章节验证 | 第 2 章本地兜底链路；第 3 章远端 writer/jury 链路跑通（人工审稿需返工） |
| 工作流收敛 | `init -> setup --chapter -> run --chapter -> review` |
| JURY-V5 | 硬规则 → 类型职责 → 文学 9 维；至少 2 个过线稿；单线返写 |
| PROD-HARDEN-1 | persona prompt、creative_score winner、L4/L3 硬停、当前 run 导出过滤、retry 熔断 |
| CORE/EXPORT/REVIEW/STATUS | `writing_chapter_reviews`、accepted-only 默认导出、review DB 状态机、previous context / fact anchors canonical 过滤、run attempt shot identity |
| BOOKRUN-1 | `run-book` / `book-report`、book_run DB 编排表、同批次草稿上下文 |
| CONTENT-GATE-1 | 标题回退、角色名 canonical gate、未授权事实扩写 gate、短 shot density gate |
| AUDIT-1 | Schema v21 全程审计表、prompt/response 完整记录、draft eligibility / failure attribution |
| CONTRACT-AUDITOR-1 | `confirm-contract` 两轮契约审计师复审 |
| CONTRACT-FIRST-1 | fact_manifest、outline fact gate、shot task card、草稿 hard fact gate |
| SETUP-LINT-1 | setup 自相矛盾 linter；preflight 失败归因到 `contract_conflict` |
| TITLE-FIX-1 | 导出标题泄漏修复；`_derive_event_title()` 从内容提取短标题；8 个测试通过 |
| OUTLINE-HALLUCINATION-1 | 大纲重生成幻觉防护；bigram drift 检测 |
| L3-GATE-FP-1 | L3 `chapter_hook_weak` / `character_absence` 假阳性改 warning |

---

## 4. 当前 P0 状态

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P0 | AUDIT-VERIFY-1 | 真实《分流》库 v22 迁移验证 | 待执行 | `ink status "分流"` 正常；重跑章节后可查全审计链 |
| P0 | FAIL-ATTR-2 | 失败归因与重试上限 | 部分完成 | `gate_false_positive` 仍需真实样本细分 |

---

## 5. P1 待办

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P1 | CONFIG-ENFORCE-1 | Schema v23：元契约结构化表 | 待实施 | 新增 `writing_project_identity` / `writing_hard_boundaries` / `writing_narrative_voice` / `writing_style_locks` / `writing_suspense_blueprint` / `writing_chapter_tension_arc`；所有字段 NOT NULL + CHECK + FK |
| P1 | CONFIG-ENFORCE-2 | Schema v23：shot 契约结构化表 | 待实施 | 新增 `writing_shot_must_land` / `writing_shot_anti_write` / `writing_shot_narrative_params`；替代 `must_land_json` / `anti_write_json` / `contract_json` 中 AI 写入字段 |
| P1 | CONFIG-ENFORCE-3 | `confirm-contract` 改造：写结构化表 + Schema 验证 | 待实施 | Python 层 `validate_contract_schema()` 快速失败 + DB INSERT 硬拦 + 语义完整性检查（弧线峰谷、角色覆盖）|
| P1 | CONFIG-ENFORCE-4 | 消费端改造：gate/exporter 读结构化表 | 待实施 | `architect_gate.py` / `exporter.py` / `prompt_compiler.py` 改为读结构化表，不再 `json.loads(layers_json).get(...)` |
| P1 | CONFIG-ENFORCE-5 | `layers_json` 降级为冗余快照 | 待实施 | 结构化表写入后仍写 `layers_json` 向后兼容；后续版本移除 JSON blob 消费路径 |
| P1 | CHAPTER-3-REWRITE | 第 3 章返工重跑 | 等 CONFIG-ENFORCE 落地后执行 | `review --reject/--revise` → 按新门禁重新 `setup/run` |
| P1 | CHAPTER-4-SETUP | 第 4 章生产前校准 | 待第 3 章返工后执行 | 吸收返工结论后 `setup --chapter v01.c04 --force` |
| P1 | SUSPENSE-EXTRACT-1 | 从分章大纲自动提取 suspense 元数据 | 待设计 | 解析 `24_分章大纲.md` 中追读类型/主引擎/情感刻度目标，映射为 suspense_blueprint |
| P1 | MODELS-CONFIG-SYNC-1 | `.models` 双源配置一致性 | 已发现 (B81) | `roles.*` 和 `jury_config.models` 统一或加校验 |
| P1 | JURY-V5-REAL | 分层裁判真实项目持续观测 | 已有样本 | 每章记录硬规则失败数、类型 gate 触发数、文学 9 维分布 |
| P1 | OBSERVABILITY-1 | 管线观测面 | 待设计 | 展示章节状态、gate 失败原因、评分分布、review 状态 |

---

## 6. 当前验证命令

```powershell
cd D:\_Progs\02Business\Writer\inkflow
python -m py_compile src\inkflow\cli.py src\inkflow\db\migration.py src\inkflow\export\exporter.py src\inkflow\services\fact_anchor_extractor.py src\inkflow\services\contract_auditor.py
rtk proxy python -m pytest tests\test_schema.py tests\test_migration.py tests\test_cli.py tests\test_fact_anchor.py -v
rtk proxy python -m pytest tests\test_cli.py::TestDeriveEventTitle -v
python -m pytest -q
python -m inkflow.cli status "分流"
```
