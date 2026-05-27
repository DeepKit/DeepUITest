-- ArtifactOS SourcePack Phase 1A minimal tables draft
-- Target schema: artifactos
-- This file is a draft and has not been executed by Claude.

begin;

create schema if not exists artifactos;

create table if not exists artifactos.source_pack (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  source_root text not null,
  pack_type text not null default 'theory_system',
  loading_level text not null default 'SPL0' check (loading_level in ('SPL0', 'SPL1', 'SPL2', 'SPL3', 'SPL4')),
  status text not null default 'candidate' check (status in ('candidate', 'active', 'archived', 'blocked')),
  created_at timestamptz not null default now()
);

create table if not exists artifactos.source_inventory_candidate (
  id uuid primary key default gen_random_uuid(),
  source_pack_id uuid references artifactos.source_pack(id),
  file_path text not null,
  content_kind text not null,
  source_layer text not null,
  candidate_claim_strength text not null,
  external_publish_policy text not null,
  human_review_status text not null default 'pending' check (human_review_status in ('pending', 'approved', 'rejected', 'needs_split')),
  file_size_bytes bigint,
  file_mtime timestamptz,
  file_hash text,
  created_at timestamptz not null default now(),
  unique (source_pack_id, file_path)
);

create table if not exists artifactos.source_pack_loading_decision (
  id uuid primary key default gen_random_uuid(),
  source_pack_id uuid not null references artifactos.source_pack(id),
  decision_type text not null check (decision_type in ('allow_inventory', 'allow_trial_generation', 'allow_production', 'block')),
  allow_production boolean not null default false,
  decided_by text not null,
  human_decision_id uuid,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

commit;
