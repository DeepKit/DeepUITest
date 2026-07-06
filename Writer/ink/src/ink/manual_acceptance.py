from __future__ import annotations

import json
import math
import sqlite3
from pathlib import Path

from ink.time import now_utc_iso


def build_llm_acceptance_record(
    conn: sqlite3.Connection,
    *,
    project_id: int | None = None,
    price_input_per_1k: float = 0.0,
    price_output_per_1k: float = 0.0,
    sample_limit: int = 3,
) -> dict[str, object]:
    attempts = _load_attempts(conn, project_id)
    total_input = sum(int(row["token_input"] or 0) for row in attempts)
    total_output = sum(int(row["token_output"] or 0) for row in attempts)
    failures = [row for row in attempts if int(row["success"]) == 0]
    latencies = [int(row["latency_ms"]) for row in attempts if row["latency_ms"] is not None]
    return {
        "schema_version": "ink.llm_acceptance.v1",
        "generated_at": now_utc_iso(),
        "project_id": project_id,
        "summary": {
            "attempt_count": len(attempts),
            "success_count": len(attempts) - len(failures),
            "failure_count": len(failures),
            "failure_rate": _ratio(len(failures), len(attempts)),
            "token_input": total_input,
            "token_output": total_output,
            "estimated_cost": round((total_input / 1000 * price_input_per_1k) + (total_output / 1000 * price_output_per_1k), 6),
            "latency_ms_avg": _avg(latencies),
            "latency_ms_p95": _percentile(latencies, 0.95),
        },
        "by_provider_model_call_type": _group_attempts(attempts),
        "quality_samples": _load_quality_samples(conn, project_id, sample_limit),
    }


def append_jsonl_record(path: str | Path, record: dict[str, object]) -> None:
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(record, ensure_ascii=False, sort_keys=True))
        stream.write("\n")


def _load_attempts(conn: sqlite3.Connection, project_id: int | None) -> list[dict[str, object]]:
    where = "" if project_id is None else "WHERE project_id = ?"
    params: tuple[object, ...] = () if project_id is None else (project_id,)
    return _query_dicts(
        conn,
        f"""
        SELECT attempt_id, project_id, call_type, model_provider, model_name,
               token_input, token_output, latency_ms, success, error_category, created_at
        FROM writing_ai_call_attempts
        {where}
        ORDER BY attempt_id
        """,
        params,
    )


def _group_attempts(attempts: list[dict[str, object]]) -> list[dict[str, object]]:
    groups: dict[tuple[str, str, str], dict[str, object]] = {}
    for row in attempts:
        key = (str(row["model_provider"]), str(row["model_name"]), str(row["call_type"]))
        group = groups.setdefault(
            key,
            {
                "model_provider": key[0],
                "model_name": key[1],
                "call_type": key[2],
                "attempt_count": 0,
                "success_count": 0,
                "failure_count": 0,
                "token_input": 0,
                "token_output": 0,
            },
        )
        group["attempt_count"] = int(group["attempt_count"]) + 1
        if int(row["success"]) == 1:
            group["success_count"] = int(group["success_count"]) + 1
        else:
            group["failure_count"] = int(group["failure_count"]) + 1
        group["token_input"] = int(group["token_input"]) + int(row["token_input"] or 0)
        group["token_output"] = int(group["token_output"]) + int(row["token_output"] or 0)
    return [groups[key] for key in sorted(groups)]


def _load_quality_samples(
    conn: sqlite3.Connection,
    project_id: int | None,
    limit: int,
) -> list[dict[str, object]]:
    where = "WHERE decision_type = 'accept'"
    params: tuple[object, ...] = ()
    if project_id is not None:
        where += " AND project_id = ?"
        params = (project_id,)
    rows = _query_dicts(
        conn,
        f"""
        SELECT decision_id, project_id, actor, reason, preconditions_json, quality_report_json, created_at
        FROM writing_human_decisions
        {where}
        ORDER BY decision_id DESC
        LIMIT {max(0, int(limit))}
        """,
        params,
    )
    samples: list[dict[str, object]] = []
    for row in rows:
        quality_report = _json_object(row["quality_report_json"])
        preconditions = _json_object(row["preconditions_json"])
        samples.append(
            {
                "decision_id": int(row["decision_id"]),
                "project_id": int(row["project_id"]),
                "actor": str(row["actor"]),
                "reason": str(row["reason"]),
                "quality_gate_passed": preconditions.get("quality_gate_passed"),
                "evidence_class": quality_report.get("evidence_class"),
                "defect_class": quality_report.get("defect_class"),
                "created_at": str(row["created_at"]),
            }
        )
    return samples


def _query_dicts(conn: sqlite3.Connection, sql: str, params: tuple[object, ...]) -> list[dict[str, object]]:
    cursor = conn.execute(sql, params)
    names = [column[0] for column in cursor.description]
    return [dict(zip(names, row, strict=True)) for row in cursor.fetchall()]


def _json_object(value: object) -> dict[str, object]:
    if not isinstance(value, str) or not value:
        return {}
    payload = json.loads(value)
    return payload if isinstance(payload, dict) else {}


def _ratio(numerator: int, denominator: int) -> float:
    if denominator == 0:
        return 0.0
    return round(numerator / denominator, 4)


def _avg(values: list[int]) -> int | None:
    if not values:
        return None
    return int(sum(values) / len(values))


def _percentile(values: list[int], percentile: float) -> int | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, math.ceil(len(ordered) * percentile) - 1)
    return ordered[index]
