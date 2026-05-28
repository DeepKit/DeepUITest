"""Hashnode publisher"""
from __future__ import annotations
import os
import httpx
from ..generate import PublishContent

_GQL = """
mutation PublishPost($input: PublishPostInput!) {
  publishPost(input: $input) {
    post { url }
  }
}
"""


def publish(content: PublishContent) -> str:
    """Publish article to Hashnode. Returns URL."""
    token = os.environ["HASHNODE_TOKEN"]
    pub_id = os.environ["HASHNODE_PUBLICATION_ID"]
    r = httpx.post(
        "https://gql.hashnode.com",
        json={
            "query": _GQL,
            "variables": {
                "input": {
                    "title": content.title_en,
                    "contentMarkdown": content.body_en,
                    "publicationId": pub_id,
                    "tags": [],
                }
            },
        },
        headers={"Authorization": token},
        timeout=30,
    )
    r.raise_for_status()
    data = r.json()
    if "errors" in data:
        raise RuntimeError(data["errors"])
    return data["data"]["publishPost"]["post"]["url"]
