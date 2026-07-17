-- 黄金生产闭环 ② — 迁移版本跟踪表。
-- 记录每个迁移文件的应用状态,使老库升级有可重放/可查的版本链。
-- 本表本身由 apply_migrations 在首次调用时自动建(IF NOT EXISTS),
-- 不依赖任何迁移注册——它是迁移机制的基座,自举创建。

CREATE TABLE IF NOT EXISTS schema_migrations (
    migration_name TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL,
    checksum TEXT NOT NULL
);
