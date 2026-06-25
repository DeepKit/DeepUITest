"""Hashing utilities for InkFlow.

Provides:
- _canonical_hash: shared deterministic hash of dicts (DRY)
- snapshot_hash: deterministic hash of contract snapshots
- text_hash_normalized: space-insensitive + Unicode-NFC-normalized hash
- context_hash: hash of context assembly state
- config_hash: hash of project config for snapshot comparison
"""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata


def _canonical_hash(data: dict) -> str:
    """Compute a deterministic SHA-256 hash of a dict with sorted keys."""
    canonical = json.dumps(data, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:12]


def snapshot_hash(data: dict | str) -> str:
    """Compute a deterministic hash of a contract snapshot.

    JSON keys are sorted for deterministic output. Delegates to _canonical_hash.
    """
    if isinstance(data, str):
        data = json.loads(data)
    return _canonical_hash(data)


def text_hash_normalized(text: str) -> str:
    """Compute a space-insensitive, Unicode-NFC-normalized hash of text.

    NFC normalization ensures that visually identical CJK and accented
    characters produce the same hash regardless of composition form.
    """
    normalized = _normalize_text(text)
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:12]


def context_hash(data: dict) -> str:
    """Compute a hash of context assembly state. Delegates to _canonical_hash."""
    return _canonical_hash(data)


def config_hash(data: dict) -> str:
    """Compute a hash of project config. Delegates to _canonical_hash."""
    return _canonical_hash(data)


def _normalize_text(text: str) -> str:
    """NFC-normalize Unicode, then collapse all whitespace sequences."""
    text = unicodedata.normalize("NFC", text)
    return re.sub(r"\s+", " ", text).strip()