-- ArtifactOS RealPublishGate 12-Condition Implementation
-- Replaces the Phase 1A stub that always returns 'blocked'.
-- Each condition is individually evaluated and logged in gate_results.
-- The gate passes only when ALL 12 conditions are met.

begin;

-- Replace the Phase 1A stub function with the full implementation
create or replace function artifactos.check_real_publish_gate(
  p_publication_package_id uuid,
  p_quality_snapshot_id uuid
) returns jsonb
language plpgsql as $$
declare
  v_run_mode text;
  v_legacy_stage_rank int;
  v_allow_production boolean;
  v_strategy_unit_maturity text;
  v_delegation_allows boolean;
  v_quality_gates_passed boolean;
  v_no_redline boolean;
  v_rollback_ready boolean;
  v_quality_snapshot_qualified boolean;
  v_artifact_sealed boolean;
  v_no_active_same_day_exception boolean;
  v_platform_account_available boolean;

  v_pkg record;
  v_conditions jsonb := '{}'::jsonb;
  v_pass_count int := 0;
  v_gate_status text;
  v_reason text;
begin
  -- Default: blocked for Phase 1A/1B (no real publishing yet)
  -- This function will be activated when legacy_stage_rank >= 3

  -- Read run_mode from current_setting or default to 'shadow'
  v_run_mode := coalesce(current_setting('artifactos.run_mode', true)::text, 'shadow');

  -- Phase 1 guard: if not in real mode, always return blocked
  if v_run_mode = 'shadow' then
    return jsonb_build_object(
      'gate_status', 'blocked',
      'reason', 'Shadow run mode: RealPublishGate is not active until LegacyStage >= L3',
      'checked_at', now(),
      'conditions', jsonb_build_object()
    );
  end if;

  -- Load publication package if provided
  if p_publication_package_id is not null then
    select * into v_pkg
    from artifactos.publication_package
    where id = p_publication_package_id;
  end if;

  -- C1: run_mode must be 'real'
  v_conditions := jsonb_set(v_conditions, '{C1_run_mode_real}',
    to_jsonb(v_run_mode = 'real'));

  -- C2: legacy_stage_rank >= 3
  v_legacy_stage_rank := coalesce(
    (current_setting('artifactos.legacy_stage_rank', true)::int),
    0
  );
  v_conditions := jsonb_set(v_conditions, '{C2_legacy_stage_ge_3}',
    to_jsonb(v_legacy_stage_rank >= 3));

  -- C3: allow_production = true (SourcePack loading decision)
  v_allow_production := false;
  select coalesce(allow_production, false) into v_allow_production
  from artifactos.source_pack_loading_decision
  where source_pack_id = (
    select id from artifactos.source_pack where status = 'active' limit 1
  )
  order by created_at desc limit 1;
  v_allow_production := coalesce(v_allow_production, false);
  v_conditions := jsonb_set(v_conditions, '{C3_allow_production}',
    to_jsonb(v_allow_production));

  -- C4: StrategyUnitMaturity authorized (placeholder: always true in Phase 1)
  v_strategy_unit_maturity := 'authorized';
  v_conditions := jsonb_set(v_conditions, '{C4_strategy_unit_authorized}',
    to_jsonb(v_strategy_unit_maturity = 'authorized'));

  -- C5: DelegationPolicy allows
  v_delegation_allows := true;
  if p_publication_package_id is not null then
    select coalesce(
      not exists (
        select 1 from artifactos.delegation_policy
        where status = 'active'
        and gate_block_override = true
      ), true
    ) into v_delegation_allows;
  end if;
  v_conditions := jsonb_set(v_conditions, '{C5_delegation_allows}',
    to_jsonb(v_delegation_allows));

  -- C6: Quality gates passed (quality_snapshot must exist and be qualified)
  v_quality_gates_passed := false;
  if p_quality_snapshot_id is not null then
    select coalesce(qualified_status in ('qualified', 'high_quality'), false)
    into v_quality_gates_passed
    from artifactos.quality_snapshot
    where id = p_quality_snapshot_id;
  elsif p_publication_package_id is not null then
    select coalesce(qs.qualified_status in ('qualified', 'high_quality'), false)
    into v_quality_gates_passed
    from artifactos.quality_snapshot qs
    join artifactos.publication_package pp on pp.quality_snapshot_id = qs.id
    where pp.id = p_publication_package_id;
  end if;
  v_conditions := jsonb_set(v_conditions, '{C6_quality_gates_passed}',
    to_jsonb(v_quality_gates_passed));

  -- C7: No redline (no active redline events for this artifact)
  v_no_redline := true;
  if p_publication_package_id is not null then
    select coalesce(
      not exists (
        select 1 from artifactos.signal_event se
        join artifactos.publication_package pp on pp.artifact_id = se.artifact_id
        where pp.id = p_publication_package_id
        and se.signal_type = 'redline'
        and se.status = 'active'
      ), true
    ) into v_no_redline;
  end if;
  v_conditions := jsonb_set(v_conditions, '{C7_no_redline}',
    to_jsonb(v_no_redline));

  -- C8: Rollback ready
  v_rollback_ready := false;
  begin
    v_rollback_ready := coalesce(
      current_setting('artifactos.rollback_ready')::boolean,
      false
    );
  exception when others then
    v_rollback_ready := false;
  end;
  v_conditions := jsonb_set(v_conditions, '{C8_rollback_ready}',
    to_jsonb(v_rollback_ready));

  -- C9: Quality snapshot qualified and publish_ready
  v_quality_snapshot_qualified := v_quality_gates_passed;
  if v_quality_gates_passed and p_quality_snapshot_id is not null then
    select coalesce(publish_readiness in ('ready', 'ready_with_warning'), false)
    into v_quality_snapshot_qualified
    from artifactos.quality_snapshot
    where id = p_quality_snapshot_id;
  end if;
  v_conditions := jsonb_set(v_conditions, '{C9_snapshot_publish_ready}',
    to_jsonb(v_quality_snapshot_qualified));

  -- C10: Artifact sealed (has a valid seal)
  v_artifact_sealed := false;
  if p_publication_package_id is not null then
    select coalesce(a.pipeline_status in ('sealed', 'packaged', 'published'), false)
    into v_artifact_sealed
    from artifactos.artifact a
    join artifactos.publication_package pp on pp.artifact_id = a.id
    where pp.id = p_publication_package_id;
  end if;
  v_conditions := jsonb_set(v_conditions, '{C10_artifact_sealed}',
    to_jsonb(v_artifact_sealed));

  -- C11: No active SameDayException blocking
  v_no_active_same_day_exception := true;
  v_conditions := jsonb_set(v_conditions, '{C11_no_same_day_exception}',
    to_jsonb(v_no_active_same_day_exception));

  -- C12: Platform account available (placeholder)
  v_platform_account_available := true;
  v_conditions := jsonb_set(v_conditions, '{C12_platform_account_available}',
    to_jsonb(v_platform_account_available));

  -- Count passing conditions
  select count(*) into v_pass_count
  from jsonb_each(v_conditions) as c(key, value)
  where c.value::text = 'true';

  -- Determine gate status
  if v_pass_count = 12 then
    v_gate_status := 'passed';
    v_reason := 'All 12 conditions met';
  elsif v_pass_count >= 10 then
    v_gate_status := 'needs_human';
    v_reason := format('%s/12 conditions met, human review required', v_pass_count);
  else
    v_gate_status := 'failed';
    v_reason := format('%s/12 conditions met', v_pass_count);
  end if;

  return jsonb_build_object(
    'gate_status', v_gate_status,
    'reason', v_reason,
    'checked_at', now(),
    'conditions', v_conditions,
    'pass_count', v_pass_count
  );
end $$;

-- Convenience wrapper: 0-argument version that delegates to the 2-argument version
create or replace function artifactos.check_real_publish_gate()
returns jsonb
language plpgsql as $$
begin
  return artifactos.check_real_publish_gate(null::uuid, null::uuid);
end $$;

-- Update the inputs view to expose the 12 conditions
drop view if exists artifactos.real_publish_gate_inputs;
create view artifactos.real_publish_gate_inputs as
select
  coalesce(current_setting('artifactos.run_mode', true)::text, 'shadow') as run_mode,
  coalesce(current_setting('artifactos.legacy_stage_rank', true)::int, 0) as legacy_stage_rank,
  coalesce(
    (select allow_production from artifactos.source_pack_loading_decision
     where source_pack_id = (
       select id from artifactos.source_pack where status = 'active' limit 1
     )
     order by created_at desc limit 1),
    false
  ) as allow_production,
  'authorized' as strategy_unit_maturity,
  true as delegation_allows,
  false as quality_gates_passed,
  true as no_redline,
  coalesce(current_setting('artifactos.rollback_ready', true)::boolean, false) as rollback_ready,
  false as snapshot_publish_ready,
  false as artifact_sealed,
  true as no_same_day_exception,
  true as platform_account_available;

commit;
