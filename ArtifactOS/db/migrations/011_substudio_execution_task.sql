-- ArtifactOS SubStudioExecutionTask Phase 1A draft
-- Target: artifactos_test first, then artifactos production after review.
-- This is the three-axis state machine engine referenced in docs/06.
-- FK to sub_studio, artifact_plan, strategy_unit relaxed for Phase 1A.

begin;

create table if not exists artifactos.substudio_execution_task (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',

  sub_studio_id uuid references artifactos.sub_studio(id),
  artifact_plan_id uuid references artifactos.artifact_plan(id),
  artifact_id uuid references artifactos.artifact(id),

  -- Three-axis state machine (see docs/06 §7A for legal combos)
  pipeline_status text not null default 'pending' check (pipeline_status in (
    'pending','contracting','drafting','reviewing','approved','publishing',
    'published','collecting','completed','publish_failed','frozen',
    'waiting_human','stored','draft_only','not_writing','abandoned'
  )),
  quality_status text not null default 'pending' check (quality_status in (
    'pending','structure_checking','structure_passed','structure_blocked',
    'es_checking','es_passed','es_failed','ses_checking','ses_passed',
    'ses_warned','strategy_decision','passed','rework','sample_review',
    'waiting_human','stored'
  )),
  publish_status text not null default 'pending' check (publish_status in (
    'pending','scheduled','publishing','published','failed','recalled','skipped'
  )),

  -- Pre‑gate status axes
  spec_status text not null default 'clarifying' check (spec_status in (
    'clarifying','snapshotting','candidate_ready','contracted','needs_review','stale'
  )),
  strategy_status text not null default 'active' check (strategy_status in (
    'active','warning','degraded','paused','experiment'
  )),
  cognition_status text not null default 'not_started' check (cognition_status in (
    'not_started','tracing','evidence_claiming','falsification_checking',
    'cognition_ready','evidence_gap','boundary_required'
  )),

  -- Runtime
  run_mode text not null default 'shadow' check (run_mode in ('real','shadow','simulation')),
  shadow_run_day_id uuid,
  boundary_decision text check (boundary_decision in (
    'write','not_write','draft_only','store_candidate','wait_human','freeze'
  )),

  -- Counters
  rework_count integer not null default 0,
  evolution_count integer not null default 0,
  max_rewrite integer not null default 3,

  -- Failure context for rework injection (S06 slot)
  failure_context text,
  rewrite_suggestion text,

  -- Flags
  flags jsonb not null default '{}'::jsonb,

  -- Evidence & seal
  evidence_bundle jsonb not null default '{}'::jsonb,
  seal_ids jsonb not null default '[]'::jsonb,
  rollback_recall jsonb not null default '{}'::jsonb,

  -- Ownership
  strategy_unit_id uuid,
  contract_id uuid,
  content_decision_refs jsonb not null default '[]'::jsonb,
  cognition_trace_refs jsonb not null default '[]'::jsonb,
  evidence_claim_refs jsonb not null default '[]'::jsonb,

  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  -- Constraint: one SubStudio can only have one active task
  unique (tenant_id, sub_studio_id)
);

create index if not exists idx_substudio_exec_task_sub_studio
  on artifactos.substudio_execution_task (sub_studio_id, pipeline_status);

create index if not exists idx_substudio_exec_task_artifact
  on artifactos.substudio_execution_task (artifact_id);

create index if not exists idx_substudio_exec_task_state_combo
  on artifactos.substudio_execution_task (pipeline_status, quality_status, publish_status);

-- State combo white‑list: only legal combos can be written
create or replace function artifactos.fn_guard_valid_state_combo()
returns trigger language plpgsql as $$
declare
  combo text;
begin
  combo := new.pipeline_status || ' x ' || new.quality_status || ' x ' || new.publish_status;

  -- Normal progression combos
  if new.pipeline_status = 'pending' and new.quality_status = 'pending' and new.publish_status = 'pending' then return new; end if;
  if new.pipeline_status = 'contracting' and new.quality_status = 'pending' and new.publish_status = 'pending' then return new; end if;
  if new.pipeline_status = 'drafting' and new.quality_status = 'pending' and new.publish_status = 'pending' then return new; end if;
  if new.pipeline_status = 'reviewing' and new.quality_status in ('structure_checking','structure_passed','es_checking','es_passed','ses_checking','ses_passed','ses_warned','strategy_decision','passed','sample_review','rework','waiting_human','stored') and new.publish_status = 'pending' then return new; end if;
  if new.pipeline_status = 'approved' and new.quality_status = 'passed' and new.publish_status in ('pending','scheduled') then return new; end if;
  if new.pipeline_status = 'publishing' and new.quality_status = 'passed' and new.publish_status in ('scheduled','publishing','published','failed') then return new; end if;
  if new.pipeline_status = 'published' and new.quality_status = 'passed' and new.publish_status = 'published' then return new; end if;
  if new.pipeline_status = 'collecting' and new.quality_status = 'passed' and new.publish_status = 'published' then return new; end if;
  if new.pipeline_status = 'completed' and new.quality_status = 'passed' and new.publish_status = 'published' then return new; end if;

  -- Exception combos
  if new.pipeline_status = 'frozen' then return new; end if;
  if new.pipeline_status = 'waiting_human' then return new; end if;
  if new.pipeline_status = 'stored' and new.publish_status in ('skipped','pending') then return new; end if;
  if new.pipeline_status = 'draft_only' then return new; end if;
  if new.pipeline_status = 'not_writing' then return new; end if;
  if new.pipeline_status = 'abandoned' then return new; end if;
  if new.pipeline_status in ('published','collecting','completed') and new.quality_status = 'passed' and new.publish_status = 'recalled' then return new; end if;

  raise exception 'invalid state combo: %', combo;
end $$;

create trigger trg_valid_state_combo
before insert or update on artifactos.substudio_execution_task
for each row execute function artifactos.fn_guard_valid_state_combo();

commit;