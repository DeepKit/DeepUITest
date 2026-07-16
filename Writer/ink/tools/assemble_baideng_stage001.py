"""Assemble the real, already-produced STAGE-001 draft without regenerating prose.

Sources remain immutable.  The output is a derived review artifact with per-source hashes
and provenance:
  prologue + author chapter 1 + prior Ink chapter 2 export + selected real benchmark 3-10.
"""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
from datetime import datetime
from pathlib import Path


ROOT = Path(r"D:/_Progs/.Story/《白灯法则》")
PROLOGUE = ROOT / "正文" / "序章_白灯.md"
CHAPTER_1 = ROOT / "正文" / "卷一" / "第01章_第十七批.md"
CHAPTER_2_DB = ROOT / ".inkflow" / "stage001" / "c02-rebuild" / "inkflow.db"
BENCHMARK = ROOT / ".inkflow" / "benchmark-c03-c10" / "final_ch03-10.md"
BENCHMARK_REPORT = ROOT / ".inkflow" / "benchmark-c03-c10" / "final_report.json"
OUTPUT_DIR = ROOT / ".inkflow" / "stage001"
OUTPUT = OUTPUT_DIR / "stage001_initial_draft.md"
MANIFEST = OUTPUT_DIR / "stage001_manifest.json"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_chapter_2() -> tuple[str, dict[str, object]]:
    conn = sqlite3.connect(f"file:{CHAPTER_2_DB.as_posix()}?mode=ro", uri=True)
    try:
        row = conn.execute(
            """
            SELECT revision_id,text FROM v_current_text
            WHERE shot_id='ch-02-shot-001@200' AND run_id=200
            """
        ).fetchone()
        review = conn.execute(
            """
            SELECT quality_gate_passed,blocking_issues FROM writing_chapter_reviews
            WHERE project_id=1 AND chapter_id=2 AND run_id=200
            ORDER BY review_id DESC LIMIT 1
            """
        ).fetchone()
        ethics = conn.execute(
            """
            SELECT risk_level,recommendation FROM writing_chapter_ethics_reviews
            WHERE project_id=1 AND chapter_id=2 AND run_id=200
            """
        ).fetchone()
    finally:
        conn.close()
    if row is None or review is None or ethics is None:
        raise RuntimeError("chapter 2 rebuilt DB is incomplete")
    if not review[0] or json.loads(review[1] or "[]"):
        raise RuntimeError("chapter 2 quality gate did not pass")
    if ethics[1] != "approve":
        raise RuntimeError("chapter 2 ethics review did not approve")
    text = "# 第02章：装车\n\n" + str(row[1]).strip()
    return text, {
        "db": str(CHAPTER_2_DB),
        "revision_id": int(row[0]),
        "quality_gate_passed": True,
        "ethics_risk_level": str(ethics[0]),
        "ethics_recommendation": str(ethics[1]),
        "mock_used": False,
    }


def normalize_benchmark(text: str) -> str:
    text = text.replace("\r\n", "\n")
    text = re.sub(r"\A# InkFlow 真实模型质量 benchmark\s*\n+", "", text)
    text = re.sub(
        r"^## 第\s+(\d+)\s+章（run\s+\d+）\s*$",
        lambda match: f"# 第{int(match.group(1)):02d}章",
        text,
        flags=re.MULTILINE,
    )
    return text.strip()


def main() -> int:
    chapter_2_text, chapter_2_lineage = load_chapter_2()
    sources = [
        ("prologue", PROLOGUE, PROLOGUE.read_text(encoding="utf-8").strip()),
        ("chapter_01", CHAPTER_1, CHAPTER_1.read_text(encoding="utf-8").strip()),
        ("chapter_02", CHAPTER_2_DB, chapter_2_text),
        (
            "chapters_03_10",
            BENCHMARK,
            normalize_benchmark(BENCHMARK.read_text(encoding="utf-8")),
        ),
    ]
    report = json.loads(BENCHMARK_REPORT.read_text(encoding="utf-8"))
    if report.get("mock_used_for_latest_runs") is not False:
        raise RuntimeError("benchmark selection is not real-model clean")
    if report.get("passed_count") != report.get("chapter_count"):
        raise RuntimeError("benchmark does not have all selected chapters passing")

    parts = [
        "# 《白灯法则》STAGE-001 初稿\n",
        "> 范围：序章、卷一、卷二、时间桥（当前正文至第10章）  \n",
        "> 状态：Ink生产阶段派生评审稿；不是作者最终接受稿。  \n",
        "> 来源：真实既有正文与真实模型benchmark；未重新生成、未使用mock。\n",
    ]
    records = []
    for kind, path, normalized in sources:
        parts.extend(["\n\n", normalized, "\n"])
        raw = path.read_bytes()
        records.append(
            {
                "kind": kind,
                "path": str(path),
                "source_sha256": sha256_bytes(raw),
                "normalized_text_sha256": sha256_bytes(normalized.encode("utf-8")),
                "characters": len(normalized),
                "lineage": chapter_2_lineage if kind == "chapter_02" else None,
            }
        )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_text = "".join(parts).strip() + "\n"
    OUTPUT.write_text(output_text, encoding="utf-8")
    manifest = {
        "schema_version": "1.0",
        "project": "白灯法则",
        "stage_id": "STAGE-001",
        "status": "initial_draft_assembled",
        "output": str(OUTPUT),
        "output_sha256": sha256_bytes(OUTPUT.read_bytes()),
        "character_count": len(output_text),
        "source_records": records,
        "benchmark_report": str(BENCHMARK_REPORT),
        "benchmark_selected_runs": {
            str(item["chapter_id"]): int(item["run_id"])
            for item in report["chapters"]
        },
        "mock_used": False,
        "author_acceptance": False,
        "assembled_at": datetime.now().isoformat(timespec="seconds"),
    }
    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
