-- ArtifactOS: Strategy Governance + Same-Day Exception Tables
-- Creates strategy_unit_maturity, maturity_change_log, same_day_exception_proposal,
-- fast_gate_result from docs/24 §5D.9-5D.10.

begin;

-- 5D.9 same_day_exception_proposal
create table if not exists artifactos.same_day_exception_proposal (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  source_signal_id uuid null,
  opportunity_reason text not null,
  window_expires_at timestamptz not null,
  status text not null check (status in (
    'detected','proposed','fast_gate_checking','waiting_human',
    'approved','published','stored','rejected','expired'
  )),
  risk_level text not null check (risk_level in (
    'low','normal','high','critical'
  )),
  strategy_unit_maturity_id uuid null,
  human_override boolean not null default false,
  approval_record_id uuid null references artifactos.approval_record(id),
  publication_package_id uuid null references artifactos.publication_package(id),
  rationale text not null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 5D.9 fast_gate_result
create table if not exists artifactos.fast_gate_result (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  same_day_exception_proposal_id uuid not null references artifactos.same_day_exception_proposal(id),
  redline_status text not null,
  fact_risk_status text not null,
  source_boundary_status text not null,
  platform_fit_status text not null,
  package_status text not null,
  gate_result text not null check (gate_result in (
    'pass','fail','freeze','needs_human'
  )),
  evidence_refs jsonb not null default '[]'::jsonb,
  checked_at timestamptz not null default now(),

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 5D.10 strategy_unit_maturity
create table if not exists artifactos.strategy_unit_maturity (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  strategy_unit_id uuid not null,
  case_constraint_id uuid not null references artifactos.case_record(id),
  maturity_level text not null check (maturity_level in (
    'M0_candidate','M1_trial','M2_stable_production',
    'M3_mature_publishing','M4_mature_operating'
  )),
  status text not null check (status in (
    'active','degraded','frozen','retired'
  )),
  evidence_refs jsonb not null default '[]'::jsonb,
  last_evaluated_at timestamptz null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  unique (tenant_id, strategy_unit_id, case_constraint_id)
);

-- 5D.10 maturity_change_log
create table if not exists artifactos.maturity_change_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  strategy_unit_maturity_id uuid not null references artifactos.strategy_unit_maturity(id),
  from_level text null,
  to_level text not null,
  change_action text not null check (change_action in (
    'suggest_upgrade','approve_upgrade','auto_downgrade','freeze','unfreeze','retire'
  )),
  rationale text not null,
  evidence_refs jsonb not null default '[]'::jsonb,
  decision_ref_type text null,
  decision_ref_id uuid null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- Indexes
create index if not exists idx_strategy_unit_maturity_unit
  on artifactos.strategy_unit_maturity (tenant_id, strategy_unit_id);

create index if not exists idx_maturity_change_log_mat
  on artifactos.maturity_change_log (tenant_id, strategy_unit_maturity_id);

create index if not exists idx_fast_gate_proposal
  on artifactos.fast_gate_result (tenant_id, same_day_exception_proposal_id);

create index if not exists idx_same_day_exception_status
  on artifactos.same_day_exception_proposal (tenant_id, status, window_expires_at);

commit;
