-- ArtifactOS ApprovalRecord + SignalEvent + SignalInterpretation + CandidateProposal Phase 1A
-- Target: artifactos_test first, then progee_db.artifactos after review.

begin;

-- 1. ApprovalRecord — human or delegated approval of publish
create table if not exists artifactos.approval_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  publication_package_id uuid references artifactos.publication_package(id),
  artifact_version_id uuid references artifactos.artifact_version(id),
  quality_snapshot_id uuid references artifactos.quality_snapshot(id),
  approver_type text not null check (approver_type in ('human','secretary','delegated')),
  approval_action text not null check (approval_action in ('approve','reject','hold','request_revision')),
  delegation_policy_id uuid references artifactos.delegation_policy(id),
  rationale text not null,
  approval_status text not null default 'pending' check (approval_status in ('pending','approved','rejected','superseded')),
  evidence_refs jsonb not null default '[]'::jsonb,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_approval_record_package
  on artifactos.approval_record (publication_package_id, approval_status);

-- 2. SignalEvent — raw platform or human feedback fact
create table if not exists artifactos.signal_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  publication_id uuid,
  artifact_id uuid references artifactos.artifact(id),
  signal_type text not null check (signal_type in ('views','likes','comments','shares','saves','follows','question','complaint','manual_feedback','unknown')),
  channel text,
  raw_value numeric(18,6),
  raw_text text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_signal_event_artifact
  on artifactos.signal_event (artifact_id, signal_type, occurred_at);

-- 3. SignalInterpretation — AI hypothesis about what the signal means
create table if not exists artifactos.signal_interpretation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  signal_event_id uuid not null references artifactos.signal_event(id),
  interpretation_type text not null,
  hypothesis text not null,
  confidence numeric(5,4) check (confidence >= 0 and confidence <= 1),
  counter_evidence text,
  misread_risk_score numeric(5,4) check (misread_risk_score >= 0 and misread_risk_score <= 1),
  misread_risk_detail text,
  resonance_type text check (resonance_type in ('aligned','distorted','surface','negative')),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_signal_interpretation_signal
  on artifactos.signal_interpretation (signal_event_id);

-- 4. AttributionDecision — what action to take based on signal
create table if not exists artifactos.attribution_decision (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  signal_interpretation_id uuid not null references artifactos.signal_interpretation(id),
  decision_type text not null,
  target_type text,
  target_id uuid,
  action text not null,
  evidence_refs jsonb not null default '[]'::jsonb,
  status text not null default 'open' check (status in ('open','applied','rejected','superseded')),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 5. CandidateProposal — envelope for any proposed change
create table if not exists artifactos.candidate_proposal (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  proposal_code text not null,
  proposal_type text not null check (proposal_type in (
    'opportunity','plan_change','boundary_change','strategy_change',
    'backfeed','quality_policy_change','calibration_example','observe_only'
  )),
  title text not null,
  summary text not null,
  rationale text not null,
  origin_type text not null,
  origin_id uuid,
  severity text not null default 'normal' check (severity in ('low','normal','high','redline')),
  scope_refs jsonb not null default '[]'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  risk_assessment jsonb not null default '{}'::jsonb,
  recommended_meeting text check (recommended_meeting in ('day','week','month','quarter','half_year','year')),
  status text not null default 'draft' check (status in ('draft','confirmed','approved','applied','rejected','deferred','superseded')),
  decided_by_type text,
  decided_by_id uuid,
  applied_output_type text,
  applied_output_id uuid,
  requires_human_decision boolean not null default true,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, proposal_code)
);

create index if not exists idx_candidate_proposal_type
  on artifactos.candidate_proposal (proposal_type, status);

create index if not exists idx_candidate_proposal_origin
  on artifactos.candidate_proposal (origin_type, origin_id);

commit;