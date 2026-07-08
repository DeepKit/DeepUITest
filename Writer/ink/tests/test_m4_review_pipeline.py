from __future__ import annotations

import json

import pytest

from ink.core.resume import ResumeManager
from ink.linting.orchestrator_signature import lint_shot_orchestrator_source
from ink.pipeline.gate_orchestrator import GateOrchestrator
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.jury_orchestrator import JuryOrchestrator
from ink.pipeline.polish_orchestrator import PolishOrchestrator
from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator
from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.errors import DataIntegrityError, LLMProviderError
from test_m3_writer_pipeline import FailFirstDraftProvider, RecordingDraftProvider, make_prompt_compiled_shot


def test_hard_gate_orchestrator_records_two_gate_eligibility_and_blocks_degraded() -> None:
    conn = make_prompt_compiled_shot()
    ids = _ids(conn)
    conn.execute("UPDATE writing_projects SET draft_count = 2 WHERE project_id = 1")
    WriteOrchestrator(conn, LLMGateway(conn, provider=FailFirstDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )

    candidates = HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))

    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "jury_scoring"
    degraded = conn.execute(
        """
        SELECT e.gate1_eligible, e.gate2_eligible
        FROM writing_draft_eligibility e
        JOIN writing_drafts d ON d.draft_id = e.draft_id
        WHERE d.degraded = 1
        """
    ).fetchone()
    assert degraded == (0, 0)
    assert all(not draft.degraded and not draft.is_deviant for draft in candidates)


def test_jury_scores_three_models_all_dimensions_and_selects_winner() -> None:
    conn = make_prompt_compiled_shot()
    _relax_llm_budget(conn)
    ids = _ids(conn)
    WriteOrchestrator(conn, LLMGateway(conn, provider=RecordingDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))

    winner = JuryOrchestrator(conn, _jury_gateway(conn)).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "winner_selected"
    assert winner.is_deviant is False
    assert winner.degraded is False
    assert conn.execute("SELECT count(*) FROM writing_jury_raw_scores").fetchone()[0] == 9
    assert conn.execute("SELECT count(*) FROM writing_jury_aggregates").fetchone()[0] == 3
    assert conn.execute("SELECT count(*) FROM writing_jury_aggregates WHERE is_winner = 1").fetchone()[0] == 1
    assert conn.execute(
        """
        SELECT count(*)
        FROM writing_jury_raw_scores r
        JOIN writing_drafts d ON d.draft_id = r.draft_id
        WHERE d.is_deviant = 1 OR d.degraded = 1 OR d.writer_model = r.judge_model
        """
    ).fetchone()[0] == 0


def test_redo_candidates_merge_with_existing_pool_and_can_flip_winner() -> None:
    conn = make_winner_selected_shot()
    ids = _ids(conn)
    original_winner = conn.execute(
        "SELECT draft_id FROM writing_jury_aggregates WHERE shot_id = ? AND is_winner = 1",
        (ids["shot_id"],),
    ).fetchone()[0]
    conn.execute(
        "UPDATE writing_shots SET redo_in_progress = 1 WHERE shot_id = ?",
        (ids["shot_id"],),
    )
    WriteOrchestrator(conn, LLMGateway(conn, provider=RedoBetterProvider())).produce_redo_candidates(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )

    winner = JuryOrchestrator(conn, _jury_gateway(conn)).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

    assert winner.draft_id != original_winner
    assert winner.retry_count == 1
    assert conn.execute(
        "SELECT redo_in_progress FROM writing_shots WHERE shot_id = ?",
        (ids["shot_id"],),
    ).fetchone()[0] == 0
    assert conn.execute("SELECT count(*) FROM writing_jury_aggregates WHERE is_winner = 1").fetchone()[0] == 1
    assert conn.execute(
        """
        SELECT count(*)
        FROM writing_drafts d
        JOIN writing_draft_eligibility e ON e.draft_id = d.draft_id
        WHERE d.retry_count > 0 AND e.gate1_eligible = 1 AND e.gate2_eligible = 1
        """
    ).fetchone()[0] == 2


def test_soft_gate_orchestrator_records_n1_counter_without_redo() -> None:
    conn = make_winner_selected_shot()
    ids = _ids(conn)
    _append_to_winner_text(conn, " [soft-fail]")

    result = GateOrchestrator(conn).run_soft_gates(str(ids["shot_id"]), int(ids["run_id"]))

    assert result.action == "block"
    assert result.passed is False
    assert [(failure.gate_name, failure.n, failure.level) for failure in result.failures] == [
        ("reader_pull", 1, 1)
    ]
    assert conn.execute(
        "SELECT status, redo_in_progress FROM writing_shots WHERE shot_id = ?",
        (ids["shot_id"],),
    ).fetchone() == ("winner_selected", 0)
    assert conn.execute(
        "SELECT n, last_level FROM writing_soft_gate_counters WHERE logical_shot_id = 'shot-001' AND gate_name = 'reader_pull'"
    ).fetchone() == (1, 1)
    snapshot = conn.execute(
        "SELECT soft_fail_counts_snapshot FROM writing_shots WHERE shot_id = ?",
        (ids["shot_id"],),
    ).fetchone()[0]
    assert json.loads(snapshot) == {"reader_pull": 1}
    assert conn.execute(
        "SELECT failure_category, failure_level, gate_name, soft_gate_n FROM writing_failure_attributions"
    ).fetchone() == ("soft", "soft_gate", "reader_pull", 1)


def test_soft_gate_orchestrator_sets_redo_in_progress_on_n2_idempotently() -> None:
    conn = make_winner_selected_shot()
    ids = _ids(conn)
    _append_to_winner_text(conn, " [soft-fail]")
    orchestrator = GateOrchestrator(conn)

    orchestrator.run_soft_gates(str(ids["shot_id"]), int(ids["run_id"]))
    result = orchestrator.run_soft_gates(str(ids["shot_id"]), int(ids["run_id"]))
    resumed = orchestrator.run_soft_gates(str(ids["shot_id"]), int(ids["run_id"]))

    assert result.action == "redo"
    assert result.failures[0].n == 2
    assert resumed.action == "redo_in_progress"
    assert conn.execute(
        "SELECT redo_in_progress FROM writing_shots WHERE shot_id = ?",
        (ids["shot_id"],),
    ).fetchone()[0] == 1
    resume_point = conn.execute(
        "SELECT resume_point FROM writing_shots WHERE shot_id = ?",
        (ids["shot_id"],),
    ).fetchone()[0]
    assert json.loads(resume_point) == {"gate_names": ["reader_pull"], "phase": "soft_gate"}
    assert conn.execute(
        "SELECT n FROM writing_soft_gate_counters WHERE logical_shot_id = 'shot-001' AND gate_name = 'reader_pull'"
    ).fetchone()[0] == 2
    assert ResumeManager(conn).resume_shot(10, str(ids["shot_id"]), int(ids["run_id"])) == "rerun_soft_gate_redo_drafting"


def test_quality_blocking_soft_gate_n3_fails_without_diagnostic_downgrade() -> None:
    conn = make_winner_selected_shot()
    ids = _ids(conn)
    _append_to_winner_text(conn, " [quality-blocking]")
    orchestrator = GateOrchestrator(conn)

    orchestrator.run_soft_gates(str(ids["shot_id"]), int(ids["run_id"]))
    orchestrator.run_soft_gates(str(ids["shot_id"]), int(ids["run_id"]))
    conn.execute(
        "UPDATE writing_shots SET redo_in_progress = 0 WHERE shot_id = ?",
        (ids["shot_id"],),
    )
    result = orchestrator.run_soft_gates(str(ids["shot_id"]), int(ids["run_id"]))

    assert result.action == "failed"
    assert result.failures[0].gate_class == "quality_blocking"
    assert result.failures[0].n == 3
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "failed"
    assert conn.execute(
        "SELECT max(soft_gate_n) FROM writing_failure_attributions WHERE gate_name = 'chapter_hook'"
    ).fetchone()[0] == 3


def test_creative_shot_passes_deviant_reference_to_jury_aggregate_without_scoring_deviant() -> None:
    conn = make_prompt_compiled_shot(creative=True)
    _relax_llm_budget(conn)
    ids = _ids(conn)
    WriteOrchestrator(conn, LLMGateway(conn, provider=RecordingDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    deviant_id = conn.execute(
        "SELECT draft_id FROM writing_drafts WHERE shot_id = ? AND is_deviant = 1",
        (ids["shot_id"],),
    ).fetchone()[0]
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))

    JuryOrchestrator(conn, _jury_gateway(conn)).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

    payload = conn.execute("SELECT weight_used FROM writing_jury_aggregates LIMIT 1").fetchone()[0]
    assert json.loads(payload)["_deviant_reference_draft_id"] == deviant_id
    assert conn.execute(
        """
        SELECT count(*)
        FROM writing_jury_raw_scores r
        JOIN writing_drafts d ON d.draft_id = r.draft_id
        WHERE d.is_deviant = 1
        """
    ).fetchone()[0] == 0


def test_polish_winner_writes_revision_and_returns_to_hard_gate() -> None:
    conn = make_winner_selected_shot()
    ids = _ids(conn)

    revision_id = PolishOrchestrator(conn, LLMGateway(conn, provider=PolishProvider())).polish_winner(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )

    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "hard_gate1"
    revision = conn.execute(
        "SELECT text, is_current, sealed_at FROM writing_shot_revisions WHERE revision_id = ?",
        (revision_id,),
    ).fetchone()
    assert revision == ("polished text", 0, None)
    polished_draft = conn.execute(
        """
        SELECT writer_model, retry_count, text
        FROM writing_drafts
        WHERE writer_model = 'smart-polish'
        """
    ).fetchone()
    assert polished_draft == ("smart-polish", 1, "polished text")
    assert conn.execute("SELECT count(*) FROM writing_ai_call_attempts WHERE call_type = 'polish'").fetchone()[0] == 1


def test_polish_blocks_when_smart_model_unavailable_without_downgrade() -> None:
    conn = make_winner_selected_shot()
    ids = _ids(conn)

    with pytest.raises(LLMProviderError):
        PolishOrchestrator(conn, LLMGateway(conn, provider=UnavailablePolishProvider())).polish_winner(
            str(ids["shot_id"]),
            int(ids["run_id"]),
        )

    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "polish_revision"
    assert conn.execute("SELECT count(*) FROM writing_shot_revisions WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == 0
    assert conn.execute("SELECT count(*) FROM writing_drafts WHERE writer_model = 'fast-fallback'").fetchone()[0] == 0


def test_polish_preserves_productive_deviations() -> None:
    conn = make_winner_selected_shot()
    ids = _ids(conn)
    _append_to_winner_text(conn, " [productive-deviation]")

    with pytest.raises(DataIntegrityError, match="productive marker"):
        PolishOrchestrator(conn, LLMGateway(conn, provider=PolishProvider())).polish_winner(
            str(ids["shot_id"]),
            int(ids["run_id"]),
        )

    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "polish_revision"
    assert conn.execute("SELECT count(*) FROM writing_shot_revisions WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == 0


def test_fact_anchor_gate_and_failure_attribution_clause_link() -> None:
    conn = make_prompt_compiled_shot()
    ids = _ids(conn)
    clause_id = conn.execute(
        """
        INSERT INTO writing_contract_clauses
            (project_id, shot_contract_id, clause_scope, clause_key, clause_text, severity, source_hash, created_at)
        VALUES (1, ?, 'shot', 'fact_anchor', 'confirmed anchor must remain true', 'hard', 'hash', ?)
        """,
        (ids["shot_contract_id"], "2026-07-04T00:00:00.000Z"),
    ).lastrowid
    conn.execute(
        """
        INSERT INTO writing_fact_anchors
            (project_id, shot_id, fact_text, confidence, status, created_at)
        VALUES (1, ?, 'the archive key is brass', 1.0, 'confirmed', ?)
        """,
        (ids["shot_id"], "2026-07-04T00:00:00.000Z"),
    )
    WriteOrchestrator(conn, LLMGateway(conn, provider=FactViolationDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )

    candidates = HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))

    assert candidates == []
    assert conn.execute(
        "SELECT count(*) FROM writing_draft_eligibility WHERE gate2_fact_anchor = 0 AND gate2_eligible = 0"
    ).fetchone()[0] == 4
    rows = conn.execute(
        """
        SELECT DISTINCT contract_clause_id, gate_name, failure_level
        FROM writing_failure_attributions
        WHERE shot_id = ?
        """,
        (ids["shot_id"],),
    ).fetchall()
    assert rows == [(clause_id, "fact_anchor", "hard_gate2")]


def test_unpolished_winner_cannot_soft_seal() -> None:
    conn = make_winner_selected_shot()
    ids = _ids(conn)

    with pytest.raises(DataIntegrityError):
        SoftSealOrchestrator(conn).soft_seal_if_polished(str(ids["shot_id"]), int(ids["run_id"]))

    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "winner_selected"
    assert conn.execute("SELECT count(*) FROM writing_shot_revisions WHERE sealed_by = 'shot_soft'").fetchone()[0] == 0


def test_polished_winner_repasses_quality_before_soft_seal() -> None:
    conn = make_winner_selected_shot()
    ids = _ids(conn)
    PolishOrchestrator(conn, LLMGateway(conn, provider=PolishProvider())).polish_winner(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))

    winner = JuryOrchestrator(conn, _jury_gateway(conn)).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))
    revision_id = SoftSealOrchestrator(conn).soft_seal_if_polished(str(ids["shot_id"]), int(ids["run_id"]))

    assert winner.writer_model == "smart-polish"
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "soft_sealed"
    revision = conn.execute(
        """
        SELECT text, sealed_by, is_current, sealed_at
        FROM writing_shot_revisions
        WHERE revision_id = ?
        """,
        (revision_id,),
    ).fetchone()
    assert revision[:3] == ("polished text", "shot_soft", 0)
    assert revision[3] is not None
    assert conn.execute(
        "SELECT quality_gate_passed FROM writing_jury_aggregates WHERE is_winner = 1"
    ).fetchone()[0] == 1
    assert conn.execute("SELECT text FROM v_current_text WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "polished text"


def test_jury_quality_floor_failure_cannot_select_winner() -> None:
    conn = make_prompt_compiled_shot()
    _relax_llm_budget(conn)
    ids = _ids(conn)
    conn.execute("UPDATE writing_projects SET auto_retry_on_hard_failure = 0 WHERE project_id = 1")
    WriteOrchestrator(conn, LLMGateway(conn, provider=LowQualityDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))

    with pytest.raises(DataIntegrityError):
        JuryOrchestrator(conn, _jury_gateway(conn, draft_marker="low-quality")).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "failed"
    rows = conn.execute(
        "SELECT quality_gate_passed, quality_gate_reasons, is_winner FROM writing_jury_aggregates"
    ).fetchall()
    assert rows
    assert all(row[0] == 0 and row[2] == 0 for row in rows)
    assert all("final_score_below_shot_quality_floor" in row[1] for row in rows)


def test_jury_quality_failure_auto_retries_and_selects_retry_winner() -> None:
    conn = make_prompt_compiled_shot()
    _relax_llm_budget(conn)
    ids = _ids(conn)
    conn.execute("UPDATE writing_projects SET min_eligible_candidates = 2, max_retries_per_gate = 1 WHERE project_id = 1")
    WriteOrchestrator(conn, LLMGateway(conn, provider=LowQualityDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))

    winner = JuryOrchestrator(conn, _jury_gateway(conn)).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

    assert winner.retry_count == 1
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "winner_selected"
    assert conn.execute("SELECT retry_count FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == 1
    assert conn.execute("SELECT count(*) FROM writing_drafts WHERE retry_count = 1").fetchone()[0] == 2
    assert conn.execute("SELECT count(*) FROM writing_jury_aggregates WHERE quality_gate_passed = 0").fetchone()[0] == 3
    assert conn.execute("SELECT count(*) FROM writing_jury_aggregates WHERE quality_gate_passed = 1").fetchone()[0] == 2


def test_jury_dimension_floor_failure_cannot_select_winner() -> None:
    conn = make_prompt_compiled_shot()
    _relax_llm_budget(conn)
    ids = _ids(conn)
    conn.execute("UPDATE writing_projects SET auto_retry_on_hard_failure = 0 WHERE project_id = 1")
    WriteOrchestrator(conn, LLMGateway(conn, provider=DimensionFailDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))

    with pytest.raises(DataIntegrityError):
        JuryOrchestrator(conn, _jury_gateway(conn, draft_marker="dimension-fail")).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

    rows = conn.execute("SELECT scene_visual_median, quality_gate_reasons, is_winner FROM writing_jury_aggregates").fetchall()
    assert rows
    assert all(row[0] == 60 and row[2] == 0 for row in rows)
    assert all("dimension_below_floor" in row[1] for row in rows)


def test_jury_disagreement_failure_cannot_select_winner() -> None:
    conn = make_prompt_compiled_shot()
    _relax_llm_budget(conn)
    ids = _ids(conn)
    conn.execute("UPDATE writing_projects SET auto_retry_on_hard_failure = 0 WHERE project_id = 1")
    WriteOrchestrator(conn, LLMGateway(conn, provider=DisagreementDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))

    with pytest.raises(DataIntegrityError):
        JuryOrchestrator(conn, _jury_gateway(conn, draft_marker="disagreement")).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

    rows = conn.execute("SELECT judge_disagreement_max, quality_gate_reasons, is_winner FROM writing_jury_aggregates").fetchall()
    assert rows
    assert all(row[0] == 30 and row[2] == 0 for row in rows)
    assert all("judge_disagreement_exceeded" in row[1] for row in rows)


def test_m4_orchestrator_entrypoint_signatures_lint_clean() -> None:
    from ink.pipeline import (
        gate_orchestrator,
        hard_gate_orchestrator,
        jury_orchestrator,
        polish_orchestrator,
        soft_seal_orchestrator,
    )

    gate_source = gate_orchestrator.__loader__.get_source(gate_orchestrator.__name__)
    hard_gate_source = hard_gate_orchestrator.__loader__.get_source(hard_gate_orchestrator.__name__)
    jury_source = jury_orchestrator.__loader__.get_source(jury_orchestrator.__name__)
    polish_source = polish_orchestrator.__loader__.get_source(polish_orchestrator.__name__)
    soft_seal_source = soft_seal_orchestrator.__loader__.get_source(soft_seal_orchestrator.__name__)
    assert lint_shot_orchestrator_source(gate_source, "gate_orchestrator.py") == []
    assert lint_shot_orchestrator_source(hard_gate_source, "hard_gate_orchestrator.py") == []
    assert lint_shot_orchestrator_source(jury_source, "jury_orchestrator.py") == []
    assert lint_shot_orchestrator_source(polish_source, "polish_orchestrator.py") == []
    assert lint_shot_orchestrator_source(soft_seal_source, "soft_seal_orchestrator.py") == []


def _ids(conn):
    row = conn.execute(
        "SELECT shot_id, run_id, shot_contract_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
    ).fetchone()
    return {"shot_id": row[0], "run_id": row[1], "shot_contract_id": row[2]}


def make_winner_selected_shot():
    conn = make_prompt_compiled_shot()
    _relax_llm_budget(conn)
    ids = _ids(conn)
    WriteOrchestrator(conn, LLMGateway(conn, provider=RecordingDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))
    JuryOrchestrator(conn, _jury_gateway(conn)).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))
    return conn


def _append_to_winner_text(conn, marker: str) -> None:
    conn.execute(
        """
        UPDATE writing_drafts
        SET text = text || ?, byte_count = byte_count + ?
        WHERE draft_id = (
            SELECT draft_id
            FROM writing_jury_aggregates
            WHERE is_winner = 1
        )
        """,
        (marker, len(marker.encode("utf-8"))),
    )


class LowQualityDraftProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        return ModelResult(
            text=f"[low-quality] {model_name}:{idempotency_key}",
            model_name=model_name,
            token_input=1,
            token_output=1,
        )


class DimensionFailDraftProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        return ModelResult(
            text=f"[dimension-fail] {model_name}:{idempotency_key}",
            model_name=model_name,
            token_input=1,
            token_output=1,
        )


class DisagreementDraftProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        return ModelResult(
            text=f"[disagreement] {model_name}:{idempotency_key}",
            model_name=model_name,
            token_input=1,
            token_output=1,
        )


class PolishProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        assert "productive_deviations" in prompt_text
        return ModelResult(text="polished text", model_name=model_name, token_input=1, token_output=1)


class RedoBetterProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        return ModelResult(
            text=f"[redo-better] {model_name}:{idempotency_key}",
            model_name=model_name,
            token_input=1,
            token_output=1,
        )


class FactViolationDraftProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        return ModelResult(
            text=f"[fact-violation] {model_name}:{idempotency_key}",
            model_name=model_name,
            token_input=1,
            token_output=1,
        )


class UnavailablePolishProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        assert model_name == "smart-polish"
        raise RuntimeError("smart model unavailable")


# jury 真实化后的评分 mock provider：按 draft.text 里的桩标记 + idempotency_key 的 slot
# 返回 12 维评分 JSON，复现原桩评分语义（low-quality/dimension-fail/disagreement 不过 gate，
# redo-better/默认过 gate）。3 judge 各 slot 返回不同值以驱动 disagreement 判定。
_JURY_DIMS = (
    "scene_visual", "rhythm_pacing", "dialogue_subtext", "suspense_tension",
    "language_texture", "emotional_progression", "character_believability",
    "structure_landing", "reading_fluency", "motif_theme_fit", "chapter_continuity",
    "creative_boundary",
)


class JuryScoreProvider:
    """注入式 jury 评分 provider（测试用）。按 draft.text 标记 + slot 返回 12 维 JSON。

    jury 调用（``idempotency_key`` 以 ``jury:`` 开头）按 prompt_text 里的 draft 标记
    返回 12 维评分 JSON，复现原桩语义（low-quality/dimension-fail/disagreement 不过 gate，
    redo-better/默认过 gate）。三 judge 各 slot 返回不同值以驱动 disagreement 判定。

    draft/redo/quality-retry 调用（``idempotency_key`` 以 ``draft:`` / ``redo:`` /
    ``quality-retry:`` 开头）返回带标记的 draft 文本，使 jury retry 路径
    （``_handle_quality_retry_or_fail`` 用 ``WriteOrchestrator(self.conn, self.gateway)``
    复用 jury gateway 生成 retry draft）生成的 draft 也带对应标记，从而 jury 再评时
    返回对应低分→retry 仍 fail。``draft_marker`` 控制返回文本的标记：空串→无标记（过 gate）。
    """

    def __init__(self, *, draft_marker: str = "") -> None:
        self.draft_marker = draft_marker

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        # jury retry 路径复用本 gateway 生成 retry draft：draft/redo/quality-retry 调用
        # 返回带标记文本（复现原 draft provider 语义），使 retry draft 也带标记。
        if idempotency_key.startswith(("draft:", "redo:", "quality-retry:")):
            if self.draft_marker:
                text = f"[{self.draft_marker}] {model_name}:{idempotency_key}"
            else:
                text = f"scene text {model_name} {idempotency_key}"
            return ModelResult(text=text, model_name=model_name, token_input=1, token_output=1)

        slot = 2  # 默认中位 slot
        if ":r1:" in idempotency_key:
            slot = int(idempotency_key.rsplit(":r1:", 1)[1])
        if "[low-quality]" in prompt_text:
            # 原桩：final=70，全维 median=70 → 70<80 不过 shot_quality_floor（不触发 dimension）
            scores = {dim: 70 for dim in _JURY_DIMS}
        elif "[dimension-fail]" in prompt_text:
            # 原桩：final=84，全维 median=84，scene_visual=60<65 → dimension_below_floor
            scores = {dim: 84 for dim in _JURY_DIMS}
            scores["scene_visual"] = 60
        elif "[disagreement]" in prompt_text:
            # 原桩 offsets=(-14,0,16) on median 84 → slot1=70 / slot2=84 / slot3=100
            # median=84≥80 过 shot_quality_floor，但 disagreement=100-70=30>25 → fail
            base = {1: 70, 2: 84, 3: 100}[slot]
            scores = {dim: base for dim in _JURY_DIMS}
        elif "[redo-better]" in prompt_text:
            scores = {dim: 92 for dim in _JURY_DIMS}
        elif "[fact-violation]" in prompt_text:
            # fact-violation 不影响 jury 评分（gate 另判），给默认过 gate 分
            scores = {dim: 84 for dim in _JURY_DIMS}
        else:
            scores = {dim: 84 for dim in _JURY_DIMS}
        return ModelResult(
            text=json.dumps(scores, ensure_ascii=False),
            model_name=model_name,
            token_input=1,
            token_output=1,
        )


def _jury_gateway(conn, *, draft_marker: str = "") -> LLMGateway:
    """构造注入 JuryScoreProvider 的 gateway，供 m4/m5/m6 jury 测试复用。

    ``draft_marker`` 决定 retry draft 文本标记：空串（默认）→ 无标记 → jury 评 84 过 gate
    （用于 retry 后选 winner 的测试）；"low-quality" 等 → retry draft 带标记 → jury 评低分
    → retry 仍 fail（用于 retry-fail 测试）。
    """
    return LLMGateway(conn, provider=JuryScoreProvider(draft_marker=draft_marker))


def _relax_llm_budget(conn) -> None:
    """jury 真实化后每个 judge 调一次 gateway.call，3 draft×3 judge=9 次 jury 调用
    超 schema 默认 max_calls_per_shot=8 会触发 per_type_exceeded 熔断。测试放宽预算。"""
    conn.execute(
        "UPDATE writing_projects SET max_calls_per_shot = 50, max_total_llm_calls = 200, "
        "consecutive_failure_circuit_break = 100 WHERE project_id = 1"
    )

