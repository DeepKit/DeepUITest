from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass

from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


BOOK_CHECK_DIMENSIONS = (
    "longline_suspense_closure",
    "character_arc_completeness",
    "motif_echo_density",
    "theme_sublimation",
    "global_rhythm_curve",
    "foreshadow_recovery",
)


@dataclass(frozen=True)
class BookCheckResult:
    check_run_id: int
    project_id: int
    chapter_range_start: int
    chapter_range_end: int
    blocking_issue_count: int
    quality_gate_passed: bool


class BookRollingCheckOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def run_if_due(self, project_id: int, up_to_chapter: int) -> BookCheckResult | None:
        interval = _rolling_interval(self.conn, project_id)
        if up_to_chapter % interval != 0:
            return None

        existing = _load_check_for_chapter(self.conn, project_id, up_to_chapter)
        if existing is not None:
            return existing

        last_end = _last_checked_chapter(self.conn, project_id)
        chapter_range_start = 1 if last_end is None else last_end + 1
        texts = _load_accepted_texts(self.conn, project_id, up_to_chapter)
        if not texts:
            raise DataIntegrityError(f"no accepted text available for book check: {project_id}/{up_to_chapter}")

        issues = _book_issues(texts, up_to_chapter)
        blocking_count = sum(1 for issue in issues if issue["severity"] == "blocking")
        scores = _book_scores(project_id, self.conn)
        check_run_id = _insert_book_check(
            self.conn,
            project_id=project_id,
            chapter_range_start=chapter_range_start,
            chapter_range_end=up_to_chapter,
            scores=scores,
            issues=issues,
            blocking_count=blocking_count,
            is_incremental=0 if last_end is None else 1,
        )
        return BookCheckResult(
            check_run_id=check_run_id,
            project_id=project_id,
            chapter_range_start=chapter_range_start,
            chapter_range_end=up_to_chapter,
            blocking_issue_count=blocking_count,
            quality_gate_passed=blocking_count == 0,
        )


def has_blocking_issues(conn: sqlite3.Connection, project_id: int) -> bool:
    row = conn.execute(
        """
        SELECT blocking_issue_count
        FROM writing_book_check_results
        WHERE project_id = ?
        ORDER BY check_run_id DESC
        LIMIT 1
        """,
        (project_id,),
    ).fetchone()
    return row is not None and int(row[0]) > 0


def _rolling_interval(conn: sqlite3.Connection, project_id: int) -> int:
    row = conn.execute(
        "SELECT chapter_rolling_check_interval FROM writing_projects WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"project not found: {project_id}")
    return max(1, int(row[0]))


def _load_check_for_chapter(conn: sqlite3.Connection, project_id: int, up_to_chapter: int) -> BookCheckResult | None:
    row = conn.execute(
        """
        SELECT check_run_id, chapter_range_start, chapter_range_end, blocking_issue_count, quality_gate_passed
        FROM writing_book_check_results
        WHERE project_id = ? AND chapter_range_end = ?
        ORDER BY check_run_id DESC
        LIMIT 1
        """,
        (project_id, up_to_chapter),
    ).fetchone()
    if row is None:
        return None
    return BookCheckResult(
        check_run_id=int(row[0]),
        project_id=project_id,
        chapter_range_start=int(row[1]),
        chapter_range_end=int(row[2]),
        blocking_issue_count=int(row[3]),
        quality_gate_passed=bool(row[4]),
    )


def _last_checked_chapter(conn: sqlite3.Connection, project_id: int) -> int | None:
    row = conn.execute(
        "SELECT max(chapter_range_end) FROM writing_book_check_results WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    return None if row is None or row[0] is None else int(row[0])


def _load_accepted_texts(conn: sqlite3.Connection, project_id: int, up_to_chapter: int) -> list[str]:
    rows = conn.execute(
        """
        SELECT s.shot_id, s.run_id
        FROM writing_chapter_reviews r
        JOIN writing_shots s
          ON s.project_id = r.project_id
         AND s.chapter_id = r.chapter_id
         AND s.run_id = r.run_id
        WHERE r.project_id = ?
          AND r.chapter_id <= ?
          AND r.status = 'accepted'
          AND s.status = 'hard_sealed'
        ORDER BY r.chapter_id, s.logical_shot_id
        """,
        (project_id, up_to_chapter),
    ).fetchall()
    repo = TextRepository(conn)
    return [repo.read_current_text(str(row[0]), int(row[1])) for row in rows]


def _book_scores(project_id: int, conn: sqlite3.Connection) -> dict[str, float]:
    row = conn.execute("SELECT book_quality_floor FROM writing_projects WHERE project_id = ?", (project_id,)).fetchone()
    if row is None:
        raise DataIntegrityError(f"project not found: {project_id}")
    return {dimension: float(max(82, int(row[0]))) for dimension in BOOK_CHECK_DIMENSIONS}


def _book_issues(texts: list[str], up_to_chapter: int) -> list[dict[str, object]]:
    joined = "\n".join(texts)
    if "[book-blocking]" not in joined:
        return []
    return [
        {
            "severity": "blocking",
            "code": "book_blocking_marker",
            "chapter_range_end": up_to_chapter,
        }
    ]


def _insert_book_check(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    chapter_range_start: int,
    chapter_range_end: int,
    scores: dict[str, float],
    issues: list[dict[str, object]],
    blocking_count: int,
    is_incremental: int,
) -> int:
    sequence = _next_sequence(conn, project_id)
    cursor = conn.execute(
        """
        INSERT INTO writing_book_check_results
            (project_id, check_sequence, chapter_range_start, chapter_range_end,
             longline_suspense_closure, character_arc_completeness, motif_echo_density,
             theme_sublimation, global_rhythm_curve, foreshadow_recovery,
             is_incremental, issues, blocking_issue_count, quality_gate_passed, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            project_id,
            sequence,
            chapter_range_start,
            chapter_range_end,
            scores["longline_suspense_closure"],
            scores["character_arc_completeness"],
            scores["motif_echo_density"],
            scores["theme_sublimation"],
            scores["global_rhythm_curve"],
            scores["foreshadow_recovery"],
            is_incremental,
            json.dumps(issues, ensure_ascii=False, sort_keys=True),
            blocking_count,
            int(blocking_count == 0),
            now_utc_iso(),
        ),
    )
    return int(cursor.lastrowid)


def _next_sequence(conn: sqlite3.Connection, project_id: int) -> int:
    row = conn.execute(
        "SELECT COALESCE(MAX(check_sequence), 0) + 1 FROM writing_book_check_results WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    return int(row[0])
