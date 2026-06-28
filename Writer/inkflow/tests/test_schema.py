"""Verify all 41 business tables, CHECK constraints, UNIQUE constraints, and FK references."""

from __future__ import annotations

import sqlite3

import pytest


# ── 41 张业务表名（按 implementation-contract-v0.md + v20 book-run orchestration） ──

ALL_TABLES = [
    "projects",
    "writing_book_constitutions",  # v9: L0 全书宪法 (ARCH-4)
    "writing_project_structure",
    "writing_meta_contract",
    "writing_meta_contract_revisions",
    "writing_project_config",
    "writing_writer_profiles",
    "writing_jury_config",
    "writing_motif_definitions",
    "writing_run_snapshots",
    "writing_shots",
    "writing_sessions",
    "writing_session_checkpoints",
    "writing_shot_contracts",
    "shot_revisions",
    "writing_drafts",
    "writing_shot_prompts",
    "writing_context_snaps",
    "writing_fact_anchors",
    "writing_motif_instances",
    "writing_motif_tracker",
    "writing_jury_scores",
    "writing_repair_audit",
    "writing_exception_events",
    "writing_deviation_notes",
    "writing_reference_pool",
    "model_attempts",
    "writing_architect_gates",
    "writing_outline_evaluations",
    "writing_information_gaps",
    "writing_chapter_rhythms",
    "writing_volume_rhythms",   # v10: L0.5 卷部节奏 (ARCH-5)
    "writing_style_preferences", # v12: 风格偏好学习 (ARCH-10)
    "writing_anti_contract_reviews", # v13: 反契约沙盒 (ARCH-11)
    "writing_chapter_reviews", # v18: 章节 accepted canonical 状态
    "writing_book_runs", # v20: 全书编排批次
    "writing_book_run_chapters", # v20: 全书编排章节状态
    # v8: 三棵树架构 (ARCH-12)
    "tree_nodes",
    "contract_versions",
    "story_content",
    "execution_records",
]

# 预期索引
EXPECTED_INDEXES = [
    "idx_sessions_project",
    "idx_sessions_status",
    "idx_checkpoints_session",
    "idx_shots_run",
    "idx_shots_status",
    "idx_shots_logical",
    "idx_shots_run_logical_unique",
    "idx_revisions_shot",
    "idx_revisions_one_current",
    "idx_drafts_shot",
    "idx_drafts_run",
    "idx_prompts_run",
    "idx_context_snaps_run",
    "idx_anchors_project",
    "idx_motif_instances_run",
    "idx_jury_scores_run",
    "idx_repair_audit_run",
    "idx_exception_events_run",
    "idx_deviation_notes_run",
    "idx_model_attempts_run",
    "idx_model_attempts_shot",
    "idx_architect_gates_run",
    "idx_architect_gates_level",
    "idx_chapter_rhythms_run",
    "idx_chapter_rhythms_chapter",
    # v10: L0.5 卷部节奏 (ARCH-5)
    "idx_volume_rhythms_run",
    "idx_volume_rhythms_volume",
    # v12: 风格偏好学习 (ARCH-10)
    "idx_style_prefs_run",
    "idx_style_prefs_project",
    "idx_style_prefs_persona",
    # v13: 反契约沙盒 (ARCH-11)
    "idx_anti_contract_reviews_run",
    # v18: 章节审稿 canonical 状态
    "idx_chapter_reviews_project_chapter",
    "idx_chapter_reviews_status",
    "idx_chapter_reviews_one_accepted",
    # v20: 全书编排
    "idx_book_runs_project",
    "idx_book_runs_status",
    "idx_book_run_chapters_book",
    "idx_book_run_chapters_run",
    "idx_book_run_chapters_status",
    # v8: 三棵树架构 (ARCH-12)
    "idx_tree_nodes_parent",
    "idx_tree_nodes_lookup",
    "idx_tree_nodes_run",
    "idx_contract_versions_node",
    "idx_story_content_node",
    "idx_execution_records_node",
    "idx_execution_records_run",
    # v9: L0 全书宪法 (ARCH-4)
    "idx_book_constitutions_project",
]


class TestSchemaTables:
    """验证所有 41 张业务表存在"""

    def test_all_tables_exist(self, db):
        """init_project_db() 应创建全部 41 张业务表"""
        rows = db.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_schema_%' ORDER BY name"
        ).fetchall()
        actual = {r[0] for r in rows}
        expected = set(ALL_TABLES)
        missing = expected - actual
        extra = actual - expected
        assert not missing, f"缺少表: {missing}"
        assert not extra, f"多余表: {extra}"

    def test_indexes_exist(self, db):
        """所有预期索引应存在"""
        rows = db.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).fetchall()
        actual = {r[0] for r in rows}
        for idx in EXPECTED_INDEXES:
            assert idx in actual, f"缺少索引: {idx}"

    def test_shots_have_logical_shot_id(self, db):
        """v19: writing_shots records stable logical identity separately."""
        columns = {
            row["name"]
            for row in db.execute("PRAGMA table_info(writing_shots)").fetchall()
        }
        assert "logical_shot_id" in columns


class TestCheckConstraints:
    """验证 CHECK 约束拒绝无效值"""

    def _insert_project(self, db) -> str:
        db.execute(
            "INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')"
        )
        return "proj_01"

    def test_projects_status_invalid(self, db):
        """projects.status 只接受 'active' 或 'archived'"""
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO projects (project_id, name, status) VALUES ('p1', 'test', 'deleted')"
            )

    def test_projects_status_valid(self, db):
        """projects.status 接受 'active' 和 'archived'"""
        db.execute(
            "INSERT INTO projects (project_id, name, status) VALUES ('p1', 'test', 'active')"
        )
        db.execute(
            "INSERT INTO projects (project_id, name, status) VALUES ('p2', 'test2', 'archived')"
        )

    def test_meta_contract_status_invalid(self, db):
        """writing_meta_contract.status 只接受 6 种状态"""
        db.execute(
            "INSERT INTO projects (project_id, name) VALUES ('proj', 'test')"
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_meta_contract (meta_contract_id, project_id, status, layers_json, human_confirm_layer) "
                "VALUES ('mc1', 'proj', 'invalid_status', '{}', 2)"
            )

    def test_shot_status_invalid(self, db):
        """writing_shots.shot_status 只接受 10 种状态"""
        pid = self._insert_project(db)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
                "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'finished')", (pid,)
            )

    def test_shot_redo_attempt_range(self, db):
        """writing_shots.redo_attempt 必须在 0-3 之间"""
        pid = self._insert_project(db)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        # 0-3 should be valid
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status, redo_attempt) "
            "VALUES ('sh0', ?, 'run_01', 'v01.c01', 1, 'pending', 3)", (pid,)
        )
        # 4 should fail
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status, redo_attempt) "
                "VALUES ('sh1', ?, 'run_01', 'v01.c01', 2, 'pending', 4)", (pid,)
            )

    def test_anchor_type_invalid(self, db):
        """writing_fact_anchors.anchor_type 只接受 9 种类型"""
        pid = self._insert_project(db)
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_fact_anchors (anchor_id, project_id, anchor_type, anchor_key, anchor_value, confidence) "
                "VALUES ('a1', ?, 'invalid_type', 'key', 'val', 1.0)", (pid,)
            )

    def test_anchor_confidence_range(self, db):
        """writing_fact_anchors.confidence 必须在 0-1 之间"""
        pid = self._insert_project(db)
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_fact_anchors (anchor_id, project_id, anchor_type, anchor_key, anchor_value, confidence) "
                "VALUES ('a1', ?, 'character_state', 'key', 'val', 1.5)", (pid,)
            )

    def test_chapter_review_status_invalid(self, db):
        """writing_chapter_reviews.status 只接受 canonical 审稿状态。"""
        pid = self._insert_project(db)
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_chapter_reviews "
                "(review_id, project_id, chapter_key, status) "
                "VALUES ('rv1', ?, 'v01.c02', 'draft')",
                (pid,),
            )

    def test_chapter_review_status_valid(self, db):
        """v18: 章节审稿表接受 accepted/needs_revision/rejected/superseded。"""
        pid = self._insert_project(db)
        for idx, status in enumerate([
            "accepted", "needs_revision", "rejected", "superseded",
        ]):
            db.execute(
                "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
                "VALUES (?, ?, ?, 'completed')",
                (f"srv_{idx}", pid, f"run_{idx}"),
            )
            db.execute(
                "INSERT INTO writing_chapter_reviews "
                "(review_id, project_id, chapter_key, run_id, status) "
                "VALUES (?, ?, 'v01.c02', ?, ?)",
                (f"rv_{idx}", pid, f"run_{idx}", status),
            )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_fact_anchors (anchor_id, project_id, anchor_type, anchor_key, anchor_value, confidence) "
                "VALUES ('a2', ?, 'character_state', 'key', 'val', -0.1)", (pid,)
            )

    def test_jury_score_range(self, db):
        """writing_jury_scores.score 必须在 0-100 之间"""
        pid = self._insert_project(db)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'pending')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d1', 'sh1', 'run_01', '意象师', 0, 'test', 'att1')"
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_jury_scores (score_id, draft_id, shot_id, run_id, jury_persona, phase, dimension, score, attempt_id) "
                "VALUES ('s1', 'd1', 'sh1', 'run_01', '契约官', 'independent', 'literary_quality', 101, 'att1')"
            )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_jury_scores (score_id, draft_id, shot_id, run_id, jury_persona, phase, dimension, score, attempt_id) "
                "VALUES ('s2', 'd1', 'sh1', 'run_01', '契约官', 'independent', 'literary_quality', -1, 'att1')"
            )

    def test_jury_unexpected_value_dimension_valid(self, db):
        """CREATIVE-1: writing_jury_scores.dimension 接受 unexpected_value。"""
        pid = self._insert_project(db)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'pending')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d1', 'sh1', 'run_01', '意象师', 0, 'test', 'att1')"
        )
        db.execute(
            "INSERT INTO writing_jury_scores (score_id, draft_id, shot_id, run_id, jury_persona, phase, dimension, score, attempt_id) "
            "VALUES ('s1', 'd1', 'sh1', 'run_01', '创意评审', 'independent', 'unexpected_value', 88, 'att1')"
        )

    def test_jury_layered_dimensions_valid(self, db):
        """v17: writing_jury_scores.dimension 接受 hard-rule 和文学 9 维。"""
        pid = self._insert_project(db)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'pending')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d1', 'sh1', 'run_01', '意象师', 0, 'test', 'att1')"
        )
        for index, dimension in enumerate([
            "hard_rule_compliance",
            "language_texture",
            "scene_specificity",
            "chapter_continuity",
        ]):
            db.execute(
                "INSERT INTO writing_jury_scores "
                "(score_id, draft_id, shot_id, run_id, jury_persona, phase, dimension, score, attempt_id) "
                "VALUES (?, 'd1', 'sh1', 'run_01', '文学裁判', 'independent', ?, 88, ?)",
                (f"layered_{index}", dimension, f"att_layered_{index}"),
            )

    def test_revision_operation_invalid(self, db):
        """shot_revisions.operation 只接受已登记操作"""
        pid = self._insert_project(db)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'pending')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shot_contracts (contract_id, project_id, run_id, shot_id, layer_key, contract_status, snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('c1', ?, 'run_01', 'sh1', 'v01.c01', 'draft', 'hash1', '{}', '{}', '{}')", (pid,)
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO shot_revisions (revision_id, shot_id, run_id, contract_id, revision_sequence, operation, text, text_hash_normalized, attempt_id) "
                "VALUES ('r1', 'sh1', 'run_01', 'c1', 1, 'invalid_op', 'text', 'hash', 'att1')"
            )

    def test_revision_operation_write_polish_valid(self, db):
        """CREATIVE-2: shot_revisions.operation 接受 write_polish。"""
        pid = self._insert_project(db)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'pending')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shot_contracts (contract_id, project_id, run_id, shot_id, layer_key, contract_status, snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('c1', ?, 'run_01', 'sh1', 'v01.c01', 'draft', 'hash1', '{}', '{}', '{}')", (pid,)
        )
        db.execute(
            "INSERT INTO shot_revisions (revision_id, shot_id, run_id, contract_id, revision_sequence, operation, text, text_hash_normalized, attempt_id) "
            "VALUES ('r1', 'sh1', 'run_01', 'c1', 1, 'write_polish', 'polished text', 'hash', 'att1')"
        )

    def test_motif_evolution_phase_invalid(self, db):
        """writing_motif_instances.evolution_phase 只接受 4 种阶段"""
        pid = self._insert_project(db)
        db.execute(
            "INSERT INTO writing_motif_definitions (motif_id, project_id, name, planned_density_json, variants_json) "
            "VALUES ('m1', ?, '膝盖', '{}', '{}')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'pending')", (pid,)
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_motif_instances (instance_id, motif_id, project_id, run_id, shot_id, variant_used, evolution_phase) "
                "VALUES ('i1', 'm1', ?, 'run_01', 'sh1', 'var1', 'invalid_phase')", (pid,)
            )

    def test_repair_layer_invalid(self, db):
        """writing_repair_audit.layer 只接受 L1-L4"""
        pid = self._insert_project(db)
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_repair_audit (repair_audit_id, run_id, contract_id, layer, diagnosis, diff_json) "
                "VALUES ('ra1', 'run_01', 'c1', 'L5', 'test', '{}')"
            )


class TestUniqueConstraints:
    """验证 UNIQUE 约束"""

    def test_projects_name_not_unique(self, db):
        """projects.name 无 UNIQUE 约束（允许同名）"""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', '分流')")
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p2', '分流')")

    def test_meta_contract_allows_multiple_versions(self, db):
        """writing_meta_contract 允许同 project 多版本 (UNIQUE 已移除)"""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.execute(
            "INSERT INTO writing_meta_contract (meta_contract_id, project_id, status, layers_json, human_confirm_layer) "
            "VALUES ('mc1', 'p1', 'draft', '{}', 2)"
        )
        # 二次插入同 project 不再报错 (支持契约版本演化)
        db.execute(
            "INSERT INTO writing_meta_contract (meta_contract_id, project_id, status, layers_json, human_confirm_layer) "
            "VALUES ('mc2', 'p1', 'draft', '{}', 2)"
        )

    def test_sessions_run_id_unique(self, db):
        """writing_sessions.run_id 是 UNIQUE"""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
                "VALUES ('s2', 'p1', 'run_01', 'active')"
            )

    def test_run_snapshots_run_id_unique(self, db):
        """writing_run_snapshots.run_id 是 UNIQUE"""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.execute(
            "INSERT INTO writing_meta_contract (meta_contract_id, project_id, status, layers_json, human_confirm_layer) "
            "VALUES ('mc1', 'p1', 'draft', '{}', 2)"
        )
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        db.execute(
            "INSERT INTO writing_run_snapshots (snapshot_id, run_id, project_id, meta_contract_id, config_hash, contract_snapshot_hash, snapshot_json) "
            "VALUES ('sn1', 'run_01', 'p1', 'mc1', 'ch1', 'csh1', '{}')"
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_run_snapshots (snapshot_id, run_id, project_id, meta_contract_id, config_hash, contract_snapshot_hash, snapshot_json) "
                "VALUES ('sn2', 'run_01', 'p1', 'mc1', 'ch2', 'csh2', '{}')"
            )

    def test_shots_run_id_shot_index_unique(self, db):
        """writing_shots (run_id, shot_index) 是 UNIQUE"""
        pid = "p1"
        db.execute("INSERT INTO projects (project_id, name) VALUES (?, 'test')", (pid,))
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'pending')", (pid,)
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
                "VALUES ('sh2', ?, 'run_01', 'v01.c01', 1, 'pending')", (pid,)
            )

    def test_chapter_reviews_only_one_accepted_per_chapter(self, db):
        """v18: 每个项目章节只能有一个 accepted canonical。"""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        for idx in range(1, 4):
            db.execute(
                "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
                "VALUES (?, 'p1', ?, 'completed')",
                (f"s{idx}", f"run_0{idx}"),
            )
        db.execute(
            "INSERT INTO writing_chapter_reviews "
            "(review_id, project_id, chapter_key, run_id, status) "
            "VALUES ('rv1', 'p1', 'v01.c02', 'run_01', 'accepted')"
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_chapter_reviews "
                "(review_id, project_id, chapter_key, run_id, status) "
                "VALUES ('rv2', 'p1', 'v01.c02', 'run_02', 'accepted')"
            )
        db.execute(
            "INSERT INTO writing_chapter_reviews "
            "(review_id, project_id, chapter_key, run_id, status) "
            "VALUES ('rv3', 'p1', 'v01.c02', 'run_03', 'rejected')"
        )


class TestForeignKeys:
    """验证外键约束"""

    def test_fk_cascade_from_shot_revisions(self, db):
        """shot_revisions 引用不存在的 shot_id 应失败"""
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO shot_revisions (revision_id, shot_id, run_id, contract_id, revision_sequence, operation, text, text_hash_normalized, attempt_id) "
                "VALUES ('r1', 'nonexistent', 'run_01', 'c1', 1, 'write_generate', 'text', 'hash', 'att1')"
            )

    def test_fk_from_drafts_to_shots(self, db):
        """writing_drafts 引用不存在的 shot_id 应失败"""
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
                "VALUES ('d1', 'nonexistent', 'run_01', '意象师', 0, 'text', 'att1')"
            )

    def test_fk_from_checkpoints_to_sessions(self, db):
        """writing_session_checkpoints 引用不存在的 session_id 应失败"""
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_session_checkpoints (checkpoint_id, session_id, shot_id, checkpoint_json, context_hash) "
                "VALUES ('cp1', 'nonexistent', 'sh1', '{}', 'hash')"
            )

    def test_fk_from_motif_instances_to_definitions(self, db):
        """writing_motif_instances 引用不存在的 motif_id 应失败"""
        pid = "p1"
        db.execute("INSERT INTO projects (project_id, name) VALUES (?, 'test')", (pid,))
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'pending')", (pid,)
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO writing_motif_instances (instance_id, motif_id, project_id, run_id, shot_id, variant_used, evolution_phase) "
                "VALUES ('i1', 'nonexistent', ?, 'run_01', 'sh1', 'var1', 'establishment')", (pid,)
            )


class TestTreeArchitecture:
    """验证三棵树架构的表结构与正文真相源规则"""

    def test_execution_records_has_revision_id(self, db):
        """execution_records 必须有 revision_id 列"""
        cols = {
            r[1] for r in db.execute(
                "PRAGMA table_info(execution_records)"
            ).fetchall()
        }
        assert "revision_id" in cols, "execution_records 缺少 revision_id 列"

    def test_text_truth_source_rule_unsealed(self, db):
        """未封版时，正文 = MAX(revision_sequence)"""
        pid = "proj_01"
        db.execute("INSERT INTO projects (project_id, name) VALUES (?, 'test')", (pid,))
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'pending')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shot_contracts (contract_id, project_id, run_id, shot_id, layer_key, "
            "contract_status, snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('c1', ?, 'run_01', 'sh1', 'v01.c01', 'locked', 'h1', '{}', '{}', '{}')", (pid,)
        )
        # seq=1 (旧版本), is_current=0
        db.execute(
            "INSERT INTO shot_revisions (revision_id, shot_id, run_id, contract_id, revision_sequence, "
            "operation, text, text_hash_normalized, is_current, attempt_id) "
            "VALUES ('r1', 'sh1', 'run_01', 'c1', 1, 'write_generate', '版本一文本', 'h1', 0, 'att1')"
        )
        # seq=2 (最新生成), is_current=0
        db.execute(
            "INSERT INTO shot_revisions (revision_id, shot_id, run_id, contract_id, revision_sequence, "
            "operation, text, text_hash_normalized, is_current, attempt_id) "
            "VALUES ('r2', 'sh1', 'run_01', 'c1', 2, 'write_generate', '版本二文本', 'h2', 0, 'att2')"
        )
        # 未封版 → 正文 = MAX(seq)
        row = db.execute(
            "SELECT text FROM shot_revisions WHERE shot_id='sh1' "
            "ORDER BY revision_sequence DESC LIMIT 1"
        ).fetchone()
        assert row[0] == '版本二文本', f"期望最新版本，实际: {row[0]}"

    def test_text_truth_source_rule_sealed(self, db):
        """封版后，正文 = is_current=1"""
        pid = "proj_02"
        db.execute("INSERT INTO projects (project_id, name) VALUES (?, 'test')", (pid,))
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', ?, 'run_01', 'active')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', ?, 'run_01', 'v01.c01', 1, 'done_green')", (pid,)
        )
        db.execute(
            "INSERT INTO writing_shot_contracts (contract_id, project_id, run_id, shot_id, layer_key, "
            "contract_status, snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('c1', ?, 'run_01', 'sh1', 'v01.c01', 'locked', 'h1', '{}', '{}', '{}')", (pid,)
        )
        # seq=1 (旧版本), is_current=0
        db.execute(
            "INSERT INTO shot_revisions (revision_id, shot_id, run_id, contract_id, revision_sequence, "
            "operation, text, text_hash_normalized, is_current, attempt_id) "
            "VALUES ('r1', 'sh1', 'run_01', 'c1', 1, 'write_generate', '旧版本', 'h1', 0, 'att1')"
        )
        # seq=2 (封版版本), is_current=1
        db.execute(
            "INSERT INTO shot_revisions (revision_id, shot_id, run_id, contract_id, revision_sequence, "
            "operation, text, text_hash_normalized, is_current, attempt_id) "
            "VALUES ('r2', 'sh1', 'run_01', 'c1', 2, 'write_generate', '封版本', 'h2', 1, 'att2')"
        )
        # seq=3 (封版后的新生成), is_current=0
        db.execute(
            "INSERT INTO shot_revisions (revision_id, shot_id, run_id, contract_id, revision_sequence, "
            "operation, text, text_hash_normalized, is_current, attempt_id) "
            "VALUES ('r3', 'sh1', 'run_01', 'c1', 3, 'write_generate', '新生成文本', 'h3', 0, 'att3')"
        )
        # 封版后 → 正文 = is_current=1
        row = db.execute(
            "SELECT text FROM shot_revisions WHERE shot_id='sh1' AND is_current=1"
        ).fetchone()
        assert row is not None, "没有找到封版记录"
        assert row[0] == '封版本', f"期望封版版本，实际: {row[0]}"
