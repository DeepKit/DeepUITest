"""Chapter-level coherence checks that do not require author-owned volume tables."""
from __future__ import annotations

import re
import sqlite3
from dataclasses import dataclass

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository

_TOKEN_RE = re.compile(r"[一-鿿]{2,4}|[A-Za-z][A-Za-z0-9_-]+")


@dataclass(frozen=True)
class ChapterOverlap:
    chapter_id: int
    score: float
    shared_tokens: tuple[str, ...]


@dataclass(frozen=True)
class CoherenceGateResult:
    passed: bool
    threshold: float
    overlaps: tuple[ChapterOverlap, ...]


def evaluate_chapter_overlap(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    chapter_id: int,
    candidate_text: str,
    threshold: float = 0.55,
) -> CoherenceGateResult:
    """Compare a candidate with all earlier sealed chapters using token containment.

    The score is ``shared / min(candidate_tokens, previous_tokens)`` so a candidate
    that substantially repeats one shorter prior chapter is rejected even when the
    candidate itself is much longer. Empty/very short token sets do not fail closed.
    """
    if not 0.0 <= threshold <= 1.0:
        raise ValueError("threshold must be between 0 and 1")
    repo = ChapterSnapshotRepository(conn)
    previous_chapters = [
        (
            previous_id,
            repo.read_active_chapter_text(
                project_id=project_id, chapter_id=previous_id
            ),
        )
        for previous_id in _sealed_previous_chapter_ids(conn, project_id, chapter_id)
    ]
    overlaps = list(compare_chapter_texts(candidate_text, previous_chapters))
    return CoherenceGateResult(
        passed=all(item.score < threshold for item in overlaps),
        threshold=threshold,
        overlaps=tuple(overlaps),
    )


def compare_chapter_texts(
    candidate_text: str, previous_chapters: list[tuple[int, str]]
) -> tuple[ChapterOverlap, ...]:
    """Return deterministic overlap evidence for supplied chapter texts."""
    candidate_tokens = _tokens(candidate_text)
    overlaps: list[ChapterOverlap] = []
    for previous_id, previous_text in previous_chapters:
        previous_tokens = _tokens(previous_text)
        denominator = min(len(candidate_tokens), len(previous_tokens))
        shared = candidate_tokens & previous_tokens
        score = len(shared) / denominator if denominator else 0.0
        overlaps.append(
            ChapterOverlap(
                chapter_id=previous_id,
                score=score,
                shared_tokens=tuple(sorted(shared)),
            )
        )
    return tuple(overlaps)


def _tokens(text: str) -> set[str]:
    return {token.casefold() for token in _TOKEN_RE.findall(text)}


def _sealed_previous_chapter_ids(
    conn: sqlite3.Connection, project_id: int, chapter_id: int
) -> list[int]:
    rows = conn.execute(
        """
        SELECT h.chapter_id
        FROM writing_chapter_heads h
        JOIN writing_chapter_snapshots s
          ON s.snapshot_id = h.active_snapshot_id AND s.sealed_at IS NOT NULL
        WHERE h.project_id = ? AND h.chapter_id < ?
        ORDER BY h.chapter_id
        """,
        (project_id, chapter_id),
    ).fetchall()
    return [int(row[0]) for row in rows]
