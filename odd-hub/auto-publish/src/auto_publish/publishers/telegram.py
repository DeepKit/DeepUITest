"""Telegram publisher"""
from __future__ import annotations
import os
import httpx
from ..generate import PublishContent


def publish(content: PublishContent) -> str:
    """Send message to Telegram channel. Returns message link."""
    token = os.environ["TELEGRAM_BOT_TOKEN"]
    chat_id = os.environ["TELEGRAM_CHAT_ID"]
    text = f"*odd-core v{content.version}*\n\n{content.short_en}\n\n🇨🇳 {content.short_zh}"
    r = httpx.post(
        f"https://api.telegram.org/bot{token}/sendMessage",
        json={
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "Markdown",
            "disable_web_page_preview": False,
        },
        timeout=30,
    )
    r.raise_for_status()
    msg = r.json()["result"]
    channel = chat_id.lstrip("@")
    return f"https://t.me/{channel}/{msg['message_id']}"
