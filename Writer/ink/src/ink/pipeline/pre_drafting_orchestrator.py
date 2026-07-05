from __future__ import annotations

import sqlite3
from collections.abc import Callable

from ink.contract.generated.dtos import PromptSpecDTO, TaskCardDTO
from ink.contract.loader import load_shot_contract
from ink.contract.prompt import PromptSnapshotCompiler
from ink.contract.task_card import TaskCardCompiler, load_latest_task_card
from ink.core.context_snapshot import prompt_context_payload, save_context_snapshot
from ink.core.llm_gateway import LLMGateway
from ink.core.state_machine import load_status, transition
from ink.errors import DataIntegrityError
from ink.outline.repository import OutlineRepository
from ink.pipeline.outline_orchestrator import OutlineOrchestrator


ResumeHandler = Callable[[str, int], object]


class PreDraftingOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway: LLMGateway | None = None) -> None:
        self.conn = conn
        self.gateway = gateway or LLMGateway(conn)
        self.outline_orchestrator = OutlineOrchestrator(conn, self.gateway)

    def run_until_prompt_compiled(self, shot_id: str, run_id: int) -> PromptSpecDTO:
        status = load_status(self.conn, shot_id, run_id)
        if status in {"pending", "outline_draft"}:
            self.outline_orchestrator.evaluate_and_select(shot_id, run_id)
            status = "outline_confirmed"
        if status == "outline_confirmed":
            self.compile_task_card(shot_id, run_id)
            status = "task_card_compiled"
        if status in {"task_card_compiled", "prompt_compiled"}:
            return self.compile_prompt(shot_id, run_id)
        raise DataIntegrityError(f"pre-drafting cannot run from status: {status}")

    def rerun_outline(self, shot_id: str, run_id: int) -> object:
        return self.outline_orchestrator.evaluate_and_select(shot_id, run_id)

    def compile_task_card(self, shot_id: str, run_id: int) -> TaskCardDTO:
        status = load_status(self.conn, shot_id, run_id)
        if status not in {"outline_confirmed", "task_card_compiled"}:
            raise DataIntegrityError(f"task card cannot compile from status: {status}")

        shot_contract_id = _lookup_shot_contract_id(self.conn, shot_id, run_id)
        outline = OutlineRepository(self.conn).load_winner(shot_contract_id)
        card = TaskCardCompiler(self.conn).compile_for_shot(shot_id, run_id, outline.evaluated_outline_text)
        if status == "outline_confirmed":
            transition(self.conn, shot_id, run_id, "outline_confirmed", "task_card_compiled")
        return card

    def compile_prompt(self, shot_id: str, run_id: int) -> PromptSpecDTO:
        status = load_status(self.conn, shot_id, run_id)
        if status not in {"task_card_compiled", "prompt_compiled"}:
            raise DataIntegrityError(f"prompt cannot compile from status: {status}")

        shot_contract_id = _lookup_shot_contract_id(self.conn, shot_id, run_id)
        contract = load_shot_contract(self.conn, shot_id, run_id)
        task_card = load_latest_task_card(self.conn, shot_contract_id)
        persona = str(contract.persona_assignment["persona"])
        prompt = PromptSnapshotCompiler(self.conn).compile_from_task_card(task_card.task_card_id, persona)
        save_context_snapshot(
            self.conn,
            project_id=_lookup_project_id(self.conn, shot_id, run_id),
            shot_id=shot_id,
            run_id=run_id,
            prompt_id=prompt.prompt_id,
            upstream_revision_ids=(),
            context_payload=prompt_context_payload(
                task_card_id=task_card.task_card_id,
                persona=persona,
                relaxed_soft=False,
            ),
        )
        if status == "task_card_compiled":
            transition(self.conn, shot_id, run_id, "task_card_compiled", "prompt_compiled")
        return prompt

    def resume_handlers(self) -> dict[str, ResumeHandler]:
        return {
            "start_from_scratch": self.run_until_prompt_compiled,
            "rerun_outline": self.rerun_outline,
            "rerun_task_card": self.compile_task_card,
            "rerun_prompt": self.compile_prompt,
        }


def _lookup_shot_contract_id(conn: sqlite3.Connection, shot_id: str, run_id: int) -> int:
    row = conn.execute(
        "SELECT shot_contract_id FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    if row is None or row[0] is None:
        raise DataIntegrityError(f"shot contract not found: {shot_id}/{run_id}")
    return int(row[0])


def _lookup_project_id(conn: sqlite3.Connection, shot_id: str, run_id: int) -> int:
    row = conn.execute(
        "SELECT project_id FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"shot not found: {shot_id}/{run_id}")
    return int(row[0])
