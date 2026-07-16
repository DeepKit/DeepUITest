"""Validate P0 literary-quality guards against real WiseGateway models.

This script never uses a mock provider.  It copies the current 《白灯法则》
production DB, re-reviews c02/c03 with the new structured POV/continuity and
industrial-mechanism protocol, and performs a real primary→secondary failover
probe by intentionally assigning a nonexistent model to the primary tier.
"""
from __future__ import annotations

import json
import os
import shutil
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ink.core.llm_gateway import LLMGateway  # noqa: E402
from ink.core.model_role_config import upsert_role_config  # noqa: E402
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator  # noqa: E402


SOURCE_DB = Path(r"D:/_Progs/.Story/《白灯法则》/.inkflow/inkflow.db")
OUTPUT_DIR = Path(r"D:/_Progs/.Story/《白灯法则》/.inkflow/p0_real_validation")
VALIDATION_DB = OUTPUT_DIR / "inkflow.db"
REPORT_PATH = OUTPUT_DIR / "report.json"
LOCAL_PROXY_BASE = "http://127.0.0.1:8000/v1"

PRIMARY_REVIEW_MODEL = "claude-xunfei-deepseek-v4-pro"
SECONDARY_REVIEW_MODEL = "claude-xunfei-qwen3-5-397b-a17b"
TERTIARY_REVIEW_MODEL = "claude-xunfei-glm-5-2"
FAILOVER_SECONDARY_MODEL = "claude-xunfei-glm-5-1"


def _load_proxy_key() -> str:
    configured = os.environ.get("LOCAL_PROXY_KEY")
    if configured:
        return configured
    # Reuse the locally provisioned key without duplicating it in a second file.
    script = (ROOT / "tools" / "run_baideng_local_proxy.py").read_text(encoding="utf-8")
    marker = 'LOCAL_PROXY_KEY = "'
    start = script.index(marker) + len(marker)
    return script[start : script.index('"', start)]


def _configure_real_models(conn: sqlite3.Connection, project_id: int) -> None:
    for tier, model in (
        ("primary", PRIMARY_REVIEW_MODEL),
        ("secondary", SECONDARY_REVIEW_MODEL),
        ("tertiary", TERTIARY_REVIEW_MODEL),
    ):
        upsert_role_config(
            conn,
            project_id=project_id,
            call_type="chapter_review",
            tier=tier,
            model_name=model,
            provider="openai-compatible",
            api_key_env="LOCAL_PROXY_KEY",
            base_url=LOCAL_PROXY_BASE,
        )

    for tier, model in (
        ("primary", "__ink_nonexistent_model_for_failover__"),
        ("secondary", FAILOVER_SECONDARY_MODEL),
        ("tertiary", TERTIARY_REVIEW_MODEL),
    ):
        upsert_role_config(
            conn,
            project_id=project_id,
            call_type="book_check",
            tier=tier,
            model_name=model,
            provider="openai-compatible",
            api_key_env="LOCAL_PROXY_KEY",
            base_url=LOCAL_PROXY_BASE,
        )


def _clear_re_review_state(conn: sqlite3.Connection, project_id: int, chapter_id: int, run_id: int) -> None:
    conn.execute(
        "DELETE FROM writing_chapter_reviews WHERE project_id=? AND chapter_id=? AND run_id=?",
        (project_id, chapter_id, run_id),
    )
    for key in (
        f"chapter_review:{project_id}:{chapter_id}:{run_id}",
        f"industrial_fact_drift:{project_id}:{chapter_id}:{run_id}",
    ):
        conn.execute("DELETE FROM writing_ai_call_attempts WHERE idempotency_key=?", (key,))


def _review_evidence(conn: sqlite3.Connection, project_id: int, chapter_id: int, run_id: int) -> dict:
    result = ChapterReviewOrchestrator(conn, LLMGateway(conn)).review_chapter(
        project_id,
        chapter_id,
        run_id,
    )
    row = conn.execute(
        """
        SELECT chapter_continuity_hard, pov_consistency, character_consistency,
               chapter_hook_soft, rhythm_curve, motif_density, info_gap_lifecycle,
               blocking_issues, review_notes
        FROM writing_chapter_reviews
        WHERE review_id=?
        """,
        (result.review_id,),
    ).fetchone()
    attempts = conn.execute(
        """
        SELECT call_type, model_provider, model_name, success, latency_ms,
               token_input, token_output
        FROM writing_ai_call_attempts
        WHERE project_id=? AND run_id=? AND idempotency_key IN (?, ?)
        ORDER BY attempt_id
        """,
        (
            project_id,
            run_id,
            f"chapter_review:{project_id}:{chapter_id}:{run_id}",
            f"industrial_fact_drift:{project_id}:{chapter_id}:{run_id}",
        ),
    ).fetchall()
    return {
        "chapter_id": chapter_id,
        "quality_gate_passed": result.quality_gate_passed,
        "blocking_issues": list(result.blocking_issues),
        "scores": {
            "chapter_continuity_hard": row[0],
            "pov_consistency": row[1],
            "character_consistency": row[2],
            "chapter_hook_soft": row[3],
            "rhythm_curve": row[4],
            "motif_density": row[5],
            "info_gap_lifecycle": row[6],
        },
        "stored_blocking_issues": json.loads(row[7]),
        "review_notes": row[8],
        "real_llm_attempts": [
            {
                "call_type": item[0],
                "provider": item[1],
                "model": item[2],
                "success": bool(item[3]),
                "latency_ms": item[4],
                "token_input": item[5],
                "token_output": item[6],
            }
            for item in attempts
        ],
    }


def _run_failover_probe(conn: sqlite3.Connection, project_id: int) -> dict:
    key = "book_check:p0_failover_probe:real:1"
    conn.execute("DELETE FROM writing_ai_call_attempts WHERE idempotency_key=?", (key,))
    conn.execute(
        "DELETE FROM writing_runtime_events WHERE event_type='model_role_failover'"
    )
    result = LLMGateway(conn).call(
        project_id=project_id,
        shot_id=None,
        run_id=None,
        call_type="book_check",
        prompt_id=None,
        prompt_text='只输出 JSON：{"ok":true,"purpose":"real failover probe"}',
        model_name=None,
        idempotency_key=key,
        tier_hint="primary",
    )
    events = conn.execute(
        """
        SELECT event_type, event_payload
        FROM writing_runtime_events
        WHERE event_type='model_role_failover'
        ORDER BY event_id
        """
    ).fetchall()
    attempt = conn.execute(
        """
        SELECT model_provider, model_name, success, latency_ms
        FROM writing_ai_call_attempts
        WHERE idempotency_key=?
        """,
        (key,),
    ).fetchone()
    return {
        "response": result.text,
        "successful_model": attempt[1] if attempt else result.model_name,
        "attempt_success": bool(attempt[2]) if attempt else True,
        "latency_ms": attempt[3] if attempt else None,
        "failover_events": [
            {"event_type": event_type, "payload": json.loads(payload)}
            for event_type, payload in events
        ],
    }


def main() -> int:
    if not SOURCE_DB.exists():
        raise FileNotFoundError(SOURCE_DB)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE_DB, VALIDATION_DB)
    os.environ["LOCAL_PROXY_KEY"] = _load_proxy_key()

    conn = sqlite3.connect(VALIDATION_DB)
    conn.execute("PRAGMA foreign_keys=ON")
    project = conn.execute(
        "SELECT project_id, code, title FROM writing_projects ORDER BY project_id LIMIT 1"
    ).fetchone()
    if project is None:
        raise RuntimeError("validation DB has no writing project")
    project_id = int(project[0])
    _configure_real_models(conn, project_id)

    evidence = []
    for chapter_id in (2, 3):
        run_row = conn.execute(
            """
            SELECT run_id
            FROM writing_shots
            WHERE project_id=? AND chapter_id=?
            GROUP BY run_id
            ORDER BY run_id DESC
            LIMIT 1
            """,
            (project_id, chapter_id),
        ).fetchone()
        if run_row is None:
            continue
        run_id = int(run_row[0])
        _clear_re_review_state(conn, project_id, chapter_id, run_id)
        evidence.append(_review_evidence(conn, project_id, chapter_id, run_id))
        conn.commit()

    failover = _run_failover_probe(conn, project_id)
    conn.commit()
    report = {
        "source_db": str(SOURCE_DB),
        "validation_db": str(VALIDATION_DB),
        "project": {"project_id": project_id, "code": project[1], "title": project[2]},
        "provider": {"base_url": LOCAL_PROXY_BASE, "mock_used": False},
        "chapter_reviews": evidence,
        "failover_probe": failover,
    }
    REPORT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
