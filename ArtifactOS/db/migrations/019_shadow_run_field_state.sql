-- ArtifactOS ShadowRun + FieldState Phase 1A draft
-- Target: artifactos_test first, then progee_db.artifactos after review.

begin;

-- 1. ShadowRun — a continuous validation run
create table if not exists artifactos.shadow_run (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  run_code text not null,
  status text not null default 'planned' check (status in ('planned','running','completed','canceled','aborted')),
  start_date date not null,
  end_date date not null,
  primary_platform text not null,
  audience_stage_scope text[] not null default '{}',
  theory_visibility text not null,
  source_pack_snapshot_id uuid,
  strategy_unit_id uuid,
  run_goal_payload jsonb not null default '{}'::jsonb,
  final_report_payload jsonb not null default '{}'::jsonb,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, run_code),
  check (end_date >= start_date)
);

-- 2. ShadowRunDay — one day within a shadow run
create table if not exists artifactos.shadow_run_day (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  shadow_run_id uuid not null references artifactos.shadow_run(id),
  run_date date not null,
  day_index integer not null check (day_index between 0 and 7),
  status text not null default 'planned' check (status in (
    'planned','generated','evening_reviewing','overnight_processing',
    'morning_confirming','simulating','reported','closed','skipped'
  )),
  daily_report_id uuid references artifactos.daily_report(id),
  next_day_plan_id uuid,
  human_review_minutes integer,
  required_work_card_count integer,
  selected_option_stats jsonb not null default '{}'::jsonb,
  deviation_summary jsonb not null default '{}'::jsonb,
  review_metrics jsonb not null default '{}'::jsonb,
  stop_reason text,
  human_intervention_log jsonb not null default '[]'::jsonb,
  attention_budget_overflow boolean not null default false,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, shadow_run_id, run_date),
  unique (tenant_id, shadow_run_id, day_index),
  check (human_review_minutes is null or human_review_minutes >= 0)
);

-- 3. ShadowRunObservation — deviation observation
create table if not exists artifactos.shadow_run_observation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  shadow_run_id uuid not null references artifactos.shadow_run(id),
  shadow_run_day_id uuid not null references artifactos.shadow_run_day(id),
  observation_type text not null check (observation_type in (
    'topic_deviation','schedule_deviation','quality_deviation',
    'theory_visibility_deviation','platform_fit_deviation',
    'publication_action_deviation','human_choice_deviation',
    'same_day_exception_deviation','no_material_deviation'
  )),
  artifactos_ref jsonb not null default '{}'::jsonb,
  legacy_ref jsonb not null default '{}'::jsonb,
  deviation_type text,
  severity text not null default 'low' check (severity in ('none','low','medium','high','critical')),
  evidence_refs jsonb not null default '[]'::jsonb,
  learning_candidate jsonb not null default '{}'::jsonb,
  resolution_status text not null default 'open' check (resolution_status in ('open','accepted','converted','ignored','resolved')),
  human_note text,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  check (
    (observation_type = 'no_material_deviation' and severity in ('none','low'))
    or observation_type <> 'no_material_deviation'
  )
);

create index if not exists idx_shadow_run_obs_day
  on artifactos.shadow_run_observation (shadow_run_day_id, observation_type);

-- 4. FieldStateSnapshot — tactical picture of a field/platform/account
create table if not exists artifactos.field_state_snapshot (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  snapshot_date date not null,
  field_ref text,
  platform_id text,
  account_id text,
  topic_cluster text,
  audience_state_hypothesis jsonb not null default '{}'::jsonb,
  observed_signals jsonb not null default '[]'::jsonb,
  interpretation_hypotheses jsonb not null default '[]'::jsonb,
  light text not null default 'gray' check (light in ('green','yellow','orange','red','blue','gray')),
  confidence numeric(5,4) check (confidence >= 0 and confidence <= 1),
  valid_until date,
  algorithm_noise_flag boolean not null default false,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, snapshot_date, field_ref, platform_id, account_id, topic_cluster)
);

-- 5. AutoTuneEvent — audit of every auto-tuned parameter
create table if not exists artifactos.auto_tune_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  target_type text not null,
  target_id uuid,
  parameter_path text not null,
  before_value text,
  after_value text,
  allowed_by_policy_id uuid,
  autotune_band_id uuid,
  trigger_signal_refs jsonb not null default '[]'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  risk_level text not null default 'low' check (risk_level in ('low','medium','high','redline')),
  requires_human_review boolean not null default false,
  human_visible_level text not null default 'digest' check (human_visible_level in ('digest','review_required')),
  rollback_path text,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_auto_tune_event_target
  on artifactos.auto_tune_event (target_type, target_id, created_at);

commit;