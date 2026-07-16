#!/usr/bin/env python3
"""幂等迁移：给 writing_projects 补 suspense_decay_floor 列（章级悬疑衰减回炉线）。

背景见 sql/migrations/2026-07-09_suspense_decay_floor.sql。
SQLite 的 ALTER TABLE ADD COLUMN 不支持 IF NOT EXISTS，重复 ADD 会报
duplicate column error，故用 PRAGMA table_info 探测后条件执行。

用法：
    python tools/migrate_suspense_decay_floor.py --db <path/to/inkflow.db>
    python tools/migrate_suspense_decay_floor.py --db <db> --dry-run   # 只探测不写
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

COL = "suspense_decay_floor"
TABLE = "writing_projects"
DEFAULT = 82


def column_exists(conn: sqlite3.Connection) -> bool:
    rows = conn.execute(f"PRAGMA table_info({TABLE})").fetchall()
    return any(r[1] == COL for r in rows)


def table_exists(conn: sqlite3.Connection) -> bool:
    row = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (TABLE,)
    ).fetchone()
    return row is not None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", required=True, type=Path, help="inkflow.db 路径")
    ap.add_argument("--dry-run", action="store_true", help="只探测不写")
    args = ap.parse_args()

    if not args.db.exists():
        print(f"[ERR] DB not found: {args.db}", file=sys.stderr)
        return 2

    conn = sqlite3.connect(str(args.db))
    try:
        if not table_exists(conn):
            print(f"[ERR] table {TABLE} not found in {args.db} — 库 schema 不符", file=sys.stderr)
            return 3
        if column_exists(conn):
            print(f"[OK] {TABLE}.{COL} 已存在，无需迁移。")
            return 0
        print(f"[INFO] {TABLE}.{COL} 缺失，将 ADD COLUMN ... DEFAULT {DEFAULT}。")
        if args.dry_run:
            print("[DRY-RUN] 不执行写入。")
            return 0
        conn.execute(
            f"ALTER TABLE {TABLE} ADD COLUMN {COL} INTEGER NOT NULL DEFAULT {DEFAULT}"
        )
        conn.commit()
        # 复查
        if column_exists(conn):
            print(f"[DONE] {TABLE}.{COL} 补列成功，默认值 {DEFAULT}。")
            return 0
        print("[ERR] ADD COLUMN 后复查仍无列，迁移失败。", file=sys.stderr)
        return 4
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
