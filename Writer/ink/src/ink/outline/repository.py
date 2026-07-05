from __future__ import annotations

import sqlite3

from ink.time import now_utc_iso


class OutlineRepository:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def add_outline(self, shot_contract_id: int, text: str, drift_score: float) -> int:
        cursor = self.conn.execute(
            """
            INSERT INTO writing_outline_specs
                (shot_contract_id, evaluated_outline_text, drift_score, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (shot_contract_id, text, drift_score, now_utc_iso()),
        )
        return int(cursor.lastrowid)

    def select_winner(self, shot_contract_id: int, outline_id: int) -> None:
        self.conn.execute(
            "UPDATE writing_outline_specs SET is_winner = 0 WHERE shot_contract_id = ?",
            (shot_contract_id,),
        )
        self.conn.execute(
            """
            UPDATE writing_outline_specs
            SET is_winner = 1
            WHERE shot_contract_id = ? AND outline_id = ?
            """,
            (shot_contract_id, outline_id),
        )
