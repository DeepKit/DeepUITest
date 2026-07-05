from __future__ import annotations

import hashlib
import json
import sqlite3
from collections.abc import Sequence

from ink.time import now_utc_iso


def save_context_snapshot(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    shot_id: str,
    run_id: int,
    prompt_id: int | None,
    upstream_revision_ids: Sequence[int],
    context_payload: dict[str, object],
) -> int:
    upstream_json = json.dumps(list(upstream_revision_ids), sort_keys=True)
    payload_json = json.dumps(context_payload, ensure_ascii=False, sort_keys=True)
    context_hash = hashlib.sha256(f"{upstream_json}\n{payload_json}".encode("utf-8")).hexdigest()
    cursor = conn.execute(
        """
        INSERT INTO writing_context_snapshots
            (project_id, shot_id, run_id, prompt_id, context_hash,
             upstream_revision_ids, context_payload, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            project_id,
            shot_id,
            run_id,
            prompt_id,
            context_hash,
            upstream_json,
            payload_json,
            now_utc_iso(),
        ),
    )
    return int(cursor.lastrowid)


def prompt_context_payload(
    *,
    task_card_id: int,
    persona: str,
    relaxed_soft: bool,
    target_reader: str | None = None,
    voice_samples: Sequence[str] = (),
    voice_anti_samples: Sequence[str] = (),
    correction_feedback: Sequence[str] = (),
) -> dict[str, object]:
    clipped_items = []
    for field_name, value in (
        ("target_reader", target_reader),
        ("voice_samples", voice_samples),
        ("voice_anti_samples", voice_anti_samples),
        ("correction_feedback", correction_feedback),
    ):
        if value in (None, "", ()):
            clipped_items.append(
                {
                    "field": field_name,
                    "reason": "not available in current contract baseline",
                }
            )

    return {
        "task_card_id": task_card_id,
        "persona": persona,
        "relaxed_soft": relaxed_soft,
        "target_reader": target_reader,
        "voice_samples": list(voice_samples),
        "voice_anti_samples": list(voice_anti_samples),
        "correction_feedback": list(correction_feedback),
        "clipped_items": clipped_items,
    }
