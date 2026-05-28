-- PostgreSQL Schema for goodmem.cn
-- 核心防盗底层结构

CREATE TABLE IF NOT EXISTS users (
    token VARCHAR(64) PRIMARY KEY,               -- 32位安全随机字符串
    granted_novels JSONB DEFAULT '["mindbreak"]', -- 授权访问的小说ID列表 (JSON 数组)
    payment_status VARCHAR(20) DEFAULT 'Paid',   -- 'Paid', 'Refunded'
    out_trade_no VARCHAR(128),                   -- 支付订单�?    cashback_status VARCHAR(32) DEFAULT 'NONE',  -- 返现状�?    status VARCHAR(20) DEFAULT 'Active',         -- 'Active', 'Warned', 'Banned'
    ban_reason VARCHAR(100),                     -- 封禁原因，如：Frequency_Melt
    last_active_ip VARCHAR(45),                  -- 最近一次心跳或登录的IP
    last_active_uuid VARCHAR(128),               -- 前端计算的组合指�?    last_heartbeat_at TIMESTAMP WITH TIME ZONE,  -- 最后心跳时�?    kick_count_10m INTEGER DEFAULT 0,            -- 10分钟内的被互踢次�?    kick_reset_at TIMESTAMP WITH TIME ZONE,      -- 互踢计数器重置时�?    -- V1 新增：诊断相关字�?    diagnosis_mode VARCHAR(10),                  -- 'rfi12' �?'quick9'
    rfi_type VARCHAR(10),                        -- 主结构类�?(water/wood/fire/earth/metal)
    secondary_rfi_type VARCHAR(10),              -- 次结构类型（MIXED 时）
    last_diagnosis_payload JSONB,                -- 完整诊断结果 JSON
    last_diagnosis_at TIMESTAMP WITH TIME ZONE,  -- 最后诊断时�?    -- V2 新增�?08篇算法推�?    pack_type VARCHAR(20) DEFAULT 'universal',   -- 'universal' 通用�?personalized' 专属
    pack_article_ids JSONB,                      -- 该用户专�?通用�?108 篇文�?ID 列表
    product_tier VARCHAR(20) DEFAULT 'system'    -- emergency/system/archive
);

CREATE TABLE IF NOT EXISTS articles (
    id SERIAL PRIMARY KEY,
    novel_key VARCHAR(50) NOT NULL,              -- 强隔离字段，挂载书名ID
    title VARCHAR(255) NOT NULL,
    content_html TEXT NOT NULL,
    is_free BOOLEAN DEFAULT FALSE,
    rfi_type VARCHAR(10),                        -- 五局分类 (water/wood/fire/earth/metal)
    legacy_id VARCHAR(10),                       -- 旧千位或 S/N 编号
    external_code VARCHAR(10),                   -- 新对外编号，例如 S0110
    subtitle VARCHAR(255),                       -- 副标�?    cluster_id VARCHAR(4),                       -- 两位母题簇号，例�?01
    drug_type VARCHAR(20),                       -- 药性，例如 '破雾�?
    drug_layer VARCHAR(50),                      -- 药性所属层
    judgment_tag VARCHAR(50),                    -- 一句话判断标签
    keywords VARCHAR(255),                       -- 搜索关键字列表，逗号分隔
    status VARCHAR(20) DEFAULT 'ready',          -- draft/review/ready
    sort_weight INTEGER DEFAULT 0,
    position_type SMALLINT DEFAULT 1,            -- 药位类型 0-9
    variant SMALLINT DEFAULT 0,                  -- 变体�?0-9
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(novel_key, title)
);

-- 建索引提升按书拉取目录树的速度
CREATE INDEX IF NOT EXISTS idx_articles_novel_key ON articles(novel_key);

-- 阅读历史追踪表（防白嫖与退单举证）
CREATE TABLE IF NOT EXISTS read_hiDeepStory (
    id SERIAL PRIMARY KEY,
    token VARCHAR(64) REFERENCES users(token) ON DELETE CASCADE,
    article_id INTEGER REFERENCES articles(id) ON DELETE CASCADE,
    first_read_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(token, article_id)
);

CREATE TABLE IF NOT EXISTS wechat_pay_events (
    transaction_id VARCHAR(128) PRIMARY KEY,
    notification_id VARCHAR(128) UNIQUE,
    out_trade_no VARCHAR(128),
    event_type VARCHAR(64) NOT NULL,
    token VARCHAR(64) REFERENCES users(token) ON DELETE SET NULL,
    payload JSONB NOT NULL,
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 插入一条给总设计师自己通电联调的权限卡
INSERT INTO users (token, granted_novels, payment_status, out_trade_no, cashback_status)
VALUES (
    'a29806588', 
    '["mindbreak"]',
    'Paid',
    'TEST_WX_TRADE_NO_123456',
    'NONE'
) ON CONFLICT (token) DO NOTHING;

-- 初始化一条测试文章数�?INSERT INTO articles (novel_key, title, content_html, is_free)
VALUES (
    'mindbreak',
    '�?01式：系统隔离法则',
    '<p>不要试图去拯救一个设计畸形的系统。你的第一步应该是拉起物理隔离线，确保系统的泥石流不会倒灌进你的责任域�?/p><p>本篇将教你如何在接口处设置熔断器�?/p>',
    FALSE
) ON CONFLICT DO NOTHING;
