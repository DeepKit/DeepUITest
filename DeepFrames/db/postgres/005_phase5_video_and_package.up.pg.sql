-- Phase 5+6: Video pipeline, platform spec, candidate package tables
-- Reference: docs/12.db-state-数据库与状态机-db-state.md

-- Platform specification (rendering profile per platform+delivery_type)
CREATE TABLE IF NOT EXISTS deepframes_platform_spec (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  platform_spec_id UUID NOT NULL UNIQUE,
  platform VARCHAR(32) NOT NULL,
  delivery_type VARCHAR(32) NOT NULL DEFAULT 'video',
  aspect_ratio VARCHAR(8) NOT NULL DEFAULT '16:9',
  width INT NOT NULL DEFAULT 1920,
  height INT NOT NULL DEFAULT 1080,
  fps DECIMAL(6,2) NOT NULL DEFAULT 30.00,
  video_codec VARCHAR(16) NOT NULL DEFAULT 'h264',
  audio_codec VARCHAR(16) NOT NULL DEFAULT 'aac',
  bitrate_policy_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  ai_label_policy_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  safe_zone_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  subtitle_policy_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  status VARCHAR(24) NOT NULL DEFAULT 'active',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_platform_spec_platform ON deepframes_platform_spec(platform);
CREATE INDEX IF NOT EXISTS idx_platform_spec_delivery ON deepframes_platform_spec(delivery_type);

-- Insert default bilibili platform spec (stable UUID for deterministic FK references)
INSERT INTO deepframes_platform_spec (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
  bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  'b11b11b1-1111-1111-1111-b11111111111'::uuid, 'bilibili', 'video', '16:9', 1920, 1080, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 8000, "audio_bitrate_kbps": 192, "max_bitrate_kbps": 12000}'::jsonb,
  '{"require_ai_label": true, "label_position": "top_right"}'::jsonb,
  '{"top_pct": 5, "bottom_pct": 10, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 36, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 8}'::jsonb
);

-- Insert douyin (抖音) platform spec — vertical 9:16
INSERT INTO deepframes_platform_spec (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
  bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'douyin', 'video', '9:16', 1080, 1920, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 6000, "audio_bitrate_kbps": 128, "max_bitrate_kbps": 8000}'::jsonb,
  '{"require_ai_label": true, "label_position": "top_right"}'::jsonb,
  '{"top_pct": 5, "bottom_pct": 15, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 32, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 12}'::jsonb
);

-- Insert kuaishou (快手) platform spec — vertical 9:16
INSERT INTO deepframes_platform_spec (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
  bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'kuaishou', 'video', '9:16', 1080, 1920, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 5000, "audio_bitrate_kbps": 128, "max_bitrate_kbps": 6000}'::jsonb,
  '{"require_ai_label": true, "label_position": "top_right"}'::jsonb,
  '{"top_pct": 5, "bottom_pct": 15, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 32, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 12}'::jsonb
);

-- Insert xiaohongshu (小红书) platform spec — vertical 3:4
INSERT INTO deepframes_platform_spec (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
  bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'xiaohongshu', 'video', '3:4', 1080, 1440, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 4000, "audio_bitrate_kbps": 128, "max_bitrate_kbps": 5000}'::jsonb,
  '{"require_ai_label": false, "label_position": "none"}'::jsonb,
  '{"top_pct": 5, "bottom_pct": 12, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 28, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 10}'::jsonb
);

-- Insert wechat_video (微信视频号) platform spec — horizontal 16:9
INSERT INTO deepframes_platform_spec (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
  bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'wechat_video', 'video', '16:9', 1920, 1080, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 6000, "audio_bitrate_kbps": 192, "max_bitrate_kbps": 8000}'::jsonb,
  '{"require_ai_label": false, "label_position": "none"}'::jsonb,
  '{"top_pct": 5, "bottom_pct": 10, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 36, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 8}'::jsonb
);

-- Insert youtube platform spec — horizontal 16:9, higher bitrate
INSERT INTO deepframes_platform_spec (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
  bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'youtube', 'video', '16:9', 1920, 1080, 30.00, 'h264', 'aac', '1.0.0', 'active',
  '{"video_bitrate_kbps": 12000, "audio_bitrate_kbps": 256, "max_bitrate_kbps": 16000}'::jsonb,
  '{"require_ai_label": false, "label_position": "none"}'::jsonb,
  '{"top_pct": 5, "bottom_pct": 10, "left_pct": 5, "right_pct": 5}'::jsonb,
  '{"font_size": 40, "font_color": "#FFFFFF", "stroke_color": "#000000", "stroke_width": 2, "position": "bottom_center", "margin_bottom_pct": 8}'::jsonb
);

-- Insert ximalaya (喜马拉雅) platform spec — audio only
INSERT INTO deepframes_platform_spec (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status,
  bitrate_policy_json, ai_label_policy_json, safe_zone_json, subtitle_policy_json)
VALUES (
  gen_random_uuid(), 'ximalaya', 'audio', '0:0', 0, 0, 0, '', 'aac', '1.0.0', 'active',
  '{"audio_bitrate_kbps": 192, "sample_rate": 48000, "channels": 2}'::jsonb,
  '{"require_ai_label": false, "label_position": "none"}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb
);

-- Video IR (render-backend-independent scene description)
CREATE TABLE IF NOT EXISTS deepframes_video_ir (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  video_ir_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  content_unit_id UUID NOT NULL REFERENCES deepframes_content_unit(content_unit_id) ON DELETE CASCADE,
  shot_document_id UUID NULL,
  audio_manifest_id UUID NULL,
  platform_spec_id UUID NULL REFERENCES deepframes_platform_spec(platform_spec_id) ON DELETE SET NULL,
  render_backend VARCHAR(16) NOT NULL DEFAULT 'hyperframes',
  template_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  timeline_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  asset_refs_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  duration_source VARCHAR(16) NOT NULL DEFAULT 'estimated',
  estimated_duration_sec DECIMAL(10,3) NULL,
  actual_duration_sec DECIMAL(10,3) NULL,
  scene_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_video_ir_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_video_ir_project ON deepframes_video_ir(project_id);
CREATE INDEX IF NOT EXISTS idx_video_ir_content_unit ON deepframes_video_ir(content_unit_id);
CREATE INDEX IF NOT EXISTS idx_video_ir_shot ON deepframes_video_ir(shot_document_id);

-- Video job (video-pipeline-specific job tracking)
CREATE TABLE IF NOT EXISTS deepframes_video_job (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  video_job_id UUID NOT NULL UNIQUE,
  job_id UUID NULL REFERENCES deepframes_job(job_id) ON DELETE SET NULL,
  video_ir_id UUID NOT NULL REFERENCES deepframes_video_ir(video_ir_id) ON DELETE CASCADE,
  platform_spec_id UUID NULL REFERENCES deepframes_platform_spec(platform_spec_id) ON DELETE SET NULL,
  render_backend VARCHAR(16) NOT NULL DEFAULT 'hyperframes',
  run_mode VARCHAR(16) NOT NULL DEFAULT 'final-with-audio',
  template_id VARCHAR(64) NULL,
  output_dir TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_video_job_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_video_job_ir ON deepframes_video_job(video_ir_id);

-- Video step (per-stage tracking within a video job)
CREATE TABLE IF NOT EXISTS deepframes_video_step (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  video_step_id UUID NOT NULL UNIQUE,
  video_job_id UUID NOT NULL REFERENCES deepframes_video_job(video_job_id) ON DELETE CASCADE,
  step_type VARCHAR(32) NOT NULL,
  step_key VARCHAR(200) NOT NULL,
  shot_id UUID NULL,
  asset_id UUID NULL,
  started_at TIMESTAMPTZ NULL,
  finished_at TIMESTAMPTZ NULL,
  metrics_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  error_message TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_video_step_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_video_step_job ON deepframes_video_step(video_job_id);

-- Video asset (video-pipeline-specific asset references)
CREATE TABLE IF NOT EXISTS deepframes_video_asset (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  video_asset_id UUID NOT NULL UNIQUE,
  video_job_id UUID NOT NULL REFERENCES deepframes_video_job(video_job_id) ON DELETE CASCADE,
  video_step_id UUID NULL REFERENCES deepframes_video_step(video_step_id) ON DELETE SET NULL,
  asset_id UUID NULL REFERENCES deepframes_asset(asset_id) ON DELETE SET NULL,
  asset_category VARCHAR(24) NOT NULL,
  shot_index INT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_video_asset_job ON deepframes_video_asset(video_job_id);

-- Candidate package (final deliverable assembly)
CREATE TABLE IF NOT EXISTS deepframes_candidate_package (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  content_unit_id UUID NOT NULL REFERENCES deepframes_content_unit(content_unit_id) ON DELETE CASCADE,
  variant_document_id UUID NULL,
  audio_manifest_id UUID NULL,
  video_ir_id UUID NULL,
  target_platform VARCHAR(32) NOT NULL DEFAULT 'bilibili',
  delivery_type VARCHAR(32) NOT NULL DEFAULT 'video',
  manifest_asset_id UUID NULL,
  cover_asset_id UUID NULL,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  quality_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  source_trace_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  output_root_uri TEXT NOT NULL DEFAULT '',
  label VARCHAR(100) NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_candidate_package_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_candidate_package_project ON deepframes_candidate_package(project_id);
CREATE INDEX IF NOT EXISTS idx_candidate_package_platform ON deepframes_candidate_package(target_platform);
CREATE INDEX IF NOT EXISTS idx_candidate_package_status ON deepframes_candidate_package(status);
