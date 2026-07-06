from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Sequence

from ink.database import connect
from ink.threshold_replay import append_jsonl_record, build_threshold_replay_record


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ink-replay-thresholds")
    parser.add_argument("--db", required=True, help="SQLite database path to replay")
    parser.add_argument("--output", default="threshold-replay-records.jsonl", help="JSONL output path")
    parser.add_argument("--project-id", type=int)
    parser.add_argument("--shot-quality-floor", type=int)
    parser.add_argument("--dimension-floor", type=int)
    parser.add_argument("--chapter-quality-floor", type=int)
    parser.add_argument("--book-quality-floor", type=int)
    parser.add_argument("--reader-pull-floor", type=int)
    parser.add_argument("--blind-review-min-passes", type=int)
    parser.add_argument("--soft-gate-redo-n", type=int)
    parser.add_argument("--soft-gate-fail-n", type=int)
    args = parser.parse_args(argv)

    conn = connect(Path(args.db))
    try:
        record = build_threshold_replay_record(
            conn,
            project_id=args.project_id,
            shot_quality_floor=args.shot_quality_floor,
            dimension_floor=args.dimension_floor,
            chapter_quality_floor=args.chapter_quality_floor,
            book_quality_floor=args.book_quality_floor,
            reader_pull_floor=args.reader_pull_floor,
            blind_review_min_passes=args.blind_review_min_passes,
            soft_gate_redo_n=args.soft_gate_redo_n,
            soft_gate_fail_n=args.soft_gate_fail_n,
        )
    finally:
        conn.close()

    append_jsonl_record(args.output, record)
    print(json.dumps(record, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
