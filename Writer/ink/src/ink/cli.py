from __future__ import annotations

import argparse
import json
import sqlite3
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Sequence

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.core.resume import ResumeManager
from ink.database import connect
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.pipeline.export_orchestrator import ExportOrchestrator
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from ink.pipeline.import_orchestrator import ImportOrchestrator
from ink.pipeline.jury_orchestrator import JuryOrchestrator
from ink.pipeline.polish_orchestrator import PolishOrchestrator
from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator
from ink.pipeline.resume_handlers import build_non_shot_resume_handlers, build_shot_resume_handlers
from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator
from ink.schema import initialize_schema
from ink.time import now_utc_iso


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    conn = _open_cli_db(args.db)
    try:
        payload = args.handler(conn, args)
    except Exception:
        conn.rollback()
        raise
    else:
        conn.commit()
        if payload is not None:
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    finally:
        conn.close()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="ink")
    parser.add_argument("--db", required=True, help="SQLite database path")
    subcommands = parser.add_subparsers(dest="command", required=True)

    init_cmd = subcommands.add_parser("init")
    init_cmd.add_argument("--code", required=True)
    init_cmd.add_argument("--title", required=True)
    init_cmd.set_defaults(handler=_cmd_init)

    setup_cmd = subcommands.add_parser("setup")
    setup_cmd.add_argument("--project-id", type=int)
    setup_cmd.add_argument("--run-id", type=int)
    setup_cmd.add_argument("--chapters", type=int, required=True)
    setup_cmd.set_defaults(handler=_cmd_setup)

    confirm_cmd = subcommands.add_parser("confirm-contract")
    confirm_cmd.add_argument("--project-id", type=int)
    confirm_cmd.add_argument("--actor", default="author")
    confirm_cmd.add_argument("--reason", default="contract confirmed")
    confirm_cmd.set_defaults(handler=_cmd_confirm_contract)

    write_cmd = subcommands.add_parser("write")
    _add_chapter_run_args(write_cmd)
    write_cmd.set_defaults(handler=_cmd_write)

    review_cmd = subcommands.add_parser("review")
    _add_chapter_run_args(review_cmd)
    review_cmd.set_defaults(handler=_cmd_review)

    accept_cmd = subcommands.add_parser("accept")
    _add_chapter_run_args(accept_cmd)
    accept_cmd.add_argument("--actor", default="author")
    accept_cmd.add_argument("--reason", default="accept chapter")
    accept_cmd.set_defaults(handler=_cmd_accept)

    revise_cmd = subcommands.add_parser("revise")
    _add_chapter_run_args(revise_cmd)
    revise_cmd.add_argument("--actor", default="author")
    revise_cmd.add_argument("--reason", default="revise chapter")
    revise_cmd.set_defaults(handler=_cmd_revise)

    reject_cmd = subcommands.add_parser("reject")
    _add_chapter_run_args(reject_cmd)
    reject_cmd.add_argument("--actor", default="author")
    reject_cmd.add_argument("--reason", default="reject chapter")
    reject_cmd.set_defaults(handler=_cmd_reject)

    resume_cmd = subcommands.add_parser("resume")
    resume_cmd.add_argument("--session-id", type=int, required=True)
    resume_cmd.set_defaults(handler=_cmd_resume)

    import_cmd = subcommands.add_parser("import")
    import_mode = import_cmd.add_mutually_exclusive_group(required=True)
    import_mode.add_argument("--dry-run", action="store_true")
    import_mode.add_argument("--finalize", type=int, metavar="IMPORT_RUN_ID")
    import_cmd.add_argument("--project-id", type=int)
    import_cmd.add_argument("--source")
    import_cmd.add_argument("--actor", default="author")
    import_cmd.add_argument("--reason", default="finalize import")
    import_cmd.set_defaults(handler=_cmd_import)

    export_cmd = subcommands.add_parser("export")
    export_cmd.add_argument("--project-id", type=int)
    export_cmd.add_argument("--output")
    export_cmd.set_defaults(handler=_cmd_export)
    return parser


def _add_chapter_run_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--project-id", type=int)
    parser.add_argument("--chapter", type=int, required=True)
    parser.add_argument("--run-id", type=int)


def _open_cli_db(path: str) -> sqlite3.Connection:
    db_path = Path(path)
    conn = connect(db_path)
    has_schema = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'writing_projects'"
    ).fetchone()
    if has_schema is None:
        initialize_schema(conn)
    return conn


def _cmd_init(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, int]:
    now = now_utc_iso()
    project_cursor = conn.execute(
        """
        INSERT INTO writing_projects
            (code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (?, ?, '["writer-a","writer-b","writer-c"]',
                '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
        """,
        (args.code, args.title, now),
    )
    project_id = int(project_cursor.lastrowid)
    session_cursor = conn.execute(
        "INSERT INTO writing_sessions (project_id, started_at) VALUES (?, ?)",
        (project_id, now),
    )
    session_id = int(session_cursor.lastrowid)
    run_cursor = conn.execute(
        """
        INSERT INTO writing_runs
            (project_id, session_id, run_attempt, started_at, status)
        VALUES (?, ?, 1, ?, 'running')
        """,
        (project_id, session_id, now),
    )
    return {"project_id": project_id, "session_id": session_id, "run_id": int(run_cursor.lastrowid)}


def _cmd_setup(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    created: list[str] = []
    for chapter_id in range(1, args.chapters + 1):
        logical_shot_id = f"ch-{chapter_id:02d}-shot-001"
        existing = conn.execute(
            """
            SELECT shot_id
            FROM writing_shots
            WHERE project_id = ? AND chapter_id = ? AND run_id = ? AND logical_shot_id = ?
            """,
            (project_id, chapter_id, run_id, logical_shot_id),
        ).fetchone()
        if existing is not None:
            continue
        now = now_utc_iso()
        contract_cursor = conn.execute(
            """
            INSERT INTO writing_shot_contracts
                (project_id, chapter_id, run_id, logical_shot_id, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, 'confirmed', ?, ?)
            """,
            (project_id, chapter_id, run_id, logical_shot_id, now, now),
        )
        shot_contract_id = int(contract_cursor.lastrowid)
        _insert_default_contract_children(conn, shot_contract_id)
        shot_id = f"{logical_shot_id}@{run_id}"
        conn.execute(
            """
            INSERT INTO writing_shots
                (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id,
                 status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)
            """,
            (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id, now, now),
        )
        conn.execute(
            """
            INSERT OR IGNORE INTO writing_chapter_specs
                (project_id, chapter_id, rhythm_curve_target, hook_target, motif_density_target)
            VALUES (?, ?, '{}', NULL, NULL)
            """,
            (project_id, chapter_id),
        )
        created.append(shot_id)
    return {"project_id": project_id, "run_id": run_id, "created_shots": created}


def _cmd_confirm_contract(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, int]:
    cursor = conn.execute(
        """
        INSERT INTO writing_human_decisions
            (project_id, decision_type, actor, reason, preconditions_json,
             quality_report_json, hard_quality_override, created_at)
        VALUES (?, 'contract_confirm', ?, ?, '{}', '{}', 0, ?)
        """,
        (_project_id(conn, args), args.actor, args.reason, now_utc_iso()),
    )
    return {"decision_id": int(cursor.lastrowid)}


def _cmd_write(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    gateway = _gateway(conn)
    written: list[str] = []
    for shot_id in _chapter_shots(conn, project_id, args.chapter, run_id):
        _run_shot_to_soft_sealed(conn, shot_id, run_id, gateway)
        written.append(shot_id)
    return {"project_id": project_id, "chapter_id": args.chapter, "run_id": run_id, "soft_sealed": written}


def _cmd_review(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    review = ChapterReviewOrchestrator(conn).review_chapter(project_id, args.chapter, run_id)
    return {"review_id": review.review_id, "quality_gate_passed": review.quality_gate_passed}


def _cmd_accept(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, int]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    decision_id = HumanReviewOrchestrator(conn).accept_chapter(
        project_id,
        args.chapter,
        run_id,
        actor=args.actor,
        reason=args.reason,
    )
    return {"decision_id": decision_id}


def _cmd_revise(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    result = HumanReviewOrchestrator(conn).revise_chapter(
        project_id,
        args.chapter,
        run_id,
        actor=args.actor,
        reason=args.reason,
    )
    return {"decision_id": result.decision_id, "run_id": result.run_id, "shot_ids": list(result.shot_ids)}


def _cmd_reject(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, int]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    decision_id = HumanReviewOrchestrator(conn).reject_chapter(
        project_id,
        args.chapter,
        run_id,
        actor=args.actor,
        reason=args.reason,
    )
    return {"decision_id": decision_id}


def _cmd_resume(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, list[dict[str, object]]]:
    manager = ResumeManager(conn)
    handlers = build_shot_resume_handlers(conn, _gateway(conn))
    session = conn.execute(
        "SELECT resume_point FROM writing_sessions WHERE session_id = ?",
        (args.session_id,),
    ).fetchone()
    if session is None:
        raise SystemExit(f"session not found: {args.session_id}")
    session_resume_point = session[0]
    rows = conn.execute(
        """
        SELECT s.shot_id, s.run_id
        FROM writing_shots s
        JOIN writing_runs r ON r.run_id = s.run_id
        WHERE r.session_id = ?
        ORDER BY s.chapter_id, s.logical_shot_id
        """,
        (args.session_id,),
    ).fetchall()
    actions = []
    for row in rows:
        shot_id = str(row[0])
        run_id = int(row[1])
        action = manager.resume_shot(args.session_id, shot_id, run_id)
        manager.execute_resume_action(shot_id, run_id, action, handlers)
        actions.append({"shot_id": shot_id, "run_id": run_id, "action": action})
    session_actions = []
    if session_resume_point:
        payload = manager.parse_resume_point(str(session_resume_point))
        result = manager.execute_resume_point(payload, build_non_shot_resume_handlers(conn))
        conn.execute(
            "UPDATE writing_sessions SET crashed = 0, resume_point = NULL WHERE session_id = ?",
            (args.session_id,),
        )
        session_actions.append({"phase": payload["phase"], "result": _jsonable_result(result)})
    return {"actions": actions, "session_actions": session_actions}


def _cmd_import(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, int]:
    orchestrator = ImportOrchestrator(conn)
    if args.dry_run:
        if not args.source:
            raise SystemExit("import --dry-run requires --source")
        result = orchestrator.dry_run(_project_id(conn, args), args.source)
        return {"import_run_id": result.import_run_id, "manifest_count": result.manifest_count}
    result = orchestrator.finalize(args.finalize, actor=args.actor, reason=args.reason)
    return {"import_decision_id": result.import_decision_id, "human_decision_id": result.human_decision_id}


def _cmd_export(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    artifact = ExportOrchestrator(conn).export_project(project_id)
    if args.output:
        Path(args.output).write_text(artifact, encoding="utf-8")
        return {"project_id": project_id, "output": args.output, "bytes": len(artifact.encode("utf-8"))}
    return {"project_id": project_id, "artifact": artifact}


def _project_id(conn: sqlite3.Connection, args: argparse.Namespace) -> int:
    if getattr(args, "project_id", None) is not None:
        return int(args.project_id)
    row = conn.execute("SELECT project_id FROM writing_projects ORDER BY project_id LIMIT 1").fetchone()
    if row is None:
        raise SystemExit("project not found; run init first or pass --project-id")
    return int(row[0])


def _run_id(conn: sqlite3.Connection, args: argparse.Namespace, project_id: int) -> int:
    if getattr(args, "run_id", None) is not None:
        return int(args.run_id)
    row = conn.execute(
        "SELECT run_id FROM writing_runs WHERE project_id = ? ORDER BY run_id DESC LIMIT 1",
        (project_id,),
    ).fetchone()
    if row is None:
        raise SystemExit("run not found; run init first or pass --run-id")
    return int(row[0])


def _chapter_shots(conn: sqlite3.Connection, project_id: int, chapter_id: int, run_id: int) -> list[str]:
    rows = conn.execute(
        """
        SELECT shot_id
        FROM writing_shots
        WHERE project_id = ? AND chapter_id = ? AND run_id = ?
        ORDER BY logical_shot_id
        """,
        (project_id, chapter_id, run_id),
    ).fetchall()
    if not rows:
        raise SystemExit(f"chapter has no shots: project={project_id} chapter={chapter_id} run={run_id}")
    return [str(row[0]) for row in rows]


def _run_shot_to_soft_sealed(conn: sqlite3.Connection, shot_id: str, run_id: int, gateway: LLMGateway) -> None:
    PreDraftingOrchestrator(conn, gateway).run_until_prompt_compiled(shot_id, run_id)
    WriteOrchestrator(conn, gateway).produce_drafts(shot_id, run_id)
    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn).score_and_select_winner(shot_id, run_id)
    PolishOrchestrator(conn, gateway).polish_winner(shot_id, run_id)
    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn).score_and_select_winner(shot_id, run_id)
    SoftSealOrchestrator(conn).soft_seal_if_polished(shot_id, run_id)


def _gateway(conn: sqlite3.Connection) -> LLMGateway:
    return LLMGateway(conn, provider=_CliDeterministicProvider())


def _jsonable_result(value: object) -> object:
    if value is None:
        return None
    if is_dataclass(value) and not isinstance(value, type):
        return asdict(value)
    if isinstance(value, dict | list | tuple | str | int | float | bool):
        return value
    return str(value)


class _CliDeterministicProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        if idempotency_key.startswith("outline:"):
            source = prompt_text.split("Contract source: ", 1)[1].splitlines()[0]
            text = f"{source} outline"
        elif idempotency_key.startswith("polish:"):
            text = f"polished text {idempotency_key}"
        else:
            text = f"scene text {model_name} {idempotency_key}"
        return ModelResult(text=text, model_name=model_name, token_input=len(prompt_text.split()), token_output=1)


def _insert_default_contract_children(conn: sqlite3.Connection, shot_contract_id: int) -> None:
    conn.execute(
        """
        INSERT INTO writing_shot_must_land
            (shot_contract_id, events, beats, information_releases)
        VALUES (?, ?, ?, ?)
        """,
        (shot_contract_id, json.dumps(["她走进档案室"]), json.dumps(["发现钥匙"]), json.dumps(["门外脚步"])),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_anti_write
            (shot_contract_id, forbidden_facts, forbidden_words, pov_only)
        VALUES (?, ?, ?, ?)
        """,
        (shot_contract_id, json.dumps([]), json.dumps(["突然"]), json.dumps(["她"])),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_scene_contract
            (shot_contract_id, location, time_of_day, characters_present, character_positions)
            VALUES (?, '档案室', '夜晚', ?, ?)
        """,
        (shot_contract_id, json.dumps(["她"]), json.dumps({"她": "门边"}, ensure_ascii=False)),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_persona_assignment
            (shot_contract_id, persona, intensity, is_creative_shot, is_suspense_shot)
            VALUES (?, '悬疑官', ?, 0, 1)
        """,
        (shot_contract_id, json.dumps({"画面": 7, "节奏": 6, "对话": 3, "结构": 6, "悬疑": 8}, ensure_ascii=False)),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_soft_constraints
            (shot_contract_id, relaxable_rules, deviation_budget)
        VALUES (?, ?, 0.2)
        """,
        (shot_contract_id, json.dumps(["metaphor"])),
    )


if __name__ == "__main__":
    raise SystemExit(main())
