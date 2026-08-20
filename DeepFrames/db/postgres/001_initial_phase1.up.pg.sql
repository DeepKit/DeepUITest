CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS deepframes_project (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL UNIQUE,
  title VARCHAR(200) NOT NULL,
  content_type VARCHAR(32) NOT NULL DEFAULT 'longform_zh_article',
  source_uri TEXT NOT NULL DEFAULT '',
  default_preset_id VARCHAR(32) NOT NULL DEFAULT 'default',
  default_platform VARCHAR(32) NOT NULL DEFAULT 'bilibili',
  default_duration_sec INT NOT NULL DEFAULT 900,
  config_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL,
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_project_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE TABLE IF NOT EXISTS deepframes_content_unit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_unit_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  unit_type VARCHAR(32) NOT NULL,
  parent_unit_id UUID NULL,
  derived_from_unit_id UUID NULL,
  display_label VARCHAR(100) NOT NULL,
  order_index INT NOT NULL DEFAULT 0,
  source_range_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  target_duration_sec INT NOT NULL DEFAULT 900,
  platform_scope_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL,
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_content_unit_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE TABLE IF NOT EXISTS deepframes_source_document (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  content_unit_id UUID NOT NULL REFERENCES deepframes_content_unit(content_unit_id) ON DELETE CASCADE,
  document_kind VARCHAR(24) NOT NULL DEFAULT 'source',
  parent_document_id UUID NULL,
  source_document_id UUID NULL,
  prompt_template_id UUID NULL,
  model_binding_id UUID NULL,
  quality_summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  content_hash CHAR(64) NOT NULL,
  source_uri TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL,
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_source_document_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE TABLE IF NOT EXISTS deepframes_job (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  content_unit_id UUID NULL REFERENCES deepframes_content_unit(content_unit_id) ON DELETE SET NULL,
  job_type VARCHAR(24) NOT NULL,
  logical_key VARCHAR(200) NOT NULL UNIQUE,
  job_queue_task_id TEXT NULL,
  priority SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL,
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_job_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE TABLE IF NOT EXISTS deepframes_job_step (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id UUID NOT NULL UNIQUE,
  job_id UUID NOT NULL REFERENCES deepframes_job(job_id) ON DELETE CASCADE,
  step_type VARCHAR(48) NOT NULL,
  step_key VARCHAR(240) NOT NULL UNIQUE,
  shot_id UUID NULL,
  asset_id UUID NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL,
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_job_step_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_project_status ON deepframes_project(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_project_created_at ON deepframes_project(created_at DESC);

CREATE INDEX IF NOT EXISTS ix_deepframes_content_unit_project_id ON deepframes_content_unit(project_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_content_unit_status ON deepframes_content_unit(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_content_unit_created_at ON deepframes_content_unit(created_at DESC);

CREATE INDEX IF NOT EXISTS ix_deepframes_source_document_project_id ON deepframes_source_document(project_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_source_document_content_unit_id ON deepframes_source_document(content_unit_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_source_document_status ON deepframes_source_document(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_source_document_created_at ON deepframes_source_document(created_at DESC);
CREATE INDEX IF NOT EXISTS ix_deepframes_source_document_payload ON deepframes_source_document USING GIN (payload_json);

CREATE INDEX IF NOT EXISTS ix_deepframes_job_project_id ON deepframes_job(project_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_job_content_unit_id ON deepframes_job(content_unit_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_job_status ON deepframes_job(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_job_created_at ON deepframes_job(created_at DESC);

CREATE INDEX IF NOT EXISTS ix_deepframes_job_step_job_id ON deepframes_job_step(job_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_job_step_status ON deepframes_job_step(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_job_step_created_at ON deepframes_job_step(created_at DESC);
