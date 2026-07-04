from __future__ import annotations

from pathlib import Path


M0_INVARIANT_EVIDENCE = {
    "INV-CONTRACT-001": ["test_field_usage_lint", "lint_field_usage"],
    "INV-SQL-001": ["test_sql_access_lint", "lint_sql_access"],
    "INV-DDL-001": ["test_schema_executes_all_ddl"],
    "INV-CONFIG-001": ["test_project_config_validator"],
    "INV-TIME-001": ["test_now_utc_iso_format"],
    "INV-STATE-002": ["test_state_update_lint", "lint_state_updates"],
    "INV-REVISION-001": ["test_v_current_text"],
    "INV-LLM-003": ["test_llm_gateway_records_attempt", "lint_llm_access"],
    "INV-QUALITY-008": ["test_quality_report_schema_requires_evidence_and_defect_class"],
    "INV-JURY-SELF-001": ["test_jury_raw_scores_reject_self_judging"],
    "INV-JURY-ROUND-001": ["test_jury_raw_scores_support_base_and_escalated_rounds"],
    "INV-CHECKPOINT-001": ["test_session_checkpoints_allow_null_shot_id"],
}


def test_m0_invariants_have_executable_evidence() -> None:
    root = Path(__file__).resolve().parents[1]
    matrix = (root / "docs" / "invariant-traceability.md").read_text(encoding="utf-8")
    test_source = "\n".join(path.read_text(encoding="utf-8") for path in (root / "tests").glob("test_*.py"))
    lint_source = "\n".join(path.read_text(encoding="utf-8") for path in (root / "src" / "ink" / "linting").glob("*.py"))
    source = test_source + "\n" + lint_source

    for invariant_id, evidence_tokens in M0_INVARIANT_EVIDENCE.items():
        assert invariant_id in matrix
        assert any(token in source for token in evidence_tokens), invariant_id
