from __future__ import annotations

import json

from factories import NOW, make_schema_db
from ink.pipeline.source_extraction_orchestrator import (
    ExtractedClause,
    SourceExtractionOrchestrator,
)
from ink.source_workflow import SourceWorkflowStore


def _insert_project(conn) -> None:
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


class _ScriptedProtocol:
    """按预设 clause 集合返回，绕过真实 LLM。"""

    def __init__(self, primary, crosscheck) -> None:
        self._primary = primary
        self._crosscheck = crosscheck

    def build_prompt(self, *, source_text, source_path) -> str:
        return "prompt"

    def parse(self, *, raw_text, source_hashes):
        if raw_text == "primary":
            return list(self._primary)
        if raw_text == "crosscheck":
            return list(self._crosscheck)
        return []


class _ScriptedGateway:
    """返回固定文本让 protocol 路由到对应 clause 集合。"""

    def call(self, **kwargs):
        call_type = kwargs.get("call_type")
        text = "primary" if call_type == "source_extract_primary" else "crosscheck"

        class _Result:
            pass

        result = _Result()
        result.text = text
        result.model_name = kwargs.get("model_name")
        result.token_input = 0
        result.token_output = 0
        result.finish_reason = "stop"
        return result


def _make_clause(text, *, clause_type="style", severity="hard", source_ref="guide.md#L1") -> ExtractedClause:
    return ExtractedClause(
        scope_type="book",
        scope_id=None,
        clause_type=clause_type,
        severity=severity,
        clause_text=text,
        source_refs=(source_ref,),
        source_hashes=("hash-guide",),
    )


def _setup_store(conn) -> int:
    store = SourceWorkflowStore(conn)
    return store.register_source_document(
        project_id=1, source_path="guide.md", source_kind="guide", content_hash="hash-guide",
    )


def _extract(orchestrator, source_document_id):
    return orchestrator.extract_dual(
        project_id=1,
        source_document_id=source_document_id,
        source_text="guide text",
        source_path="guide.md",
        source_hash="hash-guide",
        primary_model="extractor-a",
        crosscheck_model="extractor-b",
    )


def test_dual_extraction_persists_consistent_clauses_once_per_run() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    source_document_id = _setup_store(conn)

    shared = [_make_clause("全书证据链必须先确认。")]
    orchestrator = SourceExtractionOrchestrator(
        conn, gateway=_ScriptedGateway(), protocol=_ScriptedProtocol(shared, shared)
    )

    result = _extract(orchestrator, source_document_id)

    assert result.discrepancy.missing_in_crosscheck == ()
    assert result.discrepancy.missing_in_primary == ()
    assert result.discrepancy.conflict_texts == ()
    assert len(result.primary_clause_ids) == 1
    assert len(result.crosscheck_clause_ids) == 1
    assert result.primary_extraction_run_id > 0
    assert result.crosscheck_extraction_run_id > 0

    runs = conn.execute(
        "SELECT extractor_slot, model_name, status FROM writing_source_extraction_runs ORDER BY extractor_slot"
    ).fetchall()
    assert runs == [("crosscheck", "extractor-b", "completed"), ("primary", "extractor-a", "completed")]

    assert conn.execute("SELECT count(*) FROM writing_atomic_source_clauses").fetchone()[0] == 2
    assert conn.execute(
        "SELECT count(*) FROM writing_source_coverage_matrix WHERE coverage_status = 'conflict'"
    ).fetchone()[0] == 0


def test_dual_extraction_flags_crosscheck_missing_as_low_confidence() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    source_document_id = _setup_store(conn)

    primary_only = _make_clause("primary 抽到但 crosscheck 漏抽的条款。")
    orchestrator = SourceExtractionOrchestrator(
        conn, gateway=_ScriptedGateway(), protocol=_ScriptedProtocol([primary_only], [])
    )

    result = _extract(orchestrator, source_document_id)

    assert len(result.discrepancy.missing_in_crosscheck) == 1
    assert result.discrepancy.missing_in_primary == ()
    primary_run = conn.execute(
        "SELECT low_confidence_refs_json FROM writing_source_extraction_runs WHERE extractor_slot = 'primary'"
    ).fetchone()[0]
    refs = json.loads(primary_run)
    assert len(refs) == 1
    assert refs[0].startswith("primary_only:")


def test_dual_extraction_records_text_conflicts_as_coverage_conflict() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    source_document_id = _setup_store(conn)

    # 同位置（同 source_ref）但文本不同 → conflict
    primary_clause = _make_clause("证据链必须三步。")
    crosscheck_clause = _make_clause("证据链必须五步。")
    orchestrator = SourceExtractionOrchestrator(
        conn,
        gateway=_ScriptedGateway(),
        protocol=_ScriptedProtocol([primary_clause], [crosscheck_clause]),
    )

    result = _extract(orchestrator, source_document_id)

    assert len(result.discrepancy.conflict_texts) == 1
    p, c = result.discrepancy.conflict_texts[0]
    assert p.clause_text == "证据链必须三步。"
    assert c.clause_text == "证据链必须五步。"
    conflict_row = conn.execute(
        """
        SELECT coverage_status, contract_field_path, evidence_json
        FROM writing_source_coverage_matrix WHERE coverage_status = 'conflict'
        """
    ).fetchone()
    assert conflict_row is not None
    assert "conflict:" in conflict_row[1]
    evidence = json.loads(conflict_row[2])
    assert evidence["primary_text"] == "证据链必须三步。"
    assert evidence["crosscheck_text"] == "证据链必须五步。"


def test_dual_extraction_primary_missing_flags_crosscheck_low_confidence() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    source_document_id = _setup_store(conn)

    crosscheck_only = _make_clause("crosscheck 抽到但 primary 漏抽的条款。")
    orchestrator = SourceExtractionOrchestrator(
        conn, gateway=_ScriptedGateway(), protocol=_ScriptedProtocol([], [crosscheck_only])
    )

    result = _extract(orchestrator, source_document_id)

    assert len(result.discrepancy.missing_in_primary) == 1
    assert result.discrepancy.missing_in_crosscheck == ()
    crosscheck_run = conn.execute(
        "SELECT low_confidence_refs_json FROM writing_source_extraction_runs WHERE extractor_slot = 'crosscheck'"
    ).fetchone()[0]
    refs = json.loads(crosscheck_run)
    assert len(refs) == 1
    assert refs[0].startswith("crosscheck_only:")
