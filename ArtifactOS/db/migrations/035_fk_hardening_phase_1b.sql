-- ArtifactOS FK Hardening Phase 1B
-- Target: artifactos_test first, then artifactos production after review.
-- Scope: Case & Studio hierarchy FKs per 024_fk_roadmap.sql.
-- Safety: uses NOT VALID + VALIDATE CONSTRAINT to avoid full table locks on large tables.

begin;

-- Phase 1B — Case & Studio hierarchy

-- case_record: parent_case_id → case_record.id
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'fk_case_parent'
      and conrelid = 'artifactos.case_record'::regclass
  ) then
    alter table artifactos.case_record
      add constraint fk_case_parent
      foreign key (parent_case_id) references artifactos.case_record(id)
      on delete set null
      not valid;
    alter table artifactos.case_record validate constraint fk_case_parent;
  end if;
end $$;

-- case_record: root_case_id → case_record.id
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'fk_case_root'
      and conrelid = 'artifactos.case_record'::regclass
  ) then
    alter table artifactos.case_record
      add constraint fk_case_root
      foreign key (root_case_id) references artifactos.case_record(id)
      on delete set null
      not valid;
    alter table artifactos.case_record validate constraint fk_case_root;
  end if;
end $$;

-- studio: case_id → case_record.id
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'fk_studio_case'
      and conrelid = 'artifactos.studio'::regclass
  ) then
    alter table artifactos.studio
      add constraint fk_studio_case
      foreign key (case_id) references artifactos.case_record(id)
      on delete cascade
      not valid;
    alter table artifactos.studio validate constraint fk_studio_case;
  end if;
end $$;

-- studio: day_sub_case_id → case_record.id
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'fk_studio_day_sub_case'
      and conrelid = 'artifactos.studio'::regclass
  ) then
    alter table artifactos.studio
      add constraint fk_studio_day_sub_case
      foreign key (day_sub_case_id) references artifactos.case_record(id)
      on delete set null
      not valid;
    alter table artifactos.studio validate constraint fk_studio_day_sub_case;
  end if;
end $$;

-- sub_studio: studio_id → studio.id
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'fk_substudio_studio'
      and conrelid = 'artifactos.sub_studio'::regclass
  ) then
    alter table artifactos.sub_studio
      add constraint fk_substudio_studio
      foreign key (studio_id) references artifactos.studio(id)
      on delete cascade
      not valid;
    alter table artifactos.sub_studio validate constraint fk_substudio_studio;
  end if;
end $$;

-- artifact: sub_studio_id → sub_studio.id
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'fk_artifact_substudio'
      and conrelid = 'artifactos.artifact'::regclass
  ) then
    alter table artifactos.artifact
      add constraint fk_artifact_substudio
      foreign key (sub_studio_id) references artifactos.sub_studio(id)
      on delete set null
      not valid;
    alter table artifactos.artifact validate constraint fk_artifact_substudio;
  end if;
end $$;

-- artifact: blueprint_id → artifact_blueprint.id
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'fk_artifact_blueprint'
      and conrelid = 'artifactos.artifact'::regclass
  ) then
    alter table artifactos.artifact
      add constraint fk_artifact_blueprint
      foreign key (blueprint_id) references artifactos.artifact_blueprint(id)
      on delete set null
      not valid;
    alter table artifactos.artifact validate constraint fk_artifact_blueprint;
  end if;
end $$;

commit;
