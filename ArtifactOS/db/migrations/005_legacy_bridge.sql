-- ArtifactOS LegacySystemBridge Phase 1A draft
-- Target: artifactos_test first, then progee_db after review.
-- This file is a draft and has not been executed by Claude.

begin;

create schema if not exists legacy_bridge;

create table if not exists legacy_bridge.legacy_import_batch (
  id uuid primary key default gen_random_uuid(),
  batch_code text not null unique,
  source_system text not null,
  source_root text,
  import_scope text not null default 'publication_record',
  import_mode text not null default 'read_only' check (import_mode in ('read_only')),
  status text not null default 'prepared' check (status in ('prepared', 'imported', 'partial', 'failed')),
  imported_at timestamptz not null default now(),
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists legacy_bridge.legacy_external_ref (
  id uuid primary key default gen_random_uuid(),
  import_batch_id uuid not null references legacy_bridge.legacy_import_batch(id),
  ref_type text not null check (ref_type in (
    'daily_plan', 'staging_artifact', 'quality_report', 'publication_record', 'pipeline_output', 'unknown'
  )),
  ref_label text,
  source_path text,
  source_uri text,
  source_hash text,
  source_mtime timestamptz,
  captured_at timestamptz not null default now(),
  raw_summary text,
  status text not null default 'captured' check (status in ('captured', 'mapped', 'accepted', 'rejected', 'archived')),
  created_at timestamptz not null default now()
);

create index if not exists idx_legacy_external_ref_batch
  on legacy_bridge.legacy_external_ref (import_batch_id, ref_type);

create table if not exists legacy_bridge.legacy_snapshot (
  id uuid primary key default gen_random_uuid(),
  legacy_external_ref_id uuid not null references legacy_bridge.legacy_external_ref(id),
  snapshot_kind text not null check (snapshot_kind in (
    'plan', 'artifact', 'quality', 'publication', 'pipeline'
  )),
  content_hash text,
  snapshot_payload jsonb not null default '{}'::jsonb,
  captured_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists legacy_bridge.legacy_diff_card (
  id uuid primary key default gen_random_uuid(),
  shadow_run_day_id uuid,
  legacy_external_ref_id uuid references legacy_bridge.legacy_external_ref(id),
  comparison_key text,
  artifactos_ref jsonb not null default '{}'::jsonb,
  legacy_ref jsonb not null default '{}'::jsonb,
  deviation_type text,
  severity text not null default 'low' check (severity in ('none', 'low', 'medium', 'high', 'critical')),
  learning_candidate jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open', 'accepted', 'ignored', 'converted')),
  decision_ref_id uuid,
  created_at timestamptz not null default now()
);

commit;