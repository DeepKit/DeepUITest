from __future__ import annotations

import sqlite3

from ink.contract.generated.dtos import DraftSpecDTO, PromptSpecDTO
from ink.contract.loader import load_shot_contract
from ink.contract.prompt import PromptSnapshotCompiler, load_latest_prompt_spec
from ink.contract.task_card import load_latest_task_card
from ink.core.context_snapshot import prompt_context_payload, save_context_snapshot
from ink.core.llm_gateway import LLMGateway
from ink.core.state_machine import load_status, transition
from ink.errors import DataIntegrityError, LLMProviderError
from ink.writers.draft_repository import insert_draft, list_drafts
from ink.writers.local_fallback import fallback_draft_text
from ink.writers.model_pool import load_writer_model_pool, select_writer_models


_DEFAULT_ORCHESTRATOR: "WriteOrchestrator | None" = None


def produce_drafts(shot_id: str, run_id: int) -> list[DraftSpecDTO]:
    if _DEFAULT_ORCHESTRATOR is None:
        raise DataIntegrityError("write orchestrator is not configured")
    return _DEFAULT_ORCHESTRATOR.produce_drafts(shot_id, run_id)


class WriteOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway: LLMGateway | None = None) -> None:
        self.conn = conn
        self.gateway = gateway or LLMGateway(conn)

    def produce_drafts(self, shot_id: str, run_id: int) -> list[DraftSpecDTO]:
        context = _load_write_context(self.conn, shot_id, run_id)
        status = _enter_drafting_state(self.conn, shot_id, run_id)
        existing = list_drafts(self.conn, shot_id)
        regular_existing = [draft for draft in existing if not draft.is_deviant and draft.retry_count == 0]
        deviant_existing = [draft for draft in existing if draft.is_deviant and draft.retry_count == 0]

        drafts = list(existing)
        regular_needed = max(0, context.candidate_count - len(regular_existing))
        selected_models = select_writer_models(context.writer_models, context.candidate_count)
        used_regular = len(regular_existing)
        for offset in range(regular_needed):
            model_name = selected_models[used_regular + offset]
            drafts.append(
                self._produce_one(
                    context=context,
                    prompt=context.prompt,
                    model_name=model_name,
                    idempotency_key=f"draft:{shot_id}:{run_id}:{used_regular + offset + 1}",
                    is_deviant=False,
                )
            )

        if not deviant_existing:
            if context.deviant_prompt is None:
                raise DataIntegrityError("deviant prompt was not compiled")
            deviant_model = context.writer_models[context.candidate_count % len(context.writer_models)]
            drafts.append(
                self._produce_one(
                    context=context,
                    prompt=context.deviant_prompt,
                    model_name=deviant_model,
                    idempotency_key=f"draft:{shot_id}:{run_id}:deviant",
                    is_deviant=True,
                )
            )

        if status == "drafting" and load_status(self.conn, shot_id, run_id) == "drafting":
            transition(self.conn, shot_id, run_id, "drafting", "hard_gate1")
        return list_drafts(self.conn, shot_id)

    def produce_redo_candidates(self, shot_id: str, run_id: int) -> list[DraftSpecDTO]:
        context = _load_write_context(self.conn, shot_id, run_id, include_deviant=False)
        row = self.conn.execute(
            "SELECT status, redo_in_progress FROM writing_shots WHERE shot_id = ? AND run_id = ?",
            (shot_id, run_id),
        ).fetchone()
        if row is None or row[0] != "winner_selected" or int(row[1]) != 1:
            raise DataIntegrityError("redo candidates require winner_selected with redo_in_progress=1")

        existing = [draft for draft in list_drafts(self.conn, shot_id) if draft.retry_count > 0]
        retry_count = max((draft.retry_count for draft in existing), default=1)
        current_wave = [draft for draft in existing if draft.retry_count == retry_count]
        needed = max(0, context.redo_candidate_count - len(current_wave))
        selected_models = select_writer_models(context.writer_models, context.redo_candidate_count)
        for offset in range(needed):
            index = len(current_wave) + offset
            self._produce_one(
                context=context,
                prompt=context.prompt,
                model_name=selected_models[index],
                idempotency_key=f"redo:{shot_id}:{run_id}:{retry_count}:{index + 1}",
                is_deviant=False,
                retry_count=retry_count,
            )
        return [draft for draft in list_drafts(self.conn, shot_id) if draft.retry_count == retry_count]

    def resume_handlers(self) -> dict[str, object]:
        return {
            "rerun_drafting": self.produce_drafts,
            "rerun_soft_gate_redo_drafting": self.produce_redo_candidates,
        }

    def _produce_one(
        self,
        *,
        context: "_WriteContext",
        prompt: PromptSpecDTO,
        model_name: str,
        idempotency_key: str,
        is_deviant: bool,
        retry_count: int = 0,
    ) -> DraftSpecDTO:
        try:
            result = self.gateway.call(
                project_id=context.project_id,
                shot_id=context.shot_id,
                run_id=context.run_id,
                call_type="draft",
                prompt_id=prompt.prompt_id,
                prompt_text=prompt.full_prompt_text,
                model_name=model_name,
                idempotency_key=idempotency_key,
            )
            return insert_draft(
                self.conn,
                shot_id=context.shot_id,
                prompt_id=prompt.prompt_id,
                persona=prompt.persona,
                writer_model=model_name,
                text=result.text,
                is_deviant=is_deviant,
                retry_count=retry_count,
            )
        except LLMProviderError as exc:
            if "budget blocked" in str(exc):
                raise
            failure_category = type(exc).__name__
            return insert_draft(
                self.conn,
                shot_id=context.shot_id,
                prompt_id=prompt.prompt_id,
                persona=prompt.persona,
                writer_model=model_name,
                text=fallback_draft_text(prompt.full_prompt_text, failure_category),
                degraded=True,
                failure_category=failure_category,
                is_deviant=is_deviant,
                retry_count=retry_count,
            )


class _WriteContext:
    def __init__(
        self,
        *,
        project_id: int,
        shot_id: str,
        run_id: int,
        candidate_count: int,
        redo_candidate_count: int,
        writer_models: tuple[str, ...],
        prompt: PromptSpecDTO,
        deviant_prompt: PromptSpecDTO | None,
    ) -> None:
        self.project_id = project_id
        self.shot_id = shot_id
        self.run_id = run_id
        self.candidate_count = candidate_count
        self.redo_candidate_count = redo_candidate_count
        self.writer_models = writer_models
        self.prompt = prompt
        self.deviant_prompt = deviant_prompt


def _load_write_context(
    conn: sqlite3.Connection,
    shot_id: str,
    run_id: int,
    *,
    include_deviant: bool = True,
) -> _WriteContext:
    row = conn.execute(
        """
        SELECT s.project_id, s.shot_contract_id, p.draft_count, p.creative_shot_extra, p.redo_candidate_count
        FROM writing_shots s
        JOIN writing_projects p ON p.project_id = s.project_id
        WHERE s.shot_id = ? AND s.run_id = ?
        """,
        (shot_id, run_id),
    ).fetchone()
    if row is None or row[1] is None:
        raise DataIntegrityError(f"shot not found or missing contract: {shot_id}/{run_id}")

    project_id = int(row[0])
    shot_contract_id = int(row[1])
    contract = load_shot_contract(conn, shot_id, run_id)
    persona = str(contract.persona_assignment["persona"])
    is_creative = bool(contract.persona_assignment["is_creative_shot"])
    candidate_count = int(row[2]) + (int(row[3]) if is_creative else 0)
    task_card = load_latest_task_card(conn, shot_contract_id)
    prompt = load_latest_prompt_spec(conn, task_card.task_card_id, persona)
    deviant_prompt = None
    if include_deviant:
        deviant_prompt = PromptSnapshotCompiler(conn).compile_from_task_card(
            task_card.task_card_id,
            persona,
            relaxed_soft=True,
        )
        save_context_snapshot(
            conn,
            project_id=project_id,
            shot_id=shot_id,
            run_id=run_id,
            prompt_id=deviant_prompt.prompt_id,
            upstream_revision_ids=(),
            context_payload=prompt_context_payload(
                task_card_id=task_card.task_card_id,
                persona=persona,
                relaxed_soft=True,
            ),
        )

    return _WriteContext(
        project_id=project_id,
        shot_id=shot_id,
        run_id=run_id,
        candidate_count=candidate_count,
        redo_candidate_count=int(row[4]),
        writer_models=load_writer_model_pool(conn, project_id),
        prompt=prompt,
        deviant_prompt=deviant_prompt,
    )


def _enter_drafting_state(conn: sqlite3.Connection, shot_id: str, run_id: int) -> str:
    status = load_status(conn, shot_id, run_id)
    if status == "prompt_compiled":
        transition(conn, shot_id, run_id, "prompt_compiled", "drafting")
        return "drafting"
    if status == "drafting":
        return "drafting"
    raise DataIntegrityError(f"drafting cannot run from status: {status}")
