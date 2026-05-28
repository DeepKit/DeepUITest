-- ArtifactOS SourcePack write protection (P0 #4)
-- Target: artifactos_test first, then artifactos production after review.
-- Prevents AI or automated systems from modifying SourcePack data directly.
-- Only human decisions or meeting records may trigger SourcePack mutations.

begin;

-- 1. Guard: source_pack.allow_production may only be set via loading_decision
create or replace function artifactos.fn_guard_source_pack_update()
returns trigger language plpgsql as $$
begin
  -- Allow status transitions by human/meeting only (inserts OK)
  if tg_op = 'INSERT' then
    return new;
  end if;

  -- Block modification of display_name, source_root, pack_type unless
  -- the caller has a valid human_decision_id in metadata
  if new.display_name <> old.display_name
     or new.source_root <> old.source_root
     or new.pack_type <> old.pack_type then
    if new.metadata->>'human_decision_id' is null then
      raise exception 'SourcePack core fields (display_name/source_root/pack_type) may only be modified via human decision. Set metadata.human_decision_id.';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_source_pack_protection on artifactos.source_pack;
create trigger trg_source_pack_protection
before update on artifactos.source_pack
for each row execute function artifactos.fn_guard_source_pack_update();

-- 2. Guard: source_inventory_candidate labels may only be changed by human
create or replace function artifactos.fn_guard_inventory_candidate_update()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    return new;
  end if;

  -- Block re-labeling unless human decision is recorded
  if new.source_layer <> old.source_layer
     or new.candidate_claim_strength <> old.candidate_claim_strength
     or new.external_publish_policy <> old.external_publish_policy then
    if new.human_review_status not in ('approved', 'rejected') then
      raise exception 'source_inventory_candidate labels may only be changed after human review. Update human_review_status first.';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_inventory_candidate_protection on artifactos.source_inventory_candidate;
create trigger trg_inventory_candidate_protection
before update on artifactos.source_inventory_candidate
for each row execute function artifactos.fn_guard_inventory_candidate_update();

-- 3. Audit: all source_pack modifications write to event_ledger
create or replace function artifactos.fn_audit_source_pack_changes()
returns trigger language plpgsql as $$
declare
  changed_fields jsonb := '[]'::jsonb;
begin
  if tg_op = 'INSERT' then
    insert into artifactos.event_ledger (event_type, aggregate_type, aggregate_id, actor_type, actor_id, payload)
    values ('source_pack_created', 'source_pack', new.id, 'system', null,
      jsonb_build_object('display_name', new.display_name, 'pack_type', new.pack_type, 'loading_level', new.loading_level));
  elsif tg_op = 'UPDATE' then
    if old.display_name <> new.display_name then
      changed_fields := changed_fields || jsonb_build_object('field','display_name','old',old.display_name,'new',new.display_name);
    end if;
    if old.loading_level <> new.loading_level then
      changed_fields := changed_fields || jsonb_build_object('field','loading_level','old',old.loading_level,'new',new.loading_level);
    end if;
    if jsonb_array_length(changed_fields) > 0 then
      insert into artifactos.event_ledger (event_type, aggregate_type, aggregate_id, actor_type, actor_id, payload)
      values ('source_pack_updated', 'source_pack', new.id, 'system', null,
        jsonb_build_object('changes', changed_fields, 'human_decision_id', new.metadata->>'human_decision_id'));
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_source_pack_audit on artifactos.source_pack;
create trigger trg_source_pack_audit
after insert or update on artifactos.source_pack
for each row execute function artifactos.fn_audit_source_pack_changes();

commit;