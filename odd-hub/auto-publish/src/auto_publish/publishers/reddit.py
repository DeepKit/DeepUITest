"""Reddit publisher"""
from __future__ import annotations
import os
import httpx
from ..generate import PublishContent

_TOKEN_URL = "https://www.reddit.com/api/v1/access_token"
_SUBMIT_URL = "https://oauth.reddit.com/api/submit"


def _get_token() -> str:
    client_id = os.environ["REDDIT_CLIENT_ID"]
    client_secret = os.environ["REDDIT_CLIENT_SECRET"]
    username = os.environ["REDDIT_USERNAME"]
    password = os.environ["REDDIT_PASSWORD"]
    r = httpx.post(
        _TOKEN_URL,
        auth=(client_id, client_secret),
        data={"grant_type": "password", "username": username, "password": password},
        headers={"User-Agent": "odd-auto-publish/1.0"},
    )
    r.raise_for_status()
    return r.json()["access_token"]


def publish(content: PublishContent) -> str:
    """Submit a text post to Reddit. Returns post URL."""
    subreddit = os.environ.get("REDDIT_SUBREDDIT", "Python")
    token = _get_token()
    r = httpx.post(
        _SUBMIT_URL,
        data={
            "sr": subreddit,
            "kind": "self",
            "title": content.title_en,
            "text": content.body_en,
            "api_type": "json",
        },
        headers={
            "Authorization": f"bearer {token}",
            "User-Agent": "odd-auto-publish/1.0",
        },
    )
    r.raise_for_status()
    j = r.json()
    return j["json"]["data"]["url"]
