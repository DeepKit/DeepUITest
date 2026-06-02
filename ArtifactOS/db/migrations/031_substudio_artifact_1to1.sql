-- ArtifactOS SubStudio-Artifact 1:1 constraint
-- Enforces the architectural rule: one SubStudio = one Artifact (docs/04 §6.3)
-- Uses a partial unique index so frozen/recalled/retired artifacts don't block new ones.

begin;

create unique index if not exists uq_artifact_active_sub_studio
  on artifactos.artifact (sub_studio_id)
  where status not in ('frozen', 'recalled', 'retired');

comment on index artifactos.uq_artifact_active_sub_studio is
  'Enforces docs/04 §6.3: one SubStudio = one Artifact (excluding frozen/recalled/retired).';

commit;