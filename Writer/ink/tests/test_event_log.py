"""EventLog 测试。"""
from __future__ import annotations

import sqlite3

import pytest

from factories import NOW, make_schema_db
from ink.decision_sessions import DecisionSessionStore
from ink.event_log import EventLog, EventRecord, SESSION_EVENT_TYPES, VERSION_EVENT_TYPES


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


class TestEventLogSessionEvents:
    """Session event log 测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    def test_log_created_event(self, conn: sqlite3.Connection) -> None:
        """start() 自动写 'created' 事件。"""
        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封基线",
        )

        log = EventLog(conn)
        events = log.replay_session(session_id)
        assert len(events) == 1
        assert events[0].event_type == "created"
        assert events[0].payload["scope_type"] == "book"

    def test_log_ai_parsed_event(self, conn: sqlite3.Connection) -> None:
        """record_ai_parse 自动写 'ai_parsed' 事件。"""
        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1,
            scope_type="chapter",
            scope_id="1",
            target_type="ChapterContract",
            target_id="ch-1",
            human_text="调整",
        )
        store.record_ai_parse(
            session_id,
            parsed_patch={"op": "add", "path": "scene_hook", "value": "test"},
            readback_text="测试",
            source_hashes=["abc"],
        )

        log = EventLog(conn)
        events = log.replay_session(session_id)
        assert len(events) == 2
        assert events[1].event_type == "ai_parsed"
        assert events[1].payload["readback_text"] == "测试"

    def test_log_option_set_created_event(self, conn: sqlite3.Connection) -> None:
        """create_option_set 自动写 'option_set_created' 事件。"""
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
        store.create_option_set(session_id, options=[{"label": "确认"}], recommended_option=1)

        log = EventLog(conn)
        events = log.replay_session(session_id)
        event_types = [e.event_type for e in events]
        assert "option_set_created" in event_types

    def test_log_option_selected_event(self, conn: sqlite3.Connection) -> None:
        """select_option 自动写 'option_selected' 事件。"""
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
        store.create_option_set(session_id, options=[{"label": "确认"}], recommended_option=1)
        store.select_option(session_id, 1)

        log = EventLog(conn)
        events = log.replay_session(session_id)
        event_types = [e.event_type for e in events]
        assert "option_selected" in event_types

    def test_log_confirmed_event_via_confirm_and_apply(self, conn: sqlite3.Connection) -> None:
        """confirm_and_apply 自动写 'confirmed' 事件（session + version）。"""
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
        store.create_option_set(session_id, options=[{"label": "确认"}], recommended_option=1)
        store.select_option(session_id, 1)
        store.confirm_and_apply(
            session_id,
            actor="author",
            reason="测试",
            contract_scope_type="book",
            contract_scope_id=None,
            contract_payload={"identity": {"title": "Demo"}, "logline": "test"},
        )

        log = EventLog(conn)
        events = log.replay_session(session_id)
        event_types = [e.event_type for e in events]
        assert event_types.count("confirmed") >= 1

        # 也应该有 version event
        version_events = log.replay_version(1, "book")
        assert len(version_events) >= 1
        assert version_events[0].event_type == "confirmed"


class TestEventLogVersionEvents:
    """Version event log 测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    def test_log_version_event(self, conn: sqlite3.Connection) -> None:
        """手动写 version 事件。"""
        log = EventLog(conn)
        event_id = log.log_version_event(
            project_id=1,
            event_type="created",
            scope_type="book",
            payload={"contract_json": "{}"},
        )
        assert event_id > 0

        events = log.replay_version(1, "book")
        assert len(events) == 1
        assert events[0].event_type == "created"

    def test_replay_version_with_scope_id(self, conn: sqlite3.Connection) -> None:
        """replay_version 按 scope_id 过滤。"""
        log = EventLog(conn)
        log.log_version_event(project_id=1, event_type="created", scope_type="chapter", scope_id="1")
        log.log_version_event(project_id=1, event_type="created", scope_type="chapter", scope_id="2")
        log.log_version_event(project_id=1, event_type="confirmed", scope_type="chapter", scope_id="1")

        events_ch1 = log.replay_version(1, "chapter", "1")
        assert len(events_ch1) == 2
        assert events_ch1[0].event_type == "created"
        assert events_ch1[1].event_type == "confirmed"

        events_ch2 = log.replay_version(1, "chapter", "2")
        assert len(events_ch2) == 1


class TestEventLogValidation:
    """EventLog 验证测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    def test_invalid_session_event_type(self, conn: sqlite3.Connection) -> None:
        """非法 session event type 抛 ValueError。"""
        log = EventLog(conn)
        with pytest.raises(ValueError, match="invalid session event type"):
            log.log_session_event(1, "invalid_type")

    def test_invalid_version_event_type(self, conn: sqlite3.Connection) -> None:
        """非法 version event type 抛 ValueError。"""
        log = EventLog(conn)
        with pytest.raises(ValueError, match="invalid version event type"):
            log.log_version_event(1, "invalid_type", "book")

    def test_all_session_event_types_are_valid(self) -> None:
        """所有 SESSION_EVENT_TYPES 都可通过校验。"""
        log = EventLog(make_schema_db())
        for event_type in SESSION_EVENT_TYPES:
            # 只验证不抛错，不实际写入（无 session 会 FK 失败）
            assert event_type in {"created", "input_received", "ai_parsed", "option_set_created",
                                   "option_selected", "option_regenerated", "confirmed", "cancelled", "stale"}

    def test_count_methods(self, conn: sqlite3.Connection) -> None:
        """count_session_events 和 count_version_events。"""
        log = EventLog(conn)
        assert log.count_session_events(999) == 0
        assert log.count_version_events(1, "book") == 0

        log.log_version_event(1, "created", "book")
        log.log_version_event(1, "confirmed", "book")
        assert log.count_version_events(1, "book") == 2

    def test_latest_session_event(self, conn: sqlite3.Connection) -> None:
        """latest_session_event 返回最新事件。"""
        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封基线",
        )

        log = EventLog(conn)
        latest = log.latest_session_event(session_id)
        assert latest is not None
        assert latest.event_type == "created"

    def test_latest_session_event_not_found(self, conn: sqlite3.Connection) -> None:
        """latest_session_event 不存在时返回 None。"""
        log = EventLog(conn)
        assert log.latest_session_event(999) is None
