from __future__ import annotations

import json

import pytest

from ink.core.checkpoint_manager import CheckpointManager
from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.core.resume import ResumeManager
from ink.core.retry_budget import LLMCallBudget, SoftGateCounter
from ink.errors import LLMProviderError
from ink.errors import DataIntegrityError
from factories import NOW, insert_minimal_draft, insert_raw_score, make_schema_db


def test_soft_gate_counter_db_authority_and_threshold_levels() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    counter = SoftGateCounter(conn)

    assert counter.get_level(1, "shot-001", "reader_pull") == 0
    assert counter.increment(1, "shot-001", "reader_pull") == 1
    assert counter.get_level(1, "shot-001", "reader_pull") == 1
    assert counter.increment(1, "shot-001", "reader_pull") == 2
    assert counter.get_level(1, "shot-001", "reader_pull") == 2
    assert counter.increment(1, "shot-001", "reader_pull") == 3
    assert counter.get_level(1, "shot-001", "reader_pull") == 3

    stored = conn.execute(
        "SELECT n, last_level FROM writing_soft_gate_counters WHERE project_id = ? AND logical_shot_id = ?",
        (ids["project_id"], "shot-001"),
    ).fetchone()
    assert stored == (3, 3)


def test_llm_failure_streaks_and_budget_circuit() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    conn.execute(
        "UPDATE writing_projects SET max_calls_per_shot = 5, max_total_llm_calls = 9, consecutive_failure_circuit_break = 3"
    )
    budget = LLMCallBudget(conn, 1)

    for _ in range(2):
        budget.record_call(str(ids["shot_id"]), "draft", success=False, failure_type="timeout")
    assert budget.check_circuit(str(ids["shot_id"]), int(ids["run_id"])) == (True, None)

    budget.record_call(str(ids["shot_id"]), "draft", success=False, failure_type="timeout")
    assert budget.check_circuit(str(ids["shot_id"]), int(ids["run_id"])) == (False, "consecutive_fail")

    budget.record_call(str(ids["shot_id"]), "draft", success=True)
    assert budget.check_circuit(str(ids["shot_id"]), int(ids["run_id"])) == (True, None)


def test_total_llm_budget_transitions_failed() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    conn.execute("UPDATE writing_projects SET max_total_llm_calls = 2, max_calls_per_shot = 10")
    budget = LLMCallBudget(conn, 1)

    budget.record_call(str(ids["shot_id"]), "draft", success=True)
    assert budget.check_circuit(str(ids["shot_id"]), int(ids["run_id"])) == (True, None)
    budget.record_call(str(ids["shot_id"]), "jury", success=True)

    assert budget.check_circuit(str(ids["shot_id"]), int(ids["run_id"])) == (False, "total_exceeded")
    status = conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0]
    assert status == "failed"


def test_llm_gateway_integrates_budget_and_failure_streaks() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    gateway = LLMGateway(conn, provider=FailOnceProvider())

    with pytest.raises(LLMProviderError):
        gateway.call(
            project_id=int(ids["project_id"]),
            shot_id=str(ids["shot_id"]),
            run_id=int(ids["run_id"]),
            call_type="draft",
            prompt_id=int(ids["prompt_id"]),
            prompt_text="write scene",
            model_name="writer-a",
            idempotency_key="draft-fail",
        )

    assert conn.execute("SELECT llm_call_count FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == 1
    streak = conn.execute(
        """
        SELECT failure_type, consecutive_count
        FROM writing_llm_failure_streaks
        WHERE shot_id = ? AND call_type = 'draft'
        """,
        (ids["shot_id"],),
    ).fetchone()
    assert streak == ("RuntimeError", 1)

    result = gateway.call(
        project_id=int(ids["project_id"]),
        shot_id=str(ids["shot_id"]),
        run_id=int(ids["run_id"]),
        call_type="draft",
        prompt_id=int(ids["prompt_id"]),
        prompt_text="write scene",
        model_name="writer-b",
        idempotency_key="draft-ok",
    )

    assert result.text == "ok"
    assert conn.execute("SELECT llm_call_count FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == 2
    reset = conn.execute(
        """
        SELECT consecutive_count
        FROM writing_llm_failure_streaks
        WHERE shot_id = ? AND call_type = 'draft' AND failure_type = 'RuntimeError'
        """,
        (ids["shot_id"],),
    ).fetchone()
    assert reset == (0,)


def test_resume_manager_maps_status_and_rejects_cross_session_resume() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    manager = ResumeManager(conn)

    assert manager.resume_shot(10, str(ids["shot_id"]), int(ids["run_id"])) == "start_from_scratch"
    conn.execute("UPDATE writing_shots SET status = 'jury_scoring' WHERE shot_id = ?", (ids["shot_id"],))
    assert manager.resume_shot(10, str(ids["shot_id"]), int(ids["run_id"])) == "rerun_jury"

    with pytest.raises(DataIntegrityError):
        manager.resume_shot(999, str(ids["shot_id"]), int(ids["run_id"]))


def test_resume_manager_handles_redo_in_progress_branches() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    manager = ResumeManager(conn)
    conn.execute(
        "UPDATE writing_shots SET status = 'winner_selected', redo_in_progress = 1 WHERE shot_id = ?",
        (ids["shot_id"],),
    )

    assert manager.resume_shot(10, str(ids["shot_id"]), int(ids["run_id"])) == "rerun_soft_gate_redo_drafting"

    cur = conn.execute(
        """
        INSERT INTO writing_drafts
            (shot_id, prompt_id, persona, writer_model, text, retry_count, byte_count, created_at)
        VALUES (?, ?, 'text', 'writer-b', 'redo draft', 1, 10, ?)
        """,
        (ids["shot_id"], ids["prompt_id"], NOW),
    )
    assert manager.resume_shot(10, str(ids["shot_id"]), int(ids["run_id"])) == "rerun_soft_gate_redo_jury"

    insert_raw_score(conn, cur.lastrowid, ids["shot_contract_id"], 1, 1, "judge-a", "text")
    assert manager.resume_shot(10, str(ids["shot_id"]), int(ids["run_id"])) == "rerun_winner_select"


def test_resume_point_parser_requires_structured_fields() -> None:
    manager = ResumeManager(make_schema_db())

    assert manager.parse_resume_point('{"phase":"jury","chapter_id":1,"dimension_index":3}') == {
        "phase": "jury",
        "chapter_id": 1,
        "dimension_index": 3,
    }
    assert manager.parse_resume_point('{"phase":"import_finalize","import_run_id":1}') == {
        "phase": "import_finalize",
        "import_run_id": 1,
    }
    with pytest.raises(DataIntegrityError):
        manager.parse_resume_point('{"phase":"bad"}')


def test_resume_manager_execute_resume_action_dispatches_configured_handler() -> None:
    manager = ResumeManager(make_schema_db())
    calls = []

    result = manager.execute_resume_action(
        "shot-001@20",
        20,
        "rerun_prompt",
        {"rerun_prompt": lambda shot_id, run_id: calls.append((shot_id, run_id)) or "done"},
    )

    assert result == "done"
    assert calls == [("shot-001@20", 20)]
    assert manager.execute_resume_action("shot-001@20", 20, "skip", {}) is None
    with pytest.raises(DataIntegrityError):
        manager.execute_resume_action("shot-001@20", 20, "rerun_missing", {})


def test_checkpoint_manager_checksum_recovery_and_corruption_event() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    manager = CheckpointManager(conn)

    good_id = manager.save_checkpoint(10, "drafting", {"phase": "drafting", "run_id": ids["run_id"]})
    bad_id = manager.save_checkpoint(10, "jury", {"phase": "jury", "run_id": ids["run_id"]})
    conn.execute(
        "UPDATE writing_session_checkpoints SET checkpoint_payload = ? WHERE checkpoint_id = ?",
        (json.dumps({"phase": "corrupted"}, sort_keys=True), bad_id),
    )

    checkpoint_id, payload = manager.load_latest_valid_checkpoint(10)

    assert checkpoint_id == good_id
    assert payload["phase"] == "drafting"
    event = conn.execute("SELECT event_type FROM writing_runtime_events").fetchone()
    assert event[0] == "CHECKPOINT_CORRUPTED"


def test_checkpoint_manager_retention_uses_project_setting() -> None:
    conn = make_schema_db()
    insert_minimal_draft(conn)
    conn.execute("UPDATE writing_projects SET checkpoint_max_retention = 2 WHERE project_id = 1")
    manager = CheckpointManager(conn)

    for index in range(4):
        manager.save_checkpoint(10, f"phase-{index}", {"phase": f"phase-{index}"})

    rows = conn.execute(
        "SELECT phase FROM writing_session_checkpoints WHERE session_id = 10 ORDER BY checkpoint_id"
    ).fetchall()
    assert rows == [("phase-2",), ("phase-3",)]


class FailOnceProvider:
    def __init__(self) -> None:
        self.calls = 0

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        self.calls += 1
        if self.calls == 1:
            raise RuntimeError("temporary failure")
        return ModelResult(text="ok", model_name=model_name, token_input=1, token_output=1)

