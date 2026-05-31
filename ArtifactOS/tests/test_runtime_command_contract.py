#!/usr/bin/env python
"""Static contract checks for ArtifactOS runtime command migration."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "db" / "migrations" / "028_artifactos_runtime_command.sql"
STACK_DOC = ROOT / "docs" / "26.[技术]-技术选型与运行时架构-Stack-Decision.md"
DB_DOC = ROOT / "docs" / "24.[数据]-数据库模型与治理-Database.md"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8").lower()


def require(text: str, needle: str, label: str) -> None:
    if needle.lower() not in text:
        raise AssertionError(f"missing {label}: {needle}")


def main() -> int:
    migration = read(MIGRATION)
    stack_doc = read(STACK_DOC)
    db_doc = read(DB_DOC)

    for ddl in [
        "create table if not exists artifactos.runtime_instance",
        "create table if not exists artifactos.runtime_command",
        "create table if not exists artifactos.runtime_command_event",
        "create or replace function artifactos.claim_next_runtime_command",
        "create or replace function artifactos.mark_expired_runtime_commands",
        "pg_notify('artifactos_runtime_command'",
        "for update skip locked",
        "create unique index if not exists uq_runtime_command_idempotency",
        "create index if not exists idx_runtime_command_pending",
    ]:
        require(migration, ddl, "runtime DDL")

    for status in [
        "pending",
        "claimed",
        "running",
        "succeeded",
        "failed",
        "cancelled",
        "lease_expired",
        "needs_human",
        "blocked",
    ]:
        require(migration, f"'{status}'", "command status")

    for level in ["L0", "L1", "L2", "L3"]:
        require(migration, f"'{level.lower()}'", "command level")

    for source in ["desk", "agent", "amy", "test", "diagnostic", "system"]:
        require(migration, f"'{source}'", "command source")

    for instance_type in ["desk", "agent", "engine", "publishing_runtime", "diagnostic"]:
        require(migration, f"'{instance_type}'", "instance type")

    for doc_text in [stack_doc, db_doc]:
        require(doc_text, "artifactos.runtime_command", "ArtifactOS command contract doc")
        require(doc_text, "media_publish.runtime_command", "PublishingRuntime command boundary doc")
        require(doc_text, "listen/notify", "LISTEN/NOTIFY doc")
        require(doc_text, "engine", "Engine-only handoff doc")

    print("PASS runtime command contract static checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
