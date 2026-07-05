from __future__ import annotations

import sqlite3

from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


COMPLETE_TAIL_CHARS = set("。！？.!?」”'")


class TaskCardCompiler:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def write_task_card(self, shot_contract_id: int, compiled_instructions: str) -> int:
        if not _has_complete_tail(compiled_instructions):
            raise DataIntegrityError("task card instructions end with an incomplete tail")

        now = now_utc_iso()
        self.conn.execute(
            """
            UPDATE writing_shot_task_cards
            SET superseded_at = ?
            WHERE shot_contract_id = ? AND superseded_at IS NULL
            """,
            (now, shot_contract_id),
        )
        cursor = self.conn.execute(
            """
            INSERT INTO writing_shot_task_cards
                (shot_contract_id, compiled_instructions, created_at)
            VALUES (?, ?, ?)
            """,
            (shot_contract_id, compiled_instructions, now),
        )
        return int(cursor.lastrowid)


def _has_complete_tail(text: str) -> bool:
    stripped = text.strip()
    return bool(stripped) and stripped[-1] in COMPLETE_TAIL_CHARS
