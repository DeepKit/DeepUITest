"""专家模式可展开审计视图。

为 CLI ``--debug`` 模式和 ``debug`` 子命令组提供后台角色决策证据查询。
聚合 session 事件、契约版本时间线、shot 全链路追踪、stale 传播链。
"""
from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from typing import Any


@dataclass
class SessionAudit:
    """Session 审计聚合。"""
    session_id: int
    events: list[dict[str, Any]] = field(default_factory=list)
    patches: list[dict[str, Any]] = field(default_factory=list)
    contract_versions: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class ContractTimelineEntry:
    """契约时间线条目。"""
    timestamp: str
    event_type: str
    source: str  # "version_event" / "session_event" / "patch"
    payload: dict[str, Any] = field(default_factory=dict)


@dataclass
class ShotTrace:
    """Shot 完整链路。"""
    shot_id: str
    prompt_snapshot: dict[str, Any] | None = None
    draft: dict[str, Any] | None = None
    review: dict[str, Any] | None = None
    events: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class StaleChain:
    """Stale 传播链。"""
    stale_prompts: list[dict[str, Any]] = field(default_factory=list)
    stale_drafts: list[dict[str, Any]] = field(default_factory=list)
    stale_reviews: list[dict[str, Any]] = field(default_factory=list)
    stale_checks: list[dict[str, Any]] = field(default_factory=list)


class DebugView:
    """专家模式审计视图：聚合 session / contract / shot / stale 数据。"""

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    # ------------------------------------------------------------------
    # 1. Session 审计聚合
    # ------------------------------------------------------------------

    def show_session_audit(self, session_id: int) -> SessionAudit:
        """聚合 session 关联的 events、patches、versions。"""
        audit = SessionAudit(session_id=session_id)

        # 事件
        rows = self.conn.execute(
            """
            SELECT event_id, event_type, payload_json, created_at
            FROM writing_decision_session_events
            WHERE decision_session_id = ?
            ORDER BY created_at
            """,
            (session_id,),
        ).fetchall()
        for row in rows:
            audit.events.append({
                "event_id": int(row[0]),
                "event_type": str(row[1]),
                "payload": json.loads(str(row[2])) if row[2] else {},
                "created_at": str(row[3]),
            })

        # 关联的 contract patches（通过 decision_session_id）
        rows = self.conn.execute(
            """
            SELECT contract_patch_id, source_clause_ids_json, created_at
            FROM writing_contract_patches
            WHERE decision_session_id = ?
            ORDER BY created_at
            """,
            (session_id,),
        ).fetchall()
        for row in rows:
            audit.patches.append({
                "contract_patch_id": int(row[0]),
                "source_clause_ids": json.loads(str(row[1])) if row[1] else [],
                "created_at": str(row[2]),
            })

        # 关联的 contract versions（通过 patches → version）
        if audit.patches:
            patch_ids = [p["contract_patch_id"] for p in audit.patches]
            placeholders = ",".join("?" for _ in patch_ids)
            rows = self.conn.execute(
                f"""
                SELECT cv.contract_version_id, cv.version_number,
                       cv.scope_type, cv.scope_id, cv.created_at
                FROM writing_contract_versions cv
                WHERE cv.contract_version_id IN (
                    SELECT DISTINCT contract_version_id
                    FROM writing_contract_patches
                    WHERE contract_patch_id IN ({placeholders})
                )
                ORDER BY cv.created_at
                """,
                patch_ids,
            ).fetchall()
            for row in rows:
                audit.contract_versions.append({
                    "contract_version_id": int(row[0]),
                    "version_number": int(row[1]),
                    "scope_type": str(row[2]),
                    "scope_id": str(row[3]) if row[3] else None,
                    "created_at": str(row[4]),
                })

        return audit

    # ------------------------------------------------------------------
    # 2. 契约版本时间线
    # ------------------------------------------------------------------

    def show_contract_timeline(
        self,
        project_id: int,
        scope_type: str,
        scope_id: str | None = None,
    ) -> list[ContractTimelineEntry]:
        """聚合版本事件 + session 事件 + patches 为时间线。"""
        entries: list[ContractTimelineEntry] = []

        # 版本事件
        if scope_id is not None:
            rows = self.conn.execute(
                """
                SELECT event_id, event_type, payload_json, created_at
                FROM writing_contract_version_events
                WHERE project_id = ? AND scope_type = ? AND scope_id = ?
                ORDER BY created_at
                """,
                (project_id, scope_type, scope_id),
            ).fetchall()
        else:
            rows = self.conn.execute(
                """
                SELECT event_id, event_type, payload_json, created_at
                FROM writing_contract_version_events
                WHERE project_id = ? AND scope_type = ?
                ORDER BY created_at
                """,
                (project_id, scope_type),
            ).fetchall()
        for row in rows:
            entries.append(ContractTimelineEntry(
                timestamp=str(row[3]),
                event_type=str(row[1]),
                source="version_event",
                payload=json.loads(str(row[2])) if row[2] else {},
            ))

        # 相关 session 事件
        session_ids = self.conn.execute(
            """
            SELECT decision_session_id FROM writing_decision_sessions
            WHERE project_id = ? AND scope_type = ?
              AND (scope_id = ? OR (? IS NULL AND scope_id IS NULL))
            """,
            (project_id, scope_type, scope_id, scope_id),
        ).fetchall()
        for sid_row in session_ids:
            sid = int(sid_row[0])
            ev_rows = self.conn.execute(
                """
                SELECT event_id, event_type, payload_json, created_at
                FROM writing_decision_session_events
                WHERE decision_session_id = ?
                ORDER BY created_at
                """,
                (sid,),
            ).fetchall()
            for row in ev_rows:
                entries.append(ContractTimelineEntry(
                    timestamp=str(row[3]),
                    event_type=str(row[1]),
                    source="session_event",
                    payload={
                        "session_id": sid,
                        **(json.loads(str(row[2])) if row[2] else {}),
                    },
                ))

        # 排序
        entries.sort(key=lambda e: e.timestamp)
        return entries

    # ------------------------------------------------------------------
    # 3. Shot 完整链路
    # ------------------------------------------------------------------

    def show_shot_full_trace(self, shot_id: str) -> ShotTrace:
        """追踪 shot 的完整链路：prompt → draft → review → events。"""
        trace = ShotTrace(shot_id=shot_id)

        # Prompt snapshot
        row = self.conn.execute(
            """
            SELECT ps.prompt_id, ps.persona, ps.prompt_size_bytes, ps.is_stale, ps.created_at
            FROM writing_prompt_snapshots ps
            JOIN writing_shot_task_cards tc ON tc.task_card_id = ps.task_card_id
            JOIN writing_shot_contracts sc ON sc.shot_contract_id = tc.shot_contract_id
            JOIN writing_shots s ON s.shot_contract_id = sc.shot_contract_id
            WHERE s.shot_id = ?
            ORDER BY ps.created_at DESC LIMIT 1
            """,
            (shot_id,),
        ).fetchone()
        if row:
            trace.prompt_snapshot = {
                "prompt_id": int(row[0]),
                "persona": str(row[1]),
                "prompt_size_bytes": int(row[2]),
                "is_stale": int(row[3]),
                "created_at": str(row[4]),
            }

        # Draft
        row = self.conn.execute(
            """
            SELECT d.draft_id, d.writer_model, d.byte_count, d.is_stale, d.created_at
            FROM writing_drafts d
            WHERE d.shot_id = ?
            ORDER BY d.created_at DESC LIMIT 1
            """,
            (shot_id,),
        ).fetchone()
        if row:
            trace.draft = {
                "draft_id": int(row[0]),
                "writer_model": str(row[1]),
                "byte_count": int(row[2]),
                "is_stale": int(row[3]),
                "created_at": str(row[4]),
            }

        # Review（通过 chapter_id 关联）
        chapter_row = self.conn.execute(
            "SELECT chapter_id FROM writing_shots WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()
        if chapter_row:
            chapter_id = int(chapter_row[0])
            project_row = self.conn.execute(
                "SELECT project_id FROM writing_shots WHERE shot_id = ?",
                (shot_id,),
            ).fetchone()
            if project_row:
                project_id = int(project_row[0])
                row = self.conn.execute(
                    """
                    SELECT review_id, status, blocking_issues, reviewed_at
                    FROM writing_chapter_reviews
                    WHERE project_id = ? AND chapter_id = ?
                    ORDER BY reviewed_at DESC LIMIT 1
                    """,
                    (project_id, chapter_id),
                ).fetchone()
                if row:
                    trace.review = {
                        "review_id": int(row[0]),
                        "status": str(row[1]),
                        "blocking_issues": json.loads(str(row[2])) if row[2] else [],
                        "reviewed_at": str(row[3]),
                    }

        # Runtime events for this shot
        rows = self.conn.execute(
            """
            SELECT event_id, event_type, event_payload, created_at
            FROM writing_runtime_events
            WHERE shot_id = ?
            ORDER BY created_at
            """,
            (shot_id,),
        ).fetchall()
        for row in rows:
            trace.events.append({
                "event_id": int(row[0]),
                "event_type": str(row[1]),
                "payload": json.loads(str(row[2])) if row[2] else {},
                "created_at": str(row[3]),
            })

        return trace

    # ------------------------------------------------------------------
    # 4. Stale 传播链
    # ------------------------------------------------------------------

    def show_stale_chain(self, project_id: int) -> StaleChain:
        """查询所有 stale 标记的传播链。"""
        chain = StaleChain()

        # Stale prompts
        rows = self.conn.execute(
            """
            SELECT ps.prompt_id, ps.persona, ps.is_stale, ps.created_at
            FROM writing_prompt_snapshots ps
            JOIN writing_shot_task_cards tc ON tc.task_card_id = ps.task_card_id
            JOIN writing_shot_contracts sc ON sc.shot_contract_id = tc.shot_contract_id
            WHERE sc.project_id = ? AND ps.is_stale = 1
            ORDER BY ps.created_at
            """,
            (project_id,),
        ).fetchall()
        for row in rows:
            chain.stale_prompts.append({
                "prompt_id": int(row[0]),
                "persona": str(row[1]),
                "is_stale": int(row[2]),
                "created_at": str(row[3]),
            })

        # Stale drafts
        rows = self.conn.execute(
            """
            SELECT d.draft_id, d.writer_model, d.is_stale, d.created_at
            FROM writing_drafts d
            JOIN writing_shots s ON s.shot_id = d.shot_id
            WHERE s.project_id = ? AND d.is_stale = 1
            ORDER BY d.created_at
            """,
            (project_id,),
        ).fetchall()
        for row in rows:
            chain.stale_drafts.append({
                "draft_id": int(row[0]),
                "writer_model": str(row[1]),
                "is_stale": int(row[2]),
                "created_at": str(row[3]),
            })

        # Stale reviews
        rows = self.conn.execute(
            """
            SELECT review_id, chapter_id, status, is_stale, reviewed_at
            FROM writing_chapter_reviews
            WHERE project_id = ? AND is_stale = 1
            ORDER BY reviewed_at
            """,
            (project_id,),
        ).fetchall()
        for row in rows:
            chain.stale_reviews.append({
                "review_id": int(row[0]),
                "chapter_id": int(row[1]),
                "status": str(row[2]),
                "is_stale": int(row[3]),
                "reviewed_at": str(row[4]),
            })

        # Stale book checks
        rows = self.conn.execute(
            """
            SELECT check_run_id, check_sequence, is_stale, created_at
            FROM writing_book_check_results
            WHERE project_id = ? AND is_stale = 1
            ORDER BY created_at
            """,
            (project_id,),
        ).fetchall()
        for row in rows:
            chain.stale_checks.append({
                "check_run_id": int(row[0]),
                "check_sequence": int(row[1]),
                "is_stale": int(row[2]),
                "created_at": str(row[3]),
            })

        return chain
