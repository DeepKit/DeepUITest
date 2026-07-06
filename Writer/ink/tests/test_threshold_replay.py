from __future__ import annotations

import json
from pathlib import Path

from ink.database import connect
from ink.threshold_replay import SHOT_DIMENSION_COLUMNS, build_threshold_replay_record
from ink.tools.replay_thresholds import main as replay_thresholds_main
from test_schema_contract import NOW, insert_minimal_draft, make_schema_db


def test_threshold_replay_record_summarizes_candidate_thresholds() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    _insert_jury_aggregate(conn, ids, final_score=82, median_score=70, is_winner=1)
    _insert_chapter_review(conn, score=76)
    _insert_book_check(conn, score=78)
    _insert_soft_gate_counter(conn, logical_shot_id="shot-001", gate_name="reader_pull", n=2)
    _insert_soft_gate_counter(conn, logical_shot_id="shot-002", gate_name="chapter_hook", n=3)
    _insert_accept_quality_report(conn, reader_score=80, blind_pass_count=2)

    record = build_threshold_replay_record(
        conn,
        project_id=1,
        shot_quality_floor=85,
        dimension_floor=65,
        chapter_quality_floor=77,
        book_quality_floor=77,
        reader_pull_floor=85,
        blind_review_min_passes=2,
        soft_gate_redo_n=2,
        soft_gate_fail_n=3,
    )

    assert record["schema_version"] == "ink.threshold_replay.v1"
    assert record["thresholds"]["shot_quality_floor"] == 85
    assert record["shot_quality"] == {
        "total": 1,
        "pass_count": 0,
        "fail_count": 1,
        "winner_count": 1,
        "winner_pass_count": 0,
        "winner_fail_count": 1,
    }
    assert record["chapter_quality"] == {"total": 1, "pass_count": 0, "fail_count": 1}
    assert record["book_quality"] == {"total": 1, "pass_count": 1, "fail_count": 0}
    assert record["reader_blind"] == {
        "total": 1,
        "reader_pull_pass_count": 0,
        "reader_pull_fail_count": 1,
        "blind_review_pass_count": 1,
        "blind_review_fail_count": 0,
    }
    assert record["soft_gate_n"] == {"total": 2, "redo_trigger_count": 2, "fail_trigger_count": 1}


def test_replay_thresholds_tool_writes_jsonl(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    output = tmp_path / "manual" / "thresholds.jsonl"
    conn = connect(db_path, initialize=True)
    try:
        insert_minimal_draft(conn)
        conn.commit()
    finally:
        conn.close()

    assert replay_thresholds_main(["--db", str(db_path), "--output", str(output), "--project-id", "1"]) == 0

    record = json.loads(output.read_text(encoding="utf-8").splitlines()[0])
    assert record["schema_version"] == "ink.threshold_replay.v1"
    assert record["project_id"] == 1


def _insert_jury_aggregate(conn, ids, *, final_score: int, median_score: int, is_winner: int) -> None:
    columns = ", ".join(SHOT_DIMENSION_COLUMNS)
    placeholders = ", ".join(["?"] * len(SHOT_DIMENSION_COLUMNS))
    conn.execute(
        f"""
        INSERT INTO writing_jury_aggregates
            (shot_id, draft_id, shot_contract_id, jury_round_used, judge_count,
             {columns}, weight_used, final_score, quality_gate_passed,
             quality_gate_reasons, judge_disagreement_max, is_winner, evaluated_at)
        VALUES (?, ?, ?, 1, 3, {placeholders}, '{{}}', ?, 1, '[]', 5, ?, ?)
        """,
        (
            ids["shot_id"],
            ids["draft_id"],
            ids["shot_contract_id"],
            *([median_score] * len(SHOT_DIMENSION_COLUMNS)),
            final_score,
            is_winner,
            NOW,
        ),
    )


def _insert_chapter_review(conn, *, score: int) -> None:
    conn.execute(
        """
        INSERT INTO writing_chapter_reviews
            (project_id, chapter_id, run_id, status,
             chapter_continuity_hard, pov_consistency, character_consistency,
             chapter_hook_soft, rhythm_curve, motif_density, info_gap_lifecycle,
             quality_gate_passed, blocking_issues, reviewed_at)
        VALUES (1, 1, 20, 'pending', ?, ?, ?, ?, ?, ?, ?, 1, '[]', ?)
        """,
        (score, score, score, score, score, score, score, NOW),
    )


def _insert_book_check(conn, *, score: int) -> None:
    conn.execute(
        """
        INSERT INTO writing_book_check_results
            (project_id, check_sequence, chapter_range_start, chapter_range_end,
             longline_suspense_closure, character_arc_completeness, motif_echo_density,
             theme_sublimation, global_rhythm_curve, foreshadow_recovery,
             is_incremental, issues, blocking_issue_count, quality_gate_passed, created_at)
        VALUES (1, 1, 1, 1, ?, ?, ?, ?, ?, ?, 0, '[]', 0, 1, ?)
        """,
        (score, score, score, score, score, score, NOW),
    )


def _insert_soft_gate_counter(conn, *, logical_shot_id: str, gate_name: str, n: int) -> None:
    conn.execute(
        """
        INSERT INTO writing_soft_gate_counters
            (project_id, logical_shot_id, gate_name, n, last_incremented_at, last_level)
        VALUES (1, ?, ?, ?, ?, 1)
        """,
        (logical_shot_id, gate_name, n, NOW),
    )


def _insert_accept_quality_report(conn, *, reader_score: int, blind_pass_count: int) -> None:
    conn.execute(
        """
        INSERT INTO writing_human_decisions
            (project_id, decision_type, actor, reason, preconditions_json,
             quality_report_json, hard_quality_override, created_at)
        VALUES (1, 'accept', 'author', 'accepted', '{}', ?, 0, ?)
        """,
        (
            json.dumps(
                {
                    "blind_review_passed": blind_pass_count > 0,
                    "blind_review_pass_count": blind_pass_count,
                    "would_continue_reading_score": reader_score,
                },
                sort_keys=True,
            ),
            NOW,
        ),
    )
