from __future__ import annotations

import sqlite3
from pathlib import Path


def project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def schema_path() -> Path:
    return project_root() / "sql" / "schema.sql"


def load_schema_sql() -> str:
    return schema_path().read_text(encoding="utf-8")


def connect_memory() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def initialize_schema(conn: sqlite3.Connection, schema_sql: str | None = None) -> sqlite3.Connection:
    conn.executescript(schema_sql if schema_sql is not None else load_schema_sql())
    return conn
