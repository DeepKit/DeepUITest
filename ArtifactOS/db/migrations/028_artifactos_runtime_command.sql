-- ArtifactOS Desk/Agent/Engine runtime command contract
-- All ArtifactOS programs may read/write PG, but cross-process coordination uses this contract.

begin;

create table if not exists artifactos.runtime_instance (
  id uuid primary key default gen_random_uuid(),
  instance_type text not null,
  instance_name text not null,
  host_name text not null,
  pid integer,
  app_version text,
  status text not null default 'starting',
  started_at timestamptz not null default now(),
  heartbeat_at timestamptz not null default now(),
  stopped_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,

  constraint chk_runtime_instance_type check (
    instance_type in ('desk', 'agent', 'engine', 'publishing_runtime', 'diagnostic')
  ),
  constraint chk_runtime_instance_status check (
    status in ('starting', 'running', 'idle', 'stopping', 'stopped', 'failed')
  ),
  constraint chk_runtime_instance_stopped_at check (
    (status in ('stopped', 'failed') and stopped_at is not null)
    or (status not in ('stopped', 'failed'))
  )
);

create index if not exists idx_runtime_instance_alive
  on artifactos.runtime_instance (instance_type, status, heartbeat_at desc);

create index if not exists idx_runtime_instance_name
  on artifactos.runtime_instance (instance_type, instance_name, started_at desc);

create table if not exists artifactos.runtime_command (
  id uuid primary key default gen_random_uuid(),
  command_type text not null,
  command_level text not null default 'L1',
  requested_by text not null,
  requested_source text not null,
  requested_at timestamptz not null default now(),
  status text not null default 'pending',
  priority integer not null default 100,
  payload jsonb not null default '{}'::jsonb,
  idempotency_key text,
  claimed_by uuid references artifactos.runtime_instance(id),
  claimed_at timestamptz,
  lease_until timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  retry_count integer not null default 0,
  max_retries integer not null default 0,
  error_code text,
  error_message text,
  result jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,

  constraint chk_runtime_command_status check (
    status in (
      'pending', 'claimed', 'running', 'succeeded', 'failed', 'cancelled',
      'lease_expired', 'needs_human', 'blocked'
    )
  ),
  constraint chk_runtime_command_source check (
    requested_source in ('desk', 'agent', 'amy', 'test', 'diagnostic', 'system')
  ),
  constraint chk_runtime_command_level check (
    command_level in ('L0', 'L1', 'L2', 'L3')
  ),
  constraint chk_runtime_command_priority check (priority >= 0),
  constraint chk_runtime_command_retry check (retry_count >= 0 and max_retries >= 0),
  constraint chk_runtime_command_claim check (
    (status in ('claimed', 'running') and claimed_by is not null and claimed_at is not null and lease_until is not null)
    or status not in ('claimed', 'running')
  ),
  constraint chk_runtime_command_started check (
    (status = 'running' and started_at is not null)
    or status <> 'running'
  ),
  constraint chk_runtime_command_completed check (
    (status in ('succeeded', 'failed', 'cancelled', 'needs_human', 'blocked') and completed_at is not null)
    or status not in ('succeeded', 'failed', 'cancelled', 'needs_human', 'blocked')
  )
);

create unique index if not exists uq_runtime_command_idempotency
  on artifactos.runtime_command (idempotency_key)
  where idempotency_key is not null;

create index if not exists idx_runtime_command_pending
  on artifactos.runtime_command (status, priority, requested_at)
  where status in ('pending', 'lease_expired');

create index if not exists idx_runtime_command_claimed
  on artifactos.runtime_command (claimed_by, status, lease_until);

create index if not exists idx_runtime_command_type
  on artifactos.runtime_command (command_type, status, requested_at desc);

create table if not exists artifactos.runtime_command_event (
  id uuid primary key default gen_random_uuid(),
  command_id uuid not null references artifactos.runtime_command(id) on delete cascade,
  event_type text not null,
  event_at timestamptz not null default now(),
  actor_instance_id uuid references artifactos.runtime_instance(id),
  actor_source text,
  from_status text,
  to_status text,
  message text,
  payload jsonb not null default '{}'::jsonb
);

create index if not exists idx_runtime_command_event_command
  on artifactos.runtime_command_event (command_id, event_at);

create index if not exists idx_runtime_command_event_type
  on artifactos.runtime_command_event (event_type, event_at desc);

create or replace function artifactos.fn_runtime_command_touch()
returns trigger language plpgsql as $$
begin
  if new.status in ('succeeded', 'failed', 'cancelled', 'needs_human', 'blocked') and new.completed_at is null then
    new.completed_at := now();
  end if;
  if new.status = 'running' and new.started_at is null then
    new.started_at := now();
  end if;
  return new;
end $$;

drop trigger if exists trg_runtime_command_touch on artifactos.runtime_command;
create trigger trg_runtime_command_touch
before update on artifactos.runtime_command
for each row execute function artifactos.fn_runtime_command_touch();

create or replace function artifactos.fn_runtime_command_event()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    insert into artifactos.runtime_command_event (
      command_id, event_type, actor_source, to_status, message, payload
    ) values (
      new.id, 'created', new.requested_source, new.status, 'runtime command created',
      jsonb_build_object('command_type', new.command_type, 'command_level', new.command_level)
    );
    return new;
  end if;

  if old.status is distinct from new.status then
    insert into artifactos.runtime_command_event (
      command_id, event_type, actor_instance_id, actor_source, from_status, to_status, message
    ) values (
      new.id, 'status_changed', new.claimed_by, new.requested_source, old.status, new.status,
      'runtime command status changed'
    );
  end if;
  return new;
end $$;

drop trigger if exists trg_runtime_command_event_insert on artifactos.runtime_command;
create trigger trg_runtime_command_event_insert
after insert on artifactos.runtime_command
for each row execute function artifactos.fn_runtime_command_event();

drop trigger if exists trg_runtime_command_event_update on artifactos.runtime_command;
create trigger trg_runtime_command_event_update
after update on artifactos.runtime_command
for each row execute function artifactos.fn_runtime_command_event();

create or replace function artifactos.fn_notify_runtime_command()
returns trigger language plpgsql as $$
begin
  perform pg_notify('artifactos_runtime_command', new.id::text);
  return new;
end $$;

drop trigger if exists trg_notify_runtime_command on artifactos.runtime_command;
create trigger trg_notify_runtime_command
after insert on artifactos.runtime_command
for each row execute function artifactos.fn_notify_runtime_command();

create or replace function artifactos.claim_next_runtime_command(
  p_engine_instance_id uuid,
  p_lease_seconds integer default 300
)
returns setof artifactos.runtime_command
language sql
as $$
  with next_command as (
    select id
    from artifactos.runtime_command
    where status in ('pending', 'lease_expired')
      and command_level in ('L0', 'L1', 'L2', 'L3')
    order by priority asc, requested_at asc
    for update skip locked
    limit 1
  )
  update artifactos.runtime_command c
  set
    status = 'claimed',
    claimed_by = p_engine_instance_id,
    claimed_at = now(),
    lease_until = now() + make_interval(secs => p_lease_seconds)
  from next_command n
  where c.id = n.id
  returning c.*;
$$;

create or replace function artifactos.mark_expired_runtime_commands()
returns integer
language plpgsql
as $$
declare
  affected integer;
begin
  update artifactos.runtime_command
  set status = 'lease_expired'
  where status in ('claimed', 'running')
    and lease_until < now();
  get diagnostics affected = row_count;
  return affected;
end $$;

commit;
