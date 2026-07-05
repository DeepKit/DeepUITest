from __future__ import annotations

import sqlite3

from ink.contract.generated.dtos import OutlineSpecDTO
from ink.errors import DataIntegrityError
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

    def load(self, outline_id: int) -> OutlineSpecDTO:
        row = self.conn.execute(
            """
            SELECT outline_id, shot_contract_id, evaluated_outline_text, drift_score, is_winner
            FROM writing_outline_specs
            WHERE outline_id = ?
            """,
            (outline_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"outline not found: {outline_id}")
        return OutlineSpecDTO(
            outline_id=int(row[0]),
            shot_contract_id=int(row[1]),
            evaluated_outline_text=str(row[2]),
            drift_score=float(row[3]),
            is_winner=bool(row[4]),
        )

    def load_winner(self, shot_contract_id: int) -> OutlineSpecDTO:
        row = self.conn.execute(
            """
            SELECT outline_id, shot_contract_id, evaluated_outline_text, drift_score, is_winner
            FROM writing_outline_specs
            WHERE shot_contract_id = ? AND is_winner = 1
            """,
            (shot_contract_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"winner outline not found for shot_contract_id={shot_contract_id}")
        return OutlineSpecDTO(
            outline_id=int(row[0]),
            shot_contract_id=int(row[1]),
            evaluated_outline_text=str(row[2]),
            drift_score=float(row[3]),
            is_winner=bool(row[4]),
        )
