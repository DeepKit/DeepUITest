from __future__ import annotations

import sqlite3

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator
from ink.linting.orchestrator_signature import lint_shot_orchestrator_source
from test_m2_contract_outline import insert_chinese_contract_children
from test_schema_contract import insert_minimal_draft, make_schema_db


def test_write_orchestrator_produces_same_persona_same_prompt_with_distinct_models_and_deviant() -> None:
    conn = make_prompt_compiled_shot()
    ids = _ids(conn)
    provider = RecordingDraftProvider()
    orchestrator = WriteOrchestrator(conn, LLMGateway(conn, provider=provider))

    drafts = orchestrator.produce_drafts(str(ids["shot_id"]), int(ids["run_id"]))

    regular = [draft for draft in drafts if not draft.is_deviant]
    deviant = [draft for draft in drafts if draft.is_deviant]
    assert [draft.writer_model for draft in regular] == ["writer-a", "writer-b", "writer-c"]
    assert len({draft.prompt_id for draft in regular}) == 1
    assert {draft.persona for draft in regular} == {"悬疑官"}
    assert len(deviant) == 1
    assert deviant[0].prompt_id != regular[0].prompt_id
    assert conn.execute(
        "SELECT relaxed_soft FROM writing_prompt_snapshots WHERE prompt_id = ?",
        (deviant[0].prompt_id,),
    ).fetchone()[0] == 1
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "hard_gate1"
    assert conn.execute("SELECT count(*) FROM writing_ai_call_attempts WHERE call_type = 'draft'").fetchone()[0] == 4


def test_write_orchestrator_adds_creative_extra_candidates() -> None:
    conn = make_prompt_compiled_shot(creative=True)
    ids = _ids(conn)
    conn.execute("UPDATE writing_projects SET creative_shot_extra = 1 WHERE project_id = 1")
    provider = RecordingDraftProvider()

    drafts = WriteOrchestrator(conn, LLMGateway(conn, provider=provider)).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )

    regular = [draft for draft in drafts if not draft.is_deviant]
    assert len(regular) == 4
    assert [draft.writer_model for draft in regular] == ["writer-a", "writer-b", "writer-c", "writer-a"]


def test_write_orchestrator_degrades_provider_failure_to_local_fallback() -> None:
    conn = make_prompt_compiled_shot()
    ids = _ids(conn)
    conn.execute("UPDATE writing_projects SET draft_count = 1 WHERE project_id = 1")
    provider = FailFirstDraftProvider()

    drafts = WriteOrchestrator(conn, LLMGateway(conn, provider=provider)).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )

    regular = [draft for draft in drafts if not draft.is_deviant]
    assert len(regular) == 1
    assert regular[0].degraded is True
    assert regular[0].failure_category == "LLMProviderError"
    assert regular[0].text.startswith("[degraded:LLMProviderError]")
    assert conn.execute(
        """
        SELECT success, error_category
        FROM writing_ai_call_attempts
        WHERE call_type = 'draft'
        ORDER BY attempt_id
        LIMIT 1
        """
    ).fetchone() == (0, "RuntimeError")


def test_write_orchestrator_entrypoint_signature_lints_clean() -> None:
    from ink.pipeline import write_orchestrator

    source = write_orchestrator.__loader__.get_source(write_orchestrator.__name__)
    assert lint_shot_orchestrator_source(source, "write_orchestrator.py") == []


def make_prompt_compiled_shot(*, creative: bool = False) -> sqlite3.Connection:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    conn.execute("DELETE FROM writing_drafts WHERE shot_id = ?", (ids["shot_id"],))
    insert_chinese_contract_children(conn, int(ids["shot_contract_id"]))
    if creative:
        conn.execute(
            "UPDATE writing_shot_persona_assignment SET is_creative_shot = 1 WHERE shot_contract_id = ?",
            (ids["shot_contract_id"],),
        )
    conn.commit()
    PreDraftingOrchestrator(conn, LLMGateway(conn, provider=OutlineProvider())).run_until_prompt_compiled(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    return conn


def _ids(conn: sqlite3.Connection) -> dict[str, int | str]:
    row = conn.execute(
        "SELECT shot_id, run_id, shot_contract_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
    ).fetchone()
    return {"shot_id": row[0], "run_id": row[1], "shot_contract_id": row[2]}


class OutlineProvider:
    def __init__(self) -> None:
        self.responses = [
            "她走进档案室发现钥匙门外脚步",
            "她走进档案室发现钥匙门外脚步并关上灯",
        ]

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        return ModelResult(text=self.responses.pop(0), model_name=model_name, token_input=1, token_output=1)


class RecordingDraftProvider:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        self.calls.append((model_name, idempotency_key))
        return ModelResult(
            text=f"{model_name}:{idempotency_key}:{prompt_text[:16]}",
            model_name=model_name,
            token_input=1,
            token_output=1,
        )


class FailFirstDraftProvider(RecordingDraftProvider):
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        if not self.calls:
            self.calls.append((model_name, idempotency_key))
            raise RuntimeError("provider down")
        return super().complete(prompt_text, model_name, idempotency_key)
