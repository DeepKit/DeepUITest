from __future__ import annotations

from ink.core.llm_gateway import LLMGateway
from ink.core.resume import ResumeManager
from ink.pipeline.resume_handlers import build_shot_resume_handlers
from ink.pipeline.write_orchestrator import WriteOrchestrator
from test_m3_writer_pipeline import RecordingDraftProvider, make_prompt_compiled_shot
from test_schema_contract import make_schema_db


def test_shot_resume_handler_registry_covers_current_m2_to_m4_actions() -> None:
    handlers = build_shot_resume_handlers(make_schema_db())

    assert {
        "start_from_scratch",
        "rerun_outline",
        "rerun_task_card",
        "rerun_prompt",
        "rerun_drafting",
        "rerun_soft_gate_redo_drafting",
        "rerun_hard_gate1",
        "rerun_hard_gate2",
        "rerun_jury",
        "rerun_soft_gate_redo_jury",
        "rerun_winner_select",
        "rerun_soft_gate",
        "rerun_polish_and_quality_gate",
    } <= set(handlers)


def test_resume_manager_executes_hard_gate_action_from_registry() -> None:
    conn = make_prompt_compiled_shot()
    ids = _ids(conn)
    WriteOrchestrator(conn, LLMGateway(conn, provider=RecordingDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    manager = ResumeManager(conn)
    action = manager.resume_shot(10, str(ids["shot_id"]), int(ids["run_id"]))

    result = manager.execute_resume_action(
        str(ids["shot_id"]),
        int(ids["run_id"]),
        action,
        build_shot_resume_handlers(conn),
    )

    assert action == "rerun_hard_gate1"
    assert len(result) == 3
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "jury_scoring"


def _ids(conn):
    row = conn.execute(
        "SELECT shot_id, run_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
    ).fetchone()
    return {"shot_id": row[0], "run_id": row[1]}
