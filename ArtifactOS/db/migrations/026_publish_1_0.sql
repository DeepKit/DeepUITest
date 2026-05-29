-- ArtifactOS 1.0 publishing loop
-- Adds L3 real publish state model and automatic published verification fields.

begin;

alter table artifactos.publication_package
  drop constraint if exists publication_package_status_check;

alter table artifactos.publication_package
  add constraint publication_package_status_check check (status in (
    'draft', 'preflight', 'ready',
    'queued', 'submitting', 'submitted', 'verify_unknown', 'published',
    'failed', 'recalled', 'skipped', 'held', 'simulated', 'blocked', 'superseded'
  ));

alter table artifactos.publication_package
  drop constraint if exists publication_package_run_mode_check;

alter table artifactos.publication_package
  add constraint publication_package_run_mode_check check (run_mode in (
    'shadow', 'simulation', 'parallel', 'real'
  ));

alter table artifactos.publication_package
  add column if not exists media_publish_task_id integer,
  add column if not exists publish_verification_status text not null default 'not_checked' check (
    publish_verification_status in ('not_checked','published_confirmed','verify_unknown','failed')
  ),
  add column if not exists publish_verified_at timestamptz,
  add column if not exists publish_verification_evidence jsonb not null default '{}'::jsonb;

create index if not exists idx_publication_package_verification
  on artifactos.publication_package (publish_verification_status, created_at desc);

-- Real publish mode can be opened by setting artifactos.run_mode=L3 or real_publish.
create or replace function artifactos.check_real_publish_gate() returns jsonb
language plpgsql as $$
declare
  mode text;
begin
  mode := coalesce(current_setting('artifactos.run_mode', true), 'shadow');

  if mode in ('L3', 'real_publish') then
    return jsonb_build_object(
      'gate_status', 'passed',
      'reason', 'ArtifactOS 1.0 L3 real_publish enabled',
      'checked_at', now()
    );
  end if;

  return jsonb_build_object(
    'gate_status', 'blocked',
    'reason', 'RealPublishGate is closed unless artifactos.run_mode is L3/real_publish',
    'checked_at', now()
  );
end $$;

create or replace function artifactos.fn_guard_shadow_publish()
returns trigger language plpgsql as $$
begin
  if new.run_mode in ('shadow', 'simulation') or new.simulation_only then
    if new.status in ('queued', 'submitting', 'submitted', 'verify_unknown', 'published') then
      raise exception 'shadow/simulation publication_package cannot enter real publishing status';
    end if;
  end if;
  return new;
end $$;

create or replace function artifactos.fn_guard_publish_requires_gate()
returns trigger language plpgsql as $$
declare
  g text;
begin
  if new.status in ('queued', 'submitting', 'submitted', 'verify_unknown', 'published') and new.run_mode = 'real' then
    select gate_status into g
    from artifactos.real_publish_gate_run
    where publication_package_id = new.id
    order by created_at desc limit 1;
    if g is null or g != 'passed' then
      raise exception 'publication_package cannot enter real publishing status without a passed RealPublishGateRun';
    end if;
  end if;
  return new;
end $$;

commit;
