"""Unit tests for generate.py"""
from __future__ import annotations
from unittest.mock import MagicMock, patch
from auto_publish.generate import generate, PublishContent


def _mock_openai(responses: list[str]):
    """Return a patched OpenAI client that yields responses in order."""
    client = MagicMock()
    side_effects = []
    for text in responses:
        msg = MagicMock()
        msg.choices[0].message.content = text
        side_effects.append(msg)
    client.chat.completions.create.side_effect = side_effects
    return client


@patch("auto_publish.generate.OpenAI")
def test_generate_returns_publish_content(mock_cls):
    mock_cls.return_value = _mock_openai([
        "ODD v1.0.0 is out!",          # body_en
        "Short EN summary",             # short_en
        "ODD v1.0.0 发布了！",           # body_zh
        "简短中文摘�?,                   # short_zh
    ])

    result = generate(
        version="v1.0.0",
        changelog="- Initial release",
        repo_url="https://github.com/odd-hub/odd",
    )

    assert isinstance(result, PublishContent)
    assert result.version == "v1.0.0"
    assert result.title_en == "ODD v1.0.0 is out!"
    assert result.title_zh == "ODD v1.0.0 发布了！"
    assert result.body_en == "ODD v1.0.0 is out!"
    assert result.body_zh == "ODD v1.0.0 发布了！"
    assert result.short_en == "Short EN summary"
    assert result.short_zh == "简短中文摘�?


@patch("auto_publish.generate.OpenAI")
def test_generate_strips_whitespace(mock_cls):
    mock_cls.return_value = _mock_openai([
        "  body with spaces  ",
        "  short  ",
        "  中文正文  ",
        "  短文  ",
    ])

    result = generate(version="v0.1", changelog="fix", repo_url="https://example.com")
    assert result.body_en == "body with spaces"
    assert result.short_en == "short"
    assert result.body_zh == "中文正文"
    assert result.short_zh == "短文"


@patch("auto_publish.generate.OpenAI")
def test_generate_handles_none_content(mock_cls):
    """OpenAI occasionally returns None content �?should not crash."""
    client = MagicMock()
    client.chat.completions.create.return_value.choices[0].message.content = None
    mock_cls.return_value = client

    # Should not raise, just return empty strings
    result = generate(version="v0.2", changelog="fix", repo_url="https://example.com")
    assert result.body_en == ""
