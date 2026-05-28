-- ArtifactOS case_snapshot + meeting_protocol + meeting_record Phase 1A draft
-- Target: artifactos_test first, then artifactos production after review.
-- FK to case_record references are fully bound (case_record was created in 008).

begin;

-- 1. CaseSnapshot — immutable version of a Case at a meeting submission point
create table if not exists artifactos.case_snapshot (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  case_id uuid not null references artifactos.case_record(id),
  case_type text not null,
  version_no integer not null,
  parent_case_snapshot_id uuid,
  source_meeting_record_id uuid,
  snapshot_payload jsonb not null default '{}'::jsonb,
  committed_at timestamptz not null default now(),
  committed_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, case_id, version_no)
);

create index if not exists idx_case_snapshot_case
  on artifactos.case_snapshot (case_id, version_no);

-- Guard: case_snapshot rows may not be updated (immutable)
create or replace function artifactos.fn_guard_case_snapshot_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'case_snapshot rows are immutable; create a new version instead';
end $$;

create trigger trg_case_snapshot_immutable
before update on artifactos.case_snapshot
for each row execute function artifactos.fn_guard_case_snapshot_immutable();

-- 2. MeetingProtocol — static configuration per meeting type
create table if not exists artifactos.meeting_protocol (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  meeting_type text not null check (meeting_type in (
    'annual','half_year','quarter','month','week','day'
  )),
  output_case_type text not null check (output_case_type in (
    'year','half_year','quarter','month','week','day'
  )),
  planning_nature text not null check (planning_nature in (
    'strategic_execution','strategic_adjustment','strategic_arrangement',
    'strategic_landing','tactical_arrangement','tactical_execution'
  )),
  required_input_types text[] not null default '{}',
  required_output_types text[] not null default '{}',
  allowed_decision_types text[] not null default '{}',
  forbidden_decision_types text[] not null default '{}',
  status text not null default 'active' check (status in ('active','retired')),
  change_authority jsonb not null default '{}'::jsonb,
  escalation_rules jsonb not null default '[]'::jsonb,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, meeting_type)
);

-- 3. MeetingRecord — one meeting occurrence
create table if not exists artifactos.meeting_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  meeting_code text not null,
  meeting_type text not null,
  protocol_id uuid references artifactos.meeting_protocol(id),
  case_id uuid not null references artifactos.case_record(id),
  parent_case_id uuid references artifactos.case_record(id),
  status text not null default 'draft' check (status in (
    'draft','prepared','in_review','committed','archived','canceled'
  )),
  scheduled_at timestamptz,
  started_at timestamptz,
  committed_at timestamptz,
  agenda_payload jsonb not null default '[]'::jsonb,
  input_summary jsonb not null default '{}'::jsonb,
  decision_summary jsonb not null default '{}'::jsonb,
  output_case_snapshot_id uuid,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, meeting_code)
);

create index if not exists idx_meeting_record_case
  on artifactos.meeting_record (case_id, meeting_type, status);

-- 4. Seed default meeting protocols for Phase 1A
do $$
begin
  -- Daily meeting
  if not exists (select 1 from artifactos.meeting_protocol where meeting_type='day' and tenant_id='00000000-0000-0000-0000-000000000001') then
    insert into artifactos.meeting_protocol (meeting_type, output_case_type, planning_nature)
    values ('day', 'day', 'tactical_execution');
  end if;
  -- Weekly meeting
  if not exists (select 1 from artifactos.meeting_protocol where meeting_type='week' and tenant_id='00000000-0000-0000-0000-000000000001') then
    insert into artifactos.meeting_protocol (meeting_type, output_case_type, planning_nature)
    values ('week', 'week', 'tactical_arrangement');
  end if;
  -- Monthly meeting
  if not exists (select 1 from artifactos.meeting_protocol where meeting_type='month' and tenant_id='00000000-0000-0000-0000-000000000001') then
    insert into artifactos.meeting_protocol (meeting_type, output_case_type, planning_nature)
    values ('month', 'month', 'strategic_landing');
  end if;
  -- Quarterly meeting
  if not exists (select 1 from artifactos.meeting_protocol where meeting_type='quarter' and tenant_id='00000000-0000-0000-0000-000000000001') then
    insert into artifactos.meeting_protocol (meeting_type, output_case_type, planning_nature)
    values ('quarter', 'quarter', 'strategic_arrangement');
  end if;
  -- Half-year meeting
  if not exists (select 1 from artifactos.meeting_protocol where meeting_type='half_year' and tenant_id='00000000-0000-0000-0000-000000000001') then
    insert into artifactos.meeting_protocol (meeting_type, output_case_type, planning_nature)
    values ('half_year', 'half_year', 'strategic_adjustment');
  end if;
  -- Annual meeting
  if not exists (select 1 from artifactos.meeting_protocol where meeting_type='annual' and tenant_id='00000000-0000-0000-0000-000000000001') then
    insert into artifactos.meeting_protocol (meeting_type, output_case_type, planning_nature)
    values ('annual', 'year', 'strategic_execution');
  end if;
end $$;

commit;