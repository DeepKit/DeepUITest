#!/usr/bin/env python
"""ArtifactOS Contract Pipeline Smoke Test.

Validates the minimum RSC/CTF/Contract chain:
  RequirementFrame -> ContentSpecSnapshot -> ContractCandidate -> ArtifactContract
  -> SubStudioExecutionTask(spec_status='contracted')

Target: artifactos_test. All test data is rolled back.
"""

import os
import sys
import uuid
import json
import psycopg2
from dotenv import load_dotenv

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

    def ok(msg):
        nonlocal passed
        passed += 1
        print(f"  PASS {msg}")

    def fail(msg):
        nonlocal failed
        failed += 1
        print(f"  FAIL {msg}")

    conn = psycopg2.connect(CONN)
    conn.autocommit = False
    cur = conn.cursor()

    try:
        chain = str(uuid.uuid4())[:8]

        # 1. RequirementFrame: raw idea becomes a traceable RSC frame.
        cur.execute(
            """
            insert into artifactos.requirement_frame (
              topic, intent, target_account, target_platform, entry_mode,
              theory_intervention_level, target_reader, success_result,
              in_scope, non_goals, unresolved, rsc_status, review_status, payload
            ) values (
              %s, %s, %s::jsonb, %s::jsonb, 'theory_driven',
              'medium', %s, %s, %s::jsonb, %s::jsonb, %s::jsonb,
              'ready_for_ctf', 'accepted', %s::jsonb
            ) returning id
            """,
            (
                f"Contract Pipeline Smoke {chain}",
                "Create a minimal traceable ArtifactOS contract pipeline smoke article.",
                json.dumps({"status": "confirmed", "value": "sub"}),
                json.dumps({"status": "confirmed", "value": "zhihu"}),
                "ArtifactOS developer",
                "Reader understands why contract-first writing prevents drift.",
                json.dumps(["contract pipeline", "traceability"]),
                json.dumps(["real publishing", "external network calls"]),
                json.dumps([]),
                json.dumps({"raw_idea": "contract pipeline smoke"}),
            ),
        )
        rf_id = cur.fetchone()[0]
        ok("RequirementFrame created")

        # 2. ContentSpecSnapshot: CTF freezes a release-level spec snapshot.
        cur.execute(
            """
            insert into artifactos.content_spec_snapshot (
              requirement_frame_id, gen_status, review_status, snapshot_status,
              semantic_bundles, content_hash, source_hashes, accept_level,
              evidence_coverage, stale_status, payload
            ) values (
              %s, 'generated', 'accepted', 'frozen', %s::jsonb,
              'sha256:contract-pipeline-smoke', %s::jsonb, 'release',
              0.750, 'fresh', %s::jsonb
            ) returning id
            """,
            (
                rf_id,
                json.dumps([
                    {
                        "bundle_id": "bnd_contract_pipeline_smoke",
                        "label": "Contract-first writing skeleton",
                        "evidence_status": "sufficient",
                        "review_status": "accepted",
                    }
                ]),
                json.dumps(["rf:sha256:contract-pipeline-smoke"]),
                json.dumps({"snapshot": "minimal release spec"}),
            ),
        )
        snapshot_id = cur.fetchone()[0]
        ok("ContentSpecSnapshot frozen")

        # 3. ContractCandidate: ready candidate can become a formal contract.
        cur.execute(
            """
            insert into artifactos.contract_candidate (
              source_spec_snapshot_id, status, suggested_must_land,
              suggested_taboos, suggested_word_count, suggested_style,
              strategy_recommendation, payload
            ) values (
              %s, 'ready', %s::jsonb, %s::jsonb, %s::jsonb,
              'clear_engineering_note', %s::jsonb, %s::jsonb
            ) returning id
            """,
            (
                snapshot_id,
                json.dumps(["Explain RSC", "Explain CTF", "Explain ArtifactContract"]),
                json.dumps(["Do not publish", "Do not call external services"]),
                json.dumps([800, 1200]),
                json.dumps({
                    "action": "write_now",
                    "autonomy_level": "AL2",
                    "max_rewrite": 1,
                    "publish_policy": "store_draft",
                }),
                json.dumps({"candidate": "minimal ready contract candidate"}),
            ),
        )
        candidate_id = cur.fetchone()[0]
        ok("ContractCandidate ready")

        # 4. ArtifactContract: approved contract references the entire source chain.
        contract_code = f"ctr_smoke_{chain}"
        cur.execute(
            """
            insert into artifactos.artifact_contract (
              contract_code, contract_type, maturity, version_no, status,
              requirement_frame_id, source_spec_snapshot_id, contract_candidate_id,
              source, strategy, directive, structure, constraints_json, quality, asto, odd, payload
            ) values (
              %s, 'full_contract', 'agreed', 1, 'approved',
              %s, %s, %s,
              %s::jsonb, %s::jsonb, %s::jsonb, %s::jsonb,
              %s::jsonb, %s::jsonb, %s::jsonb, %s::jsonb, %s::jsonb
            ) returning id
            """,
            (
                contract_code,
                rf_id,
                snapshot_id,
                candidate_id,
                json.dumps({
                    "requirement_frame_id": str(rf_id),
                    "source_spec_snapshot_id": str(snapshot_id),
                    "contract_candidate_id": str(candidate_id),
                    "contract_candidate_status": "ready",
                    "accept_level": "release",
                    "evidence_coverage": 0.75,
                    "stale_status": "fresh",
                }),
                json.dumps({
                    "autonomy_level": "AL2",
                    "generation_mode": "delegate",
                    "entry_mode": "theory_driven",
                    "max_rewrite": 1,
                    "on_pass": "store_draft",
                }),
                json.dumps({
                    "topic": f"Contract Pipeline Smoke {chain}",
                    "target_platform": "zhihu",
                    "target_account": "sub",
                }),
                json.dumps({
                    "must_land": ["RSC", "CTF", "ArtifactContract"],
                    "suggested_structure": "problem -> chain -> verification",
                }),
                json.dumps({"word_count": {"min": 800, "max": 1200}}),
                json.dumps({"acceptance_criteria": ["contract chain is traceable"]}),
                json.dumps({"state": "draft", "actor": "system"}),
                json.dumps({"validation_gates": ["schema_check"], "seal_required_before_publish": True}),
                json.dumps({"contract": "minimal approved contract"}),
            ),
        )
        contract_id = cur.fetchone()[0]
        ok("ArtifactContract approved")

        # 5. Task can reference the real contract and enter contracted state.
        cur.execute(
            """
            insert into artifactos.substudio_execution_task (
              pipeline_status, quality_status, publish_status, spec_status,
              requirement_frame_id, spec_snapshot_id, contract_candidate_id,
              artifact_contract_id, contract_id
            ) values (
              'contracting', 'pending', 'pending', 'contracted',
              %s, %s, %s, %s, %s
            ) returning id
            """,
            (rf_id, snapshot_id, candidate_id, contract_id, contract_id),
        )
        task_id = cur.fetchone()[0]
        ok(f"SubStudioExecutionTask contracted: {task_id}")

        # 6. Guard: contracted task without a contract is rejected.
        try:
            cur.execute(
                """
                insert into artifactos.substudio_execution_task (
                  pipeline_status, quality_status, publish_status, spec_status
                ) values ('contracting', 'pending', 'pending', 'contracted')
                """
            )
            fail("contract guard should reject contracted task without contract")
        except Exception:
            conn.rollback()
            conn = psycopg2.connect(CONN)
            conn.autocommit = False
            cur = conn.cursor()
            ok("contract guard rejects contracted task without contract")

        conn.rollback()
    finally:
        try:
            conn.rollback()
            cur.close()
            conn.close()
        except Exception:
            pass

    if failed:
        print(f"\nFAILED: {failed} failure(s), {passed} pass(es)")
        sys.exit(1)

    print(f"\nPASSED: {passed} checks")


if __name__ == '__main__':
    main()
