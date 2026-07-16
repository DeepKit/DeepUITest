from __future__ import annotations

from ink.core.prose_integrity import extract_polished_prose, find_generation_artifact


def test_extract_polished_prose_removes_intro_and_trailing_edit_notes() -> None:
    raw = """好的，收到。我将严格润色。

以下是润色后的版本：

---

吕素琴把钥匙放在桌上。门外的脚步停了。

---

**主要调整说明**
- 调整了节奏。
"""

    assert extract_polished_prose(raw) == "吕素琴把钥匙放在桌上。门外的脚步停了。"


def test_generation_artifact_finds_production_failure_seen_in_real_run() -> None:
    text = "好的，收到。这个文本的基础非常扎实。\n\n以下是润色后的版本：\n\n正文。"

    assert find_generation_artifact(text) is not None


def test_extract_polished_prose_cuts_trailing_meta_heading() -> None:
    assert (
        extract_polished_prose("正文第一段。\n\n修改说明：这里还需要继续调整。")
        == "正文第一段。"
    )


def test_literary_scene_break_is_preserved() -> None:
    text = "第一场结束。\n\n---\n\n第二场开始。"

    assert extract_polished_prose(text) == text


def test_synthetic_provider_placeholder_is_never_publishable() -> None:
    assert (
        find_generation_artifact(
            "[mock:model:quality-retry:shot] generated draft"
        )
        == "synthetic_provider_placeholder"
    )
