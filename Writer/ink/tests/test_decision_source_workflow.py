from __future__ import annotations

import sqlite3

import pytest

from factories import NOW, make_schema_db
from ink.decision_sessions import DecisionSessionStore
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
