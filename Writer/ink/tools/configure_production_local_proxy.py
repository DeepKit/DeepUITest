"""Configure an Ink production DB to use the local WiseGateway real-model pool."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ink.core.model_role_config import upsert_role_config  # noqa: E402


DEFAULT_DB = Path(r"D:/_Progs/.Story/《白灯法则》/.inkflow/inkflow.db")
LOCAL_PROXY_BASE = "http://127.0.0.1:8000/v1"
MODEL_ALIASES = {
    "xopglm51": "claude-xunfei-glm-5-2",
    "xopdeepseekv4pro": "claude-xunfei-deepseek-v4-pro",
    "xopkimik26": "claude-xunfei-kimi-k2-6",
    "xopqwen36v35b": "claude-xunfei-qwen3-6-35b-a3b",
    "xopqwen35397b": "claude-xunfei-qwen3-5-397b-a17b",
    "smart-polish": "claude-fccy-gpt-5-6-sol",
}
REVIEW_CHAIN = (
    ("primary", "claude-xunfei-deepseek-v4-pro"),
    ("secondary", "claude-xunfei-qwen3-5-397b-a17b"),
    ("tertiary", "claude-xunfei-glm-5-2"),
)


def configure(db_path: Path, project_id: int, *, backup: bool = True) -> Path | None:
    backup_path: Path | None = None
    if backup:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_path = db_path.with_name(f"{db_path.stem}.before-local-proxy-{stamp}{db_path.suffix}")
        shutil.copy2(db_path, backup_path)

    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys=ON")
    row = conn.execute(
        "SELECT model_aliases FROM writing_projects WHERE project_id=?",
        (project_id,),
    ).fetchone()
    if row is None:
        raise RuntimeError(f"project not found: {project_id}")
    existing = json.loads(row[0]) if row[0] else {}
    existing.update(MODEL_ALIASES)
    conn.execute(
        "UPDATE writing_projects SET model_aliases=? WHERE project_id=?",
        (json.dumps(existing, ensure_ascii=False, sort_keys=True), project_id),
    )
    for call_type in ("chapter_review", "book_check"):
        for tier, model in REVIEW_CHAIN:
            upsert_role_config(
                conn,
                project_id=project_id,
                call_type=call_type,
                tier=tier,
                model_name=model,
                provider="openai-compatible",
                api_key_env="LOCAL_PROXY_KEY",
                base_url=LOCAL_PROXY_BASE,
            )
    conn.commit()
    conn.close()
    return backup_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--project-id", type=int, default=1)
    parser.add_argument("--no-backup", action="store_true")
    args = parser.parse_args()
    if not args.db.exists():
        raise FileNotFoundError(args.db)
    backup_path = configure(args.db, args.project_id, backup=not args.no_backup)
    print(
        json.dumps(
            {
                "db": str(args.db),
                "project_id": args.project_id,
                "backup": str(backup_path) if backup_path else None,
                "base_url": LOCAL_PROXY_BASE,
                "model_aliases": MODEL_ALIASES,
                "mock_used": False,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
