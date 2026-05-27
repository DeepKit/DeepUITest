-- ArtifactOS WorkCard + PreparedActionPanel Phase 1A draft
-- Target: artifactos_test first, then progee_db.artifactos after review.

begin;

-- 1. WorkCard — Amy's desk item
create table if not exists artifactos.work_card (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  card_type text not null,
  source_type text not null,
  source_id uuid not null,
  priority text not null default 'normal' check (priority in ('low','normal','high','critical')),
  review_requirement text not null default 'optional' check (review_requirement in ('must_handle','recommended','optional','info_only')),
  status text not null default 'prepared' check (status in ('prepared','visible','opened','completed','dismissed','expired')),
  title text not null,
  summary text not null,
  recommended_action_no text,
  card_payload jsonb not null default '{}'::jsonb,
  due_at timestamptz,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_work_card_source
  on artifactos.work_card (source_type, source_id, status);

create index if not exists idx_work_card_review
  on artifactos.work_card (review_requirement, status, priority);

-- 2. PreparedActionPanel — 1-8/9/0 choices
create table if not exists artifactos.prepared_action_panel (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  work_card_id uuid references artifactos.work_card(id),
  notification_event_id uuid,
  panel_type text not null,
  context_type text not null,
  context_id uuid not null,
  protocol_version text not null default 'pap-1.0',
  status text not null default 'prepared' check (status in ('prepared','active','completed','canceled','superseded')),
  current_version_no integer not null default 1,
  allow_back boolean not null default true,
  allow_cancel_current boolean not null default true,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- 3. PreparedActionOption — one numbered choice in a panel
create table if not exists artifactos.prepared_action_option (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  panel_id uuid not null references artifactos.prepared_action_panel(id),
  option_no text not null check (option_no in ('0','1','2','3','4','5','6','7','8','9')),
  option_role text not null check (option_role in ('prepared','regenerate','human_input')),
  label text not null,
  description text,
  recommendation_reason text,
  action_type text not null check (action_type in (
    'open_detail','remind_later','skip_today','view_exception_summary',
    'approve','reject','freeze','hold','rework','regenerate','human_input',
    'batch_action','same_day_exception','plan_confirm','handoff','no_op'
  )),
  action_payload jsonb not null default '{}'::jsonb,
  risk_level text not null default 'normal' check (risk_level in ('entry','low','normal','high','critical')),
  requires_confirmation boolean not null default false,
  display_order integer not null,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, panel_id, option_no)
);

-- Guard: option_no constraints
create or replace function artifactos.fn_guard_action_option_role()
returns trigger language plpgsql as $$
begin
  if new.option_no in ('1','2','3','4','5','6','7','8') and new.option_role != 'prepared' then
    raise exception 'option_no 1-8 must have option_role=prepared';
  end if;
  if new.option_no = '9' and new.option_role != 'regenerate' then
    raise exception 'option_no 9 must have option_role=regenerate';
  end if;
  if new.option_no = '0' and new.option_role != 'human_input' then
    raise exception 'option_no 0 must have option_role=human_input';
  end if;
  if new.option_no = '1' and new.recommendation_reason is null then
    raise exception 'option_no 1 (recommended) must have recommendation_reason';
  end if;
  return new;
end $$;

create trigger trg_action_option_role
before insert or update on artifactos.prepared_action_option
for each row execute function artifactos.fn_guard_action_option_role();

commit;