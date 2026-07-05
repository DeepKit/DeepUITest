from __future__ import annotations

import sqlite3
from typing import Literal

from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


SealMode = Literal["none", "shot_soft", "chapter_hard"]


class TextRepository:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def read_current_text(self, shot_id: str, run_id: int) -> str:
        rows = self.conn.execute(
            """
            SELECT text
            FROM v_current_text
            WHERE shot_id = ? AND run_id = ?
            """,
            (shot_id, run_id),
        ).fetchall()
        if not rows:
            raise DataIntegrityError(f"no current text for shot: {shot_id}/{run_id}")
        if len(rows) > 1:
            raise DataIntegrityError(f"multiple current text rows for shot: {shot_id}/{run_id}")
        return str(rows[0][0])

    def write_revision(
        self,
        shot_id: str,
        run_id: int,
        text: str,
        source_revision_id: int | None = None,
        seal: SealMode = "none",
    ) -> int:
        if seal not in {"none", "shot_soft", "chapter_hard"}:
            raise ValueError(f"invalid seal mode: {seal}")

        next_sequence = self._next_revision_sequence(shot_id)
        now = now_utc_iso()
        is_current = 1 if seal == "chapter_hard" else 0
        sealed_at = now if seal != "none" else None
        sealed_by = None if seal == "none" else seal

        started_transaction = not self.conn.in_transaction
        try:
            if started_transaction:
                self.conn.execute("BEGIN")
            if seal == "chapter_hard":
                self.conn.execute(
                    "UPDATE writing_shot_revisions SET is_current = 0 WHERE shot_id = ?",
                    (shot_id,),
                )
            cursor = self.conn.execute(
                """
                INSERT INTO writing_shot_revisions
                    (shot_id, run_id, revision_sequence, text, is_current,
                     sealed_at, sealed_by, source_revision_id, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    shot_id,
                    run_id,
                    next_sequence,
                    text,
                    is_current,
                    sealed_at,
                    sealed_by,
                    source_revision_id,
                    now,
                ),
            )
        except Exception:
            if started_transaction:
                self.conn.rollback()
            raise
        else:
            if started_transaction:
                self.conn.commit()
            return int(cursor.lastrowid)

    def is_hard_sealed(self, shot_id: str, run_id: int) -> bool:
        row = self.conn.execute(
            """
            SELECT 1
            FROM writing_shot_revisions
            WHERE shot_id = ? AND run_id = ? AND is_current = 1 AND sealed_by = 'chapter_hard'
            LIMIT 1
            """,
            (shot_id, run_id),
        ).fetchone()
        return row is not None

    def _next_revision_sequence(self, shot_id: str) -> int:
        row = self.conn.execute(
            "SELECT COALESCE(MAX(revision_sequence), 0) + 1 FROM writing_shot_revisions WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()
        return int(row[0])
