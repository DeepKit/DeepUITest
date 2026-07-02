"""数据库迁移 — 检测 schema 版本并自动升级

设计：
- DB 有 `_schema_meta` 表存储 `version` 字段
- 当前代码版本 = SCHEMA_VERSION（与 schema.sql 同步）
- 打开已存在 DB 时：若 version < SCHEMA_VERSION → 执行迁移链
- 迁移函数按版本号顺序执行
- 全新 DB 由 init_project_db() 创建，版本号直接写 SCHEMA_VERSION（无需迁移）
"""

from __future__ import annotations

import sqlite3

# 当前 schema 版本（每次修改 schema 时 +1）
SCHEMA_VERSION = 24

# 迁移链：(from_version, to_version, migration_function)
# 按 from_version 升序排列
_MIGRATIONS: list[tuple[int, int, object]] = []

_JURY_SCORE_DIMENSIONS = (
    "literary_quality",
    "narrative_pacing",
    "voice_consistency",
    "contract_compliance",
    "motif_compatibility",
    "anti_pattern_avoidance",
    "hook_transition",
    "character_coherence",
    "reader_engagement",
    "forbidden_expression",
    "reading_fluency",
    "suspense_effectiveness",
    "unexpected_value",
    "hard_rule_compliance",
    "language_texture",
    "scene_specificity",
    "emotional_progression",
    "character_believability",
    "dialogue_subtext",
    "pacing_control",
    "motif_theme_fit",
    "chapter_continuity",
)


def clear_migrations() -> None:
    """Clear all registered migrations. Used by tests to ensure isolation."""
    _MIGRATIONS.clear()


def register_migration(from_ver: int, to_ver: int):
    """装饰器：注册一个迁移函数"""
    def decorator(fn):
        # Warn on duplicate from_ver (last registration wins)
        for i, (f, t, _) in enumerate(_MIGRATIONS):
            if f == from_ver:
                import warnings
                warnings.warn(
                    f"Migration from_ver={from_ver} already registered "
                    f"(→{t}); overwriting with →{to_ver}",
                    stacklevel=2,
                )
                _MIGRATIONS[i] = (from_ver, to_ver, fn)
                return fn
        _MIGRATIONS.append((from_ver, to_ver, fn))
        return fn
    return decorator


def ensure_meta_table(conn: sqlite3.Connection) -> None:
    """确保 _schema_meta 表存在"""
    conn.execute(
        "CREATE TABLE IF NOT EXISTS _schema_meta "
        "(key TEXT PRIMARY KEY, value TEXT)"
    )


def get_schema_version(conn: sqlite3.Connection) -> int:
    """获取 DB 的 schema 版本号，无记录返回 0"""
    ensure_meta_table(conn)
    row = conn.execute(
        "SELECT value FROM _schema_meta WHERE key = 'version'"
    ).fetchone()
    return int(row[0]) if row else 0


def set_schema_version(conn: sqlite3.Connection, version: int) -> None:
    """设置 schema 版本号"""
    ensure_meta_table(conn)
    conn.execute(
        "INSERT OR REPLACE INTO _schema_meta (key, value) VALUES ('version', ?)",
        (str(version),),
    )


def init_version(conn: sqlite3.Connection) -> None:
    """全新 DB 创建后调用，写入当前版本号"""
    set_schema_version(conn, SCHEMA_VERSION)


def migrate_if_needed(conn: sqlite3.Connection) -> list[str]:
    """检查并执行迁移。返回执行的迁移描述列表。

    用法：在 init_project_db() 中，若 DB 已存在，调用此函数。
    """
    current = get_schema_version(conn)
    if current >= SCHEMA_VERSION:
        repairs = _repair_schema_health(conn)
        if repairs:
            conn.commit()
        return repairs

    executed = []
    # 构建迁移图：from_ver → (to_ver, fn)
    graph: dict[int, tuple[int, object]] = {}
    for from_v, to_v, fn in _MIGRATIONS:
        graph[from_v] = (to_v, fn)

    # 沿链执行
    while current < SCHEMA_VERSION:
        if current not in graph:
            # No migration path from current version → warning
            import warnings
            warnings.warn(
                f"No migration path from schema version {current} "
                f"to {SCHEMA_VERSION}. DB left at version {current}.",
                stacklevel=2,
            )
            break
        to_ver, fn = graph[current]
        desc = fn.__doc__ or f"migrate {current} → {to_ver}"
        try:
            conn.execute("SAVEPOINT migrate_step")
            fn(conn)
            set_schema_version(conn, to_ver)
            conn.execute("RELEASE SAVEPOINT migrate_step")
            executed.append(f"v{current} → v{to_ver}: {desc.strip()}")
            current = to_ver
        except Exception as e:
            conn.execute("ROLLBACK TO SAVEPOINT migrate_step")
            executed.append(f"v{current} → v{to_ver}: FAILED ({e})")
            break

    if current >= SCHEMA_VERSION:
        executed.extend(_repair_schema_health(conn))

    conn.commit()
    return executed


def _repair_schema_health(conn: sqlite3.Connection) -> list[str]:
    """Repair schema drift that version numbers alone cannot detect."""
    repairs: list[str] = []
    if _jury_scores_schema_needs_repair(conn):
        try:
            conn.execute("SAVEPOINT repair_jury_scores_schema")
            _rebuild_writing_jury_scores(conn)
            conn.execute("RELEASE SAVEPOINT repair_jury_scores_schema")
            repairs.append(
                "schema health: rebuilt writing_jury_scores for v17 jury dimensions"
            )
        except Exception as e:
            conn.execute("ROLLBACK TO SAVEPOINT repair_jury_scores_schema")
            repairs.append(f"schema health: FAILED rebuilding writing_jury_scores ({e})")
    if _audit_events_schema_needs_contract_stage(conn):
        try:
            conn.execute("SAVEPOINT repair_audit_events_contract_stage")
            _rebuild_writing_audit_events_with_contract_stage(conn)
            conn.execute("RELEASE SAVEPOINT repair_audit_events_contract_stage")
            repairs.append(
                "schema health: rebuilt writing_audit_events for contract stage"
            )
        except Exception as e:
            conn.execute("ROLLBACK TO SAVEPOINT repair_audit_events_contract_stage")
            repairs.append(f"schema health: FAILED rebuilding writing_audit_events ({e})")
    return repairs


def _jury_scores_schema_needs_repair(conn: sqlite3.Connection) -> bool:
    row = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'writing_jury_scores'"
    ).fetchone()
    if not row or not row[0]:
        return False
    sql = row[0]
    required = (
        "'hard_rule_compliance'",
        "'language_texture'",
        "'emotional_progression'",
        "'dialogue_subtext'",
        "'motif_theme_fit'",
        "'chapter_continuity'",
    )
    return not all(token in sql for token in required)


def _audit_events_schema_needs_contract_stage(conn: sqlite3.Connection) -> bool:
    row = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'writing_audit_events'"
    ).fetchone()
    if not row or not row[0]:
        return False
    return "'contract'" not in row[0]


def _create_writing_jury_scores_table(conn: sqlite3.Connection) -> None:
    dimensions = ", ".join(f"'{dimension}'" for dimension in _JURY_SCORE_DIMENSIONS)
    conn.execute(
        "CREATE TABLE writing_jury_scores ("
        "score_id TEXT PRIMARY KEY, "
        "draft_id TEXT NOT NULL REFERENCES writing_drafts(draft_id), "
        "shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id), "
        "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
        "jury_persona TEXT NOT NULL, "
        "phase TEXT NOT NULL CHECK (phase IN ("
        "'independent', 'comparative', 'final'"
        ")), "
        f"dimension TEXT NOT NULL CHECK (dimension IN ({dimensions})), "
        "score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100), "
        "comment TEXT, "
        "attempt_id TEXT NOT NULL, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(shot_id, draft_id, jury_persona, phase, dimension, attempt_id)"
        ")"
    )


def _rebuild_writing_jury_scores(conn: sqlite3.Connection) -> None:
    temp_table = f"writing_jury_scores_rebuild_{abs(id(conn))}"
    conn.execute(f"ALTER TABLE writing_jury_scores RENAME TO {temp_table}")
    _create_writing_jury_scores_table(conn)
    conn.execute(
        "INSERT INTO writing_jury_scores ("
        "score_id, draft_id, shot_id, run_id, jury_persona, phase, dimension, "
        "score, comment, attempt_id, created_at"
        ") SELECT "
        "score_id, draft_id, shot_id, run_id, jury_persona, phase, dimension, "
        "score, comment, attempt_id, created_at "
        f"FROM {temp_table}"
    )
    conn.execute(f"DROP TABLE {temp_table}")
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_jury_scores_run "
        "ON writing_jury_scores(run_id)"
    )


def _rebuild_writing_audit_events_with_contract_stage(conn: sqlite3.Connection) -> None:
    if not _table_exists(conn, "writing_audit_events"):
        _create_v21_audit_tables(conn)
        return
    if not _audit_events_schema_needs_contract_stage(conn):
        return

    temp_table = f"writing_audit_events_rebuild_{abs(id(conn))}"
    conn.execute("DROP INDEX IF EXISTS idx_audit_events_run")
    conn.execute("DROP INDEX IF EXISTS idx_audit_events_shot")
    conn.execute("DROP INDEX IF EXISTS idx_audit_events_failure")
    conn.execute(f"ALTER TABLE writing_audit_events RENAME TO {temp_table}")
    _create_v21_audit_tables(conn)
    conn.execute(
        "INSERT INTO writing_audit_events ("
        "event_id, project_id, run_id, session_id, shot_id, stage, event_type, "
        "status, actor, input_refs_json, output_refs_json, metrics_json, "
        "payload_json, failure_category, failure_detail, created_at"
        ") SELECT "
        "event_id, project_id, run_id, session_id, shot_id, stage, event_type, "
        "status, actor, input_refs_json, output_refs_json, metrics_json, "
        "payload_json, failure_category, failure_detail, created_at "
        f"FROM {temp_table}"
    )
    conn.execute(f"DROP TABLE {temp_table}")


# ═══════════════════════════════════════════════════════
# 迁移函数
# ═══════════════════════════════════════════════════════


@register_migration(1, 2)
def _migrate_v1_to_v2(conn: sqlite3.Connection) -> None:
    """Add is_baseline, current revision index, model_attempts, fix fact anchor unique key (DB-5)."""
    # Add is_baseline to writing_shots
    try:
        conn.execute("ALTER TABLE writing_shots ADD COLUMN is_baseline INTEGER NOT NULL DEFAULT 0 CHECK (is_baseline IN (0, 1))")
    except sqlite3.OperationalError:
        pass

    # Add partial unique index for current revision
    try:
        conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_revisions_one_current ON shot_revisions(shot_id) WHERE is_current = 1")
    except sqlite3.OperationalError:
        pass

    # DB-5: Rebuild fact anchor unique constraint (SQLite doesn't support ALTER DROP CONSTRAINT)
    # We create a new table, copy data, drop old, rename
    try:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS writing_fact_anchors_v2 ("
            "anchor_id TEXT PRIMARY KEY, "
            "project_id TEXT NOT NULL REFERENCES projects(project_id), "
            "run_id TEXT REFERENCES writing_sessions(run_id), "
            "shot_id TEXT REFERENCES writing_shots(shot_id), "
            "anchor_type TEXT NOT NULL CHECK (anchor_type IN ("
            "'character_state', 'character_trait', 'object_location', 'object_property', "
            "'event_occurred', 'relationship', 'world_rule', 'timeline', 'knowledge'"
            ")), "
            "anchor_key TEXT NOT NULL, "
            "anchor_value TEXT NOT NULL, "
            "confidence REAL NOT NULL CHECK (confidence BETWEEN 0 AND 1), "
            "pov_scope TEXT DEFAULT NULL, "
            "override_source TEXT CHECK (override_source IN ('universe', 'project_override', 'project_fork')), "
            "contract_clause_ref TEXT, "
            "source_revision_id TEXT REFERENCES shot_revisions(revision_id), "
            "extracted_at TEXT NOT NULL DEFAULT (datetime('now')), "
            "UNIQUE(project_id, anchor_key, source_revision_id)"
            ")"
        )
        # Copy existing data (deduplicate by keeping latest)
        conn.execute(
            "INSERT OR IGNORE INTO writing_fact_anchors_v2 "
            "SELECT * FROM writing_fact_anchors"
        )
        conn.execute("DROP TABLE writing_fact_anchors")
        conn.execute("ALTER TABLE writing_fact_anchors_v2 RENAME TO writing_fact_anchors")
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_anchors_project ON writing_fact_anchors(project_id, run_id)"
        )
    except sqlite3.OperationalError:
        pass

    # Create model_attempts table
    conn.execute(
        "CREATE TABLE IF NOT EXISTS model_attempts ("
        "attempt_id TEXT PRIMARY KEY, "
        "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
        "shot_id TEXT REFERENCES writing_shots(shot_id), "
        "phase TEXT NOT NULL CHECK (phase IN ("
        "'write_generate', 'jury_score', 'fact_extract', 'repair', "
        "'motif_task', 'contract_compile', 'prompt_compile'"
        ")), "
        "model_name TEXT NOT NULL, "
        "idempotency_key TEXT NOT NULL, "
        "request_prompt_hash TEXT NOT NULL, "
        "response_text_hash TEXT, "
        "usage_prompt_tokens INTEGER DEFAULT 0, "
        "usage_completion_tokens INTEGER DEFAULT 0, "
        "usage_total_tokens INTEGER DEFAULT 0, "
        "error_message TEXT, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(idempotency_key)"
        ")"
    )
    try:
        conn.execute("CREATE INDEX IF NOT EXISTS idx_model_attempts_run ON model_attempts(run_id)")
    except sqlite3.OperationalError:
        pass
    try:
        conn.execute("CREATE INDEX IF NOT EXISTS idx_model_attempts_shot ON model_attempts(shot_id)")
    except sqlite3.OperationalError:
        pass


@register_migration(2, 3)
def _migrate_v2_to_v3(conn: sqlite3.Connection) -> None:
    """Add writing_architect_gates table for 4-level cascading gate."""
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_architect_gates ("
        "gate_id TEXT PRIMARY KEY, "
        "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
        "level TEXT NOT NULL CHECK (level IN ('L1', 'L2', 'L3', 'L4')), "
        "scope_key TEXT NOT NULL, "
        "status TEXT NOT NULL CHECK (status IN ('pending', 'passed', 'failed')), "
        "check_result_json JSON, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "updated_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(run_id, level, scope_key)"
        ")"
    )
    try:
        conn.execute("CREATE INDEX IF NOT EXISTS idx_architect_gates_run ON writing_architect_gates(run_id)")
    except sqlite3.OperationalError:
        pass
    try:
        conn.execute("CREATE INDEX IF NOT EXISTS idx_architect_gates_level ON writing_architect_gates(level)")
    except sqlite3.OperationalError:
        pass


@register_migration(3, 4)
def _migrate_v3_to_v4(conn: sqlite3.Connection) -> None:
    """v4: 九评委新维度 + 大纲评估表。"""

    # 1. 更新 writing_jury_scores.dimension CHECK 约束（需重建表）
    try:
        conn.execute("ALTER TABLE writing_jury_scores RENAME TO writing_jury_scores_v3")
        conn.execute(
            "CREATE TABLE writing_jury_scores ("
            "score_id TEXT PRIMARY KEY, "
            "draft_id TEXT NOT NULL REFERENCES writing_drafts(draft_id), "
            "shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id), "
            "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
            "jury_persona TEXT NOT NULL, "
            "phase TEXT NOT NULL CHECK (phase IN ("
            "'independent', 'comparative', 'final'"
            ")), "
            "dimension TEXT NOT NULL CHECK (dimension IN ("
            "'literary_quality', 'narrative_pacing', 'voice_consistency', "
            "'contract_compliance', 'motif_compatibility', 'anti_pattern_avoidance', "
            "'hook_transition', 'character_coherence', 'reader_engagement', "
            "'forbidden_expression', 'reading_fluency'"
            ")), "
            "score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100), "
            "comment TEXT, "
            "attempt_id TEXT NOT NULL, "
            "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
            "UNIQUE(shot_id, draft_id, jury_persona, phase, dimension, attempt_id)"
            ")"
        )
        conn.execute(
            "INSERT INTO writing_jury_scores SELECT * FROM writing_jury_scores_v3"
        )
        conn.execute("DROP TABLE writing_jury_scores_v3")
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_jury_scores_run "
            "ON writing_jury_scores(run_id)"
        )
    except sqlite3.OperationalError:
        pass

    # 2. 新增大纲评估表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_outline_evaluations ("
        "evaluation_id TEXT PRIMARY KEY, "
        "shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id), "
        "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
        "attempt INTEGER NOT NULL DEFAULT 1, "
        "outline_text TEXT NOT NULL, "
        "score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100), "
        "dimensions_json JSON NOT NULL, "
        "issues_json JSON, "
        "suggestions_json JSON, "
        "regenerated INTEGER NOT NULL DEFAULT 0 CHECK (regenerated IN (0, 1)), "
        "new_outline_text TEXT, "
        "model_used TEXT, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_outline_evals_shot "
            "ON writing_outline_evaluations(shot_id)"
        )
    except sqlite3.OperationalError:
        pass


# ═══════════════════════════════════════════════════════
# v4 → v5: ULID shot_id → 复合层级ID
# ═══════════════════════════════════════════════════════


@register_migration(4, 5)
def _migrate_v4_to_v5(conn: sqlite3.Connection) -> None:
    """v5: shot_id 从 ULID 改为复合层级格式 (v01.c02.s03)。

    8层金字塔设计恢复：
    - L2 卷 (volume): v01, v02
    - L4 章 (chapter): c01, c02
    - L5 节 (section): s01, s02  ← writing_shots 的行

    新格式: {layer_key}.s{shot_index:02d}
    示例: v01.c02.s03
    详见 docs/design-8layer-hierarchy.md
    """
    # 1. 构建 old_id → new_id 映射
    rows = conn.execute(
        "SELECT shot_id, layer_key, shot_index FROM writing_shots"
    ).fetchall()

    if not rows:
        return  # 空数据库，无需迁移

    # 检查是否已经是新格式（幂等性）
    sample_id = rows[0][0]  # use index access (not dict) for row_factory compatibility
    if sample_id.startswith("v") and ".s" in sample_id:
        return  # 已经是复合格式

    id_map = {}
    for row in rows:
        old_id = row[0]
        layer_key = row[1]
        shot_index = row[2]
        new_id = f"{layer_key}.s{shot_index:02d}"
        id_map[old_id] = new_id

    # 2. 临时关闭外键约束
    conn.execute("PRAGMA foreign_keys = OFF")

    try:
        # 3. 更新所有 FK 表的 shot_id 列
        fk_tables_with_shot_id = [
            "writing_session_checkpoints",
            "writing_shot_contracts",
            "shot_revisions",
            "writing_drafts",
            "writing_shot_prompts",
            "writing_context_snaps",
            "writing_fact_anchors",
            "writing_motif_instances",
            "writing_jury_scores",
            "writing_repair_audit",
            "writing_exception_events",
            "writing_deviation_notes",
            "writing_outline_evaluations",
            "model_attempts",
        ]

        for table in fk_tables_with_shot_id:
            # 检查表是否存在
            exists = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                (table,),
            ).fetchone()
            if not exists:
                continue
            for old_id, new_id in id_map.items():
                conn.execute(
                    f"UPDATE {table} SET shot_id = ? WHERE shot_id = ?",
                    (new_id, old_id),
                )

        # 4. 更新 writing_motif_tracker 的两个 shot_id 列
        exists = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='writing_motif_tracker'"
        ).fetchone()
        if exists:
            for old_id, new_id in id_map.items():
                conn.execute(
                    "UPDATE writing_motif_tracker "
                    "SET last_used_shot_id = ? WHERE last_used_shot_id = ?",
                    (new_id, old_id),
                )
                conn.execute(
                    "UPDATE writing_motif_tracker "
                    "SET task_generated_for_shot_id = ? WHERE task_generated_for_shot_id = ?",
                    (new_id, old_id),
                )

        # 5. 更新 writing_sessions.current_shot_id
        for old_id, new_id in id_map.items():
            conn.execute(
                "UPDATE writing_sessions SET current_shot_id = ? WHERE current_shot_id = ?",
                (new_id, old_id),
            )

        # 6. 更新 writing_reference_pool.source_shot_id
        exists = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='writing_reference_pool'"
        ).fetchone()
        if exists:
            for old_id, new_id in id_map.items():
                conn.execute(
                    "UPDATE writing_reference_pool "
                    "SET source_shot_id = ? WHERE source_shot_id = ?",
                    (new_id, old_id),
                )

        # 7. 最后更新 writing_shots 主表
        for old_id, new_id in id_map.items():
            conn.execute(
                "UPDATE writing_shots SET shot_id = ? WHERE shot_id = ?",
                (new_id, old_id),
            )

    finally:
        # 8. 恢复外键约束
        conn.execute("PRAGMA foreign_keys = ON")


# ═══════════════════════════════════════════════════════
# v5 → v6: 悬疑引擎 D-25
# ═══════════════════════════════════════════════════════


@register_migration(5, 6)
def _migrate_v5_to_v6(conn: sqlite3.Connection) -> None:
    """v6: 悬疑引擎 D-25 — 新增 writing_information_gaps 表 + 扩展 jury 维度。

    新增:
    - writing_information_gaps: 信息差生命周期追踪
    - writing_jury_scores.dimension 新增 'suspense_effectiveness'
    """
    # 1. 创建 writing_information_gaps 表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_information_gaps ("
        "gap_id TEXT PRIMARY KEY, "
        "project_id TEXT NOT NULL REFERENCES projects(project_id), "
        "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
        "description TEXT NOT NULL, "
        "reader_knows TEXT NOT NULL, "
        "character_knows TEXT NOT NULL, "
        "created_shot_id TEXT REFERENCES writing_shots(shot_id), "
        "reinforced_shot_ids TEXT DEFAULT '[]', "
        "revealed_shot_id TEXT REFERENCES writing_shots(shot_id), "
        "next_gap_id TEXT REFERENCES writing_information_gaps(gap_id), "
        "status TEXT NOT NULL DEFAULT 'pending' "
        "CHECK (status IN ('pending', 'active', 'reinforced', 'revealed', 'resolved')), "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "updated_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_info_gaps_run "
            "ON writing_information_gaps(run_id)"
        )
    except sqlite3.OperationalError:
        pass
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_info_gaps_status "
            "ON writing_information_gaps(status)"
        )
    except sqlite3.OperationalError:
        pass

    # 2. 更新 writing_jury_scores.dimension CHECK 约束（新增 suspense_effectiveness）
    try:
        conn.execute("ALTER TABLE writing_jury_scores RENAME TO writing_jury_scores_v5")
        conn.execute(
            "CREATE TABLE writing_jury_scores ("
            "score_id TEXT PRIMARY KEY, "
            "draft_id TEXT NOT NULL REFERENCES writing_drafts(draft_id), "
            "shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id), "
            "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
            "jury_persona TEXT NOT NULL, "
            "phase TEXT NOT NULL CHECK (phase IN ("
            "'independent', 'comparative', 'final'"
            ")), "
            "dimension TEXT NOT NULL CHECK (dimension IN ("
            "'literary_quality', 'narrative_pacing', 'voice_consistency', "
            "'contract_compliance', 'motif_compatibility', 'anti_pattern_avoidance', "
            "'hook_transition', 'character_coherence', 'reader_engagement', "
            "'forbidden_expression', 'reading_fluency', 'suspense_effectiveness'"
            ")), "
            "score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100), "
            "comment TEXT, "
            "attempt_id TEXT NOT NULL, "
            "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
            "UNIQUE(shot_id, draft_id, jury_persona, phase, dimension, attempt_id)"
            ")"
        )
        conn.execute(
            "INSERT INTO writing_jury_scores SELECT * FROM writing_jury_scores_v5"
        )
        conn.execute("DROP TABLE writing_jury_scores_v5")
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_jury_scores_run "
            "ON writing_jury_scores(run_id)"
        )
    except sqlite3.OperationalError:
        pass


# ═══════════════════════════════════════════════════════
# v6 → v7: AI 架构师·全书节奏统筹 — 章级节奏表
# ═══════════════════════════════════════════════════════


@register_migration(6, 7)
def _migrate_v6_to_v7(conn: sqlite3.Connection) -> None:
    """v7: AI 架构师 L1 — 新增 writing_chapter_rhythms 表。

    存储每章的节奏分析结果（每个 shot 的 narrative_phase + deviation_budget）。
    """
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_chapter_rhythms ("
        "rhythm_id TEXT PRIMARY KEY, "
        "chapter_key TEXT NOT NULL, "
        "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
        "rhythm_map_json JSON NOT NULL, "
        "validation_json JSON, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_chapter_rhythms_run "
            "ON writing_chapter_rhythms(run_id)"
        )
    except sqlite3.OperationalError:
        pass
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_chapter_rhythms_chapter "
            "ON writing_chapter_rhythms(chapter_key)"
        )
    except sqlite3.OperationalError:
        pass


@register_migration(7, 8)
def _migrate_v7_to_v8(conn: sqlite3.Connection) -> None:
    """v8: 三棵树架构 (ARCH-12) — 新增 tree_nodes / contract_versions / story_content / execution_records。

    4 张新表支撑契约树、故事树、执行树。详见 docs/design-3tree-architecture.md。
    """
    # tree_nodes — 三棵树共用骨架
    conn.execute(
        "CREATE TABLE IF NOT EXISTS tree_nodes ("
        "node_id TEXT PRIMARY KEY, "
        "tree_type TEXT NOT NULL "
        "CHECK (tree_type IN ('contract', 'story', 'execution')), "
        "project_id TEXT NOT NULL REFERENCES projects(project_id), "
        "parent_id TEXT REFERENCES tree_nodes(node_id), "
        "layer_key TEXT NOT NULL, "
        "node_level TEXT NOT NULL "
        "CHECK (node_level IN ('L0','L1','L2','L3','L4','L5','L6','L7')), "
        "node_name TEXT, "
        "sort_order INTEGER DEFAULT 0, "
        "design_status TEXT DEFAULT 'pending' "
        "CHECK (design_status IN "
        "('pending','drafting','review','confirmed','locked')), "
        "quality_color TEXT "
        "CHECK (quality_color IN ('green','yellow','red','gray',NULL)), "
        "node_intent TEXT, "
        "run_id TEXT, "
        "source_version_id TEXT, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "updated_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(tree_type, project_id, layer_key, run_id)"
        ")"
    )
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_tree_nodes_parent "
            "ON tree_nodes(parent_id)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_tree_nodes_lookup "
            "ON tree_nodes(tree_type, project_id, layer_key)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_tree_nodes_run "
            "ON tree_nodes(run_id) WHERE run_id IS NOT NULL"
        )
    except sqlite3.OperationalError:
        pass

    # contract_versions — 契约树正文，版本化
    conn.execute(
        "CREATE TABLE IF NOT EXISTS contract_versions ("
        "version_id TEXT PRIMARY KEY, "
        "node_id TEXT NOT NULL REFERENCES tree_nodes(node_id), "
        "version INTEGER NOT NULL, "
        "parent_version_id TEXT REFERENCES contract_versions(version_id), "
        "is_collapsed INTEGER NOT NULL DEFAULT 0, "
        "contract_body_json JSON NOT NULL, "
        "change_reason TEXT, "
        "created_by TEXT NOT NULL DEFAULT 'human' "
        "CHECK (created_by IN ('human', 'ai', 'upgrade')), "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(node_id, version)"
        ")"
    )
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_contract_versions_node "
            "ON contract_versions(node_id)"
        )
    except sqlite3.OperationalError:
        pass

    # story_content — 故事树正文
    conn.execute(
        "CREATE TABLE IF NOT EXISTS story_content ("
        "content_id TEXT PRIMARY KEY, "
        "node_id TEXT NOT NULL REFERENCES tree_nodes(node_id), "
        "content_body_json JSON NOT NULL, "
        "updated_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_story_content_node "
            "ON story_content(node_id)"
        )
    except sqlite3.OperationalError:
        pass

    # execution_records — 执行树正文
    conn.execute(
        "CREATE TABLE IF NOT EXISTS execution_records ("
        "record_id TEXT PRIMARY KEY, "
        "node_id TEXT NOT NULL REFERENCES tree_nodes(node_id), "
        "run_id TEXT NOT NULL, "
        "prompt_snapshot_id TEXT, "
        "draft_ids_json JSON, "
        "selected_draft_id TEXT, "
        "revision_id TEXT REFERENCES shot_revisions(revision_id), "
        "quality_result_json JSON, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_execution_records_node "
            "ON execution_records(node_id)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_execution_records_run "
            "ON execution_records(run_id)"
        )
    except sqlite3.OperationalError:
        pass


# ═══════════════════════════════════════════════════════
# v8 → v9: L0 全书宪法 (ARCH-4)
# ═══════════════════════════════════════════════════════


@register_migration(8, 9)
def _migrate_v8_to_v9(conn: sqlite3.Connection) -> None:
    """v9: L0 全书宪法 (ARCH-4) — 新增 writing_book_constitutions 表 + meta_contract 指针。

    writing_book_constitutions: 全书节奏治理参数（arc_shape, volume_map, motif_lifecycle, deviation）。
    writing_meta_contract.constitution_version_id: 指向生成此契约的宪法版本。
    """
    # 1. 创建 writing_book_constitutions 表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_book_constitutions ("
        "constitution_id TEXT PRIMARY KEY, "
        "project_id TEXT NOT NULL REFERENCES projects(project_id), "
        "version INTEGER NOT NULL DEFAULT 1, "
        "arc_shape TEXT, "
        "tension_peak_chapter TEXT, "
        "tension_valley_chapters_json JSON, "
        "volume_map_json JSON, "
        "chapter_roles_json JSON, "
        "motif_lifecycle_json JSON, "
        "global_deviation_mean REAL, "
        "global_deviation_range_json JSON, "
        "status TEXT NOT NULL DEFAULT 'draft' "
        "CHECK (status IN ('draft', 'human_review', 'confirmed', 'locked')), "
        "confirmed_at TEXT, "
        "locked_at TEXT, "
        "source_outline_hash TEXT, "
        "llm_model_ref TEXT, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "updated_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(project_id, version)"
        ")"
    )
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_book_constitutions_project "
            "ON writing_book_constitutions(project_id)"
        )
    except sqlite3.OperationalError:
        pass

    # 2. 添加 constitution_version_id 到 writing_meta_contract
    try:
        conn.execute(
            "ALTER TABLE writing_meta_contract "
            "ADD COLUMN constitution_version_id TEXT "
            "REFERENCES writing_book_constitutions(constitution_id)"
        )
    except sqlite3.OperationalError:
        pass  # 列已存在


@register_migration(9, 10)
def _migrate_v9_to_v10(conn: sqlite3.Connection) -> None:
    """v10: L0.5 卷部节奏 (ARCH-5) — 新增 writing_volume_rhythms 表。"""
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_volume_rhythms ("
        "rhythm_id TEXT PRIMARY KEY, "
        "volume_key TEXT NOT NULL, "
        "project_id TEXT NOT NULL REFERENCES projects(project_id), "
        "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
        "rhythm_json JSON NOT NULL, "
        "validation_json JSON, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_volume_rhythms_run "
            "ON writing_volume_rhythms(run_id)"
        )
    except sqlite3.OperationalError:
        pass
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_volume_rhythms_volume "
            "ON writing_volume_rhythms(volume_key)"
        )
    except sqlite3.OperationalError:
        pass


@register_migration(10, 11)
def _migrate_v10_to_v11(conn: sqlite3.Connection) -> None:
    """v11: D-25 悬疑可靠性闭环 — writing_shots 新增 failure_signature_json 列。"""
    try:
        conn.execute(
            "ALTER TABLE writing_shots "
            "ADD COLUMN failure_signature_json JSON"
        )
    except sqlite3.OperationalError:
        pass  # 列已存在


@register_migration(11, 12)
def _migrate_v11_to_v12(conn: sqlite3.Connection) -> None:
    """v12: ARCH-10 风格偏好学习 — 新增 writing_style_preferences 表 + writing_drafts 扩展列。"""
    try:
        conn.execute("""
            CREATE TABLE writing_style_preferences (
                preference_id     TEXT PRIMARY KEY,
                shot_id           TEXT NOT NULL REFERENCES writing_shots(shot_id),
                draft_id          TEXT NOT NULL REFERENCES writing_drafts(draft_id),
                project_id        TEXT NOT NULL REFERENCES projects(project_id),
                run_id            TEXT NOT NULL REFERENCES writing_sessions(run_id),
                persona           TEXT NOT NULL,
                model_ref         TEXT,
                temperature       REAL NOT NULL DEFAULT 0.8,
                style_direction   TEXT NOT NULL,
                score             REAL,
                created_at        TEXT NOT NULL DEFAULT (datetime('now'))
            )
        """)
        conn.execute("CREATE INDEX idx_style_prefs_run ON writing_style_preferences(run_id)")
        conn.execute("CREATE INDEX idx_style_prefs_project ON writing_style_preferences(project_id)")
        conn.execute("CREATE INDEX idx_style_prefs_persona ON writing_style_preferences(persona)")
    except sqlite3.OperationalError:
        pass  # 表已存在

    try:
        conn.execute("ALTER TABLE writing_drafts ADD COLUMN model_ref TEXT")
    except sqlite3.OperationalError:
        pass
    try:
        conn.execute("ALTER TABLE writing_drafts ADD COLUMN temperature REAL DEFAULT 0.8")
    except sqlite3.OperationalError:
        pass
    try:
        conn.execute("ALTER TABLE writing_drafts ADD COLUMN style_direction TEXT")
    except sqlite3.OperationalError:
        pass


@register_migration(13, 14)
def _migrate_v13_to_v14(conn: sqlite3.Connection) -> None:
    """v14: CREATIVE-1 意外价值维度 — 更新 writing_jury_scores.dimension CHECK 约束。"""
    try:
        conn.execute("ALTER TABLE writing_jury_scores RENAME TO writing_jury_scores_v13")
        conn.execute(
            "CREATE TABLE writing_jury_scores ("
            "score_id TEXT PRIMARY KEY, "
            "draft_id TEXT NOT NULL REFERENCES writing_drafts(draft_id), "
            "shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id), "
            "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
            "jury_persona TEXT NOT NULL, "
            "phase TEXT NOT NULL CHECK (phase IN ("
            "'independent', 'comparative', 'final'"
            ")), "
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
        conn.execute(
            "INSERT INTO writing_jury_scores SELECT * FROM writing_jury_scores_v13"
        )
        conn.execute("DROP TABLE writing_jury_scores_v13")
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_jury_scores_run "
            "ON writing_jury_scores(run_id)"
        )
    except sqlite3.OperationalError:
        pass


@register_migration(12, 13)
def _migrate_v12_to_v13(conn: sqlite3.Connection) -> None:
    """v13: ARCH-11 反契约沙盒 — 新增 writing_anti_contract_reviews 表。"""
    try:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS writing_anti_contract_reviews ("
            "review_id TEXT PRIMARY KEY, "
            "shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id), "
            "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
            "deviant_draft_id TEXT NOT NULL REFERENCES writing_drafts(draft_id), "
            "deviant_score REAL NOT NULL, "
            "compliant_mean REAL NOT NULL, "
            "advantage REAL NOT NULL, "
            "soft_constraints_json JSON NOT NULL, "
            "human_decision TEXT NOT NULL DEFAULT 'pending' "
            "CHECK (human_decision IN ('pending', 'accept', 'reject', 'conditional')), "
            "human_notes TEXT, "
            "reviewed_at TEXT, "
            "created_at TEXT NOT NULL DEFAULT (datetime('now'))"
            ")"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_anti_contract_reviews_run "
            "ON writing_anti_contract_reviews(run_id)"
        )
    except sqlite3.OperationalError:
        pass  # 表已存在


@register_migration(14, 15)
def _migrate_v14_to_v15(conn: sqlite3.Connection) -> None:
    """v15: CREATIVE-2 polish 阶段 — 扩展 revision operation 与 model audit phase。"""
    try:
        conn.execute("ALTER TABLE shot_revisions RENAME TO shot_revisions_v14")
        conn.execute(
            "CREATE TABLE shot_revisions ("
            "revision_id TEXT PRIMARY KEY, "
            "shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id), "
            "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
            "parent_revision_id TEXT REFERENCES shot_revisions(revision_id), "
            "contract_id TEXT NOT NULL REFERENCES writing_shot_contracts(contract_id), "
            "revision_sequence INTEGER NOT NULL, "
            "operation TEXT NOT NULL CHECK (operation IN ("
            "'write_generate', 'write_placeholder', 'write_repair', "
            "'write_redo', 'write_polish'"
            ")), "
            "text TEXT NOT NULL, "
            "text_hash_normalized TEXT NOT NULL, "
            "writer_persona TEXT, "
            "jury_scores_json JSON, "
            "gate_result_json JSON, "
            "is_current BOOLEAN NOT NULL DEFAULT 0, "
            "attempt_id TEXT NOT NULL, "
            "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
            "UNIQUE(shot_id, operation, attempt_id)"
            ")"
        )
        conn.execute(
            "INSERT INTO shot_revisions ("
            "revision_id, shot_id, run_id, parent_revision_id, contract_id, "
            "revision_sequence, operation, text, text_hash_normalized, writer_persona, "
            "jury_scores_json, gate_result_json, is_current, attempt_id, created_at"
            ") SELECT "
            "revision_id, shot_id, run_id, parent_revision_id, contract_id, "
            "revision_sequence, operation, text, text_hash_normalized, writer_persona, "
            "jury_scores_json, gate_result_json, is_current, attempt_id, created_at "
            "FROM shot_revisions_v14"
        )
        conn.execute("DROP TABLE shot_revisions_v14")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_revisions_shot ON shot_revisions(shot_id)")
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_revisions_one_current "
            "ON shot_revisions(shot_id) WHERE is_current = 1"
        )
    except sqlite3.OperationalError:
        pass


@register_migration(15, 16)
def _migrate_v15_to_v16(conn: sqlite3.Connection) -> None:
    """v16: 扩展 model_attempts.phase，保留架构/大纲模型调用审计。"""
    try:
        conn.execute("ALTER TABLE model_attempts RENAME TO model_attempts_v15")
        conn.execute(
            "CREATE TABLE model_attempts ("
            "attempt_id TEXT PRIMARY KEY, "
            "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
            "shot_id TEXT REFERENCES writing_shots(shot_id), "
            "phase TEXT NOT NULL CHECK (phase IN ("
            "'write_generate', 'jury_score', 'fact_extract', 'repair', "
            "'motif_task', 'contract_compile', 'prompt_compile', 'polish', "
            "'outline_evaluate', 'constitution_generate', "
            "'architect_chapter_rhythm', 'architect_chapter_rhythm_retry', "
            "'architect_volume_rhythm', 'architect_volume_rhythm_retry'"
            ")), "
            "model_name TEXT NOT NULL, "
            "idempotency_key TEXT NOT NULL, "
            "request_prompt_hash TEXT NOT NULL, "
            "response_text_hash TEXT, "
            "usage_prompt_tokens INTEGER DEFAULT 0, "
            "usage_completion_tokens INTEGER DEFAULT 0, "
            "usage_total_tokens INTEGER DEFAULT 0, "
            "error_message TEXT, "
            "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
            "UNIQUE(idempotency_key)"
            ")"
        )
        conn.execute(
            "INSERT INTO model_attempts ("
            "attempt_id, run_id, shot_id, phase, model_name, idempotency_key, "
            "request_prompt_hash, response_text_hash, usage_prompt_tokens, "
            "usage_completion_tokens, usage_total_tokens, error_message, created_at"
            ") SELECT "
            "attempt_id, run_id, shot_id, phase, model_name, idempotency_key, "
            "request_prompt_hash, response_text_hash, usage_prompt_tokens, "
            "usage_completion_tokens, usage_total_tokens, error_message, created_at "
            "FROM model_attempts_v15"
        )
        conn.execute("DROP TABLE model_attempts_v15")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_model_attempts_run ON model_attempts(run_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_model_attempts_shot ON model_attempts(shot_id)")
    except sqlite3.OperationalError:
        pass


@register_migration(16, 17)
def _migrate_v16_to_v17(conn: sqlite3.Connection) -> None:
    """v17: 分层裁判维度 — 扩展 writing_jury_scores.dimension CHECK 约束。"""
    try:
        conn.execute("ALTER TABLE writing_jury_scores RENAME TO writing_jury_scores_v16")
        conn.execute(
            "CREATE TABLE writing_jury_scores ("
            "score_id TEXT PRIMARY KEY, "
            "draft_id TEXT NOT NULL REFERENCES writing_drafts(draft_id), "
            "shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id), "
            "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
            "jury_persona TEXT NOT NULL, "
            "phase TEXT NOT NULL CHECK (phase IN ("
            "'independent', 'comparative', 'final'"
            ")), "
            "dimension TEXT NOT NULL CHECK (dimension IN ("
            "'literary_quality', 'narrative_pacing', 'voice_consistency', "
            "'contract_compliance', 'motif_compatibility', 'anti_pattern_avoidance', "
            "'hook_transition', 'character_coherence', 'reader_engagement', "
            "'forbidden_expression', 'reading_fluency', 'suspense_effectiveness', "
            "'unexpected_value', 'hard_rule_compliance', 'language_texture', "
            "'scene_specificity', 'emotional_progression', 'character_believability', "
            "'dialogue_subtext', 'pacing_control', 'motif_theme_fit', 'chapter_continuity'"
            ")), "
            "score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100), "
            "comment TEXT, "
            "attempt_id TEXT NOT NULL, "
            "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
            "UNIQUE(shot_id, draft_id, jury_persona, phase, dimension, attempt_id)"
            ")"
        )
        conn.execute(
            "INSERT INTO writing_jury_scores SELECT * FROM writing_jury_scores_v16"
        )
        conn.execute("DROP TABLE writing_jury_scores_v16")
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_jury_scores_run "
            "ON writing_jury_scores(run_id)"
        )
    except sqlite3.OperationalError:
        pass


@register_migration(17, 18)
def _migrate_v17_to_v18(conn: sqlite3.Connection) -> None:
    """v18: 章节人工审稿 canonical 状态 — 新增 writing_chapter_reviews 表。"""
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_chapter_reviews ("
        "review_id TEXT PRIMARY KEY, "
        "project_id TEXT NOT NULL REFERENCES projects(project_id), "
        "chapter_key TEXT NOT NULL, "
        "run_id TEXT REFERENCES writing_sessions(run_id), "
        "status TEXT NOT NULL CHECK (status IN ("
        "'accepted', 'needs_revision', 'rejected', 'superseded'"
        ")), "
        "review_text TEXT, "
        "notes TEXT, "
        "exported_path TEXT, "
        "shot_stats_json JSON NOT NULL DEFAULT '[]', "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "updated_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(project_id, chapter_key, run_id)"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_chapter_reviews_project_chapter "
        "ON writing_chapter_reviews(project_id, chapter_key)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_chapter_reviews_status "
        "ON writing_chapter_reviews(status)"
    )
    conn.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_chapter_reviews_one_accepted "
        "ON writing_chapter_reviews(project_id, chapter_key) "
        "WHERE status = 'accepted'"
    )


@register_migration(18, 19)
def _migrate_v18_to_v19(conn: sqlite3.Connection) -> None:
    """v19: 分离 logical shot 与 run attempt shot 主键。"""
    cols = {
        row[1]
        for row in conn.execute("PRAGMA table_info(writing_shots)").fetchall()
    }
    if "logical_shot_id" not in cols:
        conn.execute("ALTER TABLE writing_shots ADD COLUMN logical_shot_id TEXT")
    conn.execute(
        "UPDATE writing_shots SET logical_shot_id = shot_id "
        "WHERE logical_shot_id IS NULL OR logical_shot_id = ''"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_shots_logical "
        "ON writing_shots(project_id, layer_key, logical_shot_id)"
    )
    conn.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_shots_run_logical_unique "
        "ON writing_shots(run_id, logical_shot_id)"
    )


@register_migration(19, 20)
def _migrate_v19_to_v20(conn: sqlite3.Connection) -> None:
    """v20: 全书编排批次 — 新增 writing_book_runs 与 chapter 状态表。"""
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_book_runs ("
        "book_run_id TEXT PRIMARY KEY, "
        "project_id TEXT NOT NULL REFERENCES projects(project_id), "
        "from_chapter TEXT NOT NULL, "
        "to_chapter TEXT NOT NULL, "
        "status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ("
        "'planned', 'running', 'completed', 'failed', 'aborted'"
        ")), "
        "total_chapters INTEGER NOT NULL DEFAULT 0 CHECK (total_chapters >= 0), "
        "completed_chapters INTEGER NOT NULL DEFAULT 0 CHECK (completed_chapters >= 0), "
        "failed_chapters INTEGER NOT NULL DEFAULT 0 CHECK (failed_chapters >= 0), "
        "current_chapter TEXT, "
        "options_json JSON NOT NULL DEFAULT '{}', "
        "report_json JSON NOT NULL DEFAULT '{}', "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "updated_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_book_runs_project "
        "ON writing_book_runs(project_id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_book_runs_status "
        "ON writing_book_runs(status)"
    )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_book_run_chapters ("
        "book_run_chapter_id TEXT PRIMARY KEY, "
        "book_run_id TEXT NOT NULL REFERENCES writing_book_runs(book_run_id) "
        "ON DELETE CASCADE, "
        "project_id TEXT NOT NULL REFERENCES projects(project_id), "
        "chapter_key TEXT NOT NULL, "
        "chapter_order INTEGER NOT NULL, "
        "run_id TEXT REFERENCES writing_sessions(run_id), "
        "status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ("
        "'planned', 'setup_ready', 'running', 'completed', "
        "'failed', 'skipped', 'context_stale'"
        ")), "
        "setup_path TEXT, "
        "exported_path TEXT, "
        "failure_reason TEXT, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "updated_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(book_run_id, chapter_key)"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_book_run_chapters_book "
        "ON writing_book_run_chapters(book_run_id, chapter_order)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_book_run_chapters_run "
        "ON writing_book_run_chapters(run_id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_book_run_chapters_status "
        "ON writing_book_run_chapters(status)"
    )


@register_migration(20, 21)
def _migrate_v20_to_v21(conn: sqlite3.Connection) -> None:
    """v21: 全程审计 — 事件、setup 快照、草稿资格、失败归因。"""
    _create_v21_audit_tables(conn)
    if _table_exists(conn, "writing_outline_evaluations"):
        columns = {
            row[1]
            for row in conn.execute("PRAGMA table_info(writing_outline_evaluations)").fetchall()
        }
        if "threshold" not in columns:
            conn.execute(
                "ALTER TABLE writing_outline_evaluations "
                "ADD COLUMN threshold INTEGER NOT NULL DEFAULT 70 "
                "CHECK (threshold BETWEEN 0 AND 100)"
            )
        if "passed" not in columns:
            conn.execute(
                "ALTER TABLE writing_outline_evaluations "
                "ADD COLUMN passed INTEGER NOT NULL DEFAULT 0 "
                "CHECK (passed IN (0, 1))"
            )
        conn.execute(
            "UPDATE writing_outline_evaluations "
            "SET passed = CASE WHEN score >= threshold THEN 1 ELSE 0 END"
        )
    if _table_exists(conn, "model_attempts"):
        model_columns = {
            row[1]
            for row in conn.execute("PRAGMA table_info(model_attempts)").fetchall()
        }
        if "request_prompt_text" not in model_columns:
            conn.execute("ALTER TABLE model_attempts ADD COLUMN request_prompt_text TEXT")
        if "response_text" not in model_columns:
            conn.execute("ALTER TABLE model_attempts ADD COLUMN response_text TEXT")


@register_migration(21, 22)
def _migrate_v21_to_v22(conn: sqlite3.Connection) -> None:
    """v22: 契约审计 — writing_audit_events.stage 增加 contract。"""
    _rebuild_writing_audit_events_with_contract_stage(conn)


@register_migration(22, 23)
def _migrate_v22_to_v23(conn: sqlite3.Connection) -> None:
    """v23: 配置项 DB 强制化 — 元契约结构化表，替代 layers_json 中的 AI 写入部分。

    新增 6 张表：
    - writing_project_identity: 项目身份（title, genre, era, language）
    - writing_hard_boundaries: 硬边界（forbidden_phrases, deprecated_aliases 等）
    - writing_narrative_voice: 叙事声音（pov_mode, pov_characters, tense, narrator_type）
    - writing_style_locks: 风格锁（max_paragraph_chars, dialogue_ratio, anti_patterns 等）
    - writing_suspense_blueprint: 悬疑蓝图（preset, global_question）
    - writing_chapter_tension_arc: 章节张力弧线（tension_target, suspense_role 等）

    所有字段 NOT NULL + CHECK 约束，AI 无法绕过。
    """
    _create_v23_config_tables(conn)


def _create_v23_config_tables(conn: sqlite3.Connection) -> None:
    """Create all v23 structured configuration tables."""

    # ═══ 项目身份 ═══
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_project_identity ("
        "identity_id     TEXT PRIMARY KEY, "
        "project_id      TEXT NOT NULL REFERENCES projects(project_id), "
        "title           TEXT NOT NULL CHECK(length(title) > 0), "
        "author          TEXT NOT NULL CHECK(length(author) > 0), "
        "genre_tags      TEXT NOT NULL, "
        "era             TEXT NOT NULL CHECK(length(era) > 0), "
        "language        TEXT NOT NULL DEFAULT 'zh-CN', "
        "total_chapters  INTEGER NOT NULL CHECK(total_chapters > 0), "
        "created_at      TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_project_identity_project "
        "ON writing_project_identity(project_id)"
    )

    # ═══ 硬边界 ═══
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_hard_boundaries ("
        "boundary_id         TEXT PRIMARY KEY, "
        "project_id          TEXT NOT NULL REFERENCES projects(project_id), "
        "forbidden_phrases   TEXT NOT NULL DEFAULT '[]', "
        "forbidden_topics    TEXT NOT NULL DEFAULT '[]', "
        "deprecated_aliases  TEXT NOT NULL DEFAULT '{}', "
        "world_rules         TEXT NOT NULL DEFAULT '[]', "
        "characters_alive    TEXT NOT NULL DEFAULT '[]', "
        "created_at          TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_hard_boundaries_project "
        "ON writing_hard_boundaries(project_id)"
    )

    # ═══ 叙事声音 ═══
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_narrative_voice ("
        "voice_id        TEXT PRIMARY KEY, "
        "project_id      TEXT NOT NULL REFERENCES projects(project_id), "
        "pov_mode        TEXT NOT NULL CHECK(pov_mode IN ("
                        "'first_person','third_limited','third_omniscient',"
                        "'multi_pov','free_indirect')), "
        "pov_characters  TEXT NOT NULL, "
        "tense           TEXT NOT NULL CHECK(tense IN ('past','present','mixed')), "
        "narrator_type   TEXT NOT NULL CHECK(narrator_type IN ("
                        "'character','invisible','unreliable','choral')), "
        "created_at      TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_narrative_voice_project "
        "ON writing_narrative_voice(project_id)"
    )

    # ═══ 风格锁 ═══
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_style_locks ("
        "lock_id                 TEXT PRIMARY KEY, "
        "project_id              TEXT NOT NULL REFERENCES projects(project_id), "
        "max_paragraph_chars     INTEGER CHECK(max_paragraph_chars > 0), "
        "max_sentence_chars      INTEGER CHECK(max_sentence_chars > 0), "
        "dialogue_ratio_min      REAL CHECK(dialogue_ratio_min BETWEEN 0 AND 1), "
        "dialogue_ratio_max      REAL CHECK(dialogue_ratio_max BETWEEN 0 AND 1), "
        "sensory_density         TEXT CHECK(sensory_density IN ("
                                "'sparse','normal','dense')), "
        "anti_patterns           TEXT NOT NULL DEFAULT '[]', "
        "created_at              TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_style_locks_project "
        "ON writing_style_locks(project_id)"
    )

    # ═══ 悬疑蓝图 ═══
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_suspense_blueprint ("
        "blueprint_id    TEXT PRIMARY KEY, "
        "project_id      TEXT NOT NULL REFERENCES projects(project_id), "
        "preset          TEXT NOT NULL CHECK(preset IN ("
                        "'literary_tension','institutional_suspense',"
                        "'psychological_thriller','whodunit','slow_burn')), "
        "global_question TEXT NOT NULL CHECK(length(global_question) > 5), "
        "created_at      TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_suspense_blueprint_project "
        "ON writing_suspense_blueprint(project_id)"
    )

    # ═══ 章节张力弧线 ═══
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_chapter_tension_arc ("
        "arc_id          TEXT PRIMARY KEY, "
        "blueprint_id    TEXT NOT NULL REFERENCES writing_suspense_blueprint(blueprint_id), "
        "chapter_key     TEXT NOT NULL, "
        "tension_target  INTEGER NOT NULL CHECK(tension_target BETWEEN 0 AND 100), "
        "suspense_role   TEXT NOT NULL CHECK(suspense_role IN ("
                        "'setup','escalation','peak','payoff','breather')), "
        "reader_retention TEXT NOT NULL DEFAULT '', "
        "main_engine     TEXT NOT NULL DEFAULT '', "
        "created_at      TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(blueprint_id, chapter_key)"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_tension_arc_blueprint "
        "ON writing_chapter_tension_arc(blueprint_id)"
    )


@register_migration(23, 24)
def _migrate_v23_to_v24(conn: sqlite3.Connection) -> None:
    """v24: Shot 契约结构化表 — 新增 writing_shot_must_land / writing_shot_anti_write / writing_shot_narrative_params。

    替代 writing_shot_contracts 中 must_land_json / anti_write_json / contract_json 的 AI 写入部分。
    所有字段 NOT NULL + CHECK 约束，AI 无法绕过。
    """
    _create_v24_shot_tables(conn)


def _create_v24_shot_tables(conn: sqlite3.Connection) -> None:
    """Create all v24 shot-level structured tables."""

    # ═══ Shot must_land ═══
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_shot_must_land ("
        "must_land_id    TEXT PRIMARY KEY, "
        "contract_id     TEXT NOT NULL REFERENCES writing_shot_contracts(contract_id), "
        "title           TEXT NOT NULL CHECK(length(title) > 0), "
        "beats           TEXT NOT NULL CHECK(length(beats) > 0), "
        "event_text      TEXT NOT NULL CHECK(length(event_text) > 0), "
        "pov_character   TEXT NOT NULL DEFAULT '', "
        "created_at      TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(contract_id)"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_shot_must_land_contract "
        "ON writing_shot_must_land(contract_id)"
    )

    # ═══ Shot anti_write ═══
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_shot_anti_write ("
        "anti_write_id   TEXT PRIMARY KEY, "
        "contract_id     TEXT NOT NULL REFERENCES writing_shot_contracts(contract_id), "
        "pov_only        TEXT NOT NULL DEFAULT '', "
        "forbidden_words TEXT NOT NULL DEFAULT '[]', "
        "forbidden_facts TEXT NOT NULL DEFAULT '[]', "
        "created_at      TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(contract_id)"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_shot_anti_write_contract "
        "ON writing_shot_anti_write(contract_id)"
    )

    # ═══ Shot narrative params ═══
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_shot_narrative_params ("
        "params_id           TEXT PRIMARY KEY, "
        "contract_id         TEXT NOT NULL REFERENCES writing_shot_contracts(contract_id), "
        "narrative_phase     TEXT CHECK(narrative_phase IN ("
                                "'opening','rising','complication','crisis','climax','resolution')), "
        "sensory_pressure    TEXT CHECK(sensory_pressure IN ("
                                "'low','normal','heightened','overwhelming')), "
        "deviation_budget    INTEGER CHECK(deviation_budget BETWEEN 0 AND 100), "
        "dominant_sense      TEXT CHECK(dominant_sense IN ("
                                "'visual','auditory','tactile','olfactory','gustatory','kinesthetic')), "
        "entry_mood          TEXT NOT NULL DEFAULT '', "
        "hard_facts          TEXT NOT NULL DEFAULT '[]', "
        "soft_constraints    TEXT NOT NULL DEFAULT '[]', "
        "reference           TEXT NOT NULL DEFAULT '', "
        "exit_to             TEXT NOT NULL DEFAULT '', "
        "motif_tasks         TEXT NOT NULL DEFAULT '{}', "
        "created_at          TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(contract_id)"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_shot_narrative_params_contract "
        "ON writing_shot_narrative_params(contract_id)"
    )


def _table_exists(conn: sqlite3.Connection, table_name: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (table_name,),
    ).fetchone() is not None


def _create_v21_audit_tables(conn: sqlite3.Connection) -> None:
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_audit_events ("
        "event_id TEXT PRIMARY KEY, "
        "project_id TEXT REFERENCES projects(project_id), "
        "run_id TEXT REFERENCES writing_sessions(run_id), "
        "session_id TEXT REFERENCES writing_sessions(session_id), "
        "shot_id TEXT REFERENCES writing_shots(shot_id), "
        "stage TEXT NOT NULL CHECK (stage IN ("
        "'init', 'contract', 'setup', 'run', 'outline', 'outline_gate', 'prompt', "
        "'writer', 'gate1', 'hard_rule', 'type_gate', 'literary_jury', "
        "'jury_unavailable', 'gate2', 'l4', 'l3', 'l2', 'l1', 'export', 'review', "
        "'repair', 'resume', 'book_run'"
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
        "CREATE INDEX IF NOT EXISTS idx_audit_events_run "
        "ON writing_audit_events(run_id, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_audit_events_shot "
        "ON writing_audit_events(shot_id, stage)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_audit_events_failure "
        "ON writing_audit_events(failure_category)"
    )

    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_setup_snapshots ("
        "setup_id TEXT PRIMARY KEY, "
        "project_id TEXT NOT NULL REFERENCES projects(project_id), "
        "run_id TEXT REFERENCES writing_sessions(run_id), "
        "chapter_key TEXT NOT NULL, "
        "meta_contract_id TEXT REFERENCES writing_meta_contract(meta_contract_id), "
        "source_path TEXT, "
        "setup_hash TEXT NOT NULL, "
        "setup_json JSON NOT NULL, "
        "status TEXT NOT NULL DEFAULT 'ready', "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(project_id, chapter_key, setup_hash)"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_setup_snapshots_project_chapter "
        "ON writing_setup_snapshots(project_id, chapter_key)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_setup_snapshots_run "
        "ON writing_setup_snapshots(run_id)"
    )

    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_draft_eligibility ("
        "eligibility_id TEXT PRIMARY KEY, "
        "draft_id TEXT NOT NULL REFERENCES writing_drafts(draft_id), "
        "shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id), "
        "run_id TEXT NOT NULL REFERENCES writing_sessions(run_id), "
        "gate_stage TEXT NOT NULL CHECK (gate_stage IN ("
        "'gate1', 'hard_rule', 'type_gate', 'literary_jury', "
        "'jury_unavailable', 'gate2', 'l4', 'l3'"
        ")), "
        "passed INTEGER NOT NULL CHECK (passed IN (0, 1)), "
        "score REAL, "
        "threshold REAL, "
        "reason_json JSON NOT NULL DEFAULT '{}', "
        "result_json JSON NOT NULL DEFAULT '{}', "
        "attempt_id TEXT NOT NULL, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(draft_id, gate_stage, attempt_id)"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_draft_eligibility_run "
        "ON writing_draft_eligibility(run_id, gate_stage)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_draft_eligibility_shot "
        "ON writing_draft_eligibility(shot_id, gate_stage)"
    )

    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_failure_attributions ("
        "attribution_id TEXT PRIMARY KEY, "
        "project_id TEXT REFERENCES projects(project_id), "
        "run_id TEXT REFERENCES writing_sessions(run_id), "
        "shot_id TEXT REFERENCES writing_shots(shot_id), "
        "draft_id TEXT REFERENCES writing_drafts(draft_id), "
        "stage TEXT NOT NULL, "
        "failure_category TEXT NOT NULL CHECK (failure_category IN ("
        "'contract_conflict', 'outline_gap', 'task_card_gap', 'writer_drift', "
        "'gate_false_positive', 'model_failure', 'jury_failure', 'unknown'"
        ")), "
        "root_cause_json JSON NOT NULL DEFAULT '{}', "
        "evidence_refs_json JSON NOT NULL DEFAULT '{}', "
        "suggested_action TEXT, "
        "created_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_failure_attr_run "
        "ON writing_failure_attributions(run_id, stage)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_failure_attr_shot "
        "ON writing_failure_attributions(shot_id, stage)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_failure_attr_category "
        "ON writing_failure_attributions(failure_category)"
    )
