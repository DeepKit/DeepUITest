#!/usr/bin/env python3
"""Idempotently add the Scene repair-task audit table to an existing Ink DB."""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

TABLE = "writing_scene_repair_tasks"

_CREATE_SQL = f"""
CREATE TABLE {TABLE} (
    repair_task_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    scene_id INTEGER NOT NULL,
    branch_version_id INTEGER NOT NULL,
    source_revision_id INTEGER,
    scene_contract_id INTEGER NOT NULL,
    issue TEXT NOT NULL CHECK (length(trim(issue)) > 0),
    status TEXT NOT NULL CHECK (status IN (
        'planned', 'running', 'completed', 'failed', 'cancelled'
    )),
    created_by TEXT NOT NULL,
    created_at TEXT NOT NULL,
    completed_at TEXT,
    FOREIGN KEY (scene_id) REFERENCES writing_scenes(scene_id) ON DELETE CASCADE,
    FOREIGN KEY (branch_version_id)
        REFERENCES writing_chapter_candidate_branch_versions(branch_version_id),
    FOREIGN KEY (source_revision_id) REFERENCES writing_scene_revisions(scene_revision_id),
    FOREIGN KEY (scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
)
"""


def table_exists(conn: sqlite3.Connection) -> bool:
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (TABLE,)
    ).fetchone() is not None


def migrate(conn: sqlite3.Connection, *, dry_run: bool = False) -> bool:
    if table_exists(conn) or dry_run:
        return False
    with conn:
        conn.execute(_CREATE_SQL)
        conn.execute(
            f"CREATE INDEX idx_scene_repair_tasks_scope "
            f"ON {TABLE}(project_id, chapter_id, scene_id, status)"
        )
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("db", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if not args.db.exists():
        print(f"[ERR] database not found: {args.db}", file=sys.stderr)
        return 2
    conn = sqlite3.connect(str(args.db))
    try:
        if table_exists(conn):
            print(f"[OK] {TABLE} already exists.")
            return 0
        if args.dry_run:
            print(f"[DRY-RUN] would create {TABLE}.")
            return 0
        migrate(conn)
        if not table_exists(conn):
            print("[ERR] table verification failed.", file=sys.stderr)
            return 4
        print(f"[DONE] created {TABLE}; legacy revisions were not rewritten.")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
