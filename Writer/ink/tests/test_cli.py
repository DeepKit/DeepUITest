from __future__ import annotations

import json
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


def test_cli_setup_accepts_author_contract_inputs(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"

    assert main(["--db", str(db_path), "init", "--code", "setup-demo", "--title", "Setup Demo"]) == 0
    assert main(
        [
            "--db",
            str(db_path),
            "setup",
            "--chapters",
            "2",
            "--shots-per-chapter",
            "2",
            "--identity-json",
            '{"logline":"雨夜旧宅"}',
            "--narrative-voice-json",
            '{"person":"third","distance":"close"}',
            "--style-quality-profile-json",
            '{"target_reader":"悬疑读者","banned_cliches":["失忆"]}',
            "--rhythm-json",
            '{"curve":[2,5,8]}',
            "--hook-target",
            "钥匙转动",
            "--motif-density",
            "0.7",
            "--must-land-event",
            "她进入旧宅",
            "--beat",
            "发现钥匙",
            "--information-release",
            "门后有脚步",
            "--forbidden-word",
            "突然",
            "--pov-only",
            "她",
            "--location",
            "旧宅",
            "--time-of-day",
            "雨夜",
            "--character",
            "她",
            "--character-position",
            "她=门口",
            "--persona",
            "结构师",
            "--persona-intensity-json",
            '{"画面":6,"节奏":7,"对话":3,"结构":9,"悬疑":6}',
            "--creative-shot",
            "--relaxable-rule",
            "metaphor",
            "--deviation-budget",
            "0.35",
        ]
    ) == 0

    assert _scalar(db_path, "SELECT count(*) FROM writing_shots") == 4
    assert _scalar(db_path, "SELECT count(*) FROM writing_meta_contracts WHERE status = 'confirmed'") == 1
    meta = _row(db_path, "SELECT identity, narrative_voice, style_quality_profile FROM writing_meta_contracts")
    assert json.loads(meta[0]) == {"logline": "雨夜旧宅"}
    assert json.loads(meta[1]) == {"distance": "close", "person": "third"}
    assert json.loads(meta[2]) == {"banned_cliches": ["失忆"], "target_reader": "悬疑读者"}
    chapter_spec = _row(
        db_path,
        "SELECT rhythm_curve_target, hook_target, motif_density_target FROM writing_chapter_specs WHERE chapter_id = 1",
    )
    assert json.loads(chapter_spec[0]) == {"curve": [2, 5, 8]}
    assert chapter_spec[1:] == ("钥匙转动", 0.7)
    contract = _row(
        db_path,
        """
        SELECT m.events, m.beats, m.information_releases,
               a.forbidden_words, a.pov_only,
               sc.location, sc.time_of_day, sc.characters_present, sc.character_positions,
               p.persona, p.intensity, p.is_creative_shot,
               s.relaxable_rules, s.deviation_budget
        FROM writing_shot_contracts c
        JOIN writing_shot_must_land m ON m.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_anti_write a ON a.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_scene_contract sc ON sc.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_persona_assignment p ON p.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_soft_constraints s ON s.shot_contract_id = c.shot_contract_id
        WHERE c.logical_shot_id = 'ch-01-shot-002'
        """,
    )
    assert json.loads(contract[0]) == ["她进入旧宅"]
    assert json.loads(contract[1]) == ["发现钥匙"]
    assert json.loads(contract[2]) == ["门后有脚步"]
    assert json.loads(contract[3]) == ["突然"]
    assert json.loads(contract[4]) == ["她"]
    assert contract[5:7] == ("旧宅", "雨夜")
    assert json.loads(contract[7]) == ["她"]
    assert json.loads(contract[8]) == {"她": "门口"}
    assert contract[9] == "结构师"
    assert json.loads(contract[10]) == {"画面": 6, "节奏": 7, "对话": 3, "结构": 9, "悬疑": 6}
    assert contract[11] == 1
    assert json.loads(contract[12]) == ["metaphor"]
    assert contract[13] == 0.35


def _scalar(db_path: Path, sql: str):
    conn = sqlite3.connect(db_path)
    try:
        return conn.execute(sql).fetchone()[0]
    finally:
        conn.close()


def _row(db_path: Path, sql: str):
    conn = sqlite3.connect(db_path)
    try:
        return conn.execute(sql).fetchone()
    finally:
        conn.close()
