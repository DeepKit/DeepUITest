-- ArtifactOS: L1 Candidate/Proposal Chain + Publication Chain
-- Batch E: 14 tables — candidate sub-tables, opportunity, plan/boundary change
-- Batch D continued: revision_session, batch_action_proposal, publication attempts

begin;

-- ============================================================
-- Candidate Proposal Sub-Tables (7 tables)
-- ============================================================

-- candidate_source_ref
create table if not exists artifactos.candidate_source_ref (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  candidate_proposal_id uuid not null references artifactos.candidate_proposal(id),
  source_type text not null check (source_type in (
    'signal_event','signal_interpretation','field_state_snapshot',
    'quality_run','quality_snapshot','meeting_record','recall_card',
    'human_review_choice','daily_report','shadow_run_observation',
    'external_ref'
  )),
  source_ref_id uuid null,
  source_role text not null check (source_role in (
    'trigger','supporting','context','merged_source'
  )),
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- candidate_evidence_ref
create table if not exists artifactos.candidate_evidence_ref (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  candidate_proposal_id uuid not null references artifactos.candidate_proposal(id),
  evidence_type text not null check (evidence_type in (
    'signal_event','signal_interpretation','field_state_snapshot',
    'quality_run','quality_snapshot','meeting_decision',
    'human_review_choice','artifact_version','publication_attempt',
    'investment_thesis_snapshot','investment_outcome_review',
    'external_ref'
  )),
  evidence_ref_id uuid null,
  evidence_role text not null check (evidence_role in (
    'supporting','contradicting','risk','baseline','context'
  )),
  confidence numeric(5,4) null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- candidate_scope_ref
create table if not exists artifactos.candidate_scope_ref (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  candidate_proposal_id uuid not null references artifactos.candidate_proposal(id),
  scope_type text not null check (scope_type in (
    'source_pack','lighthouse_strategy_objective','case_record',
    'case_objective','purpose_portfolio','purpose_policy_binding',
    'quality_policy','artifact','publication_package','field_state',
    'investment_target','investment_thesis_snapshot',
    'account','platform','strategy_unit'
  )),
  scope_ref_id uuid not null,
  scope_role text not null check (scope_role in (
    'primary_target','affected_object','blocked_object','reference_only'
  )),
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- candidate_risk_assessment
create table if not exists artifactos.candidate_risk_assessment (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  candidate_proposal_id uuid not null references artifactos.candidate_proposal(id),
  risk_type text not null check (risk_type in (
    'source_boundary','lighthouse_positioning','legal_ethics',
    'platform_policy','misread_amplification','brand_voice',
    'publication_safety','tenant_security'
  )),
  risk_level text not null check (risk_level in ('low','medium','high','redline')),
  mitigation_plan text null,
  requires_human_review boolean not null default false,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- candidate_merge_link
create table if not exists artifactos.candidate_merge_link (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  survivor_candidate_id uuid not null references artifactos.candidate_proposal(id),
  merged_candidate_id uuid not null references artifactos.candidate_proposal(id),
  merge_reason text not null,
  merged_by uuid not null,
  merged_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, survivor_candidate_id, merged_candidate_id)
);

-- candidate_decision
create table if not exists artifactos.candidate_decision (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  candidate_proposal_id uuid not null references artifactos.candidate_proposal(id),
  decision_type text not null check (decision_type in (
    'approve','reject','defer','merge','request_revision','observe_only'
  )),
  decided_by_type text not null check (decided_by_type in (
    'human','meeting','delegated_amy'
  )),
  decided_by_ref_id uuid null,
  decision_reason text not null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- candidate_application
create table if not exists artifactos.candidate_application (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  candidate_proposal_id uuid not null references artifactos.candidate_proposal(id),
  candidate_decision_id uuid not null references artifactos.candidate_decision(id),
  output_type text not null check (output_type in (
    'opportunity_candidate',
    'plan_change_proposal',
    'boundary_change_proposal',
    'strategy_change_proposal',
    'quality_policy_version',
    'purpose_portfolio_version',
    'purpose_policy_binding_version',
    'resource_allocation_decision',
    'source_backfeed_candidate',
    'calibration_example',
    'retained_pattern'
  )),
  output_ref_id uuid not null,
  application_status text not null check (application_status in (
    'pending','applied','failed','rolled_back','superseded'
  )),
  applied_at timestamptz null,
  rollback_ref_id uuid null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- ============================================================
-- Opportunity + Plan/Boundary Change (4 tables)
-- ============================================================

-- opportunity_candidate
create table if not exists artifactos.opportunity_candidate (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  candidate_proposal_id uuid null references artifactos.candidate_proposal(id),
  opportunity_type text not null,
  title text not null,
  description text null,
  source_type text not null,
  source_ref_id uuid null,
  suggested_action text null,
  recommended_meeting_type text null,
  affected_case_id uuid null references artifactos.case_record(id),
  status text not null check (status in (
    'new','screening','promoted_to_proposal','rejected','archived'
  )),
  evidence_refs jsonb not null default '[]'::jsonb,
  risk_notes text null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- plan_change_proposal
create table if not exists artifactos.plan_change_proposal (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  candidate_proposal_id uuid null references artifactos.candidate_proposal(id),
  proposal_code text not null,
  proposal_type text not null check (proposal_type in (
    'add_plan','drop_plan','rebalance_plan','change_delegation','change_boundary'
  )),
  status text not null check (status in (
    'draft','waiting_meeting','approved','applied','rejected','deferred','superseded'
  )),
  opportunity_candidate_id uuid null references artifactos.opportunity_candidate(id),
  target_case_id uuid not null references artifactos.case_record(id),
  target_field_path text not null,
  recommended_meeting_type text not null,
  required_meeting_type text null,
  before_value jsonb null,
  proposed_value jsonb not null,
  rationale text not null,
  evidence_refs jsonb not null default '[]'::jsonb,
  expected_impact jsonb not null default '{}'::jsonb,
  rollback_plan jsonb not null default '{}'::jsonb,
  decided_by_meeting_record_id uuid null references artifactos.meeting_record(id),
  decided_at timestamptz null,
  applied_at timestamptz null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, proposal_code)
);

-- plan_change_log
create table if not exists artifactos.plan_change_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  proposal_id uuid not null references artifactos.plan_change_proposal(id),
  target_case_id uuid not null references artifactos.case_record(id),
  meeting_record_id uuid not null references artifactos.meeting_record(id),
  decision text not null check (decision in (
    'approved','rejected','deferred','superseded'
  )),
  applied_snapshot_id uuid null references artifactos.case_snapshot(id),
  decision_narrative text not null,
  affected_field_paths text[] not null default '{}',
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- boundary_change_proposal
create table if not exists artifactos.boundary_change_proposal (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  candidate_proposal_id uuid null references artifactos.candidate_proposal(id),
  target_case_id uuid not null references artifactos.case_record(id),
  boundary_type text not null,
  status text not null check (status in (
    'draft','waiting_human','approved','rejected','applied','superseded'
  )),
  current_boundary jsonb not null,
  proposed_boundary jsonb not null,
  reason text not null,
  requires_year_case_reopen boolean not null default false,
  decision_record_id uuid null references artifactos.meeting_decision_record(id),
  applied_snapshot_id uuid null references artifactos.case_snapshot(id),
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- ============================================================
-- Publication Chain (3 tables)
-- ============================================================

-- revision_session
create table if not exists artifactos.revision_session (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  studio_id uuid null references artifactos.studio(id),
  artifact_plan_set_id uuid null references artifactos.artifact_plan_set(id),
  session_scope text not null,
  status text not null check (status in ('open','applying','completed','canceled')),
  instruction_summary text null,
  affected_artifact_ids uuid[] not null default '{}',
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- batch_action_proposal
create table if not exists artifactos.batch_action_proposal (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  proposal_code text not null,
  source_work_card_id uuid null references artifactos.work_card(id),
  source_panel_id uuid null references artifactos.prepared_action_panel(id),
  source_choice_id uuid null references artifactos.human_review_choice(id),
  studio_id uuid null references artifactos.studio(id),
  artifact_plan_set_id uuid null references artifactos.artifact_plan_set(id),
  proposal_type text not null check (proposal_type in (
    'batch_approve','batch_rework','batch_hold','batch_freeze',
    'batch_publish_package','batch_exclude','batch_calibration'
  )),
  status text not null check (status in (
    'draft','previewed','waiting_human','approved','applied','rejected','canceled','expired'
  )),
  affected_artifact_ids uuid[] not null default '{}',
  affected_part_refs jsonb not null default '[]'::jsonb,
  impact_preview jsonb not null default '{}'::jsonb,
  exclusions jsonb not null default '[]'::jsonb,
  high_risk_items jsonb not null default '[]'::jsonb,
  resulting_revision_session_id uuid null,
  resulting_approval_record_ids uuid[] not null default '{}',
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, proposal_code)
);

-- simulated_publication_attempt
create table if not exists artifactos.simulated_publication_attempt (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  shadow_run_day_id uuid not null,
  publication_package_id uuid not null references artifactos.publication_package(id),
  target_platform_id uuid not null,
  status text not null check (status in (
    'prepared','preflight_passed','preflight_failed','blocked','canceled'
  )),
  reached_step text not null,
  blocked_reason text null,
  evidence_refs jsonb not null default '[]'::jsonb,
  simulated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- publication_attempt
create table if not exists artifactos.publication_attempt (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  publication_package_id uuid not null references artifactos.publication_package(id),
  real_publish_gate_run_id uuid not null references artifactos.real_publish_gate_run(id),
  attempt_no integer not null,
  idempotency_key text not null,
  submit_status text not null check (submit_status in (
    'prepared','submitting','submitted','verified','failed','unknown','human_takeover','rolled_back'
  )),
  media_publish_job_id uuid null,
  submitted_url text null,
  verification_result jsonb not null default '{}'::jsonb,
  error_payload jsonb not null default '{}'::jsonb,
  started_at timestamptz null,
  finished_at timestamptz null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, publication_package_id, attempt_no),
  unique (tenant_id, idempotency_key)
);

-- ============================================================
-- Indexes
-- ============================================================
create index if not exists idx_candidate_source_ref_proposal
  on artifactos.candidate_source_ref (tenant_id, candidate_proposal_id);
create index if not exists idx_candidate_evidence_ref_proposal
  on artifactos.candidate_evidence_ref (tenant_id, candidate_proposal_id);
create index if not exists idx_candidate_scope_ref_proposal
  on artifactos.candidate_scope_ref (tenant_id, candidate_proposal_id);
create index if not exists idx_candidate_decision_proposal
  on artifactos.candidate_decision (tenant_id, candidate_proposal_id);
create index if not exists idx_opportunity_candidate_status
  on artifactos.opportunity_candidate (tenant_id, status);
create index if not exists idx_plan_change_proposal_case
  on artifactos.plan_change_proposal (tenant_id, target_case_id);
create index if not exists idx_boundary_change_proposal_case
  on artifactos.boundary_change_proposal (tenant_id, target_case_id);
create index if not exists idx_publication_attempt_package
  on artifactos.publication_attempt (tenant_id, publication_package_id);
create index if not exists idx_batch_action_proposal_status
  on artifactos.batch_action_proposal (tenant_id, status);

commit;
