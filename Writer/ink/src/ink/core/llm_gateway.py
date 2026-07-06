from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import urllib.error
import urllib.request
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Protocol

from ink.core.retry_budget import LLMCallBudget
from ink.errors import ConfigError, LLMProviderError
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


@dataclass(frozen=True)
class LLMProviderConfig:
    provider: str
    base_url: str | None = None
    api_key: str | None = None
    timeout_seconds: float = 60.0


class MockProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        return ModelResult(
            text=f"[mock:{model_name}:{idempotency_key}] generated draft",
            model_name=model_name,
            token_input=len(prompt_text.split()),
            token_output=1,
        )


class OpenAICompatibleProvider:
    def __init__(
        self,
        *,
        base_url: str,
        api_key: str,
        timeout_seconds: float = 60.0,
        opener: Callable[..., object] | None = None,
    ) -> None:
        if not base_url.strip():
            raise ConfigError("LLM provider base_url must be non-empty")
        if not api_key.strip():
            raise ConfigError("LLM provider api_key must be non-empty")
        if timeout_seconds <= 0:
            raise ConfigError("LLM provider timeout_seconds must be positive")
        self.endpoint = f"{base_url.rstrip('/')}/chat/completions"
        self.api_key = api_key
        self.timeout_seconds = timeout_seconds
        self._opener = opener or urllib.request.urlopen

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        payload = {
            "model": model_name,
            "messages": [{"role": "user", "content": prompt_text}],
        }
        request = urllib.request.Request(
            self.endpoint,
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
                "Idempotency-Key": idempotency_key,
            },
            method="POST",
        )
        try:
            with self._opener(request, timeout=self.timeout_seconds) as response:
                response_payload = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise LLMProviderError(f"provider HTTP {exc.code}: {body[:200]}") from exc
        except urllib.error.URLError as exc:
            raise LLMProviderError(f"provider request failed: {exc.reason}") from exc
        except json.JSONDecodeError as exc:
            raise LLMProviderError("provider returned invalid JSON") from exc
        return _parse_chat_completion_response(response_payload, fallback_model=model_name)


class LLMGateway:
    def __init__(
        self,
        conn: sqlite3.Connection,
        provider: ModelProvider | None = None,
        *,
        provider_name: str | None = None,
    ) -> None:
        self.conn = conn
        self.provider = provider or MockProvider()
        self.provider_name = provider_name or ("mock" if provider is None else provider.__class__.__name__)

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
        model_provider: str | None = None,
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
                model_provider or self.provider_name,
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


def load_llm_provider_config(
    *,
    env: Mapping[str, str] | None = None,
    provider: str | None = None,
    base_url: str | None = None,
    api_key: str | None = None,
    api_key_env: str | None = None,
    timeout_seconds: float | None = None,
) -> LLMProviderConfig:
    source = os.environ if env is None else env
    provider_name = (provider or source.get("INK_LLM_PROVIDER") or "mock").strip().lower().replace("_", "-")
    if provider_name == "mock":
        return LLMProviderConfig(provider="mock")
    if provider_name != "openai-compatible":
        raise ConfigError(f"unsupported LLM provider: {provider_name}")

    resolved_base_url = base_url or source.get("INK_LLM_BASE_URL")
    key_env = api_key_env or source.get("INK_LLM_API_KEY_ENV") or "INK_LLM_API_KEY"
    resolved_api_key = api_key or source.get(key_env)
    timeout_raw: object = timeout_seconds if timeout_seconds is not None else source.get("INK_LLM_TIMEOUT_SECONDS", 60.0)
    try:
        resolved_timeout = float(timeout_raw)
    except (TypeError, ValueError) as exc:
        raise ConfigError("INK_LLM_TIMEOUT_SECONDS must be numeric") from exc
    if resolved_timeout <= 0:
        raise ConfigError("INK_LLM_TIMEOUT_SECONDS must be positive")

    if not resolved_base_url:
        raise ConfigError("openai-compatible provider requires INK_LLM_BASE_URL or --llm-base-url")
    if not resolved_api_key:
        raise ConfigError(f"openai-compatible provider requires API key in {key_env}")
    return LLMProviderConfig(
        provider="openai-compatible",
        base_url=resolved_base_url,
        api_key=resolved_api_key,
        timeout_seconds=resolved_timeout,
    )


def build_model_provider(config: LLMProviderConfig) -> ModelProvider:
    if config.provider == "mock":
        return MockProvider()
    if config.provider == "openai-compatible":
        if config.base_url is None or config.api_key is None:
            raise ConfigError("openai-compatible provider config is incomplete")
        return OpenAICompatibleProvider(
            base_url=config.base_url,
            api_key=config.api_key,
            timeout_seconds=config.timeout_seconds,
        )
    raise ConfigError(f"unsupported LLM provider: {config.provider}")


def _parse_chat_completion_response(payload: object, *, fallback_model: str) -> ModelResult:
    if not isinstance(payload, dict):
        raise LLMProviderError("provider response must be a JSON object")
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        raise LLMProviderError("provider response missing choices")
    choice = choices[0]
    if not isinstance(choice, dict):
        raise LLMProviderError("provider response choice must be an object")
    message = choice.get("message")
    text = message.get("content") if isinstance(message, dict) else choice.get("text")
    if not isinstance(text, str) or not text:
        raise LLMProviderError("provider response missing text content")
    usage = payload.get("usage")
    usage_data = usage if isinstance(usage, dict) else {}
    return ModelResult(
        text=text,
        model_name=str(payload.get("model") or fallback_model),
        token_input=int(usage_data.get("prompt_tokens") or 0),
        token_output=int(usage_data.get("completion_tokens") or 0),
        finish_reason=str(choice.get("finish_reason") or "stop"),
    )
