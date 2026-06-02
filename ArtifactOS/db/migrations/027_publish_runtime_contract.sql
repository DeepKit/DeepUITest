-- ArtifactOS <-> PublishingRuntime PG contract
-- ArtifactOS/Amy Desk writes intents and human actions; PublishingRuntime owns browser control.

begin;

create schema if not exists media_publish;

create table if not exists media_publish.runtime_command (
  id bigserial primary key,
  command_type text not null check (command_type in (
    'start_browser', 'show_browser', 'check_login', 'capture_screenshot',
    'publish_article', 'verify_url', 'retry_task', 'pause_session', 'close_browser'
  )),
  platform_id text not null,
  account_id text not null,
  session_key text generated always as (platform_id || '/' || account_id) stored,
  artifactos_publication_package_id uuid,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in (
    'pending', 'leased', 'running', 'completed', 'failed', 'canceled'
  )),
  lease_owner text,
  lease_expires_at timestamptz,
  result jsonb not null default '{}'::jsonb,
  error_code text,
  error_message text,
  requested_by text not null default 'amy_desk',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists idx_runtime_command_queue
  on media_publish.runtime_command (status, platform_id, account_id, id);

create index if not exists idx_runtime_command_package
  on media_publish.runtime_command (artifactos_publication_package_id, id);

create table if not exists media_publish.platform_account_session (
  platform_id text not null,
  account_id text not null,
  session_key text generated always as (platform_id || '/' || account_id) stored,
  state text not null default 'unknown' check (state in (
    'unknown', 'offline', 'starting', 'ready', 'busy', 'needs_login',
    'risk_control', 'captcha', 'publish_unknown', 'error', 'paused'
  )),
  current_task_id bigint,
  current_url text,
  profile_ref text,
  last_screenshot_ref text,
  last_event jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (platform_id, account_id)
);

create index if not exists idx_platform_account_session_state
  on media_publish.platform_account_session (state, updated_at desc);

create or replace function media_publish.fn_runtime_command_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if new.status in ('completed', 'failed', 'canceled') and new.completed_at is null then
    new.completed_at := now();
  end if;
  return new;
end $$;

drop trigger if exists trg_runtime_command_touch on media_publish.runtime_command;
create trigger trg_runtime_command_touch
before update on media_publish.runtime_command
for each row execute function media_publish.fn_runtime_command_touch();

create or replace function media_publish.fn_notify_runtime_command()
returns trigger language plpgsql as $$
begin
  perform pg_notify('media_publish_runtime_command', new.id::text);
  return new;
end $$;

drop trigger if exists trg_notify_runtime_command on media_publish.runtime_command;
create trigger trg_notify_runtime_command
after insert on media_publish.runtime_command
for each row execute function media_publish.fn_notify_runtime_command();

commit;
