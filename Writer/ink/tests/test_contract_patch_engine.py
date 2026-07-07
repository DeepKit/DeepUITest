"""ContractPatchEngine 测试。

覆盖形态校验、6 步流水线（schema / intra‑conflict / base / apply /
必填字段 / readback）、以及 decision_sessions 集成点。
"""
from __future__ import annotations

import json
import sqlite3

import pytest

from factories import NOW, make_schema_db
from ink.contract.fields import validate_field_path
from ink.contract.patch_engine import (
    ContractPatchEngine,
    LLMReadbackVerifier,
    PatchApplicationResult,
    ReadbackVerifier,
)
from ink.decision_sessions import DecisionSessionStore
from ink.errors import ContractPatchError, DataIntegrityError
from ink.source_workflow import SourceWorkflowStore


# ═══════════════════════════════════════════════════════════
#  Test doubles
# ═══════════════════════════════════════════════════════════

class _ScriptedReadbackVerifier:
    """mock verifier，返回固定 bool。"""
    def __init__(self, result: bool = True) -> None:
        self._result = result
        self.last_call: dict | None = None

    def verify(self, *, patch: list[dict], readback_text: str, scope_type: str) -> bool:
        self.last_call = {"patch": patch, "readback_text": readback_text, "scope_type": scope_type}
        return self._result


# ═══════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════

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


def _insert_base_contract(
    conn: sqlite3.Connection,
    *,
    project_id: int = 1,
    scope_type: str = "part",
    scope_id: str | None = "part-1",
    payload: dict | None = None,
) -> int:
    """插入一条 confirmed 契约版本作为 base，返回 contract_version_id。"""
    if payload is None:
        payload = {"part_id": {"name": "序章"}, "local_goal": "建立世界观"}
    cursor = conn.execute(
        """
        INSERT INTO writing_contract_versions
            (project_id, scope_type, scope_id, version, status, contract_json,
             contract_hash, source_clause_ids_json, created_at)
        VALUES (?, ?, ?, ?, 'confirmed', ?, ?, ?, ?)
        """,
        (
            project_id,
            scope_type,
            scope_id,
            1,
            json.dumps(payload, ensure_ascii=False, sort_keys=True),
            "fake-hash",
            "[]",
            NOW,
        ),
    )
    return int(cursor.lastrowid)


class TestValidatePatchShape:
    """静态方法 validate_patch_shape — 形态校验。"""

    def test_accepts_valid_patch(self) -> None:
        patch = [
            {"op": "replace", "path": "local_goal", "value": "新目标"},
            {"op": "add", "path": "risk_notes", "value": ["风险"]},
        ]
        result = ContractPatchEngine.validate_patch_shape(patch)
        assert result is patch

    def test_rejects_non_list(self) -> None:
        with pytest.raises(ContractPatchError, match="patch must be a list"):
            ContractPatchEngine.validate_patch_shape({"op": "replace", "path": "x"})  # type: ignore

    def test_rejects_empty_list(self) -> None:
        with pytest.raises(ContractPatchError, match="patch must not be empty"):
            ContractPatchEngine.validate_patch_shape([])

    def test_rejects_non_dict_op(self) -> None:
        with pytest.raises(ContractPatchError, match="op #0 must be a dict"):
            ContractPatchEngine.validate_patch_shape(["string"])

    def test_rejects_unsupported_op(self) -> None:
        with pytest.raises(ContractPatchError, match="unsupported or missing op"):
            ContractPatchEngine.validate_patch_shape([{"op": "copy", "path": "x", "from": "y"}])

    def test_rejects_missing_path(self) -> None:
        with pytest.raises(ContractPatchError, match="missing or invalid path"):
            ContractPatchEngine.validate_patch_shape([{"op": "remove"}])

    def test_rejects_move_without_from(self) -> None:
        with pytest.raises(ContractPatchError, match="missing or invalid 'from'"):
            ContractPatchEngine.validate_patch_shape([
                {"op": "move", "path": "b"},
            ])

    def test_rejects_empty_path(self) -> None:
        with pytest.raises(ContractPatchError, match="missing or invalid path"):
            ContractPatchEngine.validate_patch_shape([{"op": "add", "path": "", "value": 1}])


class TestValidateSchema:
    """schema 白名单校验。"""

    def test_valid_paths_pass(self) -> None:
        patch = [
            {"op": "replace", "path": "local_goal", "value": "x"},
            {"op": "add", "path": "risk_notes", "value": []},
        ]
        # 不会抛异常
        ContractPatchEngine._validate_schema(patch, "part")

    def test_invalid_paths_raise(self) -> None:
        patch = [
            {"op": "replace", "path": "nonexistent", "value": 1},
        ]
        with pytest.raises(ContractPatchError, match="whitelist"):
            ContractPatchEngine._validate_schema(patch, "part")

    def test_mixed_valid_and_invalid(self) -> None:
        patch = [
            {"op": "replace", "path": "local_goal", "value": "x"},
            {"op": "add", "path": "bad_field", "value": 1},
        ]
        with pytest.raises(ContractPatchError, match="bad_field"):
            ContractPatchEngine._validate_schema(patch, "part")

    def test_book_scope_paths(self) -> None:
        patch = [{"op": "replace", "path": "logline", "value": "new"}]
        ContractPatchEngine._validate_schema(patch, "book")

    def test_unknown_scope_raises(self) -> None:
        patch = [{"op": "replace", "path": "any", "value": 1}]
        with pytest.raises(ContractPatchError, match="whitelist"):
            ContractPatchEngine._validate_schema(patch, "invalid_scope")


class TestIntraPatchConflicts:
    def test_duplicate_path_raises(self) -> None:
        patch = [
            {"op": "replace", "path": "local_goal", "value": "a"},
            {"op": "add", "path": "local_goal", "value": "b"},
        ]
        with pytest.raises(ContractPatchError, match="same field path"):
            ContractPatchEngine._check_intra_patch_conflicts(patch)

    def test_unique_paths_pass(self) -> None:
        patch = [
            {"op": "replace", "path": "local_goal", "value": "a"},
            {"op": "add", "path": "risk_notes", "value": []},
        ]
        ContractPatchEngine._check_intra_patch_conflicts(patch)  # no raise

    def test_single_op_always_passes(self) -> None:
        ContractPatchEngine._check_intra_patch_conflicts([
            {"op": "remove", "path": "local_goal"},
        ])


class TestCheckRequiredFields:
    def test_all_required_present(self) -> None:
        payload = {"part_id": {"name": "序章"}, "local_goal": "x"}
        ContractPatchEngine._check_required_fields(payload, "part")

    def test_missing_required_raises(self) -> None:
        payload = {"local_goal": "x"}  # missing part_id + part_id.name
        with pytest.raises(ContractPatchError, match="required fields missing"):
            ContractPatchEngine._check_required_fields(payload, "part")

    def test_missing_nested_required_raises(self) -> None:
        payload = {"part_id": {}}  # part_id exists but part_id.name does not
        with pytest.raises(ContractPatchError, match="required fields missing.*part_id.name"):
            ContractPatchEngine._check_required_fields(payload, "part")


class TestApplyAndValidate:
    """需要 DB 的集成测试。"""

    DB_TEST_SCOPE = "part"
    DB_TEST_SCOPE_ID = "part-1"

    VALID_PATCH = [{"op": "replace", "path": "local_goal", "value": "新目标"}]
    VALID_READBACK = "把局部目标改为新目标"
    SOURCE_CLAUSE_IDS = [1]
    SOURCE_HASHES = ["hash-a"]

    # ── fixtures ──────────────────────────────────────────

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    @pytest.fixture
    def base_version_id(self, conn: sqlite3.Connection) -> int:
        return _insert_base_contract(conn)

    @pytest.fixture
    def engine(self, conn: sqlite3.Connection) -> ContractPatchEngine:
        verifier = _ScriptedReadbackVerifier(result=True)
        return ContractPatchEngine(conn, readback_verifier=verifier)

    # ── tests ────────────────────────────────────────────

    def test_adds_field_to_base(
        self, conn: sqlite3.Connection, base_version_id: int,
    ) -> None:
        verifier = _ScriptedReadbackVerifier(result=True)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        result = engine.apply_and_validate(
            project_id=1,
            scope_type=self.DB_TEST_SCOPE,
            scope_id=self.DB_TEST_SCOPE_ID,
            patch=[{"op": "add", "path": "risk_notes", "value": ["高风险"]}],
            readback_text=self.VALID_READBACK,
            source_clause_ids=self.SOURCE_CLAUSE_IDS,
            source_hashes=self.SOURCE_HASHES,
        )
        assert result.new_payload["risk_notes"] == ["高风险"]
        assert result.new_payload["part_id"]["name"] == "序章"  # base preserved
        assert "local_goal" in result.new_payload  # base preserved
        assert result.base_contract_version_id == base_version_id
        assert result.affected_field_paths == ["risk_notes"]

    def test_first_time_no_base(self, conn: sqlite3.Connection) -> None:
        """首次确认：无 base contract，patch 等价于全量构造。"""
        verifier = _ScriptedReadbackVerifier(result=True)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        result = engine.apply_and_validate(
            project_id=1,
            scope_type=self.DB_TEST_SCOPE,
            scope_id=self.DB_TEST_SCOPE_ID,
            patch=[
                {"op": "add", "path": "part_id.name", "value": "序章"},
                {"op": "add", "path": "local_goal", "value": "建立"},
            ],
            readback_text=self.VALID_READBACK,
            source_clause_ids=self.SOURCE_CLAUSE_IDS,
            source_hashes=self.SOURCE_HASHES,
        )
        assert result.new_payload["part_id"]["name"] == "序章"
        assert result.new_payload["local_goal"] == "建立"
        assert result.base_contract_version_id is None

    def test_readback_empty_raises(
        self, conn: sqlite3.Connection, base_version_id: int,
    ) -> None:
        verifier = _ScriptedReadbackVerifier(result=True)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        with pytest.raises(ContractPatchError, match="readback_text is empty"):
            engine.apply_and_validate(
                project_id=1,
                scope_type=self.DB_TEST_SCOPE,
                scope_id=self.DB_TEST_SCOPE_ID,
                patch=self.VALID_PATCH,
                readback_text="",
                source_clause_ids=self.SOURCE_CLAUSE_IDS,
                source_hashes=self.SOURCE_HASHES,
            )

    def test_readback_fails_raises(
        self, conn: sqlite3.Connection, base_version_id: int,
    ) -> None:
        verifier = _ScriptedReadbackVerifier(result=False)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        with pytest.raises(ContractPatchError, match="readback verification failed"):
            engine.apply_and_validate(
                project_id=1,
                scope_type=self.DB_TEST_SCOPE,
                scope_id=self.DB_TEST_SCOPE_ID,
                patch=self.VALID_PATCH,
                readback_text=self.VALID_READBACK,
                source_clause_ids=self.SOURCE_CLAUSE_IDS,
                source_hashes=self.SOURCE_HASHES,
            )

    def test_readback_passes(
        self, conn: sqlite3.Connection, base_version_id: int,
    ) -> None:
        verifier = _ScriptedReadbackVerifier(result=True)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        result = engine.apply_and_validate(
            project_id=1,
            scope_type=self.DB_TEST_SCOPE,
            scope_id=self.DB_TEST_SCOPE_ID,
            patch=self.VALID_PATCH,
            readback_text=self.VALID_READBACK,
            source_clause_ids=self.SOURCE_CLAUSE_IDS,
            source_hashes=self.SOURCE_HASHES,
        )
        assert isinstance(result, PatchApplicationResult)
        # 确认 verifier 被调用
        assert verifier.last_call is not None
        assert verifier.last_call["scope_type"] == self.DB_TEST_SCOPE

    def test_readback_skipped_when_no_verifier(
        self, conn: sqlite3.Connection, base_version_id: int,
    ) -> None:
        """不传 readback_verifier → 跳过步骤 6。"""
        engine = ContractPatchEngine(conn, readback_verifier=None)
        result = engine.apply_and_validate(
            project_id=1,
            scope_type=self.DB_TEST_SCOPE,
            scope_id=self.DB_TEST_SCOPE_ID,
            patch=self.VALID_PATCH,
            readback_text="no check needed",
            source_clause_ids=self.SOURCE_CLAUSE_IDS,
            source_hashes=self.SOURCE_HASHES,
        )
        assert "local_goal" in result.new_payload

    def test_required_field_missing_after_patch_raises(
        self, conn: sqlite3.Connection, base_version_id: int,
    ) -> None:
        """patch 移除了必填字段 part_id.name → 报错。"""
        verifier = _ScriptedReadbackVerifier(result=True)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        with pytest.raises(ContractPatchError, match="required fields missing"):
            engine.apply_and_validate(
                project_id=1,
                scope_type=self.DB_TEST_SCOPE,
                scope_id=self.DB_TEST_SCOPE_ID,
                patch=[{"op": "remove", "path": "part_id.name"}],
                readback_text=self.VALID_READBACK,
                source_clause_ids=self.SOURCE_CLAUSE_IDS,
                source_hashes=self.SOURCE_HASHES,
            )

    def test_schema_validation_rejects_invalid_path(
        self, conn: sqlite3.Connection, base_version_id: int,
    ) -> None:
        """patch path 不在 scope schema 白名单内 → 步骤 1 拒绝。"""
        verifier = _ScriptedReadbackVerifier(result=True)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        with pytest.raises(ContractPatchError, match="whitelist"):
            engine.apply_and_validate(
                project_id=1,
                scope_type=self.DB_TEST_SCOPE,
                scope_id=self.DB_TEST_SCOPE_ID,
                patch=[{"op": "replace", "path": "nonexistent_field", "value": 1}],
                readback_text=self.VALID_READBACK,
                source_clause_ids=self.SOURCE_CLAUSE_IDS,
                source_hashes=self.SOURCE_HASHES,
            )

    def test_intra_conflict_rejected(
        self, conn: sqlite3.Connection, base_version_id: int,
    ) -> None:
        """同 patch 两个 op 改同 path → 步骤 2 拒绝。"""
        verifier = _ScriptedReadbackVerifier(result=True)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        with pytest.raises(ContractPatchError, match="same field path"):
            engine.apply_and_validate(
                project_id=1,
                scope_type=self.DB_TEST_SCOPE,
                scope_id=self.DB_TEST_SCOPE_ID,
                patch=[
                    {"op": "add", "path": "local_goal", "value": "a"},
                    {"op": "replace", "path": "local_goal", "value": "b"},
                ],
                readback_text=self.VALID_READBACK,
                source_clause_ids=self.SOURCE_CLAUSE_IDS,
                source_hashes=self.SOURCE_HASHES,
            )

    def test_affected_field_paths_match_patch(
        self, conn: sqlite3.Connection, base_version_id: int,
    ) -> None:
        verifier = _ScriptedReadbackVerifier(result=True)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        result = engine.apply_and_validate(
            project_id=1,
            scope_type=self.DB_TEST_SCOPE,
            scope_id=self.DB_TEST_SCOPE_ID,
            patch=[
                {"op": "replace", "path": "local_goal", "value": "a"},
                {"op": "add", "path": "risk_notes", "value": ["r1"]},
            ],
            readback_text=self.VALID_READBACK,
            source_clause_ids=self.SOURCE_CLAUSE_IDS,
            source_hashes=self.SOURCE_HASHES,
        )
        assert "local_goal" in result.affected_field_paths
        assert "risk_notes" in result.affected_field_paths


# ═══════════════════════════════════════════════════════════
#  集成测试：decision_sessions 与 patch_engine 的协同
# ═══════════════════════════════════════════════════════════

class TestIntegrationWithDecisionSession:
    """验证 record_ai_parse / confirm_and_apply 与 patch_engine 的集成点。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _insert_project(c)
        return c

    def _prepare_awaiting_session(
        self,
        conn: sqlite3.Connection,
        patch: list[dict] | None = None,
    ) -> int:
        """创建一条已进入 awaiting_confirm 的 session。"""
        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1, scope_type="part", scope_id="part-1",
            target_type="PartContract", target_id="part-1",
            human_text="调整局部目标",
        )
        store.record_ai_parse(
            session_id,
            parsed_patch=patch or [{"op": "replace", "path": "local_goal", "value": "新目标"}],
            readback_text="把局部目标改为新目标",
            source_hashes=["hash-a"],
        )
        store.create_option_set(session_id, options=[{"label": "确认"}], recommended_option=1)
        store.select_option(session_id, 1)
        return session_id

    def test_record_ai_parse_rejects_malformed_patch(self, conn: sqlite3.Connection) -> None:
        """传入 malformed patch 且 patch_engine 非 None → DataIntegrityError。"""
        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1, scope_type="part", scope_id="part-1",
            target_type="PartContract", target_id="part-1",
            human_text="测试",
        )
        engine = ContractPatchEngine(conn, readback_verifier=None)
        with pytest.raises(DataIntegrityError, match="malformed patch"):
            store.record_ai_parse(
                session_id,
                parsed_patch="not-a-list",  # type: ignore[arg-type]
                readback_text="测试",
                source_hashes=[],
                before_hash="bh",
                patch_engine=engine,
            )

    def test_record_ai_parse_accepts_valid_patch(self, conn: sqlite3.Connection) -> None:
        """合法 patch + patch_engine → 正常写库（不抛）。"""
        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1, scope_type="part", scope_id="part-1",
            target_type="PartContract", target_id="part-1",
            human_text="测试",
        )
        engine = ContractPatchEngine(conn, readback_verifier=None)
        store.record_ai_parse(
            session_id,
            parsed_patch=[{"op": "replace", "path": "local_goal", "value": "新目标"}],
            readback_text="测试",
            source_hashes=[],
            before_hash="bh",
            patch_engine=engine,
        )
        row = conn.execute(
            "SELECT status FROM writing_decision_sessions WHERE decision_session_id = ?",
            (session_id,),
        ).fetchone()
        assert row[0] == "ai_parsed"

    def test_confirm_and_apply_with_patch_engine_full_audit(
        self, conn: sqlite3.Connection,
    ) -> None:
        """patch_engine 模式：confirm_and_apply 自动应用 patch 写全审计链 + coverage。"""
        # 准备 base contract
        _insert_base_contract(conn)

        # 准备 awaiting session（patch 使用 JSON-Patch list）
        store = DecisionSessionStore(conn)
        session_id = self._prepare_awaiting_session(conn)

        # 构造 patch_engine
        verifier = _ScriptedReadbackVerifier(result=True)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        source_store = SourceWorkflowStore(conn)

        # 执行 confirm + patch engine
        result = store.confirm_and_apply(
            session_id,
            actor="author",
            reason="测试 patch engine",
            contract_scope_type="part",
            contract_scope_id="part-1",
            source_clause_ids=[1],
            source_hashes=["hash-a"],
            coverage_gate=source_store,
            patch_engine=engine,
        )

        # 验证审计链
        assert result.decision_session_id == session_id
        session_row = conn.execute(
            "SELECT status FROM writing_decision_sessions WHERE decision_session_id = ?",
            (session_id,),
        ).fetchone()
        assert session_row[0] == "confirmed"

        # 验证 contract_version 写入的是 patch 后的 payload
        version_row = conn.execute(
            "SELECT contract_json FROM writing_contract_versions WHERE contract_version_id = ?",
            (result.contract_version_id,),
        ).fetchone()
        version_payload = json.loads(version_row[0])
        assert version_payload["local_goal"] == "新目标"  # patch 覆盖
        assert version_payload["part_id"]["name"] == "序章"  # base 保留

        # patch_json 存原始 JSON-Patch
        patch_row = conn.execute(
            "SELECT patch_json FROM writing_contract_patches WHERE contract_patch_id = ?",
            (result.contract_patch_id,),
        ).fetchone()
        assert "local_goal" in str(patch_row[0])

        # coverage matrix 写入受影响路径
        coverage_rows = conn.execute(
            """
            SELECT contract_field_path, coverage_status
            FROM writing_source_coverage_matrix
            WHERE decision_session_id = ?
            """,
            (session_id,),
        ).fetchall()
        paths = {r[0] for r in coverage_rows}
        assert "local_goal" in paths
        statuses = {r[1] for r in coverage_rows}
        assert "covered" in statuses

    def test_confirm_and_apply_with_patch_engine_generates_payload(
        self, conn: sqlite3.Connection,
    ) -> None:
        """patch_engine 模式下不传 contract_payload → 正常派生。"""
        _insert_base_contract(conn)
        store = DecisionSessionStore(conn)
        session_id = self._prepare_awaiting_session(conn)

        verifier = _ScriptedReadbackVerifier(result=True)
        engine = ContractPatchEngine(conn, readback_verifier=verifier)
        source_store = SourceWorkflowStore(conn)

        # 显式不传 contract_payload
        result = store.confirm_and_apply(
            session_id,
            actor="author",
            reason="no payload test",
            contract_scope_type="part",
            contract_scope_id="part-1",
            source_clause_ids=[],
            source_hashes=["hash-a"],
            coverage_gate=source_store,
            patch_engine=engine,
        )
        assert result.contract_version_id > 0

    def test_confirm_and_apply_without_patch_engine_still_requires_payload(
        self, conn: sqlite3.Connection,
    ) -> None:
        """不传 patch_engine 且不传 contract_payload → DataIntegrityError。"""
        store = DecisionSessionStore(conn)
        session_id = self._prepare_awaiting_session(conn)

        with pytest.raises(DataIntegrityError, match="contract_payload or patch_engine"):
            store.confirm_and_apply(
                session_id,
                actor="author",
                reason="missing both",
                contract_scope_type="part",
                contract_scope_id="part-1",
                source_clause_ids=[],
                source_hashes=[],
                # contract_payload not provided, patch_engine not provided
            )

    def test_record_ai_parse_backward_compat_without_patch_engine(
        self, conn: sqlite3.Connection,
    ) -> None:
        """不传 patch_engine 时 record_ai_parse 保持原行为（接受 dict）。"""
        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1, scope_type="book", scope_id=None,
            target_type="BookContract", target_id="book",
            human_text="旧模式",
        )
        # 传 dict（旧格式），不传 patch_engine → 不会校验
        store.record_ai_parse(
            session_id,
            parsed_patch={"scope_type": "book"},  # 虽然不符合 JSON-Patch 格式，但无 patch_engine 检查
            readback_text="兼容",
            source_hashes=[],
        )
        row = conn.execute(
            "SELECT status FROM writing_decision_sessions WHERE decision_session_id = ?",
            (session_id,),
        ).fetchone()
        assert row[0] == "ai_parsed"
