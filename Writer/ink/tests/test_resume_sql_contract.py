from __future__ import annotations

from ink.core.resume_sql import SELECT_SESSION_SHOTS_SQL, load_session_shots
from factories import insert_minimal_draft, make_schema_db


def test_resume_sql_filters_session_through_runs_not_shots() -> None:
    normalized = " ".join(SELECT_SESSION_SHOTS_SQL.split()).lower()

    assert "join writing_runs r on r.run_id = s.run_id" in normalized
    assert "where r.session_id = ?" in normalized
    assert "s.session_id" not in normalized


def test_load_session_shots_uses_run_session_binding() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)

    rows = load_session_shots(conn, int(ids["session_id"]))

    assert [(row[0], row[1], row[2]) for row in rows] == [(ids["shot_id"], ids["run_id"], "pending")]

