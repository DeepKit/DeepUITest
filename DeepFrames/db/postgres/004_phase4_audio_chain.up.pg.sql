-- DeepFrames Phase 4: Audio Chain tables
-- Audio manifest for shot-level TTS synthesis, ASR timestamps,
-- audio merge, loudnorm two-pass normalization, and asset registration.

-- ---------------------------------------------------------------------------
-- deepframes_audio_manifest
-- Records per-shot TTS output, ASR timestamps, merge and loudnorm results.
-- Bound to a shot_document and a job. Audio assets registered in deepframes_asset.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_audio_manifest (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  manifest_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  content_unit_id UUID NOT NULL REFERENCES deepframes_content_unit(content_unit_id) ON DELETE SET NULL,
  job_id UUID NOT NULL REFERENCES deepframes_job(job_id) ON DELETE CASCADE,
  shot_document_id UUID NOT NULL,
  audio_asset_id UUID NULL REFERENCES deepframes_asset(asset_id) ON DELETE SET NULL,
  timestamps_asset_id UUID NULL REFERENCES deepframes_asset(asset_id) ON DELETE SET NULL,
  merged_audio_asset_id UUID NULL REFERENCES deepframes_asset(asset_id) ON DELETE SET NULL,
  duration_sec DECIMAL(10,3) NOT NULL DEFAULT 0.0,
  sample_rate INT NOT NULL DEFAULT 48000,
  channels SMALLINT NOT NULL DEFAULT 2,
  codec VARCHAR(16) NOT NULL DEFAULT 'pcm_s16le',
  bgm_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  tts_rewrite_count INT NOT NULL DEFAULT 0,
  tts_rewrite_log_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  loudnorm_pass1_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  loudnorm_pass2_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  resample_from INT NULL,
  resample_to INT NULL,
  target_lufs DECIMAL(4,1) NOT NULL DEFAULT -16.0,
  measured_lufs DECIMAL(6,2) NULL,
  measured_tp DECIMAL(6,2) NULL,
  measured_lra DECIMAL(6,2) NULL,
  concat_duration_delta_ms DECIMAL(8,2) NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_audio_manifest_status CHECK (status IN ('pending','synthesizing','asr_done','merging','loudnorm_pass1','loudnorm_pass2','done','failed')),
  CONSTRAINT ck_deepframes_audio_manifest_channels CHECK (channels IN (1, 2))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_audio_manifest_project_id ON deepframes_audio_manifest(project_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_audio_manifest_content_unit_id ON deepframes_audio_manifest(content_unit_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_audio_manifest_job_id ON deepframes_audio_manifest(job_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_audio_manifest_shot_document_id ON deepframes_audio_manifest(shot_document_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_audio_manifest_status ON deepframes_audio_manifest(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_audio_manifest_created_at ON deepframes_audio_manifest(created_at DESC);
