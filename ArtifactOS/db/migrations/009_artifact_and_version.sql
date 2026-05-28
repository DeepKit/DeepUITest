-- ArtifactOS artifact + artifact_version + artifact_part Phase 1A draft
-- Target: artifactos_test first, then artifactos production after review.
-- FK to sub_studio, artifact_plan, blueprint relaxed for Phase 1A.

begin;

-- 1. Artifact — the publishable media object
create table if not exists artifactos.artifact (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  sub_studio_id uuid,
  artifact_plan_id uuid,
  blueprint_id uuid,
  title text,
  status text not null default 'planned' check (status in (
    'planned','drafting','assembled','gate_checking','sealed','packaged','published','rework','frozen','recalled','retired'
  )),
  primary_purpose_type text,
  risk_level text not null default 'normal',
  theory_visibility text,
  seal_id uuid,
  quality_snapshot_id uuid references artifactos.quality_snapshot(id),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_artifact_sub_studio
  on artifactos.artifact (sub_studio_id, status);

create index if not exists idx_artifact_quality_snapshot
  on artifactos.artifact (quality_snapshot_id);

-- 2. ArtifactVersion — immutable version snapshot of an artifact
create table if not exists artifactos.artifact_version (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  artifact_id uuid not null references artifactos.artifact(id),
  version_no integer not null,
  assembled_payload jsonb not null default '{}'::jsonb,
  revision_session_id uuid,
  generation_reason text,
  gate_summary jsonb not null default '{}'::jsonb,
  seal_status text not null default 'unsealed' check (seal_status in ('unsealed','sealed','superseded')),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, artifact_id, version_no)
);

create index if not exists idx_artifact_version_artifact
  on artifactos.artifact_version (artifact_id, version_no);

-- 3. ArtifactPart — semantic part of a composite artifact
create table if not exists artifactos.artifact_part (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  artifact_id uuid not null references artifactos.artifact(id),
  parent_part_id uuid,
  part_type text not null,
  part_order integer not null default 0,
  sequence_no integer,
  timeline_start_ms integer,
  timeline_end_ms integer,
  content_text text,
  content_json jsonb not null default '{}'::jsonb,
  status text not null default 'draft',
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  check (sequence_no is null or sequence_no >= 0),
  check (timeline_start_ms is null or timeline_start_ms >= 0),
  check (timeline_end_ms is null or timeline_end_ms >= 0),
  check (timeline_start_ms is null or timeline_end_ms is null or timeline_end_ms >= timeline_start_ms)
);

create index if not exists idx_artifact_part_artifact
  on artifactos.artifact_part (artifact_id, part_order);

-- 4. Cross-table guard: artifact cannot be published without a sealed version
create or replace function artifactos.fn_guard_artifact_publish_requires_sealed_version()
returns trigger language plpgsql as $$
declare
  sealed_count integer;
begin
  if new.status in ('packaged', 'published') then
    select count(*) into sealed_count
    from artifactos.artifact_version
    where artifact_id = new.id and seal_status = 'sealed';
    if sealed_count = 0 then
      raise exception 'artifact cannot enter packaged/published without a sealed artifact_version';
    end if;
  end if;
  return new;
end $$;

create trigger trg_artifact_publish_requires_sealed_version
before insert or update on artifactos.artifact
for each row execute function artifactos.fn_guard_artifact_publish_requires_sealed_version();

commit;