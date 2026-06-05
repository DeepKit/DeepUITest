-- L4-76: Calibration delta ledger
-- Dedicated ledger for tracking prediction vs actual over time.
-- Links cognition_trace predictions to performance_observation actuals.

begin;

-- Calibration ledger entry: one row per prediction-actual comparison
create table if not exists artifactos.calibration_ledger (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',

  -- What is being calibrated
  artifact_id uuid not null references artifactos.artifact(id),
  cognition_trace_id uuid references artifactos.cognition_trace(id),
  performance_observation_id uuid references artifactos.performance_observation(id),

  -- Dimension of calibration
  delta_dimension text not null check (delta_dimension in (
    'reading',             -- view count prediction vs actual
    'interaction',         -- engagement rate prediction vs actual
    'conversion',          -- follow/subscribe rate prediction vs actual
    'negative_feedback',   -- complaint/report rate prediction vs actual
    'theory_risk',         -- theory exposure risk prediction vs actual
    'overall'              -- aggregate quality prediction vs actual
  )),

  -- The comparison
  expected_value double precision not null,
  actual_value double precision not null,
  calibration_delta double precision not null,  -- |expected - actual|

  -- Threshold breach check
  delta_threshold double precision not null default 0.25,
  is_miss boolean not null,                      -- delta > threshold
  severity text not null default 'low' check (severity in ('low', 'medium', 'high', 'critical')),

  -- Running count (how many consecutive misses for this strategy unit)
  consecutive_miss_count integer not null default 0,

  -- Environment context
  environment_noise_flag boolean not null default false,
  platform_anomaly_flag boolean not null default false,

  -- Resolution
  resolution_status text not null default 'open' check (resolution_status in (
    'open',               -- not yet reviewed
    'acknowledged',       -- seen by system/human
    'disturbance_filed',  -- cognitive disturbance event created
    'proposal_generated', -- strategy change proposal created
    'dismissed',          -- noise or false alarm
    'resolved'            -- addressed and closed
  )),

  -- Timestamps
  observed_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_cal_ledger_artifact
  on artifactos.calibration_ledger (artifact_id, delta_dimension, observed_at desc);
create index if not exists idx_cal_ledger_miss
  on artifactos.calibration_ledger (is_miss, severity, resolution_status);

-- Strategy-change-proposal auto-generation support
-- Triggered when consecutive_miss_count >= threshold
create table if not exists artifactos.strategy_change_proposal (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',

  -- What triggered the proposal
  trigger_type text not null check (trigger_type in (
    'consecutive_calibration_miss',
    'rewrite_exhaustion',
    'evidence_contradiction',
    'algorithm_noise_overload',
    'quality_regression',
    'human_override'
  )),

  -- References to triggering entities
  calibration_ledger_ids jsonb not null default '[]'::jsonb,
  disturbance_event_ids jsonb not null default '[]'::jsonb,
  strategy_unit_id uuid,

  -- The proposal
  proposal_title text not null,
  proposal_body text not null,
  proposed_changes jsonb not null default '{}'::jsonb,

  -- Risk assessment
  risk_level text not null default 'medium' check (risk_level in ('low', 'medium', 'high', 'redline')),
  auto_tune_eligible boolean not null default false,
  requires_human_confirmation boolean not null default true,

  -- Outcome
  proposal_status text not null default 'pending' check (proposal_status in (
    'pending', 'approved', 'rejected', 'expired', 'superseded'
  )),
  decided_by text,         -- 'human' | 'auto_approved'
  decided_at timestamptz,
  decision_rationale text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_scp_status
  on artifactos.strategy_change_proposal (proposal_status, risk_level, created_at desc);

-- Auto-touch updated_at
create or replace function artifactos.fn_touch_strategy_change_proposal()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_touch_strategy_change_proposal on artifactos.strategy_change_proposal;
create trigger trg_touch_strategy_change_proposal
  before update on artifactos.strategy_change_proposal
  for each row execute function artifactos.fn_touch_strategy_change_proposal();

commit;
