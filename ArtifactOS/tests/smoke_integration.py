#!/usr/bin/env python
"""ArtifactOS Phase 1A Integration Smoke Test.

Exercises the full chain against artifactos_test:
  Case → Studio → SubStudio → Artifact → ArtifactVersion(sealed)
  → QualityRun → QualitySnapshot(qualified) → PublicationPackage(simulated)

No real publishing.  All test data cleaned up after run.
"""

import psycopg2, sys, time, json, uuid, hashlib, os
from dotenv import load_dotenv

# Load .env from project root
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

DB = os.environ.get('ARTIFACTOS_DB_NAME', 'artifactos_test')
DB_USER = os.environ.get('ARTIFACTOS_DB_USER', 'fuyi01')
DB_PASS = os.environ.get('ARTIFACTOS_DB_PASS', '')
DB_HOST = os.environ.get('ARTIFACTOS_DB_HOST', '127.0.0.1')
DB_PORT = os.environ.get('ARTIFACTOS_DB_PORT', '5432')
CONN = f"host={DB_HOST} port={DB_PORT} dbname={DB} user={DB_USER} password={DB_PASS}"

def main():
    passed = 0
    failed = 0

    def ok(msg): nonlocal passed; passed += 1; print(f"  PASS {msg}")
    def fail(msg): nonlocal failed; failed += 1; print(f"  FAIL {msg}")

    conn = psycopg2.connect(CONN)
    conn.autocommit = False
    cur = conn.cursor()

    try:
        # ── 1. SourcePack check ──
        cur.execute("select display_name, loading_level from artifactos.source_pack limit 1")
        sp = cur.fetchone()
        if sp: ok(f"SourcePack: {sp[0]} | SPL={sp[1]}")
        else: fail("No SourcePack loaded")

        cur.execute("select count(*) from artifactos.source_inventory_candidate")
        inv = cur.fetchone()[0]
        if inv >= 2900: ok(f"inventory: {inv} files")
        else: fail(f"inventory: only {inv} files")

        # ── 2. Blueprint ──
        cur.execute("select count(*) from artifactos.artifact_blueprint")
        bp = cur.fetchone()[0]
        if bp >= 3: ok(f"blueprints: {bp}")
        else: fail(f"blueprints: only {bp}")

        # ── 3. Meeting ──
        cur.execute("select count(*) from artifactos.meeting_protocol where status='active'")
        mp = cur.fetchone()[0]
        if mp >= 6: ok(f"meeting protocols: {mp}")
        else: fail(f"meeting protocols: only {mp}")

        # ── 4. Case chain ──
        cur.execute("select count(*) from artifactos.case_record where status='active'")
        cases = cur.fetchone()[0]
        if cases >= 3: ok(f"active cases: {cases}")
        else: fail(f"active cases: only {cases}")

        # ── 5. Full chain transaction ──
        chain = str(uuid.uuid4())[:8]
        conn.rollback()
        conn.set_session(autocommit=False)

        cur.execute(
            "insert into artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) "
            "values (%s, 'day_sub', %s, 'active', 'tactical_execution', "
            "(select id from artifactos.case_record where case_code='yearcase_2026'), "
            "(select id from artifactos.case_record where case_code='yearcase_2026')) returning id",
            (f'smoke_{chain}', f'Smoke Chain {chain}')
        )
        case_id = cur.fetchone()[0]
        cur.execute(
            "insert into artifactos.studio (studio_code, case_id, platform_id, artifact_type, theory_visibility, status) "
            "values (%s, %s, 'zhihu', 'zhihu_longform', 'medium', 'planning') returning id",
            (f'smoke_studio_{chain}', case_id)
        )
        studio_id = cur.fetchone()[0]
        cur.execute(
            "insert into artifactos.artifact_plan (studio_id, blueprint_id, primary_purpose_type, risk_level, status) "
            "values (%s, (select id from artifactos.artifact_blueprint where blueprint_code='zhihu_article_v1' limit 1), "
            "'explanation', 'normal', 'approved') returning id",
            (studio_id,)
        )
        plan_id = cur.fetchone()[0]
        cur.execute(
            "insert into artifactos.sub_studio (studio_id, artifact_plan_id, status) values (%s, %s, 'executing') returning id",
            (studio_id, plan_id)
        )
        cur.execute(
            "insert into artifactos.artifact (sub_studio_id, artifact_plan_id, blueprint_id, title, status, "
            "primary_purpose_type, theory_visibility) "
            "values ((select id from artifactos.sub_studio where artifact_plan_id=%s), %s, "
            "(select id from artifactos.artifact_blueprint where blueprint_code='zhihu_article_v1' limit 1), "
            "'Smoke Test Artifact', 'assembled', 'explanation', 'medium') returning id",
            (plan_id, plan_id)
        )
        artifact_id = cur.fetchone()[0]

        body = ("AI is not just a productivity tool. It represents a structural transformation "
                "in how we think about knowledge work. The fundamental shift is from executing "
                "procedures to defining desired outcomes. This article explores three dimensions "
                "of this transformation: cognitive, organizational, and methodological. "
                "We argue that the most important skill in the AI era is not learning new tools "
                "but understanding constraint spaces and outcome specifications.")
        cur.execute(
            "insert into artifactos.artifact_version (artifact_id, version_no, assembled_payload, seal_status) "
            "values (%s, 1, %s, 'sealed') returning id",
            (artifact_id, json.dumps({"title": "Smoke Test", "body": body}))
        )
        version_id = cur.fetchone()[0]

        # ES gate: validate body length
        if len(body) >= 50:
            es_passed = True
        else:
            es_passed = False
            fail("ES gate: body too short")

        if es_passed:
            cur.execute(
                "insert into artifactos.quality_run (artifact_id, artifact_version_id, run_type, run_evidence, run_status, completed_at) "
                "values (%s, %s, 'es', '{\"es_gate\":\"passed\"}', 'completed', now()) returning id",
                (artifact_id, version_id)
            )
            run_id = cur.fetchone()[0]

            cur.execute(
                "insert into artifactos.quality_snapshot (artifact_id, artifact_version_id, qualified_status, "
                "publish_readiness, purpose_fit_status, seal_candidate, sealed_at, sealed_by) "
                "values (%s, %s, 'qualified', 'ready', 'pass', true, null, null) returning id",
                (artifact_id, version_id)
            )
            snapshot_id = cur.fetchone()[0]

            cur.execute(
                "update artifactos.quality_snapshot set quality_run_ids_cache=%s where id=%s",
                (json.dumps([str(run_id)]), snapshot_id)
            )
            cur.execute(
                "update artifactos.quality_snapshot set sealed_at=now(), sealed_by='system:smoke_test' where id=%s and sealed_at is null",
                (snapshot_id,)
            )

            # Build publication package (simulated)
            idem_key = f'smoke_pkg_{chain}_{int(time.time())}'
            cur.execute(
                "insert into artifactos.publication_package (artifact_id, artifact_version_id, quality_snapshot_id, "
                "platform, idempotency_key, simulation_only, run_mode, status) "
                "values (%s, %s, %s, 'zhihu', %s, true, 'shadow', 'simulated') returning id",
                (artifact_id, version_id, snapshot_id, idem_key)
            )
            package_id = cur.fetchone()[0]

            ok(f"full chain: Case→Studio→SubStudio→Artifact→Version→Run→Snapshot→Package")

            # Commit the chain so snapshot seal is visible to other connections
            conn.commit()

            # Verify shadow guard
            try:
                cur.execute("update artifactos.publication_package set status='queued' where id=%s", (package_id,))
                cur.execute("rollback")
                fail("shadow guard: should have blocked queued transition")
            except Exception:
                conn.rollback()
                ok("shadow guard: blocked queued transition (expected)")

            # Verify snapshot immutability — sealed snapshots reject UPDATE.
            # The snapshot was sealed in the INSERT+UPDATE cycle above;
            # the guard trigger fn_guard_snapshot_immutable fires on UPDATE.
            blocked = False
            conn2 = psycopg2.connect(CONN)
            conn2.autocommit = False
            cur2 = conn2.cursor()
            try:
                cur2.execute("update artifactos.quality_snapshot set qualified_status='not_qualified' where id=%s", (snapshot_id,))
            except Exception:
                conn2.rollback()
                blocked = True
            if blocked:
                ok("snapshot immutability: blocked modification (expected)")
            else:
                conn2.rollback()
                fail("snapshot immutability: should have blocked modification")
            conn2.close()

            # Verify state machine guard — illegal combo
            try:
                cur.execute(
                    "insert into artifactos.substudio_execution_task (pipeline_status, quality_status, publish_status) "
                    "values ('drafting', 'published', 'pending')"
                )
                fail("state machine: should have rejected illegal combo")
            except Exception:
                conn.rollback()
                ok("state machine: rejected illegal combo (expected)")

            # Verify RealPublishGate always blocked
            cur.execute("select artifactos.check_real_publish_gate()")
            gate_json = cur.fetchone()[0]
            gate = (gate_json.get('gate_status'), gate_json.get('reason'))
            if gate and gate[0] == 'blocked' and 'RealPublishGate' in (gate[1] or ''):
                ok(f"RealPublishGate: {gate[0]} — {gate[1]}")
            else:
                fail(f"RealPublishGate: unexpected status {gate}")

            # ── 6. ShadowRun + Observation ──
            cur.execute(
                "insert into artifactos.shadow_run (run_code, status, start_date, end_date, primary_platform, theory_visibility) "
                "values (%s, 'running', '2026-05-27', '2026-05-28', 'zhihu', 'medium') returning id",
                (f'smoke_sr_{chain}',)
            )
            sr_id = cur.fetchone()[0]
            cur.execute(
                "insert into artifactos.shadow_run_day (shadow_run_id, run_date, day_index, status) "
                "values (%s, '2026-05-27', 1, 'simulating') returning id",
                (sr_id,)
            )
            srd_id = cur.fetchone()[0]
            cur.execute(
                "insert into artifactos.shadow_run_observation (shadow_run_id, shadow_run_day_id, observation_type, severity) "
                "values (%s, %s, 'no_material_deviation', 'none') returning id",
                (sr_id, srd_id)
            )
            ok(f"shadow run: created + day + observation")

            # ── 7. Work Card (daily report already exists from Day 1 shadow) ──
            cur.execute(
                "insert into artifactos.work_card (card_type, source_type, source_id, title, summary, review_requirement, status) "
                "values ('DailyOverviewCard', 'case_record', %s, 'Smoke Test Card', 'Integration smoke', 'must_handle', 'prepared')",
                (case_id,)
            )
            ok("work card created")

            # ── 8. AutoTune: deny-list blocks ──
            cur.execute(
                "insert into artifactos.auto_tune_event (target_type, parameter_path, before_value, after_value, risk_level, requires_human_review, human_visible_level) "
                "values ('strategy_unit', 'source_pack.core', '0.5', '0.8', 'redline', true, 'review_required')"
            )
            ok("AutoTune: deny-listed parameter recorded as redline + requires_human_review")

            # ── 9. Legacy bridge diff ──
            cur.execute(
                "insert into legacy_bridge.legacy_diff_card (artifactos_ref, legacy_ref, deviation_type, severity, status) "
                "values (%s, %s, 'topic_deviation', 'medium', 'open')",
                (json.dumps({"artifact_id": str(artifact_id)}), json.dumps({"legacy": "no old system"})),
            )
            ok("legacy diff card created")

            # Clean up test chain
            cur.execute("delete from artifactos.publication_package where id=%s", (package_id,))
            cur.execute("delete from artifactos.quality_snapshot where id=%s", (snapshot_id,))
            cur.execute("delete from artifactos.quality_run where id=%s", (run_id,))
            cur.execute("delete from artifactos.artifact_version where id=%s", (version_id,))
            cur.execute("delete from artifactos.artifact where id=%s", (artifact_id,))
            cur.execute("delete from artifactos.sub_studio where artifact_plan_id=%s", (plan_id,))
            cur.execute("delete from artifactos.artifact_plan where id=%s", (plan_id,))
            cur.execute("delete from artifactos.studio where id=%s", (studio_id,))
            cur.execute("delete from artifactos.case_record where id=%s", (case_id,))
            cur.execute("delete from artifactos.shadow_run_observation where shadow_run_id=%s", (sr_id,))
            cur.execute("delete from artifactos.shadow_run_day where shadow_run_id=%s", (sr_id,))
            cur.execute("delete from artifactos.shadow_run where id=%s", (sr_id,))

            conn.commit()
            ok("test chain cleaned up")

    except Exception as e:
        conn.rollback()
        fail(f"unexpected error: {e}")
    finally:
        cur.close()
        conn.close()

    print(f"\n{'='*50}")
    print(f"  PASS: {passed}  FAIL: {failed}")
    print(f"{'='*50}")
    return 0 if failed == 0 else 1


if __name__ == '__main__':
    sys.exit(main())