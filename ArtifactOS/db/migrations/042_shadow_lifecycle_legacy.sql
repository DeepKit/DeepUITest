-- ArtifactOS: L1 Shadow Run + Lifecycle + Legacy Tables
-- Batch G-H: 5 tables — shadow_run_input_pack, shadow_run_comparison_pair,
-- forgetting_queue, retained_pattern_store, calibration_impact_log

begin;

-- ============================================================
-- Shadow Run (2 tables)
-- ============================================================

-- 5D.12 shadow_run_input_pack
create table if not exists artifactos.shadow_run_input_pack (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  shadow_run_id uuid not null references artifactos.shadow_run(id),
  run_date date not null,
  source_pack_snapshot_id uuid null,
  week_case_snapshot_id uuid null references artifactos.case_snapshot(id),
  day_case_id uuid null references artifactos.case_record(id),
  legacy_input_refs jsonb not null default '[]'::jsonb,
  platform_constraint_refs jsonb not null default '[]'::jsonb,
  captured_at timestamptz not null default now(),
  input_hash text null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, shadow_run_id, run_date)
);

-- 5D.14 shadow_run_comparison_pair
create table if not exists artifactos.shadow_run_comparison_pair (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  shadow_run_id uuid not null references artifactos.shadow_run(id),
  shadow_run_day_id uuid not null references artifactos.shadow_run_day(id),
  comparison_key text not null,
  artifactos_ref jsonb not null default '{}'::jsonb,
  legacy_ref jsonb not null default '{}'::jsonb,
  pair_status text not null check (pair_status in (
    'matched','artifactos_only','legacy_only','unobservable','human_not_reviewed'
  )),
  pairing_reason text null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, shadow_run_day_id, comparison_key)
);

-- ============================================================
-- Lifecycle: Forgetting + Retained Patterns + Calibration Impact (3 tables)
-- ============================================================

-- 9.5 forgetting_queue
create table if not exists artifactos.forgetting_queue (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  source_type text not null,
  source_id uuid not null,
  current_lifecycle_state text not null check (current_lifecycle_state in (
    'active','candidate','muted','deprecated','archived'
  )),
  proposed_lifecycle_state text null check (proposed_lifecycle_state is null or proposed_lifecycle_state in (
    'active','candidate','muted','deprecated','archived'
  )),
  retention_score numeric(8,4) null,
  refinement_reason text null,
  next_refine_at timestamptz null,
  status text not null default 'pending',
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 9.6 retained_pattern_store
create table if not exists artifactos.retained_pattern_store (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  pattern_type text not null,
  pattern_scope text not null,
  scope_ref_id uuid null,
  pattern_payload jsonb not null,
  source_refs jsonb not null default '[]'::jsonb,
  confidence numeric(5,4) null,
  lifecycle_state text not null check (lifecycle_state in (
    'candidate','active_pattern','stale','deprecated','archived'
  )),
  activation_policy jsonb not null default '{}'::jsonb,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- calibration_impact_log
create table if not exists artifactos.calibration_impact_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  calibration_example_id uuid not null references artifactos.calibration_example(id),
  target_type text not null,
  target_id uuid not null,
  impact_type text not null check (impact_type in (
    'context_injection','gate_warning','rewrite_guidance',
    'delegation_suggestion','recall','avoidance'
  )),
  context_pack_id uuid null,
  rationale text not null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- ============================================================
-- Indexes
-- ============================================================
create index if not exists idx_shadow_run_input_pack_run_date
  on artifactos.shadow_run_input_pack (tenant_id, shadow_run_id, run_date);
create index if not exists idx_shadow_run_comparison_pair_day
  on artifactos.shadow_run_comparison_pair (tenant_id, shadow_run_day_id);
create index if not exists idx_forgetting_queue_status
  on artifactos.forgetting_queue (tenant_id, status, next_refine_at);
create index if not exists idx_retained_pattern_store_type
  on artifactos.retained_pattern_store (tenant_id, pattern_type, lifecycle_state);
create index if not exists idx_calibration_impact_log_example
  on artifactos.calibration_impact_log (tenant_id, calibration_example_id);

commit;
