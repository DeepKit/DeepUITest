"""WorkflowConductor 测试。"""
from __future__ import annotations

import sqlite3

import pytest

from factories import NOW, make_schema_db
from ink.workflow_conductor import WorkflowConductor


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


class TestWorkflowConductor:
    """WorkflowConductor 状态机推进测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    @pytest.fixture
    def conductor(self, conn: sqlite3.Connection) -> WorkflowConductor:
        return WorkflowConductor(conn)

    def test_step_collecting_to_awaiting_confirm(self, conn: sqlite3.Connection, conductor: WorkflowConductor) -> None:
        """collecting + human_text → awaiting_confirm。"""
        session_id = conductor._host.start_session(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封全书基线",
        )

        step = conductor.step(
            project_id=1,
            session_id=session_id,
            human_text="封全书基线",
        )

        assert step.next_action == "awaiting_confirm"
        assert step.session_id == session_id
        assert "parsed_patch" in step.payload

        # 验证 session 状态
        row = conn.execute(
            "SELECT status FROM writing_decision_sessions WHERE decision_session_id = ?",
            (session_id,),
        ).fetchone()
        assert str(row[0]) == "awaiting_confirm"

    def test_step_awaiting_confirm_to_confirmed(self, conn: sqlite3.Connection, conductor: WorkflowConductor) -> None:
        """awaiting_confirm + selected_option=1 → confirmed。"""
        session_id = conductor._host.start_session(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封全书基线",
        )
        conductor.step(project_id=1, session_id=session_id, human_text="封全书基线")

        # 需要传 contract_payload，因为 conductor 没有 patch_engine
        step = conductor.step(project_id=1, session_id=session_id, selected_option=1)

        assert step.next_action == "confirmed"
        assert "contract_version_id" in step.payload
        assert "after_hash" in step.payload

        # 验证 session 状态
        row = conn.execute(
            "SELECT status FROM writing_decision_sessions WHERE decision_session_id = ?",
            (session_id,),
        ).fetchone()
        assert str(row[0]) == "confirmed"

    def test_step_awaiting_confirm_to_rejected(self, conn: sqlite3.Connection, conductor: WorkflowConductor) -> None:
        """awaiting_confirm + selected_option=2 → rejected。"""
        session_id = conductor._host.start_session(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封全书基线",
        )
        conductor.step(project_id=1, session_id=session_id, human_text="封全书基线")

        step = conductor.step(project_id=1, session_id=session_id, selected_option=2)

        assert step.next_action == "rejected"

    def test_step_confirmed_to_done(self, conn: sqlite3.Connection, conductor: WorkflowConductor) -> None:
        """confirmed → done。"""
        session_id = conductor._host.start_session(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封全书基线",
        )
        conductor.step(project_id=1, session_id=session_id, human_text="封全书基线")
        conductor.step(project_id=1, session_id=session_id, selected_option=1)

        step = conductor.step(project_id=1, session_id=session_id)

        assert step.next_action == "done"

    def test_step_wait_for_input(self, conn: sqlite3.Connection, conductor: WorkflowConductor) -> None:
        """collecting 但无 human_text → wait_for_input。"""
        session_id = conductor._host.start_session(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="",
        )

        step = conductor.step(project_id=1, session_id=session_id)

        assert step.next_action == "wait_for_input"

    def test_step_wait_for_selection(self, conn: sqlite3.Connection, conductor: WorkflowConductor) -> None:
        """awaiting_confirm 但无 selected_option → wait_for_selection。"""
        session_id = conductor._host.start_session(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封全书基线",
        )
        conductor.step(project_id=1, session_id=session_id, human_text="封全书基线")

        step = conductor.step(project_id=1, session_id=session_id)

        assert step.next_action == "wait_for_selection"

    def test_audit_event_recorded(self, conn: sqlite3.Connection, conductor: WorkflowConductor) -> None:
        """确认契约后记录审计事件。"""
        session_id = conductor._host.start_session(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封全书基线",
        )
        conductor.step(project_id=1, session_id=session_id, human_text="封全书基线")
        conductor.step(project_id=1, session_id=session_id, selected_option=1)

        # 验证审计事件（可能有多个事件，检查是否存在 CONTRACT_CONFIRMED）
        rows = conn.execute(
            "SELECT event_type FROM writing_runtime_events WHERE project_id = 1 ORDER BY created_at"
        ).fetchall()
        event_types = [str(row[0]) for row in rows]
        assert "CONTRACT_CONFIRMED" in event_types

    def test_session_not_found_raises(self, conn: sqlite3.Connection, conductor: WorkflowConductor) -> None:
        """不存在的 session_id → DataIntegrityError。"""
        with pytest.raises(Exception, match="session not found"):
            conductor.step(project_id=1, session_id=99999)


class TestDecisionSessionHost:
    """DecisionSessionHost 测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    def test_start_session(self, conn: sqlite3.Connection) -> None:
        """启动新 session。"""
        from ink.workflow_conductor import DecisionSessionHost
        host = DecisionSessionHost(conn)

        session_id = host.start_session(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="测试",
        )

        assert session_id > 0
        row = conn.execute(
            "SELECT status FROM writing_decision_sessions WHERE decision_session_id = ?",
            (session_id,),
        ).fetchone()
        assert str(row[0]) == "collecting"

    def test_parse_mock_mode(self, conn: sqlite3.Connection) -> None:
        """Mock 模式解析。"""
        from ink.workflow_conductor import DecisionSessionHost
        host = DecisionSessionHost(conn)

        session_id = host.start_session(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="测试",
        )

        result = host.parse(session_id, human_text="测试输入", scope_type="book")

        assert result.decision_session_id == session_id
        assert isinstance(result.parsed_patch, list)
        assert len(result.parsed_patch) > 0
        assert result.readback_text.startswith("我理解为：")


class TestContractSteward:
    """ContractSteward 测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    def test_apply_with_explicit_payload(self, conn: sqlite3.Connection) -> None:
        """显式传 contract_payload。"""
        from ink.decision_sessions import DecisionSessionStore
        from ink.workflow_conductor import ContractSteward

        ds_store = DecisionSessionStore(conn)
        steward = ContractSteward(conn)

        session_id = ds_store.start(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
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

        result = steward.apply(
            session_id,
            actor="author",
            reason="测试",
            contract_scope_type="book",
            contract_scope_id=None,
            contract_payload={"identity": {"title": "Demo"}},
        )

        assert result.contract_version_id > 0
        assert result.after_hash is not None


class TestGatekeeper:
    """Gatekeeper 测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    def test_validate_valid_patch(self, conn: sqlite3.Connection) -> None:
        """合法 patch 通过校验。"""
        from ink.workflow_conductor import Gatekeeper
        gatekeeper = Gatekeeper(conn)

        result = gatekeeper.validate(
            project_id=1,
            scope_type="book",
            scope_id=None,
            patch=[{"op": "add", "path": "test", "value": "v"}],
        )

        assert result.is_valid is True
        assert len(result.errors) == 0
