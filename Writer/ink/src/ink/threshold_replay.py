from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from ink.time import now_utc_iso


SHOT_DIMENSION_COLUMNS = (
    "scene_visual_median",
    "rhythm_pacing_median",
    "dialogue_subtext_median",
    "suspense_tension_median",
    "language_texture_median",
    "emotional_progression_median",
    "character_believability_median",
    "structure_landing_median",
    "reading_fluency_median",
    "motif_theme_fit_median",
    "chapter_continuity_median",
    "creative_boundary_median",
)
CHAPTER_DIMENSION_COLUMNS = (
    "chapter_continuity_hard",
    "pov_consistency",
    "character_consistency",
    "chapter_hook_soft",
    "rhythm_curve",
    "motif_density",
    "info_gap_lifecycle",
    "chapter_coherence",
)
BOOK_DIMENSION_COLUMNS = (
    "longline_suspense_closure",
    "character_arc_completeness",
    "motif_echo_density",
    "theme_sublimation",
    "global_rhythm_curve",
    "foreshadow_recovery",
)


def build_threshold_replay_record(
    conn: sqlite3.Connection,
    *,
    project_id: int | None = None,
    shot_quality_floor: int | None = None,
    dimension_floor: int | None = None,
    chapter_quality_floor: int | None = None,
    book_quality_floor: int | None = None,
    reader_pull_floor: int | None = None,
    blind_review_min_passes: int | None = None,
    soft_gate_redo_n: int | None = None,
    soft_gate_fail_n: int | None = None,
) -> dict[str, object]:
    thresholds = _thresholds(
        conn,
        project_id=project_id,
        overrides={
            "shot_quality_floor": shot_quality_floor,
            "dimension_floor": dimension_floor,
            "chapter_quality_floor": chapter_quality_floor,
            "book_quality_floor": book_quality_floor,
            "reader_pull_floor": reader_pull_floor,
            "blind_review_min_passes": blind_review_min_passes,
            "soft_gate_redo_n": soft_gate_redo_n,
            "soft_gate_fail_n": soft_gate_fail_n,
        },
    )
    return {
        "schema_version": "ink.threshold_replay.v1",
        "generated_at": now_utc_iso(),
        "project_id": project_id,
        "thresholds": thresholds,
        "shot_quality": _shot_quality_summary(conn, project_id, thresholds),
        "chapter_quality": _chapter_quality_summary(conn, project_id, thresholds),
        "book_quality": _book_quality_summary(conn, project_id, thresholds),
        "reader_blind": _reader_blind_summary(conn, project_id, thresholds),
        "soft_gate_n": _soft_gate_summary(conn, project_id, thresholds),
    }


def append_jsonl_record(path: str | Path, record: dict[str, object]) -> None:
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(record, ensure_ascii=False, sort_keys=True))
        stream.write("\n")


def _thresholds(
    conn: sqlite3.Connection,
    *,
    project_id: int | None,
    overrides: dict[str, int | None],
) -> dict[str, int]:
    row = _project_threshold_row(conn, project_id)
    defaults = {
        "shot_quality_floor": 75,
        "dimension_floor": 60,
        "chapter_quality_floor": 75,
        "book_quality_floor": 75,
        "reader_pull_floor": 75,
        "blind_review_min_passes": 2,
        "soft_gate_redo_n": 2,
        "soft_gate_fail_n": 3,
    }
    if row is not None:
        defaults.update({key: int(row[key]) for key in defaults})
    return {key: int(overrides[key]) if overrides[key] is not None else value for key, value in defaults.items()}


def _project_threshold_row(conn: sqlite3.Connection, project_id: int | None) -> dict[str, object] | None:
    if project_id is None:
        cursor = conn.execute(
            """
            SELECT shot_quality_floor, dimension_floor, chapter_quality_floor, book_quality_floor,
                   reader_pull_floor, blind_review_min_passes, soft_gate_redo_n, soft_gate_fail_n
            FROM writing_projects
            ORDER BY project_id
            LIMIT 1
            """
        )
    else:
        cursor = conn.execute(
            """
            SELECT shot_quality_floor, dimension_floor, chapter_quality_floor, book_quality_floor,
                   reader_pull_floor, blind_review_min_passes, soft_gate_redo_n, soft_gate_fail_n
            FROM writing_projects
            WHERE project_id = ?
            """,
            (project_id,),
        )
    row = cursor.fetchone()
    if row is None:
        return None
    names = [column[0] for column in cursor.description]
    return dict(zip(names, row, strict=True))


def _shot_quality_summary(
    conn: sqlite3.Connection,
    project_id: int | None,
    thresholds: dict[str, int],
) -> dict[str, int]:
    rows = _query_dicts(
        conn,
        """
        SELECT a.final_score, a.is_winner,
               a.scene_visual_median, a.rhythm_pacing_median, a.dialogue_subtext_median,
               a.suspense_tension_median, a.language_texture_median, a.emotional_progression_median,
               a.character_believability_median, a.structure_landing_median, a.reading_fluency_median,
               a.motif_theme_fit_median, a.chapter_continuity_median, a.creative_boundary_median
        FROM writing_jury_aggregates a
        JOIN writing_shots s ON s.shot_id = a.shot_id
        WHERE (? IS NULL OR s.project_id = ?)
        """,
        (project_id, project_id),
    )
    pass_count = 0
    winner_pass_count = 0
    for row in rows:
        passed = float(row["final_score"]) >= thresholds["shot_quality_floor"] and min(
            float(row[column]) for column in SHOT_DIMENSION_COLUMNS
        ) >= thresholds["dimension_floor"]
        pass_count += int(passed)
        winner_pass_count += int(passed and int(row["is_winner"]) == 1)
    winner_count = sum(1 for row in rows if int(row["is_winner"]) == 1)
    return {
        "total": len(rows),
        "pass_count": pass_count,
        "fail_count": len(rows) - pass_count,
        "winner_count": winner_count,
        "winner_pass_count": winner_pass_count,
        "winner_fail_count": winner_count - winner_pass_count,
    }


def _chapter_quality_summary(
    conn: sqlite3.Connection,
    project_id: int | None,
    thresholds: dict[str, int],
) -> dict[str, int]:
    rows = _query_dicts(
        conn,
        """
        SELECT chapter_continuity_hard, pov_consistency, character_consistency,
               chapter_hook_soft, rhythm_curve, motif_density, info_gap_lifecycle,
               chapter_coherence
        FROM writing_chapter_reviews
        WHERE (? IS NULL OR project_id = ?)
        """,
        (project_id, project_id),
    )
    pass_count = sum(
        1
        for row in rows
        if all(row[column] is not None and int(row[column]) >= thresholds["chapter_quality_floor"] for column in CHAPTER_DIMENSION_COLUMNS)
    )
    return {"total": len(rows), "pass_count": pass_count, "fail_count": len(rows) - pass_count}


def _book_quality_summary(
    conn: sqlite3.Connection,
    project_id: int | None,
    thresholds: dict[str, int],
) -> dict[str, int]:
    rows = _query_dicts(
        conn,
        """
        SELECT longline_suspense_closure, character_arc_completeness, motif_echo_density,
               theme_sublimation, global_rhythm_curve, foreshadow_recovery, blocking_issue_count
        FROM writing_book_check_results
        WHERE (? IS NULL OR project_id = ?)
        """,
        (project_id, project_id),
    )
    pass_count = sum(
        1
        for row in rows
        if int(row["blocking_issue_count"]) == 0
        and all(row[column] is not None and float(row[column]) >= thresholds["book_quality_floor"] for column in BOOK_DIMENSION_COLUMNS)
    )
    return {"total": len(rows), "pass_count": pass_count, "fail_count": len(rows) - pass_count}


def _reader_blind_summary(
    conn: sqlite3.Connection,
    project_id: int | None,
    thresholds: dict[str, int],
) -> dict[str, int]:
    rows = _query_dicts(
        conn,
        """
        SELECT quality_report_json
        FROM writing_human_decisions
        WHERE decision_type = 'accept'
          AND (? IS NULL OR project_id = ?)
        """,
        (project_id, project_id),
    )
    reader_pass = 0
    blind_pass = 0
    for row in rows:
        payload = _json_object(row["quality_report_json"])
        reader_score = int(payload.get("would_continue_reading_score") or 0)
        blind_count = int(payload.get("blind_review_pass_count") or int(bool(payload.get("blind_review_passed"))))
        reader_pass += int(reader_score >= thresholds["reader_pull_floor"])
        blind_pass += int(blind_count >= thresholds["blind_review_min_passes"])
    return {
        "total": len(rows),
        "reader_pull_pass_count": reader_pass,
        "reader_pull_fail_count": len(rows) - reader_pass,
        "blind_review_pass_count": blind_pass,
        "blind_review_fail_count": len(rows) - blind_pass,
    }


def _soft_gate_summary(
    conn: sqlite3.Connection,
    project_id: int | None,
    thresholds: dict[str, int],
) -> dict[str, int]:
    rows = _query_dicts(
        conn,
        """
        SELECT n
        FROM writing_soft_gate_counters
        WHERE (? IS NULL OR project_id = ?)
        """,
        (project_id, project_id),
    )
    redo_count = sum(1 for row in rows if int(row["n"]) >= thresholds["soft_gate_redo_n"])
    fail_count = sum(1 for row in rows if int(row["n"]) >= thresholds["soft_gate_fail_n"])
    return {"total": len(rows), "redo_trigger_count": redo_count, "fail_trigger_count": fail_count}


def _query_dicts(conn: sqlite3.Connection, sql: str, params: tuple[object, ...]) -> list[dict[str, object]]:
    cursor = conn.execute(sql, params)
    names = [column[0] for column in cursor.description]
    return [dict(zip(names, row, strict=True)) for row in cursor.fetchall()]


def _json_object(value: object) -> dict[str, object]:
    if not isinstance(value, str) or not value:
        return {}
    payload = json.loads(value)
    return payload if isinstance(payload, dict) else {}
