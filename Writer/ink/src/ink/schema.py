from __future__ import annotations

import hashlib
import re
import sqlite3
from pathlib import Path

from ink.time import now_utc_iso


def project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def schema_path() -> Path:
    return project_root() / "sql" / "schema.sql"


def load_schema_sql() -> str:
    return schema_path().read_text(encoding="utf-8")


def connect_memory() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.execute("PRAGMA foreign_keys=ON")
    # busy_timeout is harmless on in-memory DBs and keeps test parity with
    # the file-backend contract (PRAGMA §6); WAL is omitted (not applicable).
    conn.execute("PRAGMA busy_timeout=5000")
    return conn


def initialize_schema(conn: sqlite3.Connection, schema_sql: str | None = None) -> sqlite3.Connection:
    conn.executescript(schema_sql if schema_sql is not None else load_schema_sql())
    return conn


_MIGRATION_NAME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}_[a-z0-9_]+\.sql$")


def migrations_dir() -> Path:
    return project_root() / "sql" / "migrations"


def list_migration_files() -> list[Path]:
    """按字典序返回合法迁移文件路径。文件名须匹配 YYYY-MM-DD_name.sql。"""
    if not migrations_dir().is_dir():
        return []
    return sorted(
        p
        for p in migrations_dir().glob("*.sql")
        if _MIGRATION_NAME_RE.match(p.name)
    )


def _checksum(sql_text: str) -> str:
    return hashlib.sha256(sql_text.encode("utf-8")).hexdigest()


def _ensure_migrations_table(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            migration_name TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL,
            checksum TEXT NOT NULL
        )
        """
    )
    conn.commit()


def applied_migrations(conn: sqlite3.Connection) -> dict[str, str]:
    """返回 {migration_name: checksum}。自动建表(若不存在)。"""
    _ensure_migrations_table(conn)
    rows = conn.execute(
        "SELECT migration_name, checksum FROM schema_migrations"
    ).fetchall()
    return {str(name): str(checksum) for name, checksum in rows}


def mark_all_migrations_applied(conn: sqlite3.Connection) -> list[str]:
    """全新库专用:base schema.sql 已含所有迁移对应的对象,把现有迁移全部
    标记为已应用,跳过实际执行(避免重复 CREATE 已存在的表)。

    若某迁移已记录,校验 checksum 一致;不一致则抛错(迁移文件被改且库已应用)。
    """
    applied = applied_migrations(conn)
    now = now_utc_iso()
    marked: list[str] = []
    for path in list_migration_files():
        name = path.name
        sql_text = path.read_text(encoding="utf-8")
        checksum = _checksum(sql_text)
        if name in applied:
            if applied[name] != checksum:
                raise RuntimeError(
                    f"migration {name} checksum mismatch: file changed after apply"
                )
            continue
        conn.execute(
            "INSERT INTO schema_migrations (migration_name, applied_at, checksum) VALUES (?, ?, ?)",
            (name, now, checksum),
        )
        marked.append(name)
    conn.commit()
    return marked


def migrate_db(conn: sqlite3.Connection) -> list[str]:
    """对已存在的库应用未跑的迁移,返回本次应用的迁移名列表。

    迁移按文件名字典序应用;每个迁移在独立事务内执行并记录到 schema_migrations。
    迁移文件须幂等(IF NOT EXISTS)以支持崩溃重放。
    """
    applied = applied_migrations(conn)
    now = now_utc_iso()
    applied_now: list[str] = []
    for path in list_migration_files():
        name = path.name
        sql_text = path.read_text(encoding="utf-8")
        checksum = _checksum(sql_text)
        if name in applied:
            if applied[name] != checksum:
                raise RuntimeError(
                    f"migration {name} checksum mismatch: file changed after apply"
                )
            continue
        try:
            conn.execute("BEGIN")
            conn.executescript(sql_text)
            conn.execute(
                "INSERT INTO schema_migrations (migration_name, applied_at, checksum) VALUES (?, ?, ?)",
                (name, now, checksum),
            )
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        applied_now.append(name)
    return applied_now
