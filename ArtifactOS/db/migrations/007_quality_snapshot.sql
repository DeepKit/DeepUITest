-- ArtifactOS QualitySnapshot Phase 1A minimal draft
-- Target: artifactos_test first, then progee_db.artifactos after review.
-- FK references to artifact, artifact_version, purpose_type_registry are relaxed
-- and will be hardened in subsequent migrations after those tables are created.

begin;

create table if not exists artifactos.quality_run (
  id uuid primary key default gen_random_uuid(),
  artifact_id uuid,
  artifact_version_id uuid,
  run_type text not null check (run_type in ('es', 'ses', 'nes', 'strategy_decision', 'gate')),
  quality_policy_version integer not null default 1,
  run_evidence jsonb not null default '{}'::jsonb,
  run_score jsonb not null default '{}'::jsonb,
  run_status text not null default 'started' check (run_status in ('started', 'completed', 'failed', 'superseded')),
  run_error text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_quality_run_artifact_version
  on artifactos.quality_run (artifact_id, artifact_version_id, completed_at);

create table if not exists artifactos.quality_snapshot (
  id uuid primary key default gen_random_uuid(),
  artifact_id uuid,
  artifact_version_id uuid,
  quality_run_ids_cache jsonb not null default '[]'::jsonb,
  qualified_status text not null check (qualified_status in (
    'not_qualified', 'qualified', 'high_quality', 'blocked'
  )),
  publish_readiness text not null check (publish_readiness in (
    'not_ready', 'ready', 'ready_with_warning', 'frozen'
  )),
  purpose_fit_status text not null check (purpose_fit_status in (
    'pass', 'warning', 'fail', 'not_applicable'
  )),
  seal_candidate boolean not null default false,
  sealed_at timestamptz,
  sealed_by text,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_quality_snapshot_artifact_version
  on artifactos.quality_snapshot (artifact_id, artifact_version_id, sealed_at desc);

-- Guard: quality_snapshot sealed records cannot be modified
create or replace function artifactos.fn_guard_snapshot_immutable()
returns trigger language plpgsql as $$
begin
  if old.sealed_at is not null then
    raise exception 'sealed quality_snapshot cannot be modified; create a new snapshot instead';
  end if;
  return new;
end $$;

create trigger trg_snapshot_immutable
before update on artifactos.quality_snapshot
for each row execute function artifactos.fn_guard_snapshot_immutable();

commit;