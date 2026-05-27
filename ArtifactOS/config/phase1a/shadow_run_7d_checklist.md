# 7 Day Shadow Run Acceptance Checklist

> Phase 1A execution checklist; each day must pass before advancing.
> Run mode: shadow only.  Real publishing remains with legacy system.

---

## Day 0 — Prep

- [ ] `artifactos_test` database reachable and migrations applied (001-007)
- [ ] `source_pack` record exists, loading_level = SPL2
- [ ] `source_inventory_candidate` populated (≥ 1 file)
- [ ] `media_publish doctor` or equivalent check confirms playwright/runtime available
- [ ] Legacy system path located and readable (article_pipeline.py, publish_engine.py)
- [ ] Hermes or Amy Desk fallback confirmed (iPhone/WeChat test message sendable)
- [ ] `first_operational_surface.yaml` filled with tangible values
- [ ] `DayCase` draft created (may be minimal, single-case)
- [ ] `NextDayPlan` draft generated for Day 1

---

## Day 1 — Pipeline Pathway

- [ ] `DailyReport` generated and written to `artifactos_test`
- [ ] `NextDayPlan` confirmed or amended by human
- [ ] At least one `Artifact` candidate generated (zhihu longform)
- [ ] `QualityRun` completed (ES gate at minimum)
- [ ] `PublicationPackage` created with `simulation_only=true`, `run_mode=shadow`
- [ ] `ShadowRunObservation` recorded (may be `no_material_deviation` for Day 1)
- [ ] EveningWorkPage displayed with at least `DailyReportCard` + `TomorrowPublishReviewCard`
- [ ] No real publishing triggered (verified via `publication_package.status not in ('queued','submitting','published')`)

---

## Day 2 — Artifact Chain Validation

- [ ] `SourcePackSnapshot` → `Case` → `Studio` → `ArtifactPlan` → `Artifact` chain replayable
- [ ] `Artifact` passes structure gate (spec_snapshot_id present, evidence_coverage ≥ 0.6)
- [ ] `QualitySnapshot` sealed for at least one artifact
- [ ] `SimulatedPublicationAttempt` recorded correctly
- [ ] Legacy daily plan imported into `legacy_bridge.legacy_external_ref`
- [ ] `LegacyDiffCard` generated (severity ≤ medium for Day 2 expected)

---

## Day 3 — Evening Review Closed Loop

- [ ] `TomorrowPublishReviewCard` displayed to human
- [ ] Human action recorded via `1-8/9/0` panel
- [ ] Overnight revision produces new `ArtifactVersion`
- [ ] Rebuilt `PublicationPackage` re-bound to new `QualitySnapshot`
- [ ] Morning light confirmation shows only exceptions
- [ ] Same-day exception NOT triggered (Goal: zero)

---

## Day 4 — Legacy System Comparison

- [ ] Legacy publication records imported (≥ 1 type)
- [ ] `LegacyDiffCard` covers ≥ 2 deviation types (topic/schedule/quality/theory_visibility/platform_fit/publication_action/human_choice)
- [ ] Deviation resolution logged; no direct SourcePack modification triggered by any deviation
- [ ] ShadowRunObservation records human_note where applicable

---

## Day 5 — Exception & Degradation

- [ ] Simulated WeChat unreachable → system degrades to Amy Desk without data loss
- [ ] Simulated media_publish smoke failure → `PublicationPackage` remains `held`/`blocked`, does not silently transition
- [ ] Simulated human-no-review → `human_not_reviewed` recorded, no publish attempt
- [ ] Attention budget overflow → cards deferred, digest-mode activated
- [ ] `InterruptCard` raised for redline risk (simulate one redline scenario)

---

## Day 6 — Feedback & Candidate

- [ ] At least one `CandidateProposal` generated (opportunity / plan_change / strategy_change)
- [ ] At least one `BackfeedCandidate` generated (from legacy diff or human feedback)
- [ ] Both enter human review queue, NOT auto-applied to SourcePack or plan_pool
- [ ] Aggregate gate / threshold gate / purpose gate logic exercised (at least one raw signal must be merged before becoming a candidate)
- [ ] AutoTune event generated for a whitelisted low-risk parameter only

---

## Day 7 — Retrospective

- [ ] `ShadowRunReviewReport` generated, containing:
  - [ ] Run summary (6 days of metrics)
  - [ ] Human load analysis (must_handle count, review minutes per evening)
  - [ ] Artifact quality analysis (gate pass rates, rework counts)
  - [ ] Legacy deviation analysis (deviation breakdown)
  - [ ] Prepared-action analysis (which buttons used, which skipped)
  - [ ] Calibration examples (≥ 1 positive or negative model extracted)
  - [ ] Intervention mistakes (wrong_interrupt_count + missed_interrupt_count)
  - [ ] Source boundary risks identified
  - [ ] Phase 1A implementation priority recommendations
- [ ] `RealPublishGate` remains blocked (verified: `run_mode=shadow`, `legacy_stage_rank=0`)
- [ ] All simulation data archived under `shadow_run_archive`, NOT mixed into production records
- [ ] Final decision: proceed to Phase 1A implementation, defer, or re-design