-- ArtifactOS: Signal Event Layer — Missing Governance Tables
-- Creates 11 tables from docs/24 §8B + §9 that don't yet exist.
-- Existing tables (signal_event, signal_interpretation, attribution_decision,
-- event_ledger, field_state_snapshot) were created by earlier migrations and
-- may need column alignment in a future migration.

begin;

-- 8B.3 signal_interpretation_event (M2M: interpretation ↔ signal_event)
create table if not exists artifactos.signal_interpretation_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  signal_interpretation_id uuid not null references artifactos.signal_interpretation(id),
  signal_event_id uuid not null references artifactos.signal_event(id),
  relation_role text not null default 'supporting',
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, signal_interpretation_id, signal_event_id, relation_role)
);

-- 8B.5 field_state_run (computation run: signals → field state)
create table if not exists artifactos.field_state_run (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  run_scope text not null check (run_scope in (
    'field','platform','account','lighthouse_objective','case_objective','purpose_portfolio'
  )),
  scope_ref_id uuid null,
  model_ref text null,
  policy_ref text null,
  input_summary jsonb not null default '{}'::jsonb,
  run_status text not null check (run_status in (
    'pending','running','completed','failed','canceled'
  )),
  started_at timestamptz null,
  completed_at timestamptz null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 8B.7 field_state_current (pointer to latest snapshot)
create table if not exists artifactos.field_state_current (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  scope_type text not null,
  scope_ref_id uuid null,
  platform_id uuid null,
  account_id uuid null,
  selector_key text not null,
  current_snapshot_id uuid not null references artifactos.field_state_snapshot(id),
  updated_reason text not null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  unique (tenant_id, selector_key)
);

-- 8B.8 field_state_signal_event (snapshot ↔ signal_event M2M)
create table if not exists artifactos.field_state_signal_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  field_state_snapshot_id uuid not null references artifactos.field_state_snapshot(id),
  signal_event_id uuid not null references artifactos.signal_event(id),
  contribution_role text not null check (contribution_role in (
    'supporting','contradicting','noise','baseline','outlier'
  )),
  weight numeric(8,4) null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, field_state_snapshot_id, signal_event_id, contribution_role)
);

-- 8B.8 field_state_signal_interpretation (snapshot ↔ interpretation M2M)
create table if not exists artifactos.field_state_signal_interpretation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  field_state_snapshot_id uuid not null references artifactos.field_state_snapshot(id),
  signal_interpretation_id uuid not null references artifactos.signal_interpretation(id),
  interpretation_role text not null check (interpretation_role in (
    'accepted','competing','rejected','uncertain'
  )),
  weight numeric(8,4) null,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, field_state_snapshot_id, signal_interpretation_id, interpretation_role)
);

-- 8B.9 field_state_alert
create table if not exists artifactos.field_state_alert (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  field_state_snapshot_id uuid not null references artifactos.field_state_snapshot(id),

  alert_code text not null check (alert_code in (
    'algorithm_noise_overload',
    'misread_risk_spike',
    'resonance_drop',
    'fatigue_spike',
    'platform_behavior_shift'
  )),
  alert_light text not null check (alert_light in ('yellow','gray','red')),
  blocks_auto_adjustment boolean not null default true,
  requires_human_review boolean not null default false,
  rationale text not null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 8B.9 field_state_metric_registry
create table if not exists artifactos.field_state_metric_registry (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  metric_code text not null,
  metric_name_zh text not null,
  metric_name_en text not null,
  metric_family text not null,
  value_type text not null check (value_type in ('numeric','boolean','category','json')),
  description text null,
  status text not null check (status in ('active','draft','deprecated','disabled')),
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, metric_code)
);

-- 9.2 recall_card
create table if not exists artifactos.recall_card (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  meeting_record_id uuid null references artifactos.meeting_record(id),
  target_case_id uuid null references artifactos.case_record(id),
  recall_reason text not null,
  source_refs jsonb not null default '[]'::jsonb,
  relevance_score numeric(8,4) null,
  lifecycle_state text not null default 'candidate',
  suggested_action text null,
  adoption_status text not null default 'not_decided',

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 9.3 operation_context_pack
create table if not exists artifactos.operation_context_pack (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  purpose text not null,
  target_type text not null,
  target_id uuid not null,
  source_refs jsonb not null default '[]'::jsonb,
  included_items jsonb not null default '[]'::jsonb,
  excluded_items jsonb not null default '[]'::jsonb,
  trimming_policy jsonb not null default '{}'::jsonb,
  token_budget integer null,

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 9.4 operation_context_item
create table if not exists artifactos.operation_context_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,

  operation_context_pack_id uuid not null references artifactos.operation_context_pack(id),
  item_type text not null check (item_type in (
    'event_ledger','recall_card','retained_pattern','source_snapshot',
    'calibration_example','legacy_snapshot','manual_note'
  )),
  item_ref_id uuid null,
  item_ref_payload jsonb not null default '{}'::jsonb,
  lifecycle_state text not null check (lifecycle_state in (
    'active','muted','deprecated','archived','candidate','exception_included'
  )),
  retention_score numeric(8,4) null,
  inclusion_reason text not null,
  recall_card_id uuid null references artifactos.recall_card(id),
  override_reason text null,
  included_at timestamptz not null default now(),

  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  check (
    lifecycle_state <> 'exception_included'
    or (override_reason is not null and recall_card_id is not null)
  )
);

-- EventLedger append-only guard trigger
create or replace function artifactos.fn_guard_event_ledger_append_only()
returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    raise exception 'event_ledger rows cannot be updated — corrections must be expressed as new events';
  elsif tg_op = 'DELETE' then
    if new.metadata->>'deletion_reason' is null
       or new.metadata->>'deletion_authorized_by' is null then
      raise exception 'event_ledger is append-only — physical deletion only permitted with deletion_reason and deletion_authorized_by in metadata';
    end if;
  end if;
  return null;
end $$;

drop trigger if exists trg_event_ledger_append_only
  on artifactos.event_ledger;
create trigger trg_event_ledger_append_only
  before update or delete on artifactos.event_ledger
  for each row execute function artifactos.fn_guard_event_ledger_append_only();

-- Indexes for governance queries
create index if not exists idx_field_state_signal_event
  on artifactos.field_state_signal_event (tenant_id, signal_event_id, contribution_role);

create index if not exists idx_event_ledger_aggregate
  on artifactos.event_ledger (aggregate_type, aggregate_id);

create index if not exists idx_event_ledger_payload_gin
  on artifactos.event_ledger using gin (payload);

create index if not exists idx_recall_card_target_case
  on artifactos.recall_card (tenant_id, target_case_id);

create index if not exists idx_field_state_current_selector
  on artifactos.field_state_current (tenant_id, scope_type, selector_key);

commit;
