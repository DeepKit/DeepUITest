from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from dataclasses import asdict, dataclass, is_dataclass
from pathlib import Path
from typing import Sequence

from ink.core.llm_gateway import LLMGateway, ModelResult, build_model_provider, load_llm_provider_config
from ink.core.resume import ResumeManager
from ink.database import connect
from ink.errors import InkError
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
    except SystemExit as exc:
        conn.rollback()
        _print_error(args, exc)
        return _exit_code(exc)
    except Exception as exc:
        conn.rollback()
        _print_error(args, exc)
        return 1
    else:
        if _is_precheck_dry_run(args):
            conn.rollback()
        else:
            conn.commit()
        if payload is not None:
            print(json.dumps({"ok": True, "command": args.command, "data": payload}, ensure_ascii=False, sort_keys=True))
        return 0
    finally:
        conn.close()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="ink")
    parser.add_argument("--db", required=True, help="SQLite database path")
    parser.add_argument(
        "--llm-provider",
        choices=("deterministic", "mock", "openai-compatible"),
        default="deterministic",
        help="LLM provider for commands that call models",
    )
    parser.add_argument("--llm-base-url", help="Base URL for openai-compatible providers")
    parser.add_argument("--llm-api-key-env", help="Environment variable that stores the provider API key")
    parser.add_argument("--llm-timeout", type=float, help="Provider request timeout in seconds")
    subcommands = parser.add_subparsers(dest="command", required=True)

    init_cmd = subcommands.add_parser("init")
    init_cmd.add_argument("--code", required=True)
    init_cmd.add_argument("--title", required=True)
    init_cmd.set_defaults(handler=_cmd_init)

    setup_cmd = subcommands.add_parser("setup")
    setup_cmd.add_argument("--project-id", type=int)
    setup_cmd.add_argument("--run-id", type=int)
    setup_cmd.add_argument("--chapters", type=int, required=True)
    _add_dry_run(setup_cmd)
    setup_cmd.add_argument("--shots-per-chapter", type=int, default=1)
    setup_cmd.add_argument("--identity-json")
    setup_cmd.add_argument("--narrative-voice-json")
    setup_cmd.add_argument("--hard-boundaries-json")
    setup_cmd.add_argument("--style-locks-json")
    setup_cmd.add_argument("--world-knowledge-json")
    setup_cmd.add_argument("--motif-system-json")
    setup_cmd.add_argument("--creative-zones-json")
    setup_cmd.add_argument("--style-quality-profile-json")
    setup_cmd.add_argument("--rhythm-json")
    setup_cmd.add_argument("--hook-target")
    setup_cmd.add_argument("--motif-density", type=float)
    setup_cmd.add_argument("--must-land-event", action="append")
    setup_cmd.add_argument("--beat", action="append")
    setup_cmd.add_argument("--information-release", action="append")
    setup_cmd.add_argument("--forbidden-fact", action="append")
    setup_cmd.add_argument("--forbidden-word", action="append")
    setup_cmd.add_argument("--pov-only", action="append")
    setup_cmd.add_argument("--location")
    setup_cmd.add_argument("--time-of-day")
    setup_cmd.add_argument("--character", action="append")
    setup_cmd.add_argument("--character-position", action="append", metavar="NAME=POSITION")
    setup_cmd.add_argument("--persona", choices=("意象师", "节奏师", "对话师", "结构师", "悬疑官"))
    setup_cmd.add_argument("--persona-intensity-json")
    setup_cmd.add_argument("--creative-shot", action="store_true")
    setup_cmd.add_argument("--relaxable-rule", action="append")
    setup_cmd.add_argument("--deviation-budget", type=float)
    setup_cmd.set_defaults(handler=_cmd_setup)

    confirm_cmd = subcommands.add_parser("confirm-contract")
    confirm_cmd.add_argument("--project-id", type=int)
    confirm_cmd.add_argument("--actor", default="author")
    confirm_cmd.add_argument("--reason", default="contract confirmed")
    _add_dry_run(confirm_cmd)
    confirm_cmd.set_defaults(handler=_cmd_confirm_contract)

    write_cmd = subcommands.add_parser("write")
    _add_chapter_run_args(write_cmd)
    _add_dry_run(write_cmd)
    write_cmd.set_defaults(handler=_cmd_write)

    review_cmd = subcommands.add_parser("review")
    _add_chapter_run_args(review_cmd)
    _add_dry_run(review_cmd)
    review_cmd.set_defaults(handler=_cmd_review)

    accept_cmd = subcommands.add_parser("accept")
    _add_chapter_run_args(accept_cmd)
    accept_cmd.add_argument("--actor", default="author")
    accept_cmd.add_argument("--reason", default="accept chapter")
    _add_dry_run(accept_cmd)
    accept_cmd.set_defaults(handler=_cmd_accept)

    revise_cmd = subcommands.add_parser("revise")
    _add_chapter_run_args(revise_cmd)
    revise_cmd.add_argument("--actor", default="author")
    revise_cmd.add_argument("--reason", default="revise chapter")
    _add_dry_run(revise_cmd)
    revise_cmd.set_defaults(handler=_cmd_revise)

    reject_cmd = subcommands.add_parser("reject")
    _add_chapter_run_args(reject_cmd)
    reject_cmd.add_argument("--actor", default="author")
    reject_cmd.add_argument("--reason", default="reject chapter")
    _add_dry_run(reject_cmd)
    reject_cmd.set_defaults(handler=_cmd_reject)

    resume_cmd = subcommands.add_parser("resume")
    resume_cmd.add_argument("--session-id", type=int, required=True)
    _add_dry_run(resume_cmd)
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
    _add_dry_run(export_cmd)
    export_cmd.set_defaults(handler=_cmd_export)
    return parser


def _add_chapter_run_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--project-id", type=int)
    parser.add_argument("--chapter", type=int, required=True)
    parser.add_argument("--run-id", type=int)


def _add_dry_run(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--dry-run", action="store_true", help="Validate inputs and print the planned action without writing changes")


def _open_cli_db(path: str) -> sqlite3.Connection:
    db_path = Path(path)
    conn = connect(db_path)
    has_schema = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'writing_projects'"
    ).fetchone()
    if has_schema is None:
        initialize_schema(conn)
    return conn


def _is_precheck_dry_run(args: argparse.Namespace) -> bool:
    return bool(getattr(args, "dry_run", False)) and getattr(args, "command", None) != "import"


def _print_error(args: argparse.Namespace, exc: BaseException | None) -> None:
    command = getattr(args, "command", None)
    if isinstance(exc, SystemExit):
        message = str(exc.code)
        error_type = "UsageError"
    elif isinstance(exc, InkError):
        message = str(exc)
        error_type = type(exc).__name__
    elif isinstance(exc, sqlite3.Error):
        message = str(exc)
        error_type = type(exc).__name__
    else:
        message = "" if exc is None else str(exc)
        error_type = "UnexpectedError" if exc is not None else "UnknownError"
    print(
        json.dumps(
            {"ok": False, "command": command, "error": {"type": error_type, "message": message}},
            ensure_ascii=False,
            sort_keys=True,
        ),
        file=sys.stderr,
    )


def _exit_code(exc: SystemExit) -> int:
    return int(exc.code) if isinstance(exc.code, int) else 1


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
    options = _setup_options(args)
    if args.dry_run:
        return {
            "project_id": project_id,
            "run_id": run_id,
            "planned_chapters": args.chapters,
            "shots_per_chapter": options.shots_per_chapter,
            "planned_shots": args.chapters * options.shots_per_chapter,
        }
    _upsert_meta_contract(conn, project_id, options)
    created: list[str] = []
    for chapter_id in range(1, args.chapters + 1):
        for shot_index in range(1, options.shots_per_chapter + 1):
            logical_shot_id = f"ch-{chapter_id:02d}-shot-{shot_index:03d}"
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
            _insert_contract_children(conn, shot_contract_id, options)
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
            created.append(shot_id)
        conn.execute(
            """
            INSERT INTO writing_chapter_specs
                (project_id, chapter_id, rhythm_curve_target, hook_target, motif_density_target)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(project_id, chapter_id)
            DO UPDATE SET
                rhythm_curve_target = excluded.rhythm_curve_target,
                hook_target = excluded.hook_target,
                motif_density_target = excluded.motif_density_target
            """,
            (
                project_id,
                chapter_id,
                _json_dumps(options.rhythm_curve_target),
                options.hook_target,
                options.motif_density_target,
            ),
        )
    return {
        "project_id": project_id,
        "run_id": run_id,
        "shots_per_chapter": options.shots_per_chapter,
        "created_shots": created,
    }


def _cmd_confirm_contract(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, int]:
    project_id = _project_id(conn, args)
    if args.dry_run:
        return {"project_id": project_id, "planned_decisions": 1}
    cursor = conn.execute(
        """
        INSERT INTO writing_human_decisions
            (project_id, decision_type, actor, reason, preconditions_json,
             quality_report_json, hard_quality_override, created_at)
        VALUES (?, 'contract_confirm', ?, ?, '{}', '{}', 0, ?)
        """,
        (project_id, args.actor, args.reason, now_utc_iso()),
    )
    return {"decision_id": int(cursor.lastrowid)}


def _cmd_write(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    gateway = _gateway(conn, args)
    shot_ids = _chapter_shots(conn, project_id, args.chapter, run_id)
    if args.dry_run:
        return {"project_id": project_id, "chapter_id": args.chapter, "run_id": run_id, "planned_shots": shot_ids}
    written: list[str] = []
    for shot_id in shot_ids:
        _run_shot_to_soft_sealed(conn, shot_id, run_id, gateway)
        written.append(shot_id)
    return {"project_id": project_id, "chapter_id": args.chapter, "run_id": run_id, "soft_sealed": written}


def _cmd_review(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    shot_ids = _chapter_shots(conn, project_id, args.chapter, run_id)
    if args.dry_run:
        return {"project_id": project_id, "chapter_id": args.chapter, "run_id": run_id, "planned_review_shots": shot_ids}
    review = ChapterReviewOrchestrator(conn).review_chapter(project_id, args.chapter, run_id)
    return {"review_id": review.review_id, "quality_gate_passed": review.quality_gate_passed}


def _cmd_accept(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, int]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    if args.dry_run:
        return {"project_id": project_id, "chapter_id": args.chapter, "run_id": run_id, "planned_decisions": 1}
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
    if args.dry_run:
        return {"project_id": project_id, "chapter_id": args.chapter, "run_id": run_id, "planned_action": "revise"}
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
    if args.dry_run:
        return {"project_id": project_id, "chapter_id": args.chapter, "run_id": run_id, "planned_decisions": 1}
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
    handlers = build_shot_resume_handlers(conn, _gateway(conn, args))
    dry_run = bool(args.dry_run)
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
        if not dry_run:
            manager.execute_resume_action(shot_id, run_id, action, handlers)
        actions.append({"shot_id": shot_id, "run_id": run_id, "action": action})
    session_actions = []
    if session_resume_point:
        payload = manager.parse_resume_point(str(session_resume_point))
        result = None if dry_run else manager.execute_resume_point(payload, build_non_shot_resume_handlers(conn))
        if not dry_run:
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
    if args.dry_run:
        row = conn.execute(
            """
            SELECT count(DISTINCT r.chapter_id), count(*)
            FROM writing_chapter_reviews r
            JOIN writing_shots s
              ON s.project_id = r.project_id
             AND s.chapter_id = r.chapter_id
             AND s.run_id = r.run_id
            WHERE r.project_id = ?
              AND r.status = 'accepted'
              AND s.status = 'hard_sealed'
            """,
            (project_id,),
        ).fetchone()
        return {
            "project_id": project_id,
            "output": args.output,
            "accepted_chapters": int(row[0]),
            "hard_sealed_shots": int(row[1]),
        }
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


def _gateway(conn: sqlite3.Connection, args: argparse.Namespace) -> LLMGateway:
    if args.llm_provider == "deterministic":
        return LLMGateway(conn, provider=_CliDeterministicProvider(), provider_name="deterministic")
    config = load_llm_provider_config(
        provider=args.llm_provider,
        base_url=args.llm_base_url,
        api_key_env=args.llm_api_key_env,
        timeout_seconds=args.llm_timeout,
    )
    return LLMGateway(conn, provider=build_model_provider(config), provider_name=config.provider)


def _jsonable_result(value: object) -> object:
    if value is None:
        return None
    if is_dataclass(value) and not isinstance(value, type):
        return asdict(value)
    if isinstance(value, dict | list | tuple | str | int | float | bool):
        return value
    return str(value)


@dataclass(frozen=True)
class _SetupOptions:
    shots_per_chapter: int
    identity: dict[str, object]
    narrative_voice: dict[str, object]
    hard_boundaries: dict[str, object]
    style_locks: dict[str, object]
    world_knowledge: dict[str, object]
    motif_system: dict[str, object]
    creative_zones: dict[str, object]
    style_quality_profile: dict[str, object]
    rhythm_curve_target: object
    hook_target: str | None
    motif_density_target: float | None
    must_land_events: list[str]
    beats: list[str]
    information_releases: list[str]
    forbidden_facts: list[str]
    forbidden_words: list[str]
    pov_only: list[str]
    location: str
    time_of_day: str
    characters_present: list[str]
    character_positions: dict[str, str]
    persona: str
    persona_intensity: dict[str, int]
    is_creative_shot: bool
    relaxable_rules: list[str]
    deviation_budget: float


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


def _setup_options(args: argparse.Namespace) -> _SetupOptions:
    shots_per_chapter = int(args.shots_per_chapter)
    if shots_per_chapter < 1:
        raise SystemExit("setup --shots-per-chapter must be >= 1")
    persona_intensity = _json_object_arg(
        args.persona_intensity_json,
        {"画面": 7, "节奏": 6, "对话": 3, "结构": 6, "悬疑": 8},
        "--persona-intensity-json",
    )
    _validate_persona_intensity(persona_intensity)
    characters = _arg_list(args.character, ["她"])
    return _SetupOptions(
        shots_per_chapter=shots_per_chapter,
        identity=_json_object_arg(args.identity_json, {"project_identity": "local author draft"}, "--identity-json"),
        narrative_voice=_json_object_arg(
            args.narrative_voice_json,
            {"person": "third", "distance": "close", "texture": "clean suspense"},
            "--narrative-voice-json",
        ),
        hard_boundaries=_json_object_arg(args.hard_boundaries_json, {"forbidden": []}, "--hard-boundaries-json"),
        style_locks=_json_object_arg(args.style_locks_json, {"must_keep": []}, "--style-locks-json"),
        world_knowledge=_json_object_arg(args.world_knowledge_json, {"facts": []}, "--world-knowledge-json"),
        motif_system=_json_object_arg(args.motif_system_json, {"motifs": []}, "--motif-system-json"),
        creative_zones=_json_object_arg(args.creative_zones_json, {"allowed": []}, "--creative-zones-json"),
        style_quality_profile=_json_object_arg(
            args.style_quality_profile_json,
            {
                "target_reader": "genre reader",
                "benchmark": [],
                "positive_examples": [],
                "negative_examples": [],
                "banned_cliches": [],
            },
            "--style-quality-profile-json",
        ),
        rhythm_curve_target=_json_value_arg(args.rhythm_json, {}, "--rhythm-json"),
        hook_target=args.hook_target,
        motif_density_target=args.motif_density,
        must_land_events=_arg_list(args.must_land_event, ["她走进档案室"]),
        beats=_arg_list(args.beat, ["发现钥匙"]),
        information_releases=_arg_list(args.information_release, ["门外脚步"]),
        forbidden_facts=_arg_list(args.forbidden_fact, []),
        forbidden_words=_arg_list(args.forbidden_word, ["突然"]),
        pov_only=_arg_list(args.pov_only, ["她"]),
        location=args.location or "档案室",
        time_of_day=args.time_of_day or "夜晚",
        characters_present=characters,
        character_positions=_character_positions(args.character_position, characters),
        persona=args.persona or "悬疑官",
        persona_intensity={key: int(persona_intensity[key]) for key in ("画面", "节奏", "对话", "结构", "悬疑")},
        is_creative_shot=bool(args.creative_shot),
        relaxable_rules=_arg_list(args.relaxable_rule, ["metaphor"]),
        deviation_budget=0.2 if args.deviation_budget is None else float(args.deviation_budget),
    )


def _upsert_meta_contract(conn: sqlite3.Connection, project_id: int, options: _SetupOptions) -> None:
    row = conn.execute(
        "SELECT meta_contract_id FROM writing_meta_contracts WHERE project_id = ? ORDER BY meta_contract_id DESC LIMIT 1",
        (project_id,),
    ).fetchone()
    values = (
        _json_dumps(options.identity),
        _json_dumps(options.narrative_voice),
        _json_dumps(options.hard_boundaries),
        _json_dumps(options.style_locks),
        _json_dumps(options.world_knowledge),
        _json_dumps(options.motif_system),
        _json_dumps(options.creative_zones),
        _json_dumps(options.style_quality_profile),
    )
    if row is None:
        conn.execute(
            """
            INSERT INTO writing_meta_contracts
                (project_id, identity, narrative_voice, hard_boundaries, style_locks,
                 world_knowledge, motif_system, creative_zones, style_quality_profile, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'confirmed')
            """,
            (project_id, *values),
        )
        return
    conn.execute(
        """
        UPDATE writing_meta_contracts
        SET identity = ?, narrative_voice = ?, hard_boundaries = ?, style_locks = ?,
            world_knowledge = ?, motif_system = ?, creative_zones = ?,
            style_quality_profile = ?, status = 'confirmed'
        WHERE meta_contract_id = ?
        """,
        (*values, int(row[0])),
    )


def _insert_contract_children(conn: sqlite3.Connection, shot_contract_id: int, options: _SetupOptions) -> None:
    conn.execute(
        """
        INSERT INTO writing_shot_must_land
            (shot_contract_id, events, beats, information_releases)
        VALUES (?, ?, ?, ?)
        """,
        (
            shot_contract_id,
            _json_dumps(options.must_land_events),
            _json_dumps(options.beats),
            _json_dumps(options.information_releases),
        ),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_anti_write
            (shot_contract_id, forbidden_facts, forbidden_words, pov_only)
        VALUES (?, ?, ?, ?)
        """,
        (
            shot_contract_id,
            _json_dumps(options.forbidden_facts),
            _json_dumps(options.forbidden_words),
            _json_dumps(options.pov_only),
        ),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_scene_contract
            (shot_contract_id, location, time_of_day, characters_present, character_positions)
            VALUES (?, ?, ?, ?, ?)
        """,
        (
            shot_contract_id,
            options.location,
            options.time_of_day,
            _json_dumps(options.characters_present),
            _json_dumps(options.character_positions),
        ),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_persona_assignment
            (shot_contract_id, persona, intensity, is_creative_shot, is_suspense_shot)
            VALUES (?, ?, ?, ?, 1)
        """,
        (
            shot_contract_id,
            options.persona,
            _json_dumps(options.persona_intensity),
            int(options.is_creative_shot),
        ),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_soft_constraints
            (shot_contract_id, relaxable_rules, deviation_budget)
        VALUES (?, ?, ?)
        """,
        (shot_contract_id, _json_dumps(options.relaxable_rules), options.deviation_budget),
    )


def _json_value_arg(raw: str | None, default: object, field_name: str) -> object:
    if raw is None:
        return default
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{field_name} must be valid JSON") from exc


def _json_object_arg(raw: str | None, default: dict[str, object], field_name: str) -> dict[str, object]:
    value = _json_value_arg(raw, default, field_name)
    if not isinstance(value, dict):
        raise SystemExit(f"{field_name} must be a JSON object")
    return value


def _arg_list(values: list[str] | None, default: list[str]) -> list[str]:
    result = [value for value in (values or default) if value]
    if not result and default:
        return default
    return result


def _character_positions(values: list[str] | None, characters: list[str]) -> dict[str, str]:
    if not values:
        return {character: "场内" for character in characters}
    positions: dict[str, str] = {}
    for value in values:
        if "=" not in value:
            raise SystemExit("setup --character-position must use NAME=POSITION")
        name, position = value.split("=", 1)
        if not name or not position:
            raise SystemExit("setup --character-position must use NAME=POSITION")
        positions[name] = position
    for character in characters:
        positions.setdefault(character, "场内")
    return positions


def _validate_persona_intensity(payload: dict[str, object]) -> None:
    for key in ("画面", "节奏", "对话", "结构", "悬疑"):
        value = payload.get(key)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0 or value > 10:
            raise SystemExit(f"--persona-intensity-json must contain integer 0-10 for {key}")


def _json_dumps(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


if __name__ == "__main__":
    raise SystemExit(main())
