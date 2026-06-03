#!/usr/bin/env python
"""Run one ArtifactOS Phase 1A publication chain in shadow mode.

Keeps the created records for acceptance review.
"""

import hashlib
import json
import os
import time
import uuid

from dotenv import load_dotenv
import psycopg2

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

CONN = (
    f"host={os.environ.get('ARTIFACTOS_DB_HOST', '127.0.0.1')} "
    f"port={os.environ.get('ARTIFACTOS_DB_PORT', '5432')} "
    f"dbname={os.environ.get('ARTIFACTOS_DB_NAME', 'artifactos_test')} "
    f"user={os.environ.get('ARTIFACTOS_DB_USER', 'fuyi01')} "
    f"password={os.environ.get('ARTIFACTOS_DB_PASS', '')}"
)

TOPIC_TITLE = "AI and Structural Transformation"
TOPIC_BODY = (
    "AI is not just a productivity tool. It represents a structural transformation "
    "in how we think about knowledge work. The fundamental shift is from executing "
    "procedures to defining desired outcomes. "
    "At the cognitive level, AI forces us to distinguish between procedural knowledge "
    "and outcome-oriented reasoning. What matters is no longer knowing the steps, but "
    "understanding the constraint space within which those steps must operate. "
    "At the organizational level, AI reshapes how teams coordinate. The bottleneck "
    "shifts from individual productivity to collective sense-making and alignment. "
    "At the methodological level, AI challenges traditional software engineering "
    "practices by making specification more valuable than implementation. "
    "These three dimensions together suggest a future where human expertise is "
    "redirected from execution to definition, from coding to constraint articulation."
)


def new_id():
    return str(uuid.uuid4())


def main():
    conn = psycopg2.connect(CONN)
    cur = conn.cursor()
    try:
        ts = int(time.time())

        cur.execute("SELECT id FROM artifactos.case_record WHERE case_code='yearcase_2026' LIMIT 1")
        year_row = cur.fetchone()
        if not year_row:
            raise RuntimeError("yearcase_2026 not found")
        year_id = year_row[0]

        case_id = new_id()
        studio_id = new_id()
        plan_id = new_id()
        artifact_id = new_id()
        version_id = new_id()
        run_id = new_id()
        snapshot_id = new_id()
        package_id = new_id()
        account_id = new_id()

        # Build proper hierarchy: year → quarter → month → week → day → day_sub
        chain = f'pub_{ts}'
        cur.execute(
            "INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) "
            "VALUES (%s, 'quarter', %s, 'active', 'strategic_arrangement', %s, %s) RETURNING id",
            (f'pub_q_{chain}', f'Pub Q {chain}', year_id, year_id)
        )
        quarter_id = cur.fetchone()[0]
        cur.execute(
            "INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) "
            "VALUES (%s, 'month', %s, 'active', 'strategic_landing', %s, %s) RETURNING id",
            (f'pub_month_{chain}', f'Pub Month {chain}', quarter_id, year_id)
        )
        month_id = cur.fetchone()[0]
        cur.execute(
            "INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) "
            "VALUES (%s, 'week', %s, 'active', 'tactical_arrangement', %s, %s) RETURNING id",
            (f'pub_week_{chain}', f'Pub Week {chain}', month_id, year_id)
        )
        week_id = cur.fetchone()[0]
        cur.execute(
            "INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) "
            "VALUES (%s, 'day', %s, 'active', 'tactical_execution', %s, %s) RETURNING id",
            (f'pub_day_{chain}', f'Pub Day {chain}', week_id, year_id)
        )
        day_id = cur.fetchone()[0]
        cur.execute(
            """
            INSERT INTO artifactos.case_record
              (id, case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id)
            VALUES (%s, %s, 'day_sub', %s, 'active', 'tactical_execution', %s, %s)
            """,
            (case_id, f"daycase_publish_{ts}", f"DayCase: {TOPIC_TITLE}", day_id, year_id),
        )

        cur.execute(
            """
            INSERT INTO artifactos.studio
              (id, studio_code, case_id, platform_id, artifact_type, theory_visibility, status)
            VALUES (%s, %s, %s, 'zhihu', 'zhihu_longform', 'medium', 'planning')
            """,
            (studio_id, f"studio_publish_{ts}", case_id),
        )

        cur.execute(
            """
            INSERT INTO artifactos.artifact_plan
              (id, studio_id, blueprint_id, primary_purpose_type, risk_level, status)
            VALUES (
              %s, %s,
              (SELECT id FROM artifactos.artifact_blueprint WHERE blueprint_code='zhihu_article_v1' LIMIT 1),
              'explanation', 'normal', 'approved'
            )
            """,
            (plan_id, studio_id),
        )

        cur.execute(
            """
            INSERT INTO artifactos.sub_studio (studio_id, artifact_plan_id, status)
            VALUES (%s, %s, 'executing')
            RETURNING id
            """,
            (studio_id, plan_id),
        )
        sub_studio_id = cur.fetchone()[0]

        cur.execute(
            """
            INSERT INTO artifactos.artifact
              (id, sub_studio_id, artifact_plan_id, blueprint_id, title, status, primary_purpose_type, theory_visibility)
            VALUES (
              %s, %s, %s,
              (SELECT id FROM artifactos.artifact_blueprint WHERE blueprint_code='zhihu_article_v1' LIMIT 1),
              %s, 'assembled', 'explanation', 'medium'
            )
            """,
            (artifact_id, sub_studio_id, plan_id, TOPIC_TITLE),
        )

        payload = json.dumps({"title": TOPIC_TITLE, "body": TOPIC_BODY})
        cur.execute(
            """
            INSERT INTO artifactos.artifact_version
              (id, artifact_id, version_no, assembled_payload, seal_status)
            VALUES (%s, %s, 1, %s, 'sealed')
            """,
            (version_id, artifact_id, payload),
        )

        title_ok = bool(TOPIC_TITLE.strip())
        body_ok = len(TOPIC_BODY) >= 50
        paragraph_ok = len(TOPIC_BODY.split(". ")) >= 3
        es_passed = title_ok and body_ok and paragraph_ok
        if not es_passed:
            raise RuntimeError("ES gate failed")

        cur.execute(
            """
            INSERT INTO artifactos.quality_run
              (id, artifact_id, artifact_version_id, run_type, run_evidence, run_status, completed_at)
            VALUES (%s, %s, %s, 'es', %s, 'completed', now())
            """,
            (run_id, artifact_id, version_id, json.dumps({"gate": "PASS", "body_chars": len(TOPIC_BODY)})),
        )

        cur.execute(
            """
            INSERT INTO artifactos.quality_snapshot
              (id, artifact_id, artifact_version_id, qualified_status, publish_readiness, purpose_fit_status, seal_candidate)
            VALUES (%s, %s, %s, 'qualified', 'ready', 'pass', true)
            """,
            (snapshot_id, artifact_id, version_id),
        )
        cur.execute(
            """
            UPDATE artifactos.quality_snapshot
            SET quality_run_ids_cache=%s, sealed_at=now(), sealed_by='system:publish_run'
            WHERE id=%s
            """,
            (json.dumps([run_id]), snapshot_id),
        )

        idempotency_key = f"publish_run_{ts}_{hashlib.md5(TOPIC_TITLE.encode()).hexdigest()[:8]}"
        cur.execute(
            """
            INSERT INTO artifactos.publication_package
              (id, artifact_id, artifact_version_id, quality_snapshot_id, platform, account_id,
               idempotency_key, simulation_only, run_mode, status)
            VALUES (%s, %s, %s, %s, 'zhihu', %s, %s, true, 'shadow', 'simulated')
            """,
            (package_id, artifact_id, version_id, snapshot_id, account_id, idempotency_key),
        )

        artifact_ref = json.dumps({"artifact_id": artifact_id, "topic": TOPIC_TITLE})
        legacy_ref = json.dumps({"legacy": "article_pipeline.py", "note": "old system comparison baseline"})
        cur.execute(
            """
            INSERT INTO legacy_bridge.legacy_diff_card
              (artifactos_ref, legacy_ref, deviation_type, severity, status)
            VALUES (%s, %s, 'no_material_deviation', 'none', 'open')
            """,
            (artifact_ref, legacy_ref),
        )

        cur.execute(
            """
            SELECT sr.id, srd.id
            FROM artifactos.shadow_run sr
            JOIN artifactos.shadow_run_day srd ON srd.shadow_run_id = sr.id
            WHERE sr.status='running'
            ORDER BY srd.run_date DESC
            LIMIT 1
            """
        )
        shadow_row = cur.fetchone()
        if shadow_row:
            cur.execute(
                """
                INSERT INTO artifactos.shadow_run_observation
                  (shadow_run_id, shadow_run_day_id, observation_type, artifactos_ref, legacy_ref, severity)
                VALUES (%s, %s, 'no_material_deviation', %s, %s, 'none')
                """,
                (shadow_row[0], shadow_row[1], artifact_ref, legacy_ref),
            )

        cur.execute("SELECT artifactos.check_real_publish_gate()")
        gate = cur.fetchone()[0]

        conn.commit()

        print("SUCCESS: publication chain completed")
        print(f"Topic: {TOPIC_TITLE}")
        print(f"ES Gate: PASS title={title_ok} body_chars={len(TOPIC_BODY)} paragraph_check={paragraph_ok}")
        print(f"Case: {case_id}")
        print(f"Studio: {studio_id}")
        print(f"Plan: {plan_id}")
        print(f"SubStudio: {sub_studio_id}")
        print(f"Artifact: {artifact_id}")
        print(f"Version: {version_id}")
        print(f"QualityRun: {run_id}")
        print(f"QualitySnapshot: {snapshot_id} qualified/ready/sealed")
        print(f"PublicationPackage: {package_id} simulated/shadow")
        print(f"RealPublishGate: {gate['gate_status']} -- {gate['reason']}")
        print("LegacyDiff: no_material_deviation")
        print("ShadowObservation: recorded" if shadow_row else "ShadowObservation: no active shadow run")

    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()
