-- ArtifactOS RealPublishGate Phase 1A draft
-- Target: artifactos_test first, then artifactos production after review.
-- This file is a draft and has not been executed by Claude.

begin;

-- 1. RealPublishGateRun — the single publish gate record
-- Every PublicationPackage entering real submission must have one passed run.
create table if not exists artifactos.real_publish_gate_run (
  id uuid primary key default gen_random_uuid(),
  publication_package_id uuid not null,
  quality_snapshot_id uuid not null,
  gate_status text not null default 'pending' check (gate_status in (
    'pending', 'passed', 'failed', 'needs_human', 'blocked', 'canceled'
  )),
  -- all fact inputs, frozen at gate time
  gate_inputs jsonb not null default '{}'::jsonb,
  gate_results jsonb not null default '{}'::jsonb,
  human_takeover_required boolean not null default false,
  rollback_plan jsonb not null default '{}'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_real_publish_gate_package
  on artifactos.real_publish_gate_run (publication_package_id, gate_status);

-- 2. RealPublishGate audit view — computable from artifactos schema
-- This view exposes the Phase 1A input facts that the gate must verify.
-- In Phase 1A, run_mode is always 'shadow', so this view always returns blocked.
create or replace view artifactos.real_publish_gate_inputs as
select
  current_setting('artifactos.run_mode', true)::text as run_mode,
  0 as legacy_stage_rank,
  coalesce(
    (select allow_production from artifactos.source_pack_loading_decision
     where source_pack_id = (
       select id from artifactos.source_pack where status = 'active' limit 1
     )
     order by created_at desc limit 1),
    false
  ) as allow_production,
  false as rollback_ready,
  false as human_override_allowed
;

-- 3. RealPublishGate check function — returns passed/blocked/failed/needs_human
-- In Phase 1A, always returns blocked because run_mode=shadow and legacy_stage_rank=0.
create or replace function artifactos.check_real_publish_gate() returns jsonb
language plpgsql as $$
declare
  result jsonb;
begin
  result := jsonb_build_object(
    'gate_status', 'blocked',
    'reason', 'Phase 1A: shadow run only; RealPublishGate is not active until LegacyStage >= L3',
    'checked_at', now()
  );
  return result;
end $$;

-- 4. Guard trigger: publication_package must pass RealPublishGate before queued/submitting/published
-- NOTE: publication_package table is created in migration 006. The trigger is
-- created here only if the table already exists; otherwise migration 006 will
-- bind the trigger via its own CREATE TRIGGER (see 006_publication_package.sql).
create or replace function artifactos.fn_guard_publish_requires_gate()
returns trigger language plpgsql as $$
declare
  g text;
begin
  if new.status in ('queued', 'submitting', 'published') and new.run_mode = 'real' then
    select gate_status into g
    from artifactos.real_publish_gate_run
    where publication_package_id = new.id
    order by created_at desc limit 1;
    if g is null or g != 'passed' then
      raise exception 'publication_package cannot enter queued/submitting/published without a passed RealPublishGateRun';
    end if;
  end if;
  return new;
end $$;

do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'artifactos' and table_name = 'publication_package') then
    execute 'drop trigger if exists trg_real_publish_gate_required on artifactos.publication_package';
    execute 'create trigger trg_real_publish_gate_required
      before insert or update on artifactos.publication_package
      for each row execute function artifactos.fn_guard_publish_requires_gate()';
  end if;
end $$;

commit;