#!/usr/bin/env python3
"""Idempotently bring an existing Ink DB up to the Fact-lifecycle schema.

Covers:
- writing_fact_anchors: add scene_id/chapter_id/version_hash/
  superseded_by_anchor_id/supersede_reason; widen status to include
  'superseded'; repoint revision_id FK to writing_scene_revisions.
- writing_fact_proposals: add reviewed_by/reviewed_at/reviewer_model/
  review_evidence_json/superseded_by_proposal_id.
- writing_guidance_cards: add scope/cooldown_until/use_count/max_uses/
  applied_at/applied_to_chapter_id.
- writing_contract_fact_bindings: create the Contract↔Fact binding table.
- stale_marks trio: rebuild with nullable replacement_scene_contract_id
  (Fact-supersede marks carry NULL replacement).

SQLite cannot ALTER a column's NOT NULL/FK in place, so the stale_marks
trio is rebuilt via the _new → copy → drop → rename idiom. New DBs already
have the current definitions from schema.sql; this tool is for archival
read-only databases only (the production rewrite uses a fresh DB).
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

_ANCHOR_ADD_COLUMNS = (
    ("scene_id", "INTEGER"),
    ("chapter_id", "INTEGER"),
    ("version_hash", "TEXT NOT NULL DEFAULT ''"),
    ("superseded_by_anchor_id", "INTEGER"),
    ("supersede_reason", "TEXT"),
)

_PROPOSAL_ADD_COLUMNS = (
    ("reviewed_by", "TEXT"),
    ("reviewed_at", "TEXT"),
    ("reviewer_model", "TEXT"),
    ("review_evidence_json", "TEXT"),
    ("superseded_by_proposal_id", "INTEGER"),
)

_GUIDANCE_ADD_COLUMNS = (
    ("scope", "TEXT NOT NULL DEFAULT 'scene'"),
    ("cooldown_until", "TEXT"),
    ("use_count", "INTEGER NOT NULL DEFAULT 0"),
    ("max_uses", "INTEGER"),
    ("applied_at", "TEXT"),
    ("applied_to_chapter_id", "INTEGER"),
)

_BINDINGS_CREATE_SQL = """
CREATE TABLE IF NOT EXISTS writing_contract_fact_bindings (
    binding_id INTEGER PRIMARY KEY,
    scene_contract_id INTEGER NOT NULL,
    fact_anchor_id INTEGER NOT NULL,
    fact_version_hash TEXT NOT NULL,
    binding_type TEXT NOT NULL CHECK (binding_type IN ('required','forbidden','context')),
    created_at TEXT NOT NULL,
    UNIQUE (scene_contract_id, fact_anchor_id),
    FOREIGN KEY (scene_contract_id)
        REFERENCES writing_scene_contracts(scene_contract_id) ON DELETE CASCADE,
    FOREIGN KEY (fact_anchor_id)
        REFERENCES writing_fact_anchors(anchor_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_contract_fact_bindings_contract
    ON writing_contract_fact_bindings(scene_contract_id);
CREATE INDEX IF NOT EXISTS idx_contract_fact_bindings_anchor
    ON writing_contract_fact_bindings(fact_anchor_id);
"""

_STALE_REBUILD = {
    "writing_scene_revision_stale_marks": (
        """
CREATE TABLE {name} (
    scene_revision_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (scene_revision_id) REFERENCES writing_scene_revisions(scene_revision_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_scene_revision_stale_source ON {name}(source_scene_contract_id);
""",
        ("scene_revision_id", "source_scene_contract_id",
         "replacement_scene_contract_id", "stale_reason", "marked_at"),
    ),
    "writing_branch_version_stale_marks": (
        """
CREATE TABLE {name} (
    branch_version_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (branch_version_id) REFERENCES writing_chapter_candidate_branch_versions(branch_version_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_branch_version_stale_source ON {name}(source_scene_contract_id);
""",
        ("branch_version_id", "source_scene_contract_id",
         "replacement_scene_contract_id", "stale_reason", "marked_at"),
    ),
    "writing_chapter_snapshot_stale_marks": (
        """
CREATE TABLE {name} (
    snapshot_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (snapshot_id) REFERENCES writing_chapter_snapshots(snapshot_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_chapter_snapshot_stale_source ON {name}(source_scene_contract_id);
""",
        ("snapshot_id", "source_scene_contract_id",
         "replacement_scene_contract_id", "stale_reason", "marked_at"),
    ),
}


def _column_exists(conn: sqlite3.Connection, table: str, column: str) -> bool:
    return any(row[1] == column for row in conn.execute(f"PRAGMA table_info({table})"))


def _table_exists(conn: sqlite3.Connection, table: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)
    ).fetchone() is not None


def _add_columns(conn: sqlite3.Connection, table: str, columns) -> bool:
    changed = False
    for name, decl in columns:
        if _column_exists(conn, table, name):
            continue
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {decl}")
        changed = True
    return changed


def _rebuild_stale_table(conn: sqlite3.Connection, table: str, dry_run: bool) -> bool:
    if not _table_exists(conn, table):
        return False
    # Already nullable? nothing to do.
    col = next(
        row for row in conn.execute(f"PRAGMA table_info({table})")
        if row[1] == "replacement_scene_contract_id"
    )
    if col[3] == 0:  # notnull flag = 0 → already nullable
        return False
    if dry_run:
        return True
    create_sql, col_list = _STALE_REBUILD[table]
    cols_csv = ", ".join(col_list)
    tmp = f"{table}__fact_migration_tmp"
    conn.execute(f"DROP TABLE IF EXISTS {tmp}")
    conn.executescript(create_sql.format(name=tmp))
    conn.execute(f"INSERT INTO {tmp} ({cols_csv}) SELECT {cols_csv} FROM {table}")
    conn.execute(f"DROP TABLE {table}")
    conn.execute(f"ALTER TABLE {tmp} RENAME TO {table}")
    return True


def migrate(conn: sqlite3.Connection, *, dry_run: bool = False) -> bool:
    changed = False
    if _table_exists(conn, "writing_fact_anchors"):
        changed |= _add_columns(conn, "writing_fact_anchors", _ANCHOR_ADD_COLUMNS)
    if _table_exists(conn, "writing_fact_proposals"):
        changed |= _add_columns(conn, "writing_fact_proposals", _PROPOSAL_ADD_COLUMNS)
    if _table_exists(conn, "writing_guidance_cards"):
        changed |= _add_columns(conn, "writing_guidance_cards", _GUIDANCE_ADD_COLUMNS)
    if not _table_exists(conn, "writing_contract_fact_bindings"):
        if not dry_run:
            conn.executescript(_BINDINGS_CREATE_SQL)
        changed = True
    for table in _STALE_REBUILD:
        changed |= _rebuild_stale_table(conn, table, dry_run)
    return changed


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
        conn.execute("PRAGMA foreign_keys=ON")
        changed = migrate(conn, dry_run=args.dry_run)
        if not dry_run and changed:
            conn.commit()
        if args.dry_run:
            print("[DRY-RUN] would apply Fact-lifecycle schema changes.")
        elif changed:
            print("[DONE] applied Fact-lifecycle schema changes; historical data preserved.")
        else:
            print("[OK] Fact-lifecycle schema already up to date.")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
