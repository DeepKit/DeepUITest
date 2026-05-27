-- ArtifactOS DelegationPolicy + InterventionPolicy + HumanAttentionBudget Phase 1A
-- Target: artifactos_test first, then progee_db.artifactos after review.

begin;

-- 1. DelegationPolicy — what Amy is allowed to do
create table if not exists artifactos.delegation_policy (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  policy_code text not null,
  policy_scope text not null check (policy_scope in ('global','case','day_sub_case','studio','sub_studio')),
  scope_ref_id uuid,
  autonomy_level text not null check (autonomy_level in ('AL0','AL1','AL2','AL3','AL4')),
  allowed_actions text[] not null default '{}',
  forbidden_actions text[] not null default '{}',
  auto_publish_allowed boolean not null default false,
  auto_approve_allowed boolean not null default false,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  status text not null default 'active' check (status in ('active','paused','revoked','expired')),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, policy_code)
);

-- 2. InterventionPolicy — when to interrupt the human
create table if not exists artifactos.intervention_policy (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  policy_code text not null,
  policy_scope text not null,
  scope_ref_id uuid,
  interruption_level text not null check (interruption_level in (
    'silent_record','digest','review_queue','ask_next_meeting','interrupt_now'
  )),
  trigger_rules jsonb not null default '[]'::jsonb,
  escalation_rules jsonb not null default '[]'::jsonb,
  status text not null default 'active' check (status in ('active','paused','archived')),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, policy_code)
);

-- 3. HumanAttentionBudget — daily caps on human load
create table if not exists artifactos.human_attention_budget (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  budget_code text not null,
  budget_scope text not null,
  scope_ref_id uuid,
  budget_date date not null default current_date,
  max_must_review integer not null default 3,
  max_recommended_review integer not null default 3,
  max_estimated_minutes integer not null default 30,
  used_must_review integer not null default 0,
  used_recommended_review integer not null default 0,
  used_estimated_minutes integer not null default 0,
  overflow_policy text not null default 'defer_to_digest',
  status text not null default 'active' check (status in ('active','closed')),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, budget_code, budget_date)
);

-- 3a. Default budget for Phase 1A shadow run
insert into artifactos.human_attention_budget (budget_code, budget_scope, budget_date, max_must_review, max_recommended_review, max_estimated_minutes)
values ('shadow_week1_default', 'global', current_date, 3, 3, 30)
on conflict (tenant_id, budget_code, budget_date) do nothing;

-- 4. DecisionBrief — compressed human judgment item
create table if not exists artifactos.decision_brief (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  meeting_record_id uuid,
  target_type text not null,
  target_id uuid,
  brief_type text not null,
  urgency text not null check (urgency in ('low','normal','high','critical')),
  question_text text not null,
  recommended_action text,
  evidence_refs jsonb not null default '[]'::jsonb,
  alternative_actions jsonb not null default '[]'::jsonb,
  decision_status text not null default 'waiting' check (decision_status in ('waiting','decided','deferred','canceled')),
  decision_record_id uuid,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

commit;