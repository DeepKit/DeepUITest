-- ArtifactOS runtime command hardening
-- 1. parent_command_id for future DAG/multi-step orchestration (Expert C)
-- 2. cleanup function for old commands (Expert D)
-- 3. runtime_instance cleanup for old instances (Expert A/D)

begin;

alter table artifactos.runtime_command
  add column if not exists parent_command_id uuid references artifactos.runtime_command(id);

create index if not exists idx_runtime_command_parent
  on artifactos.runtime_command (parent_command_id, status)
  where parent_command_id is not null;

create or replace function artifactos.cleanup_old_commands(p_days integer default 30)
returns integer
language plpgsql
as $$
declare
  affected integer;
begin
  delete from artifactos.runtime_command
  where completed_at < now() - make_interval(days => p_days)
    and status in ('succeeded', 'failed', 'cancelled', 'needs_human', 'blocked');
  get diagnostics affected = row_count;
  return affected;
end $$;

create or replace function artifactos.cleanup_old_instances(p_days integer default 30)
returns integer
language plpgsql
as $$
declare
  affected integer;
begin
  delete from artifactos.runtime_instance
  where stopped_at < now() - make_interval(days => p_days)
    and status in ('stopped', 'failed');
  get diagnostics affected = row_count;
  return affected;
end $$;

commit;