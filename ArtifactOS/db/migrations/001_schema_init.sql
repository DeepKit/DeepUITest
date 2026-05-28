-- ArtifactOS Phase 1A schema initialization draft
-- Target: artifactos_test first, then artifactos production after review.
-- This file is a draft and has not been executed by Claude.

begin;

create schema if not exists artifactos;
create schema if not exists media_publish;
create schema if not exists legacy_bridge;

create table if not exists artifactos.schema_migration_log (
  id bigserial primary key,
  migration_name text not null unique,
  applied_at timestamptz not null default now(),
  checksum text not null,
  notes text not null default ''
);

create table if not exists artifactos.event_ledger (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  aggregate_type text not null,
  aggregate_id uuid,
  actor_type text not null default 'system',
  actor_id text,
  payload jsonb not null default '{}'::jsonb,
  correlation_id uuid,
  causation_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_event_ledger_aggregate
  on artifactos.event_ledger (aggregate_type, aggregate_id, created_at);

create index if not exists idx_event_ledger_event_type
  on artifactos.event_ledger (event_type, created_at);

commit;
