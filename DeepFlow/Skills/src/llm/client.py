"""
UniFlow LLM Client
==================
Asynchronous LLM chat client backed by LiteLLM.

Usage:
    config = LLMConfig(api_key=os.getenv("OPENAI_API_KEY"))
    client = LLMClient(config)
    result = await client.chat(
        messages=[{"role": "user", "content": "Hello"}],
        model="gpt-4o-mini",
    )
    await client.close()
"""

import structlog
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

logger = structlog.get_logger(__name__)


@dataclass
class LLMConfig:
    """LLM client configuration."""

    api_key: str = ""
    default_model: str = "gpt-4o-mini"
    base_url: str = ""
    timeout: float = 30.0
    max_retries: int = 3


@dataclass
class ChatResult:
    """Chat completion result."""

    content: str
    model: str
    usage: Dict[str, int] = field(default_factory=dict)
    finish_reason: str = "stop"
    truncated: bool = False  # T9: 输出被 max_tokens 截断（JSON 解析失败的常见根因，供降级诊断）


class LLMClient:
    """LiteLLM-based chat completion client."""

    def __init__(self, config: LLMConfig):
        self._config = config
        self._closed = False

    async def chat(
        self,
        messages: Optional[List[Dict[str, str]]] = None,
        model: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 4096,
        system: Optional[str] = None,
        user: Optional[str] = None,
    ) -> ChatResult:
        """
        Execute a chat completion.

        Args:
            messages: Chat messages ([{role, content}, ...])
            model: Model name override (defaults to config.default_model)
            temperature: Sampling temperature
            max_tokens: Maximum tokens to generate
            system: System prompt shortcut (creates system message)
            user: User prompt shortcut (creates user message)

        Returns:
            ChatResult with content, model, usage and finish reason

        Raises:
            RuntimeError: If client is closed or API key is not configured
        """
        if self._closed:
            raise RuntimeError("LLM client is closed")

        if not self._config.api_key:
            raise RuntimeError(
                "LLM API key is not configured (set OPENAI_API_KEY environment variable)"
            )

        # 支持 system/user 快捷参数：构造标准 messages
        if messages is None:
            messages = []
            if system:
                messages.append({"role": "system", "content": system})
            if user:
                messages.append({"role": "user", "content": user})

        import litellm

        model_name = model or self._config.default_model

        # 自定义网关 base_url 时，litellm 需要 provider 前缀（openai 兼容）
        if self._config.base_url and "/" not in model_name:
            model_name = f"openai/{model_name}"

        # 支持自定义网关 base_url（如 WiseGateway 127.0.0.1:8000）
        llm_kwargs: Dict[str, Any] = {
            "model": model_name,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "api_key": self._config.api_key,
            "timeout": self._config.timeout,
            "num_retries": self._config.max_retries,
        }
        if self._config.base_url:
            llm_kwargs["api_base"] = self._config.base_url

        logger.info(
            "LLM chat completion",
            model=model_name,
            base_url=self._config.base_url or "openai-default",
            messages_count=len(messages),
        )

        response = await litellm.acompletion(**llm_kwargs)

        choice = response.choices[0]
        usage = response.usage or None
        finish_reason = getattr(choice, "finish_reason", None) or "stop"
        truncated = finish_reason == "length"
        if truncated:
            logger.warning(
                "LLM output truncated by max_tokens (JSON 解析失败高风险)",
                model=model_name,
                max_tokens=max_tokens,
            )

        return ChatResult(
            content=(choice.message.content or "") if choice.message else "",
            model=response.model or model_name,
            usage={
                "prompt_tokens": getattr(usage, "prompt_tokens", 0) if usage else 0,
                "completion_tokens": getattr(usage, "completion_tokens", 0) if usage else 0,
                "total_tokens": getattr(usage, "total_tokens", 0) if usage else 0,
            },
            finish_reason=finish_reason,
            truncated=truncated,
        )

    async def close(self) -> None:
        """Close the client and release resources."""
        self._closed = True
        logger.info("LLM client closed")
