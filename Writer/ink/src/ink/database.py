from __future__ import annotations

import sqlite3
from collections.abc import Iterator, Mapping, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

from ink.schema import initialize_schema


@runtime_checkable
class CursorLike(Protocol):
    rowcount: int
    lastrowid: int | None
    description: Sequence[Sequence[object]] | None

    def fetchone(self) -> Any: ...

    def fetchall(self) -> list[Any]: ...


@runtime_checkable
class ConnectionLike(Protocol):
    def execute(self, sql: str, params: Sequence[object] = ()) -> CursorLike: ...

    def executemany(self, sql: str, params: Sequence[Sequence[object]]) -> CursorLike: ...

    def commit(self) -> None: ...

    def rollback(self) -> None: ...

    def close(self) -> None: ...


@dataclass(frozen=True)
class AuthContext:
    """Transaction-local identity consumed by PostgreSQL RLS policies."""

    project_id: int | None = None
    session_id: int | None = None
    actor_id: str | None = None


class DBAdapter(Protocol):
    backend: str

    def connect(self) -> ConnectionLike: ...


@dataclass(frozen=True)
class SQLiteAdapter:
    path: str | Path = ":memory:"
    initialize: bool = False
    backend: str = "sqlite"

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys=ON")
        if self.initialize:
            initialize_schema(conn)
        return conn


class MappingRow(Mapping[str, object]):
    """Driver-independent row supporting both row['name'] and row[0]."""

    def __init__(self, columns: Sequence[str], values: Sequence[object]) -> None:
        self._columns = tuple(columns)
        self._values = tuple(values)
        self._mapping = dict(zip(self._columns, self._values, strict=True))

    def __getitem__(self, key: str | int) -> object:
        if isinstance(key, int):
            return self._values[key]
        return self._mapping[key]

    def __iter__(self) -> Iterator[str]:
        return iter(self._columns)

    def __len__(self) -> int:
        return len(self._columns)


class PostgreSQLCursor:
    def __init__(
        self,
        cursor: Any,
        *,
        lastrowid: int | None = None,
    ) -> None:
        self._cursor = cursor
        self.lastrowid = lastrowid

    @property
    def rowcount(self) -> int:
        return int(self._cursor.rowcount)

    @property
    def description(self) -> Any:
        return self._cursor.description

    def fetchone(self) -> MappingRow | None:
        row = self._cursor.fetchone()
        return None if row is None else self._row(row)

    def fetchall(self) -> list[MappingRow]:
        return [self._row(row) for row in self._cursor.fetchall()]

    def __iter__(self) -> Iterator[MappingRow]:
        for row in self._cursor:
            yield self._row(row)

    def _row(self, row: object) -> MappingRow:
        if isinstance(row, Mapping):
            columns = tuple(str(column) for column in row.keys())
            return MappingRow(columns, tuple(row.values()))
        description = self._cursor.description or ()
        columns = tuple(_column_name(column) for column in description)
        return MappingRow(columns, tuple(row))  # type: ignore[arg-type]


class PostgreSQLConnection:
    """Small DB-API compatibility wrapper; no ORM or business SQL lives here."""

    backend = "postgresql"

    def __init__(self, raw_connection: Any) -> None:
        self.raw_connection = raw_connection

    def execute(self, sql: str, params: Sequence[object] = ()) -> PostgreSQLCursor:
        cursor = self.raw_connection.cursor()
        cursor.execute(_qmark_to_pyformat(sql), tuple(params))
        lastrowid = self._last_insert_id(sql)
        return PostgreSQLCursor(cursor, lastrowid=lastrowid)

    def executemany(
        self,
        sql: str,
        params: Sequence[Sequence[object]],
    ) -> PostgreSQLCursor:
        cursor = self.raw_connection.cursor()
        cursor.executemany(_qmark_to_pyformat(sql), [tuple(item) for item in params])
        return PostgreSQLCursor(cursor)

    def commit(self) -> None:
        self.raw_connection.commit()

    def rollback(self) -> None:
        self.raw_connection.rollback()

    def close(self) -> None:
        self.raw_connection.close()

    def _last_insert_id(self, sql: str) -> int | None:
        if not sql.lstrip().upper().startswith("INSERT "):
            return None
        cursor = self.raw_connection.cursor()
        cursor.execute("SELECT LASTVAL()")
        row = cursor.fetchone()
        return None if row is None else int(row[0])


@dataclass(frozen=True)
class PostgreSQLAdapter:
    dsn: str
    connect_kwargs: Mapping[str, object] | None = None
    driver: Any = None
    backend: str = "postgresql"

    def connect(self) -> PostgreSQLConnection:
        driver = self.driver
        if driver is None:
            try:
                import psycopg as driver  # type: ignore[import-not-found,no-redef]
            except ImportError as exc:
                raise RuntimeError(
                    "PostgreSQL support requires the optional 'psycopg' package"
                ) from exc
        raw = driver.connect(self.dsn, **dict(self.connect_kwargs or {}))
        return PostgreSQLConnection(raw)


def connect(
    path: str | Path = ":memory:",
    *,
    initialize: bool = False,
    backend: str = "sqlite",
    dsn: str | None = None,
    driver: Any = None,
) -> ConnectionLike:
    """Open a supported database while preserving the historic SQLite API."""

    normalized = backend.strip().lower()
    if normalized == "sqlite":
        return SQLiteAdapter(path=path, initialize=initialize).connect()
    if normalized in {"postgres", "postgresql"}:
        if initialize:
            raise ValueError("PostgreSQL schema initialization requires an explicit migration")
        pg_dsn = dsn or (str(path) if str(path) != ":memory:" else "")
        if not pg_dsn:
            raise ValueError("PostgreSQL backend requires a DSN")
        return PostgreSQLAdapter(pg_dsn, driver=driver).connect()
    raise ValueError(f"unsupported database backend: {backend}")


@contextmanager
def transaction(
    conn: ConnectionLike,
    *,
    auth: AuthContext | None = None,
    shot_id: str | None = None,
    run_id: int | None = None,
) -> Iterator[None]:
    try:
        conn.execute("BEGIN")
        if _is_postgresql(conn):
            _set_postgresql_auth_context(conn, auth or AuthContext())
            if (shot_id is None) != (run_id is None):
                raise ValueError("shot_id and run_id must be supplied together")
            if shot_id is not None and run_id is not None:
                acquire_shot_lock(conn, shot_id, run_id)
        yield
    except Exception:
        conn.rollback()
        raise
    else:
        conn.commit()


def acquire_shot_lock(conn: ConnectionLike, shot_id: str, run_id: int) -> None:
    if not _is_postgresql(conn):
        return
    conn.execute(
        "SELECT pg_advisory_xact_lock(hashtext(? || ':' || ?::text))",
        (shot_id, run_id),
    )


def _set_postgresql_auth_context(conn: ConnectionLike, auth: AuthContext) -> None:
    values = {
        "ink.project_id": auth.project_id,
        "ink.session_id": auth.session_id,
        "ink.actor_id": auth.actor_id,
    }
    for setting, value in values.items():
        conn.execute(
            "SELECT set_config(?, ?, true)",
            (setting, "" if value is None else str(value)),
        )


def _is_postgresql(conn: ConnectionLike) -> bool:
    return getattr(conn, "backend", "sqlite") == "postgresql"


def _column_name(column: object) -> str:
    name = getattr(column, "name", None)
    if name is not None:
        return str(name)
    return str(column[0])  # type: ignore[index]


def _qmark_to_pyformat(sql: str) -> str:
    """Translate SQLite placeholders without touching literals or SQL comments."""

    output: list[str] = []
    index = 0
    state = "normal"
    while index < len(sql):
        char = sql[index]
        next_char = sql[index + 1] if index + 1 < len(sql) else ""
        if state == "normal":
            if char == "'":
                state = "single"
            elif char == '"':
                state = "double"
            elif char == "-" and next_char == "-":
                state = "line_comment"
            elif char == "/" and next_char == "*":
                state = "block_comment"
            elif char == "?":
                output.append("%s")
                index += 1
                continue
        elif state == "single":
            if char == "'" and next_char == "'":
                output.extend((char, next_char))
                index += 2
                continue
            if char == "'":
                state = "normal"
        elif state == "double":
            if char == '"' and next_char == '"':
                output.extend((char, next_char))
                index += 2
                continue
            if char == '"':
                state = "normal"
        elif state == "line_comment":
            if char == "\n":
                state = "normal"
        elif state == "block_comment" and char == "*" and next_char == "/":
            output.extend((char, next_char))
            state = "normal"
            index += 2
            continue
        output.append(char)
        index += 1
    return "".join(output)
