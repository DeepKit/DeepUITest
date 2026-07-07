from __future__ import annotations

import sqlite3

import pytest

from factories import NOW, make_schema_db
from ink.decision_sessions import ConfirmedContractResult, DecisionSessionStore
from ink.errors import DataIntegrityError
from ink.source_workflow import SourceWorkflowStore


def test_decision_session_enforces_single_active_target_and_option_regeneration() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    store = DecisionSessionStore(conn)

    session_id = store.start(
        project_id=1,
        scope_type="book",
        scope_id=None,
        target_type="BookContract",
        target_id="book",
        human_text="按这个方向封全书基线",
    )
    with pytest.raises(sqlite3.IntegrityError):
        store.start(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="第二个活跃会话不应允许",
        )

    store.record_ai_parse(
        session_id,
        parsed_patch={"scope_type": "book", "change_type": "refine"},
        readback_text="我理解为封全书基线。",
        source_hashes=["hash-guide"],
        before_hash="before",
    )
    first_option_set_id = store.create_option_set(
        session_id,
        options=[{"label": "确认基线"}, {"label": "补充人物"}],
        recommended_option=1,
    )
    second_option_set_id = store.regenerate_options(
        session_id,
        options=[{"label": "确认基线"}, {"label": "推迟证据链"}],
        recommended_option=1,
    )
    assert second_option_set_id != first_option_set_id

    rows = conn.execute(
        """
        SELECT version, status, regenerate_count
        FROM writing_decision_option_sets
        WHERE decision_session_id = ?
        ORDER BY version
        """,
        (session_id,),
    ).fetchall()
    assert rows == [(1, "superseded", 0), (2, "active", 1)]

    store.select_option(session_id, 2)
    store.confirm(session_id, after_hash="after")

    row = conn.execute(
        "SELECT status, selected_option, after_hash FROM writing_decision_sessions WHERE decision_session_id = ?",
        (session_id,),
    ).fetchone()
    assert row == ("confirmed", 2, "after")

    next_session_id = store.start(
        project_id=1,
        scope_type="book",
        scope_id=None,
        target_type="BookContract",
        target_id="book",
        human_text="confirmed 后允许新会话",
    )
    assert next_session_id != session_id


def test_decision_session_option_zero_returns_to_collecting_and_option_nine_requires_regeneration() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    store = DecisionSessionStore(conn)

    session_id = store.start(
        project_id=1,
        scope_type="chapter",
        scope_id="1",
        target_type="ChapterContract",
        target_id="1",
        human_text="调整第一章钩子",
    )
    store.record_ai_parse(
        session_id,
        parsed_patch={"scope_type": "chapter"},
        readback_text="我理解为调整第一章钩子。",
        source_hashes=[],
    )
    store.create_option_set(session_id, options=[{"label": "接受"}])

    with pytest.raises(DataIntegrityError):
        store.select_option(session_id, 9)

    store.select_option(session_id, 0)
    row = conn.execute(
        "SELECT status, selected_option FROM writing_decision_sessions WHERE decision_session_id = ?",
        (session_id,),
    ).fetchone()
    option_status = conn.execute(
        "SELECT status FROM writing_decision_option_sets WHERE decision_session_id = ?",
        (session_id,),
    ).fetchone()[0]
    assert row == ("collecting", None)
    assert option_status == "cancelled"


def test_source_coverage_gate_and_process_manifest_do_not_store_process_text() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    store = SourceWorkflowStore(conn)

    source_document_id = store.register_source_document(
        project_id=1,
        source_path="better.md",
        source_kind="process_scratch",
        content_hash="hash-before-clear",
    )
    clause_id = store.record_atomic_clause(
        project_id=1,
        source_document_id=source_document_id,
        scope_type="book",
        scope_id=None,
        clause_type="plot",
        severity="hard",
        clause_text="全书证据链必须先确认。",
        source_refs=["better.md#L1"],
        source_hashes=["hash-before-clear"],
        status="confirmed",
    )
    store.record_extraction_run(
        project_id=1,
        source_document_id=source_document_id,
        extractor_slot="primary",
        model_provider="mock",
        model_name="extractor-a",
        source_hash="hash-before-clear",
        extracted_clause_ids=[clause_id],
    )
    store.record_extraction_run(
        project_id=1,
        source_document_id=source_document_id,
        extractor_slot="crosscheck",
        model_provider="mock",
        model_name="extractor-b",
        source_hash="hash-before-clear",
        extracted_clause_ids=[],
        low_confidence_refs=["better.md#L1"],
    )
    coverage_id = store.record_coverage(
        project_id=1,
        contract_scope_type="book",
        contract_scope_id=None,
        contract_field_path="BookContract.evidence_chain",
        coverage_status="gap",
        atomic_clause_id=clause_id,
        evidence={"reason": "crosscheck_missing"},
    )
    assert store.has_blocking_coverage_gaps(project_id=1, contract_scope_type="book")

    store.resolve_coverage(
        coverage_id,
        coverage_status="covered",
        evidence={"decision": "author_confirmed"},
    )
    assert not store.has_blocking_coverage_gaps(project_id=1, contract_scope_type="book")

    manifest_id = store.record_process_file_manifest(
        project_id=1,
        source_document_id=source_document_id,
        source_path="better.md",
        content_hash="hash-before-clear",
        processed_hash="hash-empty-file",
        extracted_clause_ids=[clause_id],
        contract_patch_ids=[100],
        decision_session_ids=[200],
    )
    assert manifest_id > 0

    source_status = conn.execute(
        "SELECT status, processed_hash FROM writing_source_documents WHERE source_document_id = ?",
        (source_document_id,),
    ).fetchone()
    assert source_status == ("cleared", "hash-empty-file")

    manifest_columns = {
        row[1]
        for row in conn.execute("PRAGMA table_info(writing_process_file_manifests)").fetchall()
    }
    assert "content_text" not in manifest_columns
    assert "summary" not in manifest_columns


def test_option_set_rejects_more_than_eight_options() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    store = DecisionSessionStore(conn)
    session_id = store.start(
        project_id=1,
        scope_type="book",
        scope_id=None,
        target_type="BookContract",
        target_id="book",
        human_text="选择太多",
    )
    store.record_ai_parse(session_id, parsed_patch={}, readback_text="太多选项。", source_hashes=[])

    with pytest.raises(DataIntegrityError):
        store.create_option_set(session_id, options=[{"label": str(index)} for index in range(9)])


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


def _prepare_awaiting_session(store: DecisionSessionStore, *, scope_type: str = "book", scope_id: str | None = None, target_id: str = "book") -> int:
    session_id = store.start(
        project_id=1,
        scope_type=scope_type,
        scope_id=scope_id,
        target_type=f"{scope_type.capitalize()}Contract",
        target_id=target_id,
        human_text="封基线",
    )
    store.record_ai_parse(
        session_id,
        parsed_patch={"scope_type": scope_type, "change_type": "refine"},
        readback_text="我理解为封基线。",
        source_hashes=["hash-guide"],
        before_hash="before-hash",
    )
    store.create_option_set(session_id, options=[{"label": "确认基线"}], recommended_option=1)
    store.select_option(session_id, 1)
    return session_id


def test_confirm_and_apply_atomically_writes_full_audit_chain() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    store = DecisionSessionStore(conn)
    session_id = _prepare_awaiting_session(store)

    result = store.confirm_and_apply(
        session_id,
        actor="author",
        reason="封全书基线",
        contract_scope_type="book",
        contract_scope_id=None,
        contract_payload={"identity": {"title": "Demo"}, "logline": "core promise"},
        change_type="refine",
        source_clause_ids=[101, 102],
        affected_scopes=[{"scope_type": "book"}],
        stale_downstream=[],
        source_hashes=["hash-guide"],
    )

    assert isinstance(result, ConfirmedContractResult)
    assert result.decision_session_id == session_id

    session_row = conn.execute(
        "SELECT status, after_hash FROM writing_decision_sessions WHERE decision_session_id = ?",
        (session_id,),
    ).fetchone()
    assert session_row[0] == "confirmed"
    assert session_row[1] == result.after_hash

    decision_row = conn.execute(
        """
        SELECT decision_type, actor, reason
        FROM writing_human_decisions WHERE decision_id = ?
        """,
        (result.human_decision_id,),
    ).fetchone()
    assert decision_row == ("contract_confirm", "author", "封全书基线")

    version_row = conn.execute(
        """
        SELECT scope_type, scope_id, version, status, contract_hash,
               created_from_decision_session_id
        FROM writing_contract_versions WHERE contract_version_id = ?
        """,
        (result.contract_version_id,),
    ).fetchone()
    assert version_row[0] == "book"
    assert version_row[1] is None
    assert version_row[2] == 1
    assert version_row[3] == "confirmed"
    assert version_row[4] == result.after_hash
    assert version_row[5] == session_id

    patch_row = conn.execute(
        """
        SELECT decision_session_id, base_contract_version_id, target_contract_version_id,
               change_type, status
        FROM writing_contract_patches WHERE contract_patch_id = ?
        """,
        (result.contract_patch_id,),
    ).fetchone()
    assert patch_row[0] == session_id
    assert patch_row[1] is None  # 首次确认无 base
    assert patch_row[2] == result.contract_version_id
    assert patch_row[3] == "refine"
    assert patch_row[4] == "confirmed"

    changelog_row = conn.execute(
        """
        SELECT old_hash, new_hash, human_decision_id
        FROM writing_contract_changelog WHERE change_id = ?
        """,
        (result.contract_changelog_id,),
    ).fetchone()
    assert changelog_row[0] == "before-hash"
    assert changelog_row[1] == result.after_hash
    assert changelog_row[2] == result.human_decision_id


def test_confirm_and_apply_second_version_links_base_contract_version() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    store = DecisionSessionStore(conn)

    first_session = _prepare_awaiting_session(store, target_id="book")
    first_result = store.confirm_and_apply(
        first_session,
        actor="author",
        reason="封基线",
        contract_scope_type="book",
        contract_scope_id=None,
        contract_payload={"identity": {"title": "Demo"}},
        source_hashes=["hash-guide"],
    )

    second_session = _prepare_awaiting_session(store, target_id="book")
    second_result = store.confirm_and_apply(
        second_session,
        actor="author",
        reason="细化证据链",
        contract_scope_type="book",
        contract_scope_id=None,
        contract_payload={"identity": {"title": "Demo"}, "evidence_chain": "chain-v2"},
        source_hashes=["hash-guide"],
    )

    assert second_result.contract_version_id != first_result.contract_version_id
    patch_row = conn.execute(
        """
        SELECT base_contract_version_id, target_contract_version_id, version
        FROM writing_contract_patches p
        JOIN writing_contract_versions v ON v.contract_version_id = p.target_contract_version_id
        WHERE p.contract_patch_id = ?
        """,
        (second_result.contract_patch_id,),
    ).fetchone()
    assert patch_row[0] == first_result.contract_version_id
    assert patch_row[1] == second_result.contract_version_id
    assert patch_row[2] == 2  # 第二次确认版本号递增


def test_confirm_and_apply_blocked_by_coverage_gate() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    store = DecisionSessionStore(conn)
    source_store = SourceWorkflowStore(conn)

    source_document_id = source_store.register_source_document(
        project_id=1,
        source_path="guide.md",
        source_kind="guide",
        content_hash="hash-guide",
    )
    clause_id = source_store.record_atomic_clause(
        project_id=1,
        source_document_id=source_document_id,
        scope_type="book",
        scope_id=None,
        clause_type="plot",
        severity="hard",
        clause_text="全书证据链必须先确认。",
        source_refs=["guide.md#L1"],
        source_hashes=["hash-guide"],
    )
    source_store.record_coverage(
        project_id=1,
        contract_scope_type="book",
        contract_scope_id=None,
        contract_field_path="BookContract.evidence_chain",
        coverage_status="gap",
        atomic_clause_id=clause_id,
    )

    session_id = _prepare_awaiting_session(store)
    with pytest.raises(DataIntegrityError):
        store.confirm_and_apply(
            session_id,
            actor="author",
            reason="封基线",
            contract_scope_type="book",
            contract_scope_id=None,
            contract_payload={"identity": {"title": "Demo"}},
            source_hashes=["hash-guide"],
            coverage_gate=source_store,
        )

    # 阻断时不应写入任何审计行
    assert conn.execute(
        "SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'contract_confirm'"
    ).fetchone()[0] == 0
    assert conn.execute("SELECT count(*) FROM writing_contract_versions").fetchone()[0] == 0
    assert conn.execute("SELECT count(*) FROM writing_contract_patches").fetchone()[0] == 0
    assert conn.execute("SELECT count(*) FROM writing_contract_changelog").fetchone()[0] == 0
    session_status = conn.execute(
        "SELECT status FROM writing_decision_sessions WHERE decision_session_id = ?",
        (session_id,),
    ).fetchone()[0]
    assert session_status == "awaiting_confirm"


def test_confirm_and_apply_rejects_non_awaiting_session() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    store = DecisionSessionStore(conn)
    session_id = store.start(
        project_id=1,
        scope_type="book",
        scope_id=None,
        target_type="BookContract",
        target_id="book",
        human_text="未解析",
    )
    with pytest.raises(DataIntegrityError):
        store.confirm_and_apply(
            session_id,
            actor="author",
            reason="封基线",
            contract_scope_type="book",
            contract_scope_id=None,
            contract_payload={},
            source_hashes=[],
        )


def test_list_coverage_gaps_returns_gap_detail_and_suggested_clauses() -> None:
    """list_coverage_gaps 返回 gap 明细 + 建议源条款。"""
    conn = make_schema_db()
    _insert_project(conn)
    store = SourceWorkflowStore(conn)

    doc_id = store.register_source_document(
        project_id=1, source_path="guide.md", source_kind="guide",
        content_hash="h1",
    )
    # 两条同 scope 的 atomic clause，clause_type 含 "must_land"
    clause_a = store.record_atomic_clause(
        project_id=1, source_document_id=doc_id, scope_type="book", scope_id=None,
        clause_type="plot", severity="hard", clause_text="主角必须登场。",
        source_refs=["guide.md#L1"], source_hashes=["h1"], status="confirmed",
    )
    clause_b = store.record_atomic_clause(
        project_id=1, source_document_id=doc_id, scope_type="book", scope_id=None,
        clause_type="forbidden", severity="hard", clause_text="禁止反派视角。",
        source_refs=["guide.md#L2"], source_hashes=["h1"], status="confirmed",
    )
    # 一个 gap（关联 clause_a）+ 一个 conflict
    store.record_coverage(
        project_id=1, contract_scope_type="book", contract_scope_id=None,
        contract_field_path="must_land.protagonist", coverage_status="gap",
        atomic_clause_id=clause_a, evidence={"reason": "missing"},
    )
    store.record_coverage(
        project_id=1, contract_scope_type="book", contract_scope_id=None,
        contract_field_path="anti_write.villain_pov", coverage_status="conflict",
        evidence={"conflict": "two_sources"},
    )
    # 一个 covered，不应出现在结果里
    store.record_coverage(
        project_id=1, contract_scope_type="book", contract_scope_id=None,
        contract_field_path="tone.dramatic", coverage_status="covered",
    )

    gaps = store.list_coverage_gaps(project_id=1, contract_scope_type="book")
    assert len(gaps) == 2
    # 按 field_path 排序：anti_write 在前
    assert gaps[0].field_path == "anti_write.villain_pov"
    assert gaps[0].status == "conflict"
    assert gaps[1].field_path == "must_land.protagonist"
    assert gaps[1].status == "gap"
    assert gaps[1].atomic_clause_id == clause_a
    # must_land 顶层组应优先匹配 clause_type LIKE %must_land% 的 clause_a
    assert clause_a in gaps[1].suggested_clause_ids


def test_list_coverage_gaps_filters_by_scope() -> None:
    """scope 过滤：只返回指定 scope 的 gap。"""
    conn = make_schema_db()
    _insert_project(conn)
    store = SourceWorkflowStore(conn)

    store.record_coverage(
        project_id=1, contract_scope_type="book", contract_scope_id=None,
        contract_field_path="BookContract.logline", coverage_status="gap",
    )
    store.record_coverage(
        project_id=1, contract_scope_type="chapter", contract_scope_id="5",
        contract_field_path="ShotContract.scene", coverage_status="gap",
    )

    book_gaps = store.list_coverage_gaps(project_id=1, contract_scope_type="book")
    assert len(book_gaps) == 1
    assert book_gaps[0].scope_type == "book"

    chapter_gaps = store.list_coverage_gaps(
        project_id=1, contract_scope_type="chapter", contract_scope_id="5",
    )
    assert len(chapter_gaps) == 1
    assert chapter_gaps[0].scope_id == "5"
