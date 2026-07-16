#!/usr/bin/env python3
"""Idempotently add the chapter-level coherence score to an existing Ink DB.

Background: sql/migrations/2026-07-16_chapter_coherence.sql.
SQLite does not support portable ``ALTER TABLE ... ADD COLUMN IF NOT EXISTS``,
so this tool probes ``PRAGMA table_info`` before changing the database.
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

TABLE = "writing_chapter_reviews"
COLUMN = "chapter_coherence"


def table_exists(conn: sqlite3.Connection) -> bool:
    row = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        (TABLE,),
    ).fetchone()
    return row is not None


def column_exists(conn: sqlite3.Connection) -> bool:
    return any(row[1] == COLUMN for row in conn.execute(f"PRAGMA table_info({TABLE})"))


def migrate(conn: sqlite3.Connection, *, dry_run: bool = False) -> bool:
    """Add the nullable score column; return True only when schema changed."""
    if not table_exists(conn):
        raise RuntimeError(f"table {TABLE} not found")
    if column_exists(conn) or dry_run:
        return False
    conn.execute(
        f"ALTER TABLE {TABLE} ADD COLUMN {COLUMN} INTEGER "
        f"CHECK ({COLUMN} IS NULL OR {COLUMN} BETWEEN 0 AND 100)"
    )
    conn.commit()
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if not args.db.exists():
        print(f"[ERR] database not found: {args.db}", file=sys.stderr)
        return 2

    conn = sqlite3.connect(str(args.db))
    try:
        if not table_exists(conn):
            print(f"[ERR] table {TABLE} not found in {args.db}", file=sys.stderr)
            return 3
        if column_exists(conn):
            print(f"[OK] {TABLE}.{COLUMN} already exists.")
            return 0
        if args.dry_run:
            print(f"[DRY-RUN] would add nullable {TABLE}.{COLUMN}.")
            return 0
        migrate(conn)
        if not column_exists(conn):
            print("[ERR] column verification failed.", file=sys.stderr)
            return 4
        print(f"[DONE] added nullable {TABLE}.{COLUMN}; legacy rows remain NULL.")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
