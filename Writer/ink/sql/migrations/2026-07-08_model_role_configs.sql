-- 迁移：新建 writing_model_role_configs 表（按 call_type 的模型角色主/备/兜底配置）
-- 日期：2026-07-08
-- 目的：
--   把「模型角色配置」从 writing_projects 的两个扁平 JSON 列表（writer_model_pool/jury_model_pool）
--   升级为「按 call_type × tier 的结构化主备兜底」，每 call_type 三行，尽量跨供应商。
--   LLMGateway.call 按 (project_id, call_type) 取主/备/兜底，失败逐 tier 切，三都失败才判该次调用失败。
--   api_key 只存环境变量名（api_key_env），不落明文 key。
-- 幂等：CREATE TABLE IF NOT EXISTS + CREATE INDEX IF NOT EXISTS。
-- 执行：sqlite3 <db> ".read sql/migrations/2026-07-08_model_role_configs.sql"
-- 注意：本迁移只建表，不回填数据。旧 writer_model_pool/jury_model_pool 列保留向后兼容；
--   CLI init 在无 role_configs 时用旧池自动生成 draft/jury 的 primary 单档（见 cli.py）。

CREATE TABLE IF NOT EXISTS writing_model_role_configs (
    role_config_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    call_type TEXT NOT NULL,
    tier TEXT NOT NULL CHECK (tier IN ('primary','secondary','tertiary')),
    model_name TEXT NOT NULL,
    provider TEXT NOT NULL,
    base_url TEXT,
    api_key_env TEXT NOT NULL,
    max_tokens INTEGER,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE (project_id, call_type, tier),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_role_configs_project_call ON writing_model_role_configs(project_id, call_type, tier);
