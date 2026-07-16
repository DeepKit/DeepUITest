-- 迁移：放宽质量门底线 shot_quality_floor 80→75、dimension_floor 65→60
-- 日期：2026-07-09
-- 目的：
--   真实讯飞多模型套餐（GLM-5.1 / DeepSeek V4 Pro / Kimi K2.6 / Qwen3.5-397B）跑 6 章
--   实稿，jury 稳定打 77-83 分。原 DB 硬底线 shot_quality_floor>=80（schema CHECK）
--   导致 77-79 分的优秀稿 passed=False、不进 winner 选择集、整章 fail、稿被永久丢弃
--   （如第 2 章 draft5=79.83）。放宽到 75 让真实稿直接过门，成稿链路贯通。
--
-- 注意（SQLite CHECK 限制）：
--   SQLite 无法用 ALTER 修改既有表的 CHECK 约束。既有库的 CHECK(shot_quality_floor>=80)
--   仍锁死在 80。本迁移只能改「数据值」；若既有库 CHECK 仍是 80，下面的 UPDATE 会被拒。
--   既有库要彻底放宽，须重建 writing_projects 表（drop + 从新 schema.sql 重建 + 回灌数据），
--   或直接新建库（CLI init 时 _open_cli_db 走 initialize_schema 读新 schema.sql，CHECK 天然=75）。
--   测试链路（make_schema_db）每次重建，已自动生效。
--   新建生产库：sqlite3 prod.sqlite + ink --db prod.sqlite init ...（自动用新 schema）
--
-- 幂等：UPDATE 只把仍为旧默认值的行放宽（不覆盖用户已调过的值）。
-- 执行：sqlite3 <db> ".read sql/migrations/2026-07-09_relax_quality_floor.sql"

UPDATE writing_projects
SET shot_quality_floor = 75
WHERE shot_quality_floor = 80;

UPDATE writing_projects
SET dimension_floor = 60
WHERE dimension_floor = 65;
