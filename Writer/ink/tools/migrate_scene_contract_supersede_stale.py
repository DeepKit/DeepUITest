#!/usr/bin/env python3
"""Idempotently add Scene-first stale annotation tables to an existing Ink DB."""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

TABLES = (
    "writing_scene_revision_stale_marks",
    "writing_branch_version_stale_marks",
    "writing_chapter_snapshot_stale_marks",
)

_CREATE_SQL = """
CREATE TABLE writing_scene_revision_stale_marks (
    scene_revision_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER NOT NULL,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (scene_revision_id) REFERENCES writing_scene_revisions(scene_revision_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_scene_revision_stale_source
ON writing_scene_revision_stale_marks(source_scene_contract_id);
CREATE TABLE writing_branch_version_stale_marks (
    branch_version_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER NOT NULL,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (branch_version_id) REFERENCES writing_chapter_candidate_branch_versions(branch_version_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_branch_version_stale_source
ON writing_branch_version_stale_marks(source_scene_contract_id);
CREATE TABLE writing_chapter_snapshot_stale_marks (
    snapshot_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER NOT NULL,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (snapshot_id) REFERENCES writing_chapter_snapshots(snapshot_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_chapter_snapshot_stale_source
ON writing_chapter_snapshot_stale_marks(source_scene_contract_id);
"""


def table_exists(conn: sqlite3.Connection, table: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)
    ).fetchone() is not None


def migrate(conn: sqlite3.Connection, *, dry_run: bool = False) -> bool:
    existing = [table for table in TABLES if table_exists(conn, table)]
    if len(existing) == len(TABLES):
        return False
    if existing:
        raise RuntimeError(f"partial stale migration detected: {existing}")
    if dry_run:
        return False
    conn.executescript(_CREATE_SQL)
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
        changed = migrate(conn, dry_run=args.dry_run)
        if args.dry_run:
            print("[DRY-RUN] would add Scene-first stale annotation tables.")
        elif changed:
            print("[DONE] added Scene-first stale annotation tables; historical data unchanged.")
        else:
            print("[OK] Scene-first stale annotation tables already exist.")
        return 0
    except RuntimeError as exc:
        print(f"[ERR] {exc}", file=sys.stderr)
        return 4
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
