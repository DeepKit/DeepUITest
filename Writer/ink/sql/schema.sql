-- Generated from ink/docs/implementation-contract-v1.md.
-- Do not hand-edit without syncing the implementation contract.

-- 1. writing_projects
-- 运营参数全部在此表，运行时可调不改代码（见 §1.5 参数化原则）
CREATE TABLE writing_projects (
    project_id INTEGER PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    meta_contract_id INTEGER,                         -- 当前元契约指针；不做 FK，避免 projects/meta_contracts 循环级联

    -- ── 产稿参数 ──
    draft_count INTEGER NOT NULL DEFAULT 3,          -- X 全局候选稿数
    creative_shot_extra INTEGER NOT NULL DEFAULT 3,  -- 创意 shot 额外候选数
    writer_model_pool TEXT NOT NULL,                 -- JSON array
    jury_model_pool TEXT NOT NULL,                   -- JSON array
    jury_model_pool_min INTEGER NOT NULL DEFAULT 3,  -- 裁判模型池最少数量（DB CHECK 用）
    model_aliases TEXT,                              -- JSON {"别名":"真实模型名"}，如 {"smart-polish":"xopglm51"}；NULL 表示无别名
    min_eligible_outlines INTEGER NOT NULL DEFAULT 1,  -- 大纲生成最少合格数（默认 1：真实模型 outline 易因 drift 全拒，2 过严）
    min_eligible_candidates INTEGER NOT NULL DEFAULT 2,  -- jury 候选不足此数触发补写
    redo_candidate_count INTEGER NOT NULL DEFAULT 2,    -- N=2 局部重写时产几篇新候选
    escalated_jury_count INTEGER NOT NULL DEFAULT 5,    -- 裁判分歧超阈值时升级到几个裁判

    -- ── 熔断预算参数（原硬编码，现运营可调） ──
    max_calls_per_shot INTEGER NOT NULL DEFAULT 8,          -- 单 shot 单类型 LLM 调用上限
    max_total_llm_calls INTEGER NOT NULL DEFAULT 40,        -- 单 shot 全生命周期 LLM 调用总上限
    consecutive_failure_circuit_break INTEGER NOT NULL DEFAULT 3,  -- 同类失败连续 N 次熔断

    -- ── soft gate 升级阈值参数（原硬编码，现运营可调） ──
    soft_gate_redo_n INTEGER NOT NULL DEFAULT 2,            -- soft gate 连续失败 N 次触发局部重写
    soft_gate_fail_n INTEGER NOT NULL DEFAULT 3,            -- soft gate 连续失败 N 次，质量类转 failed

    -- ── 自动重试参数（A'+A'' 机制） ──
    auto_retry_on_hard_failure INTEGER NOT NULL DEFAULT 1 CHECK (auto_retry_on_hard_failure IN (0,1)),
    max_retries_per_gate INTEGER NOT NULL DEFAULT 2,        -- 每层 gate 自动重试最大次数
    retry_strategy TEXT NOT NULL DEFAULT 'change_model'
        CHECK (retry_strategy IN ('change_model','adjust_intensity','relax_soft')),

    -- ── 大纲与容量参数 ──
    outline_drift_threshold REAL NOT NULL DEFAULT 0.10,     -- 大纲 CJK bigram overlap 拒绝阈值（默认 0.10：真实模型 overlap 易低于 0.20 全拒）
    capacity_floor_titled_shot INTEGER NOT NULL DEFAULT 1200,  -- titled shot 容量下限 UTF-8 bytes
    capacity_floor_chapter_end INTEGER NOT NULL DEFAULT 1500,  -- 章末 shot 容量下限 UTF-8 bytes

    -- ── 多样性与场景参数 ──
    scene_fingerprint_min_diversity INTEGER NOT NULL DEFAULT 3,  -- L3 场景指纹多样性最低要求
    suspense_shot_min_intensity INTEGER NOT NULL DEFAULT 5,      -- 悬疑 shot 悬疑维度最低强度

    -- ── 归档与恢复参数 ──
    prompt_archive_size_bytes INTEGER NOT NULL DEFAULT 65536,  -- prompt 超此大小归档到独立文件
    checkpoint_max_retention INTEGER NOT NULL DEFAULT 3,       -- checkpoint 保留最近几个稳定点

    -- ── 质量阈值参数（原 quality_bar JSON，拆为独立字段以支持 DB 层约束） ──
    shot_quality_floor INTEGER NOT NULL DEFAULT 75,           -- winner 最低 final_score，DB 绝对底线 75（真实模型 jury 稳定 77-83，80 过严）
    dimension_floor INTEGER NOT NULL DEFAULT 60,              -- 12 维任一核心维度最低分，DB 绝对底线 60
    chapter_quality_floor INTEGER NOT NULL DEFAULT 75,        -- 章级 8 维最低分，DB 绝对底线 75
    book_quality_floor INTEGER NOT NULL DEFAULT 75,           -- 篇级 6 维最低分，DB 绝对底线 75
    judge_disagreement_max INTEGER NOT NULL DEFAULT 25,       -- 同维 3 裁判最高-最低最大分差，DB 绝对底线 25
    reader_pull_floor INTEGER NOT NULL DEFAULT 75,            -- would_continue_reading 最低分
    blind_review_min_passes INTEGER NOT NULL DEFAULT 2,       -- 盲评最少通过数

    -- ── 篇级检测参数 ──
    chapter_rolling_check_interval INTEGER NOT NULL DEFAULT 5,
    suspense_decay_floor INTEGER NOT NULL DEFAULT 82 CHECK (suspense_decay_floor >= 82),
    require_ethics_review INTEGER NOT NULL DEFAULT 0 CHECK (require_ethics_review IN (0,1)),

    created_at TEXT NOT NULL,

    CHECK (shot_quality_floor >= 75),                          -- 运营阈值不得低于 DB 绝对底线
    CHECK (dimension_floor >= 60),
    CHECK (chapter_quality_floor >= 75),
    CHECK (book_quality_floor >= 75),
    CHECK (judge_disagreement_max <= 25),                     -- 分差阈值不得高于绝对底线（越小越严格）
    CHECK (blind_review_min_passes BETWEEN 1 AND 3),

    -- CHECK 约束：DB 只做 JSON/长度底线；元素类型、去重、两池交集由 ProjectConfigValidator 校验
    CHECK (json_valid(writer_model_pool) AND json_type(writer_model_pool) = 'array'),
    CHECK (json_valid(jury_model_pool) AND json_type(jury_model_pool) = 'array'),
    CHECK (model_aliases IS NULL OR (json_valid(model_aliases) AND json_type(model_aliases) = 'object')),
    CHECK (json_array_length(writer_model_pool) >= draft_count),
    CHECK (json_array_length(jury_model_pool) >= jury_model_pool_min),
    CHECK (jury_model_pool_min >= 3)
);

-- 2. writing_meta_contracts
CREATE TABLE writing_meta_contracts (
    meta_contract_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    identity TEXT NOT NULL,                          -- JSON
    narrative_voice TEXT NOT NULL,                   -- JSON
    hard_boundaries TEXT NOT NULL,                   -- JSON
    style_locks TEXT NOT NULL,                       -- JSON
    world_knowledge TEXT NOT NULL,                   -- JSON
    motif_system TEXT NOT NULL,                      -- JSON
    creative_zones TEXT NOT NULL,                    -- JSON
    -- quality_bar 已迁移至 writing_projects 表作为独立字段（支持 DB 层约束和索引）
    style_quality_profile TEXT NOT NULL,             -- JSON：目标读者、文体标杆、正/反例、禁用俗套、密度目标
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','confirmed','locked')),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);

-- 3. writing_chapter_specs
CREATE TABLE writing_chapter_specs (
    chapter_spec_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    volume_id TEXT,                                    -- 所属卷 ID（逻辑分组，可为 NULL）
    part_id TEXT,                                      -- 所属部分 ID（逻辑分组，可为 NULL）
    rhythm_curve_target TEXT NOT NULL,               -- JSON 节奏曲线目标
    hook_target TEXT,                                -- 章末钩子目标
    motif_density_target REAL,
    injected_issues TEXT,                            -- 篇级检测/soft gate 注入的问题（评审 #18/#36）
    UNIQUE (project_id, chapter_id),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);

-- 4. writing_outline_specs
CREATE TABLE writing_outline_specs (
    outline_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER,
    evaluated_outline_text TEXT NOT NULL,
    drift_score REAL NOT NULL,
    -- drift_rejected 派生自 drift_score < writing_projects.outline_drift_threshold，不再存列（评审 #23："一个信号只存一处"）
    is_winner INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);
-- 评审 #30：is_winner 唯一约束，大纲 PK 只能选一个 winner
CREATE UNIQUE INDEX idx_outline_winner ON writing_outline_specs(shot_contract_id) WHERE is_winner = 1;

-- 5. writing_shot_contracts（契约主表，不存核心字段 blob）
CREATE TABLE writing_shot_contracts (
    shot_contract_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    run_id INTEGER NOT NULL,
    logical_shot_id TEXT NOT NULL,
    -- 核心字段拆到 5 张子表（下方 6-10），本表只存状态与指针
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','confirmed','locked')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,                        -- 评审 #28：状态机变更时间可追踪
    UNIQUE (project_id, chapter_id, logical_shot_id, run_id),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE
);

-- 6. writing_shot_must_land（必须落地，结构化）
CREATE TABLE writing_shot_must_land (
    must_land_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL UNIQUE,        -- 1:1
    events TEXT NOT NULL,                            -- JSON array（事件列表，结构化存储非 blob 单列）
    beats TEXT NOT NULL,                             -- JSON array（beat 顺序）
    information_releases TEXT NOT NULL,              -- JSON array
    CHECK (json_array_length(events) > 0),
    CHECK (json_array_length(beats) > 0),
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 7. writing_shot_anti_write（禁区，结构化）
CREATE TABLE writing_shot_anti_write (
    anti_write_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL UNIQUE,        -- 1:1
    forbidden_facts TEXT NOT NULL,                   -- JSON array
    forbidden_words TEXT NOT NULL,                   -- JSON array
    pov_only TEXT NOT NULL,                          -- JSON array
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 8. writing_shot_scene_contract（场景契约，结构化）
CREATE TABLE writing_shot_scene_contract (
    scene_contract_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL UNIQUE,        -- 1:1
    location TEXT NOT NULL,
    time_of_day TEXT NOT NULL,
    characters_present TEXT NOT NULL,                -- JSON array
    character_positions TEXT NOT NULL,               -- JSON object {角色: 位置}
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 9. writing_shot_persona_assignment（persona 指定，结构化）
CREATE TABLE writing_shot_persona_assignment (
    persona_assignment_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL UNIQUE,        -- 1:1
    persona TEXT NOT NULL CHECK (persona IN ('意象师','节奏师','对话师','结构师','悬疑官')),
    intensity TEXT NOT NULL,                         -- JSON {画面,节奏,对话,结构,悬疑} 各 0-10
    is_creative_shot INTEGER NOT NULL DEFAULT 0 CHECK (is_creative_shot IN (0,1)),
    is_suspense_shot INTEGER NOT NULL DEFAULT 0 CHECK (is_suspense_shot IN (0,1)),
    -- 评审 medium 修订：5 维全补全非 NULL + 0-10 区间 CHECK（原只查画面/悬疑非 NULL）
    CHECK (json_extract(intensity, '$.画面') IS NOT NULL AND json_extract(intensity, '$.画面') BETWEEN 0 AND 10),
    CHECK (json_extract(intensity, '$.节奏') IS NOT NULL AND json_extract(intensity, '$.节奏') BETWEEN 0 AND 10),
    CHECK (json_extract(intensity, '$.对话') IS NOT NULL AND json_extract(intensity, '$.对话') BETWEEN 0 AND 10),
    CHECK (json_extract(intensity, '$.结构') IS NOT NULL AND json_extract(intensity, '$.结构') BETWEEN 0 AND 10),
    CHECK (json_extract(intensity, '$.悬疑') IS NOT NULL AND json_extract(intensity, '$.悬疑') BETWEEN 0 AND 10),
    -- is_suspense_shot=1 要求悬疑强度 >= writing_projects.suspense_shot_min_intensity（默认 5，运营可调）
    -- 注意：此 CHECK 为绝对底线 5，实际阈值由应用层从 writing_projects 读取后执行
    CHECK (is_suspense_shot = 0 OR json_extract(intensity, '$.悬疑') >= 5),
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 10. writing_shot_soft_constraints（软约束，结构化）
CREATE TABLE writing_shot_soft_constraints (
    soft_constraints_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL UNIQUE,        -- 1:1
    relaxable_rules TEXT NOT NULL,                   -- JSON array
    deviation_budget REAL NOT NULL,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 11. writing_shot_task_cards
CREATE TABLE writing_shot_task_cards (
    task_card_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL,
    compiled_instructions TEXT NOT NULL,
    superseded_at TEXT,                              -- B88 supersede
    created_at TEXT NOT NULL,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 12. writing_prompt_snapshots
CREATE TABLE writing_prompt_snapshots (
    prompt_id INTEGER PRIMARY KEY,
    task_card_id INTEGER NOT NULL,
    persona TEXT NOT NULL,
    full_prompt_text TEXT NOT NULL,
    prompt_size_bytes INTEGER NOT NULL,              -- 评审 #31：超 writing_projects.prompt_archive_size_bytes 时迁到独立文件
    relaxed_soft INTEGER NOT NULL DEFAULT 0,         -- 仅 deviant
    is_stale INTEGER NOT NULL DEFAULT 0,             -- stale 传播标记
    superseded_at TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (task_card_id) REFERENCES writing_shot_task_cards(task_card_id) ON DELETE CASCADE
);
-- prompt 归档策略：prompt_size_bytes > writing_projects.prompt_archive_size_bytes 时 full_prompt_text 迁到 prompts/{prompt_id}.txt，列存路径
-- supersede 历史保留：旧 prompt 不删，superseded_at 标记，供审计回溯

-- 13. writing_shots
CREATE TABLE writing_shots (
    shot_id TEXT PRIMARY KEY,                        -- {logical}@{run} 隔离
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    volume_id TEXT,                                    -- 所属卷 ID（冗余，便于 stale 传播精确筛选）
    part_id TEXT,                                      -- 所属部分 ID（冗余，便于 stale 传播精确筛选）
    shot_contract_id INTEGER,
    run_id INTEGER NOT NULL,
    logical_shot_id TEXT NOT NULL,                   -- 评审 #6：N 计数绑 logical_shot_id（跨 run 累积）
    status TEXT NOT NULL CHECK (status IN (
        'pending','outline_draft','outline_confirmed',
        'task_card_compiled','prompt_compiled',
        'drafting','hard_gate1','hard_gate2',
        'jury_scoring','winner_selected','polish_revision',
        'soft_sealed','hard_sealed','failed'
    )),                                             -- 14 态，resume 映射见 §3.6
    retry_count INTEGER NOT NULL DEFAULT 0,
    soft_fail_counts_snapshot TEXT NOT NULL DEFAULT '{}', -- JSON 审计快照；业务不得读取，权威源是 writing_soft_gate_counters
    redo_in_progress INTEGER NOT NULL DEFAULT 0,     -- 评审 #6：N=2 局部重写子状态标记
    resume_point TEXT,                               -- 评审 #17：结构化 JSON {phase, chapter_id, dimension_index}
    llm_call_count INTEGER NOT NULL DEFAULT 0,       -- 评审 P0-5：shot 内 LLM 总调用计数（上限 = writing_projects.max_total_llm_calls）
    llm_call_breakdown TEXT NOT NULL DEFAULT '{}',   -- 评审 P0-5：JSON {call_type: count}，单类型上限 = writing_projects.max_calls_per_shot
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,                        -- 评审 #28：状态机变更时间
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id),
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE
);
CREATE INDEX idx_shots_logical ON writing_shots(logical_shot_id);
CREATE INDEX idx_shots_run ON writing_shots(run_id);
CREATE INDEX idx_shots_volume ON writing_shots(project_id, volume_id);
CREATE INDEX idx_shots_part ON writing_shots(project_id, part_id);

-- 14. writing_soft_gate_counters
-- 唯一权威源：每 (project_id, logical_shot_id, gate_name) 一行，N 计数原子累加。
-- writing_shots.soft_fail_counts_snapshot 仅为审计快照，业务读 N 必须查本表。
CREATE TABLE writing_soft_gate_counters (
    counter_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    logical_shot_id TEXT NOT NULL,                   -- 跨 run 累积（绑 logical 非 attempt）
    gate_name TEXT NOT NULL,
    n INTEGER NOT NULL DEFAULT 0 CHECK (n >= 0),
    last_incremented_at TEXT NOT NULL,
    last_level INTEGER NOT NULL DEFAULT 0 CHECK (last_level IN (0,1,2,3)),  -- 0=未触发
    UNIQUE (project_id, logical_shot_id, gate_name),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX idx_soft_gate_logical ON writing_soft_gate_counters(project_id, logical_shot_id);

-- 15. writing_runs
CREATE TABLE writing_runs (
    run_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    session_id INTEGER NOT NULL,
    run_attempt INTEGER NOT NULL,                    -- 同 session 的第 N 次尝试
    started_at TEXT NOT NULL,
    finished_at TEXT,
    status TEXT NOT NULL CHECK (status IN ('running','completed','crashed','aborted')),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES writing_sessions(session_id) ON DELETE CASCADE
);

-- 16. writing_sessions
CREATE TABLE writing_sessions (
    session_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    started_at TEXT NOT NULL,
    crashed INTEGER NOT NULL DEFAULT 0,
    resume_point TEXT,                               -- 崩溃恢复点（结构化 JSON，见 §3.6）
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);

-- 17. writing_drafts
CREATE TABLE writing_drafts (
    draft_id INTEGER PRIMARY KEY,
    shot_id TEXT NOT NULL,
    prompt_id INTEGER NOT NULL,
    persona TEXT NOT NULL,
    writer_model TEXT NOT NULL,                      -- 换模型获多样性
    text TEXT NOT NULL,
    degraded INTEGER NOT NULL DEFAULT 0,             -- 铁律 3
    failure_category TEXT,
    retry_count INTEGER NOT NULL DEFAULT 0,
    is_deviant INTEGER NOT NULL DEFAULT 0,           -- deviant 沙盒稿
    is_stale INTEGER NOT NULL DEFAULT 0,             -- stale 传播标记
    byte_count INTEGER NOT NULL,
    source_revision_id INTEGER,                      -- 评审 #12/#21：B92 stale 检测，指向 revisions
    created_at TEXT NOT NULL,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (prompt_id) REFERENCES writing_prompt_snapshots(prompt_id) ON DELETE CASCADE,
    FOREIGN KEY (source_revision_id) REFERENCES writing_shot_revisions(revision_id)
);
CREATE INDEX idx_drafts_shot ON writing_drafts(shot_id);

-- 18. writing_shot_revisions（正文，物理隔离）
-- 只允许 core/text_repository 模块通过 Python import + DB VIEW 访问
CREATE TABLE writing_shot_revisions (
    revision_id INTEGER PRIMARY KEY,
    shot_id TEXT NOT NULL,
    run_id INTEGER NOT NULL,
    revision_sequence INTEGER NOT NULL,
    text TEXT NOT NULL,
    is_current INTEGER NOT NULL DEFAULT 0,           -- B19 封版规则
    sealed_at TEXT,                                  -- 硬封版时间
    sealed_by TEXT,                                  -- 'shot_soft' | 'chapter_hard'
    source_revision_id INTEGER,                      -- 评审 #12：跨 run stale 检测（B92），指向上游 revision
    created_at TEXT NOT NULL,
    UNIQUE (shot_id, revision_sequence),
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (source_revision_id) REFERENCES writing_shot_revisions(revision_id)
);
CREATE UNIQUE INDEX uq_revisions_one_current ON writing_shot_revisions(shot_id) WHERE is_current = 1;
CREATE INDEX idx_revisions_current ON writing_shot_revisions(shot_id, is_current) WHERE is_current = 1;
CREATE INDEX idx_revisions_seq ON writing_shot_revisions(shot_id, revision_sequence);

-- DB VIEW：封版逻辑封装，业务模块查 view 而非原表（评审 #3 修复）
-- 评审 P0-3 修订：原 WHERE is_current=1 OR revision_sequence=(MAX) 是 OR 并集语义，
-- 同 shot 既有 is_current=1 封版行又有更高 revision_sequence 未封版行（redo/崩溃重跑场景）
-- 时会返回两行，违反 read_current_text 单条不变量。改为 ROW_NUMBER() 优先级单行返回：
-- is_current=1 优先于任何未封版行；同为未封版时 revision_sequence 高者优先。
CREATE VIEW v_current_text AS
SELECT revision_id, shot_id, run_id, text, revision_sequence, is_current, source_revision_id
FROM (
    SELECT revision_id, shot_id, run_id, text, revision_sequence, is_current, source_revision_id,
           ROW_NUMBER() OVER (
               PARTITION BY shot_id
               ORDER BY is_current DESC, revision_sequence DESC
           ) AS rn
    FROM writing_shot_revisions
)
WHERE rn = 1;
-- 不变量：每个 shot_id 在 v_current_text 中恰好一行。
-- 集成测试（M0 必补）：同 shot 存在 is_current=1 行 + 更高 revision_sequence 未封版行时，
-- SELECT * FROM v_current_text WHERE shot_id=? 只返回一行（is_current=1 那行）。

-- 19. writing_draft_eligibility（2 道硬门槛）
-- 评审 medium 修订：8 个 eligible 列补 CHECK(0,1) + 子项一致性 CHECK（eligible=1 要求所有子项=1）
CREATE TABLE writing_draft_eligibility (
    eligibility_id INTEGER PRIMARY KEY,
    draft_id INTEGER NOT NULL,
    gate1_eligible INTEGER NOT NULL CHECK (gate1_eligible IN (0,1)),
    gate1_contract_compliance INTEGER NOT NULL CHECK (gate1_contract_compliance IN (0,1)),
    gate1_forbidden_check INTEGER NOT NULL CHECK (gate1_forbidden_check IN (0,1)),
    gate1_capacity INTEGER NOT NULL CHECK (gate1_capacity IN (0,1)),
    gate1_basic_readability INTEGER NOT NULL CHECK (gate1_basic_readability IN (0,1)),
    gate2_eligible INTEGER NOT NULL CHECK (gate2_eligible IN (0,1)),
    gate2_fact_anchor INTEGER NOT NULL CHECK (gate2_fact_anchor IN (0,1)),
    gate2_scene_contract INTEGER NOT NULL CHECK (gate2_scene_contract IN (0,1)),
    gate2_pov_compliance INTEGER NOT NULL CHECK (gate2_pov_compliance IN (0,1)),
    gate2_structure_skeleton INTEGER NOT NULL CHECK (gate2_structure_skeleton IN (0,1)),
    evaluated_at TEXT NOT NULL,
    -- gate1_eligible=1 当且仅当 4 子项全 1（eligible=0 但子项全 1 非法；eligible=1 但某子项=0 非法）
    CHECK (gate1_eligible = (gate1_contract_compliance AND gate1_forbidden_check AND gate1_capacity AND gate1_basic_readability)),
    CHECK (gate2_eligible = (gate2_fact_anchor AND gate2_scene_contract AND gate2_pov_compliance AND gate2_structure_skeleton)),
    FOREIGN KEY (draft_id) REFERENCES writing_drafts(draft_id) ON DELETE CASCADE
);
CREATE INDEX idx_eligibility_draft ON writing_draft_eligibility(draft_id);

-- 20. writing_jury_raw_scores（裁判原始分）
-- 基础轮 jury_round=1：3 裁判全评 12 维，无稀疏 NULL。
-- 分歧升级轮 jury_round>1：可使用 writing_projects.escalated_jury_count（默认 5）个裁判重评。
-- judge_role 只是 prompt 主视角标签，不是裁判身份标识；同一 role 可在升级轮重复。
-- 真正由 DB 保证的不变量："同一 draft 同一 jury_round 同一 judge_model/slot 只能一行"。
-- "judge_model 不等于该 draft 的 writer_model" 是跨表约束：
-- 1) literary_jury.dispatch 按 draft 动态排除；
-- 2) SQLite trigger 在落库时兜底阻断；
-- 3) post-write JOIN 审计作为测试门禁。
CREATE TABLE writing_jury_raw_scores (
    raw_score_id INTEGER PRIMARY KEY,
    draft_id INTEGER NOT NULL,
    shot_contract_id INTEGER NOT NULL,
    jury_round INTEGER NOT NULL DEFAULT 1 CHECK (jury_round >= 1),  -- 1=基础 3 裁判；>1=分歧升级重评
    judge_slot INTEGER NOT NULL CHECK (judge_slot >= 1),            -- 该轮第几个裁判，基础轮为 1..3，升级轮为 1..escalated_jury_count
    judge_model TEXT NOT NULL,                       -- 裁判模型（身份标识）
    judge_role TEXT NOT NULL CHECK (judge_role IN ('text','literary','cross_shot')),
    -- 12 维分数（0-100），3 裁判全填（方案 B），NOT NULL + CHECK 区间（评审 medium）
    scene_visual INTEGER NOT NULL CHECK (scene_visual BETWEEN 0 AND 100),                   -- 画面感官
    rhythm_pacing INTEGER NOT NULL CHECK (rhythm_pacing BETWEEN 0 AND 100),                 -- 节奏张弛
    dialogue_subtext INTEGER NOT NULL CHECK (dialogue_subtext BETWEEN 0 AND 100),           -- 对话潜台词
    suspense_tension INTEGER NOT NULL CHECK (suspense_tension BETWEEN 0 AND 100),           -- 悬疑紧张
    language_texture INTEGER NOT NULL CHECK (language_texture BETWEEN 0 AND 100),           -- 语言质感
    emotional_progression INTEGER NOT NULL CHECK (emotional_progression BETWEEN 0 AND 100), -- 情感推进
    character_believability INTEGER NOT NULL CHECK (character_believability BETWEEN 0 AND 100), -- 人物可信
    structure_landing INTEGER NOT NULL CHECK (structure_landing BETWEEN 0 AND 100),         -- 结构落地
    reading_fluency INTEGER NOT NULL CHECK (reading_fluency BETWEEN 0 AND 100),             -- 可读流畅
    motif_theme_fit INTEGER NOT NULL CHECK (motif_theme_fit BETWEEN 0 AND 100),             -- 母题主题贴合
    chapter_continuity INTEGER NOT NULL CHECK (chapter_continuity BETWEEN 0 AND 100),       -- 章续衔接
    creative_boundary INTEGER NOT NULL CHECK (creative_boundary BETWEEN 0 AND 100),         -- 创意边界（裁判3 参考 deviant_reference）
    evaluated_at TEXT NOT NULL,
    -- 不变量：同一 draft 同一 jury_round 内，同一 slot/model 只能出现一次（防重复评分，评审 P0-4）
    UNIQUE (draft_id, jury_round, judge_slot),
    UNIQUE (draft_id, jury_round, judge_model),
    FOREIGN KEY (draft_id) REFERENCES writing_drafts(draft_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);
-- 应用层断言（literary_jury.dispatch 落库后校验，DB 层 CHECK 无法表达"每轮恰好 N 行"）：
-- 基础轮：jury_round=1 必须 count(*)=3 且 count(DISTINCT judge_model)=3，judge_slot=1..3。
-- 升级轮：jury_round>1 必须 count(*)=writing_projects.escalated_jury_count，且模型去重。
CREATE INDEX idx_jury_raw_draft ON writing_jury_raw_scores(draft_id, jury_round, judge_model);

CREATE TRIGGER trg_jury_raw_no_self_judge_insert
BEFORE INSERT ON writing_jury_raw_scores
FOR EACH ROW
WHEN EXISTS (
    SELECT 1 FROM writing_drafts d
    WHERE d.draft_id = NEW.draft_id AND d.writer_model = NEW.judge_model
)
BEGIN
    SELECT RAISE(ABORT, 'judge_model must differ from writer_model');
END;

CREATE TRIGGER trg_jury_raw_no_self_judge_update
BEFORE UPDATE OF draft_id, judge_model ON writing_jury_raw_scores
FOR EACH ROW
WHEN EXISTS (
    SELECT 1 FROM writing_drafts d
    WHERE d.draft_id = NEW.draft_id AND d.writer_model = NEW.judge_model
)
BEGIN
    SELECT RAISE(ABORT, 'judge_model must differ from writer_model');
END;

-- 21. writing_jury_aggregates（评分聚合，1 行/draft）
CREATE TABLE writing_jury_aggregates (
    aggregate_id INTEGER PRIMARY KEY,
    shot_id TEXT NOT NULL,
    draft_id INTEGER NOT NULL UNIQUE,
    shot_contract_id INTEGER NOT NULL,
    jury_round_used INTEGER NOT NULL DEFAULT 1 CHECK (jury_round_used >= 1), -- 聚合采用的 raw score 轮次；分歧升级后使用最新升级轮
    judge_count INTEGER NOT NULL DEFAULT 3 CHECK (judge_count >= 3),         -- 该轮参与聚合的裁判数，基础轮 3，升级轮 escalated_jury_count
    -- 12 维中位数得分（3 样本去 1 高 1 低剩 1 个 = median，P0-1 诚实声明：trimmed mean 退化为 median）
    scene_visual_median REAL NOT NULL CHECK (scene_visual_median BETWEEN 0 AND 100),
    rhythm_pacing_median REAL NOT NULL CHECK (rhythm_pacing_median BETWEEN 0 AND 100),
    dialogue_subtext_median REAL NOT NULL CHECK (dialogue_subtext_median BETWEEN 0 AND 100),
    suspense_tension_median REAL NOT NULL CHECK (suspense_tension_median BETWEEN 0 AND 100),
    language_texture_median REAL NOT NULL CHECK (language_texture_median BETWEEN 0 AND 100),
    emotional_progression_median REAL NOT NULL CHECK (emotional_progression_median BETWEEN 0 AND 100),
    character_believability_median REAL NOT NULL CHECK (character_believability_median BETWEEN 0 AND 100),
    structure_landing_median REAL NOT NULL CHECK (structure_landing_median BETWEEN 0 AND 100),
    reading_fluency_median REAL NOT NULL CHECK (reading_fluency_median BETWEEN 0 AND 100),
    motif_theme_fit_median REAL NOT NULL CHECK (motif_theme_fit_median BETWEEN 0 AND 100),
    chapter_continuity_median REAL NOT NULL CHECK (chapter_continuity_median BETWEEN 0 AND 100),
    creative_boundary_median REAL NOT NULL CHECK (creative_boundary_median BETWEEN 0 AND 100),
    weight_used TEXT NOT NULL,                       -- JSON：12 维加权权重 + _intensity_5d + _Z（weight_map 输出，见 §3.5）
    final_score REAL NOT NULL,                       -- 加权平均分（Σ median[d] × weight[d]）
    quality_gate_passed INTEGER NOT NULL DEFAULT 0 CHECK (quality_gate_passed IN (0,1)),
    quality_gate_reasons TEXT NOT NULL DEFAULT '[]', -- JSON：未通过维度/原因/证据
    judge_disagreement_max REAL NOT NULL DEFAULT 0 CHECK (judge_disagreement_max BETWEEN 0 AND 100),
    is_winner INTEGER NOT NULL DEFAULT 0,
    evaluated_at TEXT NOT NULL,
    -- 绝对底线 CHECK：项目运营阈值（writing_projects 表对应字段）不得低于此，由应用层取 max(项目阈值, 绝对底线) 执行。
    CHECK (quality_gate_passed = 0 OR final_score >= 80),          -- 绝对底线，运营阈值见 writing_projects.shot_quality_floor
    CHECK (quality_gate_passed = 0 OR judge_disagreement_max <= 25),  -- 绝对底线，运营阈值见 writing_projects.judge_disagreement_max
    CHECK (quality_gate_passed = 0 OR (
        scene_visual_median >= 65 AND rhythm_pacing_median >= 65 AND dialogue_subtext_median >= 65 AND
        suspense_tension_median >= 65 AND language_texture_median >= 65 AND emotional_progression_median >= 65 AND
        character_believability_median >= 65 AND structure_landing_median >= 65 AND reading_fluency_median >= 65 AND
        motif_theme_fit_median >= 65 AND chapter_continuity_median >= 65 AND creative_boundary_median >= 65
    )),  -- 绝对底线 65，运营阈值见 writing_projects.dimension_floor
    CHECK (is_winner = 0 OR quality_gate_passed = 1),
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (draft_id) REFERENCES writing_drafts(draft_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX idx_jury_aggregate_winner ON writing_jury_aggregates(shot_id) WHERE is_winner = 1;

-- 22. writing_chapter_reviews（章级 8 维硬质量门禁）
-- 质量硬门禁修订：8 维全部是 accepted 前硬门禁；问题可注入后文，但不能替代本章达标。
CREATE TABLE writing_chapter_reviews (
    review_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    run_id INTEGER NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending','accepted','rejected','revised')),
    is_stale INTEGER NOT NULL DEFAULT 0,             -- stale 传播标记
    -- 章级 8 维（accepted 前全部必须达标），0-100
    chapter_continuity_hard INTEGER CHECK (chapter_continuity_hard IS NULL OR chapter_continuity_hard BETWEEN 0 AND 100),
    pov_consistency INTEGER CHECK (pov_consistency IS NULL OR pov_consistency BETWEEN 0 AND 100),
    character_consistency INTEGER CHECK (character_consistency IS NULL OR character_consistency BETWEEN 0 AND 100),
    chapter_hook_soft INTEGER CHECK (chapter_hook_soft IS NULL OR chapter_hook_soft BETWEEN 0 AND 100),
    rhythm_curve INTEGER CHECK (rhythm_curve IS NULL OR rhythm_curve BETWEEN 0 AND 100),
    motif_density INTEGER CHECK (motif_density IS NULL OR motif_density BETWEEN 0 AND 100),
    info_gap_lifecycle INTEGER CHECK (info_gap_lifecycle IS NULL OR info_gap_lifecycle BETWEEN 0 AND 100),
    chapter_coherence INTEGER CHECK (chapter_coherence IS NULL OR chapter_coherence BETWEEN 0 AND 100),
    quality_gate_passed INTEGER NOT NULL DEFAULT 0 CHECK (quality_gate_passed IN (0,1)),
    blocking_issues TEXT NOT NULL DEFAULT '[]',      -- JSON：任一硬质量失败项
    review_notes TEXT,
    reviewed_at TEXT NOT NULL,
    -- accepted 要求 8 维非 NULL、全部 >= 绝对底线 75（运营阈值见 writing_projects.chapter_quality_floor）、质量门禁通过。
    CHECK (status != 'accepted' OR (
        quality_gate_passed = 1 AND
        chapter_continuity_hard IS NOT NULL AND pov_consistency IS NOT NULL AND character_consistency IS NOT NULL AND
        chapter_hook_soft IS NOT NULL AND rhythm_curve IS NOT NULL AND motif_density IS NOT NULL AND
        info_gap_lifecycle IS NOT NULL AND chapter_coherence IS NOT NULL AND
        chapter_continuity_hard >= 75 AND pov_consistency >= 75 AND character_consistency >= 75 AND
        chapter_hook_soft >= 75 AND rhythm_curve >= 75 AND motif_density >= 75 AND
        info_gap_lifecycle >= 75 AND chapter_coherence >= 75
    )),  -- 绝对底线 75，运营阈值见 writing_projects.chapter_quality_floor
    UNIQUE (project_id, chapter_id, run_id),   -- accepted canonical 唯一索引
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX idx_chapter_accepted ON writing_chapter_reviews(project_id, chapter_id) WHERE status = 'accepted';

-- 23. writing_failure_attributions（评审 #16：扩展审计链，支撑质量阻断与非质量降级追溯）
CREATE TABLE writing_failure_attributions (
    attribution_id INTEGER PRIMARY KEY,
    draft_id INTEGER,
    shot_id TEXT NOT NULL,
    failure_category TEXT NOT NULL,
    failure_level TEXT NOT NULL CHECK (failure_level IN ('draft','hard_gate1','hard_gate2','jury','quality_gate','polish','soft_gate','chapter_review','book_check')),
    contract_clause_id INTEGER,                      -- 指向 writing_contract_clauses，支撑 D-23 条款级审计
    gate_name TEXT,                                  -- 触发失败的 gate 名
    soft_gate_n INTEGER,                             -- soft gate 第 N 级（1/2/3）
    injected_to_shot_id TEXT,                        -- 问题注入到哪个后续 shot
    failure_detail TEXT,
    degraded INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY (draft_id) REFERENCES writing_drafts(draft_id) ON DELETE CASCADE,
    FOREIGN KEY (contract_clause_id) REFERENCES writing_contract_clauses(clause_id),
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_attribution_shot ON writing_failure_attributions(shot_id);

-- 24. writing_information_gaps（评审 #9：加 abandoned 终态 + 转移合法性）
-- 评审 medium 修订：补转移合法性 CASE CHECK（DB 层拦截非法跳转，如 pending 直接 resolved）
CREATE TABLE writing_information_gaps (
    gap_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    gap_name TEXT NOT NULL,
    planted_chapter INTEGER NOT NULL,
    planted_shot TEXT,
    -- 转移合法性（prev_status → status）：
    --   pending → active
    --   active → reinforced | revealed | resolved | abandoned
    --   reinforced → reinforced | revealed | resolved | abandoned
    --   revealed → resolved | abandoned
    --   resolved → （终态，无出边）
    --   abandoned → （终态，无出边）
    -- 应用层写 status 时同事务写 prev_status；DB CHECK 断言 (prev_status, status) 合法。
    prev_status TEXT,   -- 上一状态（NULL 表示首次插入 pending）
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','reinforced','revealed','resolved','abandoned')),
    resolved_chapter INTEGER,
    resolved_shot TEXT,
    abandoned_chapter INTEGER,                       -- 放弃章节
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    CHECK ((
        prev_status IS NULL AND status = 'pending'
    ) OR (
        prev_status = 'pending' AND status = 'active'
    ) OR (
        prev_status IN ('active','reinforced') AND status IN ('reinforced','revealed','resolved','abandoned')
    ) OR (
        prev_status = 'revealed' AND status IN ('resolved','abandoned')
    ) OR (
        prev_status = status AND status IN ('reinforced')  -- reinforced 自环（多次加固）
    )),
    UNIQUE (project_id, gap_name),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX idx_info_gap_status ON writing_information_gaps(project_id, status);

-- 25. writing_motif_instances
CREATE TABLE writing_motif_instances (
    motif_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    motif_name TEXT NOT NULL,
    chapter_id INTEGER NOT NULL,
    shot_id TEXT,
    instance_text TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_motif_project_chapter ON writing_motif_instances(project_id, chapter_id);

-- 26. writing_shot_scene_fingerprints（L3 多样性 gate，与 motif 同层管理）
CREATE TABLE writing_shot_scene_fingerprints (
    fingerprint_id INTEGER PRIMARY KEY,
    shot_id TEXT NOT NULL,
    location_hash TEXT NOT NULL,
    time_hash TEXT NOT NULL,
    character_set_hash TEXT NOT NULL,
    similarity_score REAL,                           -- 与近邻 shot 的场景相似度
    created_at TEXT NOT NULL,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_fingerprint_shot ON writing_shot_scene_fingerprints(shot_id);

-- 27. writing_book_check_results（篇级检测结果，支撑增量检测）
CREATE TABLE writing_book_check_results (
    check_run_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    check_sequence INTEGER NOT NULL,                 -- 第 k 次检测
    chapter_range_start INTEGER NOT NULL,            -- 本次检测起始章
    chapter_range_end INTEGER NOT NULL,              -- 本次检测截止章（= 当前章）
    is_stale INTEGER NOT NULL DEFAULT 0,             -- stale 传播标记
    -- 6 维全书级检测分数
    longline_suspense_closure REAL,                  -- 长线悬念闭环
    character_arc_completeness REAL,                 -- 角色弧光完整
    motif_echo_density REAL,                         -- 母题回响
    theme_sublimation REAL,                          -- 主题升华
    global_rhythm_curve REAL,                        -- 全书节奏曲线
    foreshadow_recovery REAL,                        -- 伏笔回收
    is_incremental INTEGER NOT NULL DEFAULT 0,       -- 是否增量检测（1=只检测新增章节）
    issues TEXT NOT NULL,                            -- JSON：问题列表（注入到 chapter_specs.injected_issues）
    blocking_issue_count INTEGER NOT NULL DEFAULT 0 CHECK (blocking_issue_count >= 0),
    quality_gate_passed INTEGER NOT NULL DEFAULT 0 CHECK (quality_gate_passed IN (0,1)),
    created_at TEXT NOT NULL,
    CHECK (quality_gate_passed = 0 OR blocking_issue_count = 0),
    CHECK (quality_gate_passed = 0 OR (
        longline_suspense_closure IS NOT NULL AND character_arc_completeness IS NOT NULL AND motif_echo_density IS NOT NULL AND
        theme_sublimation IS NOT NULL AND global_rhythm_curve IS NOT NULL AND foreshadow_recovery IS NOT NULL AND
        longline_suspense_closure >= 75 AND character_arc_completeness >= 75 AND motif_echo_density >= 75 AND
        theme_sublimation >= 75 AND global_rhythm_curve >= 75 AND foreshadow_recovery >= 75
    )),  -- 绝对底线 75，运营阈值见 writing_projects.book_quality_floor
    UNIQUE (project_id, check_sequence),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX idx_book_check_project ON writing_book_check_results(project_id, chapter_range_end);

-- 28. writing_ai_call_attempts（所有 AI 调用的幂等审计）
CREATE TABLE writing_ai_call_attempts (
    attempt_id INTEGER PRIMARY KEY,
    idempotency_key TEXT NOT NULL UNIQUE,
    project_id INTEGER NOT NULL,
    shot_id TEXT,
    run_id INTEGER,
    call_type TEXT NOT NULL CHECK (call_type IN ('outline','task_card','prompt','draft','polish','gate1_semantic','gate2','jury','chapter_review','book_check','import','source_extraction')),
    model_provider TEXT NOT NULL,
    model_name TEXT NOT NULL,
    prompt_id INTEGER,
    prompt_hash TEXT NOT NULL,
    response_hash TEXT,
    response_path TEXT,
    token_input INTEGER,
    token_output INTEGER,
    latency_ms INTEGER,
    finish_reason TEXT,
    success INTEGER NOT NULL CHECK (success IN (0,1)),
    error_category TEXT,
    retry_of INTEGER,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (prompt_id) REFERENCES writing_prompt_snapshots(prompt_id),
    FOREIGN KEY (retry_of) REFERENCES writing_ai_call_attempts(attempt_id)
);
CREATE INDEX idx_ai_attempts_shot ON writing_ai_call_attempts(shot_id, call_type, created_at);

-- 29. writing_runtime_events（运行时事件时间线）
CREATE TABLE writing_runtime_events (
    event_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    session_id INTEGER,
    run_id INTEGER,
    shot_id TEXT,
    event_type TEXT NOT NULL,
    event_payload TEXT NOT NULL,                      -- JSON
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES writing_sessions(session_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_runtime_events_timeline ON writing_runtime_events(project_id, created_at);

-- 30. writing_llm_failure_streaks（连续失败计数权威源）
CREATE TABLE writing_llm_failure_streaks (
    streak_id INTEGER PRIMARY KEY,
    shot_id TEXT NOT NULL,
    call_type TEXT NOT NULL,
    failure_type TEXT NOT NULL,
    consecutive_count INTEGER NOT NULL DEFAULT 0 CHECK (consecutive_count >= 0),
    last_error_at TEXT NOT NULL,
    UNIQUE (shot_id, call_type, failure_type),
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);

-- 31. writing_session_checkpoints（崩溃恢复 checkpoint）
-- 崩溃恢复幂等性设计（见 §3.8）：
-- 1. checkpoint 写入必须原子（事务内完成 payload + checksum 一起写入）
-- 2. 恢复时先校验 checksum，不匹配则视为损坏，回退到上一个有效 checkpoint
-- 3. checkpoint_max_retention 控制保留数量，避免无限增长
CREATE TABLE writing_session_checkpoints (
    checkpoint_id INTEGER PRIMARY KEY,
    session_id INTEGER NOT NULL,
    run_id INTEGER,
    shot_id TEXT,
    phase TEXT NOT NULL,
    checkpoint_payload TEXT NOT NULL,                -- JSON：恢复所需的状态快照
    payload_checksum TEXT NOT NULL,                  -- SHA-256(checkpoint_payload)，用于检测部分写入/损坏
    created_at TEXT NOT NULL,
    CHECK (shot_id IS NULL OR shot_id LIKE '%@%'),   -- NULL 表示 session/phase 级 checkpoint
    FOREIGN KEY (session_id) REFERENCES writing_sessions(session_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_checkpoints_session ON writing_session_checkpoints(session_id, created_at);

-- 32. writing_human_decisions（人工决策审计）
CREATE TABLE writing_human_decisions (
    decision_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    session_id INTEGER,
    run_id INTEGER,
    shot_id TEXT,
    chapter_id INTEGER,
    decision_type TEXT NOT NULL CHECK (decision_type IN ('setup_confirm','contract_confirm','accept','revise','reject','abort','import_finalize')),
    actor TEXT NOT NULL,
    reason TEXT NOT NULL,
    preconditions_json TEXT NOT NULL,                -- JSON：accept/revise/reject 前置条件校验结果
    quality_report_json TEXT NOT NULL DEFAULT '{}',  -- JSON：QualityReport，含 ES/SEMI_ES/NES、destructive/productive/neutral、盲评与继续阅读
    hard_quality_override INTEGER NOT NULL DEFAULT 0 CHECK (hard_quality_override = 0), -- 硬质量失败不可人工覆盖
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES writing_sessions(session_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_human_decisions_project ON writing_human_decisions(project_id, chapter_id, created_at);

-- 33. writing_contract_clauses（条款级契约审计）
CREATE TABLE writing_contract_clauses (
    clause_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    shot_contract_id INTEGER,
    clause_scope TEXT NOT NULL CHECK (clause_scope IN ('meta','chapter','shot')),
    clause_key TEXT NOT NULL,
    clause_text TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('hard','soft','diagnostic')),
    source_hash TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);
CREATE INDEX idx_contract_clauses_scope ON writing_contract_clauses(project_id, clause_scope, clause_key);

-- 34. writing_contract_changelog（契约变更历史）
CREATE TABLE writing_contract_changelog (
    change_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    clause_id INTEGER,
    old_hash TEXT,
    new_hash TEXT NOT NULL,
    actor TEXT NOT NULL,
    reason TEXT NOT NULL,
    human_decision_id INTEGER,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (clause_id) REFERENCES writing_contract_clauses(clause_id),
    FOREIGN KEY (human_decision_id) REFERENCES writing_human_decisions(decision_id)
);

-- 35. writing_fact_anchors（事实锚点）
CREATE TABLE writing_fact_anchors (
    anchor_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    shot_id TEXT,
    revision_id INTEGER,
    fact_text TEXT NOT NULL,
    source_span TEXT,
    confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    status TEXT NOT NULL CHECK (status IN ('proposed','confirmed','violated','deprecated')),
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (revision_id) REFERENCES writing_shot_revisions(revision_id)
);
CREATE INDEX idx_fact_anchors_project ON writing_fact_anchors(project_id, status);

-- 36. writing_context_snapshots（prompt/context 输入快照）
CREATE TABLE writing_context_snapshots (
    context_snapshot_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    shot_id TEXT NOT NULL,
    run_id INTEGER NOT NULL,
    prompt_id INTEGER,
    context_hash TEXT NOT NULL,
    upstream_revision_ids TEXT NOT NULL,             -- JSON array
    context_payload TEXT NOT NULL,                   -- JSON，供 replay 和 stale 检测
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (prompt_id) REFERENCES writing_prompt_snapshots(prompt_id)
);
CREATE INDEX idx_context_snapshots_shot ON writing_context_snapshots(shot_id, run_id);

-- 37. writing_import_runs（已有稿导入/重构批次）
CREATE TABLE writing_import_runs (
    import_run_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    mode TEXT NOT NULL CHECK (mode IN ('dry_run','finalize')),
    source_root TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('running','needs_human','completed','failed')),
    created_at TEXT NOT NULL,
    finalized_at TEXT,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);

-- 38. writing_import_manifests（导入映射清单）
CREATE TABLE writing_import_manifests (
    manifest_id INTEGER PRIMARY KEY,
    import_run_id INTEGER NOT NULL,
    source_path TEXT NOT NULL,
    source_hash TEXT NOT NULL,
    target_chapter_id INTEGER,
    target_logical_shot_id TEXT,
    confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    action TEXT NOT NULL CHECK (action IN ('create','update','skip','question')),
    created_at TEXT NOT NULL,
    FOREIGN KEY (import_run_id) REFERENCES writing_import_runs(import_run_id) ON DELETE CASCADE
);
CREATE INDEX idx_import_manifest_run ON writing_import_manifests(import_run_id, target_chapter_id);

-- 39. writing_import_questions（低置信导入问题）
CREATE TABLE writing_import_questions (
    question_id INTEGER PRIMARY KEY,
    import_run_id INTEGER NOT NULL,
    manifest_id INTEGER,
    question_text TEXT NOT NULL,
    options_json TEXT NOT NULL,
    resolution TEXT,
    resolved_by TEXT,
    resolved_at TEXT,
    FOREIGN KEY (import_run_id) REFERENCES writing_import_runs(import_run_id) ON DELETE CASCADE,
    FOREIGN KEY (manifest_id) REFERENCES writing_import_manifests(manifest_id) ON DELETE CASCADE
);

-- 40. writing_import_decisions（导入 finalize 决策）
CREATE TABLE writing_import_decisions (
    import_decision_id INTEGER PRIMARY KEY,
    import_run_id INTEGER NOT NULL,
    human_decision_id INTEGER NOT NULL,
    applied_manifest_hash TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (import_run_id) REFERENCES writing_import_runs(import_run_id) ON DELETE CASCADE,
    FOREIGN KEY (human_decision_id) REFERENCES writing_human_decisions(decision_id)
);

-- 41. writing_source_documents（v1.1 主编台源文档注册表）
CREATE TABLE writing_source_documents (
    source_document_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    source_path TEXT NOT NULL,
    source_kind TEXT NOT NULL CHECK (source_kind IN ('guide','outline','character','world','draft','process_scratch','other')),
    priority INTEGER NOT NULL DEFAULT 100,
    content_hash TEXT NOT NULL,
    processed_hash TEXT,
    status TEXT NOT NULL CHECK (status IN ('active','processed','stale','cleared','rejected')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE (project_id, source_path, content_hash),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX idx_source_documents_project_status ON writing_source_documents(project_id, status);

-- 42. writing_atomic_source_clauses（源文档原子条款）
CREATE TABLE writing_atomic_source_clauses (
    atomic_clause_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    source_document_id INTEGER NOT NULL,
    scope_type TEXT NOT NULL CHECK (scope_type IN ('book','volume','part','chapter','shot','source')),
    scope_id TEXT,
    clause_type TEXT NOT NULL CHECK (clause_type IN ('plot','character','world','style','quality','forbidden','process')),
    severity TEXT NOT NULL CHECK (severity IN ('hard','soft','diagnostic')),
    clause_text TEXT NOT NULL,
    source_refs_json TEXT NOT NULL CHECK (json_valid(source_refs_json)),
    source_hashes_json TEXT NOT NULL CHECK (json_valid(source_hashes_json)),
    status TEXT NOT NULL CHECK (status IN ('proposed','confirmed','superseded','rejected','stale')),
    supersedes_clause_id INTEGER,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (source_document_id) REFERENCES writing_source_documents(source_document_id) ON DELETE CASCADE,
    FOREIGN KEY (supersedes_clause_id) REFERENCES writing_atomic_source_clauses(atomic_clause_id)
);
CREATE INDEX idx_atomic_clauses_scope ON writing_atomic_source_clauses(project_id, scope_type, scope_id, status);

-- 43. writing_source_extraction_runs（primary/crosscheck 抽取审计）
CREATE TABLE writing_source_extraction_runs (
    extraction_run_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    source_document_id INTEGER NOT NULL,
    extractor_slot TEXT NOT NULL CHECK (extractor_slot IN ('primary','crosscheck')),
    model_provider TEXT NOT NULL,
    model_name TEXT NOT NULL,
    source_hash TEXT NOT NULL,
    extracted_clause_ids_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(extracted_clause_ids_json)),
    low_confidence_refs_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(low_confidence_refs_json)),
    status TEXT NOT NULL CHECK (status IN ('running','completed','failed','superseded')),
    created_at TEXT NOT NULL,
    finished_at TEXT,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (source_document_id) REFERENCES writing_source_documents(source_document_id) ON DELETE CASCADE
);
CREATE INDEX idx_source_extraction_document ON writing_source_extraction_runs(source_document_id, extractor_slot, status);

-- 44. writing_decision_sessions（可恢复人类决策会话）
CREATE TABLE writing_decision_sessions (
    decision_session_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    scope_type TEXT NOT NULL CHECK (scope_type IN ('book','volume','part','chapter','shot','review','import','source')),
    scope_id TEXT,
    target_type TEXT NOT NULL,
    target_id TEXT,
    parent_decision_session_id INTEGER,
    status TEXT NOT NULL CHECK (status IN ('collecting','ai_parsed','awaiting_confirm','needs_human','retryable_failed','stale','confirmed','cancelled')),
    human_text TEXT NOT NULL DEFAULT '',
    parsed_patch_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(parsed_patch_json)),
    readback_text TEXT NOT NULL DEFAULT '',
    source_hashes_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(source_hashes_json)),
    before_hash TEXT,
    after_hash TEXT,
    selected_option INTEGER CHECK (selected_option IS NULL OR selected_option BETWEEN 1 AND 8),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (parent_decision_session_id) REFERENCES writing_decision_sessions(decision_session_id)
);
CREATE UNIQUE INDEX idx_active_decision_session_target
ON writing_decision_sessions(project_id, target_type, COALESCE(target_id, ''))
WHERE status IN ('collecting','ai_parsed','awaiting_confirm','needs_human','retryable_failed');
CREATE UNIQUE INDEX idx_active_decision_session_scope
ON writing_decision_sessions(project_id, scope_type, COALESCE(scope_id, ''))
WHERE status IN ('collecting','ai_parsed','awaiting_confirm','needs_human','retryable_failed');
CREATE INDEX idx_decision_sessions_scope ON writing_decision_sessions(project_id, scope_type, scope_id, status);

-- 45. writing_decision_option_sets（1-8/0/9 选择式对话）
CREATE TABLE writing_decision_option_sets (
    option_set_id INTEGER PRIMARY KEY,
    decision_session_id INTEGER NOT NULL,
    version INTEGER NOT NULL,
    options_json TEXT NOT NULL CHECK (
        json_valid(options_json)
        AND json_type(options_json) = 'array'
        AND json_array_length(options_json) BETWEEN 1 AND 8
    ),
    recommended_option INTEGER CHECK (recommended_option IS NULL OR recommended_option BETWEEN 1 AND 8),
    allow_back INTEGER NOT NULL DEFAULT 1 CHECK (allow_back IN (0,1)),
    allow_regenerate INTEGER NOT NULL DEFAULT 1 CHECK (allow_regenerate IN (0,1)),
    regenerate_count INTEGER NOT NULL DEFAULT 0 CHECK (regenerate_count >= 0),
    status TEXT NOT NULL CHECK (status IN ('active','selected','superseded','cancelled')),
    created_at TEXT NOT NULL,
    UNIQUE (decision_session_id, version),
    FOREIGN KEY (decision_session_id) REFERENCES writing_decision_sessions(decision_session_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX idx_active_decision_option_set
ON writing_decision_option_sets(decision_session_id)
WHERE status = 'active';

-- 46. writing_contract_versions（层级契约版本）
CREATE TABLE writing_contract_versions (
    contract_version_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    scope_type TEXT NOT NULL CHECK (scope_type IN ('book','volume','part','chapter','shot')),
    scope_id TEXT,
    version INTEGER NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('proposed','confirmed','locked','superseded','stale')),
    contract_json TEXT NOT NULL CHECK (json_valid(contract_json)),
    contract_hash TEXT NOT NULL,
    source_clause_ids_json TEXT NOT NULL CHECK (json_valid(source_clause_ids_json)),
    created_from_decision_session_id INTEGER,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (created_from_decision_session_id) REFERENCES writing_decision_sessions(decision_session_id)
);
CREATE UNIQUE INDEX idx_contract_versions_unique_scope
ON writing_contract_versions(project_id, scope_type, COALESCE(scope_id, ''), version);
CREATE INDEX idx_contract_versions_scope ON writing_contract_versions(project_id, scope_type, scope_id, status);

-- 47. writing_contract_patches（契约 patch 与 stale 影响）
CREATE TABLE writing_contract_patches (
    contract_patch_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    decision_session_id INTEGER NOT NULL,
    base_contract_version_id INTEGER,
    target_contract_version_id INTEGER,
    change_type TEXT NOT NULL CHECK (change_type IN ('refine','override','split','defer','reject','normalize')),
    patch_json TEXT NOT NULL CHECK (json_valid(patch_json)),
    affected_scopes_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(affected_scopes_json)),
    stale_downstream_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(stale_downstream_json)),
    source_clause_ids_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(source_clause_ids_json)),
    status TEXT NOT NULL CHECK (status IN ('proposed','confirmed','rejected','applied','stale')),
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (decision_session_id) REFERENCES writing_decision_sessions(decision_session_id) ON DELETE CASCADE,
    FOREIGN KEY (base_contract_version_id) REFERENCES writing_contract_versions(contract_version_id),
    FOREIGN KEY (target_contract_version_id) REFERENCES writing_contract_versions(contract_version_id)
);
CREATE INDEX idx_contract_patches_decision ON writing_contract_patches(decision_session_id, status);

-- 48. writing_source_coverage_matrix（原子条款 × contract field 覆盖矩阵）
CREATE TABLE writing_source_coverage_matrix (
    coverage_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    atomic_clause_id INTEGER,
    contract_scope_type TEXT NOT NULL CHECK (contract_scope_type IN ('book','volume','part','chapter','shot')),
    contract_scope_id TEXT,
    contract_field_path TEXT NOT NULL,
    coverage_status TEXT NOT NULL CHECK (coverage_status IN ('covered','gap','conflict','rejected','deferred','diagnostic')),
    decision_session_id INTEGER,
    evidence_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(evidence_json)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (atomic_clause_id) REFERENCES writing_atomic_source_clauses(atomic_clause_id) ON DELETE SET NULL,
    FOREIGN KEY (decision_session_id) REFERENCES writing_decision_sessions(decision_session_id)
);
CREATE INDEX idx_source_coverage_scope ON writing_source_coverage_matrix(project_id, contract_scope_type, contract_scope_id, coverage_status);
CREATE INDEX idx_source_coverage_field ON writing_source_coverage_matrix(project_id, contract_field_path, coverage_status);

-- 49. writing_process_file_manifests（过程文件清空后的审计 manifest，不保存正文/摘要）
CREATE TABLE writing_process_file_manifests (
    process_manifest_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    source_document_id INTEGER NOT NULL,
    source_path TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    processed_hash TEXT NOT NULL,
    cleared_at TEXT NOT NULL,
    extracted_clause_ids_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(extracted_clause_ids_json)),
    contract_patch_ids_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(contract_patch_ids_json)),
    decision_session_ids_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(decision_session_ids_json)),
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (source_document_id) REFERENCES writing_source_documents(source_document_id) ON DELETE CASCADE
);
CREATE INDEX idx_process_file_manifest_source ON writing_process_file_manifests(source_document_id, cleared_at);

-- 50. writing_decision_session_events（append-only 事件日志，用于状态回放）
CREATE TABLE writing_decision_session_events (
    event_id INTEGER PRIMARY KEY,
    decision_session_id INTEGER NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'created','input_received','ai_parsed','option_set_created',
        'option_selected','option_regenerated','confirmed','cancelled','stale'
    )),
    payload_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(payload_json)),
    created_at TEXT NOT NULL,
    FOREIGN KEY (decision_session_id) REFERENCES writing_decision_sessions(decision_session_id) ON DELETE CASCADE
);
CREATE INDEX idx_session_events_session ON writing_decision_session_events(decision_session_id, created_at);

-- 51. writing_contract_version_events（append-only 契约版本事件日志）
CREATE TABLE writing_contract_version_events (
    event_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    contract_version_id INTEGER,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'created','confirmed','locked','superseded','stale'
    )),
    scope_type TEXT NOT NULL CHECK (scope_type IN ('book','volume','part','chapter','shot')),
    scope_id TEXT,
    payload_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(payload_json)),
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (contract_version_id) REFERENCES writing_contract_versions(contract_version_id)
);
CREATE INDEX idx_version_events_scope ON writing_contract_version_events(project_id, scope_type, scope_id, created_at);

-- 52. writing_model_role_configs（v1.1 按 call_type 的模型角色主/备/兜底配置）
-- 每个 call_type 三行（primary/secondary/tertiary），尽量跨供应商；
-- LLMGateway.call 按 (project_id, call_type) 取主备兜底，失败逐 tier 切。
-- api_key 存环境变量名（api_key_env），不落明文 key。
CREATE TABLE writing_model_role_configs (
    role_config_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    call_type TEXT NOT NULL,                          -- outline/draft/jury/polish/chapter_review/book_check/
                                                     -- source_extract_primary/source_extract_crosscheck/
                                                     -- readback_verify/decision_session_parse
    tier TEXT NOT NULL CHECK (tier IN ('primary','secondary','tertiary')),
    model_name TEXT NOT NULL,                         -- 真实模型名（不存别名，别名路由在 tier 内翻译）
    provider TEXT NOT NULL,                           -- openai-compatible（DeepSeek/Qwen 各自 base_url）
    base_url TEXT,
    api_key_env TEXT NOT NULL,                        -- 环境变量名，运行时 os.environ 取明文 key
    max_tokens INTEGER,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE (project_id, call_type, tier),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX idx_role_configs_project_call ON writing_model_role_configs(project_id, call_type, tier);



-- 53. Chapter ethics review (global acceptance gate).
CREATE TABLE writing_chapter_ethics_reviews (
    ethics_review_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    run_id INTEGER NOT NULL,
    reviewer_actor TEXT NOT NULL,
    reviewer_models_json TEXT NOT NULL CHECK (
        json_valid(reviewer_models_json) AND json_type(reviewer_models_json)='array'
    ),
    responsibility_question TEXT NOT NULL,
    affected_parties_json TEXT NOT NULL CHECK (
        json_valid(affected_parties_json) AND json_type(affected_parties_json)='array'
    ),
    irreversible_harm TEXT NOT NULL,
    agency_obscured INTEGER NOT NULL CHECK (agency_obscured IN (0,1)),
    evidence_sentences_json TEXT NOT NULL CHECK (
        json_valid(evidence_sentences_json) AND json_type(evidence_sentences_json)='array'
    ),
    risk_level TEXT NOT NULL CHECK (risk_level IN ('low','medium','high','blocking')),
    recommendation TEXT NOT NULL CHECK (recommendation IN ('approve','revise')),
    review_notes TEXT NOT NULL,
    reviewed_at TEXT NOT NULL,
    UNIQUE (project_id, chapter_id, run_id),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE
);
CREATE INDEX idx_ethics_reviews_project_chapter
ON writing_chapter_ethics_reviews(project_id, chapter_id, run_id);

-- ============================================================================
-- Scene-first shadow schema (v2)
-- ============================================================================

-- 53. Stable Scene identity. Canonical text is never stored on this row.
CREATE TABLE writing_scenes (
    scene_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    logical_scene_key TEXT NOT NULL,
    scene_order INTEGER NOT NULL CHECK (scene_order >= 0),
    created_at TEXT NOT NULL,
    UNIQUE (project_id, chapter_id, logical_scene_key),
    UNIQUE (project_id, chapter_id, scene_order),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX idx_scenes_chapter ON writing_scenes(project_id, chapter_id, scene_order);

-- 54. Versioned four-layer Scene Contract.
CREATE TABLE writing_scene_contracts (
    scene_contract_id INTEGER PRIMARY KEY,
    scene_id INTEGER NOT NULL,
    version INTEGER NOT NULL CHECK (version >= 1),
    status TEXT NOT NULL CHECK (status IN (
        'draft', 'self_checked', 'under_review', 'revision_required',
        'human_resolution_required', 'approved', 'active', 'superseded'
    )),
    contract_hash TEXT NOT NULL,
    parent_contract_id INTEGER,
    source_bundle_hash TEXT NOT NULL,
    created_by TEXT NOT NULL,
    created_at TEXT NOT NULL,
    activated_at TEXT,
    superseded_at TEXT,
    UNIQUE (scene_id, version),
    FOREIGN KEY (scene_id) REFERENCES writing_scenes(scene_id) ON DELETE CASCADE,
    FOREIGN KEY (parent_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE UNIQUE INDEX idx_scene_contract_one_active
ON writing_scene_contracts(scene_id) WHERE status = 'active';

-- 55. Atomic Scene Contract clauses.
CREATE TABLE writing_scene_contract_clauses (
    clause_id INTEGER PRIMARY KEY,
    scene_contract_id INTEGER NOT NULL,
    layer TEXT NOT NULL CHECK (layer IN (
        'hard_constraint', 'source_dna', 'soft_goal', 'creative_opening'
    )),
    clause_key TEXT NOT NULL,
    clause_text TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('hard', 'soft', 'diagnostic')),
    source_asset_id INTEGER,
    source_anchor TEXT,
    authority_rank INTEGER NOT NULL DEFAULT 0,
    confidence REAL NOT NULL DEFAULT 1.0 CHECK (confidence >= 0 AND confidence <= 1),
    risk_if_removed TEXT,
    supersedes_clause_id INTEGER,
    created_at TEXT NOT NULL,
    UNIQUE (scene_contract_id, layer, clause_key),
    FOREIGN KEY (scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id) ON DELETE CASCADE,
    FOREIGN KEY (supersedes_clause_id) REFERENCES writing_scene_contract_clauses(clause_id)
);

-- H2: the database is the final activation guard. Application checks are not sufficient.
CREATE TRIGGER trg_scene_contract_active_requires_four_layers_insert
BEFORE INSERT ON writing_scene_contracts
WHEN NEW.status = 'active'
BEGIN
    SELECT RAISE(ABORT, 'active contract must be approved before activation');
END;
CREATE TRIGGER trg_scene_contract_active_requires_four_layers_update
BEFORE UPDATE OF status ON writing_scene_contracts
WHEN NEW.status = 'active' AND OLD.status <> 'active' AND (
    OLD.status <> 'approved'
    OR (SELECT COUNT(*) FROM writing_scene_contract_clauses
        WHERE scene_contract_id = NEW.scene_contract_id AND layer = 'hard_constraint') < 1
    OR (SELECT COUNT(*) FROM writing_scene_contract_clauses
        WHERE scene_contract_id = NEW.scene_contract_id AND layer = 'source_dna') < 1
    OR (SELECT COUNT(*) FROM writing_scene_contract_clauses
        WHERE scene_contract_id = NEW.scene_contract_id AND layer = 'soft_goal') < 1
    OR (SELECT COUNT(*) FROM writing_scene_contract_clauses
        WHERE scene_contract_id = NEW.scene_contract_id AND layer = 'creative_opening') < 2
)
BEGIN
    SELECT RAISE(ABORT, 'active contract requires approved status and complete four-layer clauses');
END;
CREATE TRIGGER trg_active_scene_contract_clauses_no_insert
BEFORE INSERT ON writing_scene_contract_clauses
WHEN (SELECT status FROM writing_scene_contracts
      WHERE scene_contract_id = NEW.scene_contract_id) IN ('active', 'superseded')
BEGIN SELECT RAISE(ABORT, 'active or superseded contract clauses are immutable'); END;
CREATE TRIGGER trg_active_scene_contract_clauses_no_update
BEFORE UPDATE ON writing_scene_contract_clauses
WHEN (SELECT status FROM writing_scene_contracts
      WHERE scene_contract_id = OLD.scene_contract_id) IN ('active', 'superseded')
BEGIN SELECT RAISE(ABORT, 'active or superseded contract clauses are immutable'); END;
CREATE TRIGGER trg_active_scene_contract_clauses_no_delete
BEFORE DELETE ON writing_scene_contract_clauses
WHEN (SELECT status FROM writing_scene_contracts
      WHERE scene_contract_id = OLD.scene_contract_id) IN ('active', 'superseded')
BEGIN SELECT RAISE(ABORT, 'active or superseded contract clauses are immutable'); END;

-- 56. Auditable repair tasks for AI-authored Scene revisions.
CREATE TABLE writing_scene_repair_tasks (
    repair_task_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    scene_id INTEGER NOT NULL,
    branch_version_id INTEGER NOT NULL,
    source_revision_id INTEGER,
    scene_contract_id INTEGER NOT NULL,
    issue TEXT NOT NULL CHECK (length(trim(issue)) > 0),
    status TEXT NOT NULL CHECK (status IN (
        'planned', 'running', 'completed', 'failed', 'cancelled'
    )),
    created_by TEXT NOT NULL,
    created_at TEXT NOT NULL,
    completed_at TEXT,
    FOREIGN KEY (scene_id) REFERENCES writing_scenes(scene_id) ON DELETE CASCADE,
    FOREIGN KEY (branch_version_id) REFERENCES writing_chapter_candidate_branch_versions(branch_version_id),
    FOREIGN KEY (source_revision_id) REFERENCES writing_scene_revisions(scene_revision_id),
    FOREIGN KEY (scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_scene_repair_tasks_scope
ON writing_scene_repair_tasks(project_id, chapter_id, scene_id, status);

-- Scene-first stale annotations preserve immutable prose/branch/snapshot rows.
CREATE TABLE writing_scene_revision_stale_marks (
    scene_revision_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER NOT NULL,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (scene_revision_id) REFERENCES writing_scene_revisions(scene_revision_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_scene_revision_stale_source
ON writing_scene_revision_stale_marks(source_scene_contract_id);

CREATE TABLE writing_branch_version_stale_marks (
    branch_version_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER NOT NULL,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (branch_version_id) REFERENCES writing_chapter_candidate_branch_versions(branch_version_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_branch_version_stale_source
ON writing_branch_version_stale_marks(source_scene_contract_id);

CREATE TABLE writing_chapter_snapshot_stale_marks (
    snapshot_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER NOT NULL,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (snapshot_id) REFERENCES writing_chapter_snapshots(snapshot_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_chapter_snapshot_stale_source
ON writing_chapter_snapshot_stale_marks(source_scene_contract_id);

-- 57. Immutable Scene prose revisions; deliberately no is_current flag.
CREATE TABLE writing_scene_revisions (
    scene_revision_id INTEGER PRIMARY KEY,
    scene_id INTEGER NOT NULL,
    parent_revision_id INTEGER,
    scene_contract_id INTEGER NOT NULL,
    generation_task_id INTEGER,
    repair_task_id INTEGER,
    context_snapshot_id INTEGER,
    text TEXT NOT NULL CHECK (length(text) > 0),
    text_hash TEXT NOT NULL,
    actor_type TEXT NOT NULL CHECK (actor_type IN ('ai', 'human', 'migration', 'system')),
    actor_id TEXT NOT NULL,
    change_reason TEXT NOT NULL,
    created_at TEXT NOT NULL,
    UNIQUE (scene_id, text_hash),
    FOREIGN KEY (scene_id) REFERENCES writing_scenes(scene_id) ON DELETE CASCADE,
    FOREIGN KEY (parent_revision_id) REFERENCES writing_scene_revisions(scene_revision_id),
    FOREIGN KEY (scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX idx_scene_revisions_scene ON writing_scene_revisions(scene_id, created_at);
CREATE TRIGGER trg_scene_revision_no_update
BEFORE UPDATE ON writing_scene_revisions
BEGIN SELECT RAISE(ABORT, 'scene revisions are immutable'); END;
CREATE TRIGGER trg_scene_revision_referenced_no_delete
BEFORE DELETE ON writing_scene_revisions
WHEN EXISTS (SELECT 1 FROM writing_branch_scenes WHERE scene_revision_id = OLD.scene_revision_id)
  OR EXISTS (SELECT 1 FROM writing_chapter_snapshot_scenes WHERE scene_revision_id = OLD.scene_revision_id)
BEGIN SELECT RAISE(ABORT, 'referenced scene revisions cannot be deleted'); END;

-- 57. Optional non-authoritative work slices inside one Scene Revision.
CREATE TABLE writing_scene_internal_shots (
    internal_shot_id INTEGER PRIMARY KEY,
    scene_revision_id INTEGER NOT NULL,
    shot_order INTEGER NOT NULL CHECK (shot_order >= 0),
    purpose TEXT NOT NULL,
    text_start INTEGER NOT NULL CHECK (text_start >= 0),
    text_end INTEGER NOT NULL CHECK (text_end >= text_start),
    created_at TEXT NOT NULL,
    UNIQUE (scene_revision_id, shot_order),
    FOREIGN KEY (scene_revision_id) REFERENCES writing_scene_revisions(scene_revision_id) ON DELETE CASCADE
);

-- 58. Bounded chapter candidate generation round.
CREATE TABLE writing_chapter_generation_rounds (
    generation_round_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    outline_version_id INTEGER,
    chapter_contract_version_id INTEGER,
    round_number INTEGER NOT NULL CHECK (round_number >= 1),
    status TEXT NOT NULL CHECK (status IN (
        'planned', 'generating_initial', 'validating_initial', 'supplementing',
        'validating_supplement', 'ready_for_selection', 'selecting', 'selected',
        'initial_zero_pass', 'candidate_shortage', 'diversity_shortage', 'failed', 'superseded'
    )),
    initial_target_count INTEGER NOT NULL DEFAULT 2 CHECK (initial_target_count >= 1),
    supplement_target_count INTEGER NOT NULL DEFAULT 3 CHECK (supplement_target_count >= 0),
    eligible_count INTEGER NOT NULL DEFAULT 0 CHECK (eligible_count >= 0),
    call_count INTEGER NOT NULL DEFAULT 0 CHECK (call_count >= 0),
    failure_reason TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE (project_id, chapter_id, round_number),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);

-- 59. A literary candidate is a complete chapter branch.
CREATE TABLE writing_chapter_candidate_branches (
    branch_id INTEGER PRIMARY KEY,
    generation_round_id INTEGER NOT NULL,
    candidate_index INTEGER NOT NULL CHECK (candidate_index >= 1),
    writer_model TEXT NOT NULL,
    generation_strategy TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN (
        'generating', 'validating', 'eligible', 'literary_review', 'selected', 'rejected'
    )),
    created_at TEXT NOT NULL,
    UNIQUE (generation_round_id, candidate_index),
    FOREIGN KEY (generation_round_id) REFERENCES writing_chapter_generation_rounds(generation_round_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX idx_generation_round_selected_branch
ON writing_chapter_candidate_branches(generation_round_id) WHERE status = 'selected';

-- 60. Immutable-on-freeze candidate Branch Versions.
CREATE TABLE writing_chapter_candidate_branch_versions (
    branch_version_id INTEGER PRIMARY KEY,
    branch_id INTEGER NOT NULL,
    version INTEGER NOT NULL CHECK (version >= 1),
    parent_branch_version_id INTEGER,
    outline_version_id INTEGER,
    chapter_contract_version_id INTEGER,
    world_snapshot_id INTEGER,
    fact_snapshot_id INTEGER,
    content_hash TEXT,
    status TEXT NOT NULL DEFAULT 'building' CHECK (status IN ('building', 'frozen')),
    created_at TEXT NOT NULL,
    frozen_at TEXT,
    UNIQUE (branch_id, version),
    FOREIGN KEY (branch_id) REFERENCES writing_chapter_candidate_branches(branch_id) ON DELETE CASCADE,
    FOREIGN KEY (parent_branch_version_id) REFERENCES writing_chapter_candidate_branch_versions(branch_version_id)
);
CREATE TRIGGER trg_frozen_branch_version_no_update
BEFORE UPDATE ON writing_chapter_candidate_branch_versions WHEN OLD.status = 'frozen'
BEGIN SELECT RAISE(ABORT, 'frozen branch versions are immutable'); END;
CREATE TRIGGER trg_frozen_branch_version_no_delete
BEFORE DELETE ON writing_chapter_candidate_branch_versions WHEN OLD.status = 'frozen'
BEGIN SELECT RAISE(ABORT, 'frozen branch versions cannot be deleted'); END;

-- 61. Branch-local Scene heads.
CREATE TABLE writing_branch_scenes (
    branch_version_id INTEGER NOT NULL,
    scene_order INTEGER NOT NULL CHECK (scene_order >= 0),
    scene_id INTEGER NOT NULL,
    scene_revision_id INTEGER NOT NULL,
    PRIMARY KEY (branch_version_id, scene_order),
    UNIQUE (branch_version_id, scene_id),
    FOREIGN KEY (branch_version_id) REFERENCES writing_chapter_candidate_branch_versions(branch_version_id) ON DELETE CASCADE,
    FOREIGN KEY (scene_id) REFERENCES writing_scenes(scene_id),
    FOREIGN KEY (scene_revision_id) REFERENCES writing_scene_revisions(scene_revision_id)
);
CREATE TRIGGER trg_branch_scene_revision_matches_scene_insert
BEFORE INSERT ON writing_branch_scenes
WHEN NOT EXISTS (SELECT 1 FROM writing_scene_revisions
                 WHERE scene_revision_id = NEW.scene_revision_id AND scene_id = NEW.scene_id)
BEGIN SELECT RAISE(ABORT, 'branch binding revision must belong to its Scene'); END;
CREATE TRIGGER trg_branch_scene_revision_matches_scene_update
BEFORE UPDATE OF scene_id, scene_revision_id ON writing_branch_scenes
WHEN NOT EXISTS (SELECT 1 FROM writing_scene_revisions
                 WHERE scene_revision_id = NEW.scene_revision_id AND scene_id = NEW.scene_id)
BEGIN SELECT RAISE(ABORT, 'branch binding revision must belong to its Scene'); END;
CREATE TRIGGER trg_frozen_branch_scene_no_insert
BEFORE INSERT ON writing_branch_scenes
WHEN (SELECT status FROM writing_chapter_candidate_branch_versions
      WHERE branch_version_id = NEW.branch_version_id) = 'frozen'
BEGIN SELECT RAISE(ABORT, 'frozen branch scene bindings are immutable'); END;
CREATE TRIGGER trg_frozen_branch_scene_no_update
BEFORE UPDATE ON writing_branch_scenes
WHEN (SELECT status FROM writing_chapter_candidate_branch_versions
      WHERE branch_version_id = OLD.branch_version_id) = 'frozen'
BEGIN SELECT RAISE(ABORT, 'frozen branch scene bindings are immutable'); END;
CREATE TRIGGER trg_frozen_branch_scene_no_delete
BEFORE DELETE ON writing_branch_scenes
WHEN (SELECT status FROM writing_chapter_candidate_branch_versions
      WHERE branch_version_id = OLD.branch_version_id) = 'frozen'
BEGIN SELECT RAISE(ABORT, 'frozen branch scene bindings are immutable'); END;

-- 62. Accepted Chapter Snapshot.
CREATE TABLE writing_chapter_snapshots (
    snapshot_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    source_branch_version_id INTEGER NOT NULL,
    chapter_contract_version_id INTEGER,
    world_snapshot_id INTEGER,
    fact_snapshot_id INTEGER,
    snapshot_hash TEXT NOT NULL,
    accepted_decision_id INTEGER,
    created_at TEXT NOT NULL,
    sealed_at TEXT,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (source_branch_version_id) REFERENCES writing_chapter_candidate_branch_versions(branch_version_id),
    FOREIGN KEY (accepted_decision_id) REFERENCES writing_human_decisions(decision_id)
);
CREATE TRIGGER trg_snapshot_seal_only_update
BEFORE UPDATE ON writing_chapter_snapshots
WHEN NOT (
    OLD.sealed_at IS NULL AND NEW.sealed_at IS NOT NULL
    AND OLD.snapshot_id = NEW.snapshot_id AND OLD.project_id = NEW.project_id
    AND OLD.chapter_id = NEW.chapter_id
    AND OLD.source_branch_version_id = NEW.source_branch_version_id
    AND OLD.chapter_contract_version_id IS NEW.chapter_contract_version_id
    AND OLD.world_snapshot_id IS NEW.world_snapshot_id
    AND OLD.fact_snapshot_id IS NEW.fact_snapshot_id
    AND OLD.snapshot_hash = NEW.snapshot_hash
    AND OLD.accepted_decision_id IS NEW.accepted_decision_id
    AND OLD.created_at = NEW.created_at
)
BEGIN SELECT RAISE(ABORT, 'chapter snapshots are immutable'); END;
CREATE TRIGGER trg_snapshot_no_delete
BEFORE DELETE ON writing_chapter_snapshots
BEGIN SELECT RAISE(ABORT, 'chapter snapshots cannot be deleted'); END;

-- 63. Immutable ordered copy of accepted Branch Scene bindings.
CREATE TABLE writing_chapter_snapshot_scenes (
    snapshot_id INTEGER NOT NULL,
    scene_order INTEGER NOT NULL CHECK (scene_order >= 0),
    scene_id INTEGER NOT NULL,
    scene_revision_id INTEGER NOT NULL,
    PRIMARY KEY (snapshot_id, scene_order),
    UNIQUE (snapshot_id, scene_id),
    FOREIGN KEY (snapshot_id) REFERENCES writing_chapter_snapshots(snapshot_id),
    FOREIGN KEY (scene_id) REFERENCES writing_scenes(scene_id),
    FOREIGN KEY (scene_revision_id) REFERENCES writing_scene_revisions(scene_revision_id)
);
CREATE TRIGGER trg_snapshot_scene_revision_matches_scene
BEFORE INSERT ON writing_chapter_snapshot_scenes
WHEN NOT EXISTS (SELECT 1 FROM writing_scene_revisions
                 WHERE scene_revision_id = NEW.scene_revision_id AND scene_id = NEW.scene_id)
BEGIN SELECT RAISE(ABORT, 'snapshot binding revision must belong to its Scene'); END;
CREATE TRIGGER trg_sealed_snapshot_scene_no_insert
BEFORE INSERT ON writing_chapter_snapshot_scenes
WHEN (SELECT sealed_at FROM writing_chapter_snapshots WHERE snapshot_id = NEW.snapshot_id) IS NOT NULL
BEGIN SELECT RAISE(ABORT, 'sealed snapshot scene bindings are immutable'); END;
CREATE TRIGGER trg_snapshot_scene_no_update
BEFORE UPDATE ON writing_chapter_snapshot_scenes
BEGIN SELECT RAISE(ABORT, 'snapshot scene bindings are immutable'); END;
CREATE TRIGGER trg_snapshot_scene_no_delete
BEFORE DELETE ON writing_chapter_snapshot_scenes
BEGIN SELECT RAISE(ABORT, 'snapshot scene bindings are immutable'); END;

-- 64. One optimistic-lock Head per chapter.
CREATE TABLE writing_chapter_heads (
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    active_snapshot_id INTEGER NOT NULL,
    version INTEGER NOT NULL CHECK (version >= 1),
    updated_at TEXT NOT NULL,
    PRIMARY KEY (project_id, chapter_id),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (active_snapshot_id) REFERENCES writing_chapter_snapshots(snapshot_id)
);
CREATE TRIGGER trg_chapter_head_requires_matching_sealed_snapshot_insert
BEFORE INSERT ON writing_chapter_heads
WHEN NOT EXISTS (SELECT 1 FROM writing_chapter_snapshots
                 WHERE snapshot_id = NEW.active_snapshot_id
                   AND project_id = NEW.project_id AND chapter_id = NEW.chapter_id
                   AND sealed_at IS NOT NULL)
BEGIN SELECT RAISE(ABORT, 'chapter head requires a matching sealed snapshot'); END;
CREATE TRIGGER trg_chapter_head_requires_matching_sealed_snapshot_update
BEFORE UPDATE OF project_id, chapter_id, active_snapshot_id ON writing_chapter_heads
WHEN NOT EXISTS (SELECT 1 FROM writing_chapter_snapshots
                 WHERE snapshot_id = NEW.active_snapshot_id
                   AND project_id = NEW.project_id AND chapter_id = NEW.chapter_id
                   AND sealed_at IS NOT NULL)
BEGIN SELECT RAISE(ABORT, 'chapter head requires a matching sealed snapshot'); END;

-- P0-3: Scene Contract dual-master review + amendment.
-- Idempotent. Stores reviewer independence evidence for blind audit.

CREATE TABLE IF NOT EXISTS writing_scene_contract_reviews (
    contract_review_id INTEGER PRIMARY KEY,
    scene_contract_id INTEGER NOT NULL,
    reviewer_model TEXT NOT NULL,
    reviewer_family TEXT NOT NULL,
    prompt_hash TEXT NOT NULL,
    blind_context_hash TEXT NOT NULL,
    visible_prior_reviews INTEGER NOT NULL DEFAULT 0 CHECK (visible_prior_reviews IN (0,1)),
    review_order INTEGER NOT NULL,
    verdict TEXT NOT NULL CHECK (verdict IN ('approve','revise','reject')),
    evidence_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (scene_contract_id)
        REFERENCES writing_scene_contracts(scene_contract_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_scene_contract_reviews_contract
    ON writing_scene_contract_reviews(scene_contract_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_scene_contract_review_unique_order
    ON writing_scene_contract_reviews(scene_contract_id, review_order);

-- H2: approved status alone is not review evidence. Activation requires three
-- blind approve rows from distinct model families (implementation-contract §4).
CREATE TRIGGER trg_scene_contract_active_requires_reviews
BEFORE UPDATE OF status ON writing_scene_contracts
WHEN NEW.status = 'active' AND OLD.status <> 'active' AND (
    (SELECT count(*) FROM writing_scene_contract_reviews
     WHERE scene_contract_id = NEW.scene_contract_id
       AND review_order IN (1, 2, 3) AND verdict = 'approve'
       AND visible_prior_reviews = 0) <> 3
    OR (SELECT count(DISTINCT reviewer_family) FROM writing_scene_contract_reviews
        WHERE scene_contract_id = NEW.scene_contract_id
          AND review_order IN (1, 2, 3) AND verdict = 'approve'
          AND visible_prior_reviews = 0) <> 3
)
BEGIN SELECT RAISE(ABORT, 'active contract requires three blind approve reviews from distinct families'); END;

CREATE TABLE IF NOT EXISTS writing_scene_contract_amendments (
    amendment_id INTEGER PRIMARY KEY,
    scene_contract_id INTEGER NOT NULL,
    amending_actor TEXT NOT NULL,
    amendment_reason TEXT NOT NULL,
    clause_changes_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (scene_contract_id)
        REFERENCES writing_scene_contracts(scene_contract_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_scene_contract_amendments
    ON writing_scene_contract_amendments(scene_contract_id, created_at);

-- P0-5: Guidance cards + Fact proposals (real iFLYTEK, one-step).
-- Idempotent.

CREATE TABLE IF NOT EXISTS writing_guidance_cards (
    guidance_card_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    scene_id INTEGER,
    card_type TEXT NOT NULL CHECK (card_type IN (
        'continuity_warning','character_pressure','foreshadow_reminder',
        'pacing_adjustment','fact_contradiction'
    )),
    trigger_context TEXT NOT NULL,
    guidance_text TEXT NOT NULL,
    model_name TEXT NOT NULL,
    prompt_hash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','dismissed','applied','stale')),
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_guidance_cards_chapter
    ON writing_guidance_cards(project_id, chapter_id, status);

CREATE TABLE IF NOT EXISTS writing_fact_proposals (
    fact_proposal_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    scene_id INTEGER,
    proposed_fact TEXT NOT NULL,
    fact_type TEXT NOT NULL CHECK (fact_type IN (
        'character_state','world_rule','event','causality','timeline'
    )),
    source_text TEXT NOT NULL,
    source_revision_id INTEGER,
    confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    status TEXT NOT NULL DEFAULT 'proposed'
        CHECK (status IN ('proposed','confirmed','rejected','superseded','stale')),
    model_name TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (source_revision_id)
        REFERENCES writing_scene_revisions(scene_revision_id)
);
CREATE INDEX IF NOT EXISTS idx_fact_proposals_status
    ON writing_fact_proposals(project_id, status);

-- P0-4: Pareto frontier + minority champion for literary selection.
-- Idempotent.

CREATE TABLE IF NOT EXISTS writing_pareto_frontier (
    pareto_entry_id INTEGER PRIMARY KEY,
    generation_round_id INTEGER NOT NULL,
    branch_id INTEGER NOT NULL,
    dimension_scores_json TEXT NOT NULL,
    is_dominated INTEGER NOT NULL DEFAULT 0 CHECK (is_dominated IN (0,1)),
    created_at TEXT NOT NULL,
    FOREIGN KEY (generation_round_id)
        REFERENCES writing_chapter_generation_rounds(generation_round_id) ON DELETE CASCADE,
    FOREIGN KEY (branch_id)
        REFERENCES writing_chapter_candidate_branches(branch_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_pareto_frontier_round
    ON writing_pareto_frontier(generation_round_id, is_dominated);

CREATE TABLE IF NOT EXISTS writing_minority_champions (
    champion_id INTEGER PRIMARY KEY,
    generation_round_id INTEGER NOT NULL,
    branch_id INTEGER NOT NULL,
    champion_model TEXT NOT NULL,
    champion_dimension TEXT NOT NULL,
    score INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (generation_round_id)
        REFERENCES writing_chapter_generation_rounds(generation_round_id) ON DELETE CASCADE,
    FOREIGN KEY (branch_id)
        REFERENCES writing_chapter_candidate_branches(branch_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_minority_champions_round
    ON writing_minority_champions(generation_round_id);

-- P0-2: Selection decisions + Accept guard.
-- Idempotent (IF NOT EXISTS). Mirrors the append in schema.sql.

CREATE TABLE IF NOT EXISTS writing_selection_decisions (
    selection_decision_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    generation_round_id INTEGER NOT NULL,
    selected_branch_id INTEGER NOT NULL,
    decision_type TEXT NOT NULL CHECK (decision_type IN (
        'auto_selected','human_override','minority_champion'
    )),
    evidence_json TEXT NOT NULL,
    actor TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (generation_round_id)
        REFERENCES writing_chapter_generation_rounds(generation_round_id) ON DELETE CASCADE,
    FOREIGN KEY (selected_branch_id)
        REFERENCES writing_chapter_candidate_branches(branch_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_selection_decisions_round
    ON writing_selection_decisions(generation_round_id);
