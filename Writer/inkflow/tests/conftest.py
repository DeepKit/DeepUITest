"""Shared test fixtures for InkFlow."""

from __future__ import annotations

import tempfile
from pathlib import Path

import pytest

from inkflow.db import init_project_db, open_db


@pytest.fixture
def tmp_dir() -> Path:
    """临时目录，测试结束后自动清理"""
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as d:
        yield Path(d)


@pytest.fixture
def db_path(tmp_dir: Path) -> Path:
    """inkflow.db 的路径"""
    return tmp_dir / ".inkflow" / "inkflow.db"


@pytest.fixture
def db(tmp_dir: Path):
    """全新的 inkflow.db，已初始化 25 张表"""
    path = tmp_dir / ".inkflow" / "inkflow.db"
    conn = init_project_db(path)
    yield conn
    conn.close()


@pytest.fixture
def db_reopen(db_path: Path):
    """返回一个重新打开同一 DB 文件的函数"""
    def _reopen():
        conn = open_db(db_path)
        conn.row_factory = lambda cursor, row: dict(
            zip([col[0] for col in cursor.description], row)
        )
        return conn
    return _reopen


@pytest.fixture
def setup_run(db):
    """Set up project, session, meta-contract, and shots for a run."""
    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    db.execute(
        "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
        "VALUES ('s1', 'proj_01', 'run_01', 'active')"
    )
    db.execute(
        "INSERT INTO writing_meta_contract "
        "(meta_contract_id, project_id, status, layers_json, human_confirm_layer) "
        "VALUES ('mc1', 'proj_01', 'confirmed', '{}', 2)"
    )
    db.execute(
        "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
        "VALUES ('shot_01', 'proj_01', 'run_01', 'v01.c02', 1, 'pending')"
    )
    db.execute(
        "INSERT INTO writing_shot_contracts "
        "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
        "snapshot_hash, must_land_json, anti_write_json, contract_json) "
        "VALUES ('c1', 'proj_01', 'run_01', 'shot_01', 'v01.c02', 'draft', 'h1', '{}', '{}', '{}')"
    )
    db.commit()
    return db