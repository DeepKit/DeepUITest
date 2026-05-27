-- ArtifactOS case_record + studio + sub_studio Phase 1A draft
-- Target: artifactos_test first, then progee_db.artifactos after review.
-- Self-referencing FK (parent_case_id, root_case_id) relaxed for Phase 1A.
-- Phase 1A defaults: single tenant_id placeholder, single default case.

begin;

-- 1. Case record — unified temporal case table
create table if not exists artifactos.case_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  case_code text,
  case_type text not null check (case_type in (
    'year','half_year','quarter','month','week','day','day_sub'
  )),
  parent_case_id uuid,
  root_case_id uuid,
  title text not null,
  status text not null default 'planned' check (status in (
    'planned','active','reviewing','closed','frozen','archived'
  )),
  planning_nature text not null check (planning_nature in (
    'strategic_execution','strategic_adjustment','strategic_arrangement',
    'strategic_landing','tactical_arrangement','tactical_execution'
  )),
  time_start date,
  time_end date,
  source_pack_snapshot_id uuid,
  delegation_policy_id uuid,
  intervention_policy_id uuid,
  goal_summary text,
  boundary_summary text,
  artifact_capacity jsonb not null default '{}'::jsonb,
  plan_pool jsonb not null default '[]'::jsonb,
  case_payload jsonb not null default '{}'::jsonb,
  current_snapshot_id uuid,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, case_code)
);

create index if not exists idx_case_record_parent
  on artifactos.case_record (parent_case_id, case_type);

create index if not exists idx_case_record_root
  on artifactos.case_record (root_case_id);

-- 2. Studio — fixed generation environment
create table if not exists artifactos.studio (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  studio_code text not null,
  case_id uuid not null,
  day_sub_case_id uuid,
  account_id text,
  platform_id text,
  audience_state text,
  artifact_type text,
  theory_visibility text,
  status text not null default 'planning' check (status in (
    'planning','running','gate_checking','closed','frozen'
  )),
  generation_environment jsonb not null default '{}'::jsonb,
  studio_policy jsonb not null default '{}'::jsonb,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, studio_code)
);

create index if not exists idx_studio_case
  on artifactos.studio (case_id, status);

-- 3. ArtifactPlan — what a SubStudio will produce
create table if not exists artifactos.artifact_plan (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  studio_id uuid,
  blueprint_id uuid,
  purpose_hint text,
  risk_level text not null default 'normal',
  status text not null default 'draft' check (status in (
    'draft','approved','executing','completed','frozen','canceled'
  )),
  primary_purpose_type text,
  contract_ref_id uuid,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_artifact_plan_studio
  on artifactos.artifact_plan (studio_id, status);

-- 4. SubStudio — single artifact execution unit
create table if not exists artifactos.sub_studio (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  studio_id uuid,
  artifact_plan_id uuid,
  status text not null default 'planned' check (status in (
    'planned','executing','reviewing','packaged','closed','rework','frozen'
  )),
  execution_context jsonb not null default '{}'::jsonb,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_sub_studio_studio
  on artifactos.sub_studio (studio_id, status);

-- 5. Phase 1A seed — single default case + single default studio
-- Idempotent insert; safe to re‑run.
do $$
declare
  cid uuid;
  sid uuid;
begin
  select id into cid from artifactos.case_record where case_code = 'yearcase_2026' and tenant_id = '00000000-0000-0000-0000-000000000001';
  if cid is null then
    insert into artifactos.case_record (case_code, case_type, title, status, planning_nature, goal_summary)
    values ('yearcase_2026', 'year', 'YearCase 2026: ArtifactOS Shadow Run', 'active', 'strategic_execution', 'First operational surface: shadow run validation')
    returning id into cid;
  end if;

  insert into artifactos.case_record (case_code, parent_case_id, root_case_id, case_type, title, status, planning_nature, goal_summary)
  values ('weekcase_2026_shadow_run', cid, cid, 'week', 'WeekCase: Shadow Run Week 1', 'active', 'tactical_arrangement', 'Week-long shadow run using Yiyuanlun SourcePack + Zhihu platform')
  on conflict (tenant_id, case_code) do nothing;

  insert into artifactos.case_record (case_code, parent_case_id, root_case_id, case_type, title, status, planning_nature, goal_summary)
  values ('daycase_2026_shadow_day0', cid, cid, 'day', 'DayCase: Shadow Run Day 0 Prep', 'active', 'tactical_execution', 'Day 0: environment verification, SourcePack load, Legacy bridge import')
  on conflict (tenant_id, case_code) do nothing;

  select id into sid from artifactos.studio where studio_code = 'zhihu_shadow_studio_01' and tenant_id = '00000000-0000-0000-0000-000000000001';
  if sid is null then
    insert into artifactos.studio (studio_code, case_id, platform_id, artifact_type, theory_visibility, status, generation_environment)
    values ('zhihu_shadow_studio_01', cid, 'zhihu', 'zhihu_longform', 'medium', 'planning',
            '{"platform":"zhihu","account":"main","source_pack":"difference_monism","run_mode":"shadow"}'::jsonb);
  end if;
end $$;

commit;