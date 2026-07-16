from __future__ import annotations

import pytest

from ink.database import (
    AuthContext,
    MappingRow,
    PostgreSQLAdapter,
    PostgreSQLConnection,
    _qmark_to_pyformat,
    transaction,
)


class FakeCursor:
    def __init__(self, connection: "FakeRawConnection") -> None:
        self.connection = connection
        self.rowcount = 1
        self.description = None
        self.rows: list[tuple[object, ...]] = []

    def execute(self, sql: str, params: tuple[object, ...] = ()) -> None:
        self.connection.statements.append((sql, params))
        if sql == "SELECT LASTVAL()":
            self.rows = [(self.connection.lastval,)]
            self.description = [("lastval",)]

    def executemany(self, sql: str, params: list[tuple[object, ...]]) -> None:
        self.connection.statements.append((sql, tuple(params)))
        self.rowcount = len(params)

    def fetchone(self):
        return self.rows.pop(0) if self.rows else None

    def fetchall(self):
        rows, self.rows = self.rows, []
        return rows

    def __iter__(self):
        return iter(self.rows)


class FakeRawConnection:
    def __init__(self) -> None:
        self.statements: list[tuple[str, object]] = []
        self.lastval = 41
        self.commits = 0
        self.rollbacks = 0
        self.closed = False

    def cursor(self) -> FakeCursor:
        return FakeCursor(self)

    def commit(self) -> None:
        self.commits += 1

    def rollback(self) -> None:
        self.rollbacks += 1

    def close(self) -> None:
        self.closed = True


class FakeDriver:
    def __init__(self, raw: FakeRawConnection) -> None:
        self.raw = raw
        self.calls: list[tuple[str, dict[str, object]]] = []

    def connect(self, dsn: str, **kwargs: object) -> FakeRawConnection:
        self.calls.append((dsn, kwargs))
        return self.raw


def test_qmark_translation_skips_literals_identifiers_and_comments() -> None:
    sql = """SELECT ?, '?', "?", value -- ?
             FROM sample /* ? */ WHERE note = 'it''s ?' AND id = ?"""
    translated = _qmark_to_pyformat(sql)
    assert translated.count("%s") == 2
    assert "'?'" in translated
    assert '"?"' in translated
    assert "-- ?" in translated
    assert "/* ? */" in translated


def test_mapping_row_supports_names_indexes_and_dict_conversion() -> None:
    row = MappingRow(("project_id", "code"), (7, "novel"))
    assert row["code"] == "novel"
    assert row[0] == 7
    assert dict(row) == {"project_id": 7, "code": "novel"}


def test_adapter_uses_injected_driver_and_preserves_lastrowid() -> None:
    raw = FakeRawConnection()
    driver = FakeDriver(raw)
    conn = PostgreSQLAdapter("postgresql://example/ink", {"application_name": "ink"}, driver).connect()

    cursor = conn.execute("INSERT INTO sample(value) VALUES (?)", ("x",))

    assert driver.calls == [("postgresql://example/ink", {"application_name": "ink"})]
    assert raw.statements[0] == ("INSERT INTO sample(value) VALUES (%s)", ("x",))
    assert cursor.lastrowid == 41


def test_transaction_sets_local_rls_context_and_advisory_lock_then_commits() -> None:
    raw = FakeRawConnection()
    conn = PostgreSQLConnection(raw)

    with transaction(
        conn,
        auth=AuthContext(project_id=9, session_id=12, actor_id="operator"),
        shot_id="c03-s01",
        run_id=4,
    ):
        conn.execute("SELECT code FROM writing_projects WHERE project_id = ?", (9,))

    statements = raw.statements
    assert statements[0] == ("BEGIN", ())
    assert ("SELECT set_config(%s, %s, true)", ("ink.project_id", "9")) in statements
    assert ("SELECT set_config(%s, %s, true)", ("ink.session_id", "12")) in statements
    assert ("SELECT set_config(%s, %s, true)", ("ink.actor_id", "operator")) in statements
    assert (
        "SELECT pg_advisory_xact_lock(hashtext(%s || ':' || %s::text))",
        ("c03-s01", 4),
    ) in statements
    assert raw.commits == 1
    assert raw.rollbacks == 0


def test_transaction_rolls_back_and_rejects_partial_lock_identity() -> None:
    raw = FakeRawConnection()
    conn = PostgreSQLConnection(raw)

    with pytest.raises(ValueError, match="supplied together"):
        with transaction(conn, shot_id="c03-s01"):
            pass

    assert raw.commits == 0
    assert raw.rollbacks == 1


def test_non_insert_does_not_query_lastval() -> None:
    raw = FakeRawConnection()
    conn = PostgreSQLConnection(raw)
    conn.execute("UPDATE sample SET value = ? WHERE id = ?", ("x", 1))
    assert raw.statements == [("UPDATE sample SET value = %s WHERE id = %s", ("x", 1))]
