from __future__ import annotations


def fallback_draft_text(prompt_text: str, failure_category: str) -> str:
    excerpt = prompt_text.strip().splitlines()[0] if prompt_text.strip() else "empty prompt"
    return f"[degraded:{failure_category}] Local fallback draft for prompt: {excerpt}"
