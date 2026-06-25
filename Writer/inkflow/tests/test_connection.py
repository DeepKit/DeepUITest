"""Test database connection and PRAGMA settings."""

from __future__ import annotations

import sqlite3
from pathlib import Path

from inkflow.db import open_db, init_project_db, backup_project_db


class TestOpenDb:
    """open_db() 基础连接"""

    def test_creates_file(self, tmp_dir: Path):
        """open_db 应创建数据库文件"""
        path = tmp_dir / "test.db"
        conn = open_db(path)
        conn.close()
        assert path.exists()

    def test_wal_mode(self, tmp_dir: Path):
        """WAL 模式默认启用"""
        path = tmp_dir / "test.db"
        conn = open_db(path)
        row = conn.execute("PRAGMA journal_mode").fetchone()
        assert row[0].upper() == "WAL"
        conn.close()

    def test_foreign_keys_enabled(self, tmp_dir: Path):
        """外键约束默认启用"""
        path = tmp_dir / "test.db"
        conn = open_db(path)
        row = conn.execute("PRAGMA foreign_keys").fetchone()
        assert row[0] == 1
        conn.close()

    def test_synchronous_normal(self, tmp_dir: Path):
        """默认 synchronous=NORMAL"""
        path = tmp_dir / "test.db"
        conn = open_db(path)
        row = conn.execute("PRAGMA synchronous").fetchone()
        assert row[0] == 1  # NORMAL = 1
        conn.close()

    def test_full_sync(self, tmp_dir: Path):
        """full_sync=True 时 synchronous=FULL"""
        path = tmp_dir / "test.db"
        conn = open_db(path, full_sync=True)
        row = conn.execute("PRAGMA synchronous").fetchone()
        assert row[0] == 2  # FULL = 2
        conn.close()

    def test_no_wal(self, tmp_dir: Path):
        """wal=False 时使用默认 journal_mode"""
        path = tmp_dir / "test.db"
        conn = open_db(path, wal=False)
        row = conn.execute("PRAGMA journal_mode").fetchone()
        assert row[0] in ("delete", "memory", "truncate", "persist")
        conn.close()


class TestInitProjectDb:
    """init_project_db() 数据库初始化"""

    def test_creates_parent_dirs(self, tmp_dir: Path):
        """应自动创建父目录"""
        path = tmp_dir / "deep" / "nested" / ".inkflow" / "inkflow.db"
        conn = init_project_db(path)
        conn.close()
        assert path.exists()

    def test_idempotent_reopen(self, tmp_dir: Path):
        """重复打开同一 DB 应保持数据"""
        path = tmp_dir / ".inkflow" / "inkflow.db"

        conn1 = init_project_db(path)
        conn1.execute(
            "INSERT INTO projects (project_id, name) VALUES ('p1', 'test')"
        )
        conn1.commit()
        conn1.close()

        conn2 = init_project_db(path)
        row = conn2.execute("SELECT name FROM projects WHERE project_id='p1'").fetchone()
        assert row is not None
        assert row["name"] == "test"
        conn2.close()

    def test_row_factory_is_row(self, tmp_dir: Path):
        """init_project_db 返回的 conn 应使用 Row factory"""
        path = tmp_dir / ".inkflow" / "inkflow.db"
        conn = init_project_db(path)
        conn.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        conn.commit()
        row = conn.execute("SELECT * FROM projects WHERE project_id='p1'").fetchone()
        # sqlite3.Row 支持按名称访问
        assert row["name"] == "test"
        assert row["project_id"] == "p1"
        conn.close()

    def test_schema_version_table_exists(self, tmp_dir: Path):
        """init_project_db 后 _schema_meta 表应存在"""
        path = tmp_dir / ".inkflow" / "inkflow.db"
        conn = init_project_db(path)
        row = conn.execute(
            "SELECT value FROM _schema_meta WHERE key='version'"
        ).fetchone()
        assert row is not None
        conn.close()


class TestBackup:
    """backup_project_db()"""

    def test_backup_creates_copy(self, tmp_dir: Path):
        """备份应创建 inkflow.db 的副本"""
        path = tmp_dir / ".inkflow" / "inkflow.db"
        conn = init_project_db(path)
        conn.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        conn.commit()
        conn.close()

        backup_path = backup_project_db(path, label="before_test")
        assert backup_path is not None
        assert backup_path.exists()
        assert "inkflow_" in backup_path.name
        assert "before_test" in backup_path.name

        # 备份应包含相同数据
        backup_conn = open_db(backup_path)
        row = backup_conn.execute(
            "SELECT name FROM projects WHERE project_id='p1'"
        ).fetchone()
        assert row is not None
        assert row[0] == "test"
        backup_conn.close()

    def test_backup_returns_none_for_missing_db(self, tmp_dir: Path):
        """不存在的 DB 文件返回 None"""
        result = backup_project_db(tmp_dir / "nonexistent" / "inkflow.db")
        assert result is None

    def test_backup_rotation(self, tmp_dir: Path):
        """备份应滚动删除旧文件，保留最近 N 个"""
        path = tmp_dir / ".inkflow" / "inkflow.db"
        conn = init_project_db(path)
        conn.close()

        # 创建 12 个备份 (keep=3)
        for i in range(12):
            backup_project_db(path, label=f"test_{i}", keep=3)

        backup_dir = path.parent / "backups"
        backups = sorted(backup_dir.glob("inkflow_*.db"))
        assert len(backups) <= 3


class TestSplitStatements:
    """M4: _split_statements handles string-internal semicolons."""

    def test_simple_split(self):
        """Two statements split correctly."""
        from inkflow.db.connection import _split_statements
        result = _split_statements("CREATE TABLE t (id INT);\nINSERT INTO t VALUES (1);")
        assert len(result) == 2

    def test_semicolon_in_string(self):
        """Semicolon inside a string literal should not split."""
        from inkflow.db.connection import _split_statements
        sql = "INSERT INTO t VALUES ('hello; world');"
        result = _split_statements(sql)
        assert len(result) == 1
        assert "hello; world" in result[0]

    def test_escaped_quote_in_string(self):
        """Doubled quotes inside strings don't end the string."""
        from inkflow.db.connection import _split_statements
        sql = "INSERT INTO t VALUES ('it''s; fine');\nSELECT 1;"
        result = _split_statements(sql)
        assert len(result) == 2
        assert "it''s; fine" in result[0]

    def test_empty_input(self):
        """Empty input returns empty list."""
        from inkflow.db.connection import _split_statements
        result = _split_statements("")
        assert result == []