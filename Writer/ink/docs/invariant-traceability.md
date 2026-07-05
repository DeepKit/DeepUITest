# 测试与审计追踪矩阵

> **状态**：v1（2026-07-04，质量硬门禁修订）
> **定位**：把旧 bugfix、架构决策和新生产能力映射到新系统的不变量、测试与阻断里程碑。没有映射的能力不得视为完成。

## 1. 使用规则

- 每个 invariant 必须有稳定 ID。
- 每个 invariant 必须对应至少一个新测试或 lint。
- 旧测试可以不机械迁移，但旧测试覆盖的领域不变量不能丢。
- A/C 桶迁移按“不变量数”验收，不按用例数验收。
- M0-M6 任一里程碑若缺本表标记为 blocking 的 invariant，对应里程碑不得完成。

## 2. P0 阻断不变量

| ID | 来源 | 不变量 | 新测试 / 门禁 | 里程碑 |
|----|------|--------|---------------|--------|
| INV-CONTRACT-001 | B28/B48/B67/B87/B92 | dataclass 上游字段必须被消费，不得动态访问 | `test_field_usage_lint_*` + `field_usage_lint` | M0 |
| INV-SQL-001 | B19 | 非 `core/text_repository.py` 不得直接访问 `writing_shot_revisions` | `test_sql_access_lint_*` | M0 |
| INV-DDL-001 | 评审 P0 | 40 张生产表 DDL 必须在内存 SQLite 执行成功 | `test_schema_executes_all_ddl` | M0 |
| INV-CONFIG-001 | D1/P0-4 | 模型池必须是非空唯一字符串数组；默认写手池与裁判池无交集，重叠时排除 writer 后仍有 3 个 jury model | `test_project_config_validator_model_pools` | M0 |
| INV-TIME-001 | D5 | 所有业务时间字段统一 UTC ISO 8601 `YYYY-MM-DDTHH:MM:SS.sssZ` | `test_now_utc_iso_format` | M0 |
| INV-STATE-001 | P0-2 | 14 态状态机只允许矩阵内转移，winner 必须经 polish_revision，终态无出边 | `test_state_machine_matrix` | M1 |
| INV-STATE-002 | P0-2 | 禁止除 `core/state_machine.py` 外直接 `UPDATE writing_shots SET status` | `state_update_lint` | M0 |
| INV-REVISION-001 | B19 | `v_current_text` 每 shot 恰一行，封版行优先 | `test_v_current_text_single_row` | M0 |
| INV-REVISION-002 | B92 | stale revision 不 skip，下游必须重跑 | `test_resume_detects_stale_upstream_revision` | M1 |
| INV-RUN-001 | B62/B61 | logical_shot_id、run_id、accepted、is_current 四维正交 | `test_four_axis_isolation` | M1 |
| INV-SOFT-001 | N2 | soft gate N 计数唯一权威源是 `writing_soft_gate_counters` | `test_soft_gate_counter_db_authority` | M1 |
| INV-SOFT-002 | N2 | N=2 翻盘只允许在 `winner_selected`；进入 `polish_revision`/`soft_sealed` 后新建 run | `test_resume_manager_handles_redo_in_progress_branches` + `test_redo_candidates_merge_with_existing_pool_and_can_flip_winner` | M1/M4 |
| INV-LLM-001 | B59 | 同类失败连续 `consecutive_failure_circuit_break`（默认 3）次熔断，失败类型切换归零 | `test_llm_failure_streaks` | M1 |
| INV-LLM-002 | P0-5 | shot 总 AI 调用达到 `max_total_llm_calls`（默认 40）上限转 `failed` | `test_total_llm_budget_transitions_failed` | M1 |
| INV-LLM-003 | 运行时评审 | 所有 AI 调用必须经 `LLMGateway` 并落 attempt | `llm_access_lint` + `test_ai_attempt_written` | M0/M1 |
| INV-QUALITY-001 | 质量铁律 | `final_score < shot_quality_floor` 的 draft 不得 winner | `test_jury_quality_floor_failure_cannot_select_winner` | M4 |
| INV-QUALITY-002 | 质量铁律 | 任一核心维度低于 `dimension_floor` 不得 `quality_gate_passed` / soft seal | `test_jury_dimension_floor_failure_cannot_select_winner` | M4 |
| INV-QUALITY-003 | 质量铁律 | 裁判分歧超过阈值不得直接 winner，必须升级复核 | `test_jury_disagreement_failure_cannot_select_winner` | M4 |
| INV-QUALITY-004 | 质量铁律 | winner 必须经过 `polish_revision` 并重新过 hard gates + quality floor 后才能 soft seal | `test_polish_winner_writes_revision_and_returns_to_hard_gate`（polish baseline）；soft seal 复验待 M5 补测 | M4/M5 |
| INV-QUALITY-005 | 质量铁律 | 章级 7 维任一低于阈值不得 accepted | `test_chapter_quality_gate_blocks_accept` | M5 |
| INV-QUALITY-006 | 质量铁律 | 篇级 blocking issue 未解决不得继续 accept/export | `test_book_blocking_issue_blocks_accept_export` | M6 |
| INV-QUALITY-007 | 质量铁律 | human accept 不得 override 硬质量失败 | `test_human_accept_cannot_override_quality_failure` | M5 |
| INV-QUALITY-008 | 质量证明 | `quality_report_json` 必须标注 ES/SEMI_ES/NES 与 destructive/productive/neutral | `test_quality_report_schema_requires_evidence_and_defect_class` | M0/M5 |
| INV-QUALITY-009 | 质量证明 | 盲评未通过或 `would_continue_reading_score` 低于阈值不得 `quality_gate_passed` / accepted | `test_blind_review_and_reader_pull_required` | M4/M5 |
| INV-QUALITY-010 | 文学活力保护 | `productive_deviations` / `protected_roughness` 不得被 polish 自动删除或磨平 | `test_polish_preserves_productive_deviations` | M4/M5 |
| INV-QUALITY-011 | 模型层级 | 文学体验评审、盲评排序、边界复核、返工指导、polish 不得降级到非 smart 模型 | `test_polish_blocks_when_smart_model_unavailable_without_downgrade` | M4 |
| INV-JURY-SELF-001 | D3/P0-4 | DB trigger 阻断 `judge_model = writer_model` 的 raw score 写入，JOIN 审计为空 | `test_jury_raw_scores_no_self_judge_trigger` | M0/M4 |
| INV-JURY-ROUND-001 | 专家审查 P0 | `writing_jury_raw_scores` 必须支持基础 3 裁判和分歧升级 `jury_round`；不得用 role 唯一约束限死 3 行 | `test_jury_raw_scores_supports_escalation_round` | Pre-M0/M0 |
| INV-CHECKPOINT-001 | D2 | checkpoint `shot_id` 允许 NULL；非 NULL 时必须是 attempt shot id 并满足 FK | `test_checkpoint_shot_id_null_and_fk_semantics` | M0/M1 |
| INV-HUMAN-001 | B44/B61 | setup/contract/review/import 人工动作必须写 human decision | `test_human_decision_required` | M5 |
| INV-AUDIT-001 | D-23 | failure attribution 必须能关联 contract clause | `test_failure_attribution_clause_link` | M5 |
| INV-RECOVERY-001 | D-14 | 每个稳定阶段写 checkpoint，崩溃恢复不覆盖已封板文本 | `test_resume_from_checkpoints` | M1 |
| INV-IMPORT-001 | 产品工作流 | import dry-run 不写正式数据，finalize 必须有人类决策 | `test_import_dry_run_finalize` | M6 |
| INV-EXPORT-001 | B61/B76 | export 只读 accepted canonical 且清理结构标签 | `test_export_accepted_only` | M6 |

## 3. 旧测试三桶判定

| 桶 | 判据 | 处理 |
|----|------|------|
| A | 阈值、状态转移、封版、幂等、唯一性等领域不变量 | 重写为新测试，断言不得弱化 |
| B | 旧 schema、旧 CLI、旧 dict 传递链、旧双轨逻辑绑定 | 不迁移代码；领域知识若仍有效必须映射到 P0/P1 invariant |
| C | 端到端行为规约，如写一章、审稿、导出、resume | 转写为 M6 集成测试 |

## 4. 决策映射

| 决策 | 新落点 | 必测项 |
|------|--------|--------|
| D-02 L0 机械检查 | hard_gate1 的基础可读/容量/禁区；失败不进 jury | INV-GATE-001 |
| D-14 crash recovery checkpoints | `writing_session_checkpoints` + `ResumeManager` | INV-RECOVERY-001 |
| D-19 fact anchors | `writing_fact_anchors` + hard_gate2 fact anchor | INV-FACT-001 |
| D-23 contract auditability | `writing_contract_clauses` / `writing_contract_changelog` / failure attribution | INV-AUDIT-001 |
| Q-01 high quality hard gate | `writing_projects` 质量阈值字段（`shot_quality_floor` 等）/ `style_quality_profile` / `quality_gate_passed` / `quality_report_json` | INV-QUALITY-001..011 |

## 5. P1 不变量

| ID | 不变量 | 新测试 / 门禁 | 里程碑 |
|----|--------|---------------|--------|
| INV-GATE-001 | hard gate 必须先于文学 jury | `test_hard_gate_orchestrator_records_two_gate_eligibility_and_blocks_degraded` | M4 |
| INV-GATE-002 | degraded draft 不进 jury | `test_hard_gate_orchestrator_records_two_gate_eligibility_and_blocks_degraded` | M3/M4 |
| INV-JURY-001 | 3 裁判全评 12 维，raw 与 aggregate 分离 | `test_jury_scores_three_models_all_dimensions_and_selects_winner` | M4 |
| INV-JURY-002 | 裁判模型不得等于该 draft 的 writer_model | `test_jury_scores_three_models_all_dimensions_and_selects_winner` | M4 |
| INV-PROMPT-001 | task card / prompt 二次编译旧行打 superseded_at，新行保留 | `test_task_card_compiler_rejects_incomplete_tail_and_supersedes_old_cards` + `test_prompt_snapshot_compiler_supersedes_by_task_card_persona` | M2 |
| INV-OUTLINE-001 | drift_score < `outline_drift_threshold`（默认 0.20）拒绝 | `test_outline_drift_threshold_and_winner_uniqueness` | M2 |
| INV-OUTLINE-002 | task card 半句拒绝 | `test_task_card_compiler_rejects_incomplete_tail_and_supersedes_old_cards` | M2 |
| INV-FACT-001 | fact anchor 违约/幻觉阻断 hard gate2 | `test_fact_anchor_gate` | M4 |
| INV-BOOK-001 | 第 N 章触发篇级滚动检测 | `test_book_rolling_check_interval` | M6 |
| INV-WORKFLOW-001 | 6 章完整生产验收，包括 revise/reject/import/export/resume | `test_full_production_flow_six_chapters` | M6 |

## 6. 完成定义

一个里程碑完成必须同时满足：

1. 对应代码已实现。
2. 对应 invariant 测试已存在并通过。
3. 对应 lint / CI 门禁已接入。
4. 文档中的表名、字段名、状态名与实现一致。
5. 运行时审计能重放关键过程：AI 调用、状态转移、人工决策、正文读取、导出。
