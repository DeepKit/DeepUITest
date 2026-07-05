from __future__ import annotations

import sqlite3

from ink.contract.generated.dtos import DraftSpecDTO
from ink.time import now_utc_iso


def insert_draft(
    conn: sqlite3.Connection,
    *,
    shot_id: str,
    prompt_id: int,
    persona: str,
    writer_model: str,
    text: str,
    degraded: bool = False,
    failure_category: str | None = None,
    retry_count: int = 0,
    is_deviant: bool = False,
) -> DraftSpecDTO:
    cursor = conn.execute(
        """
        INSERT INTO writing_drafts
            (shot_id, prompt_id, persona, writer_model, text, degraded, failure_category,
             retry_count, is_deviant, byte_count, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            shot_id,
            prompt_id,
            persona,
            writer_model,
            text,
            1 if degraded else 0,
            failure_category,
            retry_count,
            1 if is_deviant else 0,
            len(text.encode("utf-8")),
            now_utc_iso(),
        ),
    )
    return load_draft(conn, int(cursor.lastrowid))


def load_draft(conn: sqlite3.Connection, draft_id: int) -> DraftSpecDTO:
    row = conn.execute(
        """
        SELECT draft_id, shot_id, prompt_id, persona, writer_model, text, byte_count,
               degraded, failure_category, retry_count, is_deviant
        FROM writing_drafts
        WHERE draft_id = ?
        """,
        (draft_id,),
    ).fetchone()
    if row is None:
        raise ValueError(f"draft not found: {draft_id}")
    return _row_to_draft(row)


def list_drafts(conn: sqlite3.Connection, shot_id: str) -> list[DraftSpecDTO]:
    rows = conn.execute(
        """
        SELECT draft_id, shot_id, prompt_id, persona, writer_model, text, byte_count,
               degraded, failure_category, retry_count, is_deviant
        FROM writing_drafts
        WHERE shot_id = ?
        ORDER BY draft_id
        """,
        (shot_id,),
    ).fetchall()
    return [_row_to_draft(row) for row in rows]


def _row_to_draft(row: sqlite3.Row | tuple) -> DraftSpecDTO:
    return DraftSpecDTO(
        draft_id=int(row[0]),
        shot_id=str(row[1]),
        prompt_id=int(row[2]),
        persona=str(row[3]),
        writer_model=str(row[4]),
        text=str(row[5]),
        byte_count=int(row[6]),
        degraded=bool(row[7]),
        failure_category=None if row[8] is None else str(row[8]),
        retry_count=int(row[9]),
        is_deviant=bool(row[10]),
    )
