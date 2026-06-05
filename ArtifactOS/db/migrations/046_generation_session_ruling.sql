-- L3-67: Strategy ruling columns on generation_session
-- Adds ruling_action/reason/evidence for QualityGate strategy ruling output.
-- Also extends status enum with strategy-driven states.

begin;

-- 1. Add ruling columns
alter table artifactos.generation_session
  add column if not exists ruling_action text,
  add column if not exists ruling_reason text,
  add column if not exists ruling_evidence jsonb not null default '{}'::jsonb;

-- 2. Extend status check to include strategy-driven states
alter table artifactos.generation_session
  drop constraint if exists generation_session_status_check;

alter table artifactos.generation_session
  add constraint generation_session_status_check
  check (status in (
    'created',
    'outlining',
    'generating',
    'qualifying',
    'selecting',
    'completed',
    'failed',
    'abandoned',
    -- L3-67: strategy ruling states
    'rewrite_exhausted',      -- all rewrite attempts exhausted
    'approved_for_publish',   -- auto_publish ruling
    'pending_sample_review',  -- sample_review ruling
    'stored_draft',           -- store_draft ruling
    'downgraded',             -- downgrade ruling
    'wait_human',             -- wait_human ruling
    'frozen'                  -- freeze_and_downgrade ruling
  ));

commit;
