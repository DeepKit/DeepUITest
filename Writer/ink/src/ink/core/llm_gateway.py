from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass
from typing import Protocol

from ink.core.retry_budget import LLMCallBudget
from ink.errors import LLMProviderError
from ink.time import now_utc_iso


@dataclass(frozen=True)
class ModelResult:
    text: str
    model_name: str
    token_input: int = 0
    token_output: int = 0
    finish_reason: str = "stop"


class ModelProvider(Protocol):
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        ...


class MockProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        return ModelResult(
            text=f"[mock:{model_name}:{idempotency_key}] generated draft",
            model_name=model_name,
            token_input=len(prompt_text.split()),
            token_output=1,
        )


class LLMGateway:
    def __init__(self, conn: sqlite3.Connection, provider: ModelProvider | None = None) -> None:
        self.conn = conn
        self.provider = provider or MockProvider()

    def call(
        self,
        *,
        project_id: int,
        shot_id: str | None,
        run_id: int | None,
        call_type: str,
        prompt_id: int | None,
        prompt_text: str,
        model_name: str,
        idempotency_key: str,
        model_provider: str = "mock",
    ) -> ModelResult:
        budget = LLMCallBudget(self.conn, project_id) if shot_id is not None and run_id is not None else None
        if budget is not None:
            allowed, reason = budget.check_circuit(shot_id, run_id)
            if not allowed:
                self._write_event(project_id, shot_id, run_id, "LLM_BUDGET_BLOCKED", {"reason": reason})
                raise LLMProviderError(f"LLM budget blocked: {reason}")

        now = now_utc_iso()
        prompt_hash = _sha256(prompt_text)
        cursor = self.conn.execute(
            """
            INSERT INTO writing_ai_call_attempts
                (project_id, shot_id, run_id, call_type, model_provider, model_name, idempotency_key,
                 prompt_id, prompt_hash, success, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
            """,
            (
                project_id,
                shot_id,
                run_id,
                call_type,
                model_provider,
                model_name,
                idempotency_key,
                prompt_id,
                prompt_hash,
                now,
            ),
        )
        attempt_id = int(cursor.lastrowid)

        try:
            result = self.provider.complete(prompt_text, model_name, idempotency_key)
        except Exception as exc:
            self.conn.execute(
                """
                UPDATE writing_ai_call_attempts
                SET success = 0, error_category = ?
                WHERE attempt_id = ?
                """,
                (type(exc).__name__, attempt_id),
            )
            if budget is not None:
                budget.record_call(shot_id, call_type, success=False, failure_type=type(exc).__name__)
            self._write_event(project_id, shot_id, run_id, "LLM_CALL_FAILED", {"attempt_id": attempt_id})
            raise LLMProviderError(str(exc)) from exc

        response_hash = _sha256(result.text)
        if budget is not None:
            budget.record_call(shot_id, call_type, success=True)
            budget.check_circuit(shot_id, run_id)
        self.conn.execute(
            """
            UPDATE writing_ai_call_attempts
            SET success = 1, response_hash = ?, token_input = ?, token_output = ?, finish_reason = ?
            WHERE attempt_id = ?
            """,
            (response_hash, result.token_input, result.token_output, result.finish_reason, attempt_id),
        )
        self._write_event(project_id, shot_id, run_id, "LLM_CALL_SUCCEEDED", {"attempt_id": attempt_id})
        return result

    def _write_event(
        self,
        project_id: int,
        shot_id: str | None,
        run_id: int | None,
        event_type: str,
        payload: dict,
    ) -> None:
        self.conn.execute(
            """
            INSERT INTO writing_runtime_events
                (project_id, run_id, shot_id, event_type, event_payload, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (project_id, run_id, shot_id, event_type, json.dumps(payload, sort_keys=True), now_utc_iso()),
        )


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()
