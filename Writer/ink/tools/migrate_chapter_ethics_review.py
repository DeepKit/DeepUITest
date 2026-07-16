from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path


DEFAULT_DB = Path(r"D:/_Progs/.Story/《白灯法则》/.inkflow/inkflow.db")

TABLE_SQL = """
CREATE TABLE IF NOT EXISTS writing_chapter_ethics_reviews (
    ethics_review_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    run_id INTEGER NOT NULL,
    reviewer_actor TEXT NOT NULL,
    reviewer_models_json TEXT NOT NULL CHECK (
        json_valid(reviewer_models_json) AND json_type(reviewer_models_json)='array'
    ),
    responsibility_question TEXT NOT NULL,
    affected_parties_json TEXT NOT NULL CHECK (
        json_valid(affected_parties_json) AND json_type(affected_parties_json)='array'
    ),
    irreversible_harm TEXT NOT NULL,
    agency_obscured INTEGER NOT NULL CHECK (agency_obscured IN (0,1)),
    evidence_sentences_json TEXT NOT NULL CHECK (
        json_valid(evidence_sentences_json) AND json_type(evidence_sentences_json)='array'
    ),
    risk_level TEXT NOT NULL CHECK (risk_level IN ('low','medium','high','blocking')),
    recommendation TEXT NOT NULL CHECK (recommendation IN ('approve','revise')),
    review_notes TEXT NOT NULL,
    reviewed_at TEXT NOT NULL,
    UNIQUE (project_id, chapter_id, run_id),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_ethics_reviews_project_chapter
ON writing_chapter_ethics_reviews(project_id, chapter_id, run_id);
"""


def migrate(db_path: Path, *, dry_run: bool = False) -> dict[str, object]:
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys=ON")
    columns = {str(row[1]) for row in conn.execute("PRAGMA table_info(writing_projects)")}
    add_column = "require_ethics_review" not in columns
    table_exists = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='writing_chapter_ethics_reviews'"
    ).fetchone() is not None
    if not dry_run:
        if add_column:
            conn.execute(
                "ALTER TABLE writing_projects "
                "ADD COLUMN require_ethics_review INTEGER NOT NULL DEFAULT 0 "
                "CHECK (require_ethics_review IN (0,1))"
            )
        conn.executescript(TABLE_SQL)
        conn.commit()
    conn.close()
    return {
        "db": str(db_path),
        "dry_run": dry_run,
        "column_added": add_column and not dry_run,
        "table_created": (not table_exists) and not dry_run,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(migrate(args.db, dry_run=args.dry_run))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
