"""
主入�?�?协调内容生成 + 多平台发�?"""
from __future__ import annotations
import os
import sys
import json
import traceback
from dataclasses import dataclass
from typing import Callable

from .generate import generate, PublishContent
from .publishers import github, devto, hashnode, reddit, telegram, juejin, jike, zhihu


@dataclass
class PublishResult:
    platform: str
    success: bool
    url: str = ""
    error: str = ""


PUBLISHERS: dict[str, tuple[Callable[[PublishContent], str], str]] = {
    "github":   (github.publish,   "GITHUB_TOKEN"),
    "devto":    (devto.publish,    "DEVTO_API_KEY"),
    "hashnode": (hashnode.publish, "HASHNODE_TOKEN"),
    "reddit":   (reddit.publish,   "REDDIT_CLIENT_ID"),
    "telegram": (telegram.publish, "TELEGRAM_BOT_TOKEN"),
    "juejin":   (juejin.publish,   "JUEJIN_COOKIE"),
    "jike":     (jike.publish,     "JIKE_COOKIE"),
    "zhihu":    (zhihu.publish,    "ZHIHU_COOKIE"),
}


def run(tag: str, changelog: str, dry_run: bool = False, platforms: list[str] | None = None) -> list[PublishResult]:
    """Generate content and publish to all configured platforms."""
    if dry_run:
        print(f"[dry-run] Skipping content generation for {tag}")
        return [PublishResult(platform=name, success=True, url="(dry-run)") for name in PUBLISHERS]
    print(f"[auto-publish] Generating content for {tag}...")
    repo_url = os.environ.get("REPO_URL", "https://github.com/odd-hub/odd")
    content = generate(version=tag, changelog=changelog, repo_url=repo_url)
    results: list[PublishResult] = []
    active = {k: v for k, v in PUBLISHERS.items() if platforms is None or k in platforms}
    for name, (fn, required_env) in active.items():
        if not os.environ.get(required_env):
            print(f"[{name}] SKIP �?{required_env} not set")
            continue
        try:
            url = fn(content)
            print(f"[{name}] OK �?{url}")
            results.append(PublishResult(platform=name, success=True, url=url))
        except Exception as e:
            traceback.print_exc()
            print(f"[{name}] FAIL �?{e}", file=sys.stderr)
            results.append(PublishResult(platform=name, success=False, error=str(e)))
    return results


def cli() -> None:
    """CLI entry point. Reads env vars; pass --dry-run to skip publishing."""
    dry_run = "--dry-run" in sys.argv
    tag = os.environ.get("RELEASE_TAG", "")
    changelog = os.environ.get("RELEASE_CHANGELOG", "")
    platforms_raw = os.environ.get("PUBLISH_PLATFORMS", "")
    platforms = [p.strip() for p in platforms_raw.split(",") if p.strip()] or None
    if not tag:
        print("ERROR: RELEASE_TAG env var is required", file=sys.stderr)
        sys.exit(1)

    results = run(tag=tag, changelog=changelog, dry_run=dry_run, platforms=platforms)
    print(json.dumps([r.__dict__ for r in results], indent=2))
    if any(not r.success for r in results):
        sys.exit(1)


# Keep bare `main` as alias for backwards compat
main = cli


if __name__ == "__main__":
    cli()
