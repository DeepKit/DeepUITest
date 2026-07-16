from __future__ import annotations

import json
import sqlite3

import pytest

from ink.config import ProjectConfigValidator, load_project_config
from ink.core.llm_gateway import (
    LLMGateway,
    ModelResult,
    OpenAICompatibleProvider,
    build_model_provider,
    load_llm_provider_config,
)
from ink.core.state_machine import transition
from ink.core.text_repository import TextRepository
from ink.database import connect
from ink.errors import (
    ConcurrentModificationError,
    ConfigError,
    DataIntegrityError,
    IllegalTransitionError,
    TerminalStateError,
)
from factories import NOW, insert_minimal_draft, make_schema_db


def test_database_connect_initializes_schema_and_enables_foreign_keys() -> None:
    conn = connect(initialize=True)

    assert conn.execute("PRAGMA foreign_keys").fetchone()[0] == 1
    assert conn.execute("SELECT count(*) FROM sqlite_master WHERE name='writing_projects'").fetchone()[0] == 1


def test_project_config_validator_accepts_valid_project_config() -> None:
    conn = make_schema_db()
    insert_minimal_draft(conn)

    config = load_project_config(conn, 1)

    assert config.project_id == 1
    assert config.draft_count == 3
    assert config.writer_model_pool == ("writer-a", "writer-b", "writer-c")
    assert config.jury_model_pool_min == 3


def test_project_config_validator_rejects_duplicate_and_overlapping_models() -> None:
    conn = make_schema_db()
    row = dict(
        project_id=1,
        code="demo",
        title="Demo",
        draft_count=2,
        writer_model_pool='["writer-a","writer-a"]',
        jury_model_pool='["judge-a","judge-b","judge-c"]',
        jury_model_pool_min=3,
        shot_quality_floor=80,
        dimension_floor=65,
        chapter_quality_floor=75,
        book_quality_floor=75,
        judge_disagreement_max=25,
        reader_pull_floor=75,
        blind_review_min_passes=2,
        max_calls_per_shot=8,
        max_total_llm_calls=40,
        consecutive_failure_circuit_break=3,
    )

    with pytest.raises(ConfigError):
        ProjectConfigValidator().validate(_Row(row))

    row["writer_model_pool"] = '["writer-a","writer-b"]'
    row["jury_model_pool"] = '["writer-a","judge-b","judge-c"]'
    with pytest.raises(ConfigError):
        ProjectConfigValidator().validate(_Row(row))


def test_state_machine_allows_legal_transition_and_rejects_illegal_or_stale() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)

    transition(conn, str(ids["shot_id"]), int(ids["run_id"]), "pending", "outline_draft")
    status = conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0]
    assert status == "outline_draft"

    with pytest.raises(IllegalTransitionError):
        transition(conn, str(ids["shot_id"]), int(ids["run_id"]), "outline_draft", "drafting")

    with pytest.raises(ConcurrentModificationError):
        transition(conn, str(ids["shot_id"]), int(ids["run_id"]), "pending", "outline_draft")

    with pytest.raises(TerminalStateError):
        transition(conn, str(ids["shot_id"]), int(ids["run_id"]), "failed", "pending")


def test_text_repository_write_and_read_current_text_with_hard_seal() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    conn.commit()
    repo = TextRepository(conn)

    repo.write_revision(str(ids["shot_id"]), int(ids["run_id"]), "draft one")
    assert repo.read_current_text(str(ids["shot_id"]), int(ids["run_id"])) == "draft one"

    first_sealed_id = repo.write_revision(
        str(ids["shot_id"]),
        int(ids["run_id"]),
        "sealed one",
        seal="chapter_hard",
    )
    repo.write_revision(str(ids["shot_id"]), int(ids["run_id"]), "newer unsealed")

    assert repo.read_current_text(str(ids["shot_id"]), int(ids["run_id"])) == "sealed one"
    assert repo.is_hard_sealed(str(ids["shot_id"]), int(ids["run_id"])) is True
    current_rows = conn.execute(
        "SELECT revision_id FROM writing_shot_revisions WHERE shot_id = ? AND is_current = 1",
        (ids["shot_id"],),
    ).fetchall()
    assert current_rows == [(first_sealed_id,)]


def test_text_repository_raises_when_no_revision_exists() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)

    with pytest.raises(DataIntegrityError):
        TextRepository(conn).read_current_text(str(ids["shot_id"]), int(ids["run_id"]))


def test_llm_gateway_records_attempt_and_runtime_event() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)

    result = LLMGateway(conn).call(
        project_id=int(ids["project_id"]),
        shot_id=str(ids["shot_id"]),
        run_id=int(ids["run_id"]),
        call_type="draft",
        prompt_id=int(ids["prompt_id"]),
        prompt_text="write scene",
        model_name="mock-model",
        idempotency_key="draft-1",
    )

    assert result.text == "scene text mock-model draft-1"
    attempt = conn.execute("SELECT success, response_hash FROM writing_ai_call_attempts").fetchone()
    assert attempt[0] == 1
    assert attempt[1]
    event = conn.execute("SELECT event_type FROM writing_runtime_events").fetchone()
    assert event[0] == "LLM_CALL_SUCCEEDED"


def test_llm_provider_config_defaults_to_mock_and_rejects_incomplete_real_provider() -> None:
    config = load_llm_provider_config(env={})

    assert config.provider == "mock"
    assert build_model_provider(config).__class__.__name__ == "MockProvider"

    with pytest.raises(ConfigError, match="INK_LLM_BASE_URL"):
        load_llm_provider_config(env={}, provider="openai-compatible")
    with pytest.raises(ConfigError, match="INK_LLM_API_KEY"):
        load_llm_provider_config(
            env={"INK_LLM_BASE_URL": "https://llm.example/v1"},
            provider="openai-compatible",
        )


def test_openai_compatible_provider_posts_chat_completion_and_records_provider() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    seen = {}

    def opener(request, *, timeout):
        seen["url"] = request.full_url
        seen["authorization"] = request.get_header("Authorization")
        seen["idempotency_key"] = request.get_header("Idempotency-key")
        seen["timeout"] = timeout
        seen["body"] = json.loads(request.data.decode("utf-8"))
        return _FakeHTTPResponse(
            {
                "model": "writer-real",
                "choices": [{"message": {"content": "real provider text"}, "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 7, "completion_tokens": 3},
            }
        )

    config = load_llm_provider_config(
        env={"INK_LLM_BASE_URL": "https://llm.example/v1", "INK_LLM_API_KEY": "secret"},
        provider="openai-compatible",
        timeout_seconds=12.0,
    )
    provider = OpenAICompatibleProvider(
        base_url=config.base_url,
        api_key=config.api_key,
        timeout_seconds=config.timeout_seconds,
        opener=opener,
    )

    result = LLMGateway(conn, provider=provider, provider_name=config.provider).call(
        project_id=int(ids["project_id"]),
        shot_id=str(ids["shot_id"]),
        run_id=int(ids["run_id"]),
        call_type="draft",
        prompt_id=int(ids["prompt_id"]),
        prompt_text="write scene",
        model_name="writer-real",
        idempotency_key="draft-real-1",
    )

    assert result == ModelResult(
        text="real provider text",
        model_name="writer-real",
        token_input=7,
        token_output=3,
        finish_reason="stop",
    )
    assert seen == {
        "url": "https://llm.example/v1/chat/completions",
        "authorization": "Bearer secret",
        "idempotency_key": "draft-real-1",
        "timeout": 12.0,
        "body": {"model": "writer-real", "messages": [{"role": "user", "content": "write scene"}]},
    }
    assert conn.execute("SELECT model_provider, success FROM writing_ai_call_attempts").fetchone() == (
        "openai-compatible",
        1,
    )


class _Row:
    def __init__(self, data: dict) -> None:
        self._data = data

    def __getitem__(self, key):
        return self._data[key]


class _FakeHTTPResponse:
    def __init__(self, payload: dict) -> None:
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        return None

    def read(self) -> bytes:
        return json.dumps(self.payload).encode("utf-8")

