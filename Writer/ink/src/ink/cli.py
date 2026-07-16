from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from dataclasses import asdict, dataclass, is_dataclass
from pathlib import Path
from typing import Sequence

from ink.core.llm_gateway import LLMGateway, ModelResult, build_model_provider, load_llm_provider_config
from ink.core.capacity_planning import recommended_llm_capacity
from ink.jury.scores import SCORE_COLUMNS
from ink.core.model_role_config import (
    TIER_ORDER,
    list_role_configs,
    load_role_chain,
    upsert_role_config,
    validate_role_chain,
)
from ink.core.resume import ResumeManager
from ink.database import connect
from ink.decision_sessions import DecisionSessionStore
from ink.errors import ConfigError, InkError
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.pipeline.chesil_patch_orchestrator import ChesilPatchOrchestrator
from ink.pipeline.export_orchestrator import ExportOrchestrator
from ink.pipeline.scene_export_orchestrator import SceneExportOrchestrator
from ink.pipeline.ethics_review_orchestrator import EthicsReviewOrchestrator
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from ink.pipeline.import_orchestrator import ImportOrchestrator
from ink.pipeline.jury_orchestrator import JuryOrchestrator
from ink.pipeline.polish_orchestrator import PolishOrchestrator
from ink.pipeline.contract_review_orchestrator import (
    family_from_model_name,  # SPW 防绕过 H1：契约双盲审查的异族解析（模块级供 helper 用）
)
from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator
from ink.pipeline.resume_handlers import build_non_shot_resume_handlers, build_shot_resume_handlers
from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator
from ink.pipeline.targeted_repair_orchestrator import TargetedRepairOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator
from ink.production_readiness import backup_sqlite_database, inspect_personal_production
from ink.schema import initialize_schema
from ink.source_workflow import SourceWorkflowStore
from ink.stale_propagation import StalePropagationManager
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
    parser.add_argument(
        "--llm-max-tokens",
        type=int,
        help="Max output tokens for all models; reasoning models auto-inject a default if unset",
    )
    parser.add_argument(
        "--llm-max-retries",
        type=int,
        help="Retry count for transient provider errors (429/5xx/timeout); default 4 for openai-compatible",
    )
    subcommands = parser.add_subparsers(dest="command", required=True)

    doctor_cmd = subcommands.add_parser("doctor", help="Check personal-production launch readiness")
    doctor_cmd.add_argument("--project-id", type=int)
    doctor_cmd.set_defaults(handler=_cmd_doctor)

    backup_cmd = subcommands.add_parser("backup", help="Create and integrity-check a SQLite backup")
    backup_cmd.add_argument("--output", required=True)
    backup_cmd.set_defaults(handler=_cmd_backup)

    chesil_patch_cmd = subcommands.add_parser(
        "apply-chesil-patch",
        help="Apply an author-approved Chesil package as new Ink revisions and rerun review",
    )
    chesil_patch_cmd.add_argument("--project-id", type=int)
    chesil_patch_cmd.add_argument("--package", required=True)
    _add_dry_run(chesil_patch_cmd)
    chesil_patch_cmd.set_defaults(handler=_cmd_apply_chesil_patch)

    init_cmd = subcommands.add_parser("init")
    init_cmd.add_argument("--code", required=True)
    init_cmd.add_argument("--title", required=True)
    init_cmd.add_argument(
        "--writer-models",
        help="Comma-separated writer model IDs (writer_model_pool); "
        "default: writer-a,writer-b,writer-c",
    )
    init_cmd.add_argument(
        "--jury-models",
        help="Comma-separated jury model IDs (jury_model_pool); "
        "default: judge-a,judge-b,judge-c,judge-d,judge-e",
    )
    init_cmd.add_argument(
        "--model-aliases",
        help='Model alias mapping JSON, e.g. \'{"smart-polish":"xopglm51"}\'. '
        "Translates production aliases to real model names at the gateway layer.",
    )
    init_cmd.add_argument(
        "--role-config",
        help=(
            "Per-call_type model role chain JSON: "
            '{"<call_type>": {"primary": {"model_name","provider","base_url","api_key_env","max_tokens"}, '
            '"secondary": {...}, "tertiary": {...}}, ...}. '
            "Each call_type gets primary/secondary/tertiary tiers (failover: primary -> secondary -> tertiary). "
            "Cross-vendor recommended. If omitted, init auto-generates draft/jury primary-only rows from "
            "--writer-models/--jury-models for backward compatibility."
        ),
    )
    init_cmd.add_argument(
        "--min-eligible-outlines",
        type=int,
        help="Minimum eligible outlines to proceed (default 1; schema default 1). "
        "Real-model outlines often drift below threshold, 2 is too strict.",
    )
    init_cmd.add_argument(
        "--outline-drift-threshold",
        type=float,
        help="CJK bigram overlap rejection threshold (default 0.10; schema default 0.10). "
        "Real-model outlines easily fall below 0.20.",
    )
    init_cmd.add_argument(
        "--shot-quality-floor",
        type=int,
        help="Winner 最低 final_score（schema 默认 75；DB 硬底线 75）。"
        "真实模型 jury 常打 77-83，原默认 80 过严导致好稿被丢弃；75 让真实稿过门。",
    )
    init_cmd.add_argument(
        "--dimension-floor",
        type=int,
        help="12 维任一核心维度最低分（schema 默认 60；DB 硬底线 60）。",
    )
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
    confirm_cmd.add_argument("--decision-session-id", type=int, help="Confirm via DecisionSession confirm_and_apply (writes contract version + patch + changelog)")
    confirm_cmd.add_argument("--scope-type", choices=("book", "volume", "part", "chapter", "shot"), help="Contract scope for DecisionSession confirmation")
    confirm_cmd.add_argument("--scope-id", help="Contract scope id for scoped DecisionSession confirmation")
    confirm_cmd.add_argument("--contract-json", help="Confirmed contract payload JSON for DecisionSession confirmation")
    confirm_cmd.add_argument("--source-clause-ids", help="Comma-separated atomic source clause ids backing this contract")
    confirm_cmd.add_argument("--source-hashes", help="Comma-separated source hashes backing this contract")
    confirm_cmd.add_argument(
        "--skip-coverage-gate",
        action="store_true",
        help="Skip source coverage gate check (only with --decision-session-id; blocking gaps still block by default)",
    )
    confirm_cmd.add_argument(
        "--no-auto-stale",
        action="store_true",
        help="Skip automatic stale propagation after contract confirm (default: auto-mark downstream stale)",
    )
    _add_dry_run(confirm_cmd)
    confirm_cmd.set_defaults(handler=_cmd_confirm_contract)

    cov_cmd = subcommands.add_parser(
        "coverage-gaps",
        help="List uncovered/conflicting contract fields and suggested source clauses",
    )
    cov_cmd.add_argument("--scope-type", choices=("book", "volume", "part", "chapter", "shot"))
    cov_cmd.add_argument("--scope-id", help="Scope id to filter (e.g. chapter id)")
    cov_cmd.set_defaults(handler=_cmd_coverage_gaps)

    shot_cov_cmd = subcommands.add_parser(
        "shot-coverage",
        help="Show source-clause coverage for every shot in a chapter",
    )
    shot_cov_cmd.add_argument("--project-id", type=int)
    shot_cov_cmd.add_argument("--chapter", type=int, required=True)
    shot_cov_cmd.set_defaults(handler=_cmd_shot_coverage)

    shot_cov_set = subcommands.add_parser(
        "shot-coverage-set",
        help="Record auditable source-clause coverage evidence for one shot",
    )
    shot_cov_set.add_argument("--project-id", type=int)
    shot_cov_set.add_argument("--shot-id", required=True)
    shot_cov_set.add_argument("--atomic-clause-id", type=int, required=True)
    shot_cov_set.add_argument(
        "--status",
        required=True,
        choices=("covered", "gap", "conflict", "rejected", "deferred", "diagnostic"),
    )
    shot_cov_set.add_argument("--field-path", default="source_clauses")
    shot_cov_set.add_argument("--evidence-json", default="{}")
    _add_dry_run(shot_cov_set)
    shot_cov_set.set_defaults(handler=_cmd_shot_coverage_set)

    write_cmd = subcommands.add_parser("write")
    _add_chapter_run_args(write_cmd)
    _add_dry_run(write_cmd)
    write_cmd.set_defaults(handler=_cmd_write)

    review_cmd = subcommands.add_parser("review")
    _add_chapter_run_args(review_cmd)
    _add_dry_run(review_cmd)
    review_cmd.set_defaults(handler=_cmd_review)

    review_batch_cmd = subcommands.add_parser(
        "review-batch",
        help="Review multiple chapters with one real-provider gateway session",
    )
    review_batch_cmd.add_argument("--project-id", type=int)
    review_batch_cmd.add_argument("--run-id", type=int)
    review_batch_cmd.add_argument(
        "--chapters",
        required=True,
        help="Comma/range expression, for example 3-10 or 3,5,8",
    )
    review_batch_cmd.add_argument("--continue-on-error", action="store_true")
    _add_dry_run(review_batch_cmd)
    review_batch_cmd.set_defaults(handler=_cmd_review_batch)

    ethics_cmd = subcommands.add_parser("ethics-review")
    _add_chapter_run_args(ethics_cmd)
    ethics_cmd.add_argument("--actor", required=True)
    _add_dry_run(ethics_cmd)
    ethics_cmd.set_defaults(handler=_cmd_ethics_review)

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

    repair_cmd = subcommands.add_parser("repair")
    repair_cmd.add_argument("--shot-id", required=True)
    repair_cmd.add_argument("--run-id", type=int, required=True)
    repair_cmd.add_argument("--issue", required=True)
    repair_cmd.add_argument("--expected-pov")
    _add_dry_run(repair_cmd)
    repair_cmd.set_defaults(handler=_cmd_repair)

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

    scene_accept_cmd = subcommands.add_parser(
        "scene-accept",
        help="Scene-first: seal a selected frozen branch as the active Chapter Snapshot",
    )
    scene_accept_cmd.add_argument("--project-id", type=int)
    scene_accept_cmd.add_argument("--chapter-id", type=int, required=True)
    scene_accept_cmd.add_argument("--branch-version-id", type=int, required=True)
    scene_accept_cmd.add_argument("--actor", required=True, help="human actor id (no ai:/model:/auto: prefix)")
    scene_accept_cmd.add_argument("--reason", default="approved")
    _add_dry_run(scene_accept_cmd)
    scene_accept_cmd.set_defaults(handler=_cmd_scene_accept)

    scene_export_cmd = subcommands.add_parser(
        "scene-export",
        help="Scene-first: export a project from its active sealed Chapter Snapshots",
    )
    scene_export_cmd.add_argument("--project-id", type=int)
    scene_export_cmd.add_argument("--output")
    _add_dry_run(scene_export_cmd)
    scene_export_cmd.set_defaults(handler=_cmd_scene_export)

    scene_export_parity_cmd = subcommands.add_parser(
        "scene-export-parity",
        help="Scene-first: read-only dual-authority parity check (pre-cutover safety)",
    )
    scene_export_parity_cmd.add_argument("--project-id", type=int)
    _add_dry_run(scene_export_parity_cmd)
    scene_export_parity_cmd.set_defaults(handler=_cmd_scene_export_parity)

    produce_chapter_cmd = subcommands.add_parser(
        "produce-chapter",
        help="Scene-first end-to-end: outline -> real-model draft -> jury -> accept -> export",
    )
    produce_chapter_cmd.add_argument("--project-id", type=int)
    produce_chapter_cmd.add_argument("--chapter-id", type=int, required=True, help="chapter number (1, 2, ...)")
    produce_chapter_cmd.add_argument(
        "--outline-file",
        help="path to the chapter outline md (e.g. 24_分章大纲.md); required unless --force-branch-version-id",
    )
    produce_chapter_cmd.add_argument("--candidates", type=int, default=2, help="initial candidate count (default 2)")
    produce_chapter_cmd.add_argument("--rounds", type=int, default=2, help="max round attempts before giving up (default 2)")
    produce_chapter_cmd.add_argument("--actor", required=True, help="human actor id (no ai:/model:/auto: prefix)")
    produce_chapter_cmd.add_argument("--reason", default="produced via produce-chapter")
    produce_chapter_cmd.add_argument("--output", help="write exported chapter text to this path; omit to accept only")
    produce_chapter_cmd.add_argument(
        "--no-accept",
        action="store_true",
        help="produce candidates + jury winner but do NOT accept/seal; output (if given) writes the winner branch text, for author review (ch01 redo: produce without sealing)",
    )
    produce_chapter_cmd.add_argument(
        "--force-branch-version-id",
        type=int,
        help="skip generation, force-accept this frozen branch version (human takeover)",
    )
    _add_dry_run(produce_chapter_cmd)
    produce_chapter_cmd.set_defaults(handler=_cmd_produce_chapter)

    _add_decision_session_subcommands(subcommands)
    _add_debug_subcommands(subcommands)
    _add_role_config_subcommands(subcommands)
    return parser


def _add_role_config_subcommands(subcommands: argparse._SubParsersAction) -> None:
    """模型角色主/备/兜底配置：role-config set / get / validate。

    每 call_type 三档（primary/secondary/tertiary），尽量跨供应商；gateway 失败逐 tier 切。
    """
    rc_cmd = subcommands.add_parser(
        "role-config", help="按 call_type 的模型角色主/备/兜底配置"
    )
    rc_sub = rc_cmd.add_subparsers(dest="role_config_action", required=True)

    set_cmd = rc_sub.add_parser("set", help="设置/更新单条 role config（UPSERT）")
    set_cmd.add_argument("--project-id", type=int, required=True)
    set_cmd.add_argument("--call-type", required=True, help="outline/draft/jury/polish/chapter_review/book_check/...")
    set_cmd.add_argument("--tier", required=True, choices=list(TIER_ORDER))
    set_cmd.add_argument("--model-name", required=True, help="真实模型名（不存别名）")
    set_cmd.add_argument("--provider", required=True, help="openai-compatible 或 mock")
    set_cmd.add_argument("--base-url", help="openai-compatible 的 base_url")
    set_cmd.add_argument("--api-key-env", required=True, help="环境变量名（不存明文 key）")
    set_cmd.add_argument("--max-tokens", type=int)
    set_cmd.set_defaults(handler=_cmd_role_config_set)

    get_cmd = rc_sub.add_parser("get", help="列出某项目的 role config")
    get_cmd.add_argument("--project-id", type=int, required=True)
    get_cmd.add_argument("--call-type", help="可选，限定单 call_type")
    get_cmd.set_defaults(handler=_cmd_role_config_get)

    val_cmd = rc_sub.add_parser("validate", help="校验某 call_type 的 role chain 完整性")
    val_cmd.add_argument("--project-id", type=int, required=True)
    val_cmd.add_argument("--call-type", required=True)
    val_cmd.set_defaults(handler=_cmd_role_config_validate)


def _cmd_doctor(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    return inspect_personal_production(conn, _project_id(conn, args))


def _cmd_backup(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    conn.commit()
    return backup_sqlite_database(args.db, args.output)


def _cmd_apply_chesil_patch(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    package = json.loads(Path(args.package).read_text(encoding="utf-8"))
    patches = package.get("patches", [])
    if args.dry_run:
        return {
            "project_id": project_id,
            "package": str(Path(args.package).resolve()),
            "patch_count": len(patches),
            "targets": [
                {"shot_id": item.get("ink_shot_id"), "run_id": item.get("ink_run_id")}
                for item in patches
            ],
        }
    if args.llm_provider != "openai-compatible":
        raise ConfigError(
            "apply-chesil-patch requires --llm-provider openai-compatible for real review"
        )
    result = ChesilPatchOrchestrator(conn, _gateway(conn, args)).apply(
        args.package, project_id=project_id
    )
    return {
        "project_id": project_id,
        "applied_revision_ids": list(result.applied_revision_ids),
        "reviewed_chapters": list(result.reviewed_chapters),
        "review_ids": list(result.review_ids),
        "ethics_review_required": True,
        "author_acceptance_required": True,
    }


def _cmd_role_config_set(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    rc_id = upsert_role_config(
        conn,
        project_id=args.project_id,
        call_type=args.call_type,
        tier=args.tier,
        model_name=args.model_name,
        provider=args.provider,
        api_key_env=args.api_key_env,
        base_url=args.base_url,
        max_tokens=args.max_tokens,
    )
    return {"role_config_id": rc_id, "call_type": args.call_type, "tier": args.tier}


def _cmd_role_config_get(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    configs = list_role_configs(
        conn,
        project_id=args.project_id,
        call_type=getattr(args, "call_type", None),
    )
    return {
        "configs": [
            {
                "call_type": c.call_type,
                "tier": c.tier,
                "model_name": c.model_name,
                "provider": c.provider,
                "base_url": c.base_url,
                "api_key_env": c.api_key_env,
                "max_tokens": c.max_tokens,
            }
            for c in configs
        ]
    }


def _cmd_role_config_validate(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    chain = load_role_chain(conn, project_id=args.project_id, call_type=args.call_type)
    errors = validate_role_chain(chain)
    return {
        "call_type": args.call_type,
        "chain": [{"tier": c.tier, "model_name": c.model_name, "provider": c.provider} for c in chain],
        "valid": not errors,
        "errors": errors,
    }


def _add_debug_subcommands(subcommands: argparse._SubParsersAction) -> None:
    """专家模式可展开审计与事件状态回放。"""
    from ink.debug_view import DebugView

    dbg_cmd = subcommands.add_parser("debug", help="专家模式审计视图")
    dbg_sub = dbg_cmd.add_subparsers(dest="debug_action", required=True)

    audit = dbg_sub.add_parser("audit", help="Session 审计聚合")
    audit.add_argument("--session-id", type=int, required=True)
    audit.set_defaults(handler=_cmd_debug_audit)

    timeline = dbg_sub.add_parser("timeline", help="契约版本时间线")
    timeline.add_argument("--project-id", type=int, required=True)
    timeline.add_argument("--scope-type", required=True)
    timeline.add_argument("--scope-id")
    timeline.set_defaults(handler=_cmd_debug_timeline)

    trace = dbg_sub.add_parser("trace", help="Shot 完整链路")
    trace.add_argument("--shot-id", required=True)
    trace.set_defaults(handler=_cmd_debug_trace)

    stale = dbg_sub.add_parser("stale", help="Stale 传播链")
    stale.add_argument("--project-id", type=int, required=True)
    stale.set_defaults(handler=_cmd_debug_stale)

    replay_session = dbg_sub.add_parser("replay-session", help="从事件流重建 Session 状态")
    replay_session.add_argument("--session-id", type=int, required=True)
    replay_session.add_argument("--at-event-id", type=int)
    replay_session.add_argument("--at-time")
    replay_session.set_defaults(handler=_cmd_debug_replay_session)

    replay_contract = dbg_sub.add_parser("replay-contract", help="从事件流重建契约状态")
    replay_contract.add_argument("--project-id", type=int, required=True)
    replay_contract.add_argument("--scope-type", required=True)
    replay_contract.add_argument("--scope-id")
    replay_contract.add_argument("--at-event-id", type=int)
    replay_contract.add_argument("--at-time")
    replay_contract.set_defaults(handler=_cmd_debug_replay_contract)


def _add_decision_session_subcommands(subcommands: argparse._SubParsersAction) -> None:
    """选择式对话协议 CLI：start / parse / options / regenerate / select / show。

    主编台用 1-8 编号选项、0 返回、9 重新生成；恢复时 show 回放原 option set，
    不依赖模型重新想一版。
    """
    ds_cmd = subcommands.add_parser("decision-session", help="DecisionSession 选择式对话协议")
    ds_sub = ds_cmd.add_subparsers(dest="ds_action", required=True)

    start = ds_sub.add_parser("start")
    start.add_argument("--project-id", type=int)
    start.add_argument("--scope-type", required=True, choices=("book", "volume", "part", "chapter", "shot", "review", "import", "source"))
    start.add_argument("--scope-id")
    start.add_argument("--target-type", required=True)
    start.add_argument("--target-id")
    start.add_argument("--human-text", required=True)
    start.add_argument("--parent-decision-session-id", type=int)
    _add_dry_run(start)
    start.set_defaults(handler=_cmd_ds_start)

    parse = ds_sub.add_parser("parse")
    parse.add_argument("decision_session_id", type=int)
    parse.add_argument("--parsed-patch-json", required=True)
    parse.add_argument("--readback-text", required=True)
    parse.add_argument("--source-hashes", help="Comma-separated source hashes")
    parse.add_argument("--before-hash")
    _add_dry_run(parse)
    parse.set_defaults(handler=_cmd_ds_parse)

    options = ds_sub.add_parser("options")
    options.add_argument("decision_session_id", type=int)
    options.add_argument("--options-json", required=True, help="JSON array of 1-8 option objects")
    options.add_argument("--recommended-option", type=int)
    _add_dry_run(options)
    options.set_defaults(handler=_cmd_ds_options)

    regenerate = ds_sub.add_parser("regenerate")
    regenerate.add_argument("decision_session_id", type=int)
    regenerate.add_argument("--options-json", required=True)
    regenerate.add_argument("--recommended-option", type=int)
    _add_dry_run(regenerate)
    regenerate.set_defaults(handler=_cmd_ds_regenerate)

    select = ds_sub.add_parser("select")
    select.add_argument("decision_session_id", type=int)
    select.add_argument("selected_option", type=int, help="1-8 to choose, 0 to return, 9 requires regenerate")
    _add_dry_run(select)
    select.set_defaults(handler=_cmd_ds_select)

    show = ds_sub.add_parser("show")
    show.add_argument("decision_session_id", type=int)
    _add_dry_run(show)
    show.set_defaults(handler=_cmd_ds_show)


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


def _parse_model_pool(raw: str | None, *, default: list[str]) -> list[str]:
    """Parse a comma-separated model list into a deduped, order-preserving list."""
    if raw is None or not raw.strip():
        return list(default)
    models: list[str] = []
    seen: set[str] = set()
    for token in raw.split(","):
        mid = token.strip()
        if mid and mid not in seen:
            seen.add(mid)
            models.append(mid)
    if not models:
        return list(default)
    return models


def _seed_primary_from_pool(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    call_type: str,
    model_name: str,
) -> None:
    """向后兼容：无 --role-config 时，用旧池首个模型生成 draft/jury primary 单档。

    provider/base_url/api_key_env 取当前 INK_LLM_* 环境变量默认值（与 LLMGateway 默认一致）。
    failover 链只有 1 档，不跨供应商——用户后续用 'ink role-config set' 补齐 secondary/tertiary。
    """
    env = os.environ
    provider = (env.get("INK_LLM_PROVIDER") or "mock").strip().lower().replace("_", "-")
    if provider == "mock":
        # mock 环境无真实 key_env，用占位 env 名（gateway 走 MockProvider 不读 key）。
        upsert_role_config(
            conn,
            project_id=project_id,
            call_type=call_type,
            tier="primary",
            model_name=model_name,
            provider="mock",
            api_key_env="INK_LLM_API_KEY",
        )
        return
    upsert_role_config(
        conn,
        project_id=project_id,
        call_type=call_type,
        tier="primary",
        model_name=model_name,
        provider="openai-compatible",
        base_url=env.get("INK_LLM_BASE_URL"),
        api_key_env=env.get("INK_LLM_API_KEY_ENV") or "INK_LLM_API_KEY",
        max_tokens=env.get("INK_LLM_MAX_TOKENS") or None,
    )


def _cmd_init(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, int]:
    now = now_utc_iso()
    writer_pool = _parse_model_pool(
        getattr(args, "writer_models", None),
        default=["writer-a", "writer-b", "writer-c"],
    )
    jury_pool = _parse_model_pool(
        getattr(args, "jury_models", None),
        default=["judge-a", "judge-b", "judge-c", "judge-d", "judge-e"],
    )
    writer_pool_json = json.dumps(writer_pool, ensure_ascii=False)
    jury_pool_json = json.dumps(jury_pool, ensure_ascii=False)
    project_cursor = conn.execute(
        """
        INSERT INTO writing_projects
            (code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        (args.code, args.title, writer_pool_json, jury_pool_json, now),
    )
    project_id = int(project_cursor.lastrowid)

    # 可选运营参数：仅在 CLI 显式提供时覆盖 schema 默认值。
    updates: dict[str, object] = {}
    aliases_raw = getattr(args, "model_aliases", None)
    if aliases_raw:
        try:
            aliases = json.loads(aliases_raw)
        except json.JSONDecodeError as exc:
            raise ConfigError(f"--model-aliases JSON parse failed: {exc}") from exc
        if not isinstance(aliases, dict):
            raise ConfigError("--model-aliases must be a JSON object {alias: real_model}")
        updates["model_aliases"] = json.dumps(
            {str(k): str(v) for k, v in aliases.items() if v}, ensure_ascii=False
        )
    if args.min_eligible_outlines is not None:
        updates["min_eligible_outlines"] = args.min_eligible_outlines
    if args.outline_drift_threshold is not None:
        updates["outline_drift_threshold"] = args.outline_drift_threshold
    if args.shot_quality_floor is not None:
        updates["shot_quality_floor"] = args.shot_quality_floor
    if args.dimension_floor is not None:
        updates["dimension_floor"] = args.dimension_floor
    if updates:
        assignments = ", ".join(f"{col} = ?" for col in updates)
        conn.execute(
            f"UPDATE writing_projects SET {assignments} WHERE project_id = ?",
            (*updates.values(), project_id),
        )

    # 真实 jury 容量按候选、creative extra、retry wave 和 disagreement escalation 推导。
    capacity_row = conn.execute(
        """
        SELECT draft_count, creative_shot_extra, redo_candidate_count, escalated_jury_count
        FROM writing_projects WHERE project_id=?
        """,
        (project_id,),
    ).fetchone()
    capacity = recommended_llm_capacity(
        draft_count=int(capacity_row[0]),
        creative_shot_extra=int(capacity_row[1]),
        redo_candidate_count=int(capacity_row[2]),
        escalated_jury_count=int(capacity_row[3]),
    )
    conn.execute(
        "UPDATE writing_projects SET max_calls_per_shot = ?, max_total_llm_calls = ? WHERE project_id = ?",
        (capacity.jury_calls, capacity.total_calls, project_id),
    )

    # 模型角色主/备/兜底配置：--role-config JSON 显式配，或从旧 --writer-models/--jury-models
    # 自动生成 draft/jury 的 primary 单档（向后兼容）。gateway.call 按 call_type 取链 failover。
    role_cfg_raw = getattr(args, "role_config", None)
    if role_cfg_raw:
        try:
            role_cfg = json.loads(role_cfg_raw)
        except json.JSONDecodeError as exc:
            raise ConfigError(f"--role-config JSON parse failed: {exc}") from exc
        if not isinstance(role_cfg, dict):
            raise ConfigError("--role-config must be a JSON object {call_type: {tier: {...}}}")
        for call_type, tiers in role_cfg.items():
            if not isinstance(tiers, dict):
                raise ConfigError(f"--role-config[{call_type}] must be a JSON object {tier: {...}}")
            for tier, spec in tiers.items():
                if tier not in TIER_ORDER:
                    raise ConfigError(f"--role-config[{call_type}] tier must be one of {TIER_ORDER}, got {tier!r}")
                if not isinstance(spec, dict):
                    raise ConfigError(f"--role-config[{call_type}][{tier}] must be a JSON object")
                try:
                    upsert_role_config(
                        conn,
                        project_id=project_id,
                        call_type=str(call_type),
                        tier=tier,
                        model_name=str(spec["model_name"]),
                        provider=str(spec["provider"]),
                        api_key_env=str(spec["api_key_env"]),
                        base_url=spec.get("base_url"),
                        max_tokens=spec.get("max_tokens"),
                    )
                except KeyError as exc:
                    raise ConfigError(
                        f"--role-config[{call_type}][{tier}] missing required key: {exc}"
                    ) from exc
    else:
        # 向后兼容：无 role-config 时，用旧池首个模型生成各 call_type 的 primary 单档。
        # 跨供应商 failover 需用户后续用 'ink role-config set' 补齐 secondary/tertiary。
        _seed_primary_from_pool(conn, project_id=project_id, call_type="draft", model_name=writer_pool[0])
        _seed_primary_from_pool(conn, project_id=project_id, call_type="jury", model_name=jury_pool[0])
        # chapter_review/book_check 属评审类，复用 jury 池首模型；真实化后必须配 role_config，
        # 否则 gateway 无 role_chain 会回退注入式 provider（真实部署报错）。
        _seed_primary_from_pool(conn, project_id=project_id, call_type="chapter_review", model_name=jury_pool[0])
        _seed_primary_from_pool(conn, project_id=project_id, call_type="book_check", model_name=jury_pool[0])

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


def _cmd_confirm_contract(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    if args.dry_run:
        return {"project_id": project_id, "planned_decisions": 1}
    if args.decision_session_id is not None:
        return _confirm_via_decision_session(conn, args, project_id)
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


def _confirm_via_decision_session(conn: sqlite3.Connection, args: argparse.Namespace, project_id: int) -> dict[str, object]:
    if args.scope_type is None:
        raise SystemExit("confirm-contract --decision-session-id requires --scope-type")
    if args.contract_json is None:
        raise SystemExit("confirm-contract --decision-session-id requires --contract-json")
    try:
        contract_payload = json.loads(args.contract_json)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"--contract-json must be valid JSON: {exc}") from exc
    if not isinstance(contract_payload, dict):
        raise SystemExit("--contract-json must be a JSON object")
    # 默认接入 source coverage gate：blocking gap 未清空时阻断确认。
    # --skip-coverage-gate 仅在无 source documents 记录时才真正无影响；有 gap 时仍按默认阻断。
    coverage_gate = None if args.skip_coverage_gate else SourceWorkflowStore(conn)
    stale_manager = None if args.no_auto_stale else StalePropagationManager(conn)
    result = DecisionSessionStore(conn).confirm_and_apply(
        args.decision_session_id,
        actor=args.actor,
        reason=args.reason,
        contract_scope_type=args.scope_type,
        contract_scope_id=args.scope_id,
        contract_payload=contract_payload,
        source_clause_ids=_csv_ints(args.source_clause_ids),
        source_hashes=_csv_strings(args.source_hashes),
        coverage_gate=coverage_gate,
        stale_manager=stale_manager,
    )
    payload = {
        "decision_session_id": result.decision_session_id,
        "human_decision_id": result.human_decision_id,
        "contract_version_id": result.contract_version_id,
        "contract_patch_id": result.contract_patch_id,
        "contract_changelog_id": result.contract_changelog_id,
        "after_hash": result.after_hash,
    }
    if result.stale_mark is not None:
        sm = result.stale_mark
        payload["stale_mark"] = {
            "scope_type": sm.scope_type,
            "scope_id": sm.scope_id,
            "affected_prompt_ids": list(sm.affected_prompt_ids),
            "affected_draft_ids": list(sm.affected_draft_ids),
            "affected_review_ids": list(sm.affected_review_ids),
            "affected_check_ids": list(sm.affected_check_ids),
        }
    return payload


def _cmd_coverage_gaps(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    """列出未覆盖/冲突字段明细 + 建议源条款。"""
    project_id = _project_id(conn, args)
    store = SourceWorkflowStore(conn)
    gaps = store.list_coverage_gaps(
        project_id=project_id,
        contract_scope_type=args.scope_type,
        contract_scope_id=args.scope_id,
    )
    return {
        "project_id": project_id,
        "total_gaps": len(gaps),
        "gaps": [
            {
                "coverage_id": g.coverage_id,
                "scope_type": g.scope_type,
                "scope_id": g.scope_id,
                "field_path": g.field_path,
                "status": g.status,
                "atomic_clause_id": g.atomic_clause_id,
                "suggested_clause_ids": list(g.suggested_clause_ids),
                "evidence": g.evidence,
            }
            for g in gaps
        ],
    }


def _cmd_shot_coverage(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    matrix = SourceWorkflowStore(conn).chapter_shot_coverage(
        project_id=project_id,
        chapter_id=args.chapter,
    )
    shots: list[dict[str, object]] = []
    total = 0
    blocking = 0
    for shot_id, records in matrix.items():
        gaps = [
            record
            for record in records
            if record.coverage_status in {"gap", "conflict"}
        ]
        total += len(records)
        blocking += len(gaps)
        shots.append(
            {
                "shot_id": shot_id,
                "applicable_clause_count": len(records),
                "blocking_clause_count": len(gaps),
                "clauses": [
                    {
                        "atomic_clause_id": record.atomic_clause_id,
                        "clause_scope_type": record.clause_scope_type,
                        "clause_scope_id": record.clause_scope_id,
                        "clause_type": record.clause_type,
                        "severity": record.severity,
                        "clause_text": record.clause_text,
                        "coverage_status": record.coverage_status,
                        "evidence": record.evidence,
                    }
                    for record in records
                ],
            }
        )
    return {
        "project_id": project_id,
        "chapter_id": args.chapter,
        "shot_count": len(shots),
        "applicable_clause_count": total,
        "blocking_clause_count": blocking,
        "coverage_complete": blocking == 0,
        "shots": shots,
    }


def _cmd_shot_coverage_set(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    try:
        evidence = json.loads(args.evidence_json)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"--evidence-json must be valid JSON: {exc}") from exc
    if not isinstance(evidence, dict):
        raise SystemExit("--evidence-json must contain a JSON object")
    if args.dry_run:
        return {
            "project_id": project_id,
            "shot_id": args.shot_id,
            "atomic_clause_id": args.atomic_clause_id,
            "coverage_status": args.status,
            "field_path": args.field_path,
            "evidence": evidence,
        }
    coverage_id = SourceWorkflowStore(conn).record_shot_clause_coverage(
        project_id=project_id,
        shot_id=args.shot_id,
        atomic_clause_id=args.atomic_clause_id,
        coverage_status=args.status,
        contract_field_path=args.field_path,
        evidence=evidence,
    )
    conn.commit()
    return {
        "coverage_id": coverage_id,
        "project_id": project_id,
        "shot_id": args.shot_id,
        "atomic_clause_id": args.atomic_clause_id,
        "coverage_status": args.status,
    }


def _cmd_write(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    capacity = _project_capacity_plan(conn, project_id)
    gateway = _gateway(conn, args)
    shot_ids = _chapter_shots(conn, project_id, args.chapter, run_id)
    if args.dry_run:
        return {
            "project_id": project_id,
            "chapter_id": args.chapter,
            "run_id": run_id,
            "planned_shots": shot_ids,
            "recommended_jury_calls": capacity.jury_calls,
            "recommended_total_calls": capacity.total_calls,
        }
    configured = conn.execute(
        "SELECT max_calls_per_shot, max_total_llm_calls FROM writing_projects WHERE project_id=?",
        (project_id,),
    ).fetchone()
    if int(configured[0]) < capacity.jury_calls or int(configured[1]) < capacity.total_calls:
        raise ConfigError(
            "LLM capacity preflight failed: "
            f"configured per_type/total={configured[0]}/{configured[1]}, "
            f"recommended>={capacity.jury_calls}/{capacity.total_calls}; "
            "increase writing_projects budgets before starting real production"
        )
    written: list[str] = []
    skipped: list[str] = []
    for shot_id in shot_ids:
        status = conn.execute(
            "SELECT status FROM writing_shots WHERE shot_id = ? AND run_id = ?",
            (shot_id, run_id),
        ).fetchone()
        # 幂等续跑：已 soft_sealed（终态）的 shot 直接跳过，否则 _run_shot_to_soft_sealed 首步
        # run_until_prompt_compiled 会因 status 不在预期枚举而抛 DataIntegrityError。
        if status is not None and status[0] == "soft_sealed":
            skipped.append(shot_id)
            continue
        _run_shot_to_soft_sealed(conn, shot_id, run_id, gateway)
        # 逐 shot 提交：真模型单章全链路耗时数十分钟，整章单事务会令内存峰值随 shot 线性堆积
        # 直至爆内存。每 shot soft_seal 成功即 commit，持久化进度并释放未提交缓冲，后续 shot 失败
        # 也不丢已完成稿；进度可被 resume 幂等���跑。
        conn.commit()
        written.append(shot_id)
    return {
        "project_id": project_id,
        "chapter_id": args.chapter,
        "run_id": run_id,
        "soft_sealed": written,
        "skipped_already_soft_sealed": skipped,
    }


def _project_capacity_plan(conn: sqlite3.Connection, project_id: int):
    row = conn.execute(
        """
        SELECT draft_count, creative_shot_extra, redo_candidate_count, escalated_jury_count
        FROM writing_projects WHERE project_id=?
        """,
        (project_id,),
    ).fetchone()
    if row is None:
        raise ConfigError(f"project not found: {project_id}")
    return recommended_llm_capacity(
        draft_count=int(row[0]),
        creative_shot_extra=int(row[1]),
        redo_candidate_count=int(row[2]),
        escalated_jury_count=int(row[3]),
    )


def _cmd_review(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    shot_ids = _chapter_shots(conn, project_id, args.chapter, run_id)
    if args.dry_run:
        return {"project_id": project_id, "chapter_id": args.chapter, "run_id": run_id, "planned_review_shots": shot_ids}
    review = ChapterReviewOrchestrator(conn, _gateway(conn, args)).review_chapter(project_id, args.chapter, run_id)
    return {"review_id": review.review_id, "quality_gate_passed": review.quality_gate_passed}


def _cmd_review_batch(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    chapters = _parse_int_ranges(args.chapters)
    plans = [
        {
            "chapter_id": chapter_id,
            "shot_ids": _chapter_shots(conn, project_id, chapter_id, run_id),
        }
        for chapter_id in chapters
    ]
    if args.dry_run:
        return {
            "project_id": project_id,
            "run_id": run_id,
            "chapter_count": len(plans),
            "plans": plans,
        }
    gateway = _gateway(conn, args)
    reviewer = ChapterReviewOrchestrator(conn, gateway)
    results: list[dict[str, object]] = []
    for plan in plans:
        chapter_id = int(plan["chapter_id"])
        try:
            review = reviewer.review_chapter(project_id, chapter_id, run_id)
        except Exception as exc:
            results.append(
                {
                    "chapter_id": chapter_id,
                    "status": "error",
                    "error_type": type(exc).__name__,
                    "error": str(exc),
                }
            )
            if not args.continue_on_error:
                raise
        else:
            results.append(
                {
                    "chapter_id": chapter_id,
                    "status": "completed",
                    "review_id": review.review_id,
                    "quality_gate_passed": review.quality_gate_passed,
                }
            )
    passed = sum(
        1 for item in results if item.get("quality_gate_passed") is True
    )
    return {
        "project_id": project_id,
        "run_id": run_id,
        "chapter_count": len(chapters),
        "completed_count": sum(1 for item in results if item["status"] == "completed"),
        "passed_count": passed,
        "failed_gate_count": sum(
            1
            for item in results
            if item["status"] == "completed"
            and item.get("quality_gate_passed") is False
        ),
        "error_count": sum(1 for item in results if item["status"] == "error"),
        "results": results,
    }


def _cmd_ethics_review(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    run_id = _run_id(conn, args, project_id)
    if args.dry_run:
        return {
            "project_id": project_id,
            "chapter_id": args.chapter,
            "run_id": run_id,
            "reviewer_actor": args.actor,
            "planned_action": "three_model_ethics_review",
        }
    result = EthicsReviewOrchestrator(conn, _gateway(conn, args)).review_chapter(
        project_id,
        args.chapter,
        run_id,
        reviewer_actor=args.actor,
    )
    return {
        "ethics_review_id": result.ethics_review_id,
        "project_id": project_id,
        "chapter_id": args.chapter,
        "run_id": run_id,
        "risk_level": result.risk_level,
        "recommendation": result.recommendation,
        "reviewer_models": list(result.reviewer_models),
    }


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


def _cmd_repair(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    if args.dry_run:
        return {
            "shot_id": args.shot_id,
            "run_id": args.run_id,
            "planned_action": "targeted_repair_then_chapter_review",
            "expected_pov": args.expected_pov,
            "issue": args.issue,
        }
    gateway = _gateway(conn, args)
    repaired = TargetedRepairOrchestrator(conn, gateway).repair(
        args.shot_id,
        args.run_id,
        issue=args.issue,
        expected_pov=args.expected_pov,
    )
    review = ChapterReviewOrchestrator(conn, gateway).review_chapter(
        repaired.project_id,
        repaired.chapter_id,
        repaired.run_id,
    )
    return {
        "project_id": repaired.project_id,
        "chapter_id": repaired.chapter_id,
        "shot_id": repaired.shot_id,
        "run_id": repaired.run_id,
        "source_revision_id": repaired.source_revision_id,
        "revision_id": repaired.revision_id,
        "model_name": repaired.model_name,
        "length_before": repaired.length_before,
        "length_after": repaired.length_after,
        "review_id": review.review_id,
        "quality_gate_passed": review.quality_gate_passed,
        "blocking_issues": list(review.blocking_issues),
    }


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
        result = None if dry_run else manager.execute_resume_point(
            payload, build_non_shot_resume_handlers(conn, _gateway(conn, args))
        )
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


def _cmd_scene_accept(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository

    repo = ChapterSnapshotRepository(conn)
    existing = repo.get_active_snapshot_id(project_id=project_id, chapter_id=args.chapter_id)
    expected = 0 if existing is None else int(
        conn.execute(
            "SELECT version FROM writing_chapter_heads WHERE project_id = ? AND chapter_id = ?",
            (project_id, args.chapter_id),
        ).fetchone()[0]
    )
    if args.dry_run:
        return {
            "project_id": project_id,
            "chapter_id": args.chapter_id,
            "branch_version_id": args.branch_version_id,
            "actor": args.actor,
            "expected_head_version": expected,
            "would": "record decisions + seal snapshot + CAS head + emit CHAPTER_ACCEPTED",
        }
    head_row = repo.accept_chapter(
        branch_version_id=args.branch_version_id,
        expected_head_version=expected,
        actor=args.actor,
        reason=args.reason,
        preconditions_json={"branch_version_id": args.branch_version_id},
        selection_decision_type="human_override",
        selection_evidence_json={
            "branch_version_id": args.branch_version_id,
            "source": "scene-accept",
        },
    )
    return {
        "project_id": project_id,
        "chapter_id": args.chapter_id,
        "snapshot_id": head_row.active_snapshot_id,
        "head_version": head_row.version,
        "accepted_decision_id": head_row.accepted_decision_id,
        "selection_decision_id": head_row.selection_decision_id,
    }


def _cmd_scene_export(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    if args.dry_run:
        rows = conn.execute(
            "SELECT count(DISTINCT chapter_id) FROM writing_chapter_heads WHERE project_id = ?",
            (project_id,),
        ).fetchone()
        return {"project_id": project_id, "output": args.output, "accepted_chapters": int(rows[0])}
    artifact = SceneExportOrchestrator(conn).export_project(project_id)
    if args.output:
        Path(args.output).write_text(artifact, encoding="utf-8")
        return {"project_id": project_id, "output": args.output, "bytes": len(artifact.encode("utf-8"))}
    return {"project_id": project_id, "artifact": artifact}


def _cmd_produce_chapter(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    """End-to-end Scene-first production: outline -> real-model drafts -> jury
    quality gate -> accept as active Chapter Snapshot -> (optional) export.

    Idempotent + resumable: an existing active snapshot skips generation; a
    non-terminal round is resumed; a terminal-but-unaccepted round rolls to
    ``round_number + 1``. ``--force-branch-version-id`` takes over after a
    failed round by force-accepting a frozen branch.
    """
    project_id = _project_id(conn, args)
    chapter_id = args.chapter_id
    from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
    from ink.core.scene_repository import SceneRepository
    from ink.pipeline.generation_round_driver import GenerationRoundDriver
    from ink.pipeline.generation_round_real_ports import (
        RealGenerationPort,
        RealSelectionPort,
        RealValidationPort,
    )
    from ink.source.outline_parser import parse_outline
    from ink.source.outline_to_contract import outline_to_four_layer_clauses
    from ink.contract.brief_compiler import compile_brief
    from ink.pipeline.contract_review_orchestrator import (
        ContractReviewOrchestrator, ContractReviewLLMFailure,
    )

    repo = ChapterSnapshotRepository(conn)
    scene_repo = SceneRepository(conn)

    # Human takeover: force-accept a previously-generated frozen branch without
    # driving a new round.
    if args.force_branch_version_id is not None:
        return _force_accept_and_export(
            conn, repo, project_id, chapter_id, args.force_branch_version_id,
            args.actor, args.reason, args.output,
        )

    # Idempotent: already sealed chapter -> skip generation, just export.
    existing_snapshot = repo.get_active_snapshot_id(project_id=project_id, chapter_id=chapter_id)
    if existing_snapshot is not None:
        exported = _maybe_export(conn, project_id, chapter_id, args.output)
        return {
            "project_id": project_id, "chapter_id": chapter_id,
            "skipped": True, "snapshot_id": existing_snapshot, "exported": exported,
        }

    if not args.outline_file:
        raise SystemExit("--outline-file is required when not using --force-branch-version-id")
    outline = parse_outline(args.outline_file).get(chapter_id)
    if outline is None:
        raise SystemExit(f"chapter {chapter_id} not found in outline: {args.outline_file}")

    # 契约唯一真相源（H1）：章纲 → 四层 clause → 落库 draft 契约 → 双盲审查 →
    # activate → 从 clause 编译 brief。brief 是契约产物，不再从大纲裸拼。
    clauses = outline_to_four_layer_clauses(outline)
    contract_id = _ensure_scene_contract_clauses(scene_repo, repo, project_id, chapter_id, args.actor, clauses)

    if args.dry_run:
        return {
            "project_id": project_id, "chapter_id": chapter_id,
            "would": "contract review + generate candidates + jury + accept + export",
            "scene_contract_id": contract_id,
            "clause_counts": {k: len(v) for k, v in clauses.items()},
            "candidates": args.candidates, "rounds": args.rounds,
        }

    gateway = _gateway(conn, args)

    # 三家族盲审：全 approve 才 activate + 产稿。revise/reject/LLM 失败一律拒绝。
    architect_family = family_from_model_name(_architect_model(conn, project_id))
    reviewer_models = _reviewer_models(conn, project_id, architect_family)
    reviewer_family = family_from_model_name(reviewer_models[0])
    second_reviewer_family = family_from_model_name(reviewer_models[1])
    try:
        review = ContractReviewOrchestrator(conn, gateway).review_contract(
            scene_contract_id=contract_id, project_id=project_id,
            architect_family=architect_family, reviewer_family=reviewer_family,
            second_reviewer_family=second_reviewer_family,
        )
    except ContractReviewLLMFailure as exc:
        raise SystemExit(f"契约审查 LLM 失败，拒绝产稿: {exc}")
    if not review.approved:
        raise SystemExit(
            f"契约审查未通过（self={review.self_check_verdict}, "
            f"independent_1={review.independent_verdict}, "
            f"independent_2={review.second_independent_verdict}），拒绝产稿。修订契约后重跑。"
        )
    scene_repo.activate_contract(contract_id)

    brief = compile_brief(conn, contract_id)
    ports = {
        "generation_port": RealGenerationPort(gateway, project_id=project_id, chapter_brief=brief),
        "validation_port": RealValidationPort(gateway, project_id=project_id),
        "selection_port": RealSelectionPort(gateway, project_id=project_id),
    }

    for attempt in range(1, args.rounds + 1):
        round_id = _find_or_create_round(repo, project_id, chapter_id, attempt, args.candidates)
        driver = GenerationRoundDriver(conn, repo, **ports)
        outcome = driver.drive(round_id=round_id)
        if outcome.final_status == "selected":
            winner_bv_id = _winner_branch_version(conn, repo, round_id)
            if args.no_accept:
                # Produce-without-seal (ch01 redo semantics): winner candidate is
                # frozen + selected but NOT accepted. Output (if given) writes the
                # raw winner branch text for author review — NOT a sealed snapshot
                # export, since no active snapshot exists yet.
                exported = _maybe_export_branch_text(conn, winner_bv_id, args.output)
                return {
                    "project_id": project_id, "chapter_id": chapter_id,
                    "accepted": False, "no_accept": True, "round_id": round_id,
                    "attempt": attempt, "final_status": outcome.final_status,
                    "eligible_count": outcome.eligible_count, "call_count": outcome.call_count,
                    "winner_branch_version_id": winner_bv_id,
                    "hint": "review the winner; seal via scene-accept or re-run without --no-accept",
                    "exported": exported,
                }
            expected = _expected_head_version(conn, project_id, chapter_id)
            head_row = repo.accept_chapter(
                branch_version_id=winner_bv_id,
                expected_head_version=expected,
                actor=args.actor,
                reason=args.reason,
                preconditions_json={
                    "branch_version_id": winner_bv_id,
                    "round_id": round_id,
                },
                selection_decision_type="auto_selected",
                selection_evidence_json={
                    "branch_version_id": winner_bv_id,
                    "round_id": round_id,
                    "source": "produce-chapter",
                },
            )
            exported = _maybe_export(conn, project_id, chapter_id, args.output)
            return {
                "project_id": project_id, "chapter_id": chapter_id,
                "accepted": True, "round_id": round_id, "attempt": attempt,
                "final_status": outcome.final_status, "eligible_count": outcome.eligible_count,
                "call_count": outcome.call_count, "snapshot_id": head_row.active_snapshot_id,
                "branch_version_id": winner_bv_id, "exported": exported,
            }
    # No round produced a winner within the budget.
    return {
        "project_id": project_id, "chapter_id": chapter_id,
        "accepted": False, "attempts": args.rounds,
        "last_status": outcome.final_status, "failure_reason": outcome.failure_reason,
        "hint": "use --force-branch-version-id to accept a specific frozen branch",
    }


def _ensure_scene_contract_clauses(
    scene_repo, repo, project_id: int, chapter_id: int, actor: str, clauses: dict[str, list[dict]],
) -> int:
    """幂等落库四层 clause 契约（draft 态，待双盲审查 + activate）。

    取代旧 ``_ensure_scene_and_contract``：契约不再直接 approved 跳审查、不再用
    brief sha256 冒充 contract_hash。落四层真 clause（hard/source/soft/opening），
    状态留 draft 由调用方走 ContractReviewOrchestrator。

    幂等：已有 active 契约复用；已有 draft 契约（本轮新建未过审）复用并补 clause。
    """
    active = scene_repo.conn.execute(
        """
        SELECT c.scene_contract_id
        FROM writing_scenes s
        JOIN writing_scene_contracts c ON c.scene_id = s.scene_id
        WHERE s.project_id = ? AND s.chapter_id = ? AND c.status = 'active'
        ORDER BY s.scene_order, c.version DESC LIMIT 1
        """,
        (project_id, chapter_id),
    ).fetchone()
    if active is not None:
        return int(active[0])

    scene_id = scene_repo.conn.execute(
        """SELECT scene_id FROM writing_scenes
           WHERE project_id = ? AND chapter_id = ? AND logical_scene_key = ?""",
        (project_id, chapter_id, f"ch{chapter_id}"),
    ).fetchone()
    if scene_id is None:
        scene_id = scene_repo.create_scene(
            project_id=project_id, chapter_id=chapter_id,
            logical_scene_key=f"ch{chapter_id}", scene_order=chapter_id,
        )
    else:
        scene_id = int(scene_id[0])

    import hashlib
    # contract_hash 从四层 clause 内容派生，而非 brief——契约身份绑定四层内容。
    clause_blob = "\n".join(
        f"{c['clause_key']}:{c['clause_text']}"
        for bucket in ("hard_constraints", "source_dna", "soft_goals", "creative_openings")
        for c in clauses.get(bucket, [])
    )
    contract_hash = hashlib.sha256(clause_blob.encode("utf-8")).hexdigest()
    # created_by 携带 architect family 后缀，供 INV-CONTRACT-003 异族校验读取。
    architect_model = _architect_model(scene_repo.conn, project_id)
    created_by = f"{actor}:{family_from_model_name(architect_model)}"
    contract_id = scene_repo.create_contract(
        scene_id=scene_id, version=1, contract_hash=contract_hash,
        source_bundle_hash=contract_hash, created_by=created_by, status="draft",
    )
    scene_repo.assemble_four_layer_contract(
        scene_contract_id=contract_id,
        hard_constraints=clauses["hard_constraints"],
        source_dna=clauses["source_dna"],
        soft_goals=clauses["soft_goals"],
        creative_openings=clauses["creative_openings"],
    )
    return contract_id


def _architect_model(conn, project_id: int) -> str:
    """取架构师（draft 产稿）主模型名，用于契约 created_by family 与双盲 self_check。"""
    row = conn.execute(
        """SELECT model_name FROM writing_model_role_configs
           WHERE project_id = ? AND call_type = 'draft' AND tier = 'primary'""",
        (project_id,),
    ).fetchone()
    if row is not None:
        return str(row[0])
    return "claude-xunfei-deepseek-v4-pro"  # 兜底：与 seed 一致


def _reviewer_models(conn, project_id: int, architect_family: str) -> tuple[str, str]:
    """取两个互异且均异于架构师的审查模型。"""
    candidates = [
        str(row[0])
        for row in conn.execute(
            """SELECT model_name FROM writing_model_role_configs
               WHERE project_id = ? AND call_type IN ('contract_review', 'jury')
               ORDER BY CASE call_type WHEN 'contract_review' THEN 0 ELSE 1 END,
                        CASE tier WHEN 'secondary' THEN 0 WHEN 'fallback' THEN 1 ELSE 2 END""",
            (project_id,),
        ).fetchall()
    ]
    candidates.extend(
        (
            "claude-xunfei-glm-5-2",
            "claude-xunfei-deepseek-v4-pro",
            "claude-xunfei-qwen3-max",
        )
    )
    selected: list[str] = []
    used_families = {architect_family}
    for model in candidates:
        family = family_from_model_name(model)
        if family not in used_families:
            selected.append(model)
            used_families.add(family)
        if len(selected) == 2:
            return selected[0], selected[1]
    raise DataIntegrityError("contract review requires two model families distinct from architect")


def _reviewer_model(conn, project_id: int, architect_family: str) -> str:
    """Backward-compatible first reviewer accessor."""
    return _reviewer_models(conn, project_id, architect_family)[0]


def _find_or_create_round(repo, project_id: int, chapter_id: int, attempt: int, candidates: int) -> int:
    """Reuse a non-terminal round for the chapter, else create a new one.

    A round stuck in a non-terminal state (planned/generating/...) is resumed
    by returning its id — ``drive`` re-reads state and continues. Only when no
    resumable round exists does this create a fresh ``round_number`` round and
    fix its candidate count (bypassing supplement drafts).
    """
    row = repo.conn.execute(
        """
        SELECT generation_round_id, status FROM writing_chapter_generation_rounds
        WHERE project_id = ? AND chapter_id = ? AND status NOT IN
            ('selected','candidate_shortage','diversity_shortage','failed')
        ORDER BY round_number DESC LIMIT 1
        """,
        (project_id, chapter_id),
    ).fetchone()
    if row is not None:
        return int(row[0])
    round_id = repo.create_generation_round(
        project_id=project_id, chapter_id=chapter_id, round_number=attempt,
    )
    repo.conn.execute(
        """
        UPDATE writing_chapter_generation_rounds
        SET initial_target_count = ?, supplement_target_count = 0
        WHERE generation_round_id = ?
        """,
        (candidates, round_id),
    )
    return round_id


def _winner_branch_version(conn, repo, round_id: int) -> int:
    """Branch version id of the round's selected branch (its frozen version)."""
    row = conn.execute(
        "SELECT branch_id FROM writing_chapter_candidate_branches "
        "WHERE generation_round_id = ? AND status = 'selected'",
        (round_id,),
    ).fetchone()
    if row is None:
        raise SystemExit(f"round {round_id} has no selected branch")
    return repo.frozen_branch_version_id(int(row[0]))


def _expected_head_version(conn, project_id: int, chapter_id: int) -> int:
    row = conn.execute(
        "SELECT version FROM writing_chapter_heads WHERE project_id = ? AND chapter_id = ?",
        (project_id, chapter_id),
    ).fetchone()
    return 0 if row is None else int(row[0])


def _maybe_export(conn, project_id: int, chapter_id: int, output) -> str | None:
    if not output:
        return None
    from ink.pipeline.scene_export_orchestrator import SceneExportOrchestrator
    artifact = SceneExportOrchestrator(conn).export_chapter(project_id, chapter_id)
    Path(output).write_text(artifact, encoding="utf-8")
    return output


def _maybe_export_branch_text(conn, branch_version_id: int, output) -> str | None:
    """Write the raw frozen branch text — for --no-accept review, not a sealed export."""
    if not output:
        return None
    from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository

    text = ChapterSnapshotRepository(conn).read_branch_version_text(branch_version_id)
    Path(output).write_text(text, encoding="utf-8")
    return output


def _force_accept_and_export(
    conn, repo, project_id, chapter_id, branch_version_id, actor, reason, output,
) -> dict[str, object]:
    """Force-accept a frozen branch version without driving a round."""
    bv = conn.execute(
        "SELECT branch_id, status FROM writing_chapter_candidate_branch_versions "
        "WHERE branch_version_id = ?",
        (branch_version_id,),
    ).fetchone()
    if bv is None:
        raise SystemExit(f"branch version {branch_version_id} not found")
    if bv[1] != "frozen":
        raise SystemExit(f"branch version {branch_version_id} status={bv[1]} is not frozen")
    branch_id = int(bv[0])
    # accept_chapter requires the branch be marked 'selected' first.
    repo.select_branch(branch_id)
    expected = _expected_head_version(conn, project_id, chapter_id)
    head_row = repo.accept_chapter(
        branch_version_id=branch_version_id,
        expected_head_version=expected,
        actor=actor,
        reason=reason,
        preconditions_json={"branch_version_id": branch_version_id, "forced": True},
        selection_decision_type="human_override",
        selection_evidence_json={
            "branch_version_id": branch_version_id,
            "forced": True,
            "source": "produce-chapter-force",
        },
    )
    exported = _maybe_export(conn, project_id, chapter_id, output)
    return {
        "project_id": project_id, "chapter_id": chapter_id,
        "accepted": True, "forced": True, "snapshot_id": head_row.active_snapshot_id,
        "branch_version_id": branch_version_id, "exported": exported,
    }


def _cmd_scene_export_parity(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    result = SceneExportOrchestrator(conn).check_export_parity(project_id)
    return {"project_id": project_id, **result}


def _cmd_ds_start(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    project_id = _project_id(conn, args)
    if args.dry_run:
        return {"project_id": project_id, "planned": "start"}
    session_id = DecisionSessionStore(conn).start(
        project_id=project_id,
        scope_type=args.scope_type,
        scope_id=args.scope_id,
        target_type=args.target_type,
        target_id=args.target_id,
        human_text=args.human_text,
        parent_decision_session_id=args.parent_decision_session_id,
    )
    return {"decision_session_id": session_id, "status": "collecting"}


def _cmd_ds_parse(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    if args.dry_run:
        return {"decision_session_id": args.decision_session_id, "planned": "parse"}
    try:
        parsed_patch = json.loads(args.parsed_patch_json)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"--parsed-patch-json must be valid JSON: {exc}") from exc
    if not isinstance(parsed_patch, dict):
        raise SystemExit("--parsed-patch-json must be a JSON object")
    DecisionSessionStore(conn).record_ai_parse(
        args.decision_session_id,
        parsed_patch=parsed_patch,
        readback_text=args.readback_text,
        source_hashes=_csv_strings(args.source_hashes),
        before_hash=args.before_hash,
    )
    return {"decision_session_id": args.decision_session_id, "status": "ai_parsed"}


def _cmd_ds_options(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    if args.dry_run:
        return {"decision_session_id": args.decision_session_id, "planned": "options"}
    options = _parse_options_json(args.options_json)
    option_set_id = DecisionSessionStore(conn).create_option_set(
        args.decision_session_id,
        options=options,
        recommended_option=args.recommended_option,
    )
    return {
        "decision_session_id": args.decision_session_id,
        "option_set_id": option_set_id,
        "status": "awaiting_confirm",
        "options": options,
        "recommended_option": args.recommended_option,
    }


def _cmd_ds_regenerate(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    if args.dry_run:
        return {"decision_session_id": args.decision_session_id, "planned": "regenerate"}
    options = _parse_options_json(args.options_json)
    option_set_id = DecisionSessionStore(conn).regenerate_options(
        args.decision_session_id,
        options=options,
        recommended_option=args.recommended_option,
    )
    return {
        "decision_session_id": args.decision_session_id,
        "option_set_id": option_set_id,
        "status": "awaiting_confirm",
        "options": options,
        "recommended_option": args.recommended_option,
    }


def _cmd_ds_select(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    if args.dry_run:
        return {"decision_session_id": args.decision_session_id, "planned": "select"}
    DecisionSessionStore(conn).select_option(args.decision_session_id, args.selected_option)
    return {
        "decision_session_id": args.decision_session_id,
        "selected_option": args.selected_option,
    }


def _cmd_ds_show(conn: sqlite3.Connection, args: argparse.Namespace) -> dict[str, object]:
    """回放 DecisionSession 当前状态与活跃 option set，供断点续接不依赖聊天上下文。"""
    row = conn.execute(
        """
        SELECT decision_session_id, project_id, scope_type, scope_id, target_type, target_id,
               status, human_text, readback_text, selected_option, before_hash, after_hash,
               parent_decision_session_id
        FROM writing_decision_sessions
        WHERE decision_session_id = ?
        """,
        (args.decision_session_id,),
    ).fetchone()
    if row is None:
        raise SystemExit(f"decision session not found: {args.decision_session_id}")
    session = {
        "decision_session_id": int(row[0]),
        "project_id": int(row[1]),
        "scope_type": str(row[2]),
        "scope_id": None if row[3] is None else str(row[3]),
        "target_type": str(row[4]),
        "target_id": None if row[5] is None else str(row[5]),
        "status": str(row[6]),
        "human_text": str(row[7]),
        "readback_text": str(row[8]),
        "selected_option": None if row[9] is None else int(row[9]),
        "before_hash": None if row[10] is None else str(row[10]),
        "after_hash": None if row[11] is None else str(row[11]),
        "parent_decision_session_id": None if row[12] is None else int(row[12]),
    }
    option_set = _load_active_option_set_for_show(conn, args.decision_session_id)
    if args.dry_run:
        return {"session": session, "active_option_set": option_set, "dry_run": True}
    return {"session": session, "active_option_set": option_set}


def _parse_options_json(raw: str) -> list[dict[str, object]]:
    try:
        options = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"--options-json must be valid JSON: {exc}") from exc
    if not isinstance(options, list) or not options:
        raise SystemExit("--options-json must be a non-empty JSON array")
    if len(options) > 8:
        raise SystemExit("--options-json must contain at most 8 options")
    for index, option in enumerate(options):
        if not isinstance(option, dict):
            raise SystemExit(f"option #{index + 1} must be a JSON object")
    return options


def _load_active_option_set_for_show(conn: sqlite3.Connection, decision_session_id: int) -> dict[str, object] | None:
    row = conn.execute(
        """
        SELECT option_set_id, version, options_json, recommended_option, regenerate_count, status
        FROM writing_decision_option_sets
        WHERE decision_session_id = ?
          AND status IN ('active','selected')
        ORDER BY version DESC
        LIMIT 1
        """,
        (decision_session_id,),
    ).fetchone()
    if row is None:
        return None
    return {
        "option_set_id": int(row[0]),
        "version": int(row[1]),
        "options": json.loads(str(row[2])),
        "recommended_option": None if row[3] is None else int(row[3]),
        "regenerate_count": int(row[4]),
        "status": str(row[5]),
    }


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
    JuryOrchestrator(conn, gateway).score_and_select_winner(shot_id, run_id)
    PolishOrchestrator(conn, gateway).polish_winner(shot_id, run_id)
    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn, gateway).score_and_select_winner(shot_id, run_id)
    SoftSealOrchestrator(conn).soft_seal_if_polished(shot_id, run_id)


def _gateway(conn: sqlite3.Connection, args: argparse.Namespace) -> LLMGateway:
    if args.llm_provider == "deterministic":
        return LLMGateway(conn, provider=_CliDeterministicProvider(), provider_name="deterministic")
    config = load_llm_provider_config(
        provider=args.llm_provider,
        base_url=args.llm_base_url,
        api_key_env=args.llm_api_key_env,
        timeout_seconds=args.llm_timeout,
        max_tokens=args.llm_max_tokens,
        max_retries=args.llm_max_retries,
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
        elif idempotency_key.startswith("jury:"):
            # jury 真实化后 _score_draft 解析 12 维 JSON。polished draft 给 90 确保重评时 winner 仍是
            # polished（soft seal 契约 winner.writer_model == "smart-polish"），未 polish 给 84。
            score = 90 if "polished text" in prompt_text else 84
            text = json.dumps({col: score for col in SCORE_COLUMNS}, ensure_ascii=False)
        elif idempotency_key.startswith("chapter_review:"):
            # chapter_review 真实化后解析 7 维 JSON + review_notes。确定性默认全过（92 高于任何
            # 合理 floor 并满足绝对底线 75）；测 blocking 时用专门注入式 provider 返回低分。
            from ink.pipeline.chapter_review_orchestrator import CHAPTER_REVIEW_DIMENSIONS

            text = json.dumps(
                {col: 92 for col in CHAPTER_REVIEW_DIMENSIONS} | {"review_notes": "deterministic pass"},
                ensure_ascii=False,
            )
        elif idempotency_key.startswith("book_check:"):
            # book_check 真实化后解析 6 维 JSON + issues。确定性默认全过 + 空 issues。
            from ink.pipeline.book_rolling_check_orchestrator import BOOK_CHECK_DIMENSIONS

            text = json.dumps(
                {col: 92 for col in BOOK_CHECK_DIMENSIONS} | {"issues": []}, ensure_ascii=False
            )
        elif "-generate-" in idempotency_key:
            # Scene-first Generation Round：候选正文。从 prompt 的"纲要：\n"后取 brief 衍生一段，
            # 保证可被 validation/selection 评分（非空中文段落）。嵌入 branch_id 使多候选正文
            # 互异（writing_scene_revisions 有 (scene_id, text_hash) UNIQUE）。
            brief = prompt_text.split("纲要：\n", 1)[1] if "纲要：\n" in prompt_text else prompt_text
            bid = idempotency_key.rsplit("-", 1)[-1]
            text = f"（确定性候选{bid}）{brief[:120]}……雨势渐紧，符文在腕间隐约发烫，候选{bid}的笔触略有不同。"
        elif "-validate-" in idempotency_key or "-select-" in idempotency_key:
            # Scene-first validation / selection：7 维评分 JSON。92 高于 floor(85) 与
            # dimension_floor(60)，确定性全过门，winner 取最低 candidate_index。
            from ink.pipeline.generation_round_real_ports import RealValidationPort

            text = json.dumps(
                {col: 92 for col in RealValidationPort.DIMENSIONS}, ensure_ascii=False
            )
        elif "-diff-" in idempotency_key:
            # Scene-first 实质差异判定：true（确定性候选已带 branch_id 区分）→ 有差异，
            # 不触发补稿，2 候选直接进 selection 选优。false 会导致全废 → candidate_shortage。
            text = json.dumps({"has_substantive_difference": True}, ensure_ascii=False)
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


def _csv_ints(raw: str | None) -> list[int]:
    if not raw:
        return []
    values: list[int] = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            values.append(int(part))
        except ValueError as exc:
            raise SystemExit(f"expected integer list, got invalid value: {part}") from exc
    return values


def _csv_strings(raw: str | None) -> list[str]:
    if not raw:
        return []
    return [part.strip() for part in raw.split(",") if part.strip()]


def _parse_int_ranges(raw: str) -> list[int]:
    values: set[int] = set()
    for part in raw.split(","):
        token = part.strip()
        if not token:
            continue
        if "-" not in token:
            try:
                value = int(token)
            except ValueError as exc:
                raise SystemExit(f"invalid integer/range: {token}") from exc
            if value < 1:
                raise SystemExit("chapter numbers must be positive")
            values.add(value)
            continue
        bounds = token.split("-", 1)
        try:
            start, end = int(bounds[0]), int(bounds[1])
        except ValueError as exc:
            raise SystemExit(f"invalid integer/range: {token}") from exc
        if start < 1 or end < start:
            raise SystemExit(f"invalid chapter range: {token}")
        values.update(range(start, end + 1))
    if not values:
        raise SystemExit("--chapters must contain at least one chapter")
    return sorted(values)


def _json_dumps(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


# ---------------------------------------------------------------------------
# debug 子命令 handlers
# ---------------------------------------------------------------------------


def _cmd_debug_audit(conn: sqlite3.Connection, args: argparse.Namespace) -> dict:
    from ink.debug_view import DebugView
    dv = DebugView(conn)
    audit = dv.show_session_audit(args.session_id)
    return {
        "session_id": audit.session_id,
        "event_count": len(audit.events),
        "patch_count": len(audit.patches),
        "version_count": len(audit.contract_versions),
        "events": audit.events,
        "patches": audit.patches,
        "contract_versions": audit.contract_versions,
    }


def _cmd_debug_timeline(conn: sqlite3.Connection, args: argparse.Namespace) -> dict:
    from ink.debug_view import DebugView
    dv = DebugView(conn)
    entries = dv.show_contract_timeline(args.project_id, args.scope_type, args.scope_id)
    return {
        "project_id": args.project_id,
        "scope_type": args.scope_type,
        "scope_id": args.scope_id,
        "entry_count": len(entries),
        "entries": [
            {
                "timestamp": e.timestamp,
                "event_type": e.event_type,
                "source": e.source,
                "payload": e.payload,
            }
            for e in entries
        ],
    }


def _cmd_debug_trace(conn: sqlite3.Connection, args: argparse.Namespace) -> dict:
    from ink.debug_view import DebugView
    dv = DebugView(conn)
    trace = dv.show_shot_full_trace(args.shot_id)
    return {
        "shot_id": trace.shot_id,
        "prompt_snapshot": trace.prompt_snapshot,
        "draft": trace.draft,
        "review": trace.review,
        "event_count": len(trace.events),
        "events": trace.events,
    }


def _cmd_debug_stale(conn: sqlite3.Connection, args: argparse.Namespace) -> dict:
    from ink.debug_view import DebugView
    dv = DebugView(conn)
    chain = dv.show_stale_chain(args.project_id)
    return {
        "project_id": args.project_id,
        "stale_prompt_count": len(chain.stale_prompts),
        "stale_draft_count": len(chain.stale_drafts),
        "stale_review_count": len(chain.stale_reviews),
        "stale_check_count": len(chain.stale_checks),
        "stale_prompts": chain.stale_prompts,
        "stale_drafts": chain.stale_drafts,
        "stale_reviews": chain.stale_reviews,
        "stale_checks": chain.stale_checks,
    }


def _cmd_debug_replay_session(conn: sqlite3.Connection, args: argparse.Namespace) -> dict:
    from ink.event_replay import EventReplay

    return EventReplay(conn).session(
        args.session_id,
        at_event_id=args.at_event_id,
        at_time=args.at_time,
    ).as_dict()


def _cmd_debug_replay_contract(conn: sqlite3.Connection, args: argparse.Namespace) -> dict:
    from ink.event_replay import EventReplay

    return EventReplay(conn).contract(
        args.project_id,
        args.scope_type,
        args.scope_id,
        at_event_id=args.at_event_id,
        at_time=args.at_time,
    ).as_dict()


if __name__ == "__main__":
    raise SystemExit(main())
