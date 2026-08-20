#!/usr/bin/env python
"""ArtifactOS Migration Runner.

Applies SQL migrations in numbered order to artifactos_test.
Tracks applied migrations in a dedicated tracking table.

Usage:
    python db/migrate.py              # Apply all pending migrations
    python db/migrate.py --status     # Show migration status
    python db/migrate.py --dry-run    # Show what would be applied, no changes
    python db/migrate.py --target N   # Apply up to migration N only
    python db/migrate.py --rebuild    # Drop & recreate schema, then apply all

Target database: artifactos_test (never operates on production).
The migration tracking table lives in the 'artifactos' schema.
"""

import argparse
import os
import re
import sys
import time

import psycopg2
from dotenv import load_dotenv

# Load .env from project root
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'), override=True)

MIGRATIONS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'migrations')

DB_NAME = os.environ.get('ARTIFACTOS_DB_NAME', 'artifactos_test')
DB_USER = os.environ.get('ARTIFACTOS_DB_USER', 'fuyi01')
DB_PASS = os.environ.get('ARTIFACTOS_DB_PASS', '')
DB_HOST = os.environ.get('ARTIFACTOS_DB_HOST', '127.0.0.1')
DB_PORT = os.environ.get('ARTIFACTOS_DB_PORT', '5432')

TRACKING_TABLE = 'artifactos._migration_log'

# Safety: refuse to run against non-test databases unless forced
SAFE_DB_NAMES = {'artifactos_test'}


def get_connection(dbname=None):
    """Create a psycopg2 connection, then switch server messages to English
    so UTF-8 decoding of PG error strings doesn't choke on a Chinese (GBK)
    lc_messages locale."""
    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        dbname=dbname or DB_NAME,
        user=DB_USER, password=DB_PASS,
    )
    try:
        with conn.cursor() as cur:
            cur.execute('SET lc_messages = "english"')
        conn.commit()
    except Exception:
        pass
    return conn


def ensure_tracking_table(conn):
    """Create the migration tracking table if it doesn't exist."""
    cur = conn.cursor()
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {TRACKING_TABLE} (
            migration_no  INTEGER PRIMARY KEY,
            filename      TEXT NOT NULL,
            applied_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
            applied_by    TEXT NOT NULL DEFAULT current_user,
            checksum      TEXT,
            execution_ms  INTEGER
        );
        COMMENT ON TABLE {TRACKING_TABLE} IS
            'ArtifactOS migration tracking. Managed by db/migrate.py.';
    """)
    conn.commit()
    cur.close()


def get_applied_migrations(conn):
    """Return a set of already-applied migration numbers."""
    cur = conn.cursor()
    try:
        cur.execute(f"SELECT migration_no FROM {TRACKING_TABLE} ORDER BY migration_no")
        return {row[0] for row in cur.fetchall()}
    except psycopg2.errors.UndefinedTable:
        conn.rollback()
        ensure_tracking_table(conn)
        return set()
    finally:
        cur.close()


def discover_migrations():
    """Discover migration files, return sorted list of (number, filepath)."""
    pattern = re.compile(r'^(\d{3})_.*\.sql$')
    migrations = []
    for fname in os.listdir(MIGRATIONS_DIR):
        m = pattern.match(fname)
        if m:
            migrations.append((int(m.group(1)), os.path.join(MIGRATIONS_DIR, fname)))
    migrations.sort()
    return migrations


def sha256_file(filepath):
    """Compute SHA-256 of a file, return hex digest."""
    import hashlib
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()


def check_prerequisites(conn):
    """Check that the artifactos schema exists."""
    cur = conn.cursor()
    cur.execute("""
        SELECT COUNT(*) FROM information_schema.schemata
        WHERE schema_name IN ('artifactos', 'media_publish', 'legacy_bridge')
    """)
    count = cur.fetchone()[0]
    cur.close()
    return count >= 1  # At least artifactos must exist for fresh start


def apply_single_migration(conn, number, filepath, dry_run=False):
    """Apply one migration file. Returns True on success."""
    filename = os.path.basename(filepath)
    checksum = sha256_file(filepath)

    with open(filepath, 'r', encoding='utf-8') as f:
        sql_content = f.read()

    if dry_run:
        print(f"    DRY-RUN  {filename}")
        return True

    start = time.time()
    cur = conn.cursor()
    try:
        # Run the raw SQL as-is. Connection is autocommit=True so the
        # migration's own BEGIN/COMMIT (if any) are handled by PostgreSQL.
        cur.execute(sql_content)

        elapsed_ms = int((time.time() - start) * 1000)

        # Record in tracking table (autocommit, so this commits immediately)
        cur.execute(f"""
            INSERT INTO {TRACKING_TABLE} (migration_no, filename, checksum, execution_ms)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (migration_no) DO UPDATE SET
                filename = EXCLUDED.filename,
                applied_at = now(),
                checksum = EXCLUDED.checksum,
                execution_ms = EXCLUDED.execution_ms
        """, (number, filename, checksum, elapsed_ms))

        print(f"    APPLY    {filename}  ({elapsed_ms}ms)")
        return True
    except Exception as e:
        print(f"    FAIL     {filename}")
        print(f"             {e}")
        return False
    finally:
        cur.close()


def run_migrations(target=None, dry_run=False):
    """Apply pending migrations up to target number."""
    if DB_NAME not in SAFE_DB_NAMES:
        print(f"ERROR: Target database is '{DB_NAME}', which is not in the safe list: {SAFE_DB_NAMES}")
        print("Set ARTIFACTOS_DB_NAME=artifactos_test or use --force to override.")
        sys.exit(1)

    conn = get_connection()
    conn.autocommit = True

    # Ensure schemas exist for tracking table
    cur = conn.cursor()
    cur.execute("CREATE SCHEMA IF NOT EXISTS artifactos")
    cur.execute("CREATE SCHEMA IF NOT EXISTS media_publish")
    cur.execute("CREATE SCHEMA IF NOT EXISTS legacy_bridge")
    conn.commit()
    cur.close()

    ensure_tracking_table(conn)

    applied = get_applied_migrations(conn)
    discovered = discover_migrations()

    pending = [(n, fp) for n, fp in discovered if n not in applied]
    if target is not None:
        pending = [(n, fp) for n, fp in pending if n <= target]

    if not pending:
        print(f"All migrations applied. Latest: {max(applied) if applied else 'none'}/{max(d[0] for d in discovered) if discovered else 0}")
        conn.close()
        return True

    total = len(pending)
    print(f"Pending migrations: {total}")
    print(f"  from: {pending[0][0]:03d}")
    print(f"  to:   {pending[-1][0]:03d}")
    print()

    # Run with autocommit=True so migration's own BEGIN/COMMIT work correctly.
    success = True
    for i, (number, filepath) in enumerate(pending):
        ok = apply_single_migration(conn, number, filepath, dry_run)
        if not ok:
            success = False
            break

    conn.close()

    if success and not dry_run:
        print(f"\nDone. {total} migration(s) applied.")
    elif not success:
        print(f"\nStopped at migration {number}. Fix and re-run.")
        sys.exit(1)

    return success


def show_status():
    """Show migration status."""
    conn = get_connection()
    conn.autocommit = True
    ensure_tracking_table(conn)
    applied = get_applied_migrations(conn)
    discovered = discover_migrations()
    cur = conn.cursor()

    print(f"Database: {DB_NAME}@{DB_HOST}:{DB_PORT}")
    print(f"Migrations dir: {MIGRATIONS_DIR}")
    print()
    print(f"{'No':>4}  {'Status':<10}  {'Filename':<50}  {'Applied':<20}  {'ms':>5}")
    print("-" * 100)

    for number, filepath in discovered:
        filename = os.path.basename(filepath)
        if number in applied:
            cur.execute(f"""
                SELECT applied_at::text, execution_ms
                FROM {TRACKING_TABLE}
                WHERE migration_no = %s
            """, (number,))
            row = cur.fetchone()
            applied_at = row[0][:19] if row else '?'
            exec_ms = row[1] if row else '?'
            print(f"{number:>4}  {'APPLIED':<10}  {filename:<50}  {applied_at:<20}  {exec_ms:>5}")
        else:
            print(f"{number:>4}  {'PENDING':<10}  {filename:<50}")

    cur.close()
    conn.close()

    applied_count = len(applied)
    total_count = len(discovered)
    print()
    print(f"Applied: {applied_count}/{total_count}")
    if applied_count < total_count:
        print(f"Pending: {total_count - applied_count}")


def rebuild():
    """Drop and recreate schemas, then apply all migrations from scratch."""
    if DB_NAME not in SAFE_DB_NAMES:
        print(f"ERROR: Refusing to rebuild non-test database '{DB_NAME}'.")
        sys.exit(1)

    print(f"WARNING: This will DROP the following schemas in '{DB_NAME}':")
    print("  artifactos, media_publish, legacy_bridge")
    confirm = input("Type 'yes' to proceed: ")
    if confirm.strip().lower() != 'yes':
        print("Aborted.")
        return

    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    print("Dropping schemas...")
    for schema in ['artifactos', 'media_publish', 'legacy_bridge']:
        cur.execute(f"DROP SCHEMA IF EXISTS {schema} CASCADE")
    conn.commit()

    print("Schemas dropped. Re-applying all migrations...")
    cur.close()
    conn.close()

    run_migrations()


def main():
    parser = argparse.ArgumentParser(description='ArtifactOS Migration Runner')
    parser.add_argument('--status', action='store_true', help='Show migration status')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be applied')
    parser.add_argument('--target', type=int, help='Apply up to migration N only')
    parser.add_argument('--rebuild', action='store_true', help='Drop schemas and re-apply all')
    parser.add_argument('--force', action='store_true', help='Allow running on non-test database')
    args = parser.parse_args()

    if args.force:
        SAFE_DB_NAMES.add(DB_NAME)

    if args.status:
        show_status()
    elif args.rebuild:
        rebuild()
    else:
        run_migrations(target=args.target, dry_run=args.dry_run)


if __name__ == '__main__':
    main()
