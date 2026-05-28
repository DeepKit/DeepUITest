-- V3 Migration: diagnosis cloud sync + WeChat webhook idempotency table
-- 使用方式: psql -d goodmem -f migrate_v3_payments.sql

ALTER TABLE users ADD COLUMN IF NOT EXISTS diagnosis_mode VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS rfi_type VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS secondary_rfi_type VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_diagnosis_payload JSONB;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_diagnosis_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS pack_type VARCHAR(20) DEFAULT 'universal';
ALTER TABLE users ADD COLUMN IF NOT EXISTS pack_article_ids JSONB;

CREATE TABLE IF NOT EXISTS wechat_pay_events (
    transaction_id VARCHAR(128) PRIMARY KEY,
    notification_id VARCHAR(128) UNIQUE,
    out_trade_no VARCHAR(128),
    event_type VARCHAR(64) NOT NULL,
    token VARCHAR(64) REFERENCES users(token) ON DELETE SET NULL,
    payload JSONB NOT NULL,
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
    RAISE NOTICE 'V3 迁移完成：诊断云端同步字段与微信支付 webhook 幂等表已就绪';
END $$;
