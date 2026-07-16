"""多作用域修订与 stale downstream 记录。

局部修订必须带作用域，不能偷改上层契约。
"""
from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from typing import Any, Literal

from ink.decision_sessions import DecisionSessionStore
from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


@dataclass(frozen=True)
class ScopedDecisionPatch:
    """局部修订必须带作用域，不能偷改上层契约。"""
    scope_type: Literal["book", "volume", "part", "chapter", "shot"]
    scope_id: str | None
    base_contract_version: str
    change_type: Literal["refine", "override", "split", "defer", "reject"]
    affected_scopes_json: str
    stale_downstream_json: str
    patch_json: str


class ScopedDecisionSessionStore:
    """扩展 DecisionSessionStore，支持多作用域修订和 stale downstream 记录。"""

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn
        self._ds_store = DecisionSessionStore(conn)

    def start_scoped(
        self,
        *,
        project_id: int,
        scope_type: str,
        scope_id: str | None,
        target_type: str,
        target_id: str | None,
        human_text: str,
        parent_decision_session_id: int | None = None,
        affected_scopes: list[dict[str, Any]] | None = None,
        stale_downstream: list[dict[str, Any]] | None = None,
    ) -> int:
        """启动一个带作用域的修订会话。"""
        session_id = self._ds_store.start(
            project_id=project_id,
            scope_type=scope_type,
            scope_id=scope_id,
            target_type=target_type,
            target_id=target_id,
            human_text=human_text,
            parent_decision_session_id=parent_decision_session_id,
        )

        # 记录 affected_scopes 和 stale_downstream（如果有）
        if affected_scopes or stale_downstream:
            self.record_affected_scopes(
                session_id,
                affected_scopes=affected_scopes or [],
                stale_downstream=stale_downstream or [],
            )

        return session_id

    def record_affected_scopes(
        self,
        decision_session_id: int,
        *,
        affected_scopes: list[dict[str, Any]],
        stale_downstream: list[dict[str, Any]],
    ) -> None:
        """记录本 patch 影响的作用域和下游 stale 列表。

        写入 writing_contract_patches.affected_scopes_json + stale_downstream_json。
        注意：这需要在 confirm_and_apply 之后调用，因为 patch_id 那时才存在。
        """
        # 查询最新的 contract_patch_id
        row = self.conn.execute(
            """
            SELECT contract_patch_id FROM writing_contract_patches
            WHERE decision_session_id = ?
            ORDER BY created_at DESC LIMIT 1
            """,
            (decision_session_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(
                f"no contract patch found for session {decision_session_id}"
            )
        patch_id = int(row[0])

        # 更新 affected_scopes_json 和 stale_downstream_json
        now = now_utc_iso()
        self.conn.execute(
            """
            UPDATE writing_contract_patches
            SET affected_scopes_json = ?,
                stale_downstream_json = ?
            WHERE contract_patch_id = ?
            """,
            (
                json.dumps(affected_scopes, ensure_ascii=False, sort_keys=True),
                json.dumps(stale_downstream, ensure_ascii=False, sort_keys=True),
                patch_id,
            ),
        )

    def create_scoped_decision_patch(
        self,
        *,
        scope_type: str,
        scope_id: str | None,
        base_contract_version: str,
        change_type: str,
        affected_scopes: list[dict[str, Any]],
        stale_downstream: list[dict[str, Any]],
        patch: list[dict[str, Any]],
    ) -> ScopedDecisionPatch:
        """创建一个 ScopedDecisionPatch dataclass。"""
        return ScopedDecisionPatch(
            scope_type=scope_type,  # type: ignore
            scope_id=scope_id,
            base_contract_version=base_contract_version,
            change_type=change_type,  # type: ignore
            affected_scopes_json=json.dumps(affected_scopes, ensure_ascii=False, sort_keys=True),
            stale_downstream_json=json.dumps(stale_downstream, ensure_ascii=False, sort_keys=True),
            patch_json=json.dumps(patch, ensure_ascii=False, sort_keys=True),
        )
