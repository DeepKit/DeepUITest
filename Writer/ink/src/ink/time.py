from __future__ import annotations

from datetime import UTC, datetime


def now_utc_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
