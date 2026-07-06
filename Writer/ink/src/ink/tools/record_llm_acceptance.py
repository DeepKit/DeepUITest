from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Sequence

from ink.database import connect
from ink.manual_acceptance import append_jsonl_record, build_llm_acceptance_record


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ink-record-llm-acceptance")
    parser.add_argument("--db", required=True, help="SQLite database path to summarize")
    parser.add_argument("--output", default="llm-acceptance-records.jsonl", help="JSONL output path")
    parser.add_argument("--project-id", type=int, help="Limit the record to one project")
    parser.add_argument("--price-input-per-1k", type=float, default=0.0)
    parser.add_argument("--price-output-per-1k", type=float, default=0.0)
    parser.add_argument("--sample-limit", type=int, default=3)
    args = parser.parse_args(argv)

    conn = connect(Path(args.db))
    try:
        record = build_llm_acceptance_record(
            conn,
            project_id=args.project_id,
            price_input_per_1k=args.price_input_per_1k,
            price_output_per_1k=args.price_output_per_1k,
            sample_limit=args.sample_limit,
        )
    finally:
        conn.close()

    append_jsonl_record(args.output, record)
    print(json.dumps(record, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
