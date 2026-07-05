from __future__ import annotations

import sqlite3
from pathlib import Path

from ink.cli import main


def test_cli_chapter_revise_export_import_flow(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    output_path = tmp_path / "export.md"
    import_root = tmp_path / "legacy"
    import_root.mkdir()

    assert main(["--db", str(db_path), "init", "--code", "cli-demo", "--title", "CLI Demo"]) == 0
    assert main(["--db", str(db_path), "setup", "--chapters", "1"]) == 0
    assert main(["--db", str(db_path), "confirm-contract"]) == 0
    assert main(["--db", str(db_path), "write", "--chapter", "1"]) == 0
    assert main(["--db", str(db_path), "review", "--chapter", "1"]) == 0
    assert main(["--db", str(db_path), "reject", "--chapter", "1", "--reason", "reject first pass"]) == 0
    assert main(["--db", str(db_path), "revise", "--chapter", "1", "--reason", "revise rejected pass"]) == 0

    revised_run_id = _scalar(db_path, "SELECT max(run_id) FROM writing_runs")
    assert revised_run_id != 1
    assert main(["--db", str(db_path), "write", "--chapter", "1", "--run-id", str(revised_run_id)]) == 0
    assert main(["--db", str(db_path), "review", "--chapter", "1", "--run-id", str(revised_run_id)]) == 0
    assert main(["--db", str(db_path), "accept", "--chapter", "1", "--run-id", str(revised_run_id)]) == 0
    assert main(["--db", str(db_path), "export", "--output", str(output_path)]) == 0

    assert "polished text" in output_path.read_text(encoding="utf-8")
    (import_root / "accepted.md").write_text(output_path.read_text(encoding="utf-8"), encoding="utf-8")
    assert main(["--db", str(db_path), "import", "--dry-run", "--source", str(import_root)]) == 0
    import_run_id = _scalar(db_path, "SELECT max(import_run_id) FROM writing_import_runs")
    assert main(["--db", str(db_path), "import", "--finalize", str(import_run_id)]) == 0

    assert _scalar(db_path, "SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'reject'") == 1
    assert _scalar(db_path, "SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'revise'") == 1
    assert _scalar(db_path, "SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'accept'") == 1
    assert _scalar(db_path, "SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'import_finalize'") == 1
    assert _scalar(db_path, "SELECT count(*) FROM writing_chapter_reviews WHERE status = 'accepted'") == 1
    assert _scalar(db_path, "SELECT count(*) FROM writing_chapter_reviews WHERE status = 'rejected'") == 1


def test_cli_resume_starts_pending_shot(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"

    assert main(["--db", str(db_path), "init", "--code", "resume-demo", "--title", "Resume Demo"]) == 0
    assert main(["--db", str(db_path), "setup", "--chapters", "1"]) == 0
    assert main(["--db", str(db_path), "resume", "--session-id", "1"]) == 0

    assert _scalar(db_path, "SELECT count(*) FROM writing_shots WHERE status = 'prompt_compiled'") == 1
    assert _scalar(db_path, "SELECT count(*) FROM writing_prompt_snapshots") == 1


def _scalar(db_path: Path, sql: str):
    conn = sqlite3.connect(db_path)
    try:
        return conn.execute(sql).fetchone()[0]
    finally:
        conn.close()
