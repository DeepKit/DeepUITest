-- BFX-092 模型池配置 — pool-A 初始配置(数据迁移,幂等)。
--
-- 背景:legacy 项目 writing_projects.writer_model_pool 与 jury_model_pool 内容相同
-- (3 个模型仅顺序不同),且 jury 池 < 生产下限 5,导致 doctor model_pool_separation fail。
-- doctor `_check_model_pool_separation` 要求:writer/jury 不重叠 + jury >= max(jury_min,5)。
-- 见 ink/docs/iflytek-model-config.md §3.1 池配置方案表(pool-A)。
--
-- 本迁移写入 pool-A(writer 3 + jury 5,零重叠),并同步 role_configs 使实际调用模型落入对应池。
-- 网关 WiseGateway 127.0.0.1:8000 实测 8 模型全部可用(2026-07-17)。
-- 2026-07-17 实测 doctor 全绿 ready_for_personal_production=true。
--
-- 幂等:用 ON CONFLICT/UPDATE 覆盖,重复执行结果不变。pool-B/C 切换时新增迁移文件,
-- 不改本文件,保留历史对照。

UPDATE writing_projects
SET writer_model_pool = '["claude-xunfei-deepseek-v4-pro","claude-xunfei-glm-5-2-1m","claude-xunfei-kimi-k2-6"]',
    jury_model_pool   = '["claude-xunfei-glm-5-1","claude-xunfei-qwen3-5-397b-a17b","claude-xunfei-minimax-m2-5","claude-xunfei-spark-x2","claude-xunfei-deepseek-v3-2"]'
WHERE project_id = 1;

-- role_configs 实际调用模型对齐到对应池(jury 类角色从 jury_pool 分配,与 writer 零重叠)
UPDATE writing_model_role_configs
SET model_name = 'claude-xunfei-glm-5-1'
WHERE project_id = 1 AND call_type = 'jury' AND tier = 'primary';
UPDATE writing_model_role_configs
SET model_name = 'claude-xunfei-qwen3-5-397b-a17b'
WHERE project_id = 1 AND call_type = 'chapter_review' AND tier = 'primary';
UPDATE writing_model_role_configs
SET model_name = 'claude-xunfei-minimax-m2-5'
WHERE project_id = 1 AND call_type = 'book_check' AND tier = 'primary';
-- draft 保留 deepseek-v4-pro(本就在 writer_pool,无需改)
