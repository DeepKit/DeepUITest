from __future__ import annotations

import pytest

from ink.database import connect, transaction
from ink.schema import project_root
from factories import NOW


def test_postgres_rls_boundary_doc_captures_required_adapter_contracts() -> None:
    doc = (project_root() / "docs" / "postgresql-rls-adapter-boundary.md").read_text(encoding="utf-8")

    for required in [
        "`connect(...)` returns rows addressable by column name",
        "`transaction(conn)` commits on normal exit and rolls back on exception",
        "auth context",
        "RLS denies cross-project reads and writes",
        "pg_advisory_xact_lock",
        "No business module should contain PostgreSQL-only SQL",
    ]:
        assert required in doc


def test_database_boundary_mapping_rows_and_transaction_semantics() -> None:
    conn = connect(initialize=True)

    with transaction(conn):
        _insert_project(conn, 1, "committed")

    row = conn.execute("SELECT code FROM writing_projects WHERE project_id = 1").fetchone()
    assert row["code"] == "committed"

    with pytest.raises(RuntimeError):
        with transaction(conn):
            _insert_project(conn, 2, "rolled-back")
            raise RuntimeError("force rollback")

    assert conn.execute("SELECT count(*) FROM writing_projects WHERE project_id = 2").fetchone()[0] == 0


def _insert_project(conn, project_id: int, code: str) -> None:
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (?, ?, ?, '["writer-a","writer-b","writer-c"]',
                '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
        """,
        (project_id, code, code.title(), NOW),
    )

