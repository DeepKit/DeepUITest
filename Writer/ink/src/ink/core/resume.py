from __future__ import annotations

import json
import sqlite3

from ink.errors import DataIntegrityError


RESUME_MAP = {
    "soft_sealed": "skip",
    "hard_sealed": "skip",
    "failed": "skip",
    "drafting": "rerun_drafting",
    "hard_gate1": "rerun_hard_gate1",
    "hard_gate2": "rerun_hard_gate2",
    "jury_scoring": "rerun_jury",
    "winner_selected": "rerun_winner_select",
    "polish_revision": "rerun_polish_and_quality_gate",
    "outline_draft": "rerun_outline",
    "outline_confirmed": "rerun_outline",
    "task_card_compiled": "rerun_task_card",
    "prompt_compiled": "rerun_prompt",
    "pending": "start_from_scratch",
}


class ResumeManager:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def resume_shot(self, session_id: int, shot_id: str, run_id: int) -> str:
        row = self.conn.execute(
            """
            SELECT s.status, s.redo_in_progress
            FROM writing_shots s
            JOIN writing_runs r ON r.run_id = s.run_id
            WHERE r.session_id = ? AND s.shot_id = ? AND s.run_id = ?
            """,
            (session_id, shot_id, run_id),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"shot does not belong to session: {session_id}/{shot_id}/{run_id}")

        status = str(row[0])
        redo_in_progress = int(row[1]) == 1
        if redo_in_progress:
            new_drafts = self.conn.execute(
                "SELECT count(*) FROM writing_drafts WHERE shot_id = ? AND retry_count > 0",
                (shot_id,),
            ).fetchone()[0]
            new_scores = self.conn.execute(
                """
                SELECT count(*)
                FROM writing_jury_raw_scores r
                JOIN writing_drafts d ON d.draft_id = r.draft_id
                WHERE d.shot_id = ? AND d.retry_count > 0
                """,
                (shot_id,),
            ).fetchone()[0]
            if int(new_drafts) == 0:
                return "rerun_soft_gate_redo_drafting"
            if int(new_scores) == 0:
                return "rerun_soft_gate_redo_jury"

        return RESUME_MAP.get(status, "skip")

    def parse_resume_point(self, resume_point: str) -> dict:
        payload = json.loads(resume_point)
        phase = payload.get("phase")
        if phase not in {"outline", "drafting", "jury", "polish", "soft_gate", "chapter_review", "book_check"}:
            raise DataIntegrityError(f"invalid resume phase: {phase}")
        if "chapter_id" in payload and not isinstance(payload["chapter_id"], int):
            raise DataIntegrityError("resume chapter_id must be an integer")
        if "dimension_index" in payload and not isinstance(payload["dimension_index"], int):
            raise DataIntegrityError("resume dimension_index must be an integer")
        return payload
