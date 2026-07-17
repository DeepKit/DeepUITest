-- 黄金生产闭环 ② — stale_marks 三表迁移(从 schema.sql 抽出,幂等)。
-- 老库(2026-07-16 stale_marks 表加入之前初始化的库)缺这三张表;本迁移补齐,
-- 使老库与 base schema 一致。新库经 initialize_schema 已含此三表,
-- apply_migrations 标记为已应用(详见 ink/schema.py migrate_db)。
--
-- 三张表镜像 schema.sql:1299-1336 的定义,加 IF NOT EXISTS 以幂等。

CREATE TABLE IF NOT EXISTS writing_scene_revision_stale_marks (
    scene_revision_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (scene_revision_id) REFERENCES writing_scene_revisions(scene_revision_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX IF NOT EXISTS idx_scene_revision_stale_source
ON writing_scene_revision_stale_marks(source_scene_contract_id);

CREATE TABLE IF NOT EXISTS writing_branch_version_stale_marks (
    branch_version_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (branch_version_id) REFERENCES writing_chapter_candidate_branch_versions(branch_version_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX IF NOT EXISTS idx_branch_version_stale_source
ON writing_branch_version_stale_marks(source_scene_contract_id);

CREATE TABLE IF NOT EXISTS writing_chapter_snapshot_stale_marks (
    snapshot_id INTEGER PRIMARY KEY,
    source_scene_contract_id INTEGER NOT NULL,
    replacement_scene_contract_id INTEGER,
    stale_reason TEXT NOT NULL CHECK (length(trim(stale_reason)) > 0),
    marked_at TEXT NOT NULL,
    FOREIGN KEY (snapshot_id) REFERENCES writing_chapter_snapshots(snapshot_id) ON DELETE CASCADE,
    FOREIGN KEY (source_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id),
    FOREIGN KEY (replacement_scene_contract_id) REFERENCES writing_scene_contracts(scene_contract_id)
);
CREATE INDEX IF NOT EXISTS idx_chapter_snapshot_stale_source
ON writing_chapter_snapshot_stale_marks(source_scene_contract_id);
