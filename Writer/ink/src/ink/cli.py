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
    """专家模式可展开审计：debug audit / timeline / trace / stale。"""
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
    if updates:
        assignments = ", ".join(f"{col} = ?" for col in updates)
        conn.execute(
            f"UPDATE writing_projects SET {assignments} WHERE project_id = ?",
            (*updates.values(), project_id),
        )

    # jury 真实化后单 shot jury 调用 = 3 裁判 × (draft_count 候选 + 1 polished 稿) × 两轮（首评 + polish 后重评）。
    # 默认 draft_count=3 → 3×4×2=24，超 schema 默认 max_calls_per_shot=8。按此放宽 jury 单类型预算，
    # +3 余量容 escalation 重评。max_total_llm_calls 默认 40 亦需同步上调覆盖 draft+polish+gate+两轮 jury。
    draft_count = int(
        conn.execute("SELECT draft_count FROM writing_projects WHERE project_id = ?", (project_id,)).fetchone()[0]
    )
    jury_budget = max(8, 6 * (draft_count + 1) + 3)
    conn.execute(
        "UPDATE writing_projects SET max_calls_per_shot = ?, max_total_llm_calls = ? WHERE project_id = ?",
        (jury_budget, max(40, jury_budget * 2 + 12), project_id),
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
        # 向后兼容：无 role-config 时，用旧池首个模型生成 draft/jury primary 单档。
        # 跨供应商 failover 需用户后续用 'ink role-config set' 补齐 secondary/tertiary。
        _seed_primary_from_pool(conn, project_id=project_id, call_type="draft", model_name=writer_pool[0])
        _seed_primary_from_pool(conn, project_id=project_id, call_type="jury", model_name=jury_pool[0])

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


if __name__ == "__main__":
    raise SystemExit(main())
