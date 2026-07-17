from __future__ import annotations

import importlib.util
import sqlite3
from pathlib import Path


_TOOL = Path(__file__).resolve().parents[1] / "tools" / "migrate_scene_accept_gate_evidence.py"
_SPEC = importlib.util.spec_from_file_location("migrate_scene_accept_gate_evidence", _TOOL)
assert _SPEC is not None and _SPEC.loader is not None
_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MODULE)


def _legacy_db() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.executescript(
        """
        PRAGMA foreign_keys = ON;
        CREATE TABLE writing_projects (project_id INTEGER PRIMARY KEY);
        CREATE TABLE writing_chapters (chapter_id INTEGER PRIMARY KEY);
        CREATE TABLE writing_chapter_generation_rounds (
            generation_round_id INTEGER PRIMARY KEY
        );
        CREATE TABLE writing_chapter_candidate_branch_versions (
            branch_version_id INTEGER PRIMARY KEY
        );
        CREATE TABLE writing_chapter_snapshots (snapshot_id INTEGER PRIMARY KEY);
        """
    )
    return conn


def test_migration_creates_accept_gate_tables_idempotently() -> None:
    conn = _legacy_db()
    assert _MODULE.migrate(conn) is True
    tables = {
        row[0]
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    assert set(_MODULE.TABLES) <= tables
    assert _MODULE.migrate(conn) is False
    evidence_columns = {
        row[1]
        for row in conn.execute("PRAGMA table_info(writing_chapter_accept_gate_evidence)")
    }
    assert {
        "evidence_id",
        "branch_version_id",
        "branch_content_hash",
        "gate_type",
        "attempt",
        "passed",
        "predecessor_heads_hash",
    } <= evidence_columns


def test_migration_dry_run_does_not_create_tables() -> None:
    conn = _legacy_db()
    assert _MODULE.migrate(conn, dry_run=True) is True
    tables = {
        row[0]
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    assert not (set(_MODULE.TABLES) & tables)
