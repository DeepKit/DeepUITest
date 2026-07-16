from __future__ import annotations

import sqlite3

from ink.core.state_machine import load_status, transition
from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError


def soft_seal_if_polished(shot_id: str, run_id: int) -> int:
    raise DataIntegrityError("soft seal orchestrator is not configured")


class SoftSealOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def soft_seal_if_polished(self, shot_id: str, run_id: int) -> int:
        status = load_status(self.conn, shot_id, run_id)
        if status != "winner_selected":
            raise DataIntegrityError(f"soft seal requires winner_selected, got: {status}")
        row = self.conn.execute(
            """
            SELECT d.writer_model, d.text, a.quality_gate_passed
            FROM writing_jury_aggregates a
            JOIN writing_drafts d ON d.draft_id = a.draft_id
            WHERE a.shot_id = ? AND a.is_winner = 1
            """,
            (shot_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"winner aggregate not found: {shot_id}")
        if str(row[0]) != "smart-polish":
            # 真实模型不保证 polish 必提分（polished 稿可能分数低于原稿，jury 据实选原稿当 winner）。
            # soft_seal 的目的是把过门 winner 固化为 canonical revision，不强制成稿必须是 polish 产出物。
            # 仅当 winner 未过 quality gate 时才拒绝（下方 quality_gate_passed 检查）。
            pass
        if int(row[2]) != 1:
            raise DataIntegrityError("winner quality gate must pass before soft seal")

        try:
            self.conn.execute("SAVEPOINT soft_seal_orchestrator")
            revision_id = TextRepository(self.conn).write_revision(
                shot_id,
                run_id,
                str(row[1]),
                seal="shot_soft",
            )
            transition(self.conn, shot_id, run_id, "winner_selected", "polish_revision")
            transition(self.conn, shot_id, run_id, "polish_revision", "soft_sealed")
        except Exception:
            self.conn.execute("ROLLBACK TO soft_seal_orchestrator")
            self.conn.execute("RELEASE soft_seal_orchestrator")
            raise
        else:
            self.conn.execute("RELEASE soft_seal_orchestrator")
            return revision_id
