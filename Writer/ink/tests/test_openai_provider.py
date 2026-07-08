"""OpenAICompatibleProvider HTTP 层单测。

验证：
1. 标准模型请求体不含 max_tokens（除非显式配置）
2. 推理模型自动注入 max_tokens 默认值
3. content 为空时回退 reasoning_content
4. LLMProviderConfig.max_tokens / INK_LLM_MAX_TOKENS 环境变量解析
"""
from __future__ import annotations

import json
import urllib.error
from io import BytesIO

import pytest

from ink.core.llm_gateway import (
    LLMProviderConfig,
    OpenAICompatibleProvider,
    _is_reasoning_model,
    _parse_chat_completion_response,
    build_model_provider,
    load_llm_provider_config,
)
from ink.errors import ConfigError, LLMProviderError


class _FakeResponse:
    def __init__(self, body: bytes) -> None:
        self._buf = BytesIO(body)

    def __enter__(self) -> "_FakeResponse":
        return self

    def __exit__(self, *args: object) -> None:
        self._buf.close()

    def read(self) -> bytes:
        return self._buf.read()


class _RecordingOpener:
    """捕获最后一次请求的 payload 和 headers。"""

    def __init__(self, response_body: bytes) -> None:
        self._body = response_body
        self.last_request: object | None = None

    def __call__(self, request, timeout: float | None = None):  # noqa: ANN001
        self.last_request = request
        return _FakeResponse(self._body)


def _make_payload(model: str, *, content: str | None, reasoning: str | None = None) -> bytes:
    message = {"role": "assistant"}
    if content is not None:
        message["content"] = content
    if reasoning is not None:
        message["reasoning_content"] = reasoning
    return json.dumps(
        {
            "id": "test",
            "model": model,
            "choices": [{"index": 0, "message": message, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 5, "completion_tokens": 10},
        }
    ).encode("utf-8")


# ---------------------------------------------------------------------------
# _is_reasoning_model
# ---------------------------------------------------------------------------


class TestIsReasoningModel:
    def test_sparkx2_models_detected(self) -> None:
        assert _is_reasoning_model("xsparkx2")
        assert _is_reasoning_model("xsparkx2flash")

    def test_minimax_models_detected(self) -> None:
        assert _is_reasoning_model("xminimaxm25")

    def test_standard_models_not_reasoning(self) -> None:
        assert not _is_reasoning_model("xopglm51")
        assert not _is_reasoning_model("xopdeepseekv4pro")
        assert not _is_reasoning_model("xopqwen36v35b")


# ---------------------------------------------------------------------------
# max_tokens 注入
# ---------------------------------------------------------------------------


class TestMaxTokensInjection:
    def test_standard_model_omits_max_tokens_by_default(self) -> None:
        opener = _RecordingOpener(_make_payload("xopglm51", content="hi"))
        provider = OpenAICompatibleProvider(
            base_url="https://example.com/v2",
            api_key="k",
            opener=opener,
        )
        provider.complete("prompt", "xopglm51", "key-1")
        request = opener.last_request
        body = json.loads(request.data)  # type: ignore[attr-defined]
        assert "max_tokens" not in body, "标准模型不应注入 max_tokens"

    def test_reasoning_model_auto_injects_max_tokens(self) -> None:
        opener = _RecordingOpener(_make_payload("xsparkx2flash", content="hi"))
        provider = OpenAICompatibleProvider(
            base_url="https://example.com/v2",
            api_key="k",
            opener=opener,
        )
        provider.complete("prompt", "xsparkx2flash", "key-2")
        body = json.loads(opener.last_request.data)  # type: ignore[attr-defined]
        assert body["max_tokens"] >= 500, "推理模型必须注入足量 max_tokens"

    def test_explicit_max_tokens_overrides_default(self) -> None:
        opener = _RecordingOpener(_make_payload("xopglm51", content="hi"))
        provider = OpenAICompatibleProvider(
            base_url="https://example.com/v2",
            api_key="k",
            opener=opener,
            max_tokens=1234,
        )
        provider.complete("prompt", "xopglm51", "key-3")
        body = json.loads(opener.last_request.data)  # type: ignore[attr-defined]
        assert body["max_tokens"] == 1234

    def test_explicit_max_tokens_applies_to_reasoning_too(self) -> None:
        opener = _RecordingOpener(_make_payload("xsparkx2flash", content="hi"))
        provider = OpenAICompatibleProvider(
            base_url="https://example.com/v2",
            api_key="k",
            opener=opener,
            max_tokens=800,
        )
        provider.complete("prompt", "xsparkx2flash", "key-4")
        body = json.loads(opener.last_request.data)  # type: ignore[attr-defined]
        assert body["max_tokens"] == 800


# ---------------------------------------------------------------------------
# reasoning_content 回退
# ---------------------------------------------------------------------------


class TestReasoningContentFallback:
    def test_content_present_uses_content(self) -> None:
        result = _parse_chat_completion_response(
            json.loads(_make_payload("xopglm51", content="answer", reasoning="thought")),
            fallback_model="xopglm51",
        )
        assert result.text == "answer"

    def test_content_empty_falls_back_to_reasoning(self) -> None:
        payload = json.loads(_make_payload("xsparkx2flash", content="", reasoning="思维链输出"))
        result = _parse_chat_completion_response(payload, fallback_model="xsparkx2flash")
        assert result.text == "思维链输出"

    def test_both_empty_raises(self) -> None:
        payload = json.loads(_make_payload("xsparkx2flash", content=None, reasoning=""))
        with pytest.raises(Exception):
            _parse_chat_completion_response(payload, fallback_model="xsparkx2flash")


# ---------------------------------------------------------------------------
# config / env 解析
# ---------------------------------------------------------------------------


class TestConfigMaxTokens:
    _ENV = {
        "INK_LLM_PROVIDER": "openai-compatible",
        "INK_LLM_BASE_URL": "https://x",
        "INK_LLM_API_KEY": "k",
    }

    def test_cli_max_tokens_param_precedence(self) -> None:
        config = load_llm_provider_config(
            env={**self._ENV, "INK_LLM_MAX_TOKENS": "999"},
            max_tokens=100,
        )
        assert config.max_tokens == 100

    def test_env_max_tokens_parsed(self) -> None:
        config = load_llm_provider_config(
            env={**self._ENV, "INK_LLM_MAX_TOKENS": "4096"},
        )
        assert config.max_tokens == 4096

    def test_invalid_env_max_tokens_raises(self) -> None:
        with pytest.raises(ConfigError):
            load_llm_provider_config(
                env={**self._ENV, "INK_LLM_MAX_TOKENS": "abc"},
            )

    def test_build_provider_passes_max_tokens(self) -> None:
        config = LLMProviderConfig(
            provider="openai-compatible",
            base_url="https://x",
            api_key="k",
            max_tokens=777,
        )
        provider = build_model_provider(config)
        assert isinstance(provider, OpenAICompatibleProvider)
        assert provider.max_tokens == 777


# ---------------------------------------------------------------------------
# 退避重试：429/5xx 重试、不可重试错误立即抛、成功不重试
# ---------------------------------------------------------------------------


class _FlakyOpener:
    """前 ``fail_n`` 次抛指定 HTTPError，之后返回成功响应。

    用于验证 provider 的退避重试逻辑。配合 ``retry_base_delay=0`` 避免真 sleep。
    """

    def __init__(self, *, fail_n: int, fail_code: int, success_body: bytes) -> None:
        self.fail_n = fail_n
        self.fail_code = fail_code
        self._success_body = success_body
        self.call_count = 0

    def __call__(self, request, timeout: float | None = None):  # noqa: ANN001
        self.call_count += 1
        if self.call_count <= self.fail_n:
            raise urllib.error.HTTPError(
                url="https://x/chat/completions",
                code=self.fail_code,
                msg="busy",
                hdrs=None,  # type: ignore[arg-type]
                fp=BytesIO(b'{"error":{"message":"busy"}}'),
            )
        return _FakeResponse(self._success_body)


class _AlwaysFailOpener:
    """每次都抛指定 HTTPError，用于验证重试耗尽后仍抛出。"""

    def __init__(self, code: int) -> None:
        self.code = code
        self.call_count = 0

    def __call__(self, request, timeout: float | None = None):  # noqa: ANN001
        self.call_count += 1
        raise urllib.error.HTTPError(
            url="https://x/chat/completions",
            code=self.code,
            msg="busy",
            hdrs=None,  # type: ignore[arg-type]
            fp=BytesIO(b'{"error":{"message":"busy"}}'),
        )


def _ok_body() -> bytes:
    return _make_payload("m", content="hi")


class TestProviderRetry:
    """429/5xx 退避重试，401 立即抛，成功不重试。"""

    def test_429_retried_then_succeeds(self) -> None:
        opener = _FlakyOpener(fail_n=2, fail_code=429, success_body=_ok_body())
        provider = OpenAICompatibleProvider(
            base_url="https://x", api_key="k",
            max_retries=3, retry_base_delay=0.0,
            opener=opener,
        )
        result = provider.complete("p", "m", "idem-1")
        assert result.text == "hi"
        assert opener.call_count == 3  # 2 次失败 + 1 次成功

    def test_503_retried_then_succeeds(self) -> None:
        opener = _FlakyOpener(fail_n=1, fail_code=503, success_body=_ok_body())
        provider = OpenAICompatibleProvider(
            base_url="https://x", api_key="k",
            max_retries=2, retry_base_delay=0.0,
            opener=opener,
        )
        result = provider.complete("p", "m", "idem-2")
        assert result.text == "hi"
        assert opener.call_count == 2

    def test_retries_exhausted_raises(self) -> None:
        opener = _AlwaysFailOpener(429)
        provider = OpenAICompatibleProvider(
            base_url="https://x", api_key="k",
            max_retries=2, retry_base_delay=0.0,
            opener=opener,
        )
        with pytest.raises(LLMProviderError, match="HTTP 429"):
            provider.complete("p", "m", "idem-3")
        # 1 次初始 + 2 次重试 = 3 次
        assert opener.call_count == 3

    def test_401_not_retried(self) -> None:
        opener = _AlwaysFailOpener(401)
        provider = OpenAICompatibleProvider(
            base_url="https://x", api_key="k",
            max_retries=4, retry_base_delay=0.0,
            opener=opener,
        )
        with pytest.raises(LLMProviderError, match="HTTP 401"):
            provider.complete("p", "m", "idem-4")
        assert opener.call_count == 1  # 认证错误立即抛，不重试

    def test_success_not_retried(self) -> None:
        opener = _FlakyOpener(fail_n=0, fail_code=429, success_body=_ok_body())
        provider = OpenAICompatibleProvider(
            base_url="https://x", api_key="k",
            max_retries=4, retry_base_delay=0.0,
            opener=opener,
        )
        provider.complete("p", "m", "idem-5")
        assert opener.call_count == 1

    def test_default_no_retries(self) -> None:
        """未配置 max_retries 时(默认 0)，429 直接抛，不重试(保持既有行为)。"""
        opener = _AlwaysFailOpener(429)
        provider = OpenAICompatibleProvider(
            base_url="https://x", api_key="k",
            opener=opener,  # max_retries 默认 0
        )
        with pytest.raises(LLMProviderError, match="HTTP 429"):
            provider.complete("p", "m", "idem-6")
        assert opener.call_count == 1

    def test_config_default_retries_for_openai_compatible(self) -> None:
        """load_llm_provider_config 对 openai-compatible 默认 max_retries=4。"""
        config = load_llm_provider_config(
            provider="openai-compatible",
            base_url="https://x",
            api_key="k",
            env={},
        )
        assert config.max_retries == 4
