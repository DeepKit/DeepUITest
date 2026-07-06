# InkFlow v2 Bugfix 记录

> **用途**：记录开发中发现的缺陷、根因、修复和防回归测试。
> **最后更新**：2026-07-06

---

## 2026-07-06

### BFX-007 CLI resume 忽略 session 级 resume_point

- **现象**：`ink resume --session-id` 只遍历 `writing_shots` 并执行 shot 级 action，未读取 `writing_sessions.resume_point`，导致 `chapter_review`、`book_check` 等 session 级断点无法恢复。
- **根因**：M2-M4 先落地 shot 级 resume registry，M5-M6 的章级/篇级/导入恢复点没有统一 dispatch 入口。
- **修复**：新增非 shot 级 resume handler registry；`ResumeManager.execute_resume_point()` 按 `phase` 调度；CLI `resume` 在 shot 恢复后执行 session 级 resume point，并在成功后清空 `crashed/resume_point`。
- **防回归**：`tests/test_resume_handler_registry.py::test_cli_resume_executes_session_level_chapter_review`。

### BFX-008 import finalize 恢复可能重复写审计

- **现象**：同一 `import_run_id` 如果在 finalize 成功后再次通过恢复链路执行，会再次写入 `writing_human_decisions` 和 `writing_import_decisions`。
- **根因**：`ImportOrchestrator.finalize()` 没有先检查该 import run 是否已有 finalize 决策；DDL 也未对 `writing_import_decisions.import_run_id` 设置唯一约束。
- **修复**：`finalize()` 入口先读取既有 import decision；已存在时直接返回既有 `ImportFinalizeResult`，不再写第二份审计。
- **防回归**：`tests/test_resume_handler_registry.py::test_non_shot_resume_executes_import_finalize_once`。

## 2026-07-05

### BFX-001 import questions schema 字段误用

- **现象**：`test_import_finalize_rejects_unresolved_questions` 最初向 `writing_import_questions.created_at` 写入数据，但 DDL 中该表没有 `created_at` 字段。
- **根因**：测试假设了通用审计字段，未核对 import question 的真实 DDL。
- **修复**：按 schema 改为只写 `import_run_id / manifest_id / question_text / options_json`。
- **防回归**：`tests/test_m6_import.py::test_import_finalize_rejects_unresolved_questions`。

### BFX-002 revise/accept loader 绑定反转

- **现象**：reject 后 revise 被 pending-only loader 阻断；同时 accept 错误地允许 rejected review。
- **根因**：`accept_chapter` 与 `revise_chapter` 的 review loader 语义在重构中绑定反了。
- **修复**：`accept_chapter` 使用 `_load_pending_review()`；`revise_chapter` 使用 `_load_revision_source_review()`，允许从 pending/rejected 发起修订。
- **防回归**：`tests/test_m6_workflow_smoke.py::test_rejected_chapter_cannot_be_accepted` 和 `test_full_production_flow_six_chapters`。

### BFX-003 CLI setup 默认 persona 违反 DDL 枚举

- **现象**：CLI `setup` 写入英文 persona `suspense`，触发 `writing_shot_persona_assignment.persona` CHECK 失败。
- **根因**：CLI 默认契约没有复用 schema 中允许的五类中文 persona。
- **修复**：CLI 默认 setup 改为 `悬疑官`，并使用中文 5 维强度键。
- **防回归**：`tests/test_cli.py::test_cli_chapter_revise_export_import_flow` 和 `test_cli_resume_starts_pending_shot`。

### BFX-004 invariant 追踪矩阵漏接声明项

- **现象**：`invariant-traceability.md` 中存在 `INV-RUN-001`、`INV-AUDIT-001`、`INV-FACT-001`、`INV-QUALITY-009`、`INV-QUALITY-010`，但追踪测试未强制登记。
- **根因**：追踪测试只验证已登记 ID 有证据，未反向检查矩阵中的所有 `INV-*`。
- **修复**：补齐对应测试，并让追踪测试断言矩阵 ID 与 `INVARIANT_EVIDENCE` 完全对齐。
- **防回归**：`tests/test_invariant_traceability.py::test_tracked_invariants_have_executable_evidence`。

### BFX-005 polish 未显式保护 productive marker

- **现象**：polish baseline 可以产出不含 productive/protected marker 的文本，未显式阻断“磨平”有效偏离。
- **根因**：polish prompt 中声明保护，但代码未验证输出仍保留保护标记。
- **修复**：`PolishOrchestrator` 在写 revision 前检查 `[productive-deviation]` / `[protected-roughness]` 是否被保留。
- **防回归**：`tests/test_m4_review_pipeline.py::test_polish_preserves_productive_deviations`。

### BFX-006 fact anchor / contract clause attribution 缺少可执行闭环

- **现象**：DDL 有 `writing_fact_anchors` 和 `writing_contract_clauses`，但 hard gate baseline 没有用它们形成阻断和条款级 attribution。
- **根因**：M4 baseline 先实现了 hard gate 框架，未补事实锚点与条款审计链。
- **修复**：hard gate2 对 `[fact-violation]` + confirmed fact anchor 执行阻断，并写入 `writing_failure_attributions.contract_clause_id`。
- **防回归**：`tests/test_m4_review_pipeline.py::test_fact_anchor_gate_and_failure_attribution_clause_link`。
