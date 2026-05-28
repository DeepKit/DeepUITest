"""GitHub Release publisher"""
from __future__ import annotations
import os
import httpx
from ..generate import PublishContent


def publish(content: PublishContent) -> str:
    """Create a GitHub Release. Reads repo from GITHUB_REPOSITORY env var."""
    token = os.environ["GITHUB_TOKEN"]
    repo = os.environ["GITHUB_REPOSITORY"]  # e.g. 'owner/odd-core'
    url = f"https://api.github.com/repos/{repo}/releases"
    payload = {
        "tag_name": f"v{content.version}",
        "name": f"v{content.version} â€?{content.title_en}",
        "body": content.body_en,
        "draft": False,
        "prerelease": False,
    }
    r = httpx.post(url, json=payload,
                   headers={"Authorization": f"Bearer {token}",
                            "Accept": "application/vnd.github+json"})
    r.raise_for_status()
    return r.json()["html_url"]
