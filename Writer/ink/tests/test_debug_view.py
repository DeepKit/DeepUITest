"""DebugView 专家模式审计测试。"""
from __future__ import annotations

import json
import sqlite3

import pytest

from factories import NOW, insert_minimal_draft, make_schema_db
from ink.debug_view import DebugView, SessionAudit, ShotTrace, StaleChain
from ink.decision_sessions import DecisionSessionStore
from ink.event_log import EventLog
from ink.stale_propagation import StalePropagationManager


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


class TestSessionAudit:
    """show_session_audit 测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    def test_empty_session(self, conn: sqlite3.Connection) -> None:
        """空 session 返回空聚合。"""
        dv = DebugView(conn)
        audit = dv.show_session_audit(999)
        assert audit.session_id == 999
        assert audit.events == []
        assert audit.patches == []
        assert audit.contract_versions == []

    def test_session_with_events(self, conn: sqlite3.Connection) -> None:
        """有事件的 session 返回事件列表。"""
        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封基线",
        )
        store.record_ai_parse(
            session_id,
            parsed_patch={"op": "add", "path": "logline", "value": "test"},
            readback_text="测试",
            source_hashes=[],
        )

        dv = DebugView(conn)
        audit = dv.show_session_audit(session_id)
        assert audit.session_id == session_id
        assert len(audit.events) >= 2  # created + ai_parsed
        event_types = [e["event_type"] for e in audit.events]
        assert "created" in event_types
        assert "ai_parsed" in event_types


class TestContractTimeline:
    """show_contract_timeline 测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    def test_empty_timeline(self, conn: sqlite3.Connection) -> None:
        dv = DebugView(conn)
        entries = dv.show_contract_timeline(1, "book")
        assert entries == []

    def test_timeline_with_version_event(self, conn: sqlite3.Connection) -> None:
        log = EventLog(conn)
        log.log_version_event(
            project_id=1,
            event_type="created",
            scope_type="book",
            payload={"version": 1},
        )
        dv = DebugView(conn)
        entries = dv.show_contract_timeline(1, "book")
        assert len(entries) >= 1
        assert entries[0].event_type == "created"
        assert entries[0].source == "version_event"


class TestShotTrace:
    """show_shot_full_trace 测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        # insert_minimal_draft 已创建 project_id=1
        return c

    def test_trace_with_draft(self, conn: sqlite3.Connection) -> None:
        ids = insert_minimal_draft(conn)
        dv = DebugView(conn)
        trace = dv.show_shot_full_trace(ids["shot_id"])
        assert trace.shot_id == ids["shot_id"]
        assert trace.prompt_snapshot is not None
        assert trace.draft is not None
        assert trace.draft["writer_model"] == "writer-a"

    def test_trace_unknown_shot(self, conn: sqlite3.Connection) -> None:
        dv = DebugView(conn)
        trace = dv.show_shot_full_trace("nonexistent-shot")
        assert trace.shot_id == "nonexistent-shot"
        assert trace.prompt_snapshot is None
        assert trace.draft is None


class TestStaleChain:
    """show_stale_chain 测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        # insert_minimal_draft 已创建 project_id=1
        ids = insert_minimal_draft(c)
        # 添加 review 和 book check
        c.execute(
            """
            INSERT INTO writing_chapter_reviews
                (review_id, project_id, chapter_id, run_id, status,
                 blocking_issues, reviewed_at)
            VALUES (100, 1, 1, 20, 'pending', '[]', ?)
            """,
            (NOW,),
        )
        c.execute(
            """
            INSERT INTO writing_book_check_results
                (check_run_id, project_id, check_sequence,
                 chapter_range_start, chapter_range_end,
                 issues, blocking_issue_count, created_at)
            VALUES (200, 1, 1, 1, 1, '[]', 0, ?)
            """,
            (NOW,),
        )
        return c

    def test_no_stale(self, conn: sqlite3.Connection) -> None:
        dv = DebugView(conn)
        chain = dv.show_stale_chain(1)
        assert chain.stale_prompts == []
        assert chain.stale_drafts == []
        assert chain.stale_reviews == []
        assert chain.stale_checks == []

    def test_stale_after_book_change(self, conn: sqlite3.Connection) -> None:
        mgr = StalePropagationManager(conn)
        mgr.mark_stale_after_contract_change(
            project_id=1,
            scope_type="book",
            scope_id=None,
        )
        dv = DebugView(conn)
        chain = dv.show_stale_chain(1)
        assert len(chain.stale_prompts) >= 1
        assert len(chain.stale_drafts) >= 1
        assert len(chain.stale_reviews) >= 1
        assert len(chain.stale_checks) >= 1
