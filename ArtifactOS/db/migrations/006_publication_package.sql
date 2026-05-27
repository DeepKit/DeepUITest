-- ArtifactOS PublicationPackage Phase 1A minimal draft
-- Target: artifactos_test first, then progee_db.artifactos after review.
-- Note: FK references to artifact, artifact_version, rendering are relaxed
--       and will be hardened in subsequent migrations.

begin;

-- pre-created in 004: real_publish_gate_run, event_ledger
-- pre-created in 003: source_pack, source_pack_loading_decision

create table if not exists artifactos.publication_package (
  id uuid primary key default gen_random_uuid(),
  artifact_id uuid,
  artifact_version_id uuid,
  representation_id uuid,
  quality_snapshot_id uuid,
  real_publish_gate_run_id uuid references artifactos.real_publish_gate_run(id),
  platform text not null,
  account_id uuid,
  title text,
  body text,
  body_format text not null default 'markdown',
  tags jsonb not null default '[]'::jsonb,
  idempotency_key text not null,
  status text not null default 'draft' check (status in (
    'draft', 'preflight', 'queued', 'submitting', 'published', 'failed', 'recalled', 'skipped', 'held', 'simulated', 'blocked', 'superseded'
  )),
  simulation_only boolean not null default true,
  run_mode text not null default 'shadow' check (run_mode in ('real', 'shadow', 'simulation')),
  schedule jsonb not null default '{}'::jsonb,
  publication_url text,
  publication_evidence jsonb not null default '{}'::jsonb,
  rollback_plan jsonb not null default '{}'::jsonb,
  sealed_at timestamptz,
  sealed_by text,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (idempotency_key, status)
);

create index if not exists idx_publication_package_status
  on artifactos.publication_package (status, created_at);

create index if not exists idx_publication_package_quality_snapshot
  on artifactos.publication_package (quality_snapshot_id);

create index if not exists idx_publication_package_real_publish_gate
  on artifactos.publication_package (real_publish_gate_run_id);

-- Guard: shadow/simulation cannot enter publishing path
create or replace function artifactos.fn_guard_shadow_publish()
returns trigger language plpgsql as $$
begin
  if new.run_mode in ('shadow', 'simulation') or new.simulation_only then
    if new.status in ('queued', 'submitting', 'published') then
      raise exception 'shadow/simulation publication_package cannot enter real publishing status';
    end if;
  end if;
  return new;
end $$;

create trigger trg_shadow_publish_guard
before insert or update on artifactos.publication_package
for each row execute function artifactos.fn_guard_shadow_publish();

-- Guard: publication_package must have quality_snapshot before queued/submitting
create or replace function artifactos.fn_guard_publish_quality_bound()
returns trigger language plpgsql as $$
begin
  if new.status in ('queued', 'submitting') and new.quality_snapshot_id is null then
    raise exception 'publication_package must bind quality_snapshot before queued/submitting';
  end if;
  return new;
end $$;

create trigger trg_publish_quality_bound
before insert or update on artifactos.publication_package
for each row execute function artifactos.fn_guard_publish_quality_bound();

commit;