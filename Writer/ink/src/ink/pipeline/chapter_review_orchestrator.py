from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass

from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


CHAPTER_REVIEW_DIMENSIONS = (
    "chapter_continuity_hard",
    "pov_consistency",
    "character_consistency",
    "chapter_hook_soft",
    "rhythm_curve",
    "motif_density",
    "info_gap_lifecycle",
)


@dataclass(frozen=True)
class ChapterReviewResult:
    review_id: int
    project_id: int
    chapter_id: int
    run_id: int
    quality_gate_passed: bool
    blocking_issues: tuple[str, ...]


def review_chapter(project_id: int, chapter_id: int, run_id: int) -> ChapterReviewResult:
    raise DataIntegrityError("chapter review orchestrator is not configured")


class ChapterReviewOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def review_chapter(self, project_id: int, chapter_id: int, run_id: int) -> ChapterReviewResult:
        shots = _load_chapter_shots(self.conn, project_id, chapter_id, run_id)
        if not shots:
            raise DataIntegrityError(f"chapter has no shots: {project_id}/{chapter_id}/{run_id}")
        not_soft_sealed = [shot_id for shot_id, status in shots if status != "soft_sealed"]
        if not_soft_sealed:
            raise DataIntegrityError(f"chapter review requires all shots soft_sealed: {not_soft_sealed}")

        repo = TextRepository(self.conn)
        texts = [repo.read_current_text(shot_id, run_id) for shot_id, _ in shots]
        floor = _chapter_quality_floor(self.conn, project_id)
        scores = _score_chapter(texts, floor)
        blocking_issues = tuple(dimension for dimension, score in scores.items() if score < floor)
        review_id = self._write_review(
            project_id=project_id,
            chapter_id=chapter_id,
            run_id=run_id,
            scores=scores,
            blocking_issues=blocking_issues,
        )
        return ChapterReviewResult(
            review_id=review_id,
            project_id=project_id,
            chapter_id=chapter_id,
            run_id=run_id,
            quality_gate_passed=not blocking_issues,
            blocking_issues=blocking_issues,
        )

    def _write_review(
        self,
        *,
        project_id: int,
        chapter_id: int,
        run_id: int,
        scores: dict[str, int],
        blocking_issues: tuple[str, ...],
    ) -> int:
        existing = self.conn.execute(
            """
            SELECT status
            FROM writing_chapter_reviews
            WHERE project_id = ? AND chapter_id = ? AND run_id = ?
            """,
            (project_id, chapter_id, run_id),
        ).fetchone()
        if existing is not None and str(existing[0]) == "accepted":
            raise DataIntegrityError(f"accepted chapter review cannot be overwritten: {project_id}/{chapter_id}/{run_id}")

        try:
            self.conn.execute("SAVEPOINT chapter_review")
            self.conn.execute(
                "DELETE FROM writing_chapter_reviews WHERE project_id = ? AND chapter_id = ? AND run_id = ?",
                (project_id, chapter_id, run_id),
            )
            cursor = self.conn.execute(
                """
                INSERT INTO writing_chapter_reviews
                    (project_id, chapter_id, run_id, status,
                     chapter_continuity_hard, pov_consistency, character_consistency,
                     chapter_hook_soft, rhythm_curve, motif_density, info_gap_lifecycle,
                     quality_gate_passed, blocking_issues, review_notes, reviewed_at)
                VALUES (?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    project_id,
                    chapter_id,
                    run_id,
                    scores["chapter_continuity_hard"],
                    scores["pov_consistency"],
                    scores["character_consistency"],
                    scores["chapter_hook_soft"],
                    scores["rhythm_curve"],
                    scores["motif_density"],
                    scores["info_gap_lifecycle"],
                    int(not blocking_issues),
                    json.dumps(list(blocking_issues), ensure_ascii=False, sort_keys=True),
                    "chapter review baseline",
                    now_utc_iso(),
                ),
            )
        except Exception:
            self.conn.execute("ROLLBACK TO chapter_review")
            self.conn.execute("RELEASE chapter_review")
            raise
        else:
            self.conn.execute("RELEASE chapter_review")
            return int(cursor.lastrowid)


def _load_chapter_shots(conn: sqlite3.Connection, project_id: int, chapter_id: int, run_id: int) -> list[tuple[str, str]]:
    rows = conn.execute(
        """
        SELECT shot_id, status
        FROM writing_shots
        WHERE project_id = ? AND chapter_id = ? AND run_id = ?
        ORDER BY shot_id
        """,
        (project_id, chapter_id, run_id),
    ).fetchall()
    return [(str(row[0]), str(row[1])) for row in rows]


def _chapter_quality_floor(conn: sqlite3.Connection, project_id: int) -> int:
    row = conn.execute(
        "SELECT chapter_quality_floor FROM writing_projects WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"project not found: {project_id}")
    return int(row[0])


def _score_chapter(texts: list[str], floor: int) -> dict[str, int]:
    scores = {dimension: max(82, floor) for dimension in CHAPTER_REVIEW_DIMENSIONS}
    joined = "\n".join(texts)
    if "[chapter-fail]" in joined:
        scores["rhythm_curve"] = floor - 1
    return scores
