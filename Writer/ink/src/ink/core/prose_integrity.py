from __future__ import annotations

import re


_LEADING_META_PATTERNS = (
    re.compile(r"^\s*好的[，,]\s*(收到|明白)"),
    re.compile(r"^\s*(以下|下面)(是|为).{0,20}(润色|改写|版本|正文)"),
    re.compile(r"^\s*我将(严格|在|对)"),
    re.compile(r"^\s*作为(?:一个|AI|语言模型)"),
)

_META_HEADINGS = (
    "主要调整说明",
    "修改说明",
    "润色说明",
    "改写说明",
    "调整说明",
    "整体节奏",
    "处理说明",
)


def find_generation_artifact(text: str) -> str | None:
    """Return a publication-breaking model/meta artifact, if present."""
    stripped = text.strip()
    if not stripped:
        return "empty_prose"
    for pattern in _LEADING_META_PATTERNS:
        match = pattern.search(stripped)
        if match:
            return match.group(0)
    for heading in _META_HEADINGS:
        if re.search(rf"(?:^|\n)\s*(?:\*\*)?{re.escape(heading)}(?:\*\*)?\s*(?:[:：]|\n|$)", stripped):
            return heading
    if stripped.startswith("```") or stripped.endswith("```"):
        return "markdown_code_fence"
    if stripped.startswith(("[mock:", "[deterministic:")) or "generated draft" in stripped[:200]:
        return "synthetic_provider_placeholder"
    return None


def extract_polished_prose(raw_text: str) -> str:
    """Strip common LLM wrappers while refusing unresolved editorial commentary."""
    text = raw_text.strip()
    if text.startswith("```") and text.endswith("```"):
        first_newline = text.find("\n")
        text = text[first_newline + 1 : -3].strip() if first_newline >= 0 else text.strip("`").strip()

    # Models often emit an intro, a separator, prose, another separator, then notes.
    leading_artifact = find_generation_artifact(text)
    if leading_artifact:
        first_separator = _find_separator(text)
        if first_separator is not None:
            text = text[first_separator[1] :].strip()

    cut_at = len(text)
    for heading in _META_HEADINGS:
        match = re.search(
            rf"(?:\n\s*---\s*)?\n\s*(?:\*\*)?{re.escape(heading)}(?:\*\*)?\s*(?:[:：]|\n|$)",
            text,
        )
        if match:
            cut_at = min(cut_at, match.start())
    text = text[:cut_at].strip()

    # Remove one wrapper separator, but retain internal literary scene breaks.
    if text.startswith("---"):
        text = text[3:].lstrip()
    if text.endswith("---"):
        text = text[:-3].rstrip()

    artifact = find_generation_artifact(text)
    if artifact:
        raise ValueError(f"polish output contains generation artifact: {artifact}")
    return text


def _find_separator(text: str) -> tuple[int, int] | None:
    match = re.search(r"(?:^|\n)\s*---\s*(?:\n|$)", text)
    return None if match is None else (match.start(), match.end())
