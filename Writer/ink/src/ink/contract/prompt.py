from __future__ import annotations

import sqlite3

from ink.contract.generated.dtos import PromptSpecDTO
from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


class PromptSnapshotCompiler:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def compile_from_task_card(
        self,
        task_card_id: int,
        persona: str,
        *,
        relaxed_soft: bool = False,
    ) -> PromptSpecDTO:
        row = self.conn.execute(
            """
            SELECT compiled_instructions
            FROM writing_shot_task_cards
            WHERE task_card_id = ?
            """,
            (task_card_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"task card not found: {task_card_id}")

        relaxed_note = "\nRelax soft constraints only for deviant exploration." if relaxed_soft else ""
        prompt_text = (
            f"Persona: {persona}\n\n"
            f"{row[0]}\n\n"
            "Write one candidate draft. Preserve hard constraints and make every must-land item observable."
            f"{relaxed_note}"
        )
        prompt_id = self.write_prompt_snapshot(
            task_card_id,
            persona,
            prompt_text,
            relaxed_soft=relaxed_soft,
        )
        return load_prompt_spec(self.conn, prompt_id)

    def write_prompt_snapshot(
        self,
        task_card_id: int,
        persona: str,
        full_prompt_text: str,
        *,
        relaxed_soft: bool = False,
    ) -> int:
        if not full_prompt_text.strip():
            raise DataIntegrityError("prompt snapshot must not be empty")

        now = now_utc_iso()
        relaxed = 1 if relaxed_soft else 0
        self.conn.execute(
            """
            UPDATE writing_prompt_snapshots
            SET superseded_at = ?
            WHERE task_card_id = ?
              AND persona = ?
              AND relaxed_soft = ?
              AND superseded_at IS NULL
            """,
            (now, task_card_id, persona, relaxed),
        )
        cursor = self.conn.execute(
            """
            INSERT INTO writing_prompt_snapshots
                (task_card_id, persona, full_prompt_text, prompt_size_bytes, relaxed_soft, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                task_card_id,
                persona,
                full_prompt_text,
                len(full_prompt_text.encode("utf-8")),
                relaxed,
                now,
            ),
        )
        return int(cursor.lastrowid)


def load_prompt_spec(conn: sqlite3.Connection, prompt_id: int) -> PromptSpecDTO:
    row = conn.execute(
        """
        SELECT prompt_id, task_card_id, persona, full_prompt_text, prompt_size_bytes, relaxed_soft, superseded_at
        FROM writing_prompt_snapshots
        WHERE prompt_id = ?
        """,
        (prompt_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"prompt snapshot not found: {prompt_id}")
    return _row_to_prompt_spec(row)


def load_latest_prompt_spec(
    conn: sqlite3.Connection,
    task_card_id: int,
    persona: str,
    *,
    relaxed_soft: bool = False,
) -> PromptSpecDTO:
    row = conn.execute(
        """
        SELECT prompt_id, task_card_id, persona, full_prompt_text, prompt_size_bytes, relaxed_soft, superseded_at
        FROM writing_prompt_snapshots
        WHERE task_card_id = ?
          AND persona = ?
          AND relaxed_soft = ?
          AND superseded_at IS NULL
        ORDER BY prompt_id DESC
        LIMIT 1
        """,
        (task_card_id, persona, 1 if relaxed_soft else 0),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"current prompt snapshot not found: {task_card_id}/{persona}")
    return _row_to_prompt_spec(row)


def _row_to_prompt_spec(row: sqlite3.Row | tuple) -> PromptSpecDTO:
    return PromptSpecDTO(
        prompt_id=int(row[0]),
        task_card_id=int(row[1]),
        persona=str(row[2]),
        full_prompt_text=str(row[3]),
        prompt_size_bytes=int(row[4]),
        relaxed_soft=bool(row[5]),
        superseded_at=None if row[6] is None else str(row[6]),
    )
