"""Test shot splitter."""

from __future__ import annotations

from inkflow.importers.shot_splitter import (
    detect_shots,
    split_by_scene_headers,
    split_by_paragraphs,
    format_shot_review,
)


class TestSplitBySceneHeaders:
    """Split text using ## scene headers"""

    def test_splits_on_headers(self):
        text = "# 第01章：标题\n\n## 一\n\n第一段正文。\n第二行。\n\n## 二\n\n第二段正文。\n\n## 三\n\n第三段正文。"
        shots = split_by_scene_headers(text)
        assert len(shots) == 3
        assert shots[0]["title"] == "一"
        assert "第一段正文" in shots[0]["text"]
        assert shots[1]["title"] == "二"
        assert shots[2]["title"] == "三"

    def test_no_scene_headers(self):
        text = "没有标题的纯文本。\n\n第二段。"
        shots = split_by_scene_headers(text)
        assert len(shots) == 0


class TestSplitByParagraphs:
    """Fallback paragraph-based split"""

    def test_splits_into_groups(self):
        text = "\n\n".join([f"段落{i}" for i in range(10)])
        shots = split_by_paragraphs(text, max_paragraphs_per_shot=3)
        assert len(shots) == 4  # 10 / 3 = 4 groups
        assert shots[0]["shot_index"] == 1


class TestDetectShots:
    """Full shot detection"""

    def test_detects_with_scene_headers(self):
        text = "# 第01章\n\n## 一\n\n正文一。\n\n## 二\n\n正文二。"
        result = detect_shots(text, "v01.c01")
        assert result["shot_count"] == 2
        assert result["chapter_key"] == "v01.c01"
        assert result["shots"][0]["shot_key"] == "v01.c01.s01"
        assert result["shots"][1]["shot_key"] == "v01.c01.s02"

    def test_falls_back_to_paragraphs(self):
        text = "段落一。\n\n段落二。\n\n段落三。"
        result = detect_shots(text, "v01.c01")
        assert result["shot_count"] >= 1

    def test_char_count(self):
        text = "# 第01章\n\n## 一\n\n十个字十个字十个字。"
        result = detect_shots(text, "v01.c01")
        assert result["shots"][0]["char_count"] > 0


class TestFormatShotReview:
    """Human review formatting"""

    def test_formats_nicely(self):
        text = "# 第01章\n\n## 一\n\n正文内容测试。"
        analysis = detect_shots(text, "v01.c01")
        formatted = format_shot_review(analysis)
        assert "v01.c01" in formatted
        assert "Shot 01" in formatted
        assert "正文内容测试" in formatted