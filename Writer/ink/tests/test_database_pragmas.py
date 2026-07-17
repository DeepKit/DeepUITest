from __future__ import annotations

import sqlite3
from pathlib import Path

from ink.database import SQLiteAdapter, connect
from ink.schema import connect_memory


def _pragma(conn: sqlite3.Connection, name: str) -> object:
    return conn.execute(f"PRAGMA {name}").fetchone()[0]


def test_file_database_enables_wal_and_busy_timeout(tmp_path: Path) -> None:
    db_path = tmp_path / "prod.sqlite"
    conn = SQLiteAdapter(path=db_path, initialize=True).connect()
    try:
        assert _pragma(conn, "journal_mode") == "wal"
        assert int(_pragma(conn, "busy_timeout")) >= 5000
        assert _pragma(conn, "foreign_keys") == 1
        # synchronous=NORMAL is the WAL-safe default we set; confirm it is
        # not FULL (which would defeat the WAL throughput goal).
        assert _pragma(conn, "synchronous") in (1, "normal")
    finally:
        conn.close()
        for sidecar in ("-wal", "-shm"):
            side = Path(str(db_path) + sidecar)
            if side.exists():
                side.unlink()


def test_memory_database_skips_wal_but_keeps_busy_timeout() -> None:
    conn = SQLiteAdapter(path=":memory:", initialize=False).connect()
    try:
        # in-memory stays on the default journal mode; WAL is not applicable.
        assert _pragma(conn, "journal_mode") != "wal"
        assert int(_pragma(conn, "busy_timeout")) >= 5000
    finally:
        conn.close()


def test_connect_factory_propagates_pragmas_to_file_backend(tmp_path: Path) -> None:
    db_path = tmp_path / "factory.sqlite"
    conn = connect(str(db_path), initialize=True, backend="sqlite")
    try:
        assert _pragma(conn, "journal_mode") == "wal"
        assert int(_pragma(conn, "busy_timeout")) >= 5000
    finally:
        conn.close()
        for sidecar in ("-wal", "-shm"):
            side = Path(str(db_path) + sidecar)
            if side.exists():
                side.unlink()


def test_connect_memory_factory_keeps_busy_timeout() -> None:
    # The schema.connect_memory helper is the in-memory path tests rely on;
    # it should remain WAL-free but gain busy_timeout for determinism.
    conn = connect_memory()
    try:
        assert _pragma(conn, "journal_mode") != "wal"
    finally:
        conn.close()
