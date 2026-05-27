-- media_publish SQLite -> PostgreSQL mapping draft
-- Target schema: media_publish
-- This file is a draft and has not been executed by Claude.

begin;

create schema if not exists media_publish;

create table if not exists media_publish.publication_task (
  id bigserial primary key,
  legacy_sqlite_id bigint,
  content_hash text not null,
  account_id text not null,
  publish_kind text not null check (publish_kind in ('article', 'answer')),
  question_id text,
  status text not null check (status in (
    'created', 'queued', 'leased', 'publishing', 'submitted', 'drafted',
    'succeeded', 'needs_human', 'unknown', 'failed', 'skipped'
  )),
  checkpoint text not null,
  idempotency_key text not null,
  lease_owner text,
  lease_expires_at timestamptz,
  profile_lock_id text,
  result_url text,
  last_error_code text,
  human_note text,
  artifactos_publication_package_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (idempotency_key, status)
);

create index if not exists idx_media_publish_task_queue
  on media_publish.publication_task (status, account_id, id);

create table if not exists media_publish.publication_task_event (
  id bigserial primary key,
  task_id bigint not null references media_publish.publication_task(id),
  legacy_sqlite_id bigint,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_media_publish_task_event_task
  on media_publish.publication_task_event (task_id, id);

create table if not exists media_publish.account_event (
  id bigserial primary key,
  account_id text not null,
  legacy_sqlite_id bigint,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_media_publish_account_event_account
  on media_publish.account_event (account_id, id);

commit;
