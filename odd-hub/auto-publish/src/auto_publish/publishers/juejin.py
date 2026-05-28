"""掘金 (Juejin) publisher �?Cookie-based auth"""
from __future__ import annotations
import os
import httpx
from ..generate import PublishContent


def publish(content: PublishContent) -> str:
    """Publish article to Juejin. Returns URL."""
    cookie = os.environ["JUEJIN_COOKIE"]
    headers = {
        "Cookie": cookie,
        "User-Agent": "Mozilla/5.0",
        "Content-Type": "application/json",
        "Referer": "https://juejin.cn/",
    }
    # Step 1: create draft
    r = httpx.post(
        "https://api.juejin.cn/content_api/v1/article_draft/create",
        json={
            "title": content.title_zh,
            "brief_content": content.short_zh,
            "edit_type": 10,
            "html_content": "deprecated",
            "mark_content": content.body_zh,
            "category_id": "6809637767543259144",  # 后端
            "tag_ids": ["6809640407484334093"],      # Python
        },
        headers=headers,
        timeout=30,
    )
    r.raise_for_status()
    draft_id = r.json()["data"]["id"]

    # Step 2: publish draft
    r2 = httpx.post(
        "https://api.juejin.cn/content_api/v1/article/publish",
        json={"draft_id": draft_id, "sync_to_org": False, "column_ids": []},
        headers=headers,
        timeout=30,
    )
    r2.raise_for_status()
    article_id = r2.json()["data"]["article_id"]
    return f"https://juejin.cn/post/{article_id}"
