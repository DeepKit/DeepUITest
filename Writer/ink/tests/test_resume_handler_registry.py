from __future__ import annotations

import json
from pathlib import Path

import pytest

from ink.cli import main
from ink.core.llm_gateway import LLMGateway
from ink.core.resume import ResumeManager
from ink.errors import DataIntegrityError
from ink.pipeline.import_orchestrator import ImportOrchestrator
from ink.pipeline.resume_handlers import build_non_shot_resume_handlers, build_shot_resume_handlers
from ink.pipeline.write_orchestrator import WriteOrchestrator
from test_m5_chapter_review import make_soft_sealed_chapter
from test_m6_book_export import make_accepted_chapter
from test_m6_import import make_import_project
from test_m3_writer_pipeline import RecordingDraftProvider, make_prompt_compiled_shot
from factories import make_schema_db


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


def test_non_shot_resume_handler_registry_covers_session_level_actions() -> None:
    handlers = build_non_shot_resume_handlers(make_schema_db())

    assert {"chapter_review", "book_check", "import_finalize"} <= set(handlers)


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


def test_non_shot_resume_executes_chapter_review() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)

    result = ResumeManager(conn).execute_resume_point(
        {"phase": "chapter_review", "project_id": 1, "chapter_id": 1, "run_id": ids["run_id"]},
        build_non_shot_resume_handlers(conn),
    )

    assert result.quality_gate_passed is True
    assert conn.execute("SELECT count(*) FROM writing_chapter_reviews WHERE status = 'pending'").fetchone()[0] == 1


def test_non_shot_resume_executes_book_check() -> None:
    conn = make_accepted_chapter()
    conn.execute("UPDATE writing_projects SET chapter_rolling_check_interval = 1 WHERE project_id = 1")

    result = ResumeManager(conn).execute_resume_point(
        {"phase": "book_check", "project_id": 1, "up_to_chapter": 1},
        build_non_shot_resume_handlers(conn),
    )

    assert result is not None
    assert result.chapter_range_end == 1
    assert conn.execute("SELECT count(*) FROM writing_book_check_results").fetchone()[0] == 1


def test_non_shot_resume_executes_import_finalize_once(tmp_path: Path) -> None:
    conn = make_import_project()
    source_root = tmp_path / "source"
    source_root.mkdir()
    (source_root / "chapter-01.md").write_text("first version", encoding="utf-8")
    dry_run = ImportOrchestrator(conn).dry_run(1, str(source_root))
    payload = {
        "phase": "import_finalize",
        "import_run_id": dry_run.import_run_id,
        "actor": "author",
        "reason": "resume import finalize",
    }
    manager = ResumeManager(conn)

    first = manager.execute_resume_point(payload, build_non_shot_resume_handlers(conn))
    second = manager.execute_resume_point(payload, build_non_shot_resume_handlers(conn))

    assert second == first
    assert conn.execute("SELECT count(*) FROM writing_import_decisions").fetchone()[0] == 1
    assert conn.execute("SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'import_finalize'").fetchone()[0] == 1


def test_non_shot_resume_rejects_invalid_payload() -> None:
    manager = ResumeManager(make_schema_db())
    handlers = build_non_shot_resume_handlers(make_schema_db())

    with pytest.raises(DataIntegrityError, match="project_id"):
        manager.execute_resume_point({"phase": "chapter_review", "chapter_id": 1, "run_id": 20}, handlers)
    with pytest.raises(DataIntegrityError, match="handler"):
        manager.execute_resume_point({"phase": "drafting"}, handlers)
    with pytest.raises(DataIntegrityError, match="JSON object"):
        manager.parse_resume_point("[]")


def test_cli_resume_executes_session_level_chapter_review(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"

    assert main(["--db", str(db_path), "init", "--code", "session-resume", "--title", "Session Resume"]) == 0
    assert main(["--db", str(db_path), "setup", "--chapters", "1"]) == 0
    assert main(["--db", str(db_path), "write", "--chapter", "1"]) == 0
    _update_cli_db(
        db_path,
        "UPDATE writing_sessions SET crashed = 1, resume_point = ? WHERE session_id = 1",
        (
            json.dumps(
                {"phase": "chapter_review", "project_id": 1, "chapter_id": 1, "run_id": 1},
                sort_keys=True,
            ),
        ),
    )

    assert main(["--db", str(db_path), "resume", "--session-id", "1"]) == 0

    assert _scalar(db_path, "SELECT count(*) FROM writing_chapter_reviews WHERE status = 'pending'") == 1
    assert _scalar(db_path, "SELECT crashed FROM writing_sessions WHERE session_id = 1") == 0
    assert _scalar(db_path, "SELECT resume_point FROM writing_sessions WHERE session_id = 1") is None


def _ids(conn):
    row = conn.execute(
        "SELECT shot_id, run_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
    ).fetchone()
    return {"shot_id": row[0], "run_id": row[1]}


def _update_cli_db(db_path: Path, sql: str, params: tuple[object, ...]) -> None:
    import sqlite3

    conn = sqlite3.connect(db_path)
    try:
        conn.execute(sql, params)
        conn.commit()
    finally:
        conn.close()


def _scalar(db_path: Path, sql: str):
    import sqlite3

    conn = sqlite3.connect(db_path)
    try:
        return conn.execute(sql).fetchone()[0]
    finally:
        conn.close()

