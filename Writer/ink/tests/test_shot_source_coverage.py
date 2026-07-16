from __future__ import annotations

import pytest

from factories import make_schema_db
from ink.source_workflow import SourceWorkflowStore


@pytest.fixture
def seeded():
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'coverage', 'Coverage',
                '["w1","w2","w3"]', '["j1","j2","j3","j4","j5"]',
                '2026-07-11T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_sessions (session_id, project_id, started_at)
        VALUES (10, 1, '2026-07-11T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_runs
            (run_id, project_id, session_id, run_attempt, started_at, status)
        VALUES (20, 1, 10, 1, '2026-07-11T00:00:00Z', 'running')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_shots
            (shot_id, project_id, chapter_id, run_id, logical_shot_id,
             status, created_at, updated_at)
        VALUES ('c03-s01', 1, 3, 20, 'c03-s01', 'pending',
                '2026-07-11T00:00:00Z', '2026-07-11T00:00:00Z')
        """
    )
    store = SourceWorkflowStore(conn)
    document_id = store.register_source_document(
        project_id=1,
        source_path="guide.md",
        source_kind="guide",
        content_hash="hash",
    )
    book_clause = store.record_atomic_clause(
        project_id=1,
        source_document_id=document_id,
        scope_type="book",
        scope_id=None,
        clause_type="quality",
        severity="hard",
        clause_text="失效判断必须给出可观测证据。",
        source_refs=["guide.md:1"],
        source_hashes=["hash"],
        status="confirmed",
    )
    chapter_clause = store.record_atomic_clause(
        project_id=1,
        source_document_id=document_id,
        scope_type="chapter",
        scope_id="3",
        clause_type="plot",
        severity="soft",
        clause_text="本章必须落地封样冲突。",
        source_refs=["guide.md:2"],
        source_hashes=["hash"],
        status="confirmed",
    )
    other_chapter_clause = store.record_atomic_clause(
        project_id=1,
        source_document_id=document_id,
        scope_type="chapter",
        scope_id="4",
        clause_type="plot",
        severity="hard",
        clause_text="第四章条款。",
        source_refs=["guide.md:3"],
        source_hashes=["hash"],
        status="confirmed",
    )
    yield conn, store, book_clause, chapter_clause, other_chapter_clause
    conn.close()


def test_shot_coverage_lists_applicable_book_chapter_and_shot_clauses(seeded) -> None:
    _, store, book_clause, chapter_clause, other = seeded
    records = store.list_shot_clause_coverage(project_id=1, shot_id="c03-s01")
    ids = {record.atomic_clause_id for record in records}
    assert ids == {book_clause, chapter_clause}
    assert other not in ids
    assert all(record.coverage_status == "gap" for record in records)


def test_latest_shot_coverage_record_wins(seeded) -> None:
    _, store, book_clause, _, _ = seeded
    store.record_shot_clause_coverage(
        project_id=1,
        shot_id="c03-s01",
        atomic_clause_id=book_clause,
        coverage_status="gap",
    )
    store.record_shot_clause_coverage(
        project_id=1,
        shot_id="c03-s01",
        atomic_clause_id=book_clause,
        coverage_status="covered",
        evidence={"draft_id": 8, "sentence": "裂纹宽度达到零点三毫米。"},
    )
    record = next(
        item
        for item in store.list_shot_clause_coverage(project_id=1, shot_id="c03-s01")
        if item.atomic_clause_id == book_clause
    )
    assert record.coverage_status == "covered"
    assert record.evidence["draft_id"] == 8


def test_shot_coverage_rejects_cross_project_clause(seeded) -> None:
    conn, store, _, _, _ = seeded
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (2, 'other', 'Other',
                '["w1","w2","w3"]', '["j1","j2","j3","j4","j5"]',
                '2026-07-11T00:00:00Z')
        """
    )
    other_doc = store.register_source_document(
        project_id=2,
        source_path="other.md",
        source_kind="guide",
        content_hash="other",
    )
    other_clause = store.record_atomic_clause(
        project_id=2,
        source_document_id=other_doc,
        scope_type="book",
        scope_id=None,
        clause_type="world",
        severity="hard",
        clause_text="Other.",
        source_refs=["other.md:1"],
        source_hashes=["other"],
    )
    with pytest.raises(ValueError, match="does not belong"):
        store.record_shot_clause_coverage(
            project_id=1,
            shot_id="c03-s01",
            atomic_clause_id=other_clause,
            coverage_status="covered",
        )
