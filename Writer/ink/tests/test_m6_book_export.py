from __future__ import annotations

import json

import pytest

from ink.errors import DataIntegrityError
from ink.pipeline.book_rolling_check_orchestrator import BookRollingCheckOrchestrator
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.pipeline.export_orchestrator import ExportOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from ink.time import now_utc_iso
from test_m5_chapter_review import make_soft_sealed_chapter


def test_book_rolling_check_interval() -> None:
    conn = make_accepted_chapter()
    orchestrator = BookRollingCheckOrchestrator(conn)

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
    ChapterReviewOrchestrator(conn).review_chapter(1, 1, int(ids["run_id"]))

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


def make_accepted_chapter():
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    ChapterReviewOrchestrator(conn).review_chapter(1, 1, int(ids["run_id"]))
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


def _ids(conn):
    row = conn.execute(
        "SELECT shot_id, run_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
    ).fetchone()
    return {"shot_id": row[0], "run_id": row[1]}
