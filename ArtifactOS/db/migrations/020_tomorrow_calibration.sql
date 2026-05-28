-- ArtifactOS TomorrowPublish + DailyCalibrationReview + CalibrationExample Phase 1A
-- Target: artifactos_test first, then artifactos production after review.

begin;

-- 1. NextDayPlan — draft for tomorrow
create table if not exists artifactos.next_day_plan (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  plan_code text not null,
  source_day_case_id uuid references artifactos.case_record(id),
  target_date date not null,
  status text not null default 'draft' check (status in ('draft','proposed','confirmed','promoted','canceled','superseded')),
  auto_run_list jsonb not null default '[]'::jsonb,
  needs_human_list jsonb not null default '[]'::jsonb,
  morning_light_confirmation_required boolean not null default false,
  human_decision_id uuid,
  promoted_day_case_id uuid references artifactos.case_record(id),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, plan_code),
  unique (tenant_id, target_date, source_day_case_id)
);

-- 2. TomorrowPublishBatch — batch of tomorrow candidates
create table if not exists artifactos.tomorrow_publish_batch (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  next_day_plan_id uuid not null references artifactos.next_day_plan(id),
  target_date date not null,
  status text not null default 'draft' check (status in (
    'draft','evening_reviewing','overnight_revising',
    'morning_confirming','approved_for_publish','held','frozen','canceled'
  )),
  platform_scope jsonb not null default '[]'::jsonb,
  batch_summary jsonb not null default '{}'::jsonb,
  prepared_action_panel_id uuid,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 3. TomorrowPublishCandidate — one candidate in a batch
create table if not exists artifactos.tomorrow_publish_candidate (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  batch_id uuid not null references artifactos.tomorrow_publish_batch(id),
  artifact_id uuid not null references artifactos.artifact(id),
  artifact_version_id uuid references artifactos.artifact_version(id),
  publication_package_id uuid references artifactos.publication_package(id),
  status text not null default 'candidate' check (status in (
    'candidate','evening_reviewing','overnight_revising',
    'morning_confirming','approved_for_publish','held','frozen','canceled'
  )),
  risk_level text not null default 'normal',
  review_summary jsonb not null default '{}'::jsonb,
  human_review_choice_id uuid,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 4. SameDayExceptionProposal — urgent same-day publish
create table if not exists artifactos.same_day_exception_proposal (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  source_signal_id uuid,
  opportunity_reason text not null,
  window_expires_at timestamptz not null,
  status text not null default 'detected' check (status in (
    'detected','proposed','fast_gate_checking','waiting_human',
    'approved','published','stored','rejected','expired'
  )),
  risk_level text not null default 'normal' check (risk_level in ('low','normal','high','critical')),
  human_override boolean not null default false,
  publication_package_id uuid references artifactos.publication_package(id),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 5. DailyCalibrationReview — one human-reviewed calibration artifact per day
create table if not exists artifactos.daily_calibration_review (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  review_date date not null,
  artifact_id uuid references artifactos.artifact(id),
  artifact_version_id uuid references artifactos.artifact_version(id),
  work_card_id uuid references artifactos.work_card(id),
  review_scope_type text not null default 'artifact' check (review_scope_type in ('artifact','artifact_part','rendition','publication_package')),
  review_scope_payload jsonb not null default '{}'::jsonb,
  candidate_reason text,
  no_candidate_reason text,
  recommended_focus text,
  skip_reason text,
  status text not null default 'candidate' check (status in ('candidate','recommended','reviewing','completed','skipped','no_candidate','canceled')),
  human_review_choice_id uuid,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, review_date),
  check (status <> 'no_candidate' or (artifact_id is null and no_candidate_reason is not null)),
  check (status <> 'skipped' or skip_reason is not null)
);

-- 6. CalibrationExample — positive/negative/mixed model from human review
create table if not exists artifactos.calibration_example (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  source_daily_calibration_review_id uuid references artifactos.daily_calibration_review(id),
  artifact_id uuid references artifactos.artifact(id),
  artifact_version_id uuid references artifactos.artifact_version(id),
  example_type text not null check (example_type in ('positive','negative','mixed')),
  scope_type text not null default 'artifact' check (scope_type in ('artifact','artifact_part','rendition','publication_package','strategy_unit','account','platform')),
  scope_payload jsonb not null default '{}'::jsonb,
  pattern_payload jsonb not null default '{}'::jsonb,
  lifecycle_state text not null default 'candidate' check (lifecycle_state in ('candidate','active_pattern','stale','deprecated','archived')),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

commit;