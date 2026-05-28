#!/usr/bin/env python
"""ArtifactOS Phase 1A — Full State Machine Coverage Test

Tests all legal state combos and blocking flags defined in
db/migrations/011_substudio_execution_task.sql
"""

import psycopg2, os, json, sys

CONN = f"host={os.environ.get('ARTIFACTOS_DB_HOST','127.0.0.1')} port={os.environ.get('ARTIFACTOS_DB_PORT','5432')} dbname={os.environ.get('ARTIFACTOS_DB_NAME','artifactos_test')} user={os.environ.get('ARTIFACTOS_DB_USER','fuyi01')} password={os.environ.get('ARTIFACTOS_DB_PASS','')}"

passed = 0
failed = 0

def test(name, sql, expect_ok=True):
    global passed, failed
    conn = psycopg2.connect(CONN)
    cur = conn.cursor()
    try:
        cur.execute(sql)
        conn.rollback()
        if expect_ok:
            passed += 1; print(f"  PASS {name}")
        else:
            failed += 1; print(f"  FAIL {name}: should have rejected but passed")
    except Exception as e:
        conn.rollback()
        if not expect_ok:
            passed += 1; print(f"  PASS {name} (rejected as expected)")
        else:
            failed += 1; print(f"  FAIL {name}: {str(e)[:100]}")
    finally:
        cur.close(); conn.close()

def ins(pipeline, quality='pending', publish='pending'):
    return f"INSERT INTO artifactos.substudio_execution_task (pipeline_status, quality_status, publish_status) VALUES ('{pipeline}', '{quality}', '{publish}')"

# === Normal progression ===
print("Normal progression:")
test("pending", ins('pending'))
test("contracting", ins('contracting'))
test("drafting", ins('drafting'))
for q in ['structure_checking','structure_passed','es_checking','es_passed','ses_checking','ses_passed','ses_warned','strategy_decision','passed','sample_review','rework','waiting_human','stored']:
    test(f"reviewing x {q}", ins('reviewing', q))
test("approved x passed x pending", ins('approved','passed','pending'))
test("approved x passed x scheduled", ins('approved','passed','scheduled'))
for p in ['scheduled','publishing','published','failed']:
    test(f"publishing x passed x {p}", ins('publishing','passed', p))
test("published x passed x published", ins('published','passed','published'))
test("collecting x passed x published", ins('collecting','passed','published'))
test("completed x passed x published", ins('completed','passed','published'))

# === Exception combos ===
print("\nException combos:")
test("frozen (any quality/pub)", ins('frozen','pending','pending'))
test("frozen x rework x failed", ins('frozen','rework','failed'))
test("waiting_human (any)", ins('waiting_human','pending','pending'))
test("waiting_human x passed x published", ins('waiting_human','passed','published'))
test("stored x skipped", ins('stored','pending','skipped'))
test("stored x stored", ins('stored','stored','pending'))
test("draft_only (any)", ins('draft_only','pending','pending'))
test("draft_only x passed x skipped", ins('draft_only','passed','skipped'))
test("not_writing (any)", ins('not_writing','pending','pending'))
test("not_writing x passed x recalled", ins('not_writing','passed','recalled'))
test("abandoned (any)", ins('abandoned','pending','pending'))
test("abandoned x pending x published", ins('abandoned','pending','published'))
for ps in ['published','collecting','completed']:
    test(f"{ps} x passed x recalled", ins(ps,'passed','recalled'))

# === Illegal combos ===
print("\nIllegal combos (must be rejected):")
illegals = [
    ('drafting', 'passed', 'pending'),
    ('drafting', 'pending', 'published'),
    ('pending', 'pending', 'published'),
    ('pending', 'passed', 'scheduled'),
    ('approved', 'pending', 'scheduled'),
    ('approved', 'passed', 'published'),
    ('publishing', 'pending', 'published'),
    ('publishing', 'passed', 'recalled'),
    ('published', 'pending', 'published'),
    ('collecting', 'pending', 'published'),
    ('completed', 'pending', 'published'),
    ('stored', 'pending', 'published'),
    ('stored', 'passed', 'recalled'),
]
for pv, qv, sv in illegals:
    test(f"ILLEGAL {pv} x {qv} x {sv}", ins(pv, qv, sv), expect_ok=False)

# === Flags ===
print("\nFlag validation:")
# none of these are blocked at DB level currently — verify they can be set
for flag in ['checking','ai_working','human_override','evidence_gap','cognitive_disturbance','algorithm_noise']:
    test(f"flag_{flag} can be set",
         f"INSERT INTO artifactos.substudio_execution_task (pipeline_status, quality_status, publish_status, flags) VALUES ('pending','pending','pending','{{\"{flag}\":true}}'::jsonb)")

print(f"\n{'='*50}")
print(f"  PASS: {passed}  FAIL: {failed}  TOTAL: {passed+failed}")
print(f"{'='*50}")
sys.exit(0 if failed == 0 else 1)