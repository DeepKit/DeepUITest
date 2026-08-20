-- L3-69/70/71/72/73: Cognitive governance layer
-- cognition_trace: records AI's judgment trace per artifact (write/not-write/publish/freeze)
-- boundary_decision: decision records for boundary topics
-- publication_seal: tamper-evident seal for published artifacts
-- recall_card: rollback/recall chain for published artifacts
-- cognitive_disturbance_event: trigger for sampling/downgrade/freeze

begin;

-- ── L3-70: Cognition trace ──────────────────────────────────────────
-- Records what the AI knew, predicted, and decided at each stage.
create table if not exists artifactos.cognition_trace (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  artifact_id uuid not null references artifactos.artifact(id),
  artifact_version_id uuid references artifactos.artifact_version(id),

  -- The four states: write / not_write / publish / freeze
  trace_type text not null check (trace_type in (
    'write',       -- AI decided to write this artifact
    'not_write',   -- AI decided NOT to write (boundary topic, insufficient evidence)
    'publish',     -- AI decided to publish (passed all gates)
    'freeze'       -- AI decided to freeze (red line hit, evidence failed)
  )),

  -- What the AI knew at decision time
  context_snapshot jsonb not null default '{}'::jsonb,
  -- {signals: [...], scores: {...}, theory_state: "...", evidence: [...]}

  -- What the AI predicted
  predictions jsonb not null default '{}'::jsonb,
  -- {expected_engagement: 0.7, predicted_quality: 85, risk_flags: [...]}

  -- What the AI decided and why
  decision_rationale text not null default '',

  -- Outcome tracking (filled after publish/skip)
  outcome_status text check (outcome_status in (
    'pending', 'confirmed', 'disproven', 'partial', 'overridden'
  )) default 'pending',
  outcome_evidence jsonb default '{}'::jsonb,

  -- Calibration
  calibration_delta double precision,  -- |prediction - actual|
  consecutive_miss_count integer not null default 0,

  -- Timestamps
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists idx_cognition_trace_artifact
  on artifactos.cognition_trace (artifact_id, trace_type);
create index if not exists idx_cognition_trace_outcome
  on artifactos.cognition_trace (outcome_status);

-- ── L3-71: Boundary decision ────────────────────────────────────────
-- Records decisions about whether to write/draft/publish/reject boundary topics.
create table if not exists artifactos.boundary_decision (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  artifact_id uuid not null references artifactos.artifact(id),
  cognition_trace_id uuid references artifactos.cognition_trace(id),

  -- Decision type
  decision text not null check (decision in (
    'write_freely',       -- no boundary concern, write normally
    'write_cautious',     -- boundary topic but safe to write with care
    'draft_only',         -- write but do NOT publish, save for human review
    'restricted_publish', -- publish with limitations (no theory, simplified)
    'not_write',          -- do not write at all
    'freeze'              -- freeze pending human review
  )),

  -- Why this decision was made
  boundary_factors jsonb not null default '{}'::jsonb,
  -- {topic_sensitivity: 0.8, evidence_strength: 0.3, theory_exposure: "high", ...}

  -- Human override
  overridden_by uuid,
  override_reason text,
  overridden_at timestamptz,

  -- Metadata
  decided_by text not null default 'ai',  -- 'ai' | 'human' | 'auto_rule'
  created_at timestamptz not null default now()
);

create index if not exists idx_boundary_decision_artifact
  on artifactos.boundary_decision (artifact_id, decision);

-- ── L3-72: Publication seal ─────────────────────────────────────────
-- Tamper-evident seal for published artifacts. Once sealed, content hash is immutable.
create table if not exists artifactos.publication_seal (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',

  -- What is sealed
  artifact_id uuid not null references artifactos.artifact(id),
  artifact_version_id uuid not null references artifactos.artifact_version(id),
  publication_package_id uuid references artifactos.publication_package(id),

  -- Seal content
  seal_id text not null unique,  -- human-readable: "seal_20260605_001"
  content_hash text not null,    -- SHA-256 of (title + body + metadata)
  seal_evidence jsonb not null default '{}'::jsonb,
  -- {quality_snapshot_id, gate_results, strategy_ruling, cognition_trace_id, ...}

  -- Seal status
  sealed_at timestamptz not null default now(),
  sealed_by text not null default 'system',
  seal_status text not null default 'active' check (seal_status in (
    'active',       -- sealed and in effect
    'recalled',     -- recalled (content removed from platform)
    'superseded',   -- replaced by a new seal
    'broken'        -- seal integrity violated (emergency)
  )),

  -- Recall chain
  recalled_at timestamptz,
  recall_reason text,
  superseded_by uuid references artifactos.publication_seal(id)
);

create index if not exists idx_pub_seal_artifact
  on artifactos.publication_seal (artifact_id, seal_status);
create index if not exists idx_pub_seal_version
  on artifactos.publication_seal (artifact_version_id);

-- ── L3-72: Recall card ──────────────────────────────────────────────
-- Records each recall/rollback action with full chain traceability.
-- Drop legacy recall_card (created in early migration with different schema)
drop table if exists artifactos.recall_card cascade;
create table artifactos.recall_card (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',

  -- What is being recalled
  seal_id uuid not null references artifactos.publication_seal(id),
  artifact_id uuid not null references artifactos.artifact(id),

  -- Recall details
  recall_type text not null check (recall_type in (
    'platform_delete',     -- delete from platform
    'platform_draftify',   -- convert to draft (if supported)
    'platform_edit',       -- edit published content
    'artifact_freeze',     -- freeze in ArtifactOS
    'full_rollback'        -- rollback everything
  )),

  recall_reason text not null,
  initiated_by text not null default 'system',  -- 'system' | 'human' | 'auto_rule'
  recall_status text not null default 'pending' check (recall_status in (
    'pending', 'executing', 'completed', 'failed', 'canceled'
  )),

  -- Evidence of recall
  evidence jsonb default '{}'::jsonb,
  -- {screenshot_before: "...", screenshot_after: "...", platform_response: "..."}

  -- Chain: which recall triggered which subsequent action
  parent_recall_id uuid references artifactos.recall_card(id),

  -- Timestamps
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists idx_recall_card_seal
  on artifactos.recall_card (seal_id, recall_status);
create index if not exists idx_recall_card_artifact
  on artifactos.recall_card (artifact_id);

-- ── L3-69: Cognitive disturbance event ──────────────────────────────
-- Triggers for sampling review, downgrade, and red-line freeze.
create table if not exists artifactos.cognitive_disturbance_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',

  -- What triggered the disturbance
  artifact_id uuid references artifactos.artifact(id),
  cognition_trace_id uuid references artifactos.cognition_trace(id),

  -- Disturbance type
  disturbance_type text not null check (disturbance_type in (
    'consecutive_miss',        -- AI predictions consistently wrong
    'calibration_drift',       -- calibration delta exceeds threshold
    'evidence_contradiction',  -- new evidence contradicts prior claims
    'red_line_violation',      -- content crosses a red line
    'platform_negative',       -- platform signals negative (flagged, removed)
    'human_override',          -- human corrected AI decision
    'quality_regression'       -- quality scores dropped significantly
  )),

  severity text not null check (severity in ('low', 'medium', 'high', 'critical')),
  details jsonb not null default '{}'::jsonb,

  -- Response action
  response_action text check (response_action in (
    'increase_sampling',    -- increase sample review rate
    'downgrade_trust',      -- reduce AI autonomy level
    'freeze_pending',       -- freeze all pending publishes
    'escalate_human',       -- escalate to human review
    'auto_correct'          -- AI self-corrects based on feedback
  )),
  response_status text not null default 'pending' check (response_status in (
    'pending', 'executed', 'overridden', 'expired'
  )),

  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists idx_cog_disturbance_type
  on artifactos.cognitive_disturbance_event (disturbance_type, severity);
create index if not exists idx_cog_disturbance_artifact
  on artifactos.cognitive_disturbance_event (artifact_id, response_status);

commit;
