#!/usr/bin/env python
"""ArtifactOS pre-development readiness check.

Read-only checks for local development prerequisites. It never applies migrations,
starts browsers, or triggers publishing.
"""

from __future__ import annotations

import importlib.util
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def load_dotenv() -> None:
    env_path = ROOT / ".env"
    if not env_path.exists():
        return
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and value and key not in os.environ:
            os.environ[key] = value


load_dotenv()

DB_ENV = {
    "ARTIFACTOS_DB_HOST": os.environ.get("ARTIFACTOS_DB_HOST", "127.0.0.1"),
    "ARTIFACTOS_DB_PORT": os.environ.get("ARTIFACTOS_DB_PORT", "5432"),
    "ARTIFACTOS_DB_NAME": os.environ.get("ARTIFACTOS_DB_NAME", "artifactos_test"),
    "ARTIFACTOS_DB_USER": os.environ.get("ARTIFACTOS_DB_USER", "fuyi01"),
    "ARTIFACTOS_DB_PASS": os.environ.get("ARTIFACTOS_DB_PASS", ""),
}

MIGRATION_MIN = 28


class Report:
    def __init__(self) -> None:
        self.rows: list[tuple[str, bool, str]] = []

    def ok(self, name: str, detail: str = "") -> None:
        self.rows.append((name, True, detail))
        print(f"[OK]   {name}{_suffix(detail)}")

    def fail(self, name: str, detail: str = "") -> None:
        self.rows.append((name, False, detail))
        print(f"[FAIL] {name}{_suffix(detail)}")

    def warn(self, name: str, detail: str = "") -> None:
        self.rows.append((name, True, f"WARN: {detail}"))
        print(f"[WARN] {name}{_suffix(detail)}")

    def exit_code(self) -> int:
        return 0 if all(ok for _, ok, _ in self.rows) else 1


def _suffix(detail: str) -> str:
    return f" - {detail}" if detail else ""


def _exists(path: str) -> bool:
    return (ROOT / path).exists()


def _conn_string() -> str:
    return " ".join(
        [
            f"host={DB_ENV['ARTIFACTOS_DB_HOST']}",
            f"port={DB_ENV['ARTIFACTOS_DB_PORT']}",
            f"dbname={DB_ENV['ARTIFACTOS_DB_NAME']}",
            f"user={DB_ENV['ARTIFACTOS_DB_USER']}",
            f"password={DB_ENV['ARTIFACTOS_DB_PASS']}",
        ]
    )


def check_files(report: Report) -> None:
    required = [
        "README.md",
        "DEVELOPMENT.md",
        ".env.example",
        "requirements.txt",
        "tasks.md",
        "build.bat",
        "docs/02.[蓝图]-系统架构-Architecture.md",
        "docs/03.[蓝图]-实施路线图-Roadmap.md",
        "docs/13.[流程]-多平台发布-Publishing.md",
        "docs/15.[交互]-Amy工作台-Amy-Desk.md",
        "docs/17.[交互]-前夜审阅与影子运行-Evening-Shadow.md",
        "docs/24.[数据]-数据库模型与治理-Database.md",
        "docs/26.[技术]-技术选型与运行时架构-Stack-Decision.md",
        "db/migrations/028_artifactos_runtime_command.sql",
        "config/phase1a/day0_dry_run_report.md",
        "config/phase1a/shadow_run_7d_checklist.md",
        "backend/amy_desk.py",
        "backend/diagnostics/publishing_runtime_bridge.py",
        "tests/run_all_tests.py",
        "tests/test_runtime_command_contract.py",
    ]
    missing = [path for path in required if not _exists(path)]
    if missing:
        report.fail("required repository files", ", ".join(missing))
    else:
        report.ok("required repository files", f"{len(required)} found")

    migrations = sorted((ROOT / "db" / "migrations").glob("*.sql"))
    if len(migrations) >= MIGRATION_MIN:
        report.ok("migration files", f"{len(migrations)} SQL files")
    else:
        report.fail("migration files", f"expected >= {MIGRATION_MIN}, found {len(migrations)}")


def check_python(report: Report) -> None:
    version = sys.version_info
    if version >= (3, 11):
        report.ok("python", platform.python_version())
    else:
        report.fail("python", f"expected 3.11+, got {platform.python_version()}")

    if importlib.util.find_spec("psycopg2"):
        report.ok("python package psycopg2")
    else:
        report.fail("python package psycopg2", "install psycopg2-binary")


def check_delphi(report: Report) -> None:
    configured_dcc64 = os.environ.get("DELPHI_DCC64")
    candidates = [
        Path(configured_dcc64) if configured_dcc64 else None,
        Path("C:/Program Files (x86)/Embarcadero/Studio/37.0/bin64/dcc64.exe"),
        Path("D:/Program Files (x86)/Embarcadero/Studio/37.0/bin64/dcc64.exe"),
    ]
    found = next((path for path in candidates if path and path.exists()), None)
    if found:
        report.ok("Delphi compiler", str(found))
    else:
        report.warn("Delphi compiler", "not found; set DELPHI_DCC64 for Delphi tasks")

    deepbase = Path(os.environ.get("DEEPBASE_ROOT", ROOT / ".." / ".." / "DeepBase")).resolve()
    if deepbase.exists():
        report.ok("DeepBase source", str(deepbase))
    else:
        report.warn("DeepBase source", f"not found at {deepbase}; set DEEPBASE_ROOT if needed")


def check_database(report: Report) -> None:
    if DB_ENV["ARTIFACTOS_DB_NAME"] != "artifactos_test":
        report.fail("database target", f"expected artifactos_test, got {DB_ENV['ARTIFACTOS_DB_NAME']}")
        return
    report.ok("database target", DB_ENV["ARTIFACTOS_DB_NAME"])

    try:
        import psycopg2
    except ImportError:
        report.fail("database connection", "psycopg2 missing")
        return

    try:
        conn = psycopg2.connect(_conn_string())
        cur = conn.cursor()
        cur.execute("select current_database(), current_schema(), version()")
        db_name, schema_name, version = cur.fetchone()
        report.ok("database connection", f"{db_name} / {schema_name} / {version.split(',')[0]}")

        for schema in ["artifactos", "media_publish", "legacy_bridge"]:
            cur.execute("select exists(select 1 from information_schema.schemata where schema_name=%s)", (schema,))
            exists = cur.fetchone()[0]
            if exists:
                report.ok(f"schema {schema}")
            else:
                report.fail(f"schema {schema}", "missing")

        checks = [
            ("artifactos.source_pack", "select count(*) from artifactos.source_pack"),
            ("artifactos.publication_package", "select count(*) from artifactos.publication_package"),
            ("artifactos.runtime_instance", "select count(*) from artifactos.runtime_instance"),
            ("artifactos.runtime_command", "select count(*) from artifactos.runtime_command"),
            ("artifactos.runtime_command_event", "select count(*) from artifactos.runtime_command_event"),
            ("media_publish.runtime_command", "select count(*) from media_publish.runtime_command"),
            ("media_publish.platform_account_session", "select count(*) from media_publish.platform_account_session"),
            ("legacy_bridge.legacy_external_ref", "select count(*) from legacy_bridge.legacy_external_ref"),
        ]
        for name, sql in checks:
            try:
                cur.execute(sql)
                count = cur.fetchone()[0]
                report.ok(f"table {name}", f"rows={count}")
            except Exception as exc:
                conn.rollback()
                report.fail(f"table {name}", str(exc).splitlines()[0])

        try:
            cur.execute("select artifactos.check_real_publish_gate() ->> 'gate_status'")
            status = cur.fetchone()[0]
            if status == "blocked":
                report.ok("RealPublishGate", "blocked")
            else:
                report.fail("RealPublishGate", f"expected blocked, got {status}")
        except Exception as exc:
            conn.rollback()
            report.fail("RealPublishGate", str(exc).splitlines()[0])

        cur.close()
        conn.close()
    except Exception as exc:
        report.fail("database connection", str(exc).splitlines()[0])


def check_media_publish(report: Report) -> None:
    root = Path(os.environ.get("MEDIA_PUBLISH_ROOT", "D:/_Progs/.BetterCiv/tools/media_publish"))
    runtime_root = Path(os.environ.get("MEDIA_PUBLISH_RUNTIME_ROOT", root / ".media_publish"))
    if root.exists():
        report.ok("MEDIA_PUBLISH_ROOT", str(root))
    else:
        report.warn("MEDIA_PUBLISH_ROOT", f"not found at {root}")
        return

    cli = root / "media_publish" / "cli.py"
    if cli.exists():
        report.ok("media_publish cli", str(cli))
    else:
        report.fail("media_publish cli", f"missing {cli}")

    env = os.environ.copy()
    env["PYTHONPATH"] = str(root) + os.pathsep + env.get("PYTHONPATH", "")
    try:
        result = subprocess.run(
            [sys.executable, "-m", "media_publish.cli", "doctor"],
            cwd=root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        if result.returncode == 0:
            report.ok("media_publish doctor", "passed")
        else:
            detail = (result.stderr or result.stdout).strip().splitlines()
            report.fail("media_publish doctor", detail[0] if detail else "failed")
    except Exception as exc:
        report.fail("media_publish doctor", str(exc).splitlines()[0])

    if runtime_root.exists():
        report.ok("MEDIA_PUBLISH_RUNTIME_ROOT", str(runtime_root))
    else:
        report.warn("MEDIA_PUBLISH_RUNTIME_ROOT", f"not found at {runtime_root}")


def check_cleanups(report: Report) -> None:
    noisy = ["__pycache__", "tests/__pycache__"]
    found = [path for path in noisy if (ROOT / path).exists()]
    if found:
        report.warn("local generated files", ", ".join(found) + " (ignored by git)")
    else:
        report.ok("local generated files", "none in checked paths")

    if shutil.which("git"):
        result = subprocess.run(
            ["git", "status", "--short", "--", "README.md", "DEVELOPMENT.md", "check_readiness.py"],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        detail = result.stdout.strip() or "clean for checked readiness files"
        report.ok("git status scoped", detail)


def main() -> int:
    report = Report()
    print("ArtifactOS pre-development readiness check")
    print("=" * 48)
    check_files(report)
    check_python(report)
    check_delphi(report)
    check_database(report)
    check_media_publish(report)
    check_cleanups(report)
    print("=" * 48)
    passed = sum(1 for _, ok, _ in report.rows if ok)
    total = len(report.rows)
    print(f"PASS-LIKE: {passed}  FAIL: {total - passed}  TOTAL: {total}")
    return report.exit_code()


if __name__ == "__main__":
    raise SystemExit(main())
