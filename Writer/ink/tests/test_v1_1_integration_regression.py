"""跨模块防回归测试：覆盖本次 v1.1 集成引入的关键不变量。

这些测试不重复单个模块的单元测试，而是验证模块间的端到端不变量——
未来若有人改动其中一个模块而破坏协作链路，这些测试会先失败。
"""

from __future__ import annotations

import json
import sqlite3

from factories import NOW, make_schema_db
from ink.decision_sessions import DecisionSessionStore
from ink.errors import DataIntegrityError
from ink.pipeline.process_file_clearing_orchestrator import (
    ProcessFileClearingOrchestrator,
)
from ink.pipeline.source_extraction_orchestrator import (
    ExtractedClause,
    SourceExtractionOrchestrator,
)
from ink.source_workflow import SourceWorkflowStore
from test_source_extraction_orchestrator import (
    _ScriptedGateway,
    _ScriptedProtocol,
    _make_clause as _make_extraction_clause,
)


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


def test_extraction_conflict_blocks_contract_confirm_end_to_end() -> None:
    """双模型抽取产生 text conflict → coverage matrix 记 conflict → confirm_and_apply 被阻断。

    防回归点：抽取器的 conflict 写入与 coverage gate 的阻断查询必须协同——
    若 conflict 写入路径或 gate 查询被改动导致 conflict 不再阻断，此测试失败。
    """
    conn = make_schema_db()
    _insert_project(conn)
    store = SourceWorkflowStore(conn)
    source_document_id = store.register_source_document(
        project_id=1, source_path="guide.md", source_kind="guide", content_hash="hash-guide",
    )

    # 双模型抽取：同位置不同文本 → conflict
    primary_clause = _make_extraction_clause("证据链必须三步。")
    crosscheck_clause = _make_extraction_clause("证据链必须五步。")
    orchestrator = SourceExtractionOrchestrator(
        conn,
        gateway=_ScriptedGateway(),
        protocol=_ScriptedProtocol([primary_clause], [crosscheck_clause]),
    )
    orchestrator.extract_dual(
        project_id=1,
        source_document_id=source_document_id,
        source_text="guide text",
        source_path="guide.md",
        source_hash="hash-guide",
        primary_model="extractor-a",
        crosscheck_model="extractor-b",
    )

    # 此时存在 conflict，阻断 confirm_and_apply
    assert store.has_blocking_coverage_gaps(project_id=1) is True

    ds_store = DecisionSessionStore(conn)
    session_id = ds_store.start(
        project_id=1, scope_type="book", scope_id=None,
        target_type="BookContract", target_id="book", human_text="封基线",
    )
    ds_store.record_ai_parse(
        session_id, parsed_patch={"scope_type": "book"}, readback_text="封基线。",
        source_hashes=["hash-guide"], before_hash="before-hash",
    )
    ds_store.create_option_set(session_id, options=[{"label": "确认"}], recommended_option=1)
    ds_store.select_option(session_id, 1)

    try:
        ds_store.confirm_and_apply(
            session_id,
            actor="author",
            reason="confirm",
            contract_scope_type="book",
            contract_scope_id=None,
            contract_payload={"identity": {"title": "Demo"}},
            source_clause_ids=[],
            source_hashes=["hash-guide"],
            coverage_gate=store,
        )
    except DataIntegrityError:
        # 验证不写任何审计行
        assert conn.execute("SELECT count(*) FROM writing_contract_versions").fetchone()[0] == 0
        return
    raise AssertionError("confirm_and_apply should be blocked by extraction conflict")


def test_resolving_extraction_conflict_releases_confirm() -> None:
    """resolve coverage conflict → gate 放行 → confirm_and_apply 成功写入审计链。

    防回归点：conflict 被 resolve 后，gate 必须放行；且 confirm 写入的
    human_decision 的 preconditions 必须记录 coverage_gate_checked=True。
    """
    conn = make_schema_db()
    _insert_project(conn)
    store = SourceWorkflowStore(conn)
    source_document_id = store.register_source_document(
        project_id=1, source_path="guide.md", source_kind="guide", content_hash="hash-guide",
    )

    primary_clause = _make_extraction_clause("证据链必须三步。")
    crosscheck_clause = _make_extraction_clause("证据链必须五步。")
    orchestrator = SourceExtractionOrchestrator(
        conn,
        gateway=_ScriptedGateway(),
        protocol=_ScriptedProtocol([primary_clause], [crosscheck_clause]),
    )
    orchestrator.extract_dual(
        project_id=1,
        source_document_id=source_document_id,
        source_text="guide text",
        source_path="guide.md",
        source_hash="hash-guide",
        primary_model="extractor-a",
        crosscheck_model="extractor-b",
    )

    # resolve conflict
    conflict_id = conn.execute(
        "SELECT coverage_id FROM writing_source_coverage_matrix WHERE coverage_status = 'conflict' LIMIT 1"
    ).fetchone()[0]
    store.resolve_coverage(conflict_id, coverage_status="covered", evidence={"reason": "作者裁定三步"})
    assert store.has_blocking_coverage_gaps(project_id=1) is False

    ds_store = DecisionSessionStore(conn)
    session_id = ds_store.start(
        project_id=1, scope_type="book", scope_id=None,
        target_type="BookContract", target_id="book", human_text="封基线",
    )
    ds_store.record_ai_parse(
        session_id, parsed_patch={"scope_type": "book"}, readback_text="封基线。",
        source_hashes=["hash-guide"], before_hash="before-hash",
    )
    ds_store.create_option_set(session_id, options=[{"label": "确认"}], recommended_option=1)
    ds_store.select_option(session_id, 1)

    result = ds_store.confirm_and_apply(
        session_id,
        actor="author",
        reason="confirm",
        contract_scope_type="book",
        contract_scope_id=None,
        contract_payload={"identity": {"title": "Demo"}},
        source_clause_ids=[],
        source_hashes=["hash-guide"],
        coverage_gate=store,
    )
    assert result.contract_version_id > 0

    # 防回归：human_decision 的 preconditions 必须记录 coverage_gate_checked
    preconditions_json = conn.execute(
        "SELECT preconditions_json FROM writing_human_decisions WHERE decision_type = 'contract_confirm'"
    ).fetchone()[0]
    preconditions = json.loads(preconditions_json)
    assert preconditions.get("coverage_gate_checked") is True


def test_process_file_clearing_then_extraction_clauses_persist_independent() -> None:
    """过程文件清空后，已抽取的 atomic clauses 仍可被 coverage gate 引用。

    防回归点：清空执行器只清磁盘文件 + 写 manifest，不能删除/失效已抽取的 atomic clauses
    与 coverage 记录——否则契约确认时 gate 查不到 gap，会错误放行。
    """
    conn = make_schema_db()
    _insert_project(conn)
    store = SourceWorkflowStore(conn)
    source_document_id = store.register_source_document(
        project_id=1, source_path="guide.md", source_kind="guide", content_hash="hash-guide",
    )
    clause_id = store.record_atomic_clause(
        project_id=1, source_document_id=source_document_id,
        scope_type="book", scope_id=None, clause_type="style", severity="hard",
        clause_text="清空后仍有效的硬约束。", source_refs=["guide.md#L1"], source_hashes=["hash-guide"],
    )
    coverage_id = store.record_coverage(
        project_id=1, contract_scope_type="book", contract_scope_id=None,
        contract_field_path="BookContract.style", coverage_status="gap",
        atomic_clause_id=clause_id,
    )

    # 清空另一个过程文件（不影响已抽取条款）
    import tempfile, os
    tmp = tempfile.mkdtemp()
    better_md = os.path.join(tmp, "better.md")
    with open(better_md, "w", encoding="utf-8") as f:
        f.write("过程草稿内容")
    ProcessFileClearingOrchestrator(conn).clear_process_file(
        project_id=1, source_path=better_md,
    )

    # 清空后：atomic clauses 与 coverage gap 仍存在，gate 仍阻断
    assert conn.execute("SELECT count(*) FROM writing_atomic_source_clauses WHERE atomic_clause_id = ?", (clause_id,)).fetchone()[0] == 1
    assert store.has_blocking_coverage_gaps(project_id=1) is True

    # resolve 后放行
    store.resolve_coverage(coverage_id, coverage_status="covered", evidence={"r": "ok"})
    assert store.has_blocking_coverage_gaps(project_id=1) is False
