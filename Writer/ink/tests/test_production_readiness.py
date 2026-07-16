from __future__ import annotations

import sqlite3

from factories import NOW, make_schema_db
from ink.production_readiness import backup_sqlite_database, inspect_personal_production


def _seed_project(conn: sqlite3.Connection, *, provider: str) -> None:
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool,
             max_calls_per_shot, max_total_llm_calls, require_ethics_review, created_at)
        VALUES (1, 'prod', 'Production',
                '["w1","w2","w3"]', '["j1","j2","j3","j4","j5"]',
                64, 96, 1, ?)
        """,
        (NOW,),
    )
    conn.execute(
        """
        INSERT INTO writing_model_role_configs
            (project_id, call_type, tier, model_name, provider, api_key_env,
             created_at, updated_at)
        VALUES (1, 'draft', 'primary', 'real-model', ?, 'LOCAL_PROXY_KEY',
                ?, ?)
        """,
        (provider, NOW, NOW),
    )


def test_personal_production_doctor_passes_real_provider_config() -> None:
    conn = make_schema_db()
    _seed_project(conn, provider="openai-compatible")
    report = inspect_personal_production(conn, 1)
    assert report["ready_for_personal_production"] is True
    assert report["blocking_failures"] == []


def test_personal_production_doctor_blocks_mock_route() -> None:
    conn = make_schema_db()
    _seed_project(conn, provider="mock")
    report = inspect_personal_production(conn, 1)
    assert report["ready_for_personal_production"] is False
    assert "real_model_routes" in report["blocking_failures"]
    assert "no_mock_routes" in report["blocking_failures"]


def test_sqlite_backup_is_independent_and_integrity_checked(tmp_path) -> None:
    source = tmp_path / "production.db"
    conn = sqlite3.connect(source)
    conn.execute("CREATE TABLE sample(value TEXT)")
    conn.execute("INSERT INTO sample VALUES ('before')")
    conn.commit()
    conn.close()
    destination = tmp_path / "backups" / "production-copy.db"

    result = backup_sqlite_database(source, destination)

    assert result["integrity_check"] == "ok"
    backup = sqlite3.connect(destination)
    assert backup.execute("SELECT value FROM sample").fetchone()[0] == "before"
    backup.close()
