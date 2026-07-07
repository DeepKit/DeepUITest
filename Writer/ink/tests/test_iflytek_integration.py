"""iFLYTEK Coding Plan API integration tests for InkFlow LLMGateway.

These tests validate real HTTP connectivity to the iFLYTEK MaaS endpoint.
All tests are skipped unless the ``IFLYTEK_API_KEY`` environment variable is
set (format ``appId:apiKey``).

Run locally::

    set IFLYTEK_API_KEY=83e14cca3d4042e045c62358f11ffdfa:ZmFkMzNhMWVkOTY0NzYyYmZjZWFmYjFl
    pytest tests/test_iflytek_integration.py -v

The test suite covers:

* Direct provider reachability for the primary model (GLM-5.1).
* Reachability sweep across the 13 standard (non-reasoning) models.
* Reachability sweep for the 3 reasoning models (provider auto-injects max_tokens).
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

# 13 standard (non-reasoning) models — produce content directly
STANDARD_MODELS: list[str] = [
    "xopglm52",         # GLM-5.2 (Zhipu) — 卡，写作默认用 xopglm51
    "xopglm51",         # GLM-5.1 (Zhipu) — 写作主模型
    "xopglm5",          # GLM-5 (Zhipu)
    "xopkimik26",       # Kimi-K2.6 (Moonshot)
    "xopkimik25",       # Kimi-K2.5 (Moonshot)
    "xopdeepseekv4pro", # DeepSeek-V4-Pro
    "xopdeepseekv4flash", # DeepSeek-V4-Flash
    "xopdeepseekv32",   # DeepSeek-V3.2
    "xopqwen36v35b",    # Qwen-3.6-35B-A3B (Alibaba)
    "xopqwen35v35b",    # Qwen-3.5-35B-A3B (Alibaba)
    "xopqwen35397b",    # Qwen-3.5-397B-A17B (Alibaba) — 大模型，审阅用
    "xopglmv47flash",   # GLM-4.7-Flash (Zhipu)
    "xop3qwencodernext", # Qwen3-Coder-Next (Alibaba)
]

# 3 reasoning models — consume extra tokens for chain-of-thought
REASONING_MODELS: list[str] = [
    "xminimaxm25",      # MiniMax-M2.5
    "xsparkx2",         # Spark-X2 (iFLYTEK)
    "xsparkx2flash",    # Spark-X2-Flash (iFLYTEK)
]

ALL_MODELS: list[str] = STANDARD_MODELS + REASONING_MODELS

# 写作/裁判模型池推荐配置（见 docs/iflytek-model-config.md）
WRITER_MODEL_POOL: list[str] = ["xopglm51", "xopdeepseekv4pro", "xopkimik26"]
JURY_MODEL_POOL: list[str] = [
    "xopglm51", "xopdeepseekv4pro", "xopqwen36v35b",
    "xopkimik26", "xopqwen35397b",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


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
def reasoning_provider(api_key: str) -> OpenAICompatibleProvider:
    """Provider for reasoning models — auto-injects max_tokens via _is_reasoning_model."""
    return OpenAICompatibleProvider(
        base_url=IFLYTEK_BASE_URL,
        api_key=api_key,
        # 不传 max_tokens：推理模型由 _is_reasoning_model 自动注入默认值
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
        """GLM-5.1 (``xopglm51``,写作主模型) responds to a trivial prompt."""
        from ink.errors import LLMProviderError
        try:
            result = provider.complete(
                prompt_text="Reply with exactly: OK",
                model_name="xopglm51",
                idempotency_key="iflytek-smoke-001",
            )
        except LLMProviderError as exc:
            if "503" in str(exc):
                pytest.skip("iFLYTEK API overloaded — skipping smoke test")
            raise
        assert isinstance(result.text, str)
        assert result.text.strip(), "GLM-5.1 returned empty text"
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
        reasoning_provider: OpenAICompatibleProvider,
    ) -> None:
        """Reasoning models respond — provider auto-injects max_tokens via _is_reasoning_model."""
        from ink.errors import LLMProviderError
        for model_id in REASONING_MODELS:
            for attempt in range(3):
                try:
                    result = reasoning_provider.complete(
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
                model_name="xopglm51",
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
            model_name="xopglm51",
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
