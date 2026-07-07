"""iFLYTEK Coding Plan API integration tests for InkFlow LLMGateway.

These tests validate real HTTP connectivity to the iFLYTEK MaaS endpoint.
All tests are skipped unless the ``IFLYTEK_API_KEY`` environment variable is
set (format ``appId:apiKey``).

Run locally::

    set IFLYTEK_API_KEY=83e14cca3d4042e045c62358f11ffdfa:ZmFkMzNhMWVkOTY0NzYyYmZjZWFmYjFl
    pytest tests/test_iflytek_integration.py -v

The test suite covers:

* Direct provider reachability for the primary model (GLM-5.2).
* Reachability sweep across the 11 standard (non-reasoning) models.
* Reachability sweep for the 3 reasoning models (max_tokens capped at 500).
* End-to-end ``LLMGateway.call()`` through an ``OpenAICompatibleProvider``.
* ``LLMExtractionAdapter`` clause extraction via iFLYTEK.
"""
from __future__ import annotations

import os
import time

import pytest

from factories import make_schema_db
from ink.core.llm_gateway import (
    LLMGateway,
    ModelResult,
    OpenAICompatibleProvider,
)
from ink.source_normalizer import LLMExtractionAdapter

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

IFLYTEK_BASE_URL = "https://maas-coding-api.cn-huabei-1.xf-yun.com/v2"

IFLYTEK_API_KEY_ENV = "IFLYTEK_API_KEY"

# 11 standard (non-reasoning) models — produce content directly
STANDARD_MODELS: list[str] = [
    "xopglm52",         # GLM-5.2 (Zhipu)
    "xopglm51",         # GLM-5.1 (Zhipu)
    "xopglm5",          # GLM-5 (Zhipu)
    "xopkimik26",       # Kimi-K2.6 (Moonshot)
    "xopkimik25",       # Kimi-K2.5 (Moonshot)
    "xopdeepseekv4pro", # DeepSeek-V4-Pro
    "xopdeepseekv4flash", # DeepSeek-V4-Flash
    "xopdeepseekv32",   # DeepSeek-V3.2
    "xopqwen36v35b",   # Qwen-3.6-35B (Alibaba)
    "xopglmv47flash",   # GLM-4.7-Flash (Zhipu)
    "xop3qwencodernext", # Qwen-Coder-Next (Alibaba)
]

# 3 reasoning models — consume extra tokens for chain-of-thought
REASONING_MODELS: list[str] = [
    "xminimaxm25",      # MiniMax-M2.5
    "xsparkx2",         # Spark-X2 (iFLYTEK)
    "xsparkx2flash",    # Spark-X2-Flash (iFLYTEK)
]

ALL_MODELS: list[str] = STANDARD_MODELS + REASONING_MODELS


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

class _BoundedMaxTokensProvider(OpenAICompatibleProvider):
    """``OpenAICompatibleProvider`` subclass that injects ``max_tokens``."""

    def __init__(self, *, base_url: str, api_key: str, max_tokens: int) -> None:
        super().__init__(base_url=base_url, api_key=api_key)
        self._max_tokens = max_tokens

    def complete(
        self,
        prompt_text: str,
        model_name: str,
        idempotency_key: str,
    ) -> ModelResult:
        # Inject max_tokens into the payload before the upstream call.
        import json
        import urllib.error
        import urllib.request

        from ink.errors import LLMProviderError

        payload = {
            "model": model_name,
            "messages": [{"role": "user", "content": prompt_text}],
            "max_tokens": self._max_tokens,
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

        # Re-use the gateway's response parser.
        from ink.core.llm_gateway import _parse_chat_completion_response

        return _parse_chat_completion_response(response_payload, fallback_model=model_name)


def _insert_project(conn, project_id: int = 0) -> None:
    """Insert the minimal ``writing_projects`` row needed by LLMGateway FKs.

    CHECK constraints require ``json_array_length(writer_model_pool) >= draft_count``
    (default 3) and ``json_array_length(jury_model_pool) >= jury_model_pool_min`` (default 3).
    """
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (?, 'iflytek-test', 'iFLYTEK Test',
                '["writer-a","writer-b","writer-c"]',
                '["judge-a","judge-b","judge-c"]',
                '2026-01-01T00:00:00Z')
        """,
        (project_id,),
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def _skip_if_no_key() -> str:
    """Return the raw API key or skip the test."""
    key = os.environ.get(IFLYTEK_API_KEY_ENV, "").strip()
    if not key:
        pytest.skip(f"{IFLYTEK_API_KEY_ENV} not set — skipping iFLYTEK integration")
    return key


@pytest.fixture()
def api_key() -> str:
    return _skip_if_no_key()


@pytest.fixture()
def provider(api_key: str) -> OpenAICompatibleProvider:
    """Fresh ``OpenAICompatibleProvider`` pointing to iFLYTEK."""
    return OpenAICompatibleProvider(
        base_url=IFLYTEK_BASE_URL,
        api_key=api_key,
    )


@pytest.fixture()
def bounded_provider(api_key: str) -> _BoundedMaxTokensProvider:
    """Provider that injects ``max_tokens=500`` for reasoning models."""
    return _BoundedMaxTokensProvider(
        base_url=IFLYTEK_BASE_URL,
        api_key=api_key,
        max_tokens=500,
    )


@pytest.fixture()
def gateway_conn():
    """In-memory schema DB with a project row pre-inserted."""
    conn = make_schema_db()
    _insert_project(conn)
    return conn


@pytest.fixture()
def gateway(gateway_conn, provider: OpenAICompatibleProvider) -> LLMGateway:
    """``LLMGateway`` wired to the iFLYTEK provider."""
    return LLMGateway(gateway_conn, provider=provider, provider_name="iflytek")


# ---------------------------------------------------------------------------
# TestIFlytekConnectivity — direct provider-level reachability
# ---------------------------------------------------------------------------

class TestIFlytekConnectivity:
    """Verify the iFLYTEK Coding Plan API responds for registered models."""

    def test_single_model_reachable(
        self,
        provider: OpenAICompatibleProvider,
    ) -> None:
        """GLM-5.2 (``xopglm52``) responds to a trivial prompt."""
        from ink.errors import LLMProviderError
        try:
            result = provider.complete(
                prompt_text="Reply with exactly: OK",
                model_name="xopglm52",
                idempotency_key="iflytek-smoke-001",
            )
        except LLMProviderError as exc:
            if "503" in str(exc):
                pytest.skip("iFLYTEK API overloaded — skipping smoke test")
            raise
        assert isinstance(result.text, str)
        assert result.text.strip(), "GLM-5.2 returned empty text"
        assert result.model_name, "response should include a model name"

    def test_all_standard_models_reachable(
        self,
        provider: OpenAICompatibleProvider,
    ) -> None:
        """All 11 standard (non-reasoning) models return non-empty responses."""
        from ink.errors import LLMProviderError
        for model_id in STANDARD_MODELS:
            for attempt in range(3):
                try:
                    result = provider.complete(
                        prompt_text="Say hello in one word.",
                        model_name=model_id,
                        idempotency_key=f"iflytek-std-{model_id}-{attempt}",
                    )
                    assert result.text.strip(), f"model {model_id} returned empty text"
                    break
                except LLMProviderError as exc:
                    if "503" in str(exc) and attempt < 2:
                        time.sleep(3)
                        continue
                    raise

    def test_reasoning_models_reachable(
        self,
        bounded_provider: _BoundedMaxTokensProvider,
    ) -> None:
        """The 3 reasoning models respond with ``max_tokens=500``."""
        from ink.errors import LLMProviderError
        for model_id in REASONING_MODELS:
            for attempt in range(3):
                try:
                    result = bounded_provider.complete(
                        prompt_text="Explain 2+2=4 in one sentence.",
                        model_name=model_id,
                        idempotency_key=f"iflytek-rsn-{model_id}-{attempt}",
                    )
                    assert result.text.strip(), f"reasoning model {model_id} returned empty text"
                    break
                except LLMProviderError as exc:
                    if "503" in str(exc) and attempt < 2:
                        time.sleep(3)
                        continue
                    raise


# ---------------------------------------------------------------------------
# TestLLMGatewayIntegration — gateway-level integration
# ---------------------------------------------------------------------------

class TestLLMGatewayIntegration:
    """End-to-end tests through ``LLMGateway`` with iFLYTEK as the provider."""

    def test_gateway_complete_with_iflytek(
        self,
        gateway: LLMGateway,
    ) -> None:
        """``LLMGateway.call()`` returns non-empty text via iFLYTEK."""
        from ink.errors import LLMProviderError
        try:
            result = gateway.call(
                project_id=0,
                shot_id=None,
                run_id=None,
                call_type="source_extraction",
                prompt_id=None,
                prompt_text="Write a haiku about the moon.",
                model_name="xopglm52",
                idempotency_key="iflytek-gw-complete-001",
            )
        except LLMProviderError as exc:
            if "503" in str(exc):
                pytest.skip("iFLYTEK API overloaded — skipping gateway test")
            raise
        assert isinstance(result.text, str)
        assert result.text.strip(), "gateway complete returned empty text"
        assert result.model_name

    def test_gateway_extracts_clauses(
        self,
        gateway: LLMGateway,
    ) -> None:
        """``LLMExtractionAdapter`` parses a writing guide into clauses."""
        from ink.errors import LLMProviderError
        # Wait to avoid rate limiting from previous sweep tests.
        time.sleep(5)
        adapter = LLMExtractionAdapter(
            gateway,
            model_name="xopglm52",
            project_id=0,
        )
        sample_text = (
            "# Writing Guide\n\n"
            "1. The protagonist must never break their core promise to the reader.\n"
            "2. Use short, punchy sentences during action scenes.\n"
            "3. Every chapter must end with a hook that pulls the reader forward.\n"
        )
        try:
            clauses = adapter(sample_text, "writing_guide.md")
        except LLMProviderError as exc:
            if "503" in str(exc):
                pytest.skip("iFLYTEK API overloaded — skipping extraction test")
            raise

        assert isinstance(clauses, list), "adapter should return a list"
        assert len(clauses) > 0, "expected at least one extracted clause"

        # Validate clause schema.
        required_keys = {"scope_type", "scope_id", "clause_type", "severity", "clause_text"}
        for clause in clauses:
            missing = required_keys - set(clause.keys())
            assert not missing, f"clause missing keys: {missing}"
            assert isinstance(clause["clause_text"], str)
            assert clause["clause_text"].strip(), "clause_text must be non-empty"
