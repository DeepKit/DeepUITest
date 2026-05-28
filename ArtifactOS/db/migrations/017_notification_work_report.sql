-- ArtifactOS notification_channel + work_report + daily_report Phase 1A draft
-- Target: artifactos_test first, then artifactos production after review.

begin;

-- 1. NotificationChannel — abstract channel (Phase 1A: Weixin only)
create table if not exists artifactos.notification_channel (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  channel_code text not null,
  channel_type text not null check (channel_type in ('weixin')),
  channel_name text not null,
  owner_user_id uuid not null default '00000000-0000-0000-0000-000000000001',
  status text not null default 'binding' check (status in ('binding','active','paused','failed','revoked','archived')),
  capability_profile jsonb not null default '{}'::jsonb,
  last_seen_at timestamptz,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, channel_code)
);

-- 2. AmyWeixinChannel — Weixin work report binding
create table if not exists artifactos.amy_weixin_channel (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  notification_channel_id uuid not null references artifactos.notification_channel(id),
  weixin_account_label text,
  binding_status text not null default 'not_bound' check (binding_status in ('not_bound','qr_pending','bound','active','token_stale','rebind_required','revoked')),
  qr_bound_at timestamptz,
  activated_at timestamptz,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, notification_channel_id)
);

-- 3. NotificationPolicy — which events fire through which channel
create table if not exists artifactos.notification_policy (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  policy_code text not null,
  policy_scope text not null,
  scope_ref_id uuid,
  channel_id uuid not null references artifactos.notification_channel(id),
  event_type text not null,
  min_intervention_level text not null check (min_intervention_level in ('silent_record','digest','review_queue','ask_next_meeting','interrupt_now')),
  urgency text not null default 'normal' check (urgency in ('low','normal','high','critical')),
  send_window jsonb not null default '{}'::jsonb,
  quiet_hours jsonb not null default '{}'::jsonb,
  max_daily_count integer,
  require_ack boolean not null default false,
  status text not null default 'active' check (status in ('active','paused','archived')),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, policy_code)
);

-- 4. NotificationEvent — one pending/sent/delivered notification
create table if not exists artifactos.notification_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  policy_id uuid references artifactos.notification_policy(id),
  channel_id uuid not null references artifactos.notification_channel(id),
  source_type text not null,
  source_id uuid not null,
  target_user_id uuid not null default '00000000-0000-0000-0000-000000000001',
  notification_type text not null,
  urgency text not null default 'normal' check (urgency in ('low','normal','high','critical')),
  title text not null,
  summary text not null,
  prepared_action_panel_id uuid,
  prepared_action_panel_version_no integer,
  low_risk_action_profile jsonb not null default '[]'::jsonb,
  idempotency_key text not null,
  status text not null default 'pending' check (status in (
    'pending','scheduled','sending','delivered','acknowledged',
    'failed','retrying','expired','rebind_required','canceled','ignored'
  )),
  scheduled_at timestamptz,
  sent_at timestamptz,
  acknowledged_at timestamptz,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, idempotency_key)
);

-- 5. WorkReport — rendered snapshot sent to human
create table if not exists artifactos.work_report (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  notification_event_id uuid not null references artifactos.notification_event(id),
  report_type text not null,
  rendered_text text not null,
  rendered_payload jsonb not null default '{}'::jsonb,
  visible_ref_code text,
  detail_target_type text,
  detail_target_id uuid,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 6. DailyReport — end-of-day summary
create table if not exists artifactos.daily_report (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  report_date date not null,
  day_case_id uuid references artifactos.case_record(id),
  summary_text text not null,
  completed_summary jsonb not null default '{}'::jsonb,
  decision_summary jsonb not null default '{}'::jsonb,
  risk_summary jsonb not null default '{}'::jsonb,
  tomorrow_recommendation jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','prepared','notified','opened','completed','archived')),
  prepared_at timestamptz,
  notified_at timestamptz,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, report_date, day_case_id)
);

-- 7. DailyReportEntryCard — WeChat summary entry
create table if not exists artifactos.daily_report_entry_card (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  daily_report_id uuid not null references artifactos.daily_report(id),
  notification_event_id uuid not null references artifactos.notification_event(id),
  prepared_action_panel_id uuid not null,
  headline text not null,
  summary_payload jsonb not null default '{}'::jsonb,
  status text not null default 'prepared' check (status in ('prepared','sent','opened','expired','canceled')),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, daily_report_id)
);

commit;