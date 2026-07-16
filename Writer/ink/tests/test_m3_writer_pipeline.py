from __future__ import annotations

import json
import sqlite3

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.core.resume import ResumeManager
from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator
from ink.linting.orchestrator_signature import lint_shot_orchestrator_source
from test_m2_contract_outline import insert_chinese_contract_children
from factories import insert_minimal_draft, make_schema_db


def test_write_orchestrator_produces_same_persona_same_prompt_with_distinct_models_and_deviant() -> None:
    conn = make_prompt_compiled_shot()
    ids = _ids(conn)
    provider = RecordingDraftProvider()
    orchestrator = WriteOrchestrator(conn, LLMGateway(conn, provider=provider))

    drafts = orchestrator.produce_drafts(str(ids["shot_id"]), int(ids["run_id"]))

    regular = [draft for draft in drafts if not draft.is_deviant]
    deviant = [draft for draft in drafts if draft.is_deviant]
    # shot_id 起点偏移后顺序不再固定，但 3 候选仍覆盖全部 3 个不同模型（去重无垄断）
    assert {draft.writer_model for draft in regular} == {"writer-a", "writer-b", "writer-c"}
    assert len(regular) == 3
    assert len({draft.prompt_id for draft in regular}) == 1
    assert {draft.persona for draft in regular} == {"悬疑官"}
    assert len(deviant) == 1
    assert deviant[0].prompt_id != regular[0].prompt_id
    assert conn.execute(
        "SELECT relaxed_soft FROM writing_prompt_snapshots WHERE prompt_id = ?",
        (deviant[0].prompt_id,),
    ).fetchone()[0] == 1
    payload = conn.execute(
        """
        SELECT context_payload
        FROM writing_context_snapshots
        WHERE prompt_id = ?
        """,
        (deviant[0].prompt_id,),
    ).fetchone()[0]
    assert json.loads(payload)["relaxed_soft"] is True
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
    # shot_id 偏移后起点不固定，但 4 候选均来自 3 模型池且环绕（某模型恰好重复两次）
    pool = {"writer-a", "writer-b", "writer-c"}
    assert {draft.writer_model for draft in regular} == pool
    # 4 候选来自 3 模型 → 恰有一个模型出现两次（环绕）
    counts = [sum(1 for d in regular if d.writer_model == m) for m in pool]
    assert sorted(counts) == [1, 1, 2]


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


def test_write_orchestrator_resume_handler_reruns_drafting() -> None:
    conn = make_prompt_compiled_shot()
    ids = _ids(conn)
    provider = RecordingDraftProvider()
    orchestrator = WriteOrchestrator(conn, LLMGateway(conn, provider=provider))

    result = ResumeManager(conn).execute_resume_action(
        str(ids["shot_id"]),
        int(ids["run_id"]),
        "rerun_drafting",
        orchestrator.resume_handlers(),
    )

    regular = [draft for draft in result if not draft.is_deviant]
    assert len(regular) == 3
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "hard_gate1"


def test_write_orchestrator_redo_candidates_are_retry_drafts_and_idempotent() -> None:
    conn = make_prompt_compiled_shot()
    ids = _ids(conn)
    conn.execute("UPDATE writing_projects SET redo_candidate_count = 2 WHERE project_id = 1")
    WriteOrchestrator(conn, LLMGateway(conn, provider=RecordingDraftProvider())).produce_drafts(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    conn.execute(
        "UPDATE writing_shots SET status = 'winner_selected', redo_in_progress = 1 WHERE shot_id = ?",
        (ids["shot_id"],),
    )
    orchestrator = WriteOrchestrator(conn, LLMGateway(conn, provider=RecordingDraftProvider()))
    manager = ResumeManager(conn)

    assert manager.resume_shot(10, str(ids["shot_id"]), int(ids["run_id"])) == "rerun_soft_gate_redo_drafting"
    first = manager.execute_resume_action(
        str(ids["shot_id"]),
        int(ids["run_id"]),
        "rerun_soft_gate_redo_drafting",
        orchestrator.resume_handlers(),
    )
    second = manager.execute_resume_action(
        str(ids["shot_id"]),
        int(ids["run_id"]),
        "rerun_soft_gate_redo_drafting",
        orchestrator.resume_handlers(),
    )

    assert len(first) == 2
    assert [draft.retry_count for draft in first] == [1, 1]
    assert [draft.is_deviant for draft in first] == [False, False]
    assert [draft.draft_id for draft in second] == [draft.draft_id for draft in first]
    assert manager.resume_shot(10, str(ids["shot_id"]), int(ids["run_id"])) == "rerun_soft_gate_redo_jury"
    status = conn.execute(
        "SELECT status, redo_in_progress FROM writing_shots WHERE shot_id = ?",
        (ids["shot_id"],),
    ).fetchone()
    assert status == ("winner_selected", 1)


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


def test_select_writer_models_shot_id_offset_breaks_concentration() -> None:
    """shot_id 起点偏移破候选集中化：不同 shot 候选起点不同，避免前段模型恒占位。

    E11 诊断 writer 候选集中于 pool 前段。pool=4 模型、count=2 时：
    - 无 shot_id（兼容）：恒为 (m0, m1)
    - 不同 shot_id：起点偏移使候选子集不同，跨 4 shot 至少覆盖 3+ 不同模型
    - 同 shot_id 幂等：两次调用结果一致
    """
    from ink.writers.model_pool import select_writer_models

    pool = ("m0", "m1", "m2", "m3")

    # 兼容：无 shot_id 回退固定起点
    assert select_writer_models(pool, 2) == ("m0", "m1")

    # 幂等：同一 shot_id 两次一致
    assert select_writer_models(pool, 2, shot_id="shot-A") == select_writer_models(pool, 2, shot_id="shot-A")

    # 跨 shot 覆盖均衡：4 个 shot 的候选集合并集覆盖全部 4 模型（破前段集中）
    all_picked = set()
    for sid in ("shot-A", "shot-B", "shot-C", "shot-D"):
        all_picked.update(select_writer_models(pool, 2, shot_id=sid))
    assert all_picked == set(pool)


def test_select_writer_models_pool_smaller_than_count_wraps() -> None:
    """pool 小于 count 时跨池环绕，偏移后仍覆盖全池（无遗漏）。"""
    from ink.writers.model_pool import select_writer_models

    pool = ("m0", "m1")
    result = select_writer_models(pool, 3, shot_id="shot-X")
    assert len(result) == 3
    assert set(result) == set(pool)

