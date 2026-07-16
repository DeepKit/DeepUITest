from __future__ import annotations

import re
from pathlib import Path


INVARIANT_EVIDENCE = {
    "INV-SCENE-001": ["test_scene_revision_update_is_blocked_by_database_trigger"],
    "INV-SCENE-002": ["test_referenced_scene_revision_cannot_be_deleted"],
    "INV-INTERNAL-SHOT-001": ["test_internal_shot_has_no_canonical_or_acceptance_columns"],
    "INV-BRANCH-001": ["test_frozen_branch_blocks_revision_and_binding_mutation"],
    "INV-BRANCH-002": ["test_two_branches_can_fork_from_same_branch_local_parent"],
    "INV-SNAPSHOT-001": ["test_snapshot_and_snapshot_bindings_are_immutable"],
    "INV-SNAPSHOT-002": ["test_chapter_head_is_unique_per_project_chapter"],
    "INV-SNAPSHOT-003": ["test_snapshot_text_does_not_follow_later_scene_revision"],
    "INV-SCENE-CONTRACT-001": ["test_same_scene_allows_only_one_active_contract"],
    "INV-SCENE-AI-001": ["test_ai_revision_requires_auditable_generation_or_repair_task"],
    "INV-ROUND-001": [
        "test_round_legal_transitions_advance",
        "test_round_transition_not_in_table_is_illegal",
    ],
    "INV-ROUND-002": ["test_round_illegal_transition_raises_illegal_transition_error"],
    "INV-ROUND-003": ["test_round_cas_rejects_stale_expected_status"],
    "INV-ROUND-004": ["test_round_initial_zero_pass_terminates_round"],
    "INV-ROUND-005": ["test_round_supplement_only_once_from_validating_initial"],
    "INV-ROUND-006": ["test_round_ready_for_selection_requires_three_eligible"],
    "INV-ROUND-007": [
        "test_round_terminal_state_rejects_further_transition",
        "test_round_superseded_only_from_non_terminal",
    ],
    "INV-ROUND-008": ["test_record_eligible_branch_increments_count_atomically"],
    "INV-ROUND-009": ["test_increment_call_count_is_monotonic"],
    "INV-ROUND-010": ["test_get_round_state_returns_full_recovery_point"],
    "INV-ROUND-011": ["test_driver_advances_planned_to_selected"],
    "INV-ROUND-012": ["test_driver_initial_zero_pass_on_zero_eligible"],
    "INV-ROUND-013": ["test_driver_supplements_when_partial_initial_pass"],
    "INV-ROUND-014": ["test_driver_candidate_shortage_after_supplement"],
    "INV-ROUND-015": [
        "test_driver_diversity_shortage_when_no_substantive_difference"
    ],
    "INV-ROUND-016": ["test_driver_call_count_circuit_breaker"],
    "INV-ROUND-017": ["test_driver_resumes_from_intermediate_state"],
    "INV-ROUND-018": [
        "test_start_validating_branch_cas_rejects_non_generating"
    ],
    "INV-ROUND-019": [
        "test_advance_to_literary_review_cas_rejects_non_eligible"
    ],
    "INV-SCENE-CAS-001": ["test_stale_branch_local_parent_is_rejected"],
    "INV-CHAPTER-CAS-001": ["test_stale_expected_head_version_rolls_back_without_new_snapshot"],
    "INV-ACCEPT-001": ["test_accept_creates_sealed_snapshot_and_active_head"],
    "INV-ACCEPT-002": ["test_accept_fault_rolls_back_all_authority_rows"],
    "INV-CONTRACT-001": ["test_field_usage_lint", "lint_field_usage"],
    "INV-SQL-001": ["test_sql_access_lint", "lint_sql_access"],
    "INV-DDL-001": ["test_schema_executes_all_ddl"],
    "INV-CONFIG-001": ["test_project_config_validator"],
    "INV-TIME-001": ["test_now_utc_iso_format"],
    "INV-STATE-001": ["test_state_machine_allows_legal_transition"],
    "INV-STATE-002": ["test_state_update_lint", "lint_state_updates"],
    "INV-REVISION-001": ["test_v_current_text"],
    "INV-REVISION-002": ["test_resume_manager"],
    "INV-RUN-001": ["test_four_axis_isolation"],
    "INV-SOFT-001": [
        "test_soft_gate_counter_db_authority",
        "test_soft_gate_orchestrator_records_n1_counter_without_redo",
    ],
    "INV-SOFT-002": [
        "test_resume_manager_handles_redo_in_progress",
        "test_soft_gate_orchestrator_sets_redo_in_progress_on_n2_idempotently",
        "test_redo_candidates_merge",
    ],
    "INV-LLM-001": ["test_llm_failure_streaks_and_budget_circuit"],
    "INV-LLM-002": ["test_total_llm_budget_transitions_failed"],
    "INV-LLM-003": ["test_llm_gateway_records_attempt", "lint_llm_access"],
    "INV-QUALITY-008": ["test_quality_report_schema_requires_evidence_and_defect_class"],
    "INV-JURY-SELF-001": ["test_jury_raw_scores_reject_self_judging"],
    "INV-JURY-ROUND-001": ["test_jury_raw_scores_support_base_and_escalated_rounds"],
    "INV-CHECKPOINT-001": ["test_session_checkpoints_allow_null_shot_id"],
    "INV-RECOVERY-001": ["test_checkpoint_manager_checksum_recovery"],
    "INV-PROMPT-001": ["test_prompt_snapshot_compiler_supersedes_by_task_card_persona"],
    "INV-OUTLINE-001": ["test_outline_drift_threshold_and_winner_uniqueness"],
    "INV-OUTLINE-002": ["test_task_card_compiler_rejects_incomplete_tail_and_supersedes_old_cards"],
    "INV-QUALITY-001": ["test_jury_quality_floor_failure_cannot_select_winner"],
    "INV-QUALITY-002": ["test_jury_dimension_floor_failure_cannot_select_winner"],
    "INV-QUALITY-003": ["test_jury_disagreement_failure_cannot_select_winner"],
    "INV-QUALITY-004": [
        "test_polish_winner_writes_revision_and_returns_to_hard_gate",
        "test_unpolished_winner_cannot_soft_seal",
        "test_polished_winner_repasses_quality_before_soft_seal",
    ],
    "INV-QUALITY-005": ["test_chapter_quality_gate_blocks_accept"],
    "INV-QUALITY-006": ["test_book_blocking_issue_blocks_accept_export"],
    "INV-QUALITY-007": ["test_human_accept_cannot_override_quality_failure"],
    "INV-QUALITY-009": ["test_blind_review_and_reader_pull_required"],
    "INV-QUALITY-010": ["test_polish_preserves_productive_deviations"],
    "INV-QUALITY-011": ["test_polish_blocks_when_smart_model_unavailable_without_downgrade"],
    "INV-HUMAN-001": ["test_human_accept_writes_decision_and_hard_seals_chapter"],
    "INV-AUDIT-001": ["test_failure_attribution_clause_link"],
    "INV-IMPORT-001": ["test_import_dry_run_finalize"],
    "INV-EXPORT-001": ["test_export_accepted_only"],
    "INV-BOOK-001": ["test_book_rolling_check_interval"],
    "INV-WORKFLOW-001": ["test_full_production_flow_six_chapters"],
    "INV-GATE-001": ["test_hard_gate_orchestrator_records_two_gate_eligibility"],
    "INV-GATE-002": ["test_hard_gate_orchestrator_records_two_gate_eligibility"],
    "INV-FACT-001": ["test_fact_anchor_gate"],
    "INV-JURY-001": ["test_jury_scores_three_models_all_dimensions_and_selects_winner"],
    "INV-JURY-002": ["test_jury_scores_three_models_all_dimensions_and_selects_winner"],
}


def test_tracked_invariants_have_executable_evidence() -> None:
    root = Path(__file__).resolve().parents[1]
    matrix = (root / "docs" / "invariant-traceability.md").read_text(encoding="utf-8")
    test_source = "\n".join(path.read_text(encoding="utf-8") for path in (root / "tests").glob("test_*.py"))
    lint_source = "\n".join(path.read_text(encoding="utf-8") for path in (root / "src" / "ink" / "linting").glob("*.py"))
    source = test_source + "\n" + lint_source
    matrix_ids = set(re.findall(r"\bINV-[A-Z0-9-]+", matrix))
    assert sorted(matrix_ids - set(INVARIANT_EVIDENCE)) == []

    for invariant_id, evidence_tokens in INVARIANT_EVIDENCE.items():
        assert invariant_id in matrix
        assert any(token in source for token in evidence_tokens), invariant_id
