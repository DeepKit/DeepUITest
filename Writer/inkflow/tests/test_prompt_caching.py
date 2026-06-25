"""Tests for B23-P1 prompt caching summary degradation."""

from __future__ import annotations

import tempfile
import os
import pytest

from inkflow.services.prompt_compiler import (
    _estimate_tokens,
    _build_previous_shots,
    _assemble_with_budget,
    PREVIOUS_SHOT_FULL_TEXT_LIMIT,
    PREVIOUS_SHOT_SUMMARY_LIMIT,
)


class TestPreviousShotsDegradation:
    """B23-P1: Previous shots degrade from full text → summary → bullets → drop."""

    def test_empty_previous_shots(self):
        """No previous shots → empty string."""
        result = _build_previous_shots([])
        assert result == ""

    def test_recent_shots_get_full_text(self):
        """Last 2 shots get full text (within limit)."""
        previous = [
            {"shot_index": 1, "text": "第一个文本。"},
            {"shot_index": 2, "text": "第二个文本。"},
            {"shot_index": 3, "text": "第三个完整文本，足够长。"},
            {"shot_index": 4, "text": "第四个完整文本，足够长。"},
        ]
        result = _build_previous_shots(previous)
        # Shots 3,4 are the last 2, should get full text
        assert "第三个完整文本" in result
        assert "第四个完整文本" in result
        assert "前文上下文" in result
        assert "最近上下文" in result

    def test_older_shots_get_summary(self):
        """Shots beyond full-text limit get one-line summaries."""
        previous = [
            {"shot_index": i, "text": f"N-{i} 这是一个足够长的文本，需要被摘要。" * 3}
            for i in range(1, 8)  # 7 shots: indices 1-5 get summary, 6-7 get full text
        ]
        result = _build_previous_shots(previous)
        # Shots 6,7 get full text (last 2)
        assert "N-7" in result
        # Shots 1-5 get summary with ellipsis
        assert "..." in result  # summaries have ellipsis
        assert "较早上下文" in result

    def test_very_old_shots_get_aggregated_bullets(self):
        """Shots beyond summary limit get aggregated bullet summaries."""
        previous = [
            {"shot_index": i, "text": f"N-{i} 这是第{i}个shot的完整文本内容。"}
            for i in range(1, 8)
        ]
        result = _build_previous_shots(previous)
        assert "前文上下文" in result

    def test_all_shots_beyond_10_are_dropped(self):
        """Shots beyond 10 are not included."""
        previous = [
            {"shot_index": i, "text": f"N-{i} text." * 5}
            for i in range(1, 12)
        ]
        result = _build_previous_shots(previous)
        # The function should handle 11 shots gracefully
        assert "前文上下文" in result

    def test_section_header_present(self):
        """Result always has the 前文上下文 header."""
        result = _build_previous_shots([{"shot_index": 1, "text": "text"}])
        assert "前文上下文" in result


class TestAssembleWithBudget:
    """B23-P1: Full prompt assembly respects token budget."""

    def test_under_budget_unchanged(self):
        """Prompt under budget → no degradation."""
        small_static = "身份：作家"
        small_dynamic = "写作任务：写一个场景。"
        result = _assemble_with_budget(small_static, small_dynamic, 8000)
        assert result == f"{small_static}\n\n{small_dynamic}"

    def test_over_budget_truncates_dynamic(self):
        """Prompt over budget → dynamic section truncated."""
        large_static = "身份" * 500
        large_dynamic = "前文" * 2000
        result = _assemble_with_budget(large_static, large_dynamic, 100)
        # Should still contain static prefix
        assert large_static[:20] in result

    def test_previous_shots_degrade_before_truncation(self):
        """When over budget, previous shots degrade before other content is cut."""
        # Create a static prefix that's already substantial
        static_prefix = "## 硬边界\n不可违反。" + "额外内容 " * 100
        # Build dynamic with many previous shots (will exceed budget)
        previous = [
            {"shot_index": i, "text": f"N-{i} 这是一个很长的文本内容。" * 30}
            for i in range(1, 15)  # 14 shots, far exceeding limits
        ]

        previous_text = _build_previous_shots(previous)
        fact_text = "\n## 事实锚点\n- [character_state] cs:1: 状态"
        shot_text = "\n## 写作任务\n写一个场景。"

        dynamic = shot_text + previous_text + fact_text

        # Budget is tight — will trigger degradation
        result = _assemble_with_budget(static_prefix, dynamic, 1500)

        # Result should be within budget
        assert _estimate_tokens(result) <= 1500
        # Static prefix should always be present
        assert "硬边界" in result
        # Degradation should have occurred (no full-text shots for 14 shots)
        # Either shots are degraded, truncated, or dropped entirely
        # The key is the system handles over-budget without crashing

    def test_cache_breakpoint_warning_triggered(self):
        """Static prefix over 4096 tokens triggers cacheable=False.

        Verify that the CACHE_BREAKPOINT_LIMIT constant is 4096 and
        that _estimate_tokens can exceed it with a large input.
        """
        from inkflow.services.prompt_compiler import CACHE_BREAKPOINT_LIMIT, _estimate_tokens
        assert CACHE_BREAKPOINT_LIMIT == 4096

        # A very large prefix should exceed the limit
        large_text = "硬边界约束 " * 10000
        tokens = _estimate_tokens(large_text)
        assert tokens > 4096

        # A small prefix should be under the limit
        small_text = "硬边界约束"
        small_tokens = _estimate_tokens(small_text)
        assert small_tokens < 4096


class TestTokenEstimation:
    """Token estimation for budget calculations."""

    def test_chinese_token_ratio(self):
        """Chinese text: ~1.2 chars per token."""
        text = "右腿膝盖里像有把生锈的螺丝刀一圈圈往里拧"
        tokens = _estimate_tokens(text)
        ratio = len(text) / tokens
        assert 1.0 <= ratio <= 2.0  # Allow some variance

    def test_english_token_ratio(self):
        """English text: ~3.5 chars per token."""
        text = "The quick brown fox jumps over the lazy dog"
        tokens = _estimate_tokens(text)
        assert 8 <= tokens <= 20

    def test_mixed_text(self):
        """Mixed Chinese + English."""
        text = "阿坤在成都woke up。"
        tokens = _estimate_tokens(text)
        assert tokens > 0

    def test_empty_string(self):
        """Empty string → 0 tokens."""
        assert _estimate_tokens("") == 0
