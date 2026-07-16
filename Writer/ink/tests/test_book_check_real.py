from __future__ import annotations

import json

import pytest

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.errors import LLMProviderError
from ink.pipeline.book_rolling_check_orchestrator import (
    BOOK_CHECK_DIMENSIONS,
    BookCheckLLMFailure,
    BookRollingCheckOrchestrator,
)
from test_m6_book_export import make_accepted_chapter


class _BookCheckProvider:
    """注入式 book_check 评分 provider：按传入 scores + issues 返回 6 维 JSON。"""

    def __init__(self, scores: dict[str, int], issues: list[dict[str, object]]) -> None:
        self._scores = scores
        self._issues = issues

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        if idempotency_key.startswith("book_check:"):
            text = json.dumps(self._scores | {"issues": self._issues}, ensure_ascii=False)
            return ModelResult(text=text, model_name=model_name, token_input=1, token_output=1)
        # 非 book_check 调用走默认（本测试不应触发）。
        return ModelResult(text="{}", model_name=model_name, token_input=1, token_output=1)


class _AlwaysFailProvider:
    """注入式 provider：book_check 调用恒抛 RuntimeError（模拟供应商故障）。"""

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        if idempotency_key.startswith("book_check:"):
            raise RuntimeError("供应商故障：book_check 不可用")
        return ModelResult(text="{}", model_name=model_name, token_input=1, token_output=1)


def _accepted_with_interval():
    conn = make_accepted_chapter()
    conn.execute("UPDATE writing_projects SET chapter_rolling_check_interval = 1 WHERE project_id = 1")
    return conn


def test_real_scores_and_issues_persist() -> None:
    """真实 6 维分 + issues list 落库（非桩恒定 82 + 标记判 blocking）。"""
    conn = _accepted_with_interval()
    scores = {
        "longline_suspense_closure": 88,
        "character_arc_completeness": 85,
        "motif_echo_density": 90,
        "theme_sublimation": 87,
        "global_rhythm_curve": 86,
        "foreshadow_recovery": 83,
    }
    issues = [
        {"severity": "warning", "code": "foreshadow_unrecovered", "chapter_range_end": 1, "detail": "伏笔未回收"},
    ]
    gateway = LLMGateway(conn, provider=_BookCheckProvider(scores, issues))
    result = BookRollingCheckOrchestrator(conn, gateway).run_if_due(1, 1)

    assert result is not None
    assert result.quality_gate_passed is True
    assert result.blocking_issue_count == 0
    row = conn.execute(
        """
        SELECT longline_suspense_closure, character_arc_completeness, motif_echo_density,
               theme_sublimation, global_rhythm_curve, foreshadow_recovery,
               issues, blocking_issue_count, quality_gate_passed
        FROM writing_book_check_results WHERE check_run_id = ?
        """,
        (result.check_run_id,),
    ).fetchone()
    assert row[:6] == (88, 85, 90, 87, 86, 83)
    persisted_issues = json.loads(row[6])
    assert persisted_issues[0]["code"] == "foreshadow_unrecovered"
    assert persisted_issues[0]["severity"] == "warning"
    assert row[7] == 0
    assert row[8] == 1


def test_blocking_issue_sets_count_and_blocks_export() -> None:
    """issues 含 severity=blocking → blocking_issue_count>0 → quality_gate_passed=0 → 拦 accept/export。"""
    conn = _accepted_with_interval()
    scores = {col: 80 for col in BOOK_CHECK_DIMENSIONS}
    issues = [
        {"severity": "blocking", "code": "arc_broken", "chapter_range_end": 1, "detail": "主角弧光断裂"},
    ]
    gateway = LLMGateway(conn, provider=_BookCheckProvider(scores, issues))
    result = BookRollingCheckOrchestrator(conn, gateway).run_if_due(1, 1)

    assert result is not None
    assert result.quality_gate_passed is False
    assert result.blocking_issue_count == 1
    # has_blocking_issues 现在返回 True（最新一次 book_check 有 blocking）。
    from ink.pipeline.book_rolling_check_orchestrator import has_blocking_issues

    assert has_blocking_issues(conn, 1) is True


def test_llm_total_failure_raises_no_fake_score() -> None:
    """三 tier 全失败 → 抛 BookCheckLLMFailure，不写任何假分（无 book_check 行）。"""
    conn = _accepted_with_interval()
    gateway = LLMGateway(conn, provider=_AlwaysFailProvider())

    with pytest.raises(BookCheckLLMFailure):
        BookRollingCheckOrchestrator(conn, gateway).run_if_due(1, 1)

    assert conn.execute("SELECT count(*) FROM writing_book_check_results").fetchone()[0] == 0


def test_interval_not_due_returns_none() -> None:
    """up_to_chapter 不整除 interval → 不触发，返回 None。"""
    conn = make_accepted_chapter()  # interval 默认 3（或其他），不整除 1
    scores = {col: 90 for col in BOOK_CHECK_DIMENSIONS}
    gateway = LLMGateway(conn, provider=_BookCheckProvider(scores, []))
    result = BookRollingCheckOrchestrator(conn, gateway).run_if_due(1, 1)
    assert result is None
    assert conn.execute("SELECT count(*) FROM writing_book_check_results").fetchone()[0] == 0
