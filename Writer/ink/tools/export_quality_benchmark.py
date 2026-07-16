"""Export latest passing chapter runs and a machine-readable quality report."""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ink.core.prose_integrity import find_generation_artifact  # noqa: E402


SCORE_NAMES = (
    "chapter_continuity_hard",
    "pov_consistency",
    "character_consistency",
    "chapter_hook_soft",
    "rhythm_curve",
    "motif_density",
    "info_gap_lifecycle",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--chapter-from", type=int, required=True)
    parser.add_argument("--chapter-to", type=int, required=True)
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    chapters = []
    markdown = ["# InkFlow 真实模型质量 benchmark\n\n"]
    for chapter_id in range(args.chapter_from, args.chapter_to + 1):
        review = conn.execute(
            f"""
            SELECT review_id, run_id, quality_gate_passed, blocking_issues,
                   {", ".join(SCORE_NAMES)}, review_notes
            FROM writing_chapter_reviews
            WHERE chapter_id=? AND quality_gate_passed=1
            ORDER BY run_id DESC, review_id DESC
            LIMIT 1
            """,
            (chapter_id,),
        ).fetchone()
        if review is None:
            raise RuntimeError(f"chapter {chapter_id} has no passing review")
        run_id = int(review[1])
        shot_rows = conn.execute(
            """
            SELECT s.shot_id, v.text
            FROM writing_shots s
            JOIN v_current_text v ON v.shot_id=s.shot_id
            WHERE s.chapter_id=? AND s.run_id=?
            ORDER BY s.shot_id
            """,
            (chapter_id, run_id),
        ).fetchall()
        if not shot_rows:
            raise RuntimeError(f"chapter {chapter_id}/{run_id} has no current prose")
        texts = [str(row[1]) for row in shot_rows]
        artifacts = [
            {"shot_id": row[0], "artifact": artifact}
            for row in shot_rows
            if (artifact := find_generation_artifact(str(row[1]))) is not None
        ]
        if artifacts:
            raise RuntimeError(f"chapter {chapter_id} contains publication artifacts: {artifacts}")
        scores = dict(zip(SCORE_NAMES, (int(value) for value in review[4:11])))
        ethics = conn.execute(
            """
            SELECT ethics_review_id, reviewer_actor, reviewer_models_json,
                   responsibility_question, affected_parties_json, irreversible_harm,
                   agency_obscured, evidence_sentences_json, risk_level, recommendation
            FROM writing_chapter_ethics_reviews
            WHERE chapter_id=? AND run_id=?
            """,
            (chapter_id, run_id),
        ).fetchone()
        if ethics is None:
            raise RuntimeError(f"chapter {chapter_id}/{run_id} has no ethics review")
        if str(ethics[9]) != "approve" or str(ethics[8]) == "blocking":
            raise RuntimeError(
                f"chapter {chapter_id}/{run_id} ethics gate failed: "
                f"risk={ethics[8]} recommendation={ethics[9]}"
            )
        chapters.append(
            {
                "chapter_id": chapter_id,
                "run_id": run_id,
                "review_id": int(review[0]),
                "quality_gate_passed": bool(review[2]),
                "blocking_issues": json.loads(review[3]),
                "scores": scores,
                "shot_ids": [str(row[0]) for row in shot_rows],
                "character_count": sum(len(text) for text in texts),
                "review_notes": str(review[11]),
                "ethics_review": {
                    "ethics_review_id": int(ethics[0]),
                    "reviewer_actor": str(ethics[1]),
                    "reviewer_models": json.loads(ethics[2]),
                    "responsibility_question": str(ethics[3]),
                    "affected_parties": json.loads(ethics[4]),
                    "irreversible_harm": str(ethics[5]),
                    "agency_obscured": bool(ethics[6]),
                    "evidence_sentences": json.loads(ethics[7]),
                    "risk_level": str(ethics[8]),
                    "recommendation": str(ethics[9]),
                },
            }
        )
        markdown.append(f"## 第 {chapter_id} 章（run {run_id}）\n\n")
        markdown.append("\n\n".join(texts))
        markdown.append("\n\n")

    attempts = [
        {
            "call_type": row[0],
            "model_name": row[1],
            "count": int(row[2]),
            "successes": int(row[3]),
            "avg_latency_ms": float(row[4] or 0),
            "token_input": int(row[5] or 0),
            "token_output": int(row[6] or 0),
        }
        for row in conn.execute(
            """
            SELECT call_type, model_name, count(*), sum(success), avg(latency_ms),
                   sum(coalesce(token_input,0)), sum(coalesce(token_output,0))
            FROM writing_ai_call_attempts
            GROUP BY call_type, model_name
            ORDER BY call_type, model_name
            """
        )
    ]
    selected_shot_ids = [shot_id for item in chapters for shot_id in item["shot_ids"]]
    placeholders = ",".join("?" for _ in selected_shot_ids)
    synthetic_attempts = []
    if selected_shot_ids:
        synthetic_attempts = [
            {
                "shot_id": row[0],
                "call_type": row[1],
                "provider": row[2],
                "model_name": row[3],
            }
            for row in conn.execute(
                f"""
                SELECT shot_id, call_type, model_provider, model_name
                FROM writing_ai_call_attempts
                WHERE shot_id IN ({placeholders})
                  AND lower(model_provider) IN ('mock','deterministic')
                ORDER BY attempt_id
                """,
                selected_shot_ids,
            )
        ]
    if synthetic_attempts:
        raise RuntimeError(
            f"latest passing benchmark runs contain synthetic provider attempts: {synthetic_attempts}"
        )
    report = {
        "db": str(args.db),
        "chapter_range": [args.chapter_from, args.chapter_to],
        "chapter_count": len(chapters),
        "passed_count": sum(item["quality_gate_passed"] for item in chapters),
        "mock_used_for_latest_runs": False,
        "chapters": chapters,
        "attempt_summary": attempts,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("".join(markdown), encoding="utf-8")
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
