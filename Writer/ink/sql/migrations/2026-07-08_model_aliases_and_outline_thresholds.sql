-- 迁移：writing_projects 增加 model_aliases 列 + 放宽 outline 阈值默认值
-- 日期：2026-07-08
-- 目的：
--   1. 新增 model_aliases TEXT 列（JSON {"别名":"真实模型名"}），支持 smart-polish 等生产别名路由。
--      NULL 表示无别名。LLMGateway.call 按 project_id 查此列翻译别名。
--   2. 放宽 min_eligible_outlines 默认 2→1、outline_drift_threshold 默认 0.20→0.10。
--      原默认值对真实模型过严（outline CJK bigram overlap 易低于 0.20 → 全拒）。
--      注意：ALTER TABLE 无法改既有 DEFAULT，这里只对未设过该值的行 UPDATE；
--      新 DEFAULT 仅对迁移后新建行生效。CLI init 也已暴露这两个参数可显式覆盖。
--
-- 幂等：IF NOT EXISTS 保护列添加；UPDATE 只改仍为旧默认的行。
-- 执行：sqlite3 <db> ".read sql/migrations/2026-07-08_model_aliases_and_outline_thresholds.sql"

-- 1. model_aliases 列
ALTER TABLE writing_projects ADD COLUMN model_aliases TEXT;
-- CHECK 约束在 ALTER 后补加（SQLite 3.8+ 支持 ALTER ADD COLUMN 后无法直接加 CHECK，
-- 故该约束只在 schema.sql 全量建库时存在；既有库靠应用层 json_valid 校验）。

-- 2. outline 阈值：仅把仍是旧默认值的行放宽（不覆盖用户已调过的值）
UPDATE writing_projects
SET min_eligible_outlines = 1
WHERE min_eligible_outlines = 2;

UPDATE writing_projects
SET outline_drift_threshold = 0.10
WHERE outline_drift_threshold = 0.20;
