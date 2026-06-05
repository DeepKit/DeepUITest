-- ArtifactOS Strategic Intent Layer
-- Tables: purpose_type_registry, lighthouse_strategy_objective,
--         case_objective, purpose_portfolio, purpose_portfolio_item,
--         artifact_plan_purpose
-- Ref: docs/24 §4.4a, §7.2

begin;

-- ========================================
-- 1. purpose_type_registry (基础类型注册表)
-- ========================================
create table if not exists artifactos.purpose_type_registry (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  purpose_type_code text not null check (purpose_type_code not in (
    'trust_building','positioning'
  )),
  purpose_type_name_zh text not null,
  purpose_type_name_en text not null,
  purpose_family text not null,
  description text null,
  resonance_required_default boolean not null default false,
  is_system_reserved boolean not null default false,
  version_no integer not null default 1,
  status text not null check (status in ('active','draft','deprecated','disabled')),
  deprecated_by uuid null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  unique (tenant_id, purpose_type_code, version_no)
);

-- Seed default purpose types
insert into artifactos.purpose_type_registry
  (tenant_id, purpose_type_code, purpose_type_name_zh, purpose_type_name_en, purpose_family, is_system_reserved, status, created_by, updated_by)
values
  ('00000000-0000-0000-0000-000000000000', 'theory_promotion',  '理论推广',    'Theory Promotion',     'core',       true, 'active', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-0000-0000-000000000000', 'concept_explanation','概念解释',  'Concept Explanation',  'core',       true, 'active', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-0000-0000-000000000000', 'critique_response',  '批判回应',   'Critique Response',    'core',       true, 'active', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-0000-0000-000000000000', 'hot_topic_comment',  '热点评论',   'Hot Topic Commentary', 'core',       true, 'active', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-0000-0000-000000000000', 'audience_education', '受众教育',   'Audience Education',   'supporting', true, 'active', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-0000-0000-000000000000', 'methodology_share',  '方法论分享', 'Methodology Sharing',  'supporting', true, 'active', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-0000-0000-000000000000', 'community_building', '社区建设',   'Community Building',   'growth',     true, 'active', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-0000-0000-000000000000', 'brand_shaping',      '品牌塑造',   'Brand Shaping',        'growth',     true, 'active', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-0000-0000-000000000000', 'experiment',         '实验',       'Experiment',           'experimental', true, 'active', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000')
on conflict do nothing;

-- ========================================
-- 2. lighthouse_strategy_objective (灯塔策略目标)
-- ========================================
create table if not exists artifactos.lighthouse_strategy_objective (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  objective_code text not null,
  source_pack_snapshot_ref_id uuid null,
  field_ref_id uuid null,
  platform_id uuid null,
  account_id uuid null,
  field_position text not null,
  identity_positioning text not null,
  trust_building_goal text null,
  audience_state_path jsonb not null default '[]'::jsonb,
  boundary_posture jsonb not null default '{}'::jsonb,
  platform_account_role jsonb not null default '{}'::jsonb,
  non_goals jsonb not null default '[]'::jsonb,
  decision_lineage_refs jsonb not null default '[]'::jsonb,
  version_no integer not null default 1,
  status text not null check (status in ('draft','active','paused','retired')),
  approved_by uuid null,
  approved_at timestamptz null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  unique (tenant_id, objective_code, version_no),
  check (
    status <> 'active'
    or (
      source_pack_snapshot_ref_id is not null
      and approved_by is not null
      and approved_at is not null
      and jsonb_array_length(decision_lineage_refs) > 0
    )
  )
);

-- ========================================
-- 3. case_objective (案目标)
-- ========================================
create table if not exists artifactos.case_objective (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  case_id uuid not null references artifactos.case_record(id),
  parent_case_snapshot_id uuid null references artifactos.case_snapshot(id),
  committed_case_snapshot_id uuid null references artifactos.case_snapshot(id),
  lighthouse_strategy_objective_id uuid not null
    references artifactos.lighthouse_strategy_objective(id),
  objective_code text not null,
  objective_kind text not null default 'main' check (objective_kind in (
    'main','supporting','experiment','defense','repair'
  )),
  objective_sequence integer not null default 100,
  time_scope text not null check (time_scope in (
    'year','half_year','quarter','month','week','day','day_sub'
  )),
  strategic_task text not null,
  objective_priority jsonb not null default '{}'::jsonb,
  inherited_constraints jsonb not null default '{}'::jsonb,
  local_constraints jsonb not null default '{}'::jsonb,
  success_criteria jsonb not null default '{}'::jsonb,
  decision_lineage_refs jsonb not null default '[]'::jsonb,
  version_no integer not null default 1,
  status text not null check (status in ('draft','active','superseded','canceled')),
  approved_by uuid null,
  approved_at timestamptz null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  unique (tenant_id, case_id, objective_code, version_no)
);

-- ========================================
-- 4. purpose_portfolio (目的组合)
-- ========================================
create table if not exists artifactos.purpose_portfolio (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  case_objective_id uuid not null references artifactos.case_objective(id),
  case_id uuid not null references artifactos.case_record(id),
  parent_purpose_portfolio_id uuid null references artifactos.purpose_portfolio(id),
  portfolio_scope text not null check (portfolio_scope in (
    'year','half_year','quarter','month','week','day','day_sub'
  )),
  purpose_mix jsonb not null default '[]'::jsonb,
  sequence_policy jsonb not null default '{}'::jsonb,
  auto_adjustment_band jsonb not null default '{}'::jsonb,
  auto_adjustment_proof jsonb not null default '{}'::jsonb,
  human_intervention_threshold jsonb not null default '{}'::jsonb,
  capacity_budget jsonb not null default '{}'::jsonb,
  decision_lineage_refs jsonb not null default '[]'::jsonb,
  approval_mode text not null default 'human_approved' check (approval_mode in (
    'human_approved','delegated_within_band','inherited_projection'
  )),
  delegation_policy_id uuid null,
  version_no integer not null default 1,
  status text not null check (status in ('draft','active','superseded','canceled')),
  locked_by_human_at timestamptz null,
  approved_by uuid null,
  approved_at timestamptz null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  unique (tenant_id, case_objective_id, version_no),
  check (
    status <> 'active'
    or (
      approval_mode = 'human_approved'
      and locked_by_human_at is not null
      and approved_by is not null
      and approved_at is not null
    )
    or (
      approval_mode in ('delegated_within_band','inherited_projection')
      and parent_purpose_portfolio_id is not null
      and delegation_policy_id is not null
      and auto_adjustment_proof <> '{}'::jsonb
    )
  )
);

-- ========================================
-- 5. purpose_portfolio_item (目的组合条目)
-- ========================================
create table if not exists artifactos.purpose_portfolio_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  purpose_portfolio_id uuid not null references artifactos.purpose_portfolio(id),
  purpose_type_id uuid not null references artifactos.purpose_type_registry(id),
  target_ratio numeric(6,4) null,
  min_ratio numeric(6,4) null,
  max_ratio numeric(6,4) null,
  target_count integer null,
  min_count integer null,
  max_count integer null,
  sequence_weight integer not null default 100,
  status text not null check (status in ('active','paused','excluded')),

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  unique (tenant_id, purpose_portfolio_id, purpose_type_id)
);

-- ========================================
-- 6. artifact_plan_purpose (产出计划目的关系)
-- ========================================
create table if not exists artifactos.artifact_plan_purpose (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  artifact_plan_id uuid not null,
  purpose_type_id uuid not null references artifactos.purpose_type_registry(id),
  is_primary boolean not null default false,
  purpose_weight numeric(6,4) not null default 1.0000,
  purpose_context jsonb not null default '{}'::jsonb,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  unique (tenant_id, artifact_plan_id, purpose_type_id)
);

commit;
