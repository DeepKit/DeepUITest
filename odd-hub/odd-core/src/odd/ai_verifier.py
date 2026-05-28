"""
AI 语义验证�?�?调用 LLM 对代码语义做深度验证
"""

from __future__ import annotations
import json
import os
from typing import Any


_SYSTEM_PROMPT = """\
你是一个严格的代码契约审查员�?用户会给你一段代码和一份契约描述，你需要判断代码是否在语义上满足契约要求�?只返�?JSON，不要有任何额外文字�?"""

_USER_TEMPLATE = """\
## 契约
名称：{name}
描述：{description}
要求摘要�?{hints_summary}

## 代码
```
{code}
```

请返回如�?JSON�?{{
  "passed": true/false,
  "confidence": 0.0-1.0,
  "summary": "一句话总结",
  "issues": ["问题1", "问题2"]
}}
"""


class AIVerifier:
    """调用 LLM 对代码做语义级验证（第二层）"""

    def __init__(self, api_key: str | None = None, model: str = "gpt-4o-mini",
                 base_url: str | None = None):
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY", "")
        self.model = model
        self.base_url = base_url or os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")

    def verify(self, code: str, contract: dict[str, Any]) -> dict[str, Any]:
        """
        对代码做语义验证�?
        Returns:
            {
                "passed": bool,
                "confidence": float,
                "summary": str,
                "issues": list[str],
                "skipped": bool,   # True when API key missing
            }
        """
        if not self.api_key:
            return {
                "passed": True,
                "confidence": 0.0,
                "summary": "跳过 AI 验证（未配置 OPENAI_API_KEY�?,
                "issues": [],
                "skipped": True,
            }

        hints_summary = _build_hints_summary(contract.get("verification_hints", {}))
        user_msg = _USER_TEMPLATE.format(
            name=contract.get("name", ""),
            description=contract.get("description", ""),
            hints_summary=hints_summary,
            code=code[:6000],  # 避免超出 context window
        )

        try:
            result = _call_llm(
                api_key=self.api_key,
                base_url=self.base_url,
                model=self.model,
                system=_SYSTEM_PROMPT,
                user=user_msg,
            )
            return {**result, "skipped": False}
        except Exception as exc:
            return {
                "passed": False,
                "confidence": 0.0,
                "summary": f"AI 验证调用失败：{exc}",
                "issues": [str(exc)],
                "skipped": False,
            }


# ── helpers ───────────────────────────────────────────────────────────────────

def _build_hints_summary(hints: dict) -> str:
    lines: list[str] = []
    for rule in hints.get("must_contain_any", []):
        lines.append(f"- 必须包含（任一）：{rule.get('patterns', [])}  原因：{rule.get('reason', '')}")
    for rule in hints.get("must_not_contain", []):
        lines.append(f"- 禁止包含：{rule.get('patterns', [])}  原因：{rule.get('reason', '')}")
    for rule in hints.get("should_contain", []):
        lines.append(f"- 建议包含：{rule.get('patterns', [])}  原因：{rule.get('reason', '')}")
    return "\n".join(lines) if lines else "（无具体规则�?


def _call_llm(api_key: str, base_url: str, model: str,
              system: str, user: str) -> dict[str, Any]:
    """最小化 HTTP 调用，不依赖 openai SDK，只用标准库 urllib"""
    import urllib.request

    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0,
        "response_format": {"type": "json_object"},
    }).encode()

    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/chat/completions",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.loads(resp.read())

    content = body["choices"][0]["message"]["content"]
    return json.loads(content)
