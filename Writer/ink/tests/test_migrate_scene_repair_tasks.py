from __future__ import annotations

import importlib.util
import sqlite3
from pathlib import Path


_TOOL = Path(__file__).resolve().parents[1] / "tools" / "migrate_scene_repair_tasks.py"
_SPEC = importlib.util.spec_from_file_location("migrate_scene_repair_tasks", _TOOL)
assert _SPEC is not None and _SPEC.loader is not None
_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MODULE)


def _legacy_db() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.executescript(
        """
        PRAGMA foreign_keys = ON;
        CREATE TABLE writing_scenes (scene_id INTEGER PRIMARY KEY);
        CREATE TABLE writing_scene_revisions (scene_revision_id INTEGER PRIMARY KEY);
        CREATE TABLE writing_scene_contracts (scene_contract_id INTEGER PRIMARY KEY);
        CREATE TABLE writing_chapter_candidate_branch_versions (
            branch_version_id INTEGER PRIMARY KEY
        );
        """
    )
    return conn


def test_migration_creates_repair_task_table_idempotently() -> None:
    conn = _legacy_db()
    assert _MODULE.migrate(conn) is True
    assert _MODULE.table_exists(conn)
    assert _MODULE.migrate(conn) is False
    columns = {row[1] for row in conn.execute("PRAGMA table_info(writing_scene_repair_tasks)")}
    assert {"repair_task_id", "scene_id", "branch_version_id", "status"} <= columns


def test_migration_dry_run_does_not_create_table() -> None:
    conn = _legacy_db()
    assert _MODULE.migrate(conn, dry_run=True) is False
    assert not _MODULE.table_exists(conn)
