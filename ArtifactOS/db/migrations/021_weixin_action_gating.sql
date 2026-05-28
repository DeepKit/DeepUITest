-- ArtifactOS WeChat reply action-level gating (P0 #5)
-- Target: artifactos_test first, then artifactos production after review.
-- Enforces four action levels: entry / low_risk / needs_confirmation / cockpit_required
-- High-level actions (needs_confirmation, cockpit_required) may NEVER be executed
-- via WeChat reply alone — they must be confirmed in Amy Cockpit.

begin;

-- 0. Create reply_command table if it does not exist (never created by previous migrations)
create table if not exists artifactos.reply_command (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  notification_event_id uuid,
  channel_id uuid,
  prepared_action_panel_id uuid,
  prepared_action_panel_version_no integer,
  prepared_action_option_id uuid,
  inbound_message_id text not null,
  decision_idempotency_key text not null,
  raw_message_ref jsonb not null default '{}'::jsonb,
  raw_text text not null,
  command_type text not null,
  target_type text,
  target_id uuid,
  parse_confidence numeric(5,4),
  status text not null default 'received' check (status in (
    'received','parsed','ambiguous','confirmed','applied','rejected','expired'
  )),
  decision_record_id uuid,
  approval_record_id uuid,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, channel_id, inbound_message_id),
  unique (tenant_id, decision_idempotency_key)
);

-- 1. Add action_level column to prepared_action_option
do $$
begin
  if not exists (select 1 from information_schema.columns
    where table_schema='artifactos' and table_name='prepared_action_option'
    and column_name='action_level') then
    alter table artifactos.prepared_action_option
    add column action_level text check (action_level in (
      'entry','low_risk','needs_confirmation','cockpit_required'
    ));
  end if;
end $$;

-- 2. Map existing risk_level to action_level
-- entry → open_detail/remind_later/skip_today/view_exception_summary
-- low → approve/regenerate/no_op/handoff
-- normal/high → rework/freeze/hold/reject/batch_action/same_day_exception/plan_confirm
-- critical → human_input (must go to cockpit)
update artifactos.prepared_action_option
set action_level = case
  when risk_level = 'entry' then 'entry'
  when risk_level = 'low'   then 'low_risk'
  when risk_level in ('normal','high') then 'needs_confirmation'
  when risk_level = 'critical' then 'cockpit_required'
  else 'needs_confirmation'
end
where action_level is null;

-- 3. Guard trigger: reply_command.applied must respect action_level
create or replace function artifactos.fn_guard_weixin_action_level()
returns trigger language plpgsql as $$
declare
  p_action_level text;
begin
  if new.status = 'applied' then
    select pao.action_level into p_action_level
    from artifactos.prepared_action_option pao
    where pao.id = new.prepared_action_option_id;

    if p_action_level in ('needs_confirmation', 'cockpit_required') then
      if new.decision_record_id is null and new.approval_record_id is null then
        raise exception 'WeChat reply for action_level=%, option_id=% may not be applied without a formal decision_record_id or approval_record_id',
          p_action_level, new.prepared_action_option_id;
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_weixin_action_level_guard on artifactos.reply_command;
create trigger trg_weixin_action_level_guard
before insert or update on artifactos.reply_command
for each row execute function artifactos.fn_guard_weixin_action_level();

-- 4. Constraint: option_no 0 (human_input) always maps to cockpit_required
create or replace function artifactos.fn_guard_option_0_is_cockpit()
returns trigger language plpgsql as $$
begin
  if new.option_no = '0' and new.action_level != 'cockpit_required' then
    raise exception 'option_no=0 (human_input) must have action_level=cockpit_required';
  end if;
  return new;
end $$;

drop trigger if exists trg_option_0_cockpit on artifactos.prepared_action_option;
create trigger trg_option_0_cockpit
before insert or update on artifactos.prepared_action_option
for each row execute function artifactos.fn_guard_option_0_is_cockpit();

commit;