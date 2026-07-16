from __future__ import annotations

import json

import pytest

from ink.errors import DataIntegrityError
from ink.core.llm_gateway import LLMGateway, MockProvider
from ink.core.text_repository import TextRepository
from ink.pipeline.book_rolling_check_orchestrator import BookRollingCheckOrchestrator
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.pipeline.export_orchestrator import ExportOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from ink.time import now_utc_iso
from factories import NOW, make_schema_db
from test_m5_chapter_review import make_soft_sealed_chapter


def _review_gateway(conn) -> LLMGateway:
    """MockProvider 默认对 chapter_review:/book_check: 前缀返回全过 JSON（92 + 空 issues）。"""
    return LLMGateway(conn, provider=MockProvider())


def test_book_rolling_check_interval() -> None:
    conn = make_accepted_chapter()
    orchestrator = BookRollingCheckOrchestrator(conn, _review_gateway(conn))

    assert orchestrator.run_if_due(1, 1) is None
    conn.execute("UPDATE writing_projects SET chapter_rolling_check_interval = 1 WHERE project_id = 1")
    result = orchestrator.run_if_due(1, 1)
    second = orchestrator.run_if_due(1, 1)

    assert result is not None
    assert result.chapter_range_start == 1
    assert result.chapter_range_end == 1
    assert result.quality_gate_passed is True
    assert second == result
    assert conn.execute("SELECT count(*) FROM writing_book_check_results").fetchone()[0] == 1


def test_book_blocking_issue_blocks_accept_export() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    _insert_book_blocking_result(conn)
    ChapterReviewOrchestrator(conn, _review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))

    with pytest.raises(DataIntegrityError):
        HumanReviewOrchestrator(conn).accept_chapter(
            1,
            1,
            int(ids["run_id"]),
            actor="author",
            reason="blocked by book check",
        )
    with pytest.raises(DataIntegrityError):
        ExportOrchestrator(conn).export_project(1)

    assert conn.execute("SELECT count(*) FROM writing_human_decisions").fetchone()[0] == 0
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "soft_sealed"


def test_export_accepted_only() -> None:
    conn = make_accepted_chapter()
    conn.execute(
        """
        UPDATE writing_shot_revisions
        SET text = '[[STRUCT:drop]] polished text <struct>drop</struct>'
        WHERE sealed_by = 'chapter_hard'
        """
    )

    artifact = ExportOrchestrator(conn).export_project(1)

    assert artifact == "polished text"
    assert "[[STRUCT" not in artifact
    assert "<struct>" not in artifact
    event = conn.execute("SELECT event_type, event_payload FROM writing_runtime_events ORDER BY event_id DESC LIMIT 1").fetchone()
    assert event[0] == "EXPORT_COMPLETED"
    assert json.loads(event[1]) == {"chapter_count": 1, "shot_count": 1}


def test_four_axis_isolation() -> None:
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'axis-demo', 'Axis Demo', '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
        """,
        (NOW,),
    )
    conn.execute("INSERT INTO writing_sessions (session_id, project_id, started_at) VALUES (10, 1, ?)", (NOW,))
    conn.execute(
        """
        INSERT INTO writing_runs
            (run_id, project_id, session_id, run_attempt, started_at, status)
        VALUES (20, 1, 10, 1, ?, 'running'), (21, 1, 10, 2, ?, 'running')
        """,
        (NOW, NOW),
    )
    for shot_id, run_id, status in [("shot-001@20", 20, "soft_sealed"), ("shot-001@21", 21, "hard_sealed")]:
        conn.execute(
            """
            INSERT INTO writing_shots
                (shot_id, project_id, chapter_id, run_id, logical_shot_id, status, created_at, updated_at)
            VALUES (?, 1, 1, ?, 'shot-001', ?, ?, ?)
            """,
            (shot_id, run_id, status, NOW, NOW),
        )
    repo = TextRepository(conn)
    repo.write_revision("shot-001@20", 20, "old soft text", seal="shot_soft")
    repo.write_revision("shot-001@21", 21, "new accepted text", seal="chapter_hard")
    _insert_review(conn, run_id=20, status="rejected", quality_gate_passed=1)
    _insert_review(conn, run_id=21, status="accepted", quality_gate_passed=1)

    artifact = ExportOrchestrator(conn).export_project(1)

    assert artifact == "new accepted text"
    assert conn.execute(
        "SELECT text FROM v_current_text WHERE shot_id = 'shot-001@20'"
    ).fetchone()[0] == "old soft text"
    assert conn.execute(
        "SELECT text FROM v_current_text WHERE shot_id = 'shot-001@21'"
    ).fetchone()[0] == "new accepted text"


def make_accepted_chapter():
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    ChapterReviewOrchestrator(conn, _review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))
    HumanReviewOrchestrator(conn).accept_chapter(
        1,
        1,
        int(ids["run_id"]),
        actor="author",
        reason="chapter quality passed",
    )
    return conn


def _insert_book_blocking_result(conn) -> None:
    conn.execute(
        """
        INSERT INTO writing_book_check_results
            (project_id, check_sequence, chapter_range_start, chapter_range_end,
             longline_suspense_closure, character_arc_completeness, motif_echo_density,
             theme_sublimation, global_rhythm_curve, foreshadow_recovery,
             is_incremental, issues, blocking_issue_count, quality_gate_passed, created_at)
        VALUES (1, 1, 1, 1, 82, 82, 82, 82, 82, 82, 0, ?, 1, 0, ?)
        """,
        (
            json.dumps([{"severity": "blocking", "code": "manual_block"}], sort_keys=True),
            now_utc_iso(),
        ),
    )


def _insert_review(conn, *, run_id: int, status: str, quality_gate_passed: int) -> None:
    conn.execute(
        """
        INSERT INTO writing_chapter_reviews
            (project_id, chapter_id, run_id, status,
             chapter_continuity_hard, pov_consistency, character_consistency,
             chapter_hook_soft, rhythm_curve, motif_density, info_gap_lifecycle,
             chapter_coherence, quality_gate_passed, blocking_issues, reviewed_at)
        VALUES (1, 1, ?, ?, 82, 82, 82, 82, 82, 82, 82, 82, ?, '[]', ?)
        """,
        (run_id, status, quality_gate_passed, NOW),
    )


def _ids(conn):
    row = conn.execute(
        "SELECT shot_id, run_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
    ).fetchone()
    return {"shot_id": row[0], "run_id": row[1]}

