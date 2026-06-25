"""Test migration version tracking and chain execution."""

from __future__ import annotations

import sqlite3

from inkflow.db.migration import (
    SCHEMA_VERSION,
    ensure_meta_table,
    get_schema_version,
    init_version,
    migrate_if_needed,
    register_migration,
    set_schema_version,
)


class TestVersionTracking:
    """版本号读写"""

    def test_fresh_db_has_current_version(self, db):
        """全新 DB 应有 SCHEMA_VERSION"""
        version = get_schema_version(db)
        assert version == SCHEMA_VERSION

    def test_get_schema_version_zero_when_no_table(self, tmp_dir):
        """无 _schema_meta 表时返回 0"""
        import sqlite3
        conn = sqlite3.connect(str(tmp_dir / "empty.db"))
        try:
            v = get_schema_version(conn)
            assert v == 0
        finally:
            conn.close()

    def test_set_and_get_version(self, db):
        """set_schema_version 后 get_schema_version 应返回相同值"""
        set_schema_version(db, 3)
        assert get_schema_version(db) == 3

    def test_init_version_writes_current(self, db):
        """init_version 写入 SCHEMA_VERSION"""
        set_schema_version(db, 0)
        init_version(db)
        assert get_schema_version(db) == SCHEMA_VERSION

    def test_migrate_noop_when_current(self, db):
        """当前版本已是 SCHEMA_VERSION 时，migrate 应为空"""
        result = migrate_if_needed(db)
        assert result == []

    def test_migrate_skip_when_no_migration_path(self, db):
        """无迁移路径时保留在最后成功版本 (不再强制标记)"""
        set_schema_version(db, 0)
        result = migrate_if_needed(db)
        # 无迁移路径时不做任何操作，版本保留为 0
        assert get_schema_version(db) == 0


class TestMigrationChain:
    """迁移链执行"""

    def test_migration_executes_in_order(self, tmp_dir):
        """迁移函数按版本号顺序执行"""
        import sqlite3
        conn = sqlite3.connect(str(tmp_dir / "test_migrate.db"))
        try:
            ensure_meta_table(conn)
            set_schema_version(conn, 1)

            # 动态注册一个迁移
            executed = []

            @register_migration(1, 2)
            def _test_migrate(c):
                """测试迁移 1→2"""
                executed.append("1→2")

            @register_migration(2, 3)
            def _test_migrate_2(c):
                """测试迁移 2→3"""
                executed.append("2→3")

            # 临时修改 SCHEMA_VERSION 来测试
            import inkflow.db.migration as m
            old_version = m.SCHEMA_VERSION
            m.SCHEMA_VERSION = 3
            try:
                result = migrate_if_needed(conn)
                assert executed == ["1→2", "2→3"]
                assert len(result) == 2
                assert get_schema_version(conn) == 3
            finally:
                m.SCHEMA_VERSION = old_version
                # 清理注册的迁移
                m._MIGRATIONS.clear()
        finally:
            conn.close()

    def test_migration_failure_is_recorded(self, tmp_dir):
        """迁移失败应记录而不断开"""
        import sqlite3
        conn = sqlite3.connect(str(tmp_dir / "test_fail.db"))
        try:
            ensure_meta_table(conn)
            set_schema_version(conn, 1)

            @register_migration(1, 2)
            def _failing_migrate(c):
                """会失败的迁移"""
                raise RuntimeError("模拟失败")

            import inkflow.db.migration as m
            old_version = m.SCHEMA_VERSION
            m.SCHEMA_VERSION = 2
            try:
                result = migrate_if_needed(conn)
                assert any("FAILED" in r for r in result)
                # 失败后保留在最后成功版本 (v1), 不再强制标记为 v2
                assert get_schema_version(conn) == 1
            finally:
                m.SCHEMA_VERSION = old_version
                m._MIGRATIONS.clear()
        finally:
            conn.close()