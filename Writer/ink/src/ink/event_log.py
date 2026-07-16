"""Append-only event log for decision sessions and contract versions.

在现有 in-place UPDATE 模式上追加轻量 event log，提供状态回放能力。
不改变现有状态机逻辑，只在关键转换点追加事件记录。
"""
from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from typing import Any

from ink.time import now_utc_iso


@dataclass(frozen=True)
class EventRecord:
    """单条事件记录。"""
    event_id: int
    event_type: str
    payload: dict[str, Any]
    created_at: str


SESSION_EVENT_TYPES = frozenset({
    "created", "input_received", "ai_parsed", "option_set_created",
    "option_selected", "option_regenerated", "confirmed", "cancelled", "stale",
})

VERSION_EVENT_TYPES = frozenset({
    "created", "confirmed", "locked", "superseded", "stale",
})


class EventLog:
    """Append-only event log。

    所有写入都是 INSERT，不做 UPDATE 或 DELETE。
    事件序列可以按时间排序回放，还原任意时间点状态。
    """

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    # ------------------------------------------------------------------
    # 写入
    # ------------------------------------------------------------------

    def log_session_event(
        self,
        decision_session_id: int,
        event_type: str,
        payload: dict[str, Any] | None = None,
    ) -> int:
        """追加一条 decision session 事件。

        event_type 必须是 SESSION_EVENT_TYPES 中的值。
        """
        if event_type not in SESSION_EVENT_TYPES:
            raise ValueError(f"invalid session event type: {event_type}")

        now = now_utc_iso()
        cursor = self.conn.execute(
            """
            INSERT INTO writing_decision_session_events
                (decision_session_id, event_type, payload_json, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (
                decision_session_id,
                event_type,
                json.dumps(payload or {}, ensure_ascii=False, sort_keys=True),
                now,
            ),
        )
        return int(cursor.lastrowid)

    def log_version_event(
        self,
        project_id: int,
        event_type: str,
        scope_type: str,
        payload: dict[str, Any] | None = None,
        *,
        contract_version_id: int | None = None,
        scope_id: str | None = None,
    ) -> int:
        """追加一条 contract version 事件。

        event_type 必须是 VERSION_EVENT_TYPES 中的值。
        """
        if event_type not in VERSION_EVENT_TYPES:
            raise ValueError(f"invalid version event type: {event_type}")

        now = now_utc_iso()
        cursor = self.conn.execute(
            """
            INSERT INTO writing_contract_version_events
                (project_id, contract_version_id, event_type, scope_type, scope_id,
                 payload_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                project_id,
                contract_version_id,
                event_type,
                scope_type,
                scope_id,
                json.dumps(payload or {}, ensure_ascii=False, sort_keys=True),
                now,
            ),
        )
        return int(cursor.lastrowid)

    # ------------------------------------------------------------------
    # 回放
    # ------------------------------------------------------------------

    def replay_session(self, decision_session_id: int) -> list[EventRecord]:
        """回放某个 session 的事件序列（按 created_at 排序）。"""
        rows = self.conn.execute(
            """
            SELECT event_id, event_type, payload_json, created_at
            FROM writing_decision_session_events
            WHERE decision_session_id = ?
            ORDER BY event_id
            """,
            (decision_session_id,),
        ).fetchall()
        return [
            EventRecord(
                event_id=int(row[0]),
                event_type=str(row[1]),
                payload=json.loads(str(row[2])),
                created_at=str(row[3]),
            )
            for row in rows
        ]

    def replay_version(
        self,
        project_id: int,
        scope_type: str,
        scope_id: str | None = None,
    ) -> list[EventRecord]:
        """回放某个 scope 的契约版本事件序列。"""
        query = [
            "SELECT event_id, event_type, payload_json, created_at",
            "FROM writing_contract_version_events",
            "WHERE project_id = ? AND scope_type = ?",
        ]
        params: list[Any] = [project_id, scope_type]

        if scope_id is not None:
            query.append("AND scope_id = ?")
            params.append(scope_id)
        else:
            query.append("AND scope_id IS NULL")

        query.append("ORDER BY event_id")

        rows = self.conn.execute("\n".join(query), params).fetchall()
        return [
            EventRecord(
                event_id=int(row[0]),
                event_type=str(row[1]),
                payload=json.loads(str(row[2])),
                created_at=str(row[3]),
            )
            for row in rows
        ]

    # ------------------------------------------------------------------
    # 查询
    # ------------------------------------------------------------------

    def latest_session_event(
        self,
        decision_session_id: int,
    ) -> EventRecord | None:
        """查询某 session 的最新事件。"""
        row = self.conn.execute(
            """
            SELECT event_id, event_type, payload_json, created_at
            FROM writing_decision_session_events
            WHERE decision_session_id = ?
            ORDER BY event_id DESC LIMIT 1
            """,
            (decision_session_id,),
        ).fetchone()
        if row is None:
            return None
        return EventRecord(
            event_id=int(row[0]),
            event_type=str(row[1]),
            payload=json.loads(str(row[2])),
            created_at=str(row[3]),
        )

    def count_session_events(self, decision_session_id: int) -> int:
        """查询某 session 的事件总数。"""
        row = self.conn.execute(
            "SELECT count(*) FROM writing_decision_session_events WHERE decision_session_id = ?",
            (decision_session_id,),
        ).fetchone()
        return int(row[0])

    def count_version_events(
        self,
        project_id: int,
        scope_type: str,
        scope_id: str | None = None,
    ) -> int:
        """查询某 scope 的版本事件总数。"""
        query = [
            "SELECT count(*) FROM writing_contract_version_events",
            "WHERE project_id = ? AND scope_type = ?",
        ]
        params: list[Any] = [project_id, scope_type]

        if scope_id is not None:
            query.append("AND scope_id = ?")
            params.append(scope_id)
        else:
            query.append("AND scope_id IS NULL")

        row = self.conn.execute("\n".join(query), params).fetchone()
        return int(row[0])
