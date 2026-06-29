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

    def test_current_version_repairs_stale_jury_dimension_check(self, tmp_dir):
        """版本号已是当前值时，也要修复滞后的 jury 维度 CHECK 约束。"""
        conn = sqlite3.connect(str(tmp_dir / "stale_jury_check.db"))
        try:
            ensure_meta_table(conn)
            set_schema_version(conn, SCHEMA_VERSION)
            conn.execute(
                "CREATE TABLE writing_jury_scores ("
                "score_id TEXT PRIMARY KEY, "
                "draft_id TEXT NOT NULL, "
                "shot_id TEXT NOT NULL, "
                "run_id TEXT NOT NULL, "
                "jury_persona TEXT NOT NULL, "
                "phase TEXT NOT NULL CHECK (phase IN ('independent', 'comparative', 'final')), "
                "dimension TEXT NOT NULL CHECK (dimension IN ("
                "'literary_quality', 'narrative_pacing', 'voice_consistency', "
                "'contract_compliance', 'motif_compatibility', 'anti_pattern_avoidance', "
                "'hook_transition', 'character_coherence', 'reader_engagement', "
                "'forbidden_expression', 'reading_fluency', 'suspense_effectiveness', "
                "'unexpected_value'"
                ")), "
                "score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100), "
                "comment TEXT, "
                "attempt_id TEXT NOT NULL, "
                "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
                "UNIQUE(shot_id, draft_id, jury_persona, phase, dimension, attempt_id)"
                ")"
            )

            result = migrate_if_needed(conn)

            assert any("rebuilt writing_jury_scores" in item for item in result)
            conn.execute(
                "INSERT INTO writing_jury_scores "
                "(score_id, draft_id, shot_id, run_id, jury_persona, phase, dimension, score, attempt_id) "
                "VALUES ('s1', 'd1', 'sh1', 'run1', '规则裁判', 'independent', "
                "'hard_rule_compliance', 90, 'att1')"
            )
        finally:
            conn.close()

    def test_migrate_v18_to_v19_backfills_logical_shot_id(self, tmp_dir):
        """v19 migration should preserve old shot ids as logical ids."""
        conn = sqlite3.connect(str(tmp_dir / "v18_shots.db"))
        conn.row_factory = sqlite3.Row
        try:
            ensure_meta_table(conn)
            set_schema_version(conn, 18)
            conn.execute(
                "CREATE TABLE writing_shots ("
                "shot_id TEXT PRIMARY KEY, "
                "project_id TEXT NOT NULL, "
                "run_id TEXT NOT NULL, "
                "layer_key TEXT NOT NULL, "
                "shot_index INTEGER NOT NULL, "
                "shot_status TEXT NOT NULL, "
                "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
                "updated_at TEXT NOT NULL DEFAULT (datetime('now')), "
                "UNIQUE(run_id, shot_index)"
                ")"
            )
            conn.execute(
                "INSERT INTO writing_shots "
                "(shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
                "VALUES ('v01.c02.s01', 'p1', 'run_old', 'v01.c02', 1, 'done_green')"
            )

            result = migrate_if_needed(conn)

            assert get_schema_version(conn) == SCHEMA_VERSION
            assert any("v18 → v19" in item for item in result)
            row = conn.execute(
                "SELECT shot_id, logical_shot_id FROM writing_shots"
            ).fetchone()
            assert row["shot_id"] == "v01.c02.s01"
            assert row["logical_shot_id"] == "v01.c02.s01"
            idx = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='index' "
                "AND name='idx_shots_logical'"
            ).fetchone()
            assert idx is not None
            unique_idx = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='index' "
                "AND name='idx_shots_run_logical_unique'"
            ).fetchone()
            assert unique_idx is not None
        finally:
            conn.close()

    def test_migrate_v19_to_v20_creates_book_run_tables(self, tmp_dir):
        """v20 migration should add book-run orchestration tables."""
        conn = sqlite3.connect(str(tmp_dir / "v19_book_runs.db"))
        conn.row_factory = sqlite3.Row
        try:
            ensure_meta_table(conn)
            set_schema_version(conn, 19)
            conn.execute(
                "CREATE TABLE projects (project_id TEXT PRIMARY KEY, name TEXT NOT NULL)"
            )
            conn.execute(
                "CREATE TABLE writing_sessions ("
                "session_id TEXT PRIMARY KEY, project_id TEXT NOT NULL, "
                "run_id TEXT NOT NULL UNIQUE, status TEXT NOT NULL)"
            )

            result = migrate_if_needed(conn)

            assert get_schema_version(conn) == SCHEMA_VERSION
            assert any("v19 → v20" in item for item in result)
            for table in ("writing_book_runs", "writing_book_run_chapters"):
                row = conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                    (table,),
                ).fetchone()
                assert row is not None
            for index in (
                "idx_book_runs_project",
                "idx_book_runs_status",
                "idx_book_run_chapters_book",
                "idx_book_run_chapters_run",
                "idx_book_run_chapters_status",
            ):
                row = conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
                    (index,),
                ).fetchone()
                assert row is not None
        finally:
            conn.close()

    def test_migrate_v20_to_v21_creates_audit_tables_and_columns(self, tmp_dir):
        """v21 migration should add audit tables and full model/outline audit columns."""
        conn = sqlite3.connect(str(tmp_dir / "v20_audit.db"))
        conn.row_factory = sqlite3.Row
        try:
            ensure_meta_table(conn)
            set_schema_version(conn, 20)
            conn.execute(
                "CREATE TABLE projects (project_id TEXT PRIMARY KEY, name TEXT NOT NULL)"
            )
            conn.execute(
                "CREATE TABLE writing_sessions ("
                "session_id TEXT PRIMARY KEY, project_id TEXT NOT NULL, "
                "run_id TEXT NOT NULL UNIQUE, status TEXT NOT NULL)"
            )
            conn.execute(
                "CREATE TABLE writing_shots ("
                "shot_id TEXT PRIMARY KEY, project_id TEXT NOT NULL, "
                "run_id TEXT NOT NULL, layer_key TEXT NOT NULL, "
                "shot_index INTEGER NOT NULL, shot_status TEXT NOT NULL)"
            )
            conn.execute(
                "CREATE TABLE writing_drafts ("
                "draft_id TEXT PRIMARY KEY, shot_id TEXT NOT NULL, "
                "run_id TEXT NOT NULL, writer_persona TEXT NOT NULL, "
                "writer_index INTEGER NOT NULL, text TEXT NOT NULL, attempt_id TEXT NOT NULL)"
            )
            conn.execute(
                "CREATE TABLE model_attempts ("
                "attempt_id TEXT PRIMARY KEY, run_id TEXT NOT NULL, shot_id TEXT, "
                "phase TEXT NOT NULL, model_name TEXT NOT NULL, idempotency_key TEXT NOT NULL, "
                "request_prompt_hash TEXT NOT NULL, response_text_hash TEXT, "
                "usage_prompt_tokens INTEGER DEFAULT 0, usage_completion_tokens INTEGER DEFAULT 0, "
                "usage_total_tokens INTEGER DEFAULT 0, error_message TEXT)"
            )
            conn.execute(
                "CREATE TABLE writing_outline_evaluations ("
                "evaluation_id TEXT PRIMARY KEY, shot_id TEXT NOT NULL, run_id TEXT NOT NULL, "
                "attempt INTEGER NOT NULL DEFAULT 1, outline_text TEXT NOT NULL, "
                "score INTEGER NOT NULL, dimensions_json JSON NOT NULL)"
            )
            conn.execute(
                "INSERT INTO writing_outline_evaluations "
                "(evaluation_id, shot_id, run_id, outline_text, score, dimensions_json) "
                "VALUES ('oe1', 'shot_01', 'run_01', 'outline', 80, '{}')"
            )

            result = migrate_if_needed(conn)

            assert get_schema_version(conn) == SCHEMA_VERSION
            assert any("v20 → v21" in item for item in result)
            for table in (
                "writing_audit_events",
                "writing_setup_snapshots",
                "writing_draft_eligibility",
                "writing_failure_attributions",
            ):
                assert conn.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                    (table,),
                ).fetchone()
            model_cols = {
                row["name"]
                for row in conn.execute("PRAGMA table_info(model_attempts)").fetchall()
            }
            assert "request_prompt_text" in model_cols
            assert "response_text" in model_cols
            outline = conn.execute(
                "SELECT threshold, passed FROM writing_outline_evaluations "
                "WHERE evaluation_id = 'oe1'"
            ).fetchone()
            assert outline["threshold"] == 70
            assert outline["passed"] == 1
        finally:
            conn.close()

    def test_migrate_v21_to_v22_allows_contract_audit_stage(self, tmp_dir):
        """v22 migration should rebuild audit events with contract stage support."""
        conn = sqlite3.connect(str(tmp_dir / "v21_contract_stage.db"))
        conn.row_factory = sqlite3.Row
        try:
            ensure_meta_table(conn)
            set_schema_version(conn, 21)
            conn.execute(
                "CREATE TABLE writing_audit_events ("
                "event_id TEXT PRIMARY KEY, "
                "project_id TEXT, run_id TEXT, session_id TEXT, shot_id TEXT, "
                "stage TEXT NOT NULL CHECK (stage IN ("
                "'init', 'setup', 'run', 'outline', 'outline_gate', 'prompt', "
                "'writer', 'gate1', 'hard_rule', 'type_gate', 'literary_jury', "
                "'jury_unavailable', 'gate2', 'l4', 'l3', 'l2', 'l1', 'export', "
                "'review', 'repair', 'resume', 'book_run'"
                ")), "
                "event_type TEXT NOT NULL, "
                "status TEXT NOT NULL DEFAULT 'recorded' CHECK (status IN ("
                "'started', 'recorded', 'passed', 'failed', 'skipped', "
                "'selected', 'rejected', 'completed'"
                ")), "
                "actor TEXT, "
                "input_refs_json JSON NOT NULL DEFAULT '{}', "
                "output_refs_json JSON NOT NULL DEFAULT '{}', "
                "metrics_json JSON NOT NULL DEFAULT '{}', "
                "payload_json JSON NOT NULL DEFAULT '{}', "
                "failure_category TEXT CHECK (failure_category IN ("
                "'contract_conflict', 'outline_gap', 'task_card_gap', 'writer_drift', "
                "'gate_false_positive', 'model_failure', 'jury_failure', 'unknown'"
                ")), "
                "failure_detail TEXT, "
                "created_at TEXT NOT NULL DEFAULT (datetime('now'))"
                ")"
            )
            conn.execute(
                "INSERT INTO writing_audit_events "
                "(event_id, stage, event_type, status) "
                "VALUES ('evt_old', 'setup', 'old_setup', 'recorded')"
            )

            result = migrate_if_needed(conn)

            assert get_schema_version(conn) == SCHEMA_VERSION
            assert any("v21 → v22" in item for item in result)
            old_row = conn.execute(
                "SELECT stage, event_type FROM writing_audit_events "
                "WHERE event_id = 'evt_old'"
            ).fetchone()
            assert old_row["stage"] == "setup"
            conn.execute(
                "INSERT INTO writing_audit_events "
                "(event_id, stage, event_type, status) "
                "VALUES ('evt_contract', 'contract', 'contract_audit', 'passed')"
            )
            contract_row = conn.execute(
                "SELECT stage FROM writing_audit_events WHERE event_id = 'evt_contract'"
            ).fetchone()
            assert contract_row["stage"] == "contract"
        finally:
            conn.close()


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
