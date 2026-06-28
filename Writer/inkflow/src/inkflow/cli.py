"""InkFlow CLI — `ink` command entry point.

P0 commands:
  ink init <project>
  ink setup <project> --chapter <key>
  ink run <project> --chapter <key>
  ink review <project> --chapter <key> --accept/--revise/--reject
  ink import-baseline <project> --chapter <key> --file <path>
  ink review-shots <project> --chapter <key>
  ink repair <project> --red/--yellow
  ink resume <session_id>
  ink sessions list
  ink sessions abort <id>
  ink status <project>
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import click

from inkflow import __version__
from inkflow.services.model_client import ModelCallError


# ── Windows UTF-8 fix ──
if sys.platform == "win32" and "pytest" not in sys.modules:
    sys.stdout = open(sys.stdout.fileno(), mode="w", encoding="utf-8", buffering=1)
    sys.stderr = open(sys.stderr.fileno(), mode="w", encoding="utf-8", buffering=1)

# Module-level constant for story base directory
_STORY_BASE = Path(os.environ.get("INKFLOW_STORY_DIR", r"D:\_Progs\.Story"))


@click.group()
@click.version_option(version=__version__, prog_name="ink")
def main():
    """ink — 墨韵 (InkFlow) v3.6 文学文本生产引擎

    主流程: init 全书初始化 → setup 章前校准 → run 生产并导出 → review 人工验收。
    """


# ── Helpers ──

def _derive_baseline_chapter(chapter: str) -> str:
    """Derive the baseline chapter key from the target chapter.

    Baseline is the preceding chapter: v01.c02 → v01.c01, v02.c01 → v01.cNN.
    For the first chapter of any volume, the baseline is the last chapter
    of the previous volume.
    """
    import re
    m = re.match(r"v(\d+)\.c(\d+)", chapter)
    if not m:
        return "v01.c01"  # fallback
    vol = int(m.group(1))
    ch = int(m.group(2))
    if ch > 1:
        return f"v{vol:02d}.c{ch - 1:02d}"
    elif vol > 1:
        return f"v{vol - 1:02d}.c01"  # caller should resolve last chapter
    return "v01.c01"


def _compute_brilliance_level(score: float) -> str:
    """Map jury score to brilliance level."""
    if score >= 95:
        return "S"
    elif score >= 90:
        return "A+"
    elif score >= 85:
        return "A"
    return "A"  # minimum for green


def _compute_badsmell_level(score: float) -> str:
    """Map jury score to badsmell level (inverted)."""
    if score >= 85:
        return "B"  # clean
    elif score >= 75:
        return "Br"  # minor issues
    return "Bz"  # significant issues


def _seed_motifs_from_contract(motif_tracker, compiler) -> None:
    """Seed motif definitions from the contract's motif_system into DB.

    Converts the human-readable motif descriptions into searchable
    keyword variants so the MotifTracker can detect them in text.
    Idempotent — skips already-registered motifs.
    """
    motif_system = compiler.get_motif_system()
    if not motif_system:
        return

    # Map motif names to their search keywords
    motif_keyword_map = {
        # primary
        "膝盖/螺丝刀": ["膝盖", "螺丝刀", "拧", "关节", "骨", "损伤"],
        "都江堰分流": ["都江堰", "分流", "内江", "外江", "系统", "边界"],
        "金沙垃圾层": ["金沙", "金沙遗址", "垃圾层", "堆填", "地层"],
        # secondary
        "盖碗茶": ["盖碗茶", "茶", "盖碗", "茶社"],
        "太阳神鸟": ["太阳神鸟", "金箔", "神鸟", "金饰", "图腾"],
        "保鲜膜": ["保鲜膜", "薄膜", "缠绕", "透明"],
        "握空的手": ["握空", "握", "空", "抓", "松开"],
        # visual_markers
        "屏幕颜色边界": ["屏幕", "蓝色", "橙色", "内江蓝", "外江橙", "颜色边界"],
        "系统之眼": ["摄像头", "传感器", "系统之眼", "监控"],
    }

    existing = {
        r["name"] for r in
        motif_tracker.db.execute(
            "SELECT name FROM writing_motif_definitions WHERE project_id = ?",
            (motif_tracker.project_id,),
        ).fetchall()
    }

    for name, keywords in motif_keyword_map.items():
        if name in existing:
            continue
        try:
            motif_tracker.register_motif({
                "name": name,
                "planned_density_json": {"target_per_100_shots": 30},
                "variants_json": {"keywords": keywords},
                "min_shot_gap": 1,
            })
        except Exception:
            continue


def _read_shot_title_from_yaml(project: str, shot_index: int, chapter_key: str | None = None) -> str:
    """Read shot title from contract-draft.yaml as fallback.

    The DB meta-contract may not have the title field yet (e.g. old confirmed contracts).
    This reads directly from the YAML file as a safety net.
    """
    try:
        import yaml
        draft_path = _STORY_BASE / f"《{project}》" / ".inkflow" / "contract-draft.yaml"
        if draft_path.exists():
            with open(draft_path, encoding="utf-8") as f:
                contract = yaml.safe_load(f)
            # Try chapter-specific field first, then fallback to chapter_2_events
            if chapter_key:
                ch_num = chapter_key.split(".c")[-1] if ".c" in chapter_key else "2"
                field_name = f"chapter_{ch_num}_events"
                events = contract.get(field_name, [])
            else:
                events = contract.get("chapter_2_events", [])
            for ev in events:
                if ev.get("shot") == shot_index + 1:  # shot_index is 0-based, YAML is 1-based
                    return ev.get("title", "")
    except Exception:
        pass
    return ""


def _build_previous_context(
    db, run_id: str, baseline_shots: list[dict], current_index: int,
    pov_character: str | None = None,
    project_id: str | None = None,
) -> list[dict]:
    """Build previous-shots context — only for the SAME POV character.

    Rules:
    1. Find the most recent completed shot with the same pov_character
       across ALL runs (cross-chapter continuity).
    2. If none found in any run, look in baseline.
    3. Return a 100-char summary, NOT full text.
    4. If no relevant context exists, return empty list.

    Rationale: multi-POV chapters have independent scenes. Injecting
    unrelated POV content causes LLM hallucination of cross-POV links.
    Only inject the character's own prior state.
    """
    if not pov_character:
        return []

    # 1. Find same POV character's previous shot from the current run's
    # completed earlier shots, or from human-accepted historical chapters.
    from inkflow.services.text_repository import TextRepository
    repo = TextRepository(db)
    shot = db.execute(
        "SELECT ws.shot_id, ws.shot_index, ws.layer_key "
        "FROM writing_shots ws "
        "JOIN writing_shot_contracts wsc ON ws.shot_id = wsc.shot_id "
        "  AND ws.run_id = wsc.run_id "
        "LEFT JOIN writing_chapter_reviews cr "
        "  ON cr.project_id = ws.project_id "
        " AND cr.chapter_key = ws.layer_key "
        " AND cr.run_id = ws.run_id "
        " AND cr.status = 'accepted' "
        "WHERE ws.shot_status IN ('done_green', 'done_yellow') "
        "  AND ws.current_revision_id IS NOT NULL "
        "  AND json_extract(wsc.pov_routing_json, '$.pov_character') = ? "
        "  AND (? IS NULL OR ws.project_id = ?) "
        "  AND ("
        "    (ws.run_id = ? AND ws.shot_index < ?) "
        "    OR cr.review_id IS NOT NULL"
        "  ) "
        "ORDER BY CASE WHEN ws.run_id = ? THEN 0 ELSE 1 END, "
        "ws.layer_key DESC, ws.shot_index DESC LIMIT 1",
        (
            pov_character, project_id, project_id,
            run_id, current_index + 1, run_id,
        ),
    ).fetchone()
    if shot:
        text = repo.get_shot_text(shot["shot_id"])
        return [{
            "shot_index": shot["shot_index"],
            "text": _summarize_text(text, 100),
        }]

    # 2. Fallback: look in baseline for same character
    if baseline_shots:
        for bs in reversed(baseline_shots):
            text = bs.get("text", "")
            if pov_character in text[:200]:
                return [{
                    "shot_index": bs.get("shot_index", "基线"),
                    "text": _summarize_text(text, 100),
                }]

    return []


def _summarize_text(text: str, max_chars: int) -> str:
    """Create a short summary by taking the first max_chars chars."""
    clean = text.replace("\n", " ").replace("\r", " ").strip()
    if len(clean) <= max_chars:
        return clean
    return clean[:max_chars] + "…"


def _format_failure_summary(summary: dict | None) -> str:
    """Compact one-line failure summary for CLI output."""
    if not summary:
        return ""
    parts = []
    by_type = summary.get("by_type") or {}
    if by_type:
        parts.extend(f"{k}={v}" for k, v in sorted(by_type.items()))
    failed_gates = summary.get("failed_gates") or {}
    if failed_gates:
        parts.extend(f"gate_{k}={v}" for k, v in sorted(failed_gates.items()))
    return ", ".join(parts)


def _print_failure_summary(summary: dict | None) -> None:
    """Print a readable failure summary if the session has failures."""
    label = _format_failure_summary(summary)
    if not label:
        return
    click.echo(f"失败归因: {label}")
    for item in (summary or {}).get("details", [])[:3]:
        detail = item.get("detail") or ""
        suffix = f" — {detail}" if detail else ""
        click.echo(
            f"  Shot {item.get('shot_index', '?')}: "
            f"{item.get('failure_type', 'unknown')}{suffix}"
        )


def _format_jury_draft_score(
    draft_id: str,
    score_data: dict,
    *,
    score_key: str = "literary_score",
) -> str:
    """Format one draft's jury result without hiding gate failures as score 0."""
    raw_scores = score_data.get("raw_scores", [])
    if not score_data.get("eligible", True):
        summary = score_data.get("failure_summary") or {}
        label = summary.get("label") or _jury_failure_stage_label(
            score_data.get("failure_stage"),
        )
        reasons = summary.get("reasons") or []
        detail = f"{label}: {', '.join(str(r) for r in reasons[:3])}" if reasons else label
        return f"    草稿 {draft_id[:8]}…  未入选: {detail}  原始: {raw_scores}"

    display_key = score_key or "literary_score"
    score = score_data.get(display_key, score_data.get("trimmed_mean", 0))
    score_label = "文学均分" if display_key == "literary_score" else "均分"
    return f"    草稿 {draft_id[:8]}…  {score_label}: {score}  原始: {raw_scores}"


def _jury_failure_stage_label(stage: str | None) -> str:
    labels = {
        "hard_rule": "硬规则未通过",
        "type_gate": "类型职责未通过",
        "jury_unavailable": "评审不可用",
    }
    return labels.get(stage or "", "未入选")


def _jury_verdict_all_unavailable(verdict: dict) -> bool:
    """Return True when no draft was judged because required jury calls failed."""
    draft_scores = verdict.get("draft_scores") or {}
    if not draft_scores or verdict.get("winner_draft_id"):
        return False
    return all(
        not score_data.get("eligible", True)
        and score_data.get("failure_stage") == "jury_unavailable"
        for score_data in draft_scores.values()
    )


def _jury_unavailable_detail(verdict: dict) -> str:
    dimensions: list[str] = []
    for score_data in (verdict.get("draft_scores") or {}).values():
        for dimension in score_data.get("missing_dimensions") or []:
            if dimension not in dimensions:
                dimensions.append(str(dimension))
    if not dimensions:
        return "required jury dimension unavailable"
    return "missing_dimensions=" + ",".join(dimensions[:5])


def _raise_if_jury_unavailable(
    jury_verdict: dict,
    *,
    shot_id: str,
    retry_budget,
) -> None:
    if not _jury_verdict_all_unavailable(jury_verdict):
        return
    detail = _jury_unavailable_detail(jury_verdict)
    try:
        retry_budget.record_failure(
            shot_id, "jury_unavailable", detail=detail,
        )
    except Exception:
        # Preserve the infrastructure failure as the primary user-facing error.
        pass
    raise click.ClickException(
        "远端评审不可用，已停止本章生产；"
        f"{detail}。请检查 model_attempts.error_message 后再 resume。"
    )


def _chapter_completion_issues(db, run_id: str, chapter: str | None) -> list[str]:
    if not chapter:
        return []
    rows = db.execute(
        "SELECT shot_id, shot_index, shot_status, light_status, current_revision_id "
        "FROM writing_shots WHERE run_id = ? AND layer_key = ? "
        "ORDER BY shot_index",
        (run_id, chapter),
    ).fetchall()
    issues: list[str] = []
    if not rows:
        return ["no_shots"]
    for row in rows:
        if row["shot_status"] not in ("done_green", "done_yellow"):
            issues.append(
                f"s{row['shot_index']:02d}:{row['shot_status']}"
            )
        elif not row["current_revision_id"]:
            issues.append(f"s{row['shot_index']:02d}:missing_revision")
    return issues


def _latest_chapter_run(db, project_id: str, chapter: str) -> dict | None:
    row = db.execute(
        "SELECT ws.run_id, s.session_id, s.status, s.created_at "
        "FROM writing_shots ws "
        "JOIN writing_sessions s ON s.run_id = ws.run_id "
        "WHERE ws.project_id = ? AND ws.layer_key = ? "
        "GROUP BY ws.run_id "
        "ORDER BY s.created_at DESC LIMIT 1",
        (project_id, chapter),
    ).fetchone()
    return dict(row) if row else None


def _chapter_l3_passed(db, run_id: str, chapter: str) -> bool:
    row = db.execute(
        "SELECT status FROM writing_architect_gates "
        "WHERE run_id = ? AND level = 'L3' AND scope_key = ? "
        "ORDER BY created_at DESC LIMIT 1",
        (run_id, chapter),
    ).fetchone()
    return bool(row and row["status"] == "passed")


def _record_chapter_review_db(
    db,
    *,
    project_id: str,
    chapter: str,
    run_id: str | None,
    status: str,
    review_text: str,
    notes: str | None,
    exported_path: Path,
    shot_stats: list[dict],
) -> None:
    import json
    from inkflow.utils.ulid import generate as generate_ulid

    if status in ("accepted", "needs_revision", "rejected"):
        db.execute(
            "UPDATE writing_chapter_reviews SET status = 'superseded', "
            "updated_at = datetime('now') "
            "WHERE project_id = ? AND chapter_key = ? AND status = 'accepted'",
            (project_id, chapter),
        )

    if status in ("needs_revision", "rejected") and run_id:
        db.execute(
            "UPDATE writing_shots SET shot_status = 'redo', "
            "placeholder_type = 'redo_placeholder', updated_at = datetime('now') "
            "WHERE project_id = ? AND run_id = ? AND layer_key = ? "
            "AND shot_status IN ('done_green', 'done_yellow')",
            (project_id, run_id, chapter),
        )

    existing = None
    if run_id:
        existing = db.execute(
            "SELECT review_id FROM writing_chapter_reviews "
            "WHERE project_id = ? AND chapter_key = ? AND run_id = ?",
            (project_id, chapter, run_id),
        ).fetchone()

    review_id = existing["review_id"] if existing else generate_ulid()
    payload = (
        review_id,
        project_id,
        chapter,
        run_id,
        status,
        review_text,
        notes,
        str(exported_path) if exported_path.exists() else None,
        json.dumps(shot_stats, ensure_ascii=False),
    )
    if existing:
        db.execute(
            "UPDATE writing_chapter_reviews SET status = ?, review_text = ?, "
            "notes = ?, exported_path = ?, shot_stats_json = ?, "
            "updated_at = datetime('now') WHERE review_id = ?",
            (status, review_text, notes, payload[7], payload[8], review_id),
        )
    else:
        db.execute(
            "INSERT INTO writing_chapter_reviews "
            "(review_id, project_id, chapter_key, run_id, status, review_text, "
            "notes, exported_path, shot_stats_json) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            payload,
        )


def _resume_or_create_session(
    mgr, db, project_id, chapter, num_shots, requested_session_id=None,
):
    """Resume an exact session or the latest recoverable one, else create new."""
    if requested_session_id:
        row = db.execute(
            "SELECT session_id, run_id, status, act_id FROM writing_sessions "
            "WHERE project_id = ? AND session_id = ?",
            (project_id, requested_session_id),
        ).fetchone()
        if row is None:
            raise click.ClickException(f"未找到指定 session: {requested_session_id}")
        if row["status"] == "completed":
            raise click.ClickException(f"Session {requested_session_id[:12]}... 已完成，不能恢复。")

        if row["status"] == "aborted":
            click.echo(f"恢复已放弃 Session: {row['session_id'][:12]}...")
        else:
            click.echo(f"恢复指定 Session: {row['session_id'][:12]}... ({row['status']})")
        if row["status"] != "active":
            mgr.update_session_status(row["session_id"], "active")
        return row["session_id"], row["run_id"]

    # Find latest recoverable session for this project and chapter.
    query = (
        "SELECT session_id, run_id FROM writing_sessions "
        "WHERE project_id = ? AND status IN ('active', 'paused', 'crashed') "
    )
    params = [project_id]
    if chapter:
        query += "AND act_id = ? "
        params.append(chapter)
    query += "ORDER BY created_at DESC LIMIT 1"

    row = db.execute(query, params).fetchone()
    if row:
        click.echo(f"恢复 Session: {row['session_id'][:12]}...")
        return row["session_id"], row["run_id"]

    aborted_query = (
        "SELECT session_id FROM writing_sessions "
        "WHERE project_id = ? AND status = 'aborted' "
    )
    aborted_params = [project_id]
    if chapter:
        aborted_query += "AND act_id = ? "
        aborted_params.append(chapter)
    aborted_query += "ORDER BY updated_at DESC LIMIT 1"
    aborted = db.execute(aborted_query, aborted_params).fetchone()
    if aborted:
        summary = mgr.get_session_failure_summary(aborted["session_id"])
        label = _format_failure_summary(summary)
        note = f"；失败归因: {label}" if label else ""
        click.echo(
            f"最近有已放弃 Session: {aborted['session_id'][:12]}...，"
            f"run --resume 不自动恢复{note}。"
        )
        click.echo(f"如需继续它，请运行: ink resume {aborted['session_id']}")

    # No incomplete session → create new
    click.echo("没有未完成的 session，创建新的...")
    session_id = mgr.create_session(act_id=chapter, total_shots=num_shots)
    session = mgr.get_session(session_id)
    return session_id, session["run_id"]


def _mark_latest_active_session_crashed(db, project: str, chapter: str | None) -> None:
    """Mark the most recent in-progress active session as crashed after exceptions."""
    row = db.execute(
        "SELECT project_id FROM projects WHERE name = ?",
        (project,),
    ).fetchone()
    if row is None:
        return

    query = (
        "SELECT session_id FROM writing_sessions "
        "WHERE project_id = ? AND status = 'active' AND current_shot_id IS NOT NULL "
    )
    params = [row["project_id"]]
    if chapter:
        query += "AND act_id = ? "
        params.append(chapter)
    query += "ORDER BY updated_at DESC LIMIT 1"

    session = db.execute(query, params).fetchone()
    if session is None:
        return
    db.execute(
        "UPDATE writing_sessions SET status = 'crashed', updated_at = datetime('now') "
        "WHERE session_id = ?",
        (session["session_id"],),
    )
    db.commit()


def _resolve_project_db(title: str) -> Path:
    """Resolve inkflow.db path from project title.

    Convention: D:\\_Progs\\.Story\\《title》\\.inkflow\\inkflow.db
    """
    from inkflow.db import init_project_db

    story_dir = _STORY_BASE / f"《{title}》"
    if not story_dir.exists():
        raise click.ClickException(f"项目目录不存在: {story_dir}")

    db_path = story_dir / ".inkflow" / "inkflow.db"
    return db_path


def _next_steps(*lines: str) -> None:
    """Print human-friendly next steps."""
    click.echo()
    click.echo("下一步:")
    for line in lines:
        click.echo(f"  {line}")


def _chapter_setup_path(project: str, chapter: str) -> Path:
    return (
        _STORY_BASE / f"《{project}》" / ".inkflow" /
        "chapter-setups" / f"{chapter}.yaml"
    )


def _chapter_review_path(project: str, chapter: str) -> Path:
    return (
        _STORY_BASE / f"《{project}》" / ".inkflow" /
        "chapter-reviews" / f"{chapter}.yaml"
    )


def _write_yaml_file(path: Path, data: dict) -> None:
    import yaml

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        yaml.dump(data, allow_unicode=True, sort_keys=False, default_flow_style=False),
        encoding="utf-8",
    )


def _read_yaml_file(path: Path) -> dict:
    if not path.exists():
        return {}
    import yaml

    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def _load_chapter_setup(project: str, chapter: str | None) -> dict:
    """Load and validate the chapter preflight package."""
    if not chapter:
        return {}

    setup_path = _chapter_setup_path(project, chapter)
    if not setup_path.exists():
        raise click.ClickException(
            f"章节 {chapter} 尚未完成生产前 setup。请先运行: "
            f"ink setup \"{project}\" --chapter {chapter}"
        )

    setup_data = _read_yaml_file(setup_path)
    if setup_data.get("schema") != "inkflow.chapter_setup.v1":
        raise click.ClickException(f"章节 setup 文件格式不正确: {setup_path}")
    if setup_data.get("chapter") != chapter:
        raise click.ClickException(
            f"章节 setup 文件不匹配: 期望 {chapter}, 实际 {setup_data.get('chapter')}"
        )
    if setup_data.get("status") not in ("ready", "approved"):
        raise click.ClickException(
            f"章节 setup 状态不是 ready/approved: {setup_data.get('status')}"
        )
    return setup_data


def _validate_contract_scope_for_chapter(
    chapter: str | None,
    layers: dict,
    project: str | None = None,
) -> None:
    """Reject stale chapter-scoped contract rules before setup/run."""
    if not chapter:
        return

    chapter_number = _chapter_number_from_key(chapter)
    issues: list[str] = []

    hard_text = _flatten_contract_text(layers.get("hard_boundaries", {}))
    for matched in _find_only_generate_chapter_numbers(hard_text):
        if chapter_number is not None and matched != chapter_number:
            issues.append(
                f"hard_boundaries 仍限定只生成第 {matched} 章，当前目标是 {chapter}"
            )

    style = layers.get("style_locks", {})
    paragraph = str(style.get("paragraph_length", ""))
    if "500-800" in paragraph and "3-4" in paragraph:
        issues.append(
            "style_locks.paragraph_length 仍是旧规则 "
            "'500-800 字/段落，3-4 段/shot'"
        )

    if issues:
        detail = "\n  - ".join(issues)
        project_arg = f"\"{project}\"" if project else "\"<项目>\""
        raise click.ClickException(
            "章节契约未完成当前章校准，不能进入生产。\n"
            f"  - {detail}\n"
            "请先更新契约草稿并 confirm-contract，然后重新运行: "
            f"ink setup {project_arg} --chapter {chapter} --force"
        )


def _validate_chapter_run_preflight(
    project: str,
    chapter: str | None,
    setup_data: dict,
    meta_contract: dict,
    layers: dict,
    chapter_events: list[dict],
) -> None:
    """Validate that run uses the current chapter setup and current contract."""
    if not chapter:
        return

    _validate_contract_scope_for_chapter(chapter, layers, project)

    source = setup_data.get("source_contract") or {}
    source_id = source.get("meta_contract_id")
    current_id = meta_contract.get("meta_contract_id")
    if source_id and current_id and source_id != current_id:
        raise click.ClickException(
            "章节 setup 包基于旧元契约，不能用于当前生产。\n"
            f"  setup: {source_id}\n"
            f"  current: {current_id}\n"
            f"请重新运行: ink setup \"{project}\" --chapter {chapter} --force"
        )

    setup_shots = setup_data.get("shots") or []
    if chapter_events and len(setup_shots) != len(chapter_events):
        raise click.ClickException(
            "章节 setup 包与当前契约的 shot 数不一致。\n"
            f"  setup shots: {len(setup_shots)}\n"
            f"  contract events: {len(chapter_events)}\n"
            f"请重新运行: ink setup \"{project}\" --chapter {chapter} --force"
        )


def _chapter_number_from_key(chapter: str | None) -> int | None:
    import re

    if not chapter:
        return None
    match = re.match(r"v\d+\.c(\d+)$", chapter)
    return int(match.group(1)) if match else None


def _find_only_generate_chapter_numbers(text: str) -> list[int]:
    import re

    numbers: list[int] = []
    for match in re.finditer(r"只生成第\s*(\d{1,3})\s*章", text):
        numbers.append(int(match.group(1)))
    return numbers


def _flatten_contract_text(value: object) -> str:
    if isinstance(value, dict):
        return "\n".join(_flatten_contract_text(v) for v in value.values())
    if isinstance(value, (list, tuple, set)):
        return "\n".join(_flatten_contract_text(v) for v in value)
    if value is None:
        return ""
    return str(value)


def _chapter_setup_shot(setup_data: dict, shot_index: int) -> dict:
    """Return setup metadata for a one-based shot index."""
    for shot in setup_data.get("shots") or []:
        if not isinstance(shot, dict):
            continue
        try:
            declared_index = int(shot.get("shot"))
        except (TypeError, ValueError):
            declared_index = None
        if declared_index == shot_index:
            return shot
    shots = setup_data.get("shots") or []
    if 0 <= shot_index - 1 < len(shots):
        shot = shots[shot_index - 1]
        return shot if isinstance(shot, dict) else {}
    return {}


def _normalize_type_roles(roles: list | tuple | set | None) -> list[str]:
    if not roles:
        return []

    aliases = {
        "blank": "blank_space",
        "blankspace": "blank_space",
        "blank_space": "blank_space",
        "creative": "blank_space",
        "creative_entry": "blank_space",
        "suspense": "suspense",
        "hook": "hook",
        "chapter_hook": "hook",
    }
    result: list[str] = []
    for role in roles:
        key = str(role).strip().lower().replace("-", "_")
        normalized = aliases.get(key, key)
        if normalized and normalized not in result:
            result.append(normalized)
    return result


def _auto_export_chapter(
    db,
    project: str,
    chapter: str | None,
    *,
    run_id: str | None = None,
) -> Path | None:
    """Export completed run output to the canonical story 正文 directory."""
    if not chapter:
        return None
    from inkflow.export import export_markdown

    story_dir = _STORY_BASE / f"《{project}》"
    out_path = story_dir / "正文" / f"{project}_{chapter}_导出.md"
    return export_markdown(db, out_path, chapters=[chapter], run_id=run_id)


# ── import-baseline ──

@main.command("import-baseline")
@click.argument("project")
@click.option("--chapter", required=True, help="章节 key，如 v01.c01")
@click.option("--file", "file_path", required=True, help="章节 Markdown 文件路径")
def import_baseline(project: str, chapter: str, file_path: str):
    """导入人工样章为锁定 baseline。

    \b
    示例:
      ink import-baseline "分流" --chapter v01.c01 --file "正文/V01_第01章.md"
    """
    from inkflow.db import init_project_db, backup_project_db
    from inkflow.importers import BaselineImporter
    from inkflow.utils.ulid import generate

    db_path = _resolve_project_db(project)
    story_dir = _STORY_BASE / f"《{project}》"

    # Resolve relative file path against project directory
    file_path_obj = Path(file_path)
    if not file_path_obj.is_absolute():
        file_path_obj = story_dir / file_path_obj

    # Ensure project exists in DB
    project_id = generate()
    db = init_project_db(db_path)

    # Check or create project
    existing = db.execute(
        "SELECT project_id FROM projects WHERE name = ?", (project,)
    ).fetchone()
    if existing:
        project_id = existing["project_id"]
    else:
        db.execute(
            "INSERT INTO projects (project_id, name) VALUES (?, ?)",
            (project_id, project),
        )
        db.commit()

    # Backup before write
    backup_project_db(db_path, label="before_import_baseline")

    importer = BaselineImporter(db, project_id)
    result = importer.import_chapter(chapter, file_path_obj)

    click.echo(f"导入完成: {project}")
    click.echo(f"  章节: {result['chapter_key']}")
    click.echo(f"  Shot 数: {result['shot_count']}")
    click.echo(f"  总字数: {result['total_chars']}")
    click.echo(f"  状态: locked (human_baseline)")

    _next_steps(
        f"ink review-shots \"{project}\" --chapter {chapter}",
        f"ink init \"{project}\"",
    )

    db.close()


# ── review-shots ──

@main.command("review-shots")
@click.argument("project")
@click.option("--chapter", required=True, help="章节 key，如 v01.c01")
def review_shots(project: str, chapter: str):
    """审核/确认 baseline shot 边界。

    \b
    示例:
      ink review-shots "分流" --chapter v01.c01
    """
    from inkflow.db import init_project_db
    from inkflow.importers import BaselineImporter

    db_path = _resolve_project_db(project)
    db = init_project_db(db_path)

    row = db.execute(
        "SELECT project_id FROM projects WHERE name = ?", (project,)
    ).fetchone()
    if row is None:
        db.close()
        raise click.ClickException(f"项目 '{project}' 尚未初始化。请先运行 import-baseline。")

    project_id = row["project_id"]
    importer = BaselineImporter(db, project_id)
    shots = importer.get_baseline_shots(chapter)

    if not shots:
        db.close()
        raise click.ClickException(f"章节 {chapter} 没有 baseline shot。请先运行 import-baseline。")

    click.echo(f"章节: {chapter}")
    click.echo(f"Shot 数: {len(shots)}")
    click.echo()

    for shot in shots:
        text_preview = shot["text"][:100].replace("\n", " ") if shot["text"] else ""
        click.echo(f"  Shot {shot['shot_index']:02d}: {text_preview}...")
        click.echo()

    if importer.is_baseline_locked(chapter):
        click.echo("状态: locked (human_baseline)")

    _next_steps(f"ink init \"{project}\"")
    db.close()


# ── init / setup ──

@main.command("init")
@click.argument("project")
@click.option(
    "--chapter-file",
    default=None,
    help="第 1 章 Markdown 文件路径 (相对于项目目录)",
)
def init_project(project: str, chapter_file: str | None):
    """全书初始化 — 建库、导入样章、生成章以上层级契约草稿。

    \b
    流程:
      1. 初始化项目 + 导入第 1 章为 locked baseline
      2. AI 架构师分析第 1 章 + 全书资料
      3. 生成 contract-draft.yaml (高创造力字段留空等人类填写)
      4. 人类编辑 contract-draft.yaml → ink confirm-contract 确认

    \b
    示例:
      ink init "分流" --chapter-file "正文/V01_第01章.md"
    """
    _run_init_project(project, chapter_file)


def _run_init_project(project: str, chapter_file: str | None) -> None:
    from inkflow.db import init_project_db
    from inkflow.importers.baseline_importer import BaselineImporter
    from inkflow.services import SessionManager
    from pathlib import Path

    story_dir = _STORY_BASE / f"《{project}》"
    inkflow_dir = story_dir / ".inkflow"
    story_dir.mkdir(parents=True, exist_ok=True)
    inkflow_dir.mkdir(parents=True, exist_ok=True)
    db_path = inkflow_dir / "inkflow.db"
    draft_path = inkflow_dir / "contract-draft.yaml"

    # ── Step 1: Init project if needed ──
    db = init_project_db(db_path)
    row = db.execute(
        "SELECT project_id FROM projects WHERE name = ?", (project,)
    ).fetchone()
    if row is None:
        from inkflow.utils.ulid import generate as generate_ulid
        project_id = generate_ulid()
        db.execute(
            "INSERT INTO projects (project_id, name) VALUES (?, ?)",
            (project_id, project),
        )
        db.commit()
        click.echo(f"项目 '{project}' 已初始化")
    else:
        project_id = row["project_id"]
        click.echo(f"项目 '{project}' 已存在")

    # ── Step 2: Import chapter 1 as baseline ──
    importer = BaselineImporter(db, project_id)
    existing_shots = db.execute(
        "SELECT COUNT(*) as cnt FROM writing_shots WHERE project_id = ? AND layer_key = 'v01.c01'",
        (project_id,),
    ).fetchone()

    if existing_shots and existing_shots["cnt"] > 0:
        click.echo(f"第 1 章已导入 ({existing_shots['cnt']} shots, locked)")
        baseline_shots = importer.get_baseline_shots("v01.c01")
    else:
        if chapter_file is None:
            candidates = sorted(story_dir.glob("正文/V01*第01章*.md"))
            if not candidates:
                candidates = sorted(story_dir.glob("正文/*01*.md"))
            if candidates:
                chapter_file = str(candidates[0].relative_to(story_dir))

        if chapter_file is None:
            click.echo("未找到第 1 章文件，跳过 baseline 导入。")
            baseline_shots = []
        else:
            chapter_path = story_dir / chapter_file
            if not chapter_path.exists():
                click.echo(f"警告: 第 1 章文件不存在: {chapter_path}")
                baseline_shots = []
            else:
                click.echo(f"导入第 1 章: {chapter_file}")
                result = importer.import_chapter("v01.c01", chapter_path)
                click.echo(f"  已导入 {result['shot_count']} shots, {result['total_chars']} 字 (locked)")
                baseline_shots = importer.get_baseline_shots("v01.c01")

    # ── Step 3: Load .models ──
    mgr = SessionManager(db, project_id)
    try:
        mgr.init_project_config(str(story_dir))
        click.echo(f"模型配置已加载")
    except FileNotFoundError:
        click.echo("警告: .models 文件不存在")

    # ── Step 4: AI 架构师分析 → 生成 contract-draft.yaml ──
    _generate_contract_draft(project, story_dir, baseline_shots, draft_path)

    db.close()

    # ── Step 5: Print summary ──
    click.echo()
    click.echo("═" * 60)
    click.echo("  📋 契约草稿已生成")
    click.echo("═" * 60)
    click.echo(f"  文件: {draft_path}")
    click.echo()
    click.echo("  【高创造力字段 — 人类必须填写】")
    click.echo("    identity.character_arcs: 各角色核心弧线")
    click.echo("    narrative_voice.register_tone: 叙事语气基调")
    click.echo("    creative_zones.chapter_2_interpretation: 第 2 章创作诠释")
    click.echo()
    click.echo("  【低创造力字段 — AI 已推断，请审核】")
    click.echo("    hard_boundaries: 硬边界 (存活角色/世界规则)")
    click.echo("    style_locks: 风格铁律 (身体时刻/感官密度/方言)")
    click.echo("    anti_patterns: 反模式 (禁止的做法)")
    click.echo("    world_knowledge: 世界观 (地点/物件/季节)")
    click.echo("    motif_system: 意象系统 (主意象/视觉符号)")
    click.echo()
    click.echo("  【chapter_N_events — AI 从大纲提取，请审核】")
    click.echo("    chapter_N_events: 逐章逐 shot 必须落地的事件")
    click.echo()
    click.echo("  下一步:")
    click.echo(f"    1. 编辑 {draft_path}")
    click.echo(f"    2. 填写高创造力字段，审核 AI 推断")
    click.echo(f"    3. ink confirm-contract \"{project}\"")
    click.echo("═" * 60)


@main.command("setup")
@click.argument("project")
@click.option("--chapter", required=True, help="要生产前校准的章节 key，如 v01.c03")
@click.option("--force", is_flag=True, help="覆盖已存在的章节生产包")
def setup_project(project: str, chapter: str, force: bool):
    """章前校准 — 针对某一章生成生产前准备包。

    \b
    只校准本章，不初始化全书、不改写正文。
    示例:
      ink setup "分流" --chapter v01.c03
    """
    from datetime import datetime, timezone
    from inkflow.db import init_project_db
    from inkflow.services import ContractCompiler

    db_path = _resolve_project_db(project)
    db = init_project_db(db_path)

    row = db.execute(
        "SELECT project_id FROM projects WHERE name = ?", (project,)
    ).fetchone()
    if row is None:
        db.close()
        raise click.ClickException(f"项目 '{project}' 尚未初始化。请先运行: ink init \"{project}\"")

    project_id = row["project_id"]
    compiler = ContractCompiler(db, project_id)
    meta_contract = compiler.get_meta_contract()
    if meta_contract is None or meta_contract["status"] not in ("confirmed", "locked"):
        db.close()
        raise click.ClickException("元契约尚未确认。请先运行 init 并确认契约。")

    layers = meta_contract.get("layers_json", {})
    try:
        _validate_contract_scope_for_chapter(chapter, layers, project)
    except click.ClickException:
        db.close()
        raise

    chapter_events = compiler.get_chapter_events(chapter)
    if not chapter_events:
        db.close()
        raise click.ClickException(f"锁定契约中没有 {chapter} 的 chapter_events。请先更新契约。")

    setup_path = _chapter_setup_path(project, chapter)
    if setup_path.exists() and not force:
        db.close()
        click.echo(f"章节生产包已存在: {setup_path}")
        click.echo("如需覆盖，请加 --force。")
        return

    previous_chapter = _derive_baseline_chapter(chapter)
    previous_review = _read_yaml_file(_chapter_review_path(project, previous_chapter))
    suspense = layers.get("suspense_config", {})

    existing_rows = db.execute(
        "SELECT shot_status, light_status, COUNT(*) AS cnt "
        "FROM writing_shots WHERE project_id = ? AND layer_key = ? "
        "GROUP BY shot_status, light_status",
        (project_id, chapter),
    ).fetchall()
    existing_state = [
        {
            "shot_status": r["shot_status"],
            "light_status": r["light_status"],
            "count": r["cnt"],
        }
        for r in existing_rows
    ]

    default_exposition_gate = {
        "enabled": True,
        "rule": "概念只能通过后果显影，不能由叙述者或角色解释成主题。",
        "forbidden_phrases": [
            "系统并不恶意",
            "它只是",
            "本质上",
            "逻辑结构",
            "资源分配",
            "低效率",
            "直接回报",
            "闭环",
        ],
        "repair_instruction": "把概念句改成动作、物件、沉默、对话或身体反应；保留事件，不保留解释。",
    }

    shots = []
    total = len(chapter_events)
    for index, event in enumerate(chapter_events, start=1):
        roles = []
        if index == total:
            roles.append("hook")
        shots.append({
            "shot": event.get("shot", index),
            "title": event.get("title", f"Shot {index}"),
            "pov": event.get("pov", "unknown"),
            "must_land": event.get("event", ""),
            "type_roles": roles,
            "anti_patterns": [
                "禁止把意象解释成主题",
                "禁止长段系统/模型/资源/效率议论",
                "禁止用总结句替代动作和身体反应",
            ],
        })

    data = {
        "schema": "inkflow.chapter_setup.v1",
        "project": project,
        "chapter": chapter,
        "status": "ready",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source_contract": {
            "meta_contract_id": meta_contract["meta_contract_id"],
            "status": meta_contract["status"],
        },
        "previous_chapter": previous_chapter,
        "previous_review": previous_review or None,
        "existing_chapter_state": existing_state,
        "shots": shots,
        "chapter_hook": {
            "required": True,
            "requirements": suspense.get("chapter_hooks") or [
                "最后一句必须是未完成动作，不能是感官收束或解释",
            ],
        },
        "exposition_gate": default_exposition_gate,
        "human_checklist": [
            "确认本章 shot 事件和 POV 顺序正确",
            "确认章末钩子不是收束句",
            "确认哪些 shot 才需要悬疑、留白或创意入口",
            "确认不得出现长段概念解释",
        ],
    }

    _write_yaml_file(setup_path, data)
    db.close()

    click.echo(f"章节生产包已生成: {setup_path}")
    click.echo(f"章节: {chapter} / {len(shots)} shots")
    if existing_state:
        click.echo("检测到旧稿状态，若要重写请先运行:")
        click.echo(f"  ink repair \"{project}\" --chapter {chapter} --all")
    _next_steps(f"ink run \"{project}\" --chapter {chapter} --resume")


# ── confirm-contract ──


@main.command("confirm-contract")
@click.argument("project")
def confirm_contract(project: str):
    """确认契约: 读取 contract-draft.yaml → 验证 → 写入 DB → confirmed。

    \b
    前置条件: 已运行 ink init 并编辑过 contract-draft.yaml。
    """
    from inkflow.db import init_project_db
    from inkflow.services import ContractCompiler
    import yaml

    db_path = _resolve_project_db(project)
    story_dir = _STORY_BASE / f"《{project}》"
    draft_path = story_dir / ".inkflow" / "contract-draft.yaml"

    if not draft_path.exists():
        raise click.ClickException(
            f"契约草稿不存在: {draft_path}\n请先运行: ink init \"{project}\""
        )

    # Read and validate
    try:
        draft = yaml.safe_load(draft_path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        raise click.ClickException(f"contract-draft.yaml YAML 语法错误: {e}")

    if not isinstance(draft, dict):
        raise click.ClickException("contract-draft.yaml 格式错误: 期望 YAML 字典")

    # Validate required fields
    required = ["identity", "narrative_voice", "hard_boundaries", "style_locks",
                 "anti_patterns", "world_knowledge", "motif_system", "creative_zones",
                 "suspense_config"]
    # chapter_2_events is required; chapter_3_events, chapter_4_events etc. are optional
    has_any_chapter = any(
        k.startswith("chapter_") and k.endswith("_events") and draft.get(k)
        for k in draft
    )
    if not has_any_chapter:
        raise click.ClickException(
            "contract-draft.yaml 缺少必填字段: 至少需要 chapter_2_events"
        )

    # Check high-creativity fields are filled
    identity = draft.get("identity", {})
    if not identity.get("character_arcs") or "<<请填写" in str(identity.get("character_arcs", "")):
        raise click.ClickException(
            "identity.character_arcs 尚未填写。这是高创造力字段，必须由人类填写。"
        )

    creative = draft.get("creative_zones", {})
    if not creative.get("chapter_2_interpretation") or "<<请填写" in str(creative.get("chapter_2_interpretation", "")):
        raise click.ClickException(
            "creative_zones.chapter_2_interpretation 尚未填写。这是高创造力字段，必须由人类填写。"
        )

    # Create meta-contract from draft
    db = init_project_db(db_path)
    row = db.execute(
        "SELECT project_id FROM projects WHERE name = ?", (project,)
    ).fetchone()
    if row is None:
        db.close()
        raise click.ClickException(f"项目 '{project}' 尚未初始化。请先运行 init。")
    project_id = row["project_id"]

    compiler = ContractCompiler(db, project_id)
    existing = compiler.get_meta_contract()

    # Build contract data — include all chapter_X_events fields
    structure_rules = {
        "chapter_2_interpretation": creative.get("chapter_2_interpretation", ""),
    }
    for k in draft:
        if k.startswith("chapter_") and k.endswith("_events") and draft.get(k):
            structure_rules[k] = draft[k]

    contract_data = {
        "identity": identity,
        "narrative_voice": draft.get("narrative_voice", {}),
        "hard_boundaries": draft.get("hard_boundaries", {}),
        "anti_reveal": draft.get("anti_reveal", {"do_not_reveal": "", "keep_ambiguous": ""}),
        "world_knowledge": draft.get("world_knowledge", {}),
        "structure_rules": structure_rules,
        "anti_patterns": draft.get("anti_patterns", {}),
        "style_locks": draft.get("style_locks", {}),
        "motif_system": draft.get("motif_system", {}),
        "creative_zones": creative,
        "suspense_config": draft.get("suspense_config", {}),
        "suspense_blueprint": draft.get("suspense_blueprint", {}),
    }

    if existing:
        click.echo(f"元契约已存在 (status={existing['status']})，将更新。")
        # TODO: revision tracking

    mc_id = compiler.create_meta_contract(contract_data)
    click.echo(f"元契约已创建: {mc_id[:12]}...")

    # Transition to confirmed
    contract = compiler.get_meta_contract()
    if contract["status"] == "draft":
        compiler.update_contract_status(mc_id, "human_review")
        click.echo("draft → human_review")
    compiler.update_contract_status(mc_id, "confirmed")
    click.echo("human_review → confirmed ✅")

    click.echo()
    click.echo("契约已确认。可以运行:")
    click.echo(f"  ink run \"{project}\" --chapter v01.c02")
    db.close()


# ── constitution ──


@main.command("constitution")
@click.argument("project")
@click.option("--show", is_flag=True, help="仅显示当前宪法（不生成）")
@click.option("--confirm", is_flag=True, help="确认当前草稿 → confirmed")
@click.option("--lock", is_flag=True, help="确认并锁定 → locked")
def constitution_command(project: str, show: bool, confirm: bool, lock: bool):
    """L0 全书宪法管理 — 生成/确认/锁定全书节奏宪法。

    \b
    流程:
      1. ink constitution "分流"            → LLM 生成草稿
      2. 审核输出（arc_shape, volume_map, motif_lifecycle）
      3. ink constitution "分流" --confirm  → 确认
      4. ink constitution "分流" --lock     → 锁定（不可变）

    \b
    示例:
      ink constitution "分流"
      ink constitution "分流" --confirm
      ink constitution "分流" --show
    """
    from inkflow.db import init_project_db
    from inkflow.services import BookConstitutionService

    db_path = _resolve_project_db(project)
    story_dir = _STORY_BASE / f"《{project}》"

    db = init_project_db(db_path)
    try:
        row = db.execute(
            "SELECT project_id FROM projects WHERE name = ?", (project,)
        ).fetchone()
        if row is None:
            raise click.ClickException(f"项目不存在: {project}")
        project_id = row[0]

        svc = BookConstitutionService(db, project_id)
        constitution = svc.get_latest_constitution()

        # --show: 仅显示
        if show:
            if constitution is None:
                click.echo("无宪法。运行: ink constitution \"{}\"".format(project))
                return
            _print_constitution(constitution)
            return

        # --confirm: draft → confirmed
        if confirm:
            if constitution is None:
                raise click.ClickException("无宪法可确认。先生成: ink constitution \"{}\"".format(project))
            status = constitution["status"]
            if status == "locked":
                click.echo("宪法已锁定，不可修改。")
                return
            if status == "confirmed":
                click.echo("宪法已确认。")
                if lock:
                    svc.lock_constitution(constitution["constitution_id"])
                    click.echo("confirmed → locked ✅")
                return
            svc.update_status(constitution["constitution_id"], "confirmed")
            click.echo("draft → confirmed ✅")
            if lock:
                svc.lock_constitution(constitution["constitution_id"])
                click.echo("confirmed → locked ✅")
            _print_constitution(svc.get_latest_constitution())
            return

        # --lock (without confirm): 如果已 confirmed，直接 lock
        if lock:
            if constitution is None:
                raise click.ClickException("无宪法可锁定。")
            if constitution["status"] == "locked":
                click.echo("宪法已锁定。")
                return
            if constitution["status"] != "confirmed":
                svc.update_status(constitution["constitution_id"], "confirmed")
                click.echo("draft → confirmed ✅")
            svc.lock_constitution(constitution["constitution_id"])
            click.echo("confirmed → locked ✅")
            _print_constitution(svc.get_latest_constitution())
            return

        # 默认: 生成或显示已有
        if constitution is not None:
            click.echo(f"已有宪法 (status={constitution['status']}):")
            _print_constitution(constitution)
            click.echo()
            click.echo("如需重新生成，请先确认/锁定当前宪法。")
            return

        # 生成新宪法
        if not story_dir.exists():
            raise click.ClickException(f"项目目录不存在: {story_dir}")

        click.echo("正在生成 L0 全书宪法...")
        click.echo(f"  源目录: {story_dir}")
        click.echo()

        try:
            cid = svc.generate_constitution(str(story_dir))
        except ModelCallError as e:
            raise click.ClickException(f"LLM 调用失败: {e}")

        constitution = svc.get_latest_constitution()
        click.echo("宪法草稿已生成 ✅")
        click.echo(f"  constitution_id: {cid}")
        click.echo()
        _print_constitution(constitution)
        click.echo()
        click.echo("下一步:")
        click.echo(f"  ink constitution \"{project}\" --confirm   # 确认")
        click.echo(f"  ink constitution \"{project}\" --lock      # 确认并锁定")

    finally:
        db.close()


def _print_constitution(constitution: dict) -> None:
    """格式化输出宪法摘要。"""
    import json

    click.echo(f"═══ L0 全书宪法 (status={constitution['status']}) ═══")
    click.echo()

    arc = constitution.get("arc_shape", "")
    if arc:
        click.echo(f"叙事弧: {arc}")

    peak = constitution.get("tension_peak_chapter", "")
    if peak:
        click.echo(f"张力峰值: {peak}")

    valleys = constitution.get("tension_valley_chapters_json")
    if valleys:
        try:
            v = json.loads(valleys) if isinstance(valleys, str) else valleys
            click.echo(f"张力谷底: {', '.join(v)}")
        except (json.JSONDecodeError, TypeError):
            pass

    click.echo()

    # Volume map
    vol_map = constitution.get("volume_map_json")
    if vol_map:
        try:
            vm = json.loads(vol_map) if isinstance(vol_map, str) else vol_map
            click.echo("卷部结构:")
            for vk, vdata in sorted(vm.items()):
                name = vdata.get("name", "")
                chapters = vdata.get("chapters", [])
                summary = vdata.get("arc_summary", "")[:40]
                click.echo(f"  {vk} ({name}): {len(chapters)} 章")
                if summary:
                    click.echo(f"    → {summary}...")
        except (json.JSONDecodeError, TypeError):
            pass

    click.echo()

    # Chapter roles
    roles = constitution.get("chapter_roles_json")
    if roles:
        try:
            cr = json.loads(roles) if isinstance(roles, str) else roles
            role_groups: dict[str, list[str]] = {}
            for ck, role in sorted(cr.items()):
                role_groups.setdefault(role, []).append(ck)
            click.echo("章角色:")
            for role in ["起", "承", "转", "合"]:
                chs = role_groups.get(role, [])
                if chs:
                    click.echo(f"  {role}: {', '.join(chs)}")
        except (json.JSONDecodeError, TypeError):
            pass

    click.echo()

    # Motif lifecycle
    ml = constitution.get("motif_lifecycle_json")
    if ml:
        try:
            motifs = json.loads(ml) if isinstance(ml, str) else ml
            click.echo(f"Motif 生命周期 ({len(motifs)} 条):")
            for m in motifs[:5]:
                mid = m.get("motif_id", "?")
                plant = m.get("planted_at", "?")
                resolve = m.get("resolved_at", "?")
                click.echo(f"  {mid}: 种于 {plant} → 收于 {resolve}")
            if len(motifs) > 5:
                click.echo(f"  ... 共 {len(motifs)} 条")
        except (json.JSONDecodeError, TypeError):
            pass

    click.echo()

    # Deviation
    mean = constitution.get("global_deviation_mean")
    rng = constitution.get("global_deviation_range_json")
    if mean is not None:
        try:
            r = json.loads(rng) if isinstance(rng, str) else rng
            click.echo(f"偏离参数: mean={mean:.2f}, range=[{r[0]:.2f}, {r[1]:.2f}]")
        except (json.JSONDecodeError, TypeError, IndexError):
            click.echo(f"偏离参数: mean={mean:.2f}")


# ── run ──

@main.command("run")
@click.argument("project")
@click.option("--chapter", default=None, help="目标章节 key，如 v01.c02")
@click.option("--shot", "shot_id", default=None, help="单 Shot 运行")
@click.option("--writer-count", type=click.IntRange(2, 4), default=2, help="写手数量 (2-4)")
@click.option("--shot-count", type=int, default=None, help="每章 Shot 数 (默认从 baseline 读取)")
@click.option("--resume", is_flag=True, help="从断点恢复")
@click.option("--local-jury", is_flag=True, help="本次运行强制使用 local-default 评委")
@click.option("--session-id", "resume_session_id", default=None, hidden=True)
def run_project(
    project: str,
    chapter: str | None,
    shot_id: str | None,
    writer_count: int,
    shot_count: int | None,
    resume: bool,
    local_jury: bool,
    resume_session_id: str | None,
):
    """全自动生产。

    按目标章节逐 shot 生成。writer → jury → gate → revision → checkpoint → export。

    \b
    示例:
      ink run "分流" --chapter v01.c02
    """
    from inkflow.db import init_project_db, backup_project_db
    from inkflow.services import (
        SessionManager, ContractCompiler, PromptCompiler,
        WriterDispatcher, JuryService, QualityController,
        FactAnchorExtractor, MotifTracker,
    )
    from inkflow.utils.config import load_models_config

    db_path = _resolve_project_db(project)
    db = init_project_db(db_path)
    try:
        try:
            _run_project_inner(
                db, db_path, project, chapter, shot_id, writer_count,
                shot_count, resume, resume_session_id, local_jury,
            )
        except Exception:
            _mark_latest_active_session_crashed(db, project, chapter)
            raise
    finally:
        db.close()


def _run_project_inner(
    db, db_path, project, chapter, shot_id, writer_count, shot_count, resume,
    resume_session_id=None, local_jury=False,
):
    """Inner run logic — db is guaranteed to be closed by the caller."""
    from inkflow.services import (
        SessionManager, ContractCompiler, PromptCompiler,
        WriterDispatcher, JuryService, QualityController,
        FactAnchorExtractor, MotifTracker, ArchitectGate,
        OutlineEvaluator, RetryBudgetService, StylePreferenceService,
        AntiContractSandbox, PolishService,
    )
    from inkflow.services.retry_budget import (
        RetryBudgetExhausted, CircuitBreakerTriggered, classify_failure_type,
    )
    from inkflow.utils.config import load_models_config, get_quality_threshold

    row = db.execute(
        "SELECT project_id FROM projects WHERE name = ?", (project,)
    ).fetchone()
    if row is None:
        raise click.ClickException(f"项目 '{project}' 尚未初始化。")

    project_id = row["project_id"]

    # Verify contract is confirmed
    compiler = ContractCompiler(db, project_id)
    if not compiler.is_contract_confirmed():
        raise click.ClickException(
            "元契约尚未确认。请先运行 init 并确认契约。"
        )

    # Load models config
    story_dir = _STORY_BASE / f"《{project}》"
    try:
        models_config = load_models_config(str(story_dir))
    except FileNotFoundError:
        models_config = {
            "providers": {},
            "writer": {"primary": "local-default", "fallback": "local-default"},
            "jury": {"primary": "local-default", "fallback": "local-default"},
            "architect": {"primary": "local-default", "fallback": "local-default"},
        }
    except ValueError as e:
        raise click.ClickException(str(e))

    if local_jury:
        models_config = dict(models_config)
        jury_config = dict(models_config.get("jury_config", {}))
        jury_config["models"] = ["local-default"]
        models_config["jury_config"] = jury_config

    providers = models_config.get("providers", {})

    # Get meta-contract — this is the authority for shot count, not baseline
    meta_contract = compiler.get_meta_contract()
    compiler.lock_contract(meta_contract["meta_contract_id"])
    layers = compiler._get_layers()

    # Get baseline shots from chapter 1
    from inkflow.importers import BaselineImporter
    importer = BaselineImporter(db, project_id)

    # Derive baseline chapter from target chapter
    if chapter:
        baseline_chapter = _derive_baseline_chapter(chapter)
    else:
        baseline_chapter = "v01.c01"
    baseline_shots = importer.get_baseline_shots(baseline_chapter)

    # Determine shot count from contract, not baseline
    # Contract is the authority — the chapter outline defines how many shots exist.
    chapter_events = compiler.get_chapter_events(chapter)
    chapter_setup = _load_chapter_setup(project, chapter)
    _validate_chapter_run_preflight(
        project, chapter, chapter_setup, meta_contract, layers, chapter_events,
    )
    num_shots = shot_count or compiler.get_shot_count(chapter) or 8

    # Create session or resume
    mgr = SessionManager(db, project_id)
    if resume:
        session_id, run_id = _resume_or_create_session(
            mgr, db, project_id, chapter, num_shots,
            requested_session_id=resume_session_id,
        )
    else:
        session_id = mgr.create_session(act_id=chapter, total_shots=num_shots)
        session = mgr.get_session(session_id)
        run_id = session["run_id"]

    click.echo(f"Session: {session_id}")
    click.echo(f"Run: {run_id}")
    click.echo(f"目标章节: {chapter or '全部'}")
    click.echo(f"契约驱动: {num_shots} shots (来自 {len(chapter_events)} 个 chapter_events)")

    # D25-R1: Retry budget + circuit breaker
    retry_budget = RetryBudgetService(db, run_id)
    click.echo(f"  重试预算: {retry_budget.max_budget} 次（{num_shots} shots × 2）")

    # Create run snapshot
    from inkflow.utils.hashing import snapshot_hash, config_hash
    mgr.create_run_snapshot(
        run_id=run_id,
        meta_contract_id=meta_contract["meta_contract_id"],
        config_hash_str=config_hash(models_config),
        contract_snapshot_hash=snapshot_hash(layers),
        snapshot_data={
            "chapter": chapter,
            "writer_count": writer_count,
            "chapter_setup": {
                "schema": chapter_setup.get("schema"),
                "chapter": chapter_setup.get("chapter"),
                "status": chapter_setup.get("status"),
                "created_at": chapter_setup.get("created_at"),
                "path": str(_chapter_setup_path(project, chapter)) if chapter else None,
            } if chapter_setup else None,
        },
    )

    # Create shots for chapter 2
    if chapter:
        if shot_id:
            # Single-shot mode: create only the specified shot
            existing = db.execute(
                "SELECT shot_id FROM writing_shots WHERE shot_id = ?", (shot_id,)
            ).fetchone()
            if not existing:
                # CLI-3: Create new shot and use its real ID
                new_ids = mgr.create_shots(run_id, [{"layer_key": chapter, "shot_index": 1}])
                shot_ids = new_ids
            else:
                shot_ids = [shot_id]
        else:
            shots_data = [
                {"layer_key": chapter, "shot_index": i + 1}
                for i in range(num_shots)
            ]
            shot_ids = mgr.create_shots(run_id, shots_data)

        # Build shot data with must_land from meta-contract (already loaded above)
        shots_with_contracts = []
        for i, sid in enumerate(shot_ids):
            shot_data = {
                "shot_id": sid,
                "shot_index": i + 1,
                "layer_key": chapter,
                "must_land": {},
                "pov_routing": {},
            }
            if i < len(chapter_events):
                ev = chapter_events[i]
                # Convert narrative event to bullet-point writing directive
                event_text = ev.get("event", "")
                import re as _re
                # Strip **X线** markers (e.g. **阿坤线**：)
                clean = _re.sub(r'\*\*[^*]+\*\*[：:]?\s*', '', event_text)
                # Strip chapter-end hooks: everything from **章末钩子** to end
                clean = _re.sub(r'\*\*章末钩子\*\*.*$', '', clean, flags=_re.DOTALL)
                # Strip separator lines
                clean = _re.sub(r'---\s*$', '', clean)
                # Split into key beats
                beats = _re.split(r'[。！？]', clean)
                key_points = []
                for b in beats:
                    b = b.strip()
                    if b and len(b) > 8 and '---' not in b:
                        key_points.append(b)
                # Build a writing directive with shot title as first line
                title = ev.get("title", "")
                if not title:
                    # Fallback: try reading from contract-draft.yaml directly
                    title = _read_shot_title_from_yaml(project, i, chapter)
                title_line = f"## {title}\n\n" if title else ""
                writing_directive = title_line + '\n'.join(f'- {p}' for p in key_points[:8])
                shot_data["must_land"] = {"beats": writing_directive, "title": title}

                # Build anti_write: POV isolation constraint
                this_pov = ev.get("pov", "unknown")
                other_povs = [e.get("pov") for e in chapter_events if e.get("pov") != this_pov]
                shot_data["anti_write"] = {
                    "pov_only": f"只写 {this_pov} 的视角。不要切换到其他角色的场景。",
                    "forbidden": f"不要直接描写 {', '.join(other_povs)} 的活动",
                }
                shot_data["pov_routing"] = {"pov_character": this_pov}

                # OPT-2: Per-shot sensory density control
                if ev.get("sensory_pressure"):
                    shot_data["sensory_pressure"] = ev["sensory_pressure"]
                if ev.get("dominant_sense"):
                    shot_data["dominant_sense"] = ev["dominant_sense"]

                # OPT-6: Emotional transition bridge
                if ev.get("entry_mood"):
                    shot_data["entry_mood"] = ev["entry_mood"]

                # ARCH-1: Three-layer deviation taxonomy (from YAML if present)
                if ev.get("hard_facts"):
                    shot_data["hard_facts"] = ev["hard_facts"]
                if ev.get("soft_constraints"):
                    shot_data["soft_constraints"] = ev["soft_constraints"]
                if ev.get("reference"):
                    shot_data["reference"] = ev["reference"]

                # ARCH-2/3: Rhythm parameters (from YAML if present)
                if ev.get("deviation_budget") is not None:
                    shot_data["deviation_budget"] = ev["deviation_budget"]
                if ev.get("narrative_phase"):
                    shot_data["narrative_phase"] = ev["narrative_phase"]
            shots_with_contracts.append(shot_data)

        # Compile shot contracts using compiler (DB-driven, not JSON blob)
        contract_ids = compiler.compile_shot_contracts(
            run_id=run_id,
            shots=shots_with_contracts,
            meta_contract=compiler._get_layers(),
        )
        compiler.lock_shot_contracts(run_id)

        # Initialize services
        prompt_compiler = PromptCompiler(db)
        writer_dispatcher = WriterDispatcher(db, run_id, models_config, providers=providers)
        jury_service = JuryService(db, run_id, models_config)
        quality_controller = QualityController(db, run_id)
        fact_extractor = FactAnchorExtractor(db, project_id, models_config)
        motif_tracker = MotifTracker(db, project_id, run_id)

        # D-25: Extract suspense blueprint from contract
        suspense_blueprint = layers.get("suspense_blueprint", {})

        # D-25: Initialize information gap tracker
        from inkflow.services.information_gap_tracker import InformationGapTracker
        info_gap_tracker = InformationGapTracker(db, project_id, run_id)
        if suspense_blueprint:
            info_gap_tracker.seed_from_blueprint(suspense_blueprint)

        # ARCH-7R: Wire L0.5 volume rhythm constraints into L1 chapter rhythm
        volume_constraints_for_chapter = None
        try:
            from inkflow.services.volume_rhythm import VolumeRhythmService
            from inkflow.services.model_client import create_model_client
            vol_client = create_model_client(
                "local-default", providers=models_config.get("providers")
            )
            vol_svc = VolumeRhythmService(db, project_id, vol_client)
            if chapter:
                vol_rhythm = vol_svc.get_volume_rhythm_for_chapter(chapter, run_id)
                if vol_rhythm:
                    volume_key = chapter.split(".")[0]
                    vr_chapter_data = vol_rhythm.get("deviation_range_per_chapter", {}).get(chapter)
                    vr_role = vol_rhythm.get("chapter_roles_in_volume", {}).get(chapter)
                    if vr_chapter_data or vr_role:
                        volume_constraints_for_chapter = {
                            "deviation_range": vr_chapter_data or [0.3, 0.7],
                            "chapter_role": vr_role or "rising",
                            "volume_key": volume_key,
                        }
                        click.echo(
                            f"  📐 L0.5 卷部节奏约束: "
                            f"角色={vr_role}, deviation_range={vr_chapter_data or [0.3, 0.7]}"
                        )
        except Exception as exc:
            click.echo(f"  ⚠ 卷部节奏约束加载失败: {exc}")

        # ARCH: Chapter Rhythm Architect (L1) — analyze chapter rhythm before production
        from inkflow.services.chapter_rhythm import ChapterRhythmArchitect
        from inkflow.services.model_client import ModelRequest, ModelResponse
        # Use primary writer model for architect analysis
        architect_model = providers.get("writer", {}).get("primary")
        chapter_rhythm_map = None
        if architect_model:
            try:
                chapter_rhythm_arch = ChapterRhythmArchitect(db, architect_model)
                chapter_rhythm_map = chapter_rhythm_arch.analyze_chapter(
                    chapter_key=chapter,
                    chapter_events=chapter_events,
                    volume_constraints=volume_constraints_for_chapter,
                )
                chapter_rhythm_arch.store_rhythm_map(chapter_rhythm_map, run_id)
                click.echo(
                    f"  🎵 章级节奏分析完成: "
                    f"{len(chapter_rhythm_map.get('shots', []))} shots, "
                    f"均值 budget={chapter_rhythm_map.get('mean_deviation_budget', 0):.2f}"
                )
            except Exception as exc:
                click.echo(f"  ⚠ 章级节奏分析失败: {exc}，使用默认参数")
                chapter_rhythm_map = None

        # Seed motifs from contract into DB (idempotent)
        _seed_motifs_from_contract(motif_tracker, compiler)

        # Compile static prefix for each writer persona (from compiler, not raw JSON)
        # D-25: Inject suspense blueprint into static prefix
        static_prefixes = {}
        for persona in ["意象师", "节奏师", "对话师", "结构师"]:
            static_prefixes[persona] = prompt_compiler.compile_static_prefix(
                layers,
                persona,
                suspense_blueprint=suspense_blueprint,
            )

        # 初始化大纲评估器
        outline_evaluator = OutlineEvaluator(db, run_id, models_config, providers=providers)
        quality_threshold = get_quality_threshold(models_config)

        # Process each shot — 新流水线：大纲评估 → 双线赛马 → 九评委 → 阈值判断
        for i, shot_id in enumerate(shot_ids):
            click.echo(f"\nShot {i + 1}/{len(shot_ids)}...")

            # Resume guard: skip already-completed shots (idempotent recovery)
            shot_status_row = db.execute(
                "SELECT shot_status, light_status FROM writing_shots WHERE shot_id = ?",
                (shot_id,),
            ).fetchone()
            if shot_status_row and shot_status_row["shot_status"] in (
                "done_green", "done_yellow",
            ):
                click.echo(
                    f"  ⏭ 已 ({shot_status_row['shot_status']}/"
                    f"{shot_status_row['light_status']})，跳过"
                )
                continue

            mgr.update_current_shot(session_id, shot_id)

            # 留白机制：每 5 个 shot 释放 1 个（第 5、10、15... 个 shot）
            is_blank_shot = ((i + 1) % 5 == 0)
            blank_budget_multiplier = 2.0 if is_blank_shot else 1.0
            blank_temp_cap = 1.4 if is_blank_shot else 1.2
            if is_blank_shot:
                click.echo(f"  🪨 留白 shot：释放创造自由度（budget×2, temp≤{blank_temp_cap}）")

            setup_shot = _chapter_setup_shot(chapter_setup, i + 1)
            setup_roles = _normalize_type_roles(setup_shot.get("type_roles"))
            if "blank_space" in setup_roles:
                is_blank_shot = True
                blank_budget_multiplier = 2.0
                blank_temp_cap = 1.4
            if setup_roles:
                click.echo(f"  章前校准类型职责: {', '.join(setup_roles)}")

            # Get shot contract
            sc = compiler.get_shot_contract(shot_id, run_id)
            if sc is None:
                click.echo(f"  ⚠ 无契约，跳过")
                continue

            # Step 1: 大纲评估 → 不合格则重新生成
            click.echo(f"  📋 大纲评估...")
            try:
                outline_result = outline_evaluator.evaluate_and_fix(
                    shot_id=shot_id,
                    shot_contract=dict(sc),
                    meta_contract=layers,
                    max_retries=1,
                )
                outline_score = outline_result["initial_score"]
                was_regenerated = outline_result["regenerated"]
                click.echo(
                    f"    大纲评分: {outline_score}"
                    f"{' → 已重新生成' if was_regenerated else ' → 通过'}"
                )
                if was_regenerated:
                    refreshed_sc = compiler.get_shot_contract(shot_id, run_id)
                    if refreshed_sc is not None:
                        sc = refreshed_sc
            except (ModelCallError, ValueError, KeyError) as exc:
                click.echo(f"    ⚠ 大纲评估失败: {exc}，使用原大纲")

            # Step 2: 编译 prompt（两线共用）
            motif_task = motif_tracker.generate_motif_task(shot_id)
            active_anchors = fact_extractor.get_active_anchors(
                limit=5, run_id=run_id,
            )

            # 构建前文上下文：仅同 POV 角色，简短摘要
            pov_routing = sc.get("pov_routing_json") or {}
            if isinstance(pov_routing, str):
                import json as _json
                pov_routing = _json.loads(pov_routing) if pov_routing else {}
            elif not isinstance(pov_routing, dict):
                pov_routing = {}
            pov_character = pov_routing.get("pov_character")
            previous_shots = _build_previous_context(
                db, run_id, baseline_shots, i, pov_character=pov_character,
                project_id=project_id,
            )

            # D-25: 获取当前活跃的信息差
            active_gaps = info_gap_tracker.get_active_gaps()

            # ARCH-1/2/3: Extract rhythm + three-layer fields from contract_json
            cj = sc.get("contract_json", "{}")
            if isinstance(cj, str):
                import json as _json2
                cj = _json2.loads(cj) if cj else {}

            # ARCH: Override rhythm params from chapter_rhythm_map if available
            rhythm_budget = cj.get("deviation_budget")
            rhythm_phase = cj.get("narrative_phase")
            rhythm_sensory = cj.get("sensory_pressure")
            if chapter_rhythm_map:
                rhythm_shots = chapter_rhythm_map.get("shots", [])
                # Find this shot's rhythm data (shot_index is 1-based)
                this_rhythm = next(
                    (rs for rs in rhythm_shots if rs.get("shot_index") == i + 1),
                    None,
                )
                if this_rhythm:
                    rhythm_budget = this_rhythm.get("deviation_budget", rhythm_budget)
                    rhythm_phase = this_rhythm.get("narrative_phase", rhythm_phase)
                    # Override sensory_pressure from phase parameters if not set in contract
                    if not rhythm_sensory:
                        rhythm_sensory = this_rhythm.get("sensory_pressure")

            shot_context_payload = {
                "must_land": sc.get("must_land_json", {}),
                "anti_write": sc.get("anti_write_json", {}),
                "exit_to": sc.get("exit_to_json"),
                # ARCH-1: Three-layer deviation taxonomy
                "hard_facts": cj.get("hard_facts"),
                "soft_constraints": cj.get("soft_constraints"),
                "reference": cj.get("reference"),
                # ARCH-2/3: Rhythm parameters (from L1 architect or contract)
                "deviation_budget": rhythm_budget,
                "narrative_phase": rhythm_phase,
                # OPT-2/6: Sensory + mood (still pass through)
                "sensory_pressure": rhythm_sensory or cj.get("sensory_pressure"),
                "dominant_sense": cj.get("dominant_sense"),
                "entry_mood": cj.get("entry_mood"),
                "chapter_setup": {
                    "shot": setup_shot,
                    "exposition_gate": chapter_setup.get("exposition_gate"),
                    "chapter_hook": chapter_setup.get("chapter_hook"),
                } if chapter_setup else None,
            }
            gaps_text = info_gap_tracker.build_active_gaps_prompt() if active_gaps else ""
            persona_prompts: dict[str, str] = {}
            for persona in ["意象师", "节奏师", "对话师", "结构师"]:
                pid = prompt_compiler.compile_shot_prompt(
                    shot_id, run_id, persona,
                    static_prefixes[persona],
                    shot_context_payload,
                    previous_shots=previous_shots,
                    fact_anchors=active_anchors,
                    motif_tasks=motif_task,
                )
                prompt_row = db.execute(
                    "SELECT assembled_prompt FROM writing_shot_prompts WHERE prompt_id = ?",
                    (pid,),
                ).fetchone()
                persona_prompt = (prompt_row["assembled_prompt"] if prompt_row else "") or ""
                if persona_prompt and gaps_text:
                    persona_prompt += "\n\n" + gaps_text
                persona_prompts[persona] = persona_prompt

            compiled_prompt = persona_prompts.get("意象师", "")

            if not compiled_prompt:
                # 兜底：从合约构建简单 prompt
                import json as _json
                ml = sc.get("must_land_json", "{}")
                if isinstance(ml, str):
                    try:
                        ml = _json.loads(ml) if ml else {}
                    except Exception:
                        ml = {}
                beats = ml.get("beats", "")
                if beats:
                    compiled_prompt = f"请直接写出以下场景的小说正文。\n\n{beats}"
                else:
                    compiled_prompt = f"请为场景 {shot_id} 写一段小说正文。"
            for persona in ["意象师", "节奏师", "对话师", "结构师"]:
                if not persona_prompts.get(persona):
                    persona_prompts[persona] = compiled_prompt

            shot_type_roles = []
            if active_gaps:
                shot_type_roles.append("suspense")
            if is_blank_shot:
                shot_type_roles.append("blank_space")
            if i == len(shot_ids) - 1:
                shot_type_roles.append("hook")
            for role in setup_roles:
                if role not in shot_type_roles:
                    shot_type_roles.append(role)
            shot_profile = {"types": shot_type_roles}

            # Step 3: 四线赛马 → 4 份草稿 (ARCH-8)
            click.echo(f"  ✍️ 四线赛马（意象师/节奏师/对话师/结构师）...")
            race_result = writer_dispatcher.dispatch_quad_track(
                shot_id=shot_id,
                base_prompt=compiled_prompt,
                persona_prompts=persona_prompts,
                attempt=1,
                deviation_budget=(rhythm_budget or 0.5) * blank_budget_multiplier,
                temperature_cap=blank_temp_cap,
                blank_shot=is_blank_shot,
            )
            draft_ids = [d["draft_id"] for d in race_result["drafts"]]

            # Step 4: 质量门 1（机械检查：空文/太短/重复）
            usable = quality_controller.gate1_check(shot_id, draft_ids)
            for d in race_result["drafts"]:
                if d["draft_id"] in usable:
                    writer_dispatcher.mark_draft_usable(d["draft_id"])

            if not usable:
                # D25-R1: 记录 gate1 失败
                try:
                    ft = classify_failure_type(
                        gate1_violations=["empty_text", "too_short", "excessive_repetition"],
                    )
                    retry_budget.record_failure(shot_id, ft, detail="gate1 all failed")
                except CircuitBreakerTriggered:
                    click.echo(f"  🔴 熔断：此 shot 同类失败 {retry_budget.circuit_breaker_threshold} 次，跳过")
                    continue
                except RetryBudgetExhausted as exc:
                    click.echo(f"  🔴 重试预算耗尽: {exc}，跳过后续 shots")
                    break

                click.echo(f"  🔴 质量门 1 全部失败（空文/太短），进入第二轮")
                # 第二轮写作
                race_result2 = writer_dispatcher.dispatch_quad_track(
                    shot_id=shot_id, base_prompt=compiled_prompt, attempt=2,
                    persona_prompts=persona_prompts,
                    deviation_budget=(rhythm_budget or 0.5) * blank_budget_multiplier,
                    temperature_cap=blank_temp_cap,
                    blank_shot=is_blank_shot,
                )
                draft_ids = [d["draft_id"] for d in race_result2["drafts"]]
                usable = quality_controller.gate1_check(shot_id, draft_ids)
                for d in race_result2["drafts"]:
                    if d["draft_id"] in usable:
                        writer_dispatcher.mark_draft_usable(d["draft_id"])

                if not usable:
                    click.echo(f"  🔴 第二轮仍失败，跳过此 Shot")
                    quality_controller.smart_redo(shot_id, 0)
                    continue
                draft_ids = usable  # 第二轮通过的

            # Step 5: 九评委评分
            if is_blank_shot:
                click.echo(f"  ⚖️ 留白创意评审（提高 unexpected_value 权重）...")
            else:
                click.echo(f"  ⚖️ 九评委评分（标准权重）...")
            jury_verdict = jury_service.score_candidates(
                shot_id=shot_id,
                draft_ids=draft_ids if isinstance(draft_ids, list) else usable,
                meta_contract=layers,
                quality_threshold=quality_threshold,
                creative_review=is_blank_shot,
                shot_profile=shot_profile,
            )

            winner_id = jury_verdict.get("winner_draft_id")
            winner_score = jury_verdict.get("winner_score", 0)
            winner_track = jury_verdict.get("winner_track")

            if _jury_verdict_all_unavailable(jury_verdict):
                score_key = jury_verdict.get("score_key", "literary_score")
                for did, ds in jury_verdict.get("draft_scores", {}).items():
                    click.echo(
                        _format_jury_draft_score(did, ds, score_key=score_key)
                    )
                _raise_if_jury_unavailable(
                    jury_verdict, shot_id=shot_id, retry_budget=retry_budget,
                )

            # ARCH-11: 反契约沙盒评估 — 如果 deviation 赛道胜出，记录人类裁决需求
            try:
                sandbox = AntiContractSandbox(db, run_id)
                deviant_draft_id = race_result.get("deviant_draft_id")
                if deviant_draft_id and deviant_draft_id != winner_id:
                    # Build compliant draft IDs (all non-deviant drafts)
                    compliant_ids = [
                        d["draft_id"] for d in race_result["drafts"]
                        if d["draft_id"] != deviant_draft_id
                    ]
                    # Only evaluate if deviant draft got a score
                    deviant_score = jury_verdict.get("draft_scores", {}).get(deviant_draft_id, {}).get("trimmed_mean", 0)
                    if deviant_score > 0 and compliant_ids:
                        deviation_result = sandbox.evaluate_deviation(
                            shot_id=shot_id,
                            deviant_draft_id=deviant_draft_id,
                            compliant_draft_ids=compliant_ids,
                            jury_scores=jury_verdict.get("draft_scores", {}),
                        )
                        if deviation_result.get("flagged"):
                            click.echo(
                                f"  🔓 反契约沙盒: {race_result.get('deviant_persona', '?')} 偏离胜出 "
                                f"(优势={deviation_result['advantage']:.1f}) → 人类裁决 #{deviation_result.get('human_review_id', '?')}"
                            )
            except Exception:
                pass  # Sandbox evaluation is non-blocking

            # Step 6: 阈值判断 → 全部低于阈值则第二轮重写
            if (
                not jury_verdict.get("all_passed_threshold", False)
                and (
                    winner_score < quality_threshold
                    or jury_verdict.get("passing_count", 0) < jury_verdict.get("min_passing_drafts", 2)
                )
            ):
                # D25-R1: 记录 jury 阈值失败
                try:
                    retry_budget.record_failure(
                        shot_id, "below_threshold",
                        detail=f"score={winner_score:.2f}<threshold={quality_threshold}",
                    )
                except CircuitBreakerTriggered:
                    click.echo(f"  🔴 熔断：此 shot 同类失败 {retry_budget.circuit_breaker_threshold} 次，跳过")
                    continue
                except RetryBudgetExhausted as exc:
                    click.echo(f"  🔴 重试预算耗尽: {exc}，跳过后续 shots")
                    break

                click.echo(
                    f"    最高分 {winner_score} / 过线稿 {jury_verdict.get('passing_count', 0)}"
                    f"<{jury_verdict.get('min_passing_drafts', 2)} / 阈值 {quality_threshold}"
                    f" → 触发第二轮重写"
                )
                draft_score_map = jury_verdict.get("draft_scores", {})
                passing_draft_ids = [
                    did for did, ds in draft_score_map.items()
                    if ds.get("eligible", True)
                    and ds.get(jury_verdict.get("score_key", "literary_score"), 0) >= quality_threshold
                ]
                if passing_draft_ids:
                    rewrite_candidates = sorted(
                        draft_score_map.items(),
                        key=lambda item: (
                            item[1].get("eligible", True),
                            item[1].get(jury_verdict.get("score_key", "literary_score"), 0),
                        ),
                    )
                    rewrite_draft_id = rewrite_candidates[0][0]
                    rewrite_persona = "结构师"
                    for draft_meta in race_result.get("drafts", []):
                        if draft_meta["draft_id"] == rewrite_draft_id:
                            rewrite_persona = draft_meta.get("persona") or rewrite_persona
                            break
                    click.echo(f"  ✍️ 单线返写：{rewrite_persona}")
                    race_result2 = writer_dispatcher.dispatch_single_persona_track(
                        shot_id=shot_id, base_prompt=compiled_prompt,
                        persona_prompts=persona_prompts,
                        persona_name=rewrite_persona, attempt=2,
                        deviation_budget=(rhythm_budget or 0.5) * blank_budget_multiplier,
                        temperature_cap=blank_temp_cap,
                        blank_shot=is_blank_shot,
                    )
                else:
                    race_result2 = writer_dispatcher.dispatch_quad_track(
                        shot_id=shot_id, base_prompt=compiled_prompt, attempt=2,
                        persona_prompts=persona_prompts,
                        deviation_budget=(rhythm_budget or 0.5) * blank_budget_multiplier,
                        temperature_cap=blank_temp_cap,
                        blank_shot=is_blank_shot,
                    )
                draft_ids2 = [d["draft_id"] for d in race_result2["drafts"]]
                usable2 = quality_controller.gate1_check(shot_id, draft_ids2)
                for d in race_result2["drafts"]:
                    if d["draft_id"] in usable2:
                        writer_dispatcher.mark_draft_usable(d["draft_id"])

                if usable2:
                    click.echo(f"  ⚖️ 第二轮九评委评分...")
                    combined_usable = list(dict.fromkeys(passing_draft_ids + usable2))
                    jury_verdict2 = jury_service.score_candidates(
                        shot_id=shot_id,
                        draft_ids=combined_usable,
                        meta_contract=layers,
                        quality_threshold=quality_threshold,
                        creative_review=is_blank_shot,
                        shot_profile=shot_profile,
                    )
                    _raise_if_jury_unavailable(
                        jury_verdict2, shot_id=shot_id, retry_budget=retry_budget,
                    )
                    # 选分数更高的那份
                    if (
                        jury_verdict2.get("winner_score", 0) > winner_score
                        or jury_verdict2.get("passing_count", 0) > jury_verdict.get("passing_count", 0)
                    ):
                        jury_verdict = jury_verdict2
                        winner_id = jury_verdict.get("winner_draft_id")
                        winner_score = jury_verdict.get("winner_score", 0)
                        winner_track = jury_verdict.get("winner_track")

            if not jury_verdict.get("all_passed_threshold", False):
                click.echo(
                    f"  🔴 仍未满足过线稿数量："
                    f"{jury_verdict.get('passing_count', 0)}"
                    f"<{jury_verdict.get('min_passing_drafts', 2)}，不封版"
                )
                quality_controller.smart_redo(shot_id, 0)
                continue

            # 打印评分详情
            score_key = jury_verdict.get("score_key", "literary_score")
            for did, ds in jury_verdict.get("draft_scores", {}).items():
                click.echo(
                    _format_jury_draft_score(did, ds, score_key=score_key)
                )

            # Step 7: 写入修订记录
            if winner_id:
                gate2 = quality_controller.gate2_check(shot_id, winner_id, jury_verdict)
                light = gate2["light_status"]

                winner_draft = db.execute(
                    "SELECT * FROM writing_drafts WHERE draft_id = ?", (winner_id,)
                ).fetchone()

                from inkflow.utils.hashing import text_hash_normalized
                rev_id = mgr.write_revision(
                    shot_id=shot_id,
                    run_id=run_id,
                    contract_id=sc["contract_id"],
                    revision_sequence=1,
                    operation="write_generate",
                    text=winner_draft["text"],
                    text_hash=text_hash_normalized(winner_draft["text"]),
                    writer_persona=winner_draft["writer_persona"],
                    jury_scores_json={"winner_score": winner_score},
                    gate_result_json=gate2,
                )
                final_rev_id = rev_id
                final_text = winner_draft["text"]

                # CREATIVE-2: winner 后处理精修。保留原 winner revision，
                # 仅在精修有实质变化且通过保守 gate 时写入 write_polish 子 revision。
                if light in ("green", "yellow"):
                    try:
                        polish_svc = PolishService(db, project_id, run_id)
                        polish_result = polish_svc.polish_revision(
                            shot_id=shot_id,
                            source_revision_id=rev_id,
                            contract_id=sc["contract_id"],
                            gate_result=gate2,
                            jury_summary={"winner_score": winner_score},
                        )
                        if polish_result.get("applied"):
                            final_rev_id = polish_result["revision_id"]
                            final_text = polish_result["text"]
                            click.echo(
                                f"  ✨ 二次精修: revision {rev_id[:8]}… "
                                f"→ {final_rev_id[:8]}…"
                            )
                    except Exception as exc:
                        click.echo(f"  ⚠ 二次精修失败: {exc}")

                # L4 Gate: Shot-level architect check before sealing the shot.
                architect_gate = ArchitectGate(db, run_id, project_id, models_config, providers)
                l4_result = architect_gate.evaluate_l4(shot_id, winner_id, gate2)
                if not l4_result["passed"]:
                    click.echo(f"  🔴 L4 Gate 未通过: {l4_result['issues']}")
                    try:
                        retry_budget.record_failure(
                            shot_id, "l4_violation",
                            detail="; ".join(l4_result.get("issues", [])[:3]),
                        )
                    except CircuitBreakerTriggered:
                        click.echo(f"  🔴 熔断：此 shot 同类失败 {retry_budget.circuit_breaker_threshold} 次，跳过")
                        continue
                    except RetryBudgetExhausted as exc:
                        click.echo(f"  🔴 重试预算耗尽: {exc}，跳过后续 shots")
                        break
                    quality_controller.smart_redo(shot_id, 0)
                    continue

                # Finalize — compute brilliance/badsmell from jury scores
                brilliance_level = _compute_brilliance_level(winner_score)
                badsmell_level = _compute_badsmell_level(winner_score)
                quality_controller.finalize_shot(
                    shot_id, winner_id, gate2,
                    brilliance_level=brilliance_level,
                    badsmell_level=badsmell_level,
                )
                mgr.increment_completed_shots(session_id)

                # ARCH-10: 记录风格偏好 (jury winner persona/model/temperature/style_direction)
                try:
                    style_svc = StylePreferenceService(db, project_id, run_id)
                    winner_draft_row = db.execute(
                        "SELECT writer_persona, model_ref, temperature, style_direction "
                        "FROM writing_drafts WHERE draft_id = ?",
                        (winner_id,),
                    ).fetchone()
                    if winner_draft_row:
                        writer_persona = winner_draft_row["writer_persona"]
                        style_direction = winner_draft_row["style_direction"] or {
                            "意象师": "诗意", "节奏师": "克制", "对话师": "生活化", "结构师": "极简"
                        }.get(writer_persona, "未定义")
                        style_svc.record_winner_preference(
                            shot_id=shot_id,
                            draft_id=winner_id,
                            persona=writer_persona,
                            model_ref=winner_draft_row["model_ref"] or "",
                            temperature=winner_draft_row["temperature"] or 0.8,
                            style_direction=style_direction,
                            score=winner_score,
                        )
                        click.echo(
                            f"  🧠 风格偏好: {writer_persona}"
                            f" ({style_direction}) → 已记录"
                        )
                except Exception as exc:
                    click.echo(f"  ⚠ 风格偏好记录失败: {exc}")

                # D25-R1: 记录成功
                retry_budget.record_success(shot_id)

                dh = l4_result.get("dual_helix", {})
                ca = l4_result.get("closing_audit", {})
                if dh.get("碎裂") and dh["碎裂"] != ["no_loss_detected"]:
                    click.echo(f"  💔 碎裂: {', '.join(dh['碎裂'])}")
                if dh.get("重建") and dh["重建"] != ["no_grab_detected"]:
                    click.echo(f"  🤲 重建: {', '.join(dh['重建'])}")
                if ca.get("violation"):
                    click.echo(f"  📝 收束句: ⚠ {ca['violation']}")
                elif ca.get("type"):
                    click.echo(f"  📝 收束句: {ca['type']}")

                # 事实锚点提取
                if light in ("green", "yellow"):
                    try:
                        anchor_ids = fact_extractor.extract(
                            shot_id=shot_id,
                            run_id=run_id,
                            text=final_text,
                            revision_id=final_rev_id,
                        )
                        if anchor_ids:
                            click.echo(f"  📌 提取 {len(anchor_ids)} 个事实锚点")
                    except Exception as exc:
                        click.echo(f"  ⚠ 锚点提取失败: {exc}")

                # Motif 密度追踪：扫描生成文本中的意象出现
                if light in ("green", "yellow"):
                    try:
                        detected = motif_tracker.scan_and_record(
                            shot_id=shot_id, text=final_text,
                        )
                        if detected:
                            click.echo(f"  🎭 检测到 {len(detected)} 个意象")
                    except Exception as exc:
                        click.echo(f"  ⚠ 意象检测失败: {exc}")

                # Checkpoint
                mgr.write_checkpoint(session_id, shot_id, {
                    "shot_index": i + 1,
                    "draft_id": winner_id,
                    "light_status": light,
                    "score": winner_score,
                })

                track_str = f"赛道{winner_track}" if winner_track else "未知"
                click.echo(
                    f"  {'🟢' if light == 'green' else '🟡' if light == 'yellow' else '🔴'} "
                    f"{light} — 均分: {winner_score} — {track_str}胜出"
                )
            else:
                click.echo(f"  🔴 无 winner，创建 placeholder")
                quality_controller.smart_redo(shot_id, 0)

        completion_issues = _chapter_completion_issues(db, run_id, chapter)
        if completion_issues:
            raise click.ClickException(
                "章节未达到封板/导出条件，已停止自动导出；"
                f"未完成项: {', '.join(completion_issues)}"
            )

        # L3 Gate: Chapter-level architect check before completing/exporting.
        if chapter:
            architect_gate = ArchitectGate(db, run_id, project_id, models_config, providers)
            if architect_gate.should_trigger_l3(chapter):
                l3_result = architect_gate.evaluate_l3(chapter)
            else:
                existing_l3 = architect_gate.get_gate_result("L3", chapter)
                if existing_l3 and existing_l3.get("status") == "passed":
                    l3_result = existing_l3.get("check_result_json", {})
                elif existing_l3:
                    l3_result = architect_gate.evaluate_l3(chapter)
                else:
                    raise click.ClickException(
                        "L3 章节 Gate 尚未触发，已停止封板/导出；"
                        "请检查 L4 gate 是否完整通过。"
                    )
            status_icon = "✅" if l3_result["passed"] else "🔴"
            click.echo(
                f"\n{status_icon} L3 章节 Gate: {chapter} — "
                f"POV: {l3_result['pov_coverage']}, "
                f"绿{l3_result['green_count']}/黄{l3_result['yellow_count']}/红{l3_result['red_count']}"
            )
            if l3_result["issues"]:
                for issue in l3_result["issues"]:
                    click.echo(f"  ⚠ {issue}")
            if not l3_result["passed"]:
                failure_shot_id = (
                    l3_result.get("chapter_hook", {}).get("shot_id")
                )
                if not failure_shot_id:
                    last_shot = db.execute(
                        "SELECT shot_id FROM writing_shots "
                        "WHERE run_id = ? AND layer_key = ? "
                        "ORDER BY shot_index DESC LIMIT 1",
                        (run_id, chapter),
                    ).fetchone()
                    failure_shot_id = last_shot["shot_id"] if last_shot else None
                if failure_shot_id:
                    try:
                        failure_type = classify_failure_type(
                            gate1_violations=[],
                            l3_issues=l3_result.get("issues", []),
                        )
                        retry_budget.record_failure(
                            failure_shot_id,
                            failure_type,
                            detail="; ".join(l3_result.get("issues", [])[:3]),
                        )
                    except CircuitBreakerTriggered:
                        click.echo("  🔴 L3 失败重复触发熔断，已记录到最终 shot")
                    except RetryBudgetExhausted as exc:
                        click.echo(f"  🔴 L3 失败归因记录超出重试预算: {exc}")
                raise click.ClickException(
                    "L3 章节 Gate 未通过，已停止封板/导出；"
                    f"问题: {'; '.join(l3_result.get('issues', [])[:5])}"
                )

        # Complete session only after shot completion and L3 gate pass.
        mgr.complete_session(session_id)
        click.echo(f"\n✅ 章节 {chapter} 生成完成。")

        # P0-7: Generate minimal scope report
        _print_scope_report(db, project_id, session_id, run_id, chapter)

        exported = _auto_export_chapter(db, project, chapter, run_id=run_id)
        if exported:
            click.echo(f"\n📤 已自动导出: {exported}")

    next_steps = [f"ink status \"{project}\""]
    if chapter:
        next_steps.insert(0, f"ink review \"{project}\" --chapter {chapter} --accept")
    _next_steps(*next_steps)


# ── contract draft generator ─────────────────────────────────────────────


def _generate_contract_draft(
    project: str,
    story_dir: Path,
    baseline_shots: list[dict],
    draft_path: Path,
) -> None:
    """AI 架构师分析第 1 章 + 大纲 → 生成 contract-draft.yaml。

    高创造力字段留空等待人类填写，
    低创造力字段由 AI 推断填充，
    第 2 章 must_land 事件从大纲提取。
    """
    import yaml

    # Collect chapter 1 sample text
    sample_text = ""
    for shot in baseline_shots:
        text = shot.get("text", "")
        if text:
            sample_text += text[:300] + "\n"

    # Read outline
    outline_text = ""
    outline_path = story_dir / "04_逐章大纲.md"
    if outline_path.exists():
        outline_text = outline_path.read_text(encoding="utf-8")

    # Extract first-volume chapter events. confirm-contract already accepts
    # optional chapter_N_events fields; setup should not strand validation at c02.
    chapter_events_by_number = {
        chapter_number: _extract_chapter_events(outline_text, chapter_number)
        for chapter_number in range(2, 9)
    }
    chapter_2_events = chapter_events_by_number.get(2, [])

    # Detect patterns from chapter 1
    has_sensory = any(w in sample_text for w in ["膝盖", "螺丝刀", "灰", "湿", "保鲜膜", "露水", "茶", "雾"])
    has_body = any(w in sample_text for w in ["拧", "麻", "疼", "抖", "划", "蹭", "撕"])
    locations = _extract_locations(sample_text)
    objects = _extract_objects(sample_text)
    pov_chars = [n for n in ["阿坤", "白英", "苏然", "韩教授"] if n in sample_text]

    # Build draft
    draft = {
        "# 这是 InkFlow 的契约草稿文件": None,
        "# 高创造力字段 (标记为 <<请填写>>) 必须由人类填写": None,
        "# 低创造力字段 (AI 已推断) 请审核后确认": None,
        "# 编辑完成后运行: ink confirm-contract \"{}\"".format(project): None,
        "": None,

        "identity": {
            "title": project,
            "genre": "文学小说",
            "setting": "成都，当代",
            "pov_count": len(pov_chars),
            "pov_characters": pov_chars,
            "character_arcs": "<<请填写: 各角色核心弧线, 如: 阿坤: 从被动承受到主动选择>>",
        },

        "narrative_voice": {
            "style": "现实主义 + 感官密度",
            "sensory_density": "高" if has_sensory else "中",
            "body_moment": "是" if has_body else "否",
            "dialogue_ratio": "中",
            "register": "文学性普通话 + 成都方言点缀",
            "register_tone": "<<请填写: 叙事语气基调, 如: 冷静克制, 不煽情, 让事实本身说话>>",
        },

        "hard_boundaries": {
            "characters_alive": pov_chars,
            "world_rules": [
                "鱼嘴系统分流外卖/教育/医疗/住房/信用五领域",
                "内江=三环以内核心服务圈；外江=三环以外低优先级分流圈；运行期外江口径向三环内侧侵蚀，吞入内江边缘街区，内江变小",
                "系统不恶意，但代价在积累",
            ],
            "fixed_events": "<<请填写: 第 2 章中不可改变的事件, 如: 阿坤遇到拖行李箱的年轻人>>",
        },

        "style_locks": {
            "opening": "身体时刻开场（感官冲击）",
            "ending": "动作/物件/沉默结尾，不总结",
            "sensory": "每段至少一处气味/声音/温度/湿度描写",
            "dialect": "成都话点缀，不是普通话翻译",
            "paragraph_length": "正文按镜头节奏自然分段；导出层负责短段排版，单个自然段宜控制在约 420 字以内，镜头转换可加分隔符",
        },

        "anti_patterns": {
            "avoid": [
                "概念总结性结尾",
                "系统被描绘为纯粹恶人",
                "人物内心独白过长",
                "成都写成旅游宣传",
                "意象被解释（如'太阳神鸟象征XX'）",
            ],
        },

        "world_knowledge": {
            "locations": locations or ["成都城区"],
            "key_objects": objects or ["保鲜膜", "头盔", "太阳神鸟", "盖碗茶"],
            "time_period": "当代",
            "season": "十二月（成都冬季）",
            "weather": "灰白、湿冷、雾、雨",
        },

        "motif_system": {
            "primary": ["膝盖/螺丝刀（损伤）", "都江堰分流（系统）", "金沙垃圾层（时间）"],
            "secondary": ["盖碗茶", "太阳神鸟", "保鲜膜", "握空的手"],
            "visual_markers": ["屏幕颜色边界（内江蓝/外江橙）", "系统之眼（摄像头/传感器）", "待评估（多场景重复）"],
        },

        "creative_zones": {
            "allowed_freedom": "对话细节、环境描写、次要人物互动、成都感官细节",
            "must_consult": "POV 角色核心情节走向、重要事件变更",
            "chapter_2_scope": "严格执行 04_逐章大纲.md 第 2 章章级事件，只允许补充细节不允许改变走向",
            "chapter_2_interpretation": "<<请填写: 第 2 章的创作诠释, 如: 这一章的核心情绪是什么? 希望读者感受到什么?>>",
        },

        "suspense_config": {
            "# 悬疑引擎配置": None,
            "# 前台抓手：读者第一秒追什么": None,
            "# 信息差：读者知道但角色不知道的事": None,
            "# 核心物件：每次出现读者理解不同": None,
            "# 章末钩子：未完成动作，不能是感官收束": None,
            "# 数字有体温：数字+具体的人或物": None,
            "": None,
            "reader_anchor": "<<请填写: 读者第一秒追什么？如: 阿坤的膝盖还能撑多久？系统会不会把他完全推到外江？>>",
            "information_gap": [
                "苏然发现了6%的边界外推，但阿坤、白英、韩教授都不知道——读者知道，角色不知道",
                "骨片上的握空手势，韩教授在三星堆也见过类似图案——读者知道这个关联，但韩教授还没说出来",
                "茶社对面的火锅店昨天还在营业，今天挂了'装修中'——读者知道城市在收缩，但白英还不知道这意味着什么",
            ],
            "core_objects": {
                "骨片/握空的手": "背景→线索→证据：第一次是韩教授发现的刻痕，第二次读者意识到这手势在三星堆也出现过，第三次揭示它指向某种制度性的'放弃'",
                "太阳神鸟": "从阿坤头盔上的褪色贴纸→白英茶社里学生临摹的蓝色画→苏然屏幕上的系统图标→金沙出土的金饰残片，四层理解",
                "保鲜膜": "从阿坤的护膝工具→系统对身体的'包裹'和'隔离'→边界标记，意义逐层升级",
                "34分": "阿坤跑了三年，膝盖跑废了，系统给了34分——这个数字在第2章就要出现，让读者知道它，但不知道它还会不会涨",
            },
            "chapter_hooks": [
                "每章最后一句必须是未完成动作（物理中断/对话中断/决策悬置/感知突变），不能是感官收束或解释",
                "不要让读者在章末感到'这一章结束了'，要感到'必须翻下一页才知道发生了什么'",
                "至少每2章出现一次信息差——读者知道某件事，但POV角色不知道",
            ],
            "numbers_with_temperature": [
                "37单 → 阿坤的膝盖（内江有37单，系统却让他去外江）",
                "6% → 苏然的屏幕（边界线每年外推6%，这不是数字，是每年被推出去的人）",
                "34分 → 阿坤的健康积分（三年膝盖换34分，够不够换一副护具？）",
                "4个通知 → 白英的抽屉（去年是'建议优化'，今年是'建议转型'，明年是什么？）",
            ],
            "suspense_density": "制度悬疑——悬念不是'谁杀了人'，而是'为什么这个结构会逼出这样的处境'，以及'谁该负责'",
        },

        "chapter_2_events": chapter_2_events or [
            {"shot": 1, "pov": "阿坤", "event": "<<请从大纲填写第 2 章第 1 shot 事件>>"},
            {"shot": 2, "pov": "韩教授", "event": "<<请从大纲填写第 2 章第 2 shot 事件>>"},
            {"shot": 3, "pov": "白英", "event": "<<请从大纲填写第 2 章第 3 shot 事件>>"},
            {"shot": 4, "pov": "苏然", "event": "<<请从大纲填写第 2 章第 4 shot 事件>>"},
        ],
    }

    for chapter_number in range(3, 9):
        events = chapter_events_by_number.get(chapter_number) or []
        if events:
            draft[f"chapter_{chapter_number}_events"] = events

    # Write draft
    draft_path.parent.mkdir(parents=True, exist_ok=True)
    yaml_text = _yaml_dump_contract(draft)
    draft_path.write_text(yaml_text, encoding="utf-8")
    click.echo(f"契约草稿已生成: {draft_path}")


def _extract_locations(text: str) -> list[str]:
    """Extract locations from chapter 1."""
    locs = []
    for loc in ["人民公园", "春熙路", "锦江区", "龙潭寺", "石板滩", "新都",
                 "天府软件园", "金沙遗址", "望鹤茶社", "九眼桥", "都江堰"]:
        if loc in text:
            locs.append(loc)
    return locs or ["成都城区"]


def _extract_objects(text: str) -> list[str]:
    """Extract key recurring objects from chapter 1."""
    objs = []
    for obj in ["保鲜膜", "头盔", "太阳神鸟", "盖碗茶", "竹椅", "泡菜坛",
                 "薄荷", "螺丝刀", "护膝", "杯子"]:
        if obj in text:
            objs.append(obj)
    return objs[:8]


def _extract_chapter_2_events(outline_text: str) -> list[dict]:
    """Extract chapter 2 must-land events from the outline."""
    return _extract_chapter_events(outline_text, 2)


def _extract_chapter_events(outline_text: str, chapter_number: int) -> list[dict]:
    """Extract must-land events for a chapter from the outline."""
    marker = f"第 {chapter_number:02d} 章"
    if marker not in outline_text:
        return []

    idx = outline_text.find(marker)
    next_marker = f"第 {chapter_number + 1:02d} 章"
    end = outline_text.find(next_marker, idx)
    if end == -1:
        end = idx + 5000
    chapter_text = outline_text[idx:end]

    events = []
    # Parse structured POV blocks
    lines = chapter_text.split("\n")
    current_pov = ""
    current_event = ""

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("**阿坤"):
            if current_pov and current_event:
                events.append({"shot": len(events) + 1, "pov": current_pov, "event": current_event[:300]})
            current_pov = "阿坤"
            current_event = stripped
        elif stripped.startswith("**韩教授"):
            if current_pov and current_event:
                events.append({"shot": len(events) + 1, "pov": current_pov, "event": current_event[:300]})
            current_pov = "韩教授"
            current_event = stripped
        elif stripped.startswith("**白英"):
            if current_pov and current_event:
                events.append({"shot": len(events) + 1, "pov": current_pov, "event": current_event[:300]})
            current_pov = "白英"
            current_event = stripped
        elif stripped.startswith("**苏然"):
            if current_pov and current_event:
                events.append({"shot": len(events) + 1, "pov": current_pov, "event": current_event[:300]})
            current_pov = "苏然"
            current_event = stripped
        elif current_pov and stripped and not stripped.startswith("#"):
            current_event += " " + stripped

    # Flush last
    if current_pov and current_event:
        events.append({"shot": len(events) + 1, "pov": current_pov, "event": current_event[:300]})

    return events


def _yaml_dump_contract(draft: dict) -> str:
    """Dump contract dict to readable YAML."""
    import yaml

    # Filter out comment keys (starting with #)
    clean = {k: v for k, v in draft.items() if not k.startswith("#") and k != ""}

    # Use yaml.dump with block style
    return yaml.dump(
        clean,
        allow_unicode=True,
        default_flow_style=False,
        sort_keys=False,
        width=120,
    )


# ── scope report helper ──────────────────────────────────────────────────


def _print_scope_report(
    db, project_id: str, session_id: str, run_id: str, chapter: str
) -> None:
    """P0-7: Print minimal scope report for a completed chapter."""
    # Shot counts by status
    shot_rows = db.execute(
        "SELECT shot_status, light_status, COUNT(*) as cnt "
        "FROM writing_shots WHERE project_id = ? AND layer_key = ? "
        "GROUP BY shot_status, light_status",
        (project_id, chapter),
    ).fetchall()

    green = yellow = red = other = 0
    for row in shot_rows:
        if row["light_status"] == "green":
            green += row["cnt"]
        elif row["light_status"] == "yellow":
            yellow += row["cnt"]
        elif row["shot_status"] in ("done_red_permanent", "placeholder"):
            red += row["cnt"]
        else:
            other += row["cnt"]
    total = green + yellow + red + other

    # Average winner score
    score_row = db.execute(
        "SELECT AVG(jury_scores_json->>'winner_score') as avg_score "
        "FROM shot_revisions sr "
        "JOIN writing_shots ws ON sr.shot_id = ws.shot_id "
        "WHERE ws.project_id = ? AND ws.layer_key = ? "
        "AND sr.jury_scores_json IS NOT NULL",
        (project_id, chapter),
    ).fetchone()
    avg_score = score_row["avg_score"] if score_row else None

    # Fact anchors extracted
    anchor_row = db.execute(
        "SELECT COUNT(*) as cnt FROM writing_fact_anchors fa "
        "JOIN writing_shots ws ON fa.shot_id = ws.shot_id "
        "WHERE ws.project_id = ? AND ws.layer_key = ?",
        (project_id, chapter),
    ).fetchone()
    anchor_count = anchor_row["cnt"] if anchor_row else 0

    click.echo()
    click.echo("═" * 50)
    click.echo(f"  📋 Scope Report — {chapter}")
    click.echo("═" * 50)
    click.echo(f"  总 Shot: {total}")
    click.echo(f"    🟢 Green:   {green}")
    click.echo(f"    🟡 Yellow:  {yellow}")
    click.echo(f"    🔴 Red/PH:  {red}")
    if other:
        click.echo(f"    ⚪ Other:   {other}")
    if avg_score is not None:
        click.echo(f"  平均得分: {avg_score:.1f}")
    click.echo(f"  事实锚点: {anchor_count}")
    click.echo("═" * 50)


# ── repair ──

@main.command("repair")
@click.argument("project")
@click.option("--red", "target_red", is_flag=True, help="修复红灯 shot")
@click.option("--yellow", "target_yellow", is_flag=True, help="修复黄灯 shot")
@click.option("--chapter", default=None, help="仅修复指定章节，如 v01.c02")
@click.option("--all", "target_all", is_flag=True, help="重写指定章节全部 shot（必须配合 --chapter）")
def repair_project(
    project: str,
    target_red: bool,
    target_yellow: bool,
    chapter: str | None,
    target_all: bool,
):
    """AI 修复红灯/黄灯 shot。

    \b
    示例:
      ink repair "分流" --red
      ink repair "分流" --yellow
    """
    from inkflow.db import init_project_db

    db_path = _resolve_project_db(project)
    db = init_project_db(db_path)

    row = db.execute(
        "SELECT project_id FROM projects WHERE name = ?", (project,)
    ).fetchone()
    if row is None:
        db.close()
        raise click.ClickException(f"项目 '{project}' 尚未初始化。")

    project_id = row["project_id"]

    target_status = []
    if target_all:
        if not chapter:
            db.close()
            raise click.ClickException("--all 必须配合 --chapter，避免误重写全书。")
        target_status.extend([
            "pending", "generating", "gate1_check", "jury_scoring", "final_gate",
            "redo", "done_green", "done_yellow", "done_red_permanent", "placeholder",
        ])
    else:
        if target_red:
            target_status.append("done_red_permanent")
        if target_yellow:
            target_status.append("done_yellow")

    if not target_status:
        db.close()
        raise click.ClickException("请指定 --red、--yellow，或 --chapter <key> --all。")

    placeholders = ",".join("?" for _ in target_status)
    chapter_filter = "AND layer_key = ? " if chapter else ""
    params = [project_id] + target_status
    if chapter:
        params.append(chapter)
    shots = db.execute(
        f"SELECT shot_id, run_id, shot_index, layer_key, light_status, redo_attempt "
        f"FROM writing_shots "
        f"WHERE project_id = ? AND shot_status IN ({placeholders}) "
        f"{chapter_filter}"
        f"ORDER BY shot_index",
        params,
    ).fetchall()

    if not shots:
        click.echo("没有需要修复的 shot。")
        db.close()
        return

    from inkflow.services import QualityController
    run_ids = {shot["run_id"] for shot in shots}
    if len(run_ids) != 1:
        db.close()
        raise click.ClickException(
            f"命中多个 run，无法安全修复: {', '.join(sorted(run_ids))}"
        )
    run_id = shots[0]["run_id"]
    qc = QualityController(db, run_id)

    click.echo(f"待修复 Shot: {len(shots)}")
    shot_ids = [shot["shot_id"] for shot in shots]
    shot_placeholders = ",".join("?" for _ in shot_ids)
    db.execute(
        f"DELETE FROM writing_architect_gates "
        f"WHERE run_id = ? AND level = 'L4' AND scope_key IN ({shot_placeholders})",
        [run_id] + shot_ids,
    )
    if chapter:
        db.execute(
            "DELETE FROM writing_architect_gates "
            "WHERE run_id = ? AND level = 'L3' AND scope_key = ?",
            (run_id, chapter),
        )
    db.commit()

    for shot in shots:
        icon = "🔴" if shot["light_status"] == "red" else "🟡" if shot["light_status"] == "yellow" else "🟢"
        current_attempt = shot["redo_attempt"]
        if target_all:
            db.execute(
                "UPDATE writing_shots SET redo_attempt = 0 WHERE shot_id = ?",
                (shot["shot_id"],),
            )
            db.commit()
            current_attempt = 0
        if current_attempt >= 3:
            click.echo(f"  {icon} Shot {shot['shot_index']}: 已达最大重试次数，跳过")
            continue

        result = qc.smart_redo(shot["shot_id"], current_attempt)
        click.echo(
            f"  {icon} Shot {shot['shot_index']}: "
            f"redo → {result['action']} (level={result['level']})"
        )

    total_row = db.execute(
        "SELECT COUNT(*) AS cnt FROM writing_shots WHERE run_id = ?",
        (run_id,),
    ).fetchone()
    completed_row = db.execute(
        "SELECT COUNT(*) AS cnt FROM writing_shots "
        "WHERE run_id = ? AND shot_status IN ('done_green', 'done_yellow')",
        (run_id,),
    ).fetchone()
    db.execute(
        "UPDATE writing_sessions SET status = 'active', completed_shots = ?, "
        "total_shots = ?, current_shot_id = NULL, updated_at = datetime('now') "
        "WHERE run_id = ?",
        (completed_row["cnt"], total_row["cnt"], run_id),
    )
    db.commit()

    chapter_part = f" --chapter {chapter}" if chapter else ""
    click.echo(f"\n已触发修复，请运行 ink run \"{project}\"{chapter_part} --resume 继续生成。")
    db.close()


# ── resume ──

@main.command("resume")
@click.argument("session_id")
def resume_session(session_id: str):
    """从崩溃/断点恢复。自动找到 session 并委托给 run --resume。

    \b
    示例:
      ink resume <session_id>
    """
    from inkflow.db import init_project_db
    from inkflow.services import SessionManager

    # Find the project for this session
    story_base = Path(r"D:\_Progs\.Story")

    for story_dir in story_base.iterdir():
        if not story_dir.is_dir():
            continue
        db_path = story_dir / ".inkflow" / "inkflow.db"
        if not db_path.exists():
            continue

        db = init_project_db(db_path)
        row = db.execute(
            "SELECT project_id, run_id, act_id, status, completed_shots, total_shots "
            "FROM writing_sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()

        if row:
            project_name = story_dir.name.strip("《》")
            click.echo(f"项目: {project_name}")
            click.echo(f"Session: {session_id}")
            click.echo(f"状态: {row['status']}")
            click.echo(f"已完成: {row['completed_shots']}/{row['total_shots']} shots")

            checkpoint = db.execute(
                "SELECT checkpoint_json FROM writing_session_checkpoints "
                "WHERE session_id = ? ORDER BY created_at DESC LIMIT 1",
                (session_id,),
            ).fetchone()
            if checkpoint:
                import json
                cp_data = json.loads(checkpoint["checkpoint_json"])
                click.echo(f"最新检查点: shot {cp_data.get('shot_index', '?')}")

            mgr = SessionManager(db, row["project_id"])
            _print_failure_summary(mgr.get_session_failure_summary(session_id))

            if row["status"] == "completed":
                db.close()
                raise click.ClickException("该 session 已完成，不能恢复。")

            db.close()

            # Delegate to run --resume
            click.echo(f"\n恢复生成中...")
            ctx = click.get_current_context()
            ctx.invoke(
                run_project,
                project=project_name,
                chapter=row["act_id"],
                shot_id=None,
                writer_count=2,
                shot_count=row["total_shots"],
                resume=True,
                local_jury=False,
                resume_session_id=session_id,
            )
            return

        db.close()

    raise click.ClickException(f"未找到 session: {session_id}")


# ── sessions ──

@main.group("sessions")
def sessions_group():
    """Session 管理命令。"""
    pass


@sessions_group.command("list")
@click.argument("project", required=False)
def sessions_list(project: str | None):
    """列出可恢复和已放弃的 session。可指定项目名缩小范围。

    \b
    示例:
      ink sessions list           # 扫描所有项目
      ink sessions list "分流"    # 仅指定项目
    """
    from inkflow.db import init_project_db
    from inkflow.services import SessionManager

    story_base = Path(r"D:\_Progs\.Story")
    found_any = False

    if project:
        targets = [story_base / f"《{project}》"]
    else:
        if not story_base.exists():
            click.echo("没有未完成的 session。")
            return
        targets = [d for d in story_base.iterdir() if d.is_dir()]

    for story_dir in targets:
        if not story_dir.is_dir():
            continue
        db_path = story_dir / ".inkflow" / "inkflow.db"
        if not db_path.exists():
            continue

        db = init_project_db(db_path)
        rows = db.execute(
            "SELECT * FROM writing_sessions "
            "WHERE status IN ('active', 'paused', 'crashed', 'aborted') "
            "ORDER BY created_at DESC"
        ).fetchall()

        if rows:
            if not found_any:
                click.echo("Session:")
                found_any = True

            project_name = story_dir.name
            mgr = SessionManager(db, rows[0]["project_id"])
            for row in rows:
                status_icon = {
                    "active": "▶",
                    "paused": "⏸",
                    "crashed": "💥",
                    "aborted": "✖",
                }.get(row["status"], "?")
                label = _format_failure_summary(
                    mgr.get_session_failure_summary(row["session_id"])
                )
                failure = f" | failures: {label}" if label else ""
                click.echo(
                    f"  {status_icon} {row['session_id'][:12]}... "
                    f"| {project_name} | {row['status']} "
                    f"| {row['completed_shots']}/{row['total_shots']} shots"
                    f"{failure}"
                )

        db.close()

    if not found_any:
        click.echo("没有可恢复或已放弃的 session。")


@sessions_group.command("abort")
@click.argument("session_id")
@click.option("--project", default=None, help="项目名（加速查找）")
def sessions_abort(session_id: str, project: str | None):
    """放弃 session，已生成文本保留。

    \b
    示例:
      ink sessions abort <session_id>
      ink sessions abort <session_id> --project "分流"
    """
    from inkflow.db import init_project_db
    from inkflow.services import SessionManager

    story_base = Path(r"D:\_Progs\.Story")

    if project:
        targets = [story_base / f"《{project}》"]
    else:
        if not story_base.exists():
            raise click.ClickException(f"未找到 session: {session_id}")
        targets = [d for d in story_base.iterdir() if d.is_dir()]

    for story_dir in targets:
        if not story_dir.is_dir():
            continue
        db_path = story_dir / ".inkflow" / "inkflow.db"
        if not db_path.exists():
            continue

        db = init_project_db(db_path)
        row = db.execute(
            "SELECT project_id FROM writing_sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()

        if row:
            mgr = SessionManager(db, row["project_id"])
            mgr.abort_session(session_id)

            # Clean up non-terminal shots for this session's run
            run_row = db.execute(
                "SELECT run_id FROM writing_sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone()
            if run_row:
                db.execute(
                    "UPDATE writing_shots SET shot_status = 'placeholder', "
                    "placeholder_type = 'redo_placeholder', updated_at = datetime('now') "
                    "WHERE run_id = ? AND shot_status NOT IN "
                    "('done_green', 'done_yellow', 'done_red_permanent')",
                    (run_row["run_id"],),
                )
                db.commit()

            click.echo(f"Session {session_id[:12]}... 已放弃。")
            click.echo("已生成文本已保留。")
            db.close()
            return

        db.close()

    raise click.ClickException(f"未找到 session: {session_id}")


# ── review ──

@main.command("review")
@click.argument("project")
@click.option("--chapter", required=True, help="章节 key，如 v01.c03")
@click.option("--accept", is_flag=True, help="人工接受本章，允许作为后续上下文")
@click.option("--revise", default=None, help="人工要求修订，填写具体意见")
@click.option("--reject", is_flag=True, help="人工否决本章，下轮必须重写")
@click.option("--notes", default=None, help="补充备注")
def review_project(
    project: str,
    chapter: str,
    accept: bool,
    revise: str | None,
    reject: bool,
    notes: str | None,
):
    """记录生产后人工审稿结论。

    \b
    示例:
      ink review "分流" --chapter v01.c03 --accept
      ink review "分流" --chapter v01.c03 --revise "章末钩子不够"
      ink review "分流" --chapter v01.c03 --reject --notes "整体重写"
    """
    from datetime import datetime, timezone
    from inkflow.db import init_project_db

    selected = sum(1 for value in (accept, bool(revise), reject) if value)
    if selected != 1:
        raise click.ClickException("请且只请指定 --accept、--revise 或 --reject。")

    db_path = _resolve_project_db(project)
    db = init_project_db(db_path)
    project_row = db.execute(
        "SELECT project_id FROM projects WHERE name = ?", (project,)
    ).fetchone()
    if project_row is None:
        db.close()
        raise click.ClickException(f"项目 '{project}' 尚未初始化。")

    project_id = project_row["project_id"]
    latest_run = _latest_chapter_run(db, project_id, chapter)
    run_id = latest_run["run_id"] if latest_run else None

    if accept:
        if not latest_run:
            db.close()
            raise click.ClickException(
                f"章节 {chapter} 没有可接受的生产 run，不能标记为 accepted。"
            )
        if latest_run["status"] != "completed":
            db.close()
            raise click.ClickException(
                f"章节 {chapter} 最新 run 状态为 {latest_run['status']}，"
                "只有 completed run 可以 accepted。"
            )
        completion_issues = _chapter_completion_issues(db, latest_run["run_id"], chapter)
        if completion_issues:
            db.close()
            raise click.ClickException(
                "章节仍有未封板 shot，不能 accepted；"
                f"未完成项: {', '.join(completion_issues)}"
            )
        if not _chapter_l3_passed(db, latest_run["run_id"], chapter):
            db.close()
            raise click.ClickException(
                "L3 章节 Gate 未通过或未记录，不能 accepted。"
            )

    stat_where = "project_id = ? AND layer_key = ?"
    stat_params: list[object] = [project_id, chapter]
    if run_id:
        stat_where += " AND run_id = ?"
        stat_params.append(run_id)
    shot_stats = [
        {
            "shot_status": row["shot_status"],
            "light_status": row["light_status"],
            "count": row["cnt"],
        }
        for row in db.execute(
            "SELECT shot_status, light_status, COUNT(*) AS cnt "
            f"FROM writing_shots WHERE {stat_where} "
            "GROUP BY shot_status, light_status",
            stat_params,
        ).fetchall()
    ]

    exported_path = (
        _STORY_BASE / f"《{project}》" / "正文" / f"{project}_{chapter}_导出.md"
    )
    status = "accepted" if accept else "needs_revision" if revise else "rejected"
    review_data = {
        "schema": "inkflow.chapter_review.v1",
        "project": project,
        "chapter": chapter,
        "status": status,
        "run_id": run_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "review": revise or notes or "",
        "notes": notes,
        "exported_path": str(exported_path) if exported_path.exists() else None,
        "shot_stats": shot_stats,
        "next_action": (
            "setup_next_chapter" if accept else
            "rerun_setup_and_run_for_this_chapter"
        ),
    }
    review_path = _chapter_review_path(project, chapter)
    _write_yaml_file(review_path, review_data)
    _record_chapter_review_db(
        db,
        project_id=project_id,
        chapter=chapter,
        run_id=run_id,
        status=status,
        review_text=revise or notes or "",
        notes=notes,
        exported_path=exported_path,
        shot_stats=shot_stats,
    )
    db.commit()
    db.close()

    click.echo(f"人工审稿结论已记录: {review_path}")
    click.echo("DB canonical 状态已更新。")
    click.echo(f"状态: {status}")
    if status == "accepted":
        _next_steps(f"ink setup \"{project}\" --chapter <下一章>")
    else:
        _next_steps(
            f"ink setup \"{project}\" --chapter {chapter} --force",
            f"ink run \"{project}\" --chapter {chapter} --resume",
        )


# ── status ──

@main.command("status")
@click.argument("project")
def status_project(project: str):
    """查看写作进度。

    \b
    示例:
      ink status "分流"
    """
    from inkflow.db import init_project_db

    db_path = _resolve_project_db(project)
    db = init_project_db(db_path)

    row = db.execute(
        "SELECT project_id FROM projects WHERE name = ?", (project,)
    ).fetchone()
    if row is None:
        db.close()
        raise click.ClickException(f"项目 '{project}' 尚未初始化。")

    project_id = row["project_id"]

    # Session stats
    sessions = db.execute(
        "SELECT status, COUNT(*) as cnt FROM writing_sessions "
        "WHERE project_id = ? GROUP BY status",
        (project_id,),
    ).fetchall()

    click.echo(f"项目: {project}")

    # Shot stats
    shot_stats = db.execute(
        "SELECT shot_status, light_status, COUNT(*) as cnt "
        "FROM writing_shots WHERE project_id = ? "
        "GROUP BY shot_status, light_status",
        (project_id,),
    ).fetchall()

    if shot_stats:
        click.echo("\nShot 状态:")
        for s in shot_stats:
            click.echo(f"  {s['shot_status']} ({s['light_status'] or '-'}): {s['cnt']}")

    # Contract status
    contract = db.execute(
        "SELECT status FROM writing_meta_contract WHERE project_id = ? "
        "ORDER BY created_at DESC LIMIT 1",
        (project_id,),
    ).fetchone()

    if contract:
        click.echo(f"\n元契约: {contract['status']}")

    # Session list
    if sessions:
        click.echo("\nSession:")
        for s in sessions:
            click.echo(f"  {s['status']}: {s['cnt']}")

    story_dir = _STORY_BASE / f"《{project}》"
    setup_dir = story_dir / ".inkflow" / "chapter-setups"
    review_dir = story_dir / ".inkflow" / "chapter-reviews"

    if setup_dir.exists():
        setup_files = sorted(setup_dir.glob("*.yaml"))
        if setup_files:
            click.echo("\n章节 Setup:")
            for path in setup_files[-8:]:
                data = _read_yaml_file(path)
                click.echo(
                    f"  {data.get('chapter', path.stem)}: "
                    f"{data.get('status', 'unknown')}"
                )

    if review_dir.exists():
        review_files = sorted(review_dir.glob("*.yaml"))
        if review_files:
            click.echo("\n人工 Review:")
            for path in review_files[-8:]:
                data = _read_yaml_file(path)
                click.echo(
                    f"  {data.get('chapter', path.stem)}: "
                    f"{data.get('status', 'unknown')}"
                )

    db.close()


# ── export ──

@main.command("export")
@click.argument("project")
@click.option("--chapter", default=None, help="章节 key，如 v01.c02（默认全部）")
@click.option("--output", "-o", default=None, help="输出文件路径（默认 正文/ 目录）")
@click.option("--plain", is_flag=True, help="纯文本模式（无标注，无标题）")
@click.option("--draft", is_flag=True, help="导出未人工 accepted 的封板稿（调试/审稿用）")
def export_project(
    project: str,
    chapter: str | None,
    output: str | None,
    plain: bool,
    draft: bool,
):
    """导出当前修订为 Markdown 文件。

    \b
    示例:
      ink export "分流"                        # 导出全部章节
      ink export "分流" --chapter v01.c02      # 仅导出第 2 章
      ink export "分流" --chapter v01.c02 --draft  # 导出未 accepted 的审稿稿
      ink export "分流" --plain -o out.txt     # 纯文本导出
    """
    from inkflow.db import init_project_db
    from inkflow.export import export_markdown, export_plain_text

    db_path = _resolve_project_db(project)
    db = init_project_db(db_path)

    story_dir = _STORY_BASE / f"《{project}》"
    export_dir = story_dir / "正文"
    export_dir.mkdir(parents=True, exist_ok=True)

    if chapter:
        chapters = [chapter]
    else:
        chapters = None  # export function will list all

    if output:
        out_path = Path(output)
        if not out_path.is_absolute():
            out_path = export_dir / out_path
    else:
        chapter_suffix = f"_{chapter}" if chapter else ""
        out_path = export_dir / f"{project}{chapter_suffix}_导出.md"

    accepted_only = not draft
    if plain:
        result = export_plain_text(
            db, out_path, chapters=chapters, accepted_only=accepted_only,
        )
    else:
        result = export_markdown(
            db, out_path, chapters=chapters, accepted_only=accepted_only,
        )

    db.close()

    click.echo(f"导出完成: {result}")
    click.echo(f"  {len(result.read_text(encoding='utf-8'))} 字符")


if __name__ == "__main__":
    main()
