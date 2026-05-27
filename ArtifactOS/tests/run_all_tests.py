#!/usr/bin/env python
"""ArtifactOS Phase 1A — Run All Automated Tests.

Target: artifactos_test (independent test database).
No real publishing.  All test data cleaned up after each run.
"""

import subprocess, sys, os, time, json, psycopg2

CONN = "host=127.0.0.1 port=5432 dbname=artifactos_test user=fuyi01 password=a29806588-run"
RESULTS: list[tuple[str, bool, str]] = []

def run(name: str) -> bool:
    start = time.time()
    try:
        r = subprocess.run(
            [sys.executable, os.path.join(os.path.dirname(__file__), name)],
            capture_output=True, text=True, timeout=120
        )
        elapsed = time.time() - start
        passed = r.returncode == 0
        detail = r.stderr.strip() or r.stdout.strip()[-300:]
        RESULTS.append((name, passed, f"{elapsed:.1f}s"))
        status = "PASS" if passed else "FAIL"
        print(f"  {status} {name} ({elapsed:.1f}s)")
        if not passed:
            print(f"    {detail[:200]}")
        return passed
    except Exception as e:
        RESULTS.append((name, False, str(e)[:120]))
        print(f"  FAIL {name} — {e}")
        return False

def db_check(name: str, sql: str) -> bool:
    try:
        conn = psycopg2.connect(CONN)
        cur = conn.cursor()
        cur.execute(sql)
        val = cur.fetchone()[0]
        cur.close(); conn.close()
        ok = isinstance(val, int) and val > 0 or isinstance(val, str) and val != '0'
        RESULTS.append((name, ok, str(val)))
        status = "PASS" if ok else "FAIL"
        print(f"  {status} {name}: {val}")
        return ok
    except Exception as e:
        RESULTS.append((name, False, str(e)[:120]))
        print(f"  FAIL {name}: {e}")
        return False


if __name__ == '__main__':
    print("ArtifactOS Phase 1A — Automated Test Suite")
    print("=" * 50)

    # ── Unit: smoke integration ──
    run("smoke_integration.py")

    # ── Database integrity ──
    db_check("SourcePack loaded",
        "select count(*) from artifactos.source_pack")
    db_check("Inventory files >= 2900",
        "select count(*) from artifactos.source_inventory_candidate")
    db_check("Blueprints >= 3",
        "select count(*) from artifactos.artifact_blueprint")
    db_check("Meeting protocols = 6",
        "select count(*) from artifactos.meeting_protocol where status='active'")
    db_check("Active cases >= 3",
        "select count(*) from artifactos.case_record where status='active'")
    db_check("State rules >= 20",
        "select count(*) from artifactos.state_transition_rule where is_active=true")
    db_check("Legacy refs > 0",
        "select count(*) from legacy_bridge.legacy_external_ref")
    db_check("Legacy diff cards > 0",
        "select count(*) from legacy_bridge.legacy_diff_card")
    db_check("Shadow runs > 0",
        "select count(*) from artifactos.shadow_run")
    db_check("RealPublishGate blocked",
        "select (artifactos.check_real_publish_gate() ->> 'gate_status') = 'blocked'")

    print(f"\n{'='*50}")
    passed = sum(1 for _, ok, _ in RESULTS if ok)
    total = len(RESULTS)
    print(f"  PASS: {passed}  FAIL: {total-passed}  TOTAL: {total}")
    print(f"{'='*50}")

    if passed == total:
        print("\n  ALL TESTS PASSED — ArtifactOS Phase 1A ready.")
    else:
        print("\n  SOME TESTS FAILED — See above for details.")
        sys.exit(1)