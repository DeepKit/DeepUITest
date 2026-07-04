from __future__ import annotations

import sqlite3

from ink.errors import ConcurrentModificationError, IllegalTransitionError, TerminalStateError
from ink.time import now_utc_iso


TERMINAL_STATES = {"hard_sealed", "failed"}
LEGAL_TRANSITIONS = {
    ("pending", "outline_draft"),
    ("outline_draft", "outline_confirmed"),
    ("outline_confirmed", "task_card_compiled"),
    ("task_card_compiled", "prompt_compiled"),
    ("prompt_compiled", "drafting"),
    ("drafting", "hard_gate1"),
    ("hard_gate1", "hard_gate2"),
    ("hard_gate2", "jury_scoring"),
    ("jury_scoring", "winner_selected"),
    ("winner_selected", "polish_revision"),
    ("polish_revision", "hard_gate1"),
    ("polish_revision", "soft_sealed"),
    ("soft_sealed", "hard_sealed"),
}
NON_TERMINAL_STATES = {
    "pending",
    "outline_draft",
    "outline_confirmed",
    "task_card_compiled",
    "prompt_compiled",
    "drafting",
    "hard_gate1",
    "hard_gate2",
    "jury_scoring",
    "winner_selected",
    "polish_revision",
    "soft_sealed",
}
LEGAL_TRANSITIONS |= {(state, "failed") for state in NON_TERMINAL_STATES}


def transition(conn: sqlite3.Connection, shot_id: str, run_id: int, prev: str, next_: str) -> None:
    if prev in TERMINAL_STATES:
        raise TerminalStateError(f"terminal state has no outgoing transition: {prev}")
    if (prev, next_) not in LEGAL_TRANSITIONS:
        raise IllegalTransitionError(f"illegal transition: {prev} -> {next_}")

    cursor = conn.execute(
        """
        UPDATE writing_shots
        SET status = ?, updated_at = ?
        WHERE shot_id = ? AND run_id = ? AND status = ?
        """,
        (next_, now_utc_iso(), shot_id, run_id, prev),
    )
    if cursor.rowcount != 1:
        raise ConcurrentModificationError(
            f"expected one row for transition {shot_id}/{run_id}: {prev} -> {next_}, got {cursor.rowcount}"
        )


def load_status(conn: sqlite3.Connection, shot_id: str, run_id: int) -> str | None:
    row = conn.execute(
        "SELECT status FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    return None if row is None else str(row[0])
