-- ArtifactOS FK Hardening Roadmap (P1 #12)
-- Target: artifactos_test first, then artifactos production after review.
-- This migration does NOT create any FKs — it documents the plan.
-- All FK additions will be performed in dedicated hardening migrations per Phase.

/*
 * FK Hardening Schedule
 * =====================
 *
 * Already enforced (Phase 1A, before this roadmap):
 *   artifact_version.artifact_id                    → artifact.id
 *   shadow_run_observation.shadow_run_day_id        → shadow_run_day.id
 *   publication_package.quality_snapshot_id         → quality_snapshot.id
 *   publication_package.rendition_id                → rendition.id
 *   publication_package.real_publish_gate_run_id   → real_publish_gate_run.id
 *
 * Phase 1B — Case & Studio hierarchy:
 *   case_record.parent_case_id       → case_record.id
 *   case_record.root_case_id         → case_record.id
 *   studio.case_id                   → case_record.id
 *   studio.day_sub_case_id           → case_record.id
 *   sub_studio.studio_id             → studio.id
 *   sub_studio.artifact_plan_id      → artifact_plan.id
 *   artifact_plan.studio_id          → studio.id
 *   artifact.sub_studio_id           → sub_studio.id
 *   artifact.artifact_plan_id        → artifact_plan.id
 *   artifact.blueprint_id            → artifact_blueprint.id
 *
 * Phase 1C — Execution & governance:
 *   substudio_execution_task.sub_studio_id    → sub_studio.id
 *   substudio_execution_task.artifact_plan_id → artifact_plan.id
 *   substudio_execution_task.artifact_id      → artifact.id
 *   case_snapshot.case_id                     → case_record.id
 *   meeting_record.case_id                    → case_record.id
 *   meeting_record.protocol_id                → meeting_protocol.id
 *   approval_record.delegation_policy_id      → delegation_policy.id
 *   daily_report.day_case_id                  → case_record.id
 *   daily_calibration_review.artifact_id      → artifact.id
 *   calibration_example.artifact_id           → artifact.id
 *
 * Phase 2 — Cross-schema references:
 *   publication_package.artifact_id            → artifact.id
 *   publication_package.artifact_version_id    → artifact_version.id
 *   quality_snapshot.artifact_id               → artifact.id
 *   quality_snapshot.artifact_version_id       → artifact_version.id
 *   signal_event.artifact_id                   → artifact.id
 *
 * Phase 3+ — External references (other schemas / services):
 *   Any references to media_publish.publication_task
 *   Any references to legacy_bridge.*
 *   Any cross-service IDs that today live as bare UUIDs
 */
commit;