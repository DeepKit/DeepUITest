from __future__ import annotations

import sqlite3

from ink.core.llm_gateway import LLMGateway
from ink.core.state_machine import load_status, transition
from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError
from ink.writers.draft_repository import insert_draft, load_draft


def polish_winner(shot_id: str, run_id: int) -> int:
    raise DataIntegrityError("polish orchestrator is not configured")


class PolishOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway: LLMGateway | None = None) -> None:
        self.conn = conn
        self.gateway = gateway or LLMGateway(conn)

    def polish_winner(self, shot_id: str, run_id: int) -> int:
        status = load_status(self.conn, shot_id, run_id)
        if status == "winner_selected":
            transition(self.conn, shot_id, run_id, "winner_selected", "polish_revision")
        elif status != "polish_revision":
            raise DataIntegrityError(f"polish cannot run from status: {status}")

        winner = _load_winner_draft(self.conn, shot_id)
        project_id = _lookup_project_id(self.conn, shot_id, run_id)
        prompt_text = _polish_prompt(winner.text)
        result = self.gateway.call(
            project_id=project_id,
            shot_id=shot_id,
            run_id=run_id,
            call_type="polish",
            prompt_id=winner.prompt_id,
            prompt_text=prompt_text,
            model_name="smart-polish",
            idempotency_key=f"polish:{shot_id}:{run_id}:{winner.draft_id}",
        )
        _ensure_productive_markers_preserved(winner.text, result.text)
        revision_id = TextRepository(self.conn).write_revision(
            shot_id,
            run_id,
            result.text,
            seal="none",
        )
        insert_draft(
            self.conn,
            shot_id=shot_id,
            prompt_id=winner.prompt_id,
            persona=winner.persona,
            writer_model=result.model_name,
            text=result.text,
            retry_count=winner.retry_count + 1,
        )
        if load_status(self.conn, shot_id, run_id) == "polish_revision":
            transition(self.conn, shot_id, run_id, "polish_revision", "hard_gate1")
        return revision_id

    def resume_handlers(self) -> dict[str, object]:
        return {"rerun_polish_and_quality_gate": self.polish_winner}


def _load_winner_draft(conn: sqlite3.Connection, shot_id: str):
    row = conn.execute(
        """
        SELECT draft_id
        FROM writing_jury_aggregates
        WHERE shot_id = ? AND is_winner = 1
        """,
        (shot_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"winner not found for shot: {shot_id}")
    return load_draft(conn, int(row[0]))


def _lookup_project_id(conn: sqlite3.Connection, shot_id: str, run_id: int) -> int:
    row = conn.execute(
        "SELECT project_id FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"shot not found: {shot_id}/{run_id}")
    return int(row[0])


def _polish_prompt(winner_text: str) -> str:
    return (
        "Polish this winning draft without adding facts, changing POV, or flattening productive roughness.\n"
        "productive_deviations=[]\n"
        "neutral_issues=[]\n\n"
        f"{winner_text}"
    )


def _ensure_productive_markers_preserved(source_text: str, polished_text: str) -> None:
    markers = ("[productive-deviation]", "[protected-roughness]")
    missing = [marker for marker in markers if marker in source_text and marker not in polished_text]
    if missing:
        raise DataIntegrityError(f"polish removed protected productive marker: {', '.join(missing)}")
