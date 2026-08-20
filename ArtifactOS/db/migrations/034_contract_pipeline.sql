-- Migration 034: Contract pipeline data layer
-- Provides the minimum RSC/CTF/Contract chain required before writing pipeline development:
--   RequirementFrame -> ContentSpecSnapshot -> ContractCandidate -> ArtifactContract

begin;

create table if not exists artifactos.requirement_frame (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',

  source_signal_id uuid,
  topic text not null,
  intent text not null,

  target_account jsonb not null default '{}'::jsonb,
  target_platform jsonb not null default '{}'::jsonb,
  strategy_unit_id uuid,
  entry_mode text,
  theory_intervention_level text,
  target_reader text,
  success_result text,

  in_scope jsonb not null default '[]'::jsonb,
  non_goals jsonb not null default '[]'::jsonb,
  unresolved jsonb not null default '[]'::jsonb,

  gen_status text not null default 'generated' check (gen_status in ('pending','generated','failed')),
  review_status text not null default 'pending' check (review_status in ('pending','accepted','rejected','locked')),
  confidence text not null default 'medium' check (confidence in ('low','medium','high')),
  rsc_status text not null default 'draft' check (rsc_status in ('draft','needs_clarification','ready_for_ctf','blocked')),

  source_refs jsonb not null default '[]'::jsonb,
  decision_refs jsonb not null default '[]'::jsonb,
  spec_issue_refs jsonb not null default '[]'::jsonb,
  payload jsonb not null default '{}'::jsonb,

  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_requirement_frame_status
  on artifactos.requirement_frame (rsc_status, review_status, created_at desc);

create table if not exists artifactos.content_spec_snapshot (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  requirement_frame_id uuid not null references artifactos.requirement_frame(id),

  gen_status text not null default 'generated' check (gen_status in ('pending','generated','failed')),
  review_status text not null default 'pending' check (review_status in ('pending','accepted','rejected','locked')),
  snapshot_status text not null default 'frozen' check (snapshot_status in ('frozen','stale','needs_review')),

  semantic_bundles jsonb not null default '[]'::jsonb,
  content_hash text,
  source_hashes jsonb not null default '[]'::jsonb,
  decision_refs jsonb not null default '[]'::jsonb,
  issue_refs jsonb not null default '[]'::jsonb,
  accept_level text not null default 'provisional' check (accept_level in ('provisional','release','accountable')),
  evidence_coverage numeric(4,3) not null default 0 check (evidence_coverage >= 0 and evidence_coverage <= 1),
  stale_status text not null default 'fresh' check (stale_status in ('fresh','stale','needs_review')),
  payload jsonb not null default '{}'::jsonb,

  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  check (jsonb_typeof(semantic_bundles) = 'array'),
  check (jsonb_typeof(source_hashes) = 'array')
);

create index if not exists idx_content_spec_snapshot_requirement
  on artifactos.content_spec_snapshot (requirement_frame_id, snapshot_status, created_at desc);

create table if not exists artifactos.contract_candidate (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  source_spec_snapshot_id uuid not null references artifactos.content_spec_snapshot(id),

  status text not null default 'draft' check (status in ('draft','ready','blocked')),
  blocking_reason text,
  suggested_must_land jsonb not null default '[]'::jsonb,
  suggested_taboos jsonb not null default '[]'::jsonb,
  viral_reference text,
  suggested_word_count jsonb not null default '[2000,3500]'::jsonb,
  suggested_style text,
  strategy_recommendation jsonb not null default '{}'::jsonb,
  payload jsonb not null default '{}'::jsonb,

  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  check (status != 'blocked' or blocking_reason is not null),
  check (jsonb_typeof(suggested_must_land) = 'array'),
  check (jsonb_typeof(suggested_taboos) = 'array'),
  check (jsonb_typeof(suggested_word_count) = 'array')
);

create index if not exists idx_contract_candidate_snapshot
  on artifactos.contract_candidate (source_spec_snapshot_id, status, created_at desc);

create table if not exists artifactos.artifact_contract (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',

  contract_code text not null,
  contract_type text not null default 'full_contract' check (contract_type in ('full_contract','seed_contract')),
  strategy_unit_id uuid,
  maturity text not null default 'draft' check (maturity in ('draft','agreed','formal')),
  version_no integer not null default 1 check (version_no >= 1),
  status text not null default 'draft' check (status in ('draft','active','approved','executing','evolved','completed','abandoned')),

  requirement_frame_id uuid references artifactos.requirement_frame(id),
  source_spec_snapshot_id uuid references artifactos.content_spec_snapshot(id),
  contract_candidate_id uuid references artifactos.contract_candidate(id),

  source jsonb not null default '{}'::jsonb,
  strategy jsonb not null default '{}'::jsonb,
  theory jsonb not null default '{}'::jsonb,
  cognition jsonb not null default '{}'::jsonb,
  directive jsonb not null default '{}'::jsonb,
  structure jsonb not null default '{}'::jsonb,
  constraints_json jsonb not null default '{}'::jsonb,
  materials jsonb not null default '{}'::jsonb,
  quality jsonb not null default '{}'::jsonb,
  collaboration jsonb not null default '{}'::jsonb,
  account_binding jsonb not null default '{}'::jsonb,
  asto jsonb not null default '{}'::jsonb,
  odd jsonb not null default '{}'::jsonb,
  payload jsonb not null default '{}'::jsonb,

  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  unique (tenant_id, contract_code, version_no),
  check (status != 'approved' or contract_candidate_id is not null)
);

create index if not exists idx_artifact_contract_candidate
  on artifactos.artifact_contract (contract_candidate_id, status);

alter table artifactos.substudio_execution_task
  add column if not exists requirement_frame_id uuid,
  add column if not exists spec_snapshot_id uuid,
  add column if not exists contract_candidate_id uuid,
  add column if not exists artifact_contract_id uuid;

create index if not exists idx_substudio_exec_task_contract
  on artifactos.substudio_execution_task (artifact_contract_id, spec_status);

create index if not exists idx_substudio_exec_task_contract_id
  on artifactos.substudio_execution_task (contract_id, spec_status);

-- Add FK constraints idempotently.  Existing legacy rows are preserved by validating future writes.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'fk_substudio_task_requirement_frame') then
    alter table artifactos.substudio_execution_task
      add constraint fk_substudio_task_requirement_frame
      foreign key (requirement_frame_id) references artifactos.requirement_frame(id) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_substudio_task_spec_snapshot') then
    alter table artifactos.substudio_execution_task
      add constraint fk_substudio_task_spec_snapshot
      foreign key (spec_snapshot_id) references artifactos.content_spec_snapshot(id) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_substudio_task_contract_candidate') then
    alter table artifactos.substudio_execution_task
      add constraint fk_substudio_task_contract_candidate
      foreign key (contract_candidate_id) references artifactos.contract_candidate(id) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_substudio_task_artifact_contract') then
    alter table artifactos.substudio_execution_task
      add constraint fk_substudio_task_artifact_contract
      foreign key (artifact_contract_id) references artifactos.artifact_contract(id) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_substudio_task_contract_id') then
    alter table artifactos.substudio_execution_task
      add constraint fk_substudio_task_contract_id
      foreign key (contract_id) references artifactos.artifact_contract(id) not valid;
  end if;
end $$;

create or replace function artifactos.fn_guard_task_contract_chain()
returns trigger language plpgsql as $$
declare
  v_contract_id uuid;
  v_contract_status text;
  v_candidate_id uuid;
  v_candidate_status text;
begin
  v_contract_id := coalesce(new.artifact_contract_id, new.contract_id);

  if new.spec_status = 'contracted' then
    if v_contract_id is null then
      raise exception 'spec_status=contracted requires artifact_contract_id or contract_id';
    end if;

    select status, contract_candidate_id into v_contract_status, v_candidate_id
    from artifactos.artifact_contract
    where id = v_contract_id;

    if not found then
      raise exception 'contracted task references missing artifact_contract %', v_contract_id;
    end if;

    if v_contract_status not in ('active','approved','executing','completed') then
      raise exception 'contracted task requires active/approved/executing/completed artifact_contract, got %', v_contract_status;
    end if;

    if v_candidate_id is not null then
      select status into v_candidate_status
      from artifactos.contract_candidate
      where id = v_candidate_id;

      if v_candidate_status != 'ready' then
        raise exception 'artifact_contract candidate must be ready before task can be contracted, got %', v_candidate_status;
      end if;
    end if;
  end if;

  if new.spec_status = 'candidate_ready' and new.contract_candidate_id is null then
    raise exception 'spec_status=candidate_ready requires contract_candidate_id';
  end if;

  return new;
end $$;

drop trigger if exists trg_task_contract_chain on artifactos.substudio_execution_task;
create trigger trg_task_contract_chain
before insert or update on artifactos.substudio_execution_task
for each row execute function artifactos.fn_guard_task_contract_chain();

commit;
