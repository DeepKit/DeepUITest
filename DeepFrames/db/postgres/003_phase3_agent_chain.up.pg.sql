-- DeepFrames Phase 3: Agent Chain tables
-- Prompt registry, model binding, prompt run logging, and eval results.
-- Enables the Agent production chain (Splitter/Worker/Assembler/QA/StyleKeeper).

-- ---------------------------------------------------------------------------
-- deepframes_prompt_template
-- Versioned prompt templates with output schema declarations.
-- Each template declares output_format, output_schema_json and extraction_hints.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_prompt_template (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id UUID NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL,
  agent_role VARCHAR(32) NOT NULL,
  system_prompt TEXT NOT NULL DEFAULT '',
  output_format VARCHAR(16) NOT NULL DEFAULT 'json',
  output_schema_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extraction_hints JSONB NOT NULL DEFAULT '{}'::jsonb,
  few_shot_examples JSONB NOT NULL DEFAULT '[]'::jsonb,
  split_rules_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  temperature DECIMAL(3,2) NULL,
  max_tokens INT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  version_no INT NOT NULL DEFAULT 1,
  parent_version_id UUID NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'active',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_prompt_template_status CHECK (status IN ('active','deprecated','archived')),
  CONSTRAINT ck_deepframes_prompt_template_role CHECK (agent_role IN ('splitter','worker','assembler','qa','style_keeper'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_prompt_template_agent_role ON deepframes_prompt_template(agent_role);
CREATE INDEX IF NOT EXISTS ix_deepframes_prompt_template_status ON deepframes_prompt_template(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_prompt_template_created_at ON deepframes_prompt_template(created_at DESC);

-- ---------------------------------------------------------------------------
-- deepframes_model_binding
-- Explicit binding of agent roles to LLM provider/model pairs.
-- Style Keeper has no binding (deterministic rule engine).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_model_binding (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  binding_id UUID NOT NULL UNIQUE,
  agent_role VARCHAR(32) NOT NULL,
  provider VARCHAR(32) NOT NULL,
  model VARCHAR(64) NOT NULL,
  capability VARCHAR(24) NOT NULL DEFAULT 'llm',
  api_base_url VARCHAR(256) NOT NULL DEFAULT '',
  temperature DECIMAL(3,2) NULL,
  max_tokens INT NULL,
  extra_params_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  status VARCHAR(24) NOT NULL DEFAULT 'active',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_model_binding_status CHECK (status IN ('active','deprecated','disabled')),
  CONSTRAINT ck_deepframes_model_binding_role CHECK (agent_role IN ('splitter','worker','assembler','qa','style_keeper')),
  CONSTRAINT ck_deepframes_model_binding_capability CHECK (capability IN ('llm','tts','asr','image_gen','image_edit'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_model_binding_agent_role ON deepframes_model_binding(agent_role);
CREATE INDEX IF NOT EXISTS ix_deepframes_model_binding_provider ON deepframes_model_binding(provider);
CREATE INDEX IF NOT EXISTS ix_deepframes_model_binding_status ON deepframes_model_binding(status);

-- ---------------------------------------------------------------------------
-- deepframes_prompt_run
-- Every LLM/TTS/ASR invocation is logged here for reproducibility.
-- Includes raw output, normalized JSON, validation errors and token usage.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_prompt_run (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL UNIQUE,
  job_id UUID NULL REFERENCES deepframes_job(job_id) ON DELETE SET NULL,
  job_step_id UUID NULL,
  prompt_template_id UUID NULL REFERENCES deepframes_prompt_template(template_id) ON DELETE SET NULL,
  prompt_version_no INT NOT NULL DEFAULT 1,
  model_binding_id UUID NULL REFERENCES deepframes_model_binding(binding_id) ON DELETE SET NULL,
  agent_role VARCHAR(32) NOT NULL,
  raw_output TEXT NOT NULL DEFAULT '',
  normalized_json JSONB NULL,
  validation_error TEXT NULL,
  repair_count SMALLINT NOT NULL DEFAULT 0,
  token_input INT NOT NULL DEFAULT 0,
  token_output INT NOT NULL DEFAULT 0,
  latency_ms INT NOT NULL DEFAULT 0,
  provider VARCHAR(32) NOT NULL DEFAULT '',
  model VARCHAR(64) NOT NULL DEFAULT '',
  capability VARCHAR(24) NOT NULL DEFAULT 'llm',
  tts_char_count INT NULL,
  asr_duration_sec DECIMAL(10,3) NULL,
  retry_count SMALLINT NOT NULL DEFAULT 0,
  error_code VARCHAR(32) NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  status VARCHAR(24) NOT NULL DEFAULT 'completed',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_prompt_run_status CHECK (status IN ('completed','failed','skipped')),
  CONSTRAINT ck_deepframes_prompt_run_capability CHECK (capability IN ('llm','tts','asr','image_gen','image_edit')),
  CONSTRAINT ck_deepframes_prompt_run_role CHECK (agent_role IN ('splitter','worker','assembler','qa','style_keeper','build_script','build_variant','build_shot'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_prompt_run_job_id ON deepframes_prompt_run(job_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_prompt_run_template_id ON deepframes_prompt_run(prompt_template_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_prompt_run_binding_id ON deepframes_prompt_run(model_binding_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_prompt_run_agent_role ON deepframes_prompt_run(agent_role);
CREATE INDEX IF NOT EXISTS ix_deepframes_prompt_run_status ON deepframes_prompt_run(status);
CREATE INDEX IF NOT EXISTS ix_deepframes_prompt_run_created_at ON deepframes_prompt_run(created_at DESC);

-- ---------------------------------------------------------------------------
-- deepframes_eval_result
-- QA evaluation and Style Keeper consistency check results.
-- Stores per-dimension scores, issues and recommended actions.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deepframes_eval_result (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  eval_id UUID NOT NULL UNIQUE,
  job_id UUID NOT NULL REFERENCES deepframes_job(job_id) ON DELETE CASCADE,
  job_step_id UUID NULL,
  prompt_run_id UUID NULL REFERENCES deepframes_prompt_run(run_id) ON DELETE SET NULL,
  shot_document_id UUID NULL,
  eval_type VARCHAR(24) NOT NULL,
  score DECIMAL(4,2) NOT NULL DEFAULT 0.0,
  dimensions_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  issues_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  gate VARCHAR(8) NULL,
  gate_result VARCHAR(8) NULL,
  recommended_action VARCHAR(24) NULL,
  reviewer_note TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  schema_version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  extra_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ck_deepframes_eval_result_eval_type CHECK (eval_type IN ('qa','style_keeper','accuracy','human_review')),
  CONSTRAINT ck_deepframes_eval_result_gate CHECK (gate IS NULL OR gate IN ('gate1','gate2','gate3a','gate3b')),
  CONSTRAINT ck_deepframes_eval_result_gate_result CHECK (gate_result IS NULL OR gate_result IN ('pass','warn','fail')),
  CONSTRAINT ck_deepframes_eval_result_action CHECK (recommended_action IS NULL OR recommended_action IN ('accept','rework_worker','rework_splitter','rework_script','manual_edit'))
);

CREATE INDEX IF NOT EXISTS ix_deepframes_eval_result_job_id ON deepframes_eval_result(job_id);
CREATE INDEX IF NOT EXISTS ix_deepframes_eval_result_eval_type ON deepframes_eval_result(eval_type);
CREATE INDEX IF NOT EXISTS ix_deepframes_eval_result_gate ON deepframes_eval_result(gate);
CREATE INDEX IF NOT EXISTS ix_deepframes_eval_result_gate_result ON deepframes_eval_result(gate_result);
CREATE INDEX IF NOT EXISTS ix_deepframes_eval_result_created_at ON deepframes_eval_result(created_at DESC);
