-- =======================================================
-- 思维越狱 RFI-5 V2 体系迁移脚本
-- 用于支撑 508 篇前缀千位编号体系与精细化药性匹�?-- 执行前提：先执行�?migrate_v1.sql
-- =======================================================

-- 1. articles 表：增加千位体系相关的全部字�?ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS legacy_id VARCHAR(10),        -- 旧千位或 S/N 编号
  ADD COLUMN IF NOT EXISTS external_code VARCHAR(10),    -- 新对外编号，例如 S0110
  ADD COLUMN IF NOT EXISTS subtitle VARCHAR(255),        -- 副标�?  ADD COLUMN IF NOT EXISTS cluster_id VARCHAR(4),        -- 两位母题簇号，例�?01
  ADD COLUMN IF NOT EXISTS drug_type VARCHAR(20),        -- 药性，例如 '破雾�?
  ADD COLUMN IF NOT EXISTS drug_layer VARCHAR(50),       -- 药性所属层
  ADD COLUMN IF NOT EXISTS judgment_tag VARCHAR(50),     -- 一句话判断标签
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'ready', -- draft/review/ready
  ADD COLUMN IF NOT EXISTS sort_weight INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS position_type SMALLINT DEFAULT 1,-- 药位类型 0-9
  ADD COLUMN IF NOT EXISTS variant SMALLINT DEFAULT 0;   -- 变体�?0-9

-- 为新 external_code 创建唯一索引，以备后�?CREATE UNIQUE INDEX IF NOT EXISTS idx_articles_external_code ON articles(external_code);

-- 2. users 表：增加 108 篇计算包状�?ALTER TABLE users
  ADD COLUMN IF NOT EXISTS pack_type VARCHAR(20) DEFAULT 'universal', -- 'universal' 通用�?personalized' 专属
  ADD COLUMN IF NOT EXISTS pack_article_ids JSONB; -- 该用户专�?通用�?108 篇文�?ID 列表

-- V2 体系补充说明�?-- 之前 rfi_type 已加�?users �?articles，因此这里不重复添加�?