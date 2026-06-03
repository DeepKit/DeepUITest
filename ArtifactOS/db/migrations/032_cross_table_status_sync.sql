-- ArtifactOS cross-table status sync trigger (FIXED: prevent infinite recursion)
-- Enforces docs/06 §8.2a: Artifact ↔ SubStudioExecutionTask status coupling
-- Rule 1: Artifact cannot enter 'sealed' before Task enters 'approved'
-- Rule 2: Task cannot enter 'publishing' before Artifact enters 'sealed'
-- Rule 3: Either side entering 'frozen' syncs the other side in the same transaction
--
-- Fix: session-level recursion guard via set_config('artifactos.frozen_sync_active')
-- The WHERE status != 'frozen' guard alone is insufficient because the outer UPDATE
-- has not committed yet, so the DB still sees the old value when the nested trigger fires.

begin;

-- Drop existing triggers and functions (idempotent re-run)
drop trigger if exists trg_artifact_status_sync on artifactos.artifact;
drop trigger if exists trg_task_status_sync on artifactos.substudio_execution_task;
drop function if exists artifactos.fn_guard_artifact_status_sync();
drop function if exists artifactos.fn_guard_task_status_sync();

-- Guard: Artifact status transitions must respect Task state
create or replace function artifactos.fn_guard_artifact_status_sync()
returns trigger language plpgsql as $$
declare
  task_pipeline text;
  task_id uuid;
begin
  -- Recursion guard: if we're already in a frozen-sync chain, skip
  if current_setting('artifactos.frozen_sync_active', true) = '1' then
    return new;
  end if;

  -- Only enforce when transitioning TO sealed
  if new.status = 'sealed' and (old.status is null or old.status != 'sealed') then
    select id, pipeline_status into task_id, task_pipeline
    from artifactos.substudio_execution_task
    where artifact_id = new.id;

    if not found then
      -- Phase 1A: relaxed FK — task may not exist yet; skip validation
      return new;
    end if;

    if task_pipeline not in ('approved', 'publishing', 'published', 'collecting', 'completed') then
      raise exception 'artifact cannot enter sealed before task enters approved (task=% pipeline_status=%)', task_id, task_pipeline;
    end if;
  end if;

  -- Frozen sync: artifact → task (with recursion guard)
  if new.status = 'frozen' and (old.status is null or old.status != 'frozen') then
    perform set_config('artifactos.frozen_sync_active', '1', true);
    update artifactos.substudio_execution_task
    set pipeline_status = 'frozen', updated_at = now()
    where artifact_id = new.id and pipeline_status != 'frozen';
    perform set_config('artifactos.frozen_sync_active', '', true);
  end if;

  return new;
end $$;

create trigger trg_artifact_status_sync
before update on artifactos.artifact
for each row execute function artifactos.fn_guard_artifact_status_sync();

-- Guard: Task status transitions must respect Artifact state
create or replace function artifactos.fn_guard_task_status_sync()
returns trigger language plpgsql as $$
declare
  art_status text;
begin
  -- Recursion guard: if we're already in a frozen-sync chain, skip
  if current_setting('artifactos.frozen_sync_active', true) = '1' then
    return new;
  end if;

  -- Only enforce when transitioning TO publishing
  if new.pipeline_status = 'publishing' and (old.pipeline_status is null or old.pipeline_status != 'publishing') then
    select status into art_status
    from artifactos.artifact
    where id = new.artifact_id;

    if not found then
      -- Phase 1A: relaxed FK — artifact may not exist yet; skip validation
      return new;
    end if;

    if art_status not in ('sealed', 'packaged', 'published') then
      raise exception 'task cannot enter publishing before artifact enters sealed (artifact=% status=%)', new.artifact_id, art_status;
    end if;
  end if;

  -- Frozen sync: task → artifact (with recursion guard)
  if new.pipeline_status = 'frozen' and (old.pipeline_status is null or old.pipeline_status != 'frozen') then
    perform set_config('artifactos.frozen_sync_active', '1', true);
    update artifactos.artifact
    set status = 'frozen', updated_at = now()
    where id = new.artifact_id and status != 'frozen';
    perform set_config('artifactos.frozen_sync_active', '', true);
  end if;

  return new;
end $$;

create trigger trg_task_status_sync
before update on artifactos.substudio_execution_task
for each row execute function artifactos.fn_guard_task_status_sync();

commit;