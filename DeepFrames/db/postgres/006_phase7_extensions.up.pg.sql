-- Phase 7: Extension capabilities (BGM library, content type adapters,
-- readiness reports, additional platform specs)
-- Reference: docs/10.dev-roadmap-development-roadmap.md (Phase 7)

-- ============================================================
-- BGM Library
-- ============================================================
-- Music tracks for audio/video production. Default BGM is disabled
-- (ENGINEERING_HANDOFF.md: "BGM 默认不加"), but the library and
-- association mechanism is ready for Phase 7 activation.

CREATE TABLE IF NOT EXISTS deepframes_bgm_library (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  library_id UUID NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  status VARCHAR(24) NOT NULL DEFAULT 'active',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS deepframes_bgm_track (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  track_id UUID NOT NULL UNIQUE,
  library_id UUID NOT NULL REFERENCES deepframes_bgm_library(library_id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL,
  artist VARCHAR(100) NOT NULL DEFAULT '',
  genre VARCHAR(32) NOT NULL DEFAULT '',
  mood_tags_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  asset_id UUID NULL REFERENCES deepframes_asset(asset_id) ON DELETE SET NULL,
  duration_sec DECIMAL(10,3) NULL,
  bpm SMALLINT NULL,
  key_signature VARCHAR(8) NULL,
  license_type VARCHAR(32) NOT NULL DEFAULT 'royalty_free',
  license_uri TEXT NOT NULL DEFAULT '',
  fade_in_sec DECIMAL(5,2) NOT NULL DEFAULT 1.0,
  fade_out_sec DECIMAL(5,2) NOT NULL DEFAULT 2.0,
  loop_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  status VARCHAR(24) NOT NULL DEFAULT 'active',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_bgm_track_status CHECK (status IN ('active','disabled','deleted'))
);

CREATE INDEX IF NOT EXISTS idx_bgm_track_library ON deepframes_bgm_track(library_id);
CREATE INDEX IF NOT EXISTS idx_bgm_track_genre ON deepframes_bgm_track(genre);

-- BGM association per audio manifest (for when BGM is enabled)
CREATE TABLE IF NOT EXISTS deepframes_bgm_association (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  association_id UUID NOT NULL UNIQUE,
  audio_manifest_id UUID NOT NULL REFERENCES deepframes_audio_manifest(manifest_id) ON DELETE CASCADE,
  track_id UUID NOT NULL REFERENCES deepframes_bgm_track(track_id) ON DELETE CASCADE,
  mix_volume DECIMAL(4,2) NOT NULL DEFAULT 0.30,
  start_offset_sec DECIMAL(10,3) NOT NULL DEFAULT 0.0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_bgm_assoc_manifest ON deepframes_bgm_association(audio_manifest_id);

-- Insert default (empty) BGM library
INSERT INTO deepframes_bgm_library (library_id, name, description, is_default, schema_version, status)
VALUES (gen_random_uuid(), 'Default Library', 'Default BGM library for DeepFrames', TRUE, '1.0.0', 'active');

-- ============================================================
-- Content Type Adapter Registry
-- ============================================================
-- Each adapter handles a specific content_type (e.g. longform_zh_article,
-- short_video_script, podcast_transcript). Phase 7 requires that new
-- adapters provide a readiness report before activation.

CREATE TABLE IF NOT EXISTS deepframes_content_type_adapter (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  adapter_id UUID NOT NULL UNIQUE,
  content_type VARCHAR(64) NOT NULL UNIQUE,
  display_name VARCHAR(100) NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  adapter_class VARCHAR(200) NOT NULL DEFAULT '',
  supported_output_types_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  default_pipeline_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  config_schema_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  version_no INT NOT NULL DEFAULT 1,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_adapter_status CHECK (status IN ('pending','active','disabled','deprecated'))
);

CREATE INDEX IF NOT EXISTS idx_adapter_content_type ON deepframes_content_type_adapter(content_type);

-- Insert default article adapter (active, since Phase 1-6 use it)
INSERT INTO deepframes_content_type_adapter
  (adapter_id, content_type, display_name, description, adapter_class,
   supported_output_types_json, default_pipeline_json, schema_version, version_no, status)
VALUES (
  gen_random_uuid(), 'longform_zh_article', 'Long-form Chinese Article',
  'Default adapter for long-form Chinese articles → audio/video candidate packages',
  'TArticleContentTypeAdapter',
  '["audio", "video"]'::jsonb,
  '{"document_chain": true, "agent_chain": true, "audio_chain": true, "video_chain": true, "package_chain": true}'::jsonb,
  '1.0.0', 1, 'active'
);

-- ============================================================
-- Readiness Report
-- ============================================================
-- New adapters must pass readiness validation before activation.
-- Reports are versioned and auditable.

CREATE TABLE IF NOT EXISTS deepframes_readiness_report (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NOT NULL UNIQUE,
  adapter_id UUID NOT NULL REFERENCES deepframes_content_type_adapter(adapter_id) ON DELETE CASCADE,
  check_type VARCHAR(32) NOT NULL,
  check_result VARCHAR(16) NOT NULL,
  score DECIMAL(4,2) NULL,
  summary TEXT NOT NULL DEFAULT '',
  issues_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  evidence_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  version_no INT NOT NULL DEFAULT 1,
  status VARCHAR(24) NOT NULL DEFAULT 'done',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_readiness_result CHECK (check_result IN ('pass','warn','fail','not_checked')),
  CONSTRAINT ck_readiness_status CHECK (status IN ('pending','done','failed'))
);

CREATE INDEX IF NOT EXISTS idx_readiness_adapter ON deepframes_readiness_report(adapter_id);
CREATE INDEX IF NOT EXISTS idx_readiness_check_type ON deepframes_readiness_report(check_type);

-- Insert readiness report for default article adapter (all pass)
INSERT INTO deepframes_readiness_report
  (report_id, adapter_id, check_type, check_result, score, summary, schema_version, status)
SELECT
  gen_random_uuid(),
  adapter_id,
  'e2e_sample',
  'pass',
  1.0,
  'Default article adapter validated through Phases 1-6',
  '1.0.0',
  'done'
FROM deepframes_content_type_adapter
WHERE content_type = 'longform_zh_article';

-- ============================================================
-- Additional Platform Spec Seed Data
-- ============================================================
-- Phase 7 adds multi-platform support beyond bilibili.
-- Reference: docs/07.platform-多平台适配-multi-platform.md

-- Douyin (9:16 vertical video)
INSERT INTO deepframes_platform_spec
  (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
   bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'douyin', 'video', '9:16', 1080, 1920, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 3000, "audio_bitrate_kbps": 128, "max_bitrate_kbps": 5000}'::jsonb,
  '{"require_ai_label": true, "label_position": "top_right"}'::jsonb,
  '{"top_pct": 3, "bottom_pct": 15, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 32, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 12}'::jsonb
);

-- Kuaishou (9:16 vertical video)
INSERT INTO deepframes_platform_spec
  (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
   bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'kuaishou', 'video', '9:16', 1080, 1920, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 2500, "audio_bitrate_kbps": 128, "max_bitrate_kbps": 4000}'::jsonb,
  '{"require_ai_label": true, "label_position": "top_right"}'::jsonb,
  '{"top_pct": 3, "bottom_pct": 15, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 32, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 12}'::jsonb
);

-- Xiaohongshu 3:4
INSERT INTO deepframes_platform_spec
  (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
   bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'xiaohongshu', 'video', '3:4', 1080, 1440, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 3000, "audio_bitrate_kbps": 128, "max_bitrate_kbps": 5000}'::jsonb,
  '{"require_ai_label": false}'::jsonb,
  '{"top_pct": 3, "bottom_pct": 12, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 30, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 10}'::jsonb
);

-- Xiaohongshu 1:1 (square)
INSERT INTO deepframes_platform_spec
  (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
   bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'xiaohongshu', 'video', '1:1', 1080, 1080, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 3000, "audio_bitrate_kbps": 128, "max_bitrate_kbps": 5000}'::jsonb,
  '{"require_ai_label": false}'::jsonb,
  '{"top_pct": 3, "bottom_pct": 10, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 30, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 8}'::jsonb
);

-- WeChat Video Channel (9:16)
INSERT INTO deepframes_platform_spec
  (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
   bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'wechat_video', 'video', '9:16', 1080, 1920, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 4000, "audio_bitrate_kbps": 128, "max_bitrate_kbps": 6000}'::jsonb,
  '{"require_ai_label": false}'::jsonb,
  '{"top_pct": 3, "bottom_pct": 15, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 32, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 12}'::jsonb
);

-- YouTube (16:9)
INSERT INTO deepframes_platform_spec
  (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
   bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'youtube', 'video', '16:9', 1920, 1080, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 8000, "audio_bitrate_kbps": 192, "max_bitrate_kbps": 12000}'::jsonb,
  '{"require_ai_label": false}'::jsonb,
  '{"top_pct": 5, "bottom_pct": 10, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 36, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 8}'::jsonb
);

-- Ximalaya (audio-only platform)
INSERT INTO deepframes_platform_spec
  (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
   bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'ximalaya', 'audio', 'N/A', 0, 0, 0, '', 'aac', '1.0.0', 'active',
  '{"audio_bitrate_kbps": 192, "max_bitrate_kbps": 256}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb
);
