from __future__ import annotations

import json
from pathlib import Path

import pytest

from ink.errors import DataIntegrityError
from ink.pipeline.import_orchestrator import ImportOrchestrator
from test_schema_contract import NOW, make_schema_db


def test_import_dry_run_finalize(tmp_path: Path) -> None:
    conn = make_import_project()
    source_root = tmp_path / "source"
    source_root.mkdir()
    (source_root / "chapter-01.md").write_text("# Chapter 1\nScene text.", encoding="utf-8")
    (source_root / "notes.txt").write_text("author notes", encoding="utf-8")
    (source_root / "ignored.docx").write_text("not supported", encoding="utf-8")

    dry_run = ImportOrchestrator(conn).dry_run(1, str(source_root))

    assert dry_run.manifest_count == 2
    assert dry_run.question_count == 0
    run = conn.execute(
        """
        SELECT mode, status, source_root, finalized_at
        FROM writing_import_runs
        WHERE import_run_id = ?
        """,
        (dry_run.import_run_id,),
    ).fetchone()
    assert run == ("dry_run", "completed", str(source_root), None)

    manifests = conn.execute(
        """
        SELECT source_path, source_hash, target_chapter_id, action
        FROM writing_import_manifests
        WHERE import_run_id = ?
        ORDER BY source_path
        """,
        (dry_run.import_run_id,),
    ).fetchall()
    assert [(row[0], row[2], row[3]) for row in manifests] == [
        ("chapter-01.md", 1, "create"),
        ("notes.txt", 2, "create"),
    ]
    assert all(len(row[1]) == 64 for row in manifests)
    assert all(not Path(row[0]).is_absolute() and "\\" not in row[0] for row in manifests)
    assert conn.execute("SELECT count(*) FROM writing_import_questions").fetchone()[0] == 0
    assert _formal_body_counts(conn) == {"shots": 0, "drafts": 0, "revisions": 0, "chapter_reviews": 0}

    finalized = ImportOrchestrator(conn).finalize(
        dry_run.import_run_id,
        actor="author",
        reason="approved dry-run manifest",
    )

    assert finalized.import_decision_id > 0
    assert finalized.human_decision_id > 0
    human_decision = conn.execute(
        """
        SELECT decision_type, actor, reason, preconditions_json, quality_report_json, hard_quality_override
        FROM writing_human_decisions
        WHERE decision_id = ?
        """,
        (finalized.human_decision_id,),
    ).fetchone()
    assert human_decision[:3] == ("import_finalize", "author", "approved dry-run manifest")
    assert json.loads(human_decision[3]) == {
        "import_run_id": dry_run.import_run_id,
        "manifest_count": 2,
        "source_hash_verified": True,
    }
    assert human_decision[4:] == ("{}", 0)

    import_decision = conn.execute(
        """
        SELECT import_run_id, human_decision_id, applied_manifest_hash
        FROM writing_import_decisions
        WHERE import_decision_id = ?
        """,
        (finalized.import_decision_id,),
    ).fetchone()
    assert import_decision[:2] == (dry_run.import_run_id, finalized.human_decision_id)
    assert len(import_decision[2]) == 64
    assert conn.execute(
        "SELECT finalized_at FROM writing_import_runs WHERE import_run_id = ?",
        (dry_run.import_run_id,),
    ).fetchone()[0] is not None
    assert _formal_body_counts(conn) == {"shots": 0, "drafts": 0, "revisions": 0, "chapter_reviews": 0}


def test_import_finalize_rejects_changed_source_hash(tmp_path: Path) -> None:
    conn = make_import_project()
    source_root = tmp_path / "source"
    source_root.mkdir()
    source_file = source_root / "chapter-01.md"
    source_file.write_text("first version", encoding="utf-8")
    dry_run = ImportOrchestrator(conn).dry_run(1, str(source_root))
    source_file.write_text("changed version", encoding="utf-8")

    with pytest.raises(DataIntegrityError, match="source changed"):
        ImportOrchestrator(conn).finalize(
            dry_run.import_run_id,
            actor="author",
            reason="approve changed source",
        )

    assert conn.execute("SELECT count(*) FROM writing_human_decisions").fetchone()[0] == 0
    assert conn.execute("SELECT count(*) FROM writing_import_decisions").fetchone()[0] == 0
    assert conn.execute(
        "SELECT finalized_at FROM writing_import_runs WHERE import_run_id = ?",
        (dry_run.import_run_id,),
    ).fetchone()[0] is None


def test_import_finalize_rejects_unresolved_questions(tmp_path: Path) -> None:
    conn = make_import_project()
    source_root = tmp_path / "source"
    source_root.mkdir()
    (source_root / "chapter-01.md").write_text("first version", encoding="utf-8")
    dry_run = ImportOrchestrator(conn).dry_run(1, str(source_root))
    manifest_id = conn.execute(
        "SELECT manifest_id FROM writing_import_manifests WHERE import_run_id = ?",
        (dry_run.import_run_id,),
    ).fetchone()[0]
    conn.execute(
        """
        INSERT INTO writing_import_questions
            (import_run_id, manifest_id, question_text, options_json)
        VALUES (?, ?, 'confirm target chapter', '[]')
        """,
        (dry_run.import_run_id, manifest_id),
    )

    with pytest.raises(DataIntegrityError, match="questions resolved"):
        ImportOrchestrator(conn).finalize(
            dry_run.import_run_id,
            actor="author",
            reason="approve unresolved mapping",
        )

    assert conn.execute("SELECT count(*) FROM writing_human_decisions").fetchone()[0] == 0
    assert conn.execute("SELECT count(*) FROM writing_import_decisions").fetchone()[0] == 0


def make_import_project():
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'import-demo', 'Import Demo', '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
        """,
        (NOW,),
    )
    return conn


def _formal_body_counts(conn) -> dict[str, int]:
    return {
        "shots": conn.execute("SELECT count(*) FROM writing_shots").fetchone()[0],
        "drafts": conn.execute("SELECT count(*) FROM writing_drafts").fetchone()[0],
        "revisions": conn.execute("SELECT count(*) FROM writing_shot_revisions").fetchone()[0],
        "chapter_reviews": conn.execute("SELECT count(*) FROM writing_chapter_reviews").fetchone()[0],
    }
