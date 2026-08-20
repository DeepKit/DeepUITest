-- DeepFrames Phase 2: Document Chain tables
-- Extends Phase 1 schema with script_document, accuracy_report,
-- variant_document, shot_document, asset, and quality_gate_result.

-- ---------------------------------------------------------------------------
-- deepframes_script_document
-- Versioned document table for LLM-generated scripts.
-- parent_document_id -> deepframes_source_document.document_id
-- source_document_id -> deepframes_source_document.document_id (traceability)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_script_document (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  content_unit_id UUID NOT NULL REFERENCES deepframes_content_unit(content_unit_id) ON DELETE CASCADE,
  document_kind VARCHAR(24) NOT NULL DEFAULT 'script',
  parent_document_id UUID NULL,
  source_document_id UUID NULL,
  prompt_template_id UUID NULL,
  model_binding_id UUID NULL,
  quality_summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  content_hash CHAR(64) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL,
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_script_document_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_script_document_project_id ON deepframes_script_document(project_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_script_document_content_unit_id ON deepframes_script_document(content_unit_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_script_document_status ON deepframes_script_document(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_script_document_created_at ON deepframes_script_document(created_at DESC);
CREATE INDEX IF NOT EXISTS ix_deepframes_script_document_payload ON deepframes_script_document USING GIN (payload_json);

-- ---------------------------------------------------------------------------
-- deepframes_accuracy_report
-- Independent report linking source_document to script_document.
-- Validates script fidelity to source material.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_accuracy_report (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  source_document_id UUID NOT NULL REFERENCES deepframes_source_document(document_id) ON DELETE CASCADE,
  script_document_id UUID NOT NULL REFERENCES deepframes_script_document(document_id) ON DELETE CASCADE,
  coverage_score DECIMAL(4,2) NOT NULL DEFAULT 0.0,
  distortion_score DECIMAL(4,2) NOT NULL DEFAULT 0.0,
  result VARCHAR(8) NOT NULL DEFAULT 'pass',
  issues_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  human_review_status VARCHAR(16) NOT NULL DEFAULT 'auto_passed',
  reviewer_note TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL,
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'done',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_accuracy_report_result CHECK (result IN ('pass','warn','fail')),
  CONSTRAINT ck_deepframes_accuracy_report_human_status CHECK (human_review_status IN ('auto_passed','pending_review','human_accepted','human_rejected')),
  CONSTRAINT ck_deepframes_accuracy_report_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_accuracy_report_source_doc ON deepframes_accuracy_report(source_document_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_accuracy_report_script_doc ON deepframes_accuracy_report(script_document_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_accuracy_report_result ON deepframes_accuracy_report(result);
CREATE INDEX IF NOT EXISTS ix_deepframes_accuracy_report_created_at ON deepframes_accuracy_report(created_at DESC);

-- ---------------------------------------------------------------------------
-- deepframes_variant_document
-- Versioned document for content variants (A/B, platform, account).
-- parent_document_id -> deepframes_script_document.document_id
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_variant_document (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  content_unit_id UUID NOT NULL REFERENCES deepframes_content_unit(content_unit_id) ON DELETE CASCADE,
  document_kind VARCHAR(24) NOT NULL DEFAULT 'variant',
  parent_document_id UUID NULL,
  source_document_id UUID NULL,
  variant_kind VARCHAR(16) NOT NULL DEFAULT 'main',
  variant_label VARCHAR(100) NOT NULL DEFAULT '',
  target_platform VARCHAR(32) NOT NULL DEFAULT '',
  account_profile VARCHAR NULL,
  expression_policy_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  quality_summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  content_hash CHAR(64) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL,
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_variant_document_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_variant_document_project_id ON deepframes_variant_document(project_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_variant_document_content_unit_id ON deepframes_variant_document(content_unit_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_variant_document_status ON deepframes_variant_document(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_variant_document_created_at ON deepframes_variant_document(created_at DESC);
CREATE INDEX IF NOT EXISTS ix_deepframes_variant_document_payload ON deepframes_variant_document USING GIN (payload_json);

-- ---------------------------------------------------------------------------
-- deepframes_shot_document
-- Versioned document for shot-level breakdown.
-- parent_document_id -> deepframes_variant_document.document_id
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_shot_document (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  content_unit_id UUID NOT NULL REFERENCES deepframes_content_unit(content_unit_id) ON DELETE CASCADE,
  document_kind VARCHAR(24) NOT NULL DEFAULT 'shot',
  parent_document_id UUID NULL,
  source_document_id UUID NULL,
  style_anchor_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  quality_summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  content_hash CHAR(64) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL,
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_shot_document_status CHECK (status IN ('pending','running','blocked_review','done','skipped','failed','cancelled'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_shot_document_project_id ON deepframes_shot_document(project_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_shot_document_content_unit_id ON deepframes_shot_document(content_unit_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_shot_document_status ON deepframes_shot_document(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_shot_document_created_at ON deepframes_shot_document(created_at DESC);
CREATE INDEX IF NOT EXISTS ix_deepframes_shot_document_payload ON deepframes_shot_document USING GIN (payload_json);

-- ---------------------------------------------------------------------------
-- deepframes_asset
-- File-based asset registry with lifecycle management.
-- Status is temp/ready/failed/deleted (separate from business object status).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_asset (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id UUID NOT NULL UNIQUE,
  project_id UUID NOT NULL REFERENCES deepframes_project(project_id) ON DELETE CASCADE,
  content_unit_id UUID NULL REFERENCES deepframes_content_unit(content_unit_id) ON DELETE SET NULL,
  asset_type VARCHAR(24) NOT NULL,
  uri TEXT NOT NULL DEFAULT '',
  sha256 CHAR(64) NOT NULL,
  byte_size BIGINT NOT NULL DEFAULT 0,
  mime_type VARCHAR(64) NOT NULL DEFAULT '',
  duration_sec DECIMAL(10,3) NULL,
  sample_rate INT NULL,
  channels SMALLINT NULL,
  codec VARCHAR(16) NULL,
  width INT NULL,
  height INT NULL,
  fps DECIMAL(6,2) NULL,
  frame_count INT NULL,
  producer VARCHAR(64) NOT NULL DEFAULT '',
  producer_version VARCHAR(16) NOT NULL DEFAULT '',
  anchor_asset_id UUID NULL,
  reference_asset_id UUID NULL,
  image_generation_mode VARCHAR(16) NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'temp',
  protected_until TIMESTAMPTZ NULL,
  retention_class VARCHAR(8) NOT NULL DEFAULT 'C3',
  cleanup_eligible_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_job_id UUID NULL,
  schema_version VARCHAR(16) NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_asset_status CHECK (status IN ('temp','ready','failed','deleted')),
  CONSTRAINT ck_deepframes_asset_type CHECK (asset_type IN ('source','audio','video','image','subtitle','manifest','snapshot','package'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_asset_project_id ON deepframes_asset(project_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_asset_content_unit_id ON deepframes_asset(content_unit_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_asset_type ON deepframes_asset(asset_type);
CREATE INDEX IF NOT EXISTS ix_deepframes_asset_status ON deepframes_asset(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_asset_created_at ON deepframes_asset(created_at DESC);

-- ---------------------------------------------------------------------------
-- deepframes_quality_gate_result
-- Quality gate outcomes per job/gate combination.
-- gate_result is pass/warn/fail; warn continues with note, fail enters blocked_review.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_quality_gate_result (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  result_id UUID NOT NULL UNIQUE,
  job_id UUID NOT NULL REFERENCES deepframes_job(job_id) ON DELETE CASCADE,
  gate VARCHAR(8) NOT NULL,
  gate_result VARCHAR(8) NOT NULL,
  score DECIMAL(4,2) NOT NULL DEFAULT 0.0,
  issues_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  human_review_status VARCHAR(16) NOT NULL DEFAULT 'auto_passed',
  reviewer_note TEXT NULL,
  human_action_json JSONB NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_quality_gate_result CHECK (gate_result IN ('pass','warn','fail')),
  CONSTRAINT ck_deepframes_quality_gate_gate CHECK (gate IN ('gate1','gate2','gate3a','gate3b')),
  CONSTRAINT ck_deepframes_quality_gate_human_status CHECK (human_review_status IN ('auto_passed','pending_review','human_accepted','human_rejected'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_quality_gate_result_job_id ON deepframes_quality_gate_result(job_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_quality_gate_result_gate ON deepframes_quality_gate_result(gate);
CREATE INDEX IF NOT EXISTS ix_deepframes_quality_gate_result_gate_result ON deepframes_quality_gate_result(gate_result);
CREATE INDEX IF NOT EXISTS ix_deepframes_quality_gate_result_created_at ON deepframes_quality_gate_result(created_at DESC);
