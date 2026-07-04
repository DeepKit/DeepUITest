from __future__ import annotations

import hashlib
import json
import sqlite3

from ink.time import now_utc_iso


class CheckpointManager:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def save_checkpoint(
        self,
        session_id: int,
        phase: str,
        payload: dict,
        run_id: int | None = None,
        shot_id: str | None = None,
    ) -> int:
        payload_json = json.dumps(payload, sort_keys=True, ensure_ascii=False)
        checksum = _sha256(payload_json)
        cursor = self.conn.execute(
            """
            INSERT INTO writing_session_checkpoints
                (session_id, run_id, shot_id, phase, checkpoint_payload, payload_checksum, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (session_id, run_id, shot_id, phase, payload_json, checksum, now_utc_iso()),
        )
        checkpoint_id = int(cursor.lastrowid)
        self._trim_old_checkpoints(session_id)
        return checkpoint_id

    def load_latest_valid_checkpoint(self, session_id: int) -> tuple[int, dict] | None:
        checkpoints = self.conn.execute(
            """
            SELECT checkpoint_id, checkpoint_payload, payload_checksum
            FROM writing_session_checkpoints
            WHERE session_id = ?
            ORDER BY created_at DESC, checkpoint_id DESC
            """,
            (session_id,),
        ).fetchall()

        for checkpoint_id, payload_json, checksum in checkpoints:
            computed = _sha256(str(payload_json))
            if computed == checksum:
                return int(checkpoint_id), json.loads(payload_json)
            self._record_corruption(session_id, int(checkpoint_id), str(checksum), computed)
        return None

    def _trim_old_checkpoints(self, session_id: int) -> None:
        retention = self.conn.execute(
            """
            SELECT p.checkpoint_max_retention
            FROM writing_projects p
            JOIN writing_sessions s ON s.project_id = p.project_id
            WHERE s.session_id = ?
            """,
            (session_id,),
        ).fetchone()[0]
        self.conn.execute(
            """
            DELETE FROM writing_session_checkpoints
            WHERE session_id = ? AND checkpoint_id NOT IN (
                SELECT checkpoint_id
                FROM writing_session_checkpoints
                WHERE session_id = ?
                ORDER BY created_at DESC, checkpoint_id DESC
                LIMIT ?
            )
            """,
            (session_id, session_id, int(retention)),
        )

    def _record_corruption(self, session_id: int, checkpoint_id: int, expected: str, actual: str) -> None:
        project_id = self.conn.execute(
            "SELECT project_id FROM writing_sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()[0]
        self.conn.execute(
            """
            INSERT INTO writing_runtime_events
                (project_id, session_id, event_type, event_payload, created_at)
            VALUES (?, ?, 'CHECKPOINT_CORRUPTED', ?, ?)
            """,
            (
                int(project_id),
                session_id,
                json.dumps({"checkpoint_id": checkpoint_id, "expected": expected, "actual": actual}, sort_keys=True),
                now_utc_iso(),
            ),
        )


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()
