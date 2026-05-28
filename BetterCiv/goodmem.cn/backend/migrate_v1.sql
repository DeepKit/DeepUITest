-- V1 Migration: cop_type �?rfi_type + 新增诊断字段
-- 本文件用于已有数据库从旧版到 V1 的迁�?-- 使用方式: psql -d goodmem -f migrate_v1.sql

-- 1. articles 表：cop_type �?rfi_type
ALTER TABLE articles RENAME COLUMN cop_type TO rfi_type;

-- 2. users 表：新增诊断相关字段
ALTER TABLE users ADD COLUMN IF NOT EXISTS diagnosis_mode VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS rfi_type VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS secondary_rfi_type VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_diagnosis_payload JSONB;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_diagnosis_at TIMESTAMP WITH TIME ZONE;

-- 完成提示
DO $$
BEGIN
    RAISE NOTICE 'V1 迁移完成：cop_type �?rfi_type + 诊断字段已就�?;
END $$;
