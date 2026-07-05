from __future__ import annotations

import sqlite3

from ink.contract.generated.dtos import TaskCardDTO
from ink.contract.loader import load_shot_contract
from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


COMPLETE_TAIL_CHARS = set("。！？.!?」”'")


class TaskCardCompiler:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def compile_for_shot(self, shot_id: str, run_id: int, outline_text: str) -> TaskCardDTO:
        contract = load_shot_contract(self.conn, shot_id, run_id)
        shot_contract_id = _lookup_shot_contract_id(self.conn, shot_id, run_id)
        instructions = _render_task_card(contract.must_land, contract.anti_write, contract.persona_assignment, outline_text)
        task_card_id = self.write_task_card(shot_contract_id, instructions)
        return load_latest_task_card(self.conn, shot_contract_id, task_card_id=task_card_id)

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


def load_latest_task_card(
    conn: sqlite3.Connection,
    shot_contract_id: int,
    *,
    task_card_id: int | None = None,
) -> TaskCardDTO:
    if task_card_id is None:
        row = conn.execute(
            """
            SELECT task_card_id, shot_contract_id, compiled_instructions, superseded_at
            FROM writing_shot_task_cards
            WHERE shot_contract_id = ? AND superseded_at IS NULL
            ORDER BY task_card_id DESC
            LIMIT 1
            """,
            (shot_contract_id,),
        ).fetchone()
    else:
        row = conn.execute(
            """
            SELECT task_card_id, shot_contract_id, compiled_instructions, superseded_at
            FROM writing_shot_task_cards
            WHERE shot_contract_id = ? AND task_card_id = ?
            """,
            (shot_contract_id, task_card_id),
        ).fetchone()
    if row is None:
        raise DataIntegrityError(f"task card not found for shot_contract_id={shot_contract_id}")
    return TaskCardDTO(
        task_card_id=int(row[0]),
        shot_contract_id=int(row[1]),
        compiled_instructions=str(row[2]),
        superseded_at=None if row[3] is None else str(row[3]),
    )


def _has_complete_tail(text: str) -> bool:
    stripped = text.strip()
    return bool(stripped) and stripped[-1] in COMPLETE_TAIL_CHARS


def _lookup_shot_contract_id(conn: sqlite3.Connection, shot_id: str, run_id: int) -> int:
    row = conn.execute(
        "SELECT shot_contract_id FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    if row is None or row[0] is None:
        raise DataIntegrityError(f"shot contract not found: {shot_id}/{run_id}")
    return int(row[0])


def _render_task_card(
    must_land: dict[str, object],
    anti_write: dict[str, object],
    persona_assignment: dict[str, object],
    outline_text: str,
) -> str:
    events = _join_items(must_land.get("events"))
    beats = _join_items(must_land.get("beats"))
    releases = _join_items(must_land.get("information_releases"))
    forbidden_facts = _join_items(anti_write.get("forbidden_facts"))
    forbidden_words = _join_items(anti_write.get("forbidden_words"))
    pov_only = _join_items(anti_write.get("pov_only"))
    persona = str(persona_assignment.get("persona", ""))
    intensity = persona_assignment.get("intensity", {})
    return (
        f"Persona: {persona}\n"
        f"Intensity: {intensity}\n"
        f"Outline: {outline_text}\n"
        f"Must land events: {events}\n"
        f"Beats: {beats}\n"
        f"Information releases: {releases}\n"
        f"Forbidden facts: {forbidden_facts}\n"
        f"Forbidden words: {forbidden_words}\n"
        f"POV only: {pov_only}\n"
        "请按以上约束完成本 shot。"
    )


def _join_items(value: object) -> str:
    if isinstance(value, list):
        return "；".join(str(item) for item in value)
    return "" if value is None else str(value)
