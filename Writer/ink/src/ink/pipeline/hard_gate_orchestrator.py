from __future__ import annotations

import sqlite3

from ink.contract.generated.dtos import DraftSpecDTO
from ink.contract.loader import load_shot_contract
from ink.core.state_machine import load_status, transition
from ink.errors import DataIntegrityError
from ink.time import now_utc_iso
from ink.writers.draft_repository import list_drafts


_DEFAULT_ORCHESTRATOR: "HardGateOrchestrator | None" = None


def run_both_gates(shot_id: str, run_id: int) -> list[DraftSpecDTO]:
    if _DEFAULT_ORCHESTRATOR is None:
        raise DataIntegrityError("hard gate orchestrator is not configured")
    return _DEFAULT_ORCHESTRATOR.run_both_gates(shot_id, run_id)


class HardGateOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def run_both_gates(self, shot_id: str, run_id: int) -> list[DraftSpecDTO]:
        status = load_status(self.conn, shot_id, run_id)
        redo_mode = status == "winner_selected" and _redo_in_progress(self.conn, shot_id, run_id)
        if status == "hard_gate1":
            transition(self.conn, shot_id, run_id, "hard_gate1", "hard_gate2")
            status = "hard_gate2"
        if status not in {"hard_gate2", "jury_scoring"} and not redo_mode:
            raise DataIntegrityError(f"hard gates cannot run from status: {status}")

        contract = load_shot_contract(self.conn, shot_id, run_id)
        forbidden_words = [str(item) for item in contract.anti_write.get("forbidden_words", [])]
        drafts = list_drafts(self.conn, shot_id)
        for draft in drafts:
            gate1 = _gate1(draft, forbidden_words)
            gate2 = _gate2(draft)
            self._write_eligibility(draft.draft_id, gate1, gate2)

        if status == "hard_gate2":
            transition(self.conn, shot_id, run_id, "hard_gate2", "jury_scoring")
        return _eligible_jury_candidates(self.conn, shot_id, retry_only=redo_mode)

    def _write_eligibility(self, draft_id: int, gate1: tuple[int, int, int, int], gate2: tuple[int, int, int, int]) -> None:
        self.conn.execute("DELETE FROM writing_draft_eligibility WHERE draft_id = ?", (draft_id,))
        gate1_eligible = int(all(gate1))
        gate2_eligible = int(all(gate2))
        self.conn.execute(
            """
            INSERT INTO writing_draft_eligibility
                (draft_id, gate1_eligible, gate1_contract_compliance, gate1_forbidden_check,
                 gate1_capacity, gate1_basic_readability, gate2_eligible, gate2_fact_anchor,
                 gate2_scene_contract, gate2_pov_compliance, gate2_structure_skeleton, evaluated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (draft_id, gate1_eligible, *gate1, gate2_eligible, *gate2, now_utc_iso()),
        )

    def resume_handlers(self) -> dict[str, object]:
        return {
            "rerun_hard_gate1": self.run_both_gates,
            "rerun_hard_gate2": self.run_both_gates,
        }


def _gate1(draft: DraftSpecDTO, forbidden_words: list[str]) -> tuple[int, int, int, int]:
    contract_compliance = int(not draft.degraded)
    forbidden_check = int(not any(word and word in draft.text for word in forbidden_words))
    capacity = int(draft.byte_count > 0)
    readability = int(bool(draft.text.strip()))
    return contract_compliance, forbidden_check, capacity, readability


def _gate2(draft: DraftSpecDTO) -> tuple[int, int, int, int]:
    if draft.degraded:
        return (0, 0, 0, 0)
    return (1, 1, 1, 1)


def _eligible_jury_candidates(conn: sqlite3.Connection, shot_id: str, *, retry_only: bool = False) -> list[DraftSpecDTO]:
    candidates = [
        draft
        for draft in list_drafts(conn, shot_id)
        if not draft.degraded
        and not draft.is_deviant
        and (draft.retry_count > 0 if retry_only else draft.retry_count == 0)
        and _is_eligible(conn, draft.draft_id)
    ]
    return candidates


def _is_eligible(conn: sqlite3.Connection, draft_id: int) -> bool:
    row = conn.execute(
        """
        SELECT gate1_eligible, gate2_eligible
        FROM writing_draft_eligibility
        WHERE draft_id = ?
        """,
        (draft_id,),
    ).fetchone()
    return row is not None and int(row[0]) == 1 and int(row[1]) == 1


def _redo_in_progress(conn: sqlite3.Connection, shot_id: str, run_id: int) -> bool:
    row = conn.execute(
        "SELECT redo_in_progress FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    return row is not None and int(row[0]) == 1
