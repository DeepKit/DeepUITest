"""即刻 (Jike) publisher �?Cookie-based auth"""
from __future__ import annotations
import os
import httpx
from ..generate import PublishContent


def publish(content: PublishContent) -> str:
    """Post to Jike. Returns post URL."""
    cookie = os.environ["JIKE_COOKIE"]
    headers = {
        "Cookie": cookie,
        "User-Agent": "Mozilla/5.0",
        "Content-Type": "application/json",
        "Origin": "https://web.okjike.com",
        "Referer": "https://web.okjike.com/",
    }
    text = f"{content.title_zh}\n\n{content.short_zh}\n\n#ODD #AI编程 #开发工�?
    r = httpx.post(
        "https://api.ruguoapp.com/1.0/originalPost/create",
        json={"content": text, "pictureKeys": [], "topicId": None},
        headers=headers,
        timeout=30,
    )
    r.raise_for_status()
    post_id = r.json()["data"]["id"]
    return f"https://web.okjike.com/originalPost/{post_id}"
