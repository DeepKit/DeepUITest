"""Character name consistency helpers."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any


DEFAULT_DEPRECATED_ALIASES = {
    "阿坤": "郑坤",
}


def deprecated_aliases_for_layers(layers: Mapping[str, Any] | None) -> dict[str, str]:
    """Return deprecated alias -> canonical name rules for a contract.

    Explicit contract mappings are read first. The project currently also has a
    known rename from 阿坤 to 郑坤; enable that rule only when 郑坤 is a declared
    POV/alive character and 阿坤 is not.
    """
    layers = layers or {}
    identity = layers.get("identity", {})
    hard = layers.get("hard_boundaries", {})
    declared = set(_as_str_list(identity.get("pov_characters")))
    declared.update(_as_str_list(hard.get("characters_alive")))

    aliases: dict[str, str] = {}
    for key in ("deprecated_aliases", "canonical_name_map", "name_aliases"):
        raw = identity.get(key)
        if isinstance(raw, Mapping):
            for alias, canonical in raw.items():
                if isinstance(alias, str) and isinstance(canonical, str):
                    aliases[alias] = canonical

    for alias, canonical in DEFAULT_DEPRECATED_ALIASES.items():
        if canonical in declared and alias not in declared:
            aliases.setdefault(alias, canonical)
    return aliases


def find_deprecated_aliases(text: str, aliases: Mapping[str, str]) -> list[dict[str, str]]:
    """Find deprecated aliases in text."""
    if not text or not aliases:
        return []
    hits: list[dict[str, str]] = []
    for alias, canonical in aliases.items():
        pos = text.find(alias)
        if pos < 0:
            continue
        start = max(0, pos - 24)
        end = min(len(text), pos + len(alias) + 36)
        hits.append({
            "alias": alias,
            "canonical": canonical,
            "context": text[start:end].replace("\n", " "),
        })
    return hits


def flatten_text(value: Any) -> str:
    """Flatten nested contract data into searchable text."""
    if isinstance(value, Mapping):
        return "\n".join(flatten_text(v) for v in value.values())
    if isinstance(value, (list, tuple, set)):
        return "\n".join(flatten_text(v) for v in value)
    if value is None:
        return ""
    return str(value)


def _as_str_list(value: Any) -> list[str]:
    if isinstance(value, (list, tuple, set)):
        return [str(v) for v in value if v]
    if isinstance(value, str):
        return [value]
    return []
