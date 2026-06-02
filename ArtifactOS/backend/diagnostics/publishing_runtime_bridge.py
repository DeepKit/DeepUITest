#!/usr/bin/env python
"""ArtifactOS PublishingRuntime bridge.

Owns ArtifactOS-side routing for persistent platform-account browser sessions.
media_publish still executes browser automation; this bridge ensures session keys are
(platform_id, account_id), never account-only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ.get("MEDIA_PUBLISH_ROOT", "D:/_Progs/.BetterCiv/tools/media_publish")).resolve()
RUNTIME_ROOT = Path(os.environ.get("MEDIA_PUBLISH_RUNTIME_ROOT", ROOT / ".media_publish")).resolve()
PYTHON = sys.executable

PLATFORM_HOME = {
    "zhihu": "https://www.zhihu.com/",
    "wechat": "https://mp.weixin.qq.com/",
    "xiaohongshu": "https://www.xiaohongshu.com/",
    "weibo": "https://weibo.com/",
}


def session_id(platform_id: str, account_id: str) -> str:
    platform = _safe_segment(platform_id)
    account = _safe_segment(account_id)
    return f"{platform}__{account}"


def _safe_segment(value: str) -> str:
    value = value.strip().lower()
    if not re.fullmatch(r"[a-z0-9_.-]+", value):
        raise ValueError(f"invalid session segment: {value!r}")
    return value


def run_media_publish(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [PYTHON, "-m", "media_publish.cli", *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )


def start_browser(platform_id: str, account_id: str) -> dict:
    sid = session_id(platform_id, account_id)
    result = run_media_publish([
        "start-account-browser",
        "--root", str(RUNTIME_ROOT),
        "--account", sid,
    ])
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    record = _parse_kv(result.stdout)
    record.update({
        "platform_id": platform_id,
        "artifactos_account_id": account_id,
        "session_id": sid,
        "home_url": PLATFORM_HOME.get(platform_id, ""),
    })
    return record


def check_account(platform_id: str, account_id: str) -> dict:
    sid = session_id(platform_id, account_id)
    result = run_media_publish([
        "check-account",
        "--root", str(RUNTIME_ROOT),
        "--account", sid,
    ])
    return {
        "platform_id": platform_id,
        "account_id": account_id,
        "session_id": sid,
        "ok": result.returncode == 0,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }


def publish_article(platform_id: str, account_id: str, file_path: str, mode: str = "publish") -> dict:
    if platform_id != "zhihu":
        raise ValueError("publish_article currently supports zhihu only through media_publish")
    sid = session_id(platform_id, account_id)
    result = run_media_publish([
        "publish-article",
        "--root", str(RUNTIME_ROOT),
        "--account", sid,
        "--file", file_path,
        "--mode", mode,
    ])
    payload = {
        "platform_id": platform_id,
        "account_id": account_id,
        "session_id": sid,
        "ok": result.returncode == 0,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }
    for line in result.stdout.splitlines():
        if line.startswith("task_id="):
            payload["task_id"] = int(line.split("=", 1)[1])
    return payload


def show_task(task_id: int) -> dict:
    result = run_media_publish([
        "show-task",
        "--root", str(RUNTIME_ROOT),
        "--task-id", str(task_id),
    ])
    payload = _parse_kv(result.stdout)
    events = [line for line in result.stdout.splitlines() if line.startswith("event=")]
    return {"ok": result.returncode == 0, "task": payload, "events": events, "stderr": result.stderr.strip()}


def session_status(platform_id: str, account_id: str) -> dict:
    sid = session_id(platform_id, account_id)
    session_file = RUNTIME_ROOT / "browser_sessions" / f"{sid}.json"
    profile_dir = RUNTIME_ROOT / "profiles" / sid
    if not session_file.exists():
        return {
            "platform_id": platform_id,
            "account_id": account_id,
            "session_id": sid,
            "state": "offline",
            "profile_dir": str(profile_dir),
        }
    try:
        record = json.loads(session_file.read_text(encoding="utf-8"))
        state = "started"
    except json.JSONDecodeError:
        record = {}
        state = "corrupt_session_record"
    return {
        "platform_id": platform_id,
        "account_id": account_id,
        "session_id": sid,
        "state": state,
        "profile_dir": str(profile_dir),
        **record,
    }


def _parse_kv(text: str) -> dict:
    record = {}
    for line in text.splitlines():
        if "=" in line and not line.startswith("event="):
            k, v = line.split("=", 1)
            record[k.strip()] = v.strip()
    return record


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="publishing-runtime-bridge")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ["start-browser", "check-account", "status"]:
        p = sub.add_parser(name)
        p.add_argument("--platform", required=True)
        p.add_argument("--account", required=True)
    p = sub.add_parser("publish-article")
    p.add_argument("--platform", required=True)
    p.add_argument("--account", required=True)
    p.add_argument("--file", required=True)
    p.add_argument("--mode", default="publish", choices=["publish", "manual-review"])
    p = sub.add_parser("show-task")
    p.add_argument("--task-id", required=True, type=int)

    args = parser.parse_args(argv)
    if args.command == "start-browser":
        print(json.dumps(start_browser(args.platform, args.account), ensure_ascii=False, indent=2))
    elif args.command == "check-account":
        print(json.dumps(check_account(args.platform, args.account), ensure_ascii=False, indent=2))
    elif args.command == "status":
        print(json.dumps(session_status(args.platform, args.account), ensure_ascii=False, indent=2))
    elif args.command == "publish-article":
        print(json.dumps(publish_article(args.platform, args.account, args.file, args.mode), ensure_ascii=False, indent=2))
    elif args.command == "show-task":
        print(json.dumps(show_task(args.task_id), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
