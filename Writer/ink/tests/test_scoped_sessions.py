"""ScopedDecisionSession 测试。"""
from __future__ import annotations

import sqlite3

import pytest

from factories import NOW, make_schema_db
from ink.scoped_sessions import ScopedDecisionPatch, ScopedDecisionSessionStore


def _insert_project(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'demo', 'Demo', '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
        """,
        (NOW,),
    )


class TestScopedDecisionSessionStore:
    """ScopedDecisionSessionStore 测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    @pytest.fixture
    def store(self, conn: sqlite3.Connection) -> ScopedDecisionSessionStore:
        return ScopedDecisionSessionStore(conn)

    def test_start_scoped_basic(self, conn: sqlite3.Connection, store: ScopedDecisionSessionStore) -> None:
        """启动带作用域的修订会话。"""
        session_id = store.start_scoped(
            project_id=1,
            scope_type="chapter",
            scope_id="ch-1",
            target_type="ChapterContract",
            target_id="ch-1",
            human_text="调整第一章钩子",
        )

        assert session_id > 0
        row = conn.execute(
            "SELECT scope_type, scope_id, status FROM writing_decision_sessions WHERE decision_session_id = ?",
            (session_id,),
        ).fetchone()
        assert str(row[0]) == "chapter"
        assert str(row[1]) == "ch-1"
        assert str(row[2]) == "collecting"

    def test_start_scoped_with_parent(self, conn: sqlite3.Connection, store: ScopedDecisionSessionStore) -> None:
        """启动带父 session 的修订会话。"""
        parent_id = store.start_scoped(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封全书基线",
        )

        child_id = store.start_scoped(
            project_id=1,
            scope_type="chapter",
            scope_id="ch-1",
            target_type="ChapterContract",
            target_id="ch-1",
            human_text="调整第一章",
            parent_decision_session_id=parent_id,
        )

        row = conn.execute(
            "SELECT parent_decision_session_id FROM writing_decision_sessions WHERE decision_session_id = ?",
            (child_id,),
        ).fetchone()
        assert int(row[0]) == parent_id

    def test_record_affected_scopes(self, conn: sqlite3.Connection, store: ScopedDecisionSessionStore) -> None:
        """记录 affected_scopes 和 stale_downstream。"""
        from ink.decision_sessions import DecisionSessionStore

        ds_store = DecisionSessionStore(conn)
        session_id = ds_store.start(
            project_id=1,
            scope_type="chapter",
            scope_id="ch-1",
            target_type="ChapterContract",
            target_id="ch-1",
            human_text="测试",
        )
        ds_store.record_ai_parse(
            session_id,
            parsed_patch={"op": "add", "path": "test", "value": "v"},
            readback_text="测试",
            source_hashes=[],
        )
        ds_store.create_option_set(session_id, options=[{"label": "确认"}], recommended_option=1)
        ds_store.select_option(session_id, 1)
        ds_store.confirm_and_apply(
            session_id,
            actor="author",
            reason="测试",
            contract_scope_type="chapter",
            contract_scope_id="ch-1",
            contract_payload={"chapter_id": {"title": "Ch1"}},
        )

        # 记录 affected_scopes
        affected_scopes = [
            {"scope_type": "shot", "scope_id": "shot-1"},
            {"scope_type": "shot", "scope_id": "shot-2"},
        ]
        stale_downstream = [
            {"table": "writing_prompt_snapshots", "shot_id": "shot-1@20"},
        ]
        store.record_affected_scopes(
            session_id,
            affected_scopes=affected_scopes,
            stale_downstream=stale_downstream,
        )

        # 验证写入
        row = conn.execute(
            "SELECT affected_scopes_json, stale_downstream_json FROM writing_contract_patches WHERE decision_session_id = ?",
            (session_id,),
        ).fetchone()
        assert row is not None
        import json
        scopes = json.loads(str(row[0]))
        assert len(scopes) == 2
        assert scopes[0]["scope_type"] == "shot"

    def test_record_affected_scopes_no_patch_raises(self, conn: sqlite3.Connection, store: ScopedDecisionSessionStore) -> None:
        """没有 patch 时记录 affected_scopes 抛错。"""
        from ink.decision_sessions import DecisionSessionStore

        ds_store = DecisionSessionStore(conn)
        session_id = ds_store.start(
            project_id=1,
            scope_type="chapter",
            scope_id="ch-1",
            target_type="ChapterContract",
            target_id="ch-1",
            human_text="测试",
        )

        with pytest.raises(Exception, match="no contract patch found"):
            store.record_affected_scopes(
                session_id,
                affected_scopes=[],
                stale_downstream=[],
            )

    def test_create_scoped_decision_patch(self, store: ScopedDecisionSessionStore) -> None:
        """创建 ScopedDecisionPatch dataclass。"""
        patch = store.create_scoped_decision_patch(
            scope_type="chapter",
            scope_id="ch-1",
            base_contract_version="v1",
            change_type="refine",
            affected_scopes=[{"scope_type": "shot", "scope_id": "shot-1"}],
            stale_downstream=[{"table": "writing_prompt_snapshots"}],
            patch=[{"op": "replace", "path": "scene_hook", "value": "new"}],
        )

        assert patch.scope_type == "chapter"
        assert patch.scope_id == "ch-1"
        assert patch.change_type == "refine"
        assert "shot" in patch.affected_scopes_json
        assert "writing_prompt_snapshots" in patch.stale_downstream_json


class TestScopedDecisionPatch:
    """ScopedDecisionPatch dataclass 测试。"""

    def test_create_patch(self) -> None:
        """创建 patch。"""
        patch = ScopedDecisionPatch(
            scope_type="chapter",
            scope_id="ch-1",
            base_contract_version="v1",
            change_type="refine",
            affected_scopes_json='[{"scope_type": "shot"}]',
            stale_downstream_json='[]',
            patch_json='[{"op": "replace", "path": "x", "value": "y"}]',
        )

        assert patch.scope_type == "chapter"
        assert patch.scope_id == "ch-1"
