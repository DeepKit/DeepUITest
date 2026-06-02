-- ArtifactOS Case hierarchy validation
-- Ensures DaySubCase can only attach to DayCase, not WeekCase, MonthCase etc.
-- Hierarchy: YearCase > HalfYearCase/QuarterCase > MonthCase > WeekCase > DayCase > DaySubCase

begin;

create or replace function artifactos.fn_guard_case_type_hierarchy()
returns trigger language plpgsql as $$
declare
  parent_type text;
  v_msg text;
begin
  if new.parent_case_id is null then
    return new;
  end if;

  select case_type into parent_type
  from artifactos.case_record
  where id = new.parent_case_id;

  if not found then
    -- Phase 1A: relaxed FK — parent may not exist yet; skip validation
    return new;
  end if;

  case new.case_type
    when 'half_year', 'quarter' then
      if parent_type != 'year' then
        v_msg := 'case_type=' || new.case_type || ' must have parent case_type=year, got ' || parent_type;
        raise exception '%', v_msg;
      end if;
    when 'month' then
      if parent_type not in ('half_year', 'quarter') then
        v_msg := 'case_type=' || new.case_type || ' must have parent case_type=half_year or quarter, got ' || parent_type;
        raise exception '%', v_msg;
      end if;
    when 'week' then
      if parent_type != 'month' then
        v_msg := 'case_type=' || new.case_type || ' must have parent case_type=month, got ' || parent_type;
        raise exception '%', v_msg;
      end if;
    when 'day' then
      if parent_type != 'week' then
        v_msg := 'case_type=' || new.case_type || ' must have parent case_type=week, got ' || parent_type;
        raise exception '%', v_msg;
      end if;
    when 'day_sub' then
      if parent_type != 'day' then
        v_msg := 'case_type=day_sub must have parent case_type=day, got ' || parent_type;
        raise exception '%', v_msg;
      end if;
    else
      -- year has no parent (root); other custom types pass through
      null;
  end case;

  if new.root_case_id is null then
    new.root_case_id := new.parent_case_id;
  end if;

  return new;
end $$;

drop trigger if exists trg_case_type_hierarchy on artifactos.case_record;
create trigger trg_case_type_hierarchy
before insert or update on artifactos.case_record
for each row execute function artifactos.fn_guard_case_type_hierarchy();

commit;