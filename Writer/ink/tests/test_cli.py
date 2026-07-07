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


def test_cli_outputs_json_envelope_and_setup_dry_run_does_not_write(tmp_path: Path, capsys) -> None:
    db_path = tmp_path / "ink.sqlite"

    assert main(["--db", str(db_path), "init", "--code", "dry-run-demo", "--title", "Dry Run Demo"]) == 0
    init_payload = json.loads(capsys.readouterr().out)
    assert init_payload["ok"] is True
    assert init_payload["command"] == "init"
    assert init_payload["data"]["project_id"] == 1

    assert main(
        [
            "--db",
            str(db_path),
            "setup",
            "--chapters",
            "2",
            "--shots-per-chapter",
            "3",
            "--dry-run",
        ]
    ) == 0
    dry_run_payload = json.loads(capsys.readouterr().out)
    assert dry_run_payload == {
        "ok": True,
        "command": "setup",
        "data": {
            "project_id": 1,
            "run_id": 1,
            "planned_chapters": 2,
            "shots_per_chapter": 3,
            "planned_shots": 6,
        },
    }
    assert _scalar(db_path, "SELECT count(*) FROM writing_shots") == 0


def test_cli_init_accepts_custom_model_pools(tmp_path: Path) -> None:
    """``init --writer-models`` / ``--jury-models`` 持久化自定义模型池。"""
    db_path = tmp_path / "ink.sqlite"

    assert (
        main(
            [
                "--db",
                str(db_path),
                "init",
                "--code",
                "pool-demo",
                "--title",
                "Pool Demo",
                "--writer-models",
                "xopglm51,xopdeepseekv4pro,xopkimik26",
                "--jury-models",
                "xopglm51,xopdeepseekv4pro,xopqwen36v35b,xopkimik26,xopqwen35397b",
            ]
        )
        == 0
    )

    row = _row(
        db_path,
        "SELECT writer_model_pool, jury_model_pool FROM writing_projects WHERE code = 'pool-demo'",
    )
    assert json.loads(row[0]) == ["xopglm51", "xopdeepseekv4pro", "xopkimik26"]
    assert json.loads(row[1]) == [
        "xopglm51",
        "xopdeepseekv4pro",
        "xopqwen36v35b",
        "xopkimik26",
        "xopqwen35397b",
    ]


def test_cli_init_dedupes_and_preserves_model_order(tmp_path: Path) -> None:
    """``--writer-models`` 去重并保留首次出现的顺序。"""
    db_path = tmp_path / "ink.sqlite"

    assert (
        main(
            [
                "--db",
                str(db_path),
                "init",
                "--code",
                "dedup-demo",
                "--title",
                "Dedup Demo",
                "--writer-models",
                "m1, m2 ,m1,, m3",
            ]
        )
        == 0
    )

    row = _row(
        db_path,
        "SELECT writer_model_pool FROM writing_projects WHERE code = 'dedup-demo'",
    )
    assert json.loads(row[0]) == ["m1", "m2", "m3"]


def test_cli_init_uses_defaults_when_pools_omitted(tmp_path: Path) -> None:
    """未传 ``--writer-models``/``--jury-models`` 时回落到默认池。"""
    db_path = tmp_path / "ink.sqlite"

    assert (
        main(
            ["--db", str(db_path), "init", "--code", "default-demo", "--title", "Default Demo"]
        )
        == 0
    )

    row = _row(
        db_path,
        "SELECT writer_model_pool, jury_model_pool FROM writing_projects WHERE code = 'default-demo'",
    )
    assert json.loads(row[0]) == ["writer-a", "writer-b", "writer-c"]
    assert json.loads(row[1]) == ["judge-a", "judge-b", "judge-c", "judge-d", "judge-e"]


def test_cli_errors_are_json(tmp_path: Path, capsys) -> None:
    db_path = tmp_path / "ink.sqlite"

    assert main(["--db", str(db_path), "setup", "--chapters", "1"]) == 1

    payload = json.loads(capsys.readouterr().err)
    assert payload["ok"] is False
    assert payload["command"] == "setup"
    assert payload["error"]["type"] == "UsageError"
    assert "project not found" in payload["error"]["message"]


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


def test_cli_confirm_contract_via_decision_session_writes_audit_chain(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "ds-demo", "--title", "DS Demo"]) == 0

    # CLI 尚未暴露 decision-session start（Task #4 范围），��里直接经 Store 准备 awaiting_confirm 会话。
    from ink.decision_sessions import DecisionSessionStore

    conn = sqlite3.connect(db_path)
    try:
        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封全书基线",
        )
        store.record_ai_parse(
            session_id,
            parsed_patch={"scope_type": "book", "change_type": "refine"},
            readback_text="我理解为封基线。",
            source_hashes=["hash-guide"],
            before_hash="before-hash",
        )
        store.create_option_set(session_id, options=[{"label": "确认基线"}], recommended_option=1)
        store.select_option(session_id, 1)
        conn.commit()
    finally:
        conn.close()

    payload = _run_and_capture(
        [
            "--db", str(db_path),
            "confirm-contract",
            "--decision-session-id", str(session_id),
            "--scope-type", "book",
            "--contract-json", '{"identity":{"title":"DS Demo"},"logline":"core"}',
            "--source-hashes", "hash-guide",
            "--reason", "封基线",
        ]
    )
    assert payload["ok"] is True
    data = payload["data"]
    assert data["decision_session_id"] == session_id
    assert data["contract_version_id"] > 0
    assert data["after_hash"]

    assert _scalar(
        db_path,
        "SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'contract_confirm'",
    ) == 1
    assert _scalar(db_path, "SELECT count(*) FROM writing_contract_versions") == 1
    assert _scalar(db_path, "SELECT count(*) FROM writing_contract_patches") == 1
    assert _scalar(db_path, "SELECT count(*) FROM writing_contract_changelog") == 1

    conn = sqlite3.connect(db_path)
    try:
        status = conn.execute(
            "SELECT status, after_hash FROM writing_decision_sessions WHERE decision_session_id = ?",
            (session_id,),
        ).fetchone()
    finally:
        conn.close()
    assert status[0] == "confirmed"
    assert status[1] == data["after_hash"]


def test_cli_confirm_contract_coverage_gate_blocks_then_releases(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "gate-demo", "--title", "Gate Demo"]) == 0

    from ink.decision_sessions import DecisionSessionStore
    from ink.source_workflow import SourceWorkflowStore

    conn = sqlite3.connect(db_path)
    try:
        source_store = SourceWorkflowStore(conn)
        source_document_id = source_store.register_source_document(
            project_id=1, source_path="guide.md", source_kind="guide", content_hash="hash-guide",
        )
        clause_id = source_store.record_atomic_clause(
            project_id=1, source_document_id=source_document_id, scope_type="book", scope_id=None,
            clause_type="plot", severity="hard", clause_text="全书证据链必须先确认。",
            source_refs=["guide.md#L1"], source_hashes=["hash-guide"],
        )

        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1, scope_type="book", scope_id=None,
            target_type="BookContract", target_id="book", human_text="封基线",
        )
        store.record_ai_parse(
            session_id, parsed_patch={"scope_type": "book"}, readback_text="封基线。",
            source_hashes=["hash-guide"], before_hash="before-hash",
        )
        store.create_option_set(session_id, options=[{"label": "确认"}], recommended_option=1)
        store.select_option(session_id, 1)
        coverage_id = source_store.record_coverage(
            project_id=1, contract_scope_type="book", contract_scope_id=None,
            contract_field_path="BookContract.evidence_chain", coverage_status="gap",
            atomic_clause_id=clause_id,
        )
        conn.commit()
    finally:
        conn.close()

    # blocking gap 存在时，confirm-contract 必须失败且不写任何审计行
    rc = main([
        "--db", str(db_path), "confirm-contract",
        "--decision-session-id", str(session_id),
        "--scope-type", "book",
        "--contract-json", '{"identity":{"title":"Gate Demo"}}',
        "--source-hashes", "hash-guide",
    ])
    assert rc != 0
    assert _scalar(db_path, "SELECT count(*) FROM writing_contract_versions") == 0
    assert _scalar(db_path, "SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'contract_confirm'") == 0

    # resolve coverage 后放行
    conn = sqlite3.connect(db_path)
    try:
        SourceWorkflowStore(conn).resolve_coverage(
            coverage_id, coverage_status="covered", evidence={"decision": "author_confirmed"},
        )
        conn.commit()
    finally:
        conn.close()

    payload = _run_and_capture([
        "--db", str(db_path), "confirm-contract",
        "--decision-session-id", str(session_id),
        "--scope-type", "book",
        "--contract-json", '{"identity":{"title":"Gate Demo"}}',
        "--source-hashes", "hash-guide",
    ])
    assert payload["ok"] is True
    assert payload["data"]["contract_version_id"] > 0


def _run_and_capture(argv: list[str]) -> dict:
    import io
    import contextlib

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = main(argv)
    assert rc == 0
    return json.loads(buf.getvalue())


def test_cli_decision_session_choice_protocol_start_parse_options_select_show(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "ds-protocol", "--title", "DS Protocol"]) == 0

    start_payload = _run_and_capture([
        "--db", str(db_path), "decision-session", "start",
        "--scope-type", "book",
        "--target-type", "BookContract",
        "--target-id", "book",
        "--human-text", "封全书基线",
    ])
    session_id = start_payload["data"]["decision_session_id"]

    parse_payload = _run_and_capture([
        "--db", str(db_path), "decision-session", "parse", str(session_id),
        "--parsed-patch-json", '{"scope_type":"book","change_type":"refine"}',
        "--readback-text", "我理解为封基线。",
        "--source-hashes", "hash-guide",
        "--before-hash", "before-hash",
    ])
    assert parse_payload["data"]["status"] == "ai_parsed"

    options_payload = _run_and_capture([
        "--db", str(db_path), "decision-session", "options", str(session_id),
        "--options-json", '[{"label":"确认基线"},{"label":"补充人物"}]',
        "--recommended-option", "1",
    ])
    assert options_payload["data"]["status"] == "awaiting_confirm"
    assert options_payload["data"]["recommended_option"] == 1
    assert len(options_payload["data"]["options"]) == 2

    # 恢复时 show 回放活跃 option set，不依赖模型重新想一版
    show_payload = _run_and_capture([
        "--db", str(db_path), "decision-session", "show", str(session_id),
    ])
    session = show_payload["data"]["session"]
    assert session["status"] == "awaiting_confirm"
    assert session["readback_text"] == "我理解为封基线。"
    option_set = show_payload["data"]["active_option_set"]
    assert option_set["options"] == [{"label": "确认基线"}, {"label": "补充人物"}]
    assert option_set["recommended_option"] == 1


def test_cli_decision_session_select_zero_returns_to_collecting(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "ds-back", "--title", "DS Back"]) == 0

    session_id = _run_and_capture([
        "--db", str(db_path), "decision-session", "start",
        "--scope-type", "chapter", "--scope-id", "1",
        "--target-type", "ChapterContract", "--target-id", "1",
        "--human-text", "调整钩子",
    ])["data"]["decision_session_id"]
    _run_and_capture([
        "--db", str(db_path), "decision-session", "parse", str(session_id),
        "--parsed-patch-json", '{"scope_type":"chapter"}',
        "--readback-text", "调整钩子。",
    ])
    _run_and_capture([
        "--db", str(db_path), "decision-session", "options", str(session_id),
        "--options-json", '[{"label":"接受"}]',
    ])

    select_payload = _run_and_capture([
        "--db", str(db_path), "decision-session", "select", str(session_id), "0",
    ])
    assert select_payload["data"]["selected_option"] == 0
    show_payload = _run_and_capture([
        "--db", str(db_path), "decision-session", "show", str(session_id),
    ])
    assert show_payload["data"]["session"]["status"] == "collecting"
    assert show_payload["data"]["active_option_set"] is None


def test_cli_decision_session_select_nine_requires_regenerate(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "ds-regen", "--title", "DS Regen"]) == 0

    session_id = _run_and_capture([
        "--db", str(db_path), "decision-session", "start",
        "--scope-type", "book", "--target-type", "BookContract", "--target-id", "book",
        "--human-text", "封基线",
    ])["data"]["decision_session_id"]
    _run_and_capture([
        "--db", str(db_path), "decision-session", "parse", str(session_id),
        "--parsed-patch-json", '{}', "--readback-text", "封基线。",
    ])
    _run_and_capture([
        "--db", str(db_path), "decision-session", "options", str(session_id),
        "--options-json", '[{"label":"A"},{"label":"B"}]',
    ])

    # 9 必须先 regenerate，直接 select 9 应失败
    rc = main([
        "--db", str(db_path), "decision-session", "select", str(session_id), "9",
    ])
    assert rc != 0

    regen_payload = _run_and_capture([
        "--db", str(db_path), "decision-session", "regenerate", str(session_id),
        "--options-json", '[{"label":"C"},{"label":"D"}]',
        "--recommended-option", "2",
    ])
    assert regen_payload["data"]["option_set_id"] > 0
    show_payload = _run_and_capture([
        "--db", str(db_path), "decision-session", "show", str(session_id),
    ])
    option_set = show_payload["data"]["active_option_set"]
    assert option_set["regenerate_count"] == 1
    assert option_set["options"] == [{"label": "C"}, {"label": "D"}]
    assert option_set["recommended_option"] == 2


def test_cli_coverage_gaps_lists_uncovered_fields_and_suggested_clauses(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "cov-demo", "--title", "Cov Demo"]) == 0

    from ink.source_workflow import SourceWorkflowStore

    conn = sqlite3.connect(db_path)
    try:
        store = SourceWorkflowStore(conn)
        doc_id = store.register_source_document(
            project_id=1, source_path="guide.md", source_kind="guide",
            content_hash="h1",
        )
        clause_id = store.record_atomic_clause(
            project_id=1, source_document_id=doc_id, scope_type="book", scope_id=None,
            clause_type="plot", severity="hard", clause_text="主角必须登场。",
            source_refs=["guide.md#L1"], source_hashes=["h1"], status="confirmed",
        )
        store.record_coverage(
            project_id=1, contract_scope_type="book", contract_scope_id=None,
            contract_field_path="must_land.protagonist", coverage_status="gap",
            atomic_clause_id=clause_id, evidence={"reason": "missing"},
        )
        conn.commit()
    finally:
        conn.close()

    payload = _run_and_capture([
        "--db", str(db_path), "coverage-gaps", "--scope-type", "book",
    ])
    data = payload["data"]
    assert data["total_gaps"] == 1
    gap = data["gaps"][0]
    assert gap["field_path"] == "must_land.protagonist"
    assert gap["status"] == "gap"
    assert gap["atomic_clause_id"] == clause_id
    assert clause_id in gap["suggested_clause_ids"]


def test_cli_coverage_gaps_empty_when_no_gaps(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "cov-empty", "--title", "Empty"]) == 0

    payload = _run_and_capture(["--db", str(db_path), "coverage-gaps"])
    data = payload["data"]
    assert data["total_gaps"] == 0
    assert data["gaps"] == []
