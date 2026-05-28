-- ArtifactOS critical FK hardening (P1 #11)
-- Target: artifactos_test first, then artifactos production after review.
-- Check results: shadow_run_observation.shadow_run_day_id FK already exists (✅).
-- artifact_version.artifact_id FK already exists (✅).
-- Only publication_package.quality_snapshot_id FK needs to be added.

begin;

alter table artifactos.publication_package
drop constraint if exists fk_package_quality_snapshot;

alter table artifactos.publication_package
add constraint fk_package_quality_snapshot
foreign key (quality_snapshot_id) references artifactos.quality_snapshot(id);

commit;