# InkFlow — 当前任务与议题清单

Date: 2026-07-02
Status: v3.25 第 3 章返工验证已跑通（CONFIG-ENFORCE 真实项目验证 + B83-B91 硬化）；全量回归 519 passed；下一步人工 review 第 3 章并做第 4 章生产前校准

---

## 1. 当前结论

InkFlow 的工程内核已完成 accepted canonical、run attempt identity、accepted-only export 和 book_run 编排层。合同优先（contract-first）管线、全程审计底座、契约审计师两轮复审、大纲硬门禁、草稿资格门禁均已落地。

**《白灯法则》第 2-3 章生产验证**暴露了 16 个管线缺陷（B76-B91），已全部修复或记录。同时完成悬疑约束架构决策：**DB 字段级线束**——所有 AI 生成的配置项必须有结构化 DB 表接收，DB NOT NULL + CHECK + FK 硬拦，AI 无法绕过。JSON blob 仅保留给日志/快照/审计。

当前口径：**暂不进入正式放量生产**。第 3 章已完成自动生成和 L3 通过，下一步必须人工审稿决定是否 `review --accept`，再进入第 4 章生产前校准。

详细开发记录见 `docs/history.md`；Bug 记录见 `docs/bugfix.md`（当前至 B91）。

---

## 2. 权威文档

| 文档 | 位置 | 当前状态 |
|------|------|:---:|
| 技术设计权威 | `docs/design.md` | 已同步 v3.24 / Schema v24 |
| 实现契约 / DDL / 状态机 | `docs/implementation-contract-v0.md` | 已同步 Schema v24 |
| 人机流程 | `docs/flow.md` | 已同步 run-book / book-report |
| 三棵树与正文真相源 | `docs/design-3tree-architecture.md` | 已标注 accepted canonical 与 run attempt identity 已落地 |
| 悬疑引擎 | `docs/suspense-engine.md` | 已实施核心闭环，DB 强制化已增强 |
| 开发历史 | `docs/history.md` | 本轮追加 v3.25 |
| Bug 记录 | `docs/bugfix.md` | 本轮追加 B76-B91 |
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
| CONFIG-ENFORCE-1 | Schema v23：6 张元契约结构化表 + NOT NULL + CHECK + FK |
| CONFIG-ENFORCE-2 | Schema v24：3 张 shot 契约结构化表 + NOT NULL + CHECK + FK |
| CONFIG-ENFORCE-3 | `confirm-contract` 写结构化表 + Python `validate_contract_schema()` 预检 |
| CONFIG-ENFORCE-4 | 消费端改造：`architect_gate` / `exporter` / `run` prompt 读结构化表 |
| CONFIG-ENFORCE-5 | `layers_json` 降级为冗余快照；结构化表为主源 |
| MODELS-CONFIG-SYNC-1 | `utils/config.py` 校验 `roles.jury` 与 `jury_config.models` 一致性 |
| SUSPENSE-EXTRACT-1 | 自动从项目文档提取 `suspense_blueprint` preset + global_question |
| CONTRACT-DRAFT-ID-1 | `init` 生成 author / era / language / total_chapters / genre_tags，与 v23 DB 约束对齐 |
| CHAPTER-3-REWRITE | 《白灯法则》v01.c03 返工验证跑通；latest run completed 3/3；自动导出待人工 review |
| REAL-C03-HARDEN-1 | B83-B91：真实项目兼容、半句大纲防护、prompt upsert、L4 density 前移、Scope Report 当前 run 过滤 |

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
| P1 | CONFIG-ENFORCE-1 | Schema v23：元契约结构化表 | ✅ 已完成 | 6 张表 + NOT NULL + CHECK + FK；519 tests pass |
| P1 | CONFIG-ENFORCE-2 | Schema v24：shot 契约结构化表 | ✅ 已完成 | 新增 `writing_shot_must_land` / `writing_shot_anti_write` / `writing_shot_narrative_params`；替代 `must_land_json` / `anti_write_json` / `contract_json` 中 AI 写入字段；519 tests pass |
| P1 | CONFIG-ENFORCE-3 | `confirm-contract` 改造：写结构化表 + Schema 验证 | ✅ 已完成 | Python 层 `validate_contract_schema()` 快速失败 + DB INSERT 硬拦 + 语义完整性检查（角色覆盖）；519 tests pass |
| P1 | CONFIG-ENFORCE-4 | 消费端改造：gate/exporter 读结构化表 | ✅ 已完成 | `architect_gate.py` / `exporter.py` / `cli.py run` 改为读结构化表并保留 JSON fallback；519 tests pass |
| P1 | CONFIG-ENFORCE-5 | `layers_json` 降级为冗余快照 | ✅ 已完成 | `write_meta_contract_structured` 写入结构化表时仍保留 `layers_json` 作为只读审计快照；所有消费端优先读结构化表 |
| P1 | SUSPENSE-EXTRACT-1 | 从分章大纲自动提取 suspense 元数据 | ✅ 已完成 | `_extract_suspense_blueprint()` + `_extract_chapter_hooks_from_outline()`；fallback 默认值覆盖；519 tests pass |
| P1 | MODELS-CONFIG-SYNC-1 | `.models` 双源配置一致性 | ✅ 已修复 (B81/B86) | `get_jury_config()` 统一 `roles.jury` 与 `jury_config.models`，冲突时 warn 并以 `jury_config.models` 为准；519 tests pass |
| P1 | CHAPTER-3-REWRITE | 第 3 章返工重跑 | ✅ 已生成，待人工审稿 | latest run `01KWGE8XZPJZN41W5TTAKHAB5G` completed 3/3；L3 passed；已导出 `白灯法则_v01.c03_导出.md` |
| P1 | CHAPTER-4-SETUP | 第 4 章生产前校准 | 待第 3 章人工 review 后执行 | 吸收返工结论后 `setup --chapter v01.c04 --force` |
| P1 | JURY-V5-REAL | 分层裁判真实项目持续观测 | 已有样本 | 每章记录硬规则失败数、类型 gate 触发数、文学 9 维分布 |
| P1 | OBSERVABILITY-1 | 管线观测面 | 待设计 | 展示章节状态、gate 失败原因、评分分布、review 状态 |

---

## 6. 当前验证命令

```powershell
cd D:\_Progs\02Business\Writer\inkflow
python -m py_compile src\inkflow\cli.py src\inkflow\services\architect_gate.py src\inkflow\services\contract_compiler.py src\inkflow\services\exposition_gate.py src\inkflow\services\outline_evaluator.py src\inkflow\services\prompt_compiler.py src\inkflow\utils\config.py
rtk proxy python -m pytest tests\test_schema.py tests\test_migration.py tests\test_cli.py tests\test_fact_anchor.py -v
rtk proxy python -m pytest tests\test_cli.py::TestDeriveEventTitle -v
python -m pytest -q
python -m inkflow.cli status "白灯法则"
```
