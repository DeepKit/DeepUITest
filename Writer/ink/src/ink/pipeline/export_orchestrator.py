from __future__ import annotations

import json
import re
import sqlite3

from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError
from ink.pipeline.book_rolling_check_orchestrator import has_blocking_issues
from ink.time import now_utc_iso


STRUCTURAL_TAG_RE = re.compile(r"\[\[[^\]]+\]\]|<struct>.*?</struct>", re.DOTALL)


class ExportOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def build_project(self, project_id: int) -> str:
        """Build the legacy Shot artifact for pre-cutover parity only."""
        if has_blocking_issues(self.conn, project_id):
            raise DataIntegrityError("unresolved book blocking issue prevents export")

        rows = self.conn.execute(
            """
            SELECT r.chapter_id, s.shot_id, s.run_id
            FROM writing_chapter_reviews r
            JOIN writing_shots s
              ON s.project_id = r.project_id
             AND s.chapter_id = r.chapter_id
             AND s.run_id = r.run_id
            WHERE r.project_id = ?
              AND r.status = 'accepted'
              AND s.status = 'hard_sealed'
            ORDER BY r.chapter_id, s.logical_shot_id
            """,
            (project_id,),
        ).fetchall()
        if not rows:
            raise DataIntegrityError(f"no accepted canonical text to export: {project_id}")

        repo = TextRepository(self.conn)
        texts = [_clean_export_text(repo.read_current_text(str(row[1]), int(row[2]))) for row in rows]
        return "\n\n".join(text for text in texts if text)

    def export_project(self, project_id: int) -> str:
        """Legacy baseline retained only for migration parity and old tests."""
        artifact = self.build_project(project_id)
        counts = self.conn.execute(
            """
            SELECT count(DISTINCT r.chapter_id), count(*)
            FROM writing_chapter_reviews r
            JOIN writing_shots s
              ON s.project_id = r.project_id
             AND s.chapter_id = r.chapter_id
             AND s.run_id = r.run_id
            WHERE r.project_id = ? AND r.status = 'accepted'
              AND s.status = 'hard_sealed'
            """,
            (project_id,),
        ).fetchone()
        self.conn.execute(
            """
            INSERT INTO writing_runtime_events
                (project_id, event_type, event_payload, created_at)
            VALUES (?, 'EXPORT_COMPLETED', ?, ?)
            """,
            (
                project_id,
                json.dumps(
                    {
                        "chapter_count": int(counts[0]),
                        "shot_count": int(counts[1]),
                    },
                    sort_keys=True,
                ),
                now_utc_iso(),
            ),
        )
        return artifact


def _clean_export_text(text: str) -> str:
    without_tags = STRUCTURAL_TAG_RE.sub("", text)
    lines = [line.strip() for line in without_tags.splitlines()]
    return "\n".join(line for line in lines if line).strip()
