#!/usr/bin/env python3
"""Idempotently add Scene-first Chapter Accept hard-gate evidence tables."""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

TABLES = (
    "writing_chapter_accept_gate_evidence",
    "writing_chapter_snapshot_gate_evidence",
)

_CREATE_SQL = """
CREATE TABLE writing_chapter_accept_gate_evidence (
    evidence_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    generation_round_id INTEGER NOT NULL,
    branch_version_id INTEGER NOT NULL,
    branch_content_hash TEXT NOT NULL CHECK (length(trim(branch_content_hash)) > 0),
    gate_type TEXT NOT NULL CHECK (gate_type IN (
        'scene_integrity', 'chapter_quality', 'book_continuity', 'ethics'
    )),
    attempt INTEGER NOT NULL CHECK (attempt >= 1),
    policy_version TEXT NOT NULL CHECK (length(trim(policy_version)) > 0),
    passed INTEGER NOT NULL CHECK (passed IN (0, 1)),
    evidence_json TEXT NOT NULL CHECK (
        json_valid(evidence_json) AND json_type(evidence_json) = 'object'
    ),
    predecessor_heads_hash TEXT,
    producer_actor TEXT NOT NULL CHECK (length(trim(producer_actor)) > 0),
    reviewer_models_json TEXT NOT NULL DEFAULT '[]' CHECK (
        json_valid(reviewer_models_json) AND json_type(reviewer_models_json) = 'array'
    ),
    evaluated_at TEXT NOT NULL,
    UNIQUE (branch_version_id, gate_type, attempt),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (generation_round_id) REFERENCES writing_chapter_generation_rounds(generation_round_id),
    FOREIGN KEY (branch_version_id) REFERENCES writing_chapter_candidate_branch_versions(branch_version_id)
);
CREATE INDEX idx_accept_gate_evidence_branch
ON writing_chapter_accept_gate_evidence(branch_version_id, gate_type, attempt DESC);
CREATE TRIGGER trg_accept_gate_evidence_no_update
BEFORE UPDATE ON writing_chapter_accept_gate_evidence
BEGIN SELECT RAISE(ABORT, 'accept gate evidence is immutable'); END;
CREATE TRIGGER trg_accept_gate_evidence_no_delete
BEFORE DELETE ON writing_chapter_accept_gate_evidence
BEGIN SELECT RAISE(ABORT, 'accept gate evidence is immutable'); END;

CREATE TABLE writing_chapter_snapshot_gate_evidence (
    snapshot_id INTEGER NOT NULL,
    gate_type TEXT NOT NULL CHECK (gate_type IN (
        'scene_integrity', 'chapter_quality', 'book_continuity', 'ethics'
    )),
    evidence_id INTEGER NOT NULL,
    PRIMARY KEY (snapshot_id, gate_type),
    UNIQUE (snapshot_id, evidence_id),
    FOREIGN KEY (snapshot_id) REFERENCES writing_chapter_snapshots(snapshot_id),
    FOREIGN KEY (evidence_id) REFERENCES writing_chapter_accept_gate_evidence(evidence_id)
);
CREATE TRIGGER trg_snapshot_gate_evidence_no_update
BEFORE UPDATE ON writing_chapter_snapshot_gate_evidence
BEGIN SELECT RAISE(ABORT, 'snapshot gate evidence bindings are immutable'); END;
CREATE TRIGGER trg_snapshot_gate_evidence_no_delete
BEFORE DELETE ON writing_chapter_snapshot_gate_evidence
BEGIN SELECT RAISE(ABORT, 'snapshot gate evidence bindings are immutable'); END;
CREATE TRIGGER trg_sealed_snapshot_gate_evidence_no_insert
BEFORE INSERT ON writing_chapter_snapshot_gate_evidence
WHEN (SELECT sealed_at FROM writing_chapter_snapshots WHERE snapshot_id = NEW.snapshot_id) IS NOT NULL
BEGIN SELECT RAISE(ABORT, 'sealed snapshot gate evidence bindings are immutable'); END;
CREATE TRIGGER trg_snapshot_gate_evidence_matches
BEFORE INSERT ON writing_chapter_snapshot_gate_evidence
WHEN NOT EXISTS (
    SELECT 1
    FROM writing_chapter_snapshots s
    JOIN writing_chapter_accept_gate_evidence e ON e.evidence_id = NEW.evidence_id
    WHERE s.snapshot_id = NEW.snapshot_id
      AND e.gate_type = NEW.gate_type
      AND e.branch_version_id = s.source_branch_version_id
      AND e.branch_content_hash = s.snapshot_hash
      AND e.passed = 1
)
BEGIN SELECT RAISE(ABORT, 'snapshot gate evidence must be passing evidence for its source Branch'); END;
"""


def migrate(conn: sqlite3.Connection, *, dry_run: bool = False) -> bool:
    existing = {
        str(row[0])
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN (?, ?)",
            TABLES,
        ).fetchall()
    }
    if existing == set(TABLES):
        return False
    if existing:
        raise RuntimeError(
            "partial Scene-first Accept gate migration detected: "
            + ", ".join(sorted(existing))
        )
    if dry_run:
        return True
    conn.executescript(_CREATE_SQL)
    conn.commit()
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("db", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if not args.db.exists():
        print(f"[ERR] database not found: {args.db}", file=sys.stderr)
        return 2
    conn = sqlite3.connect(str(args.db))
    try:
        changed = migrate(conn, dry_run=args.dry_run)
        if args.dry_run:
            print("[DRY-RUN] would add Scene-first Accept gate evidence tables.")
        elif changed:
            print("[DONE] added Scene-first Accept gate evidence tables; historical data unchanged.")
        else:
            print("[OK] Scene-first Accept gate evidence tables already exist.")
        return 0
    except RuntimeError as exc:
        print(f"[ERR] {exc}", file=sys.stderr)
        return 4
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
