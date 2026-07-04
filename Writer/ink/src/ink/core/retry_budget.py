from __future__ import annotations

import json
import sqlite3
from typing import Literal

from ink.core.state_machine import TERMINAL_STATES, load_status, transition
from ink.time import now_utc_iso


SoftGateLevel = Literal[0, 1, 2, 3]


class SoftGateCounter:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def increment(self, project_id: int, logical_shot_id: str, gate_name: str) -> int:
        now = now_utc_iso()
        self.conn.execute(
            """
            INSERT INTO writing_soft_gate_counters
                (project_id, logical_shot_id, gate_name, n, last_incremented_at, last_level)
            VALUES (?, ?, ?, 1, ?, 1)
            ON CONFLICT(project_id, logical_shot_id, gate_name)
            DO UPDATE SET
                n = writing_soft_gate_counters.n + 1,
                last_incremented_at = excluded.last_incremented_at
            """,
            (project_id, logical_shot_id, gate_name, now),
        )
        n = self._get_n(project_id, logical_shot_id, gate_name)
        level = self.get_level(project_id, logical_shot_id, gate_name)
        self.conn.execute(
            """
            UPDATE writing_soft_gate_counters
            SET last_level = ?
            WHERE project_id = ? AND logical_shot_id = ? AND gate_name = ?
            """,
            (level, project_id, logical_shot_id, gate_name),
        )
        return n

    def get_level(self, project_id: int, logical_shot_id: str, gate_name: str) -> SoftGateLevel:
        n = self._get_n(project_id, logical_shot_id, gate_name)
        if n == 0:
            return 0
        redo_n, fail_n = self._thresholds(project_id)
        if n >= fail_n:
            return 3
        if n >= redo_n:
            return 2
        return 1

    def reset(self, project_id: int, logical_shot_id: str, gate_name: str) -> None:
        self.conn.execute(
            """
            UPDATE writing_soft_gate_counters
            SET n = 0, last_level = 0, last_incremented_at = ?
            WHERE project_id = ? AND logical_shot_id = ? AND gate_name = ?
            """,
            (now_utc_iso(), project_id, logical_shot_id, gate_name),
        )

    def _get_n(self, project_id: int, logical_shot_id: str, gate_name: str) -> int:
        row = self.conn.execute(
            """
            SELECT n
            FROM writing_soft_gate_counters
            WHERE project_id = ? AND logical_shot_id = ? AND gate_name = ?
            """,
            (project_id, logical_shot_id, gate_name),
        ).fetchone()
        return 0 if row is None else int(row[0])

    def _thresholds(self, project_id: int) -> tuple[int, int]:
        row = self.conn.execute(
            "SELECT soft_gate_redo_n, soft_gate_fail_n FROM writing_projects WHERE project_id = ?",
            (project_id,),
        ).fetchone()
        if row is None:
            return (2, 3)
        return int(row[0]), int(row[1])


class LLMCallBudget:
    def __init__(self, conn: sqlite3.Connection, project_id: int) -> None:
        self.conn = conn
        self.project_id = project_id

    def record_call(self, shot_id: str, call_type: str, success: bool, failure_type: str | None = None) -> None:
        row = self.conn.execute(
            "SELECT llm_call_count, llm_call_breakdown FROM writing_shots WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()
        if row is None:
            raise ValueError(f"shot not found: {shot_id}")

        breakdown = json.loads(row[1] or "{}")
        breakdown[call_type] = int(breakdown.get(call_type, 0)) + 1
        self.conn.execute(
            """
            UPDATE writing_shots
            SET llm_call_count = llm_call_count + 1,
                llm_call_breakdown = ?,
                updated_at = ?
            WHERE shot_id = ?
            """,
            (json.dumps(breakdown, sort_keys=True), now_utc_iso(), shot_id),
        )

        if success:
            self.conn.execute(
                """
                UPDATE writing_llm_failure_streaks
                SET consecutive_count = 0, last_error_at = ?
                WHERE shot_id = ? AND call_type = ?
                """,
                (now_utc_iso(), shot_id, call_type),
            )
            return

        failure = failure_type or "unknown"
        self.conn.execute(
            """
            INSERT INTO writing_llm_failure_streaks
                (shot_id, call_type, failure_type, consecutive_count, last_error_at)
            VALUES (?, ?, ?, 1, ?)
            ON CONFLICT(shot_id, call_type, failure_type)
            DO UPDATE SET
                consecutive_count = writing_llm_failure_streaks.consecutive_count + 1,
                last_error_at = excluded.last_error_at
            """,
            (shot_id, call_type, failure, now_utc_iso()),
        )

    def check_circuit(self, shot_id: str, run_id: int) -> tuple[bool, str | None]:
        max_per_type, max_total, max_consecutive = self._thresholds()
        row = self.conn.execute(
            "SELECT llm_call_count, llm_call_breakdown FROM writing_shots WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()
        if row is None:
            raise ValueError(f"shot not found: {shot_id}")

        total = int(row[0])
        if total >= max_total:
            self._fail_shot_if_possible(shot_id, run_id)
            return False, "total_exceeded"

        breakdown = json.loads(row[1] or "{}")
        if any(int(count) >= max_per_type for count in breakdown.values()):
            return False, "per_type_exceeded"

        streak = self.conn.execute(
            """
            SELECT max(consecutive_count)
            FROM writing_llm_failure_streaks
            WHERE shot_id = ?
            """,
            (shot_id,),
        ).fetchone()[0]
        if streak is not None and int(streak) >= max_consecutive:
            return False, "consecutive_fail"

        return True, None

    def _thresholds(self) -> tuple[int, int, int]:
        row = self.conn.execute(
            """
            SELECT max_calls_per_shot, max_total_llm_calls, consecutive_failure_circuit_break
            FROM writing_projects
            WHERE project_id = ?
            """,
            (self.project_id,),
        ).fetchone()
        return int(row[0]), int(row[1]), int(row[2])

    def _fail_shot_if_possible(self, shot_id: str, run_id: int) -> None:
        status = load_status(self.conn, shot_id, run_id)
        if status is not None and status not in TERMINAL_STATES:
            transition(self.conn, shot_id, run_id, status, "failed")
