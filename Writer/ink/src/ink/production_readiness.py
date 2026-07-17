from __future__ import annotations

import json
import sqlite3
from dataclasses import asdict, dataclass
from pathlib import Path

from ink.config import load_project_config
from ink.core.capacity_planning import recommended_llm_capacity


@dataclass(frozen=True)
class ReadinessCheck:
    name: str
    passed: bool
    blocking: bool
    detail: str


def inspect_personal_production(
    conn: sqlite3.Connection,
    project_id: int,
) -> dict[str, object]:
    checks: list[ReadinessCheck] = []
    try:
        config = load_project_config(conn, project_id, allow_model_overlap=True)
    except Exception as exc:
        checks.append(ReadinessCheck("project_config", False, True, str(exc)))
        # config 抛错时仍继续结构化诊断:模型池分离是独立查询,不依赖 config 校验,
        # 否则 writer/jury 完全同池会被 config 的"排除 writer 后 jury<min"提前短路,
        # 遮蔽掉 model_pool_separation 这条更可读的报错(history.md:1998 回归)。
        checks.append(_check_model_pool_separation(conn, project_id))
        return _result(project_id, checks, {})

    capacity_row = conn.execute(
        """
        SELECT creative_shot_extra, redo_candidate_count, escalated_jury_count
        FROM writing_projects WHERE project_id = ?
        """,
        (project_id,),
    ).fetchone()
    capacity = recommended_llm_capacity(
        draft_count=config.draft_count,
        creative_shot_extra=int(capacity_row[0]),
        redo_candidate_count=int(capacity_row[1]),
        escalated_jury_count=int(capacity_row[2]),
    )
    checks.append(ReadinessCheck("project_config", True, True, "valid"))
    checks.append(
        ReadinessCheck(
            "llm_capacity",
            config.max_calls_per_shot >= capacity.jury_calls
            and config.max_total_llm_calls >= capacity.total_calls,
            True,
            (
                f"configured={config.max_calls_per_shot}/{config.max_total_llm_calls}; "
                f"recommended>={capacity.jury_calls}/{capacity.total_calls}"
            ),
        )
    )
    integrity = str(conn.execute("PRAGMA integrity_check").fetchone()[0])
    foreign_keys = conn.execute("PRAGMA foreign_key_check").fetchall()
    checks.append(ReadinessCheck("sqlite_integrity", integrity == "ok", True, integrity))
    checks.append(
        ReadinessCheck(
            "foreign_keys",
            not foreign_keys,
            True,
            "ok" if not foreign_keys else f"{len(foreign_keys)} violation(s)",
        )
    )

    checks.append(_check_model_pool_separation(conn, project_id))

    role_rows = conn.execute(
        """
        SELECT call_type, tier, provider, model_name
        FROM writing_model_role_configs
        WHERE project_id = ?
        ORDER BY call_type, tier
        """,
        (project_id,),
    ).fetchall()
    production_rows = [
        row for row in role_rows if str(row[2]) not in {"mock", "deterministic"}
    ]
    checks.append(
        ReadinessCheck(
            "real_model_routes",
            bool(production_rows),
            True,
            f"{len(production_rows)}/{len(role_rows)} enabled routes use real providers",
        )
    )
    forbidden = [
        f"{row[0]}:{row[1]}={row[2]}/{row[3]}"
        for row in role_rows
        if str(row[2]) in {"mock", "deterministic"}
    ]
    checks.append(
        ReadinessCheck(
            "no_mock_routes",
            not forbidden,
            True,
            "ok" if not forbidden else "; ".join(forbidden),
        )
    )

    project = conn.execute(
        "SELECT require_ethics_review FROM writing_projects WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    checks.append(
        ReadinessCheck(
            "ethics_gate",
            project is not None and int(project[0]) == 1,
            False,
            "required" if project is not None and int(project[0]) == 1 else "not required",
        )
    )
    stats = _project_stats(conn, project_id)
    return _result(project_id, checks, stats)


def _check_model_pool_separation(
    conn: sqlite3.Connection,
    project_id: int,
) -> ReadinessCheck:
    """生产硬约束:writer/jury 模型池必须分离。

    load_project_config 的重叠校验在 doctor 路径被 allow_model_overlap=True 关闭,
    导致 writer/jury 完全同池的配置(自评风险)能过 doctor。此处独立结构化校验:
    ① writer 池与 jury 池不能完全相同(完全同池=裁判可能全是参赛者);
    ② writer 池大小 >= draft_count(schema CHECK 已挡,此处冗余校验给清晰报错);
    ③ jury 池大小 >= max(jury_model_pool_min, 5) — 生产要求 jury>=5 防 3 人小评审团。
    """
    row = conn.execute(
        """
        SELECT writer_model_pool, jury_model_pool, draft_count, jury_model_pool_min
        FROM writing_projects WHERE project_id = ?
        """,
        (project_id,),
    ).fetchone()
    if row is None:
        return ReadinessCheck("model_pool_separation", False, True, "project not found")
    writer_pool, jury_pool, draft_count, jury_min = row
    draft_count = int(draft_count)
    jury_min = int(jury_min)
    try:
        writer_models = [str(m) for m in json.loads(writer_pool)]
        jury_models = [str(m) for m in json.loads(jury_pool)]
    except (json.JSONDecodeError, TypeError) as exc:
        return ReadinessCheck("model_pool_separation", False, True, f"pool JSON invalid: {exc}")

    problems: list[str] = []
    if set(writer_models) == set(jury_models):
        problems.append(
            f"writer/jury pools identical ({len(writer_models)} models) — judges may self-evaluate"
        )
    if len(writer_models) < draft_count:
        problems.append(f"writer pool {len(writer_models)} < draft_count {draft_count}")
    jury_floor = max(jury_min, 5)
    if len(jury_models) < jury_floor:
        problems.append(f"jury pool {len(jury_models)} < production floor {jury_floor}")
    passed = not problems
    detail = "ok" if passed else "; ".join(problems)
    return ReadinessCheck("model_pool_separation", passed, True, detail)


def backup_sqlite_database(
    source: str | Path,
    destination: str | Path,
) -> dict[str, object]:
    source_path = Path(source).resolve()
    destination_path = Path(destination).resolve()
    if source_path == destination_path:
        raise ValueError("backup destination must differ from source database")
    if not source_path.is_file():
        raise FileNotFoundError(source_path)
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    if destination_path.exists():
        raise FileExistsError(destination_path)
    source_conn = sqlite3.connect(source_path)
    destination_conn = sqlite3.connect(destination_path)
    try:
        source_conn.backup(destination_conn)
        integrity = str(destination_conn.execute("PRAGMA integrity_check").fetchone()[0])
        if integrity != "ok":
            raise RuntimeError(f"backup integrity check failed: {integrity}")
    except Exception:
        destination_conn.close()
        source_conn.close()
        destination_path.unlink(missing_ok=True)
        raise
    else:
        destination_conn.close()
        source_conn.close()
    return {
        "source": str(source_path),
        "destination": str(destination_path),
        "size_bytes": destination_path.stat().st_size,
        "integrity_check": "ok",
    }


def _project_stats(conn: sqlite3.Connection, project_id: int) -> dict[str, object]:
    chapters = int(
        conn.execute(
            "SELECT count(DISTINCT chapter_id) FROM writing_shots WHERE project_id = ?",
            (project_id,),
        ).fetchone()[0]
    )
    accepted = int(
        conn.execute(
            """
            SELECT count(DISTINCT chapter_id) FROM writing_chapter_reviews
            WHERE project_id = ? AND status = 'accepted' AND quality_gate_passed = 1
            """,
            (project_id,),
        ).fetchone()[0]
    )
    soft_sealed = int(
        conn.execute(
            "SELECT count(*) FROM writing_shots WHERE project_id = ? AND status = 'soft_sealed'",
            (project_id,),
        ).fetchone()[0]
    )
    hard_sealed = int(
        conn.execute(
            "SELECT count(*) FROM writing_shots WHERE project_id = ? AND status = 'hard_sealed'",
            (project_id,),
        ).fetchone()[0]
    )
    return {
        "planned_chapters_with_shots": chapters,
        "accepted_chapters": accepted,
        "soft_sealed_shots": soft_sealed,
        "hard_sealed_shots": hard_sealed,
    }


def _result(
    project_id: int,
    checks: list[ReadinessCheck],
    stats: dict[str, object],
) -> dict[str, object]:
    blocking_failures = [
        check.name for check in checks if check.blocking and not check.passed
    ]
    return {
        "project_id": project_id,
        "ready_for_personal_production": not blocking_failures,
        "blocking_failures": blocking_failures,
        "checks": [asdict(check) for check in checks],
        "stats": stats,
    }
