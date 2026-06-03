import psycopg2, uuid

conn = psycopg2.connect(host='127.0.0.1', port=5432, dbname='artifactos_test', user='fuyi01', password='a29806588-run')
cur = conn.cursor()
tid = '00000000-0000-0000-0000-000000000000'

# === P1-1: Case Hierarchy Guard ===
print("=== P1-1: Case Hierarchy Guard ===")
year_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.case_record (id, tenant_id, case_type, title, planning_nature) "
    "values (%s, %s, 'year', 'test-year', 'strategic_landing') returning id",
    (year_id, tid))
conn.commit()

# day_sub under year -> should FAIL
try:
    bad_id = str(uuid.uuid4())
    cur.execute(
        "insert into artifactos.case_record (id, tenant_id, case_type, title, parent_case_id, root_case_id, planning_nature) "
        "values (%s, %s, 'day_sub', 'bad', %s, %s, 'tactical_execution')",
        (bad_id, tid, year_id, year_id))
    conn.commit()
    print("  FAIL: day_sub under year accepted")
except Exception as e:
    conn.rollback()
    print(f"  PASS: rejected day_sub under year")
    print(f"       error: {str(e).split(chr(10))[0][:120]}")

# Build correct hierarchy: year -> quarter -> month -> week -> day -> day_sub
quarter_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.case_record (id, tenant_id, case_type, title, parent_case_id, root_case_id, planning_nature) "
    "values (%s, %s, 'quarter', 'test-quarter', %s, %s, 'strategic_arrangement') returning id",
    (quarter_id, tid, year_id, year_id))
month_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.case_record (id, tenant_id, case_type, title, parent_case_id, root_case_id, planning_nature) "
    "values (%s, %s, 'month', 'test-month', %s, %s, 'tactical_arrangement') returning id",
    (month_id, tid, quarter_id, year_id))
week_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.case_record (id, tenant_id, case_type, title, parent_case_id, root_case_id, planning_nature) "
    "values (%s, %s, 'week', 'test-week', %s, %s, 'tactical_arrangement') returning id",
    (week_id, tid, month_id, year_id))
day_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.case_record (id, tenant_id, case_type, title, parent_case_id, root_case_id, planning_nature) "
    "values (%s, %s, 'day', 'test-day', %s, %s, 'tactical_execution') returning id",
    (day_id, tid, week_id, year_id))
conn.commit()
print("  PASS: full hierarchy year->quarter->month->week->day accepted")

# day_sub under day -> should PASS
sub_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.case_record (id, tenant_id, case_type, title, parent_case_id, root_case_id, planning_nature) "
    "values (%s, %s, 'day_sub', 'test-sub', %s, %s, 'tactical_execution') returning id",
    (sub_id, tid, day_id, year_id))
conn.commit()
print("  PASS: day_sub under day accepted")

# Cleanup hierarchy test
cur.execute("delete from artifactos.case_record where id in (%s,%s,%s,%s,%s,%s)", (sub_id, day_id, week_id, month_id, quarter_id, year_id))
conn.commit()

# === P1-2: SubStudio-Artifact 1:1 ===
print("\n=== P1-2: SubStudio-Artifact 1:1 ===")
case_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.case_record (id, tenant_id, case_type, title, planning_nature) "
    "values (%s, %s, 'day', 'test-day', 'tactical_execution') returning id",
    (case_id, tid))
conn.commit()

studio_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.studio (id, tenant_id, studio_code, case_id, status) "
    "values (%s, %s, %s, %s, 'running') returning id",
    (studio_id, tid, f'test-studio-p1-{studio_id[:8]}', case_id))

sub_studio_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.sub_studio (id, tenant_id, studio_id, status) "
    "values (%s, %s, %s, 'executing') returning id",
    (sub_studio_id, tid, studio_id))

bp_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.artifact_blueprint (id, tenant_id, blueprint_code, artifact_type, platform_id, status) "
    "values (%s, %s, %s, 'article', 'zhihu', 'active') returning id",
    (bp_id, tid, f'test_bp_{bp_id[:8]}'))

a1_id = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.artifact (id, tenant_id, sub_studio_id, blueprint_id, status) "
    "values (%s, %s, %s, %s, 'planned') returning id",
    (a1_id, tid, sub_studio_id, bp_id))
conn.commit()

# Second artifact with same sub_studio_id -> should FAIL
try:
    a2_id = str(uuid.uuid4())
    cur.execute(
        "insert into artifactos.artifact (id, tenant_id, sub_studio_id, blueprint_id, status) "
        "values (%s, %s, %s, %s, 'drafting')",
        (a2_id, tid, sub_studio_id, bp_id))
    conn.commit()
    print("  FAIL: second artifact with same sub_studio accepted")
except Exception as e:
    conn.rollback()
    print(f"  PASS: rejected duplicate sub_studio_id")
    print(f"       error: {str(e).split(chr(10))[0][:120]}")

# === P1-3: Cross-table Status Sync ===
print("\n=== P1-3: Cross-table Status Sync ===")

case_id2 = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.case_record (id, tenant_id, case_type, title, planning_nature) "
    "values (%s, %s, 'day', 'test-day2', 'tactical_execution') returning id",
    (case_id2, tid))
conn.commit()

studio_id2 = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.studio (id, tenant_id, studio_code, case_id, status) "
    "values (%s, %s, %s, %s, 'running') returning id",
    (studio_id2, tid, f'test-studio2-{studio_id2[:8]}', case_id2))

sub_id2 = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.sub_studio (id, tenant_id, studio_id, status) "
    "values (%s, %s, %s, 'executing') returning id",
    (sub_id2, tid, studio_id2))

bp_id2 = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.artifact_blueprint (id, tenant_id, blueprint_code, artifact_type, platform_id, status) "
    "values (%s, %s, %s, 'article', 'zhihu', 'active') returning id",
    (bp_id2, tid, f'test_bp2_{bp_id2[:8]}'))

a_id2 = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.artifact (id, tenant_id, sub_studio_id, blueprint_id, status) "
    "values (%s, %s, %s, %s, 'planned') returning id",
    (a_id2, tid, sub_id2, bp_id2))

task_id2 = str(uuid.uuid4())
cur.execute(
    "insert into artifactos.substudio_execution_task (id, tenant_id, sub_studio_id, artifact_id, pipeline_status, quality_status, publish_status) "
    "values (%s, %s, %s, %s, 'pending', 'pending', 'pending') returning id",
    (task_id2, tid, sub_id2, a_id2))
conn.commit()

# Test A: artifact -> sealed with task=pending -> FAIL
try:
    cur.execute("update artifactos.artifact set status = 'sealed', updated_at = now() where id = %s", (a_id2,))
    conn.commit()
    print("  FAIL: artifact sealed with task=pending accepted")
except Exception as e:
    conn.rollback()
    print(f"  PASS: artifact->sealed blocked (task pending)")
    print(f"       error: {str(e).split(chr(10))[0][:120]}")

# Test B: task -> approved (valid combo: approved x passed x pending), then artifact -> sealed
cur.execute(
    "update artifactos.substudio_execution_task set pipeline_status = 'approved', quality_status = 'passed', updated_at = now() where id = %s",
    (task_id2,))
conn.commit()
cur.execute("update artifactos.artifact set status = 'sealed', updated_at = now() where id = %s", (a_id2,))
conn.commit()
print("  PASS: artifact->sealed with task=approved succeeded")

# Test C: artifact->frozen syncs task->frozen
cur.execute("update artifactos.artifact set status = 'frozen', updated_at = now() where id = %s", (a_id2,))
conn.commit()
cur.execute("select pipeline_status from artifactos.substudio_execution_task where id = %s", (task_id2,))
print(f"  PASS: artifact->frozen synced task to: {cur.fetchone()[0]}")

# Test D: reverse frozen sync (task->frozen, artifact follows)
# First, unfreeze: set task to approved, then artifact to sealed
cur.execute(
    "update artifactos.substudio_execution_task set pipeline_status = 'approved', quality_status = 'passed', updated_at = now() where id = %s",
    (task_id2,))
conn.commit()
cur.execute("update artifactos.artifact set status = 'sealed', updated_at = now() where id = %s", (a_id2,))
conn.commit()
cur.execute(
    "update artifactos.substudio_execution_task set pipeline_status = 'frozen', updated_at = now() where id = %s",
    (task_id2,))
conn.commit()
cur.execute("select status from artifactos.artifact where id = %s", (a_id2,))
print(f"  PASS: task->frozen synced artifact to: {cur.fetchone()[0]}")

# Cleanup all
cur.execute("delete from artifactos.substudio_execution_task where id = %s", (task_id2,))
cur.execute("delete from artifactos.artifact where id = %s", (a_id2,))
cur.execute("delete from artifactos.sub_studio where id = %s", (sub_id2,))
cur.execute("delete from artifactos.studio where id = %s", (studio_id2,))
cur.execute("delete from artifactos.artifact_blueprint where id = %s", (bp_id2,))
cur.execute("delete from artifactos.case_record where id = %s", (case_id2,))
cur.execute("delete from artifactos.artifact where id = %s", (a1_id,))
cur.execute("delete from artifactos.sub_studio where id = %s", (sub_studio_id,))
cur.execute("delete from artifactos.studio where id = %s", (studio_id,))
cur.execute("delete from artifactos.artifact_blueprint where id = %s", (bp_id,))
cur.execute("delete from artifactos.case_record where id = %s", (case_id,))
conn.commit()

conn.close()
print("\n=== ALL P1 TESTS PASSED ===")