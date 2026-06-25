-- InkFlow v3.12 — Schema v15 (CREATIVE-2 polish 精修阶段)
-- SCHEMA_VERSION: 15
-- Generated from implementation-contract-v0.md; aligned 2026-06-25
-- 38 business tables total (+ _schema_meta = 39 SQLite user tables), ordered by FK dependency
-- v5→v6: 新增 writing_information_gaps 表 (D-25 悬疑引擎)
-- v6→v7: 新增 writing_chapter_rhythms 表 (AI 架构师 L1 章级节奏)
-- v7→v8: 新增 tree_nodes / contract_versions / story_content / execution_records (ARCH-12 三棵树架构)
-- v8→v9: 新增 writing_book_constitutions 表 + writing_meta_contract.constitution_version_id (ARCH-4 L0 全书宪法)
-- v9→v10: 新增 writing_volume_rhythms 表 (ARCH-5 L0.5 卷部节奏)
-- v10→v11: writing_shots 新增 failure_signature_json (D-25 可靠性闭环)
-- v11→v12: 新增 writing_style_preferences 表 + writing_drafts 风格字段 (ARCH-10)
-- v12→v13: 新增 writing_anti_contract_reviews 表 (ARCH-11)
-- v13→v14: writing_jury_scores.dimension 新增 unexpected_value (CREATIVE-1)
-- v14→v15: shot_revisions.operation 新增 write_polish；model_attempts.phase 新增 polish (CREATIVE-2)

PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA foreign_keys = ON;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -64000;
PRAGMA temp_store = MEMORY;
PRAGMA encoding = 'UTF-8';

-- =============================================================================
-- Layer 1: No FK dependencies
-- =============================================================================

CREATE TABLE projects (
    project_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    universe_id TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- =============================================================================
-- Layer 2: FK → projects
-- =============================================================================

CREATE TABLE writing_book_constitutions (
    constitution_id        TEXT PRIMARY KEY,
    project_id             TEXT NOT NULL REFERENCES projects(project_id),
    version                INTEGER NOT NULL DEFAULT 1,

    -- 节奏治理参数（LLM 生成 + 规则引擎验证）
    arc_shape              TEXT,
    tension_peak_chapter   TEXT,
    tension_valley_chapters_json JSON,
    volume_map_json        JSON,
    chapter_roles_json     JSON,
    motif_lifecycle_json   JSON,
    global_deviation_mean  REAL,
    global_deviation_range_json JSON,

    -- 状态管理
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'human_review', 'confirmed', 'locked')),
    confirmed_at  TEXT,
    locked_at     TEXT,

    -- 审计
    source_outline_hash TEXT,
    llm_model_ref       TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(project_id, version)
);
CREATE INDEX idx_book_constitutions_project ON writing_book_constitutions(project_id);

CREATE TABLE writing_project_structure (
    structure_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    layer_type TEXT NOT NULL CHECK (layer_type IN ('universe', 'project', 'act', 'volume', 'chapter', 'scene')),
    layer_key TEXT NOT NULL,
    parent_layer_key TEXT,
    layer_index INTEGER NOT NULL,
    human_confirm_layer INTEGER NOT NULL,
    metadata_json JSON,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(project_id, layer_key)
);

CREATE TABLE writing_meta_contract (
    meta_contract_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    contract_version TEXT NOT NULL DEFAULT '3.6',
    min_runtime_version TEXT NOT NULL DEFAULT '3.6',
    status TEXT NOT NULL CHECK (status IN ('draft', 'human_review', 'confirmed', 'locked', 'repairing', 'evolving')),
    upgraded_from TEXT,
    upgraded_at TEXT,
    fields_added_json JSON,
    layers_json JSON NOT NULL,
    human_confirm_layer INTEGER NOT NULL,
    constitution_version_id TEXT REFERENCES writing_book_constitutions(constitution_id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE writing_meta_contract_revisions (
    revision_id TEXT PRIMARY KEY,
    meta_contract_id TEXT NOT NULL REFERENCES writing_meta_contract(meta_contract_id),
    changed_by TEXT NOT NULL CHECK (changed_by IN ('human', 'ai', 'upgrade')),
    reason TEXT NOT NULL CHECK (length(reason) >= 50),
    before_json JSON NOT NULL,
    after_json JSON NOT NULL,
    diff_json JSON NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- =============================================================================
-- Layer 3: FK → projects (configs, definitions, profiles)
-- =============================================================================

CREATE TABLE writing_project_config (
    config_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    default_preset TEXT NOT NULL DEFAULT 'balanced',
    redo_model TEXT NOT NULL DEFAULT 'claude-sonnet-4-6',
    layers_json JSON NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE writing_writer_profiles (
    profile_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    persona_name TEXT NOT NULL CHECK (persona_name IN ('意象师', '节奏师', '对话师', '结构师')),
    model_id TEXT NOT NULL,
    temperature REAL NOT NULL DEFAULT 0.8 CHECK (temperature BETWEEN 0.0 AND 2.0),
    voice_samples_json JSON,
    anti_samples_json JSON,
    system_prompt_template TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(project_id, persona_name)
);

CREATE TABLE writing_jury_config (
    config_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    base_dimensions_json JSON NOT NULL,
    dynamic_dimensions_json JSON,
    thresholds_json JSON NOT NULL,
    weights_json JSON NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE writing_motif_definitions (
    motif_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    name TEXT NOT NULL,
    category TEXT,
    description TEXT,
    planned_density_json JSON NOT NULL,
    variants_json JSON NOT NULL,
    min_shot_gap INTEGER NOT NULL DEFAULT 3 CHECK (min_shot_gap >= 0),
    mutual_exclusion_json JSON,
    evolution_json JSON,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- =============================================================================
-- Layer 4a: Sessions (must precede shots so shots can FK to run_id)
-- =============================================================================

CREATE TABLE writing_sessions (
    session_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    run_id TEXT NOT NULL UNIQUE,
    act_id TEXT,
    status TEXT NOT NULL CHECK (status IN ('active', 'paused', 'completed', 'aborted', 'crashed')),
    current_shot_id TEXT,
    completed_shots INTEGER NOT NULL DEFAULT 0,
    total_shots INTEGER,
    escape_used BOOLEAN NOT NULL DEFAULT 0,
    checkpoint_json JSON,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_sessions_project ON writing_sessions(project_id);
CREATE INDEX idx_sessions_status ON writing_sessions(status);

-- =============================================================================
-- Layer 4b: FK → projects + writing_sessions
-- =============================================================================

CREATE TABLE writing_run_snapshots (
    snapshot_id TEXT PRIMARY KEY,
    run_id TEXT NOT NULL UNIQUE REFERENCES writing_sessions(run_id),
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    meta_contract_id TEXT NOT NULL REFERENCES writing_meta_contract(meta_contract_id),
    config_hash TEXT NOT NULL,
    contract_snapshot_hash TEXT NOT NULL,
    snapshot_json JSON NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE writing_shots (
    shot_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    layer_key TEXT NOT NULL,
    shot_index INTEGER NOT NULL,
    shot_status TEXT NOT NULL CHECK (shot_status IN (
        'pending', 'generating', 'gate1_check', 'jury_scoring', 'final_gate',
        'done_green', 'done_yellow', 'placeholder', 'redo', 'done_red_permanent'
    )),
    placeholder_type TEXT CHECK (placeholder_type IN ('best_failed_candidate', 'redo_placeholder', 'permanent_red')),
    redo_attempt INTEGER NOT NULL DEFAULT 0 CHECK (redo_attempt BETWEEN 0 AND 3),
    light_status TEXT CHECK (light_status IN ('green', 'yellow', 'red')),
    brilliance_level TEXT CHECK (brilliance_level IN ('A', 'A+', 'S')),
    badsmell_level TEXT CHECK (badsmell_level IN ('B', 'Br', 'Bz')),
    source_hard_boundary_index INTEGER,
    context_injection_status TEXT CHECK (context_injection_status IN ('full', 'warning', 'summary_only')),
    current_revision_id TEXT,
    is_baseline INTEGER NOT NULL DEFAULT 0 CHECK (is_baseline IN (0, 1)),
    failure_signature_json JSON,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(run_id, shot_index)
);
CREATE INDEX idx_shots_run ON writing_shots(run_id);
CREATE INDEX idx_shots_status ON writing_shots(shot_status);

-- =============================================================================
-- Layer 5: FK → writing_sessions + writing_shots
-- =============================================================================

CREATE TABLE writing_session_checkpoints (
    checkpoint_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES writing_sessions(session_id) ON DELETE CASCADE,
    shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
    checkpoint_json JSON NOT NULL,
    checkpoint_storage_path TEXT NOT NULL DEFAULT '.checkpoints/',
    context_hash TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_checkpoints_session ON writing_session_checkpoints(session_id);

CREATE TABLE writing_shot_contracts (
    contract_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
    layer_key TEXT NOT NULL,
    parent_contract_id TEXT REFERENCES writing_shot_contracts(contract_id),
    contract_status TEXT NOT NULL CHECK (contract_status IN ('draft', 'human_review', 'confirmed', 'locked', 'repairing', 'evolving')),
    snapshot_hash TEXT NOT NULL,
    must_land_json JSON NOT NULL,
    anti_write_json JSON NOT NULL,
    exit_to_json JSON,
    motif_tasks_json JSON,
    pov_routing_json JSON,
    contract_json JSON NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(run_id, shot_id)
);

-- =============================================================================
-- Layer 6: FK → writing_shots + writing_shot_contracts
-- =============================================================================

CREATE TABLE shot_revisions (
    revision_id TEXT PRIMARY KEY,
    shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    parent_revision_id TEXT REFERENCES shot_revisions(revision_id),
    contract_id TEXT NOT NULL REFERENCES writing_shot_contracts(contract_id),
    revision_sequence INTEGER NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('write_generate', 'write_placeholder', 'write_repair', 'write_redo', 'write_polish')),
    text TEXT NOT NULL,
    text_hash_normalized TEXT NOT NULL,
    writer_persona TEXT,
    jury_scores_json JSON,
    gate_result_json JSON,
    is_current BOOLEAN NOT NULL DEFAULT 0,
    attempt_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(shot_id, operation, attempt_id)
);
CREATE INDEX idx_revisions_shot ON shot_revisions(shot_id);
-- DB-2: ensure at most one current revision per shot
CREATE UNIQUE INDEX idx_revisions_one_current ON shot_revisions(shot_id) WHERE is_current = 1;

CREATE TABLE writing_drafts (
    draft_id TEXT PRIMARY KEY,
    shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    writer_persona TEXT NOT NULL,
    writer_index INTEGER NOT NULL,
    text TEXT NOT NULL,
    self_note TEXT,
    gate1_result_json JSON,
    gate2_result_json JSON,
    is_usable BOOLEAN NOT NULL DEFAULT 0,
    attempt_id TEXT NOT NULL,
    model_ref TEXT,
    temperature REAL DEFAULT 0.8,
    style_direction TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_drafts_shot ON writing_drafts(shot_id);
CREATE INDEX idx_drafts_run ON writing_drafts(run_id);

CREATE TABLE writing_shot_prompts (
    prompt_id TEXT PRIMARY KEY,
    shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    writer_persona TEXT,
    prompt_hash TEXT NOT NULL,
    static_prefix TEXT NOT NULL,
    static_prefix_length INTEGER NOT NULL DEFAULT 0,
    dynamic_assembly_json JSON NOT NULL,
    assembled_prompt TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(run_id, shot_id, writer_persona)
);
CREATE INDEX idx_prompts_run ON writing_shot_prompts(run_id);

CREATE TABLE writing_context_snaps (
    snap_id TEXT PRIMARY KEY,
    shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    context_hash TEXT NOT NULL,
    previous_shots_json JSON NOT NULL,
    fact_anchor_refs_json JSON NOT NULL,
    motif_tracker_state_json JSON NOT NULL,
    anti_samples_json JSON NOT NULL,
    injected_with_warning BOOLEAN NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_context_snaps_run ON writing_context_snaps(run_id);

-- =============================================================================
-- Layer 7: FK → multiple tables (anchors, motifs, scores)
-- =============================================================================

CREATE TABLE writing_fact_anchors (
    anchor_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    run_id TEXT REFERENCES writing_sessions(run_id),
    shot_id TEXT REFERENCES writing_shots(shot_id),
    anchor_type TEXT NOT NULL CHECK (anchor_type IN (
        'character_state', 'character_trait', 'object_location', 'object_property',
        'event_occurred', 'relationship', 'world_rule', 'timeline', 'knowledge'
    )),
    anchor_key TEXT NOT NULL,
    anchor_value TEXT NOT NULL,
    confidence REAL NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    pov_scope TEXT DEFAULT NULL,
    override_source TEXT CHECK (override_source IN ('universe', 'project_override', 'project_fork')),
    contract_clause_ref TEXT,
    source_revision_id TEXT REFERENCES shot_revisions(revision_id),
    extracted_at TEXT NOT NULL DEFAULT (datetime('now')),
    -- DB-5: allow same key within same run for update/confirm/POV variants
    UNIQUE(project_id, anchor_key, source_revision_id)
);
CREATE INDEX idx_anchors_project ON writing_fact_anchors(project_id, run_id);

CREATE TABLE writing_motif_instances (
    instance_id TEXT PRIMARY KEY,
    motif_id TEXT NOT NULL REFERENCES writing_motif_definitions(motif_id),
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
    variant_used TEXT NOT NULL,
    evolution_phase TEXT NOT NULL CHECK (evolution_phase IN ('establishment', 'variation', 'subversion', 'resolution')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_motif_instances_run ON writing_motif_instances(run_id);

CREATE TABLE writing_motif_tracker (
    tracker_id TEXT PRIMARY KEY,
    motif_id TEXT NOT NULL REFERENCES writing_motif_definitions(motif_id),
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    current_count INTEGER NOT NULL DEFAULT 0,
    density_status TEXT NOT NULL CHECK (density_status IN ('green', 'yellow', 'blue', 'red', 'gray')),
    last_used_shot_id TEXT,
    task_generated_for_shot_id TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(run_id, motif_id)
);

CREATE TABLE writing_jury_scores (
    score_id TEXT PRIMARY KEY,
    draft_id TEXT NOT NULL REFERENCES writing_drafts(draft_id),
    shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    jury_persona TEXT NOT NULL,
    phase TEXT NOT NULL CHECK (phase IN ('independent', 'comparative', 'final')),
    dimension TEXT NOT NULL CHECK (dimension IN (
        'literary_quality', 'narrative_pacing', 'voice_consistency', 'contract_compliance',
        'motif_compatibility', 'anti_pattern_avoidance', 'hook_transition', 'character_coherence',
        'reader_engagement', 'forbidden_expression', 'reading_fluency', 'suspense_effectiveness',
        'unexpected_value'
    )),
    score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
    comment TEXT,
    attempt_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(shot_id, draft_id, jury_persona, phase, dimension, attempt_id)
);
CREATE INDEX idx_jury_scores_run ON writing_jury_scores(run_id);

-- =============================================================================
-- Layer 8: FK → writing_shots (audit, events, notes)
-- =============================================================================

CREATE TABLE writing_repair_audit (
    repair_audit_id TEXT PRIMARY KEY,
    shot_id TEXT REFERENCES writing_shots(shot_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    contract_id TEXT NOT NULL REFERENCES writing_shot_contracts(contract_id),
    layer TEXT NOT NULL CHECK (layer IN ('L1', 'L2', 'L3', 'L4')),
    diagnosis TEXT NOT NULL,
    diff_json JSON NOT NULL,
    repair_result_json JSON,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_repair_audit_run ON writing_repair_audit(run_id);

CREATE TABLE writing_exception_events (
    event_id TEXT PRIMARY KEY,
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
    event_type TEXT NOT NULL CHECK (event_type IN ('unresolvable', 'escape', 'drift_alert')),
    reason_json JSON NOT NULL,
    boundary_id TEXT,
    new_direction TEXT,
    resolution_json JSON,
    architect_review_status TEXT CHECK (architect_review_status IN ('pending', 'approved', 'rejected', 'deferred')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_exception_events_run ON writing_exception_events(run_id);

CREATE TABLE writing_deviation_notes (
    note_id TEXT PRIMARY KEY,
    shot_id TEXT REFERENCES writing_shots(shot_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    note_type TEXT NOT NULL CHECK (note_type IN ('intent_drift', 'contract_violation', 'human_flag')),
    severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
    content TEXT NOT NULL,
    resolved_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_deviation_notes_run ON writing_deviation_notes(run_id);

-- =============================================================================
-- Layer 9: FK → projects + writing_shots (reference pool)
-- =============================================================================

CREATE TABLE writing_reference_pool (
    sample_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    sample_type TEXT NOT NULL CHECK (sample_type IN ('positive', 'negative')),
    text TEXT NOT NULL,
    annotation TEXT NOT NULL,
    source_shot_id TEXT REFERENCES writing_shots(shot_id),
    review_status TEXT NOT NULL DEFAULT 'pending' CHECK (review_status IN ('pending', 'approved', 'rejected')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- =============================================================================
-- Layer 10a: Information Gap Tracking (D-25 悬疑引擎)
-- =============================================================================

CREATE TABLE writing_information_gaps (
    gap_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    description TEXT NOT NULL,
    reader_knows TEXT NOT NULL,
    character_knows TEXT NOT NULL,
    created_shot_id TEXT REFERENCES writing_shots(shot_id),
    reinforced_shot_ids TEXT DEFAULT '[]',
    revealed_shot_id TEXT REFERENCES writing_shots(shot_id),
    next_gap_id TEXT REFERENCES writing_information_gaps(gap_id),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'active', 'reinforced', 'revealed', 'resolved')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_info_gaps_run ON writing_information_gaps(run_id);
CREATE INDEX idx_info_gaps_status ON writing_information_gaps(status);

-- =============================================================================
-- Layer 10: Model call audit (DB-6 / B22)
-- =============================================================================

CREATE TABLE model_attempts (
    attempt_id TEXT PRIMARY KEY,
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    shot_id TEXT REFERENCES writing_shots(shot_id),
    phase TEXT NOT NULL CHECK (phase IN (
        'write_generate', 'jury_score', 'fact_extract', 'repair',
        'motif_task', 'contract_compile', 'prompt_compile', 'polish'
    )),
    model_name TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    request_prompt_hash TEXT NOT NULL,
    response_text_hash TEXT,
    usage_prompt_tokens INTEGER DEFAULT 0,
    usage_completion_tokens INTEGER DEFAULT 0,
    usage_total_tokens INTEGER DEFAULT 0,
    error_message TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(idempotency_key)
);
CREATE INDEX idx_model_attempts_run ON model_attempts(run_id);
CREATE INDEX idx_model_attempts_shot ON model_attempts(shot_id);

-- =============================================================================
-- Layer 11: Architect Gates — 4-level cascading quality gate
-- =============================================================================

CREATE TABLE writing_architect_gates (
    gate_id TEXT PRIMARY KEY,
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    level TEXT NOT NULL CHECK (level IN ('L1', 'L2', 'L3', 'L4')),
    scope_key TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'passed', 'failed')),
    check_result_json JSON,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(run_id, level, scope_key)
);

-- =============================================================================
-- Layer 12: Outline Evaluations (v4)
-- =============================================================================

CREATE TABLE writing_outline_evaluations (
    evaluation_id TEXT PRIMARY KEY,
    shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    attempt INTEGER NOT NULL DEFAULT 1,
    outline_text TEXT NOT NULL,
    score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
    dimensions_json JSON NOT NULL,
    issues_json JSON,
    suggestions_json JSON,
    regenerated INTEGER NOT NULL DEFAULT 0 CHECK (regenerated IN (0, 1)),
    new_outline_text TEXT,
    model_used TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_outline_evals_shot ON writing_outline_evaluations(shot_id);
CREATE INDEX idx_architect_gates_run ON writing_architect_gates(run_id);
CREATE INDEX idx_architect_gates_level ON writing_architect_gates(level);

-- =============================================================================
-- Layer 13: Chapter Rhythms — AI 架构师 L1 章级节奏 (v7)
-- =============================================================================

CREATE TABLE writing_chapter_rhythms (
    rhythm_id TEXT PRIMARY KEY,
    chapter_key TEXT NOT NULL,
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    rhythm_map_json JSON NOT NULL,
    validation_json JSON,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_chapter_rhythms_run ON writing_chapter_rhythms(run_id);
CREATE INDEX idx_chapter_rhythms_chapter ON writing_chapter_rhythms(chapter_key);

-- =============================================================================
-- Layer 14: Contract Tree — 三棵树架构 (v8, ARCH-12)
-- tree_nodes: 统一骨架，三棵树（契约/故事/执行）共用
-- contract_versions: 契约树正文，版本化
-- story_content: 故事树正文，追加式
-- execution_records: 执行树正文，per-run
-- 完整设计见 docs/design-3tree-architecture.md
-- =============================================================================

CREATE TABLE tree_nodes (
    node_id         TEXT PRIMARY KEY,
    tree_type       TEXT NOT NULL
                        CHECK (tree_type IN ('contract', 'story', 'execution')),
    project_id      TEXT NOT NULL REFERENCES projects(project_id),
    parent_id       TEXT REFERENCES tree_nodes(node_id),
    layer_key       TEXT NOT NULL,
    node_level      TEXT NOT NULL
                        CHECK (node_level IN ('L0','L1','L2','L3','L4','L5','L6','L7')),
    node_name       TEXT,
    sort_order      INTEGER DEFAULT 0,
    design_status   TEXT DEFAULT 'pending'
                        CHECK (design_status IN
                            ('pending','drafting','review','confirmed','locked')),
    quality_color   TEXT
                        CHECK (quality_color IN ('green','yellow','red','gray',NULL)),
    node_intent     TEXT,
    run_id          TEXT,
    source_version_id TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(tree_type, project_id, layer_key, run_id)
);
CREATE INDEX idx_tree_nodes_parent ON tree_nodes(parent_id);
CREATE INDEX idx_tree_nodes_lookup ON tree_nodes(tree_type, project_id, layer_key);
CREATE INDEX idx_tree_nodes_run    ON tree_nodes(run_id) WHERE run_id IS NOT NULL;

CREATE TABLE contract_versions (
    version_id        TEXT PRIMARY KEY,
    node_id           TEXT NOT NULL REFERENCES tree_nodes(node_id),
    version           INTEGER NOT NULL,
    parent_version_id TEXT REFERENCES contract_versions(version_id),
    is_collapsed      INTEGER NOT NULL DEFAULT 0,
    contract_body_json JSON NOT NULL,
    change_reason     TEXT,
    created_by        TEXT NOT NULL DEFAULT 'human'
                          CHECK (created_by IN ('human', 'ai', 'upgrade')),
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(node_id, version)
);
CREATE INDEX idx_contract_versions_node ON contract_versions(node_id);

CREATE TABLE story_content (
    content_id        TEXT PRIMARY KEY,
    node_id           TEXT NOT NULL REFERENCES tree_nodes(node_id),
    content_body_json JSON NOT NULL,
    updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_story_content_node ON story_content(node_id);

CREATE TABLE execution_records (
    record_id          TEXT PRIMARY KEY,
    node_id            TEXT NOT NULL REFERENCES tree_nodes(node_id),
    run_id             TEXT NOT NULL,
    prompt_snapshot_id TEXT,
    draft_ids_json     JSON,
    selected_draft_id  TEXT,
    revision_id        TEXT REFERENCES shot_revisions(revision_id),
    quality_result_json JSON,
    created_at         TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_execution_records_node ON execution_records(node_id);
CREATE INDEX idx_execution_records_run  ON execution_records(run_id);

-- =============================================================================
-- Layer 15: Volume Rhythms — AI 架构师 L0.5 卷部节奏 (v10, ARCH-5)
-- =============================================================================

CREATE TABLE writing_volume_rhythms (
    rhythm_id       TEXT PRIMARY KEY,
    volume_key      TEXT NOT NULL,
    project_id      TEXT NOT NULL REFERENCES projects(project_id),
    run_id          TEXT NOT NULL REFERENCES writing_sessions(run_id),
    rhythm_json     JSON NOT NULL,
    validation_json JSON,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_volume_rhythms_run ON writing_volume_rhythms(run_id);
CREATE INDEX idx_volume_rhythms_volume ON writing_volume_rhythms(volume_key);

-- v12: ARCH-10 风格偏好学习 — 记录 jury winner 的 persona/model/temperature/style_direction
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
);
CREATE INDEX idx_style_prefs_run ON writing_style_preferences(run_id);
CREATE INDEX idx_style_prefs_project ON writing_style_preferences(project_id);
CREATE INDEX idx_style_prefs_persona ON writing_style_preferences(persona);

-- v13: ARCH-11 反契约沙盒 — 记录软约束偏离的人类裁决
CREATE TABLE writing_anti_contract_reviews (
    review_id         TEXT PRIMARY KEY,
    shot_id           TEXT NOT NULL REFERENCES writing_shots(shot_id),
    run_id            TEXT NOT NULL REFERENCES writing_sessions(run_id),
    deviant_draft_id  TEXT NOT NULL REFERENCES writing_drafts(draft_id),
    deviant_score     REAL NOT NULL,
    compliant_mean    REAL NOT NULL,
    advantage         REAL NOT NULL,
    soft_constraints_json JSON NOT NULL,
    human_decision    TEXT NOT NULL DEFAULT 'pending' CHECK (human_decision IN ('pending', 'accept', 'reject', 'conditional')),
    human_notes       TEXT,
    reviewed_at       TEXT,
    created_at        TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_anti_contract_reviews_run ON writing_anti_contract_reviews(run_id);
