"""Dev.to publisher"""
from __future__ import annotations
import os
import httpx
from ..generate import PublishContent


def publish(content: PublishContent) -> str:
    """Publish article to Dev.to. Returns URL."""
    api_key = os.environ["DEVTO_API_KEY"]
    payload = {
        "article": {
            "title": content.title_en,
            "body_markdown": content.body_en,
            "published": True,
            "tags": ["python", "ai", "devtools", "opensource"],
        }
    }
    r = httpx.post(
        "https://dev.to/api/articles",
        json=payload,
        headers={"api-key": api_key},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()["url"]
