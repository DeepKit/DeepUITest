-- ArtifactOS: Topic Funnel — event_signal + topic_score tables
-- Creates the data layer for docs/08 选题漏斗 (Topic Funnel) scoring engine.
-- Layer 1: event_signal (7 signal types from §3.1)
-- Layer 2: topic_score (4-dimension basic + 10-dimension strategy matrix from §4.1/§4.5)

begin;

-- ---------------------------------------------------------------------------
-- Layer 1: Event Signal
-- ---------------------------------------------------------------------------
create table if not exists artifactos.event_signal (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  signal_type text not null check (signal_type in (
    'trending', 'anomaly', 'theory', 'evergreen',
    'viral_hit', 'material', 'falsification'
  )),
  source text not null default 'manual',
  title text not null,
  description text not null default '',
  metadata_json jsonb not null default '{}'::jsonb,

  captured_at timestamptz not null default now(),
  expires_at timestamptz null,
  signal_status text not null default 'captured' check (signal_status in (
    'captured', 'scored', 'selected', 'archived', 'expired'
  )),

  -- Optional link to strategy unit for evaluation context
  strategy_unit_id uuid null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_event_signal_type on artifactos.event_signal (signal_type);
create index idx_event_signal_status on artifactos.event_signal (signal_status);
create index idx_event_signal_captured on artifactos.event_signal (captured_at desc);

comment on table artifactos.event_signal is
  'Layer 1 signal capture for the topic funnel (docs/08 §3). Seven signal types feed into the scoring engine.';

-- ---------------------------------------------------------------------------
-- Layer 2: Topic Score
-- ---------------------------------------------------------------------------
create table if not exists artifactos.topic_score (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  signal_id uuid not null references artifactos.event_signal(id),
  strategy_unit_id uuid null,

  -- 4-dimension basic scoring (docs/08 §4.1)
  coverage_score double precision not null default 0,   -- 覆盖人群 0-10
  pain_score double precision not null default 0,       -- 痛点强度 0-10
  spread_score double precision not null default 0,     -- 传播属性 0-10
  verified_score double precision not null default 0,   -- 已验证性 0-10
  basic_composite double precision not null default 0,  -- weighted composite

  -- 10-dimension strategy matrix (docs/08 §4.5)
  strategy_fit double precision not null default 0,     -- strategy_unit_fit
  theory_fit double precision not null default 0,
  theory_intervention double precision not null default 0,
  traffic_potential double precision not null default 0,
  theory_level double precision not null default 0,
  readability double precision not null default 0,
  risk_level double precision not null default 0,
  operation_goal_fit double precision not null default 0,
  claim_potential double precision not null default 0,
  research_value double precision not null default 0,
  strategy_composite double precision not null default 0,

  -- Boundary decision (docs/08 §4.6)
  boundary_decision text not null default 'store_candidate' check (boundary_decision in (
    'write_now', 'store_candidate', 'experiment',
    'do_not_write', 'research_question', 'draft_only'
  )),
  decision_reason text not null default '',
  confidence text not null default 'low' check (confidence in ('low', 'medium', 'high')),

  scored_at timestamptz not null default now(),

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (tenant_id, signal_id, strategy_unit_id)
);

create index idx_topic_score_decision on artifactos.topic_score (boundary_decision);
create index idx_topic_score_basic on artifactos.topic_score (basic_composite desc);
create index idx_topic_score_strategy on artifactos.topic_score (strategy_composite desc);

comment on table artifactos.topic_score is
  'Layer 2 scoring result for the topic funnel (docs/08 §4). Stores 4-dimension basic scores + 10-dimension strategy matrix + boundary decision.';

-- Track in migration log
insert into artifactos.schema_migration_log (migration_name, checksum, notes)
values ('043_topic_funnel_signal_score', '', 'event_signal + topic_score tables for topic funnel engine')
on conflict do nothing;

commit;
