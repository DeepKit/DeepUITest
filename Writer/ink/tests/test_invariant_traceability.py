from __future__ import annotations

from pathlib import Path


INVARIANT_EVIDENCE = {
    "INV-CONTRACT-001": ["test_field_usage_lint", "lint_field_usage"],
    "INV-SQL-001": ["test_sql_access_lint", "lint_sql_access"],
    "INV-DDL-001": ["test_schema_executes_all_ddl"],
    "INV-CONFIG-001": ["test_project_config_validator"],
    "INV-TIME-001": ["test_now_utc_iso_format"],
    "INV-STATE-001": ["test_state_machine_allows_legal_transition"],
    "INV-STATE-002": ["test_state_update_lint", "lint_state_updates"],
    "INV-REVISION-001": ["test_v_current_text"],
    "INV-REVISION-002": ["test_resume_manager"],
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
    "INV-QUALITY-011": ["test_polish_blocks_when_smart_model_unavailable_without_downgrade"],
    "INV-GATE-001": ["test_hard_gate_orchestrator_records_two_gate_eligibility"],
    "INV-GATE-002": ["test_hard_gate_orchestrator_records_two_gate_eligibility"],
    "INV-JURY-001": ["test_jury_scores_three_models_all_dimensions_and_selects_winner"],
    "INV-JURY-002": ["test_jury_scores_three_models_all_dimensions_and_selects_winner"],
}


def test_tracked_invariants_have_executable_evidence() -> None:
    root = Path(__file__).resolve().parents[1]
    matrix = (root / "docs" / "invariant-traceability.md").read_text(encoding="utf-8")
    test_source = "\n".join(path.read_text(encoding="utf-8") for path in (root / "tests").glob("test_*.py"))
    lint_source = "\n".join(path.read_text(encoding="utf-8") for path in (root / "src" / "ink" / "linting").glob("*.py"))
    source = test_source + "\n" + lint_source

    for invariant_id, evidence_tokens in INVARIANT_EVIDENCE.items():
        assert invariant_id in matrix
        assert any(token in source for token in evidence_tokens), invariant_id
