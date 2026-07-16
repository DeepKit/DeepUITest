"""Targeted, audited real-model POV repair for an already soft-sealed shot."""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ink.core.llm_gateway import LLMGateway, OpenAICompatibleProvider  # noqa: E402
from ink.core.prose_integrity import extract_polished_prose, find_generation_artifact  # noqa: E402
from ink.core.text_repository import TextRepository  # noqa: E402


LOCAL_PROXY_BASE = "http://127.0.0.1:8000/v1"


def _load_proxy_key() -> str:
    configured = os.environ.get("LOCAL_PROXY_KEY")
    if configured:
        return configured
    script = (ROOT / "tools" / "run_baideng_local_proxy.py").read_text(encoding="utf-8")
    marker = 'LOCAL_PROXY_KEY = "'
    start = script.index(marker) + len(marker)
    return script[start : script.index('"', start)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--shot-id", required=True)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--expected-pov", required=True)
    parser.add_argument("--issue", required=True)
    args = parser.parse_args()

    key = _load_proxy_key()
    os.environ["LOCAL_PROXY_KEY"] = key
    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA foreign_keys=ON")
    row = conn.execute(
        """
        SELECT s.project_id, v.revision_id, v.text
        FROM writing_shots s
        JOIN v_current_text v ON v.shot_id=s.shot_id
        WHERE s.shot_id=? AND s.run_id=?
        """,
        (args.shot_id, args.run_id),
    ).fetchone()
    if row is None:
        raise RuntimeError(f"shot/current text not found: {args.shot_id}/{args.run_id}")
    project_id, source_revision_id, source_text = int(row[0]), int(row[1]), str(row[2])
    idem = f"polish:pov-repair:{args.shot_id}:{args.run_id}:{source_revision_id}"
    conn.execute("DELETE FROM writing_ai_call_attempts WHERE idempotency_key=?", (idem,))

    prompt = (
        "你是出版级小说责任编辑。对下方完整正文做一次最小范围 POV 修复。\n"
        f"硬锁 POV：{args.expected_pov}。\n"
        f"已确认问题：{args.issue}\n"
        "只改造成该问题的句子；保留所有事件、事实、物件、段落顺序、节奏、留白、人物声线和章末钩子。"
        "不得新增解释，不得把隐约感受改成作者结论。只输出修复后的完整小说正文，禁止任何说明、"
        "标题、问候、markdown 围栏或修改清单。\n\n"
        f"{source_text}"
    )
    provider = OpenAICompatibleProvider(
        base_url=LOCAL_PROXY_BASE,
        api_key=key,
        max_retries=3,
        retry_base_delay=1.0,
    )
    result = LLMGateway(conn, provider=provider, provider_name="local_proxy").call(
        project_id=project_id,
        shot_id=args.shot_id,
        run_id=args.run_id,
        call_type="polish",
        prompt_id=None,
        prompt_text=prompt,
        model_name="smart-polish",
        idempotency_key=idem,
    )
    repaired = extract_polished_prose(result.text)
    artifact = find_generation_artifact(repaired)
    if artifact:
        raise RuntimeError(f"repaired prose still contains generation artifact: {artifact}")
    ratio = len(repaired) / max(1, len(source_text))
    if ratio < 0.75 or ratio > 1.25:
        raise RuntimeError(f"targeted repair changed text length too much: ratio={ratio:.3f}")
    revision_id = TextRepository(conn).write_revision(
        args.shot_id,
        args.run_id,
        repaired,
        source_revision_id=source_revision_id,
        seal="shot_soft",
    )
    conn.commit()
    print(
        json.dumps(
            {
                "shot_id": args.shot_id,
                "run_id": args.run_id,
                "source_revision_id": source_revision_id,
                "revision_id": revision_id,
                "model": result.model_name,
                "length_before": len(source_text),
                "length_after": len(repaired),
                "mock_used": False,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
