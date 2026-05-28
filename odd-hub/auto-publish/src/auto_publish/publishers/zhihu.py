"""知乎 (Zhihu) publisher �?Cookie-based auth"""
from __future__ import annotations
import os
import httpx
from ..generate import PublishContent


def publish(content: PublishContent) -> str:
    """Publish article to Zhihu. Returns URL."""
    cookie = os.environ["ZHIHU_COOKIE"]
    headers = {
        "Cookie": cookie,
        "User-Agent": "Mozilla/5.0",
        "Content-Type": "application/json",
        "Origin": "https://zhuanlan.zhihu.com",
        "Referer": "https://zhuanlan.zhihu.com/",
        "x-zse-93": "101_3_3.0",
    }
    # Step 1: create draft
    r = httpx.post(
        "https://zhuanlan.zhihu.com/api/articles/drafts",
        json={
            "title": content.title_zh,
            "delta_time": 0,
        },
        headers=headers,
        timeout=30,
    )
    r.raise_for_status()
    draft_id = r.json()["id"]

    # Step 2: update content
    r2 = httpx.patch(
        f"https://zhuanlan.zhihu.com/api/articles/{draft_id}/draft",
        json={
            "title": content.title_zh,
            "content": f"<p>{content.body_zh}</p>",
        },
        headers=headers,
        timeout=30,
    )
    r2.raise_for_status()

    # Step 3: publish
    r3 = httpx.put(
        f"https://zhuanlan.zhihu.com/api/articles/{draft_id}/publish",
        json={"disclaimer_status": "close"},
        headers=headers,
        timeout=30,
    )
    r3.raise_for_status()
    return f"https://zhuanlan.zhihu.com/p/{draft_id}"
