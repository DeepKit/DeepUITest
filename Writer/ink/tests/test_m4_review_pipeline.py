from __future__ import annotations

from ink.linting.orchestrator_signature import lint_shot_orchestrator_source
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.jury_orchestrator import JuryOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator
from ink.core.llm_gateway import LLMGateway
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
    ids = _ids(conn)
    WriteOrchestrator(conn, LLMGateway(conn, provider=RecordingDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))

    winner = JuryOrchestrator(conn).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

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


def test_m4_orchestrator_entrypoint_signatures_lint_clean() -> None:
    from ink.pipeline import hard_gate_orchestrator, jury_orchestrator

    hard_gate_source = hard_gate_orchestrator.__loader__.get_source(hard_gate_orchestrator.__name__)
    jury_source = jury_orchestrator.__loader__.get_source(jury_orchestrator.__name__)
    assert lint_shot_orchestrator_source(hard_gate_source, "hard_gate_orchestrator.py") == []
    assert lint_shot_orchestrator_source(jury_source, "jury_orchestrator.py") == []


def _ids(conn):
    row = conn.execute(
        "SELECT shot_id, run_id, shot_contract_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
    ).fetchone()
    return {"shot_id": row[0], "run_id": row[1], "shot_contract_id": row[2]}
