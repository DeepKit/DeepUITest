-- ArtifactOS: L1 Core Structure — Plan Set, Part Version, Case Control, Capability,
-- Meeting, Quality Policy, Amy Workstation
-- Batch A-D: 14 tables from docs/24

begin;

-- ============================================================
-- Batch A: Core Structure (4 tables)
-- ============================================================

-- 5D.4 artifact_plan_set
create table if not exists artifactos.artifact_plan_set (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  studio_id uuid not null references artifactos.studio(id),
  case_id uuid not null references artifactos.case_record(id),
  status text not null check (status in ('draft','approved','running','closed','frozen')),
  plan_summary jsonb not null default '{}'::jsonb,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 5D.7 artifact_part_version
create table if not exists artifactos.artifact_part_version (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  artifact_part_id uuid not null references artifactos.artifact_part(id),
  artifact_version_id uuid not null references artifactos.artifact_version(id),
  version_no integer not null,
  content_text text null,
  content_json jsonb not null default '{}'::jsonb,
  change_reason text null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, artifact_part_id, version_no)
);

-- 5B.1 case_change_control
create table if not exists artifactos.case_change_control (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  case_type text not null,
  field_path text not null,
  change_policy text not null,
  allowed_meeting_types text[] not null default '{}',
  requires_human_decision boolean not null default true,
  requires_plan_change_proposal boolean not null default true,
  emergency_override text null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, case_type, field_path)
);

-- 5C.2 production_capability_registry
create table if not exists artifactos.production_capability_registry (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  capability_code text not null,
  capability_type text not null check (capability_type in (
    'generation','review','revision','rendition','publishing',
    'signal_collection','recall','forgetting_refine','notification'
  )),
  provider text not null,
  model_or_tool text null,
  input_contract jsonb not null default '{}'::jsonb,
  output_contract jsonb not null default '{}'::jsonb,
  allowed_target_types text[] not null default '{}',
  permission_scope jsonb not null default '{}'::jsonb,
  risk_level text not null check (risk_level in ('low','medium','high','redline')),
  cost_profile jsonb not null default '{}'::jsonb,
  quality_score numeric null,
  deprecation_status text not null default 'active' check (deprecation_status in (
    'active','trial','deprecated','disabled'
  )),
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, capability_code)
);

-- ============================================================
-- Batch B: Meeting + Decision (3 tables)
-- ============================================================

-- 5B.4 meeting_input_ref
create table if not exists artifactos.meeting_input_ref (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  meeting_record_id uuid not null references artifactos.meeting_record(id),
  ref_type text not null,
  ref_id uuid not null,
  ref_label text null,
  relevance_reason text null,
  injected_by text not null default 'secretary',
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 5B.4 meeting_decision_record
create table if not exists artifactos.meeting_decision_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  meeting_record_id uuid not null references artifactos.meeting_record(id),
  decision_type text not null,
  target_type text not null,
  target_id uuid null,
  decision_action text not null,
  decision_narrative text not null,
  requires_follow_up boolean not null default false,
  follow_up_ref_type text null,
  follow_up_ref_id uuid null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 5C.1 human_review_choice
create table if not exists artifactos.human_review_choice (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  work_card_id uuid null references artifactos.work_card(id),
  panel_id uuid null references artifactos.prepared_action_panel(id),
  option_id uuid null references artifactos.prepared_action_option(id),
  source_channel text not null check (source_channel in (
    'amy_cockpit','weixin','mobile','voice','api'
  )),
  raw_input text null,
  choice_type text not null,
  status text not null check (status in (
    'received','applied','canceled','rejected','superseded'
  )),
  resulting_ref_type text null,
  resulting_ref_id uuid null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- ============================================================
-- Batch C: Quality + Purpose Policy (3 tables)
-- ============================================================

-- 7.1 quality_policy
create table if not exists artifactos.quality_policy (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  policy_code text not null,
  policy_scope text not null,
  scope_ref_id uuid null,
  purpose_type_id uuid not null references artifactos.purpose_type_registry(id),
  required_hard_gates text[] not null default '{}',
  minimum_score_dimensions jsonb not null default '{}'::jsonb,
  quality_exit_criteria jsonb not null default '{}'::jsonb,
  version_no integer not null default 1,
  status text not null default 'active',
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, policy_code, version_no)
);

-- 7.2 purpose_policy_binding
create table if not exists artifactos.purpose_policy_binding (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  binding_code text not null,
  selector_key text not null,
  purpose_type_id uuid not null references artifactos.purpose_type_registry(id),
  platform_id uuid null,
  account_id uuid null,
  artifact_shape text null,
  audience_state text null,
  source_pack_profile text null,
  strategy_unit_id uuid null,
  lighthouse_strategy_objective_id uuid null
    references artifactos.lighthouse_strategy_objective(id),
  case_objective_id uuid null references artifactos.case_objective(id),
  purpose_portfolio_id uuid null references artifactos.purpose_portfolio(id),
  artifact_blueprint_id uuid null references artifactos.artifact_blueprint(id),
  quality_policy_id uuid not null references artifactos.quality_policy(id),
  amy_action_policy jsonb not null default '{}'::jsonb,
  expression_diversity_policy jsonb not null default '{}'::jsonb,
  fatigue_signal_policy jsonb not null default '{}'::jsonb,
  specificity_score integer not null default 100,
  priority integer not null default 100,
  effective_from timestamptz null,
  effective_to timestamptz null,
  version_no integer not null default 1,
  status text not null check (status in ('active','draft','deprecated','disabled')),
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, binding_code, version_no)
);

-- 7.3 quality_snapshot_run (M2M)
create table if not exists artifactos.quality_snapshot_run (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  quality_snapshot_id uuid not null references artifactos.quality_snapshot(id),
  quality_run_id uuid not null references artifactos.quality_run(id),
  relation_role text not null default 'supporting' check (relation_role in (
    'primary','supporting','override_evidence'
  )),
  sort_order integer not null default 100,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, quality_snapshot_id, quality_run_id)
);

-- ============================================================
-- Batch D: Amy Workstation — Delivery + Plan Versioning (5 tables)
-- ============================================================

-- 5C.4 delivery_attempt
create table if not exists artifactos.delivery_attempt (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  notification_event_id uuid not null references artifactos.notification_event(id),
  channel_id uuid not null references artifactos.notification_channel(id),
  attempt_no integer not null,
  status text not null check (status in (
    'queued','sending','success','failed','retrying','rebind_required','abandoned'
  )),
  request_payload jsonb not null default '{}'::jsonb,
  response_payload jsonb not null default '{}'::jsonb,
  error_code text null,
  error_message text null,
  started_at timestamptz null,
  finished_at timestamptz null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, notification_event_id, attempt_no)
);

-- 5C.5 weixin_context_token
create table if not exists artifactos.weixin_context_token (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  amy_weixin_channel_id uuid not null references artifactos.amy_weixin_channel(id),
  weixin_user_id text not null,
  context_token_ciphertext text not null,
  captured_at timestamptz not null,
  expires_at timestamptz null,
  last_verified_at timestamptz null,
  token_status text not null check (token_status in (
    'active','stale','expired','revoked'
  )),
  failure_count integer not null default 0,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, amy_weixin_channel_id, weixin_user_id)
);

-- 5D.2 next_day_plan_version
create table if not exists artifactos.next_day_plan_version (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  next_day_plan_id uuid not null references artifactos.next_day_plan(id),
  version_no integer not null,
  created_from_report_id uuid null references artifactos.daily_report(id),
  plan_payload jsonb not null,
  change_reason text null,
  source_refs jsonb not null default '[]'::jsonb,
  gate_summary jsonb not null default '{}'::jsonb,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, next_day_plan_id, version_no)
);

-- 5D.2 next_day_plan_parent_snapshot
create table if not exists artifactos.next_day_plan_parent_snapshot (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  next_day_plan_id uuid not null references artifactos.next_day_plan(id),
  next_day_plan_version_id uuid null references artifactos.next_day_plan_version(id),
  snapshot_type text not null check (snapshot_type in (
    'year','half_year','quarter','month','week','day'
  )),
  case_snapshot_id uuid not null references artifactos.case_snapshot(id),
  boundary_summary jsonb not null default '{}'::jsonb,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, next_day_plan_id, snapshot_type)
);

-- 5D.2 next_day_plan_promotion
create table if not exists artifactos.next_day_plan_promotion (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  next_day_plan_id uuid not null references artifactos.next_day_plan(id),
  next_day_plan_version_id uuid not null references artifactos.next_day_plan_version(id),
  target_date date not null,
  promotion_status text not null check (promotion_status in (
    'prepared','applied','blocked','canceled'
  )),
  parent_snapshot_refs jsonb not null default '[]'::jsonb,
  authorization_ref_type text not null check (authorization_ref_type in (
    'human_review_choice','meeting_decision_record','delegation_policy'
  )),
  authorization_ref_id uuid not null,
  promoted_day_case_id uuid null references artifactos.case_record(id),
  promoted_day_sub_case_ids uuid[] not null default '{}',
  block_reason text null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- ============================================================
-- Indexes
-- ============================================================
create index if not exists idx_artifact_plan_set_studio
  on artifactos.artifact_plan_set (tenant_id, studio_id);
create index if not exists idx_artifact_part_version_part
  on artifactos.artifact_part_version (tenant_id, artifact_part_id);
create index if not exists idx_meeting_input_ref_meeting
  on artifactos.meeting_input_ref (tenant_id, meeting_record_id);
create index if not exists idx_meeting_decision_record_meeting
  on artifactos.meeting_decision_record (tenant_id, meeting_record_id);
create index if not exists idx_human_review_choice_work_card
  on artifactos.human_review_choice (tenant_id, work_card_id);
create index if not exists idx_quality_policy_code
  on artifactos.quality_policy (tenant_id, policy_code);
create index if not exists idx_purpose_policy_binding_code
  on artifactos.purpose_policy_binding (tenant_id, binding_code);
create index if not exists idx_delivery_attempt_event
  on artifactos.delivery_attempt (tenant_id, notification_event_id);
create index if not exists idx_next_day_plan_version_plan
  on artifactos.next_day_plan_version (tenant_id, next_day_plan_id);

commit;
