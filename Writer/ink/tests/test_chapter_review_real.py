from __future__ import annotations

import json

import pytest

from ink.core.chapter_coherence import ChapterOverlap, CoherenceGateResult
from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.core.text_repository import TextRepository
from ink.errors import LLMProviderError
from ink.pipeline.chapter_review_orchestrator import (
    CHAPTER_REVIEW_DIMENSIONS,
    ChapterReviewLLMFailure,
    ChapterReviewOrchestrator,
)
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from ink.pipeline.jury_orchestrator import JuryOrchestrator
from ink.pipeline.polish_orchestrator import PolishOrchestrator
from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator
from test_m4_review_pipeline import PolishProvider, _jury_gateway, make_winner_selected_shot


class _FixedScoreProvider:
    """注入式 chapter_review 评分 provider：按传入的 scores dict 返回章级维度 JSON。"""

    def __init__(self, scores: dict[str, int], *, notes: str = "real review") -> None:
        self._scores = scores
        self._notes = notes

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        text = json.dumps(self._scores | {"review_notes": self._notes}, ensure_ascii=False)
        return ModelResult(text=text, model_name=model_name, token_input=1, token_output=1)


class _AlwaysFailProvider:
    """注入式 provider：chapter_review 调用恒抛 RuntimeError（模拟供应商故障）。"""

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        if idempotency_key.startswith("chapter_review:"):
            raise RuntimeError("供应商故障：chapter_review 不可用")
        # 非 chapter_review 调用走默认（本测试不会触发，但保留安全回退）。
        return ModelResult(text="{}", model_name=model_name, token_input=1, token_output=1)


def _gateway_with(conn, scores: dict[str, int]) -> LLMGateway:
    return LLMGateway(conn, provider=_FixedScoreProvider(scores))


def _make_soft_sealed_chapter():
    conn = make_winner_selected_shot()
    row = conn.execute(
        "SELECT shot_id, run_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
    ).fetchone()
    shot_id, run_id = str(row[0]), int(row[1])
    PolishOrchestrator(conn, LLMGateway(conn, provider=PolishProvider())).polish_winner(shot_id, run_id)
    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn, _jury_gateway(conn)).score_and_select_winner(shot_id, run_id)
    SoftSealOrchestrator(conn).soft_seal_if_polished(shot_id, run_id)
    return conn, shot_id, run_id


def test_real_scores_persist_not_stub_eighty_two() -> None:
    """真实评分落库：8 维为 LLM 返回的真实分（非桩的恒定 82）。"""
    conn, _, run_id = _make_soft_sealed_chapter()
    scores = {
        "chapter_continuity_hard": 88,
        "pov_consistency": 91,
        "character_consistency": 85,
        "chapter_hook_soft": 90,
        "rhythm_curve": 87,
        "motif_density": 86,
        "info_gap_lifecycle": 89,
        "chapter_coherence": 93,
    }
    review = ChapterReviewOrchestrator(conn, _gateway_with(conn, scores)).review_chapter(1, 1, run_id)

    assert review.quality_gate_passed is True
    assert review.blocking_issues == ()
    row = conn.execute(
        """
        SELECT chapter_continuity_hard, pov_consistency, character_consistency,
               chapter_hook_soft, rhythm_curve, motif_density, info_gap_lifecycle,
               chapter_coherence, quality_gate_passed, blocking_issues
        FROM writing_chapter_reviews WHERE review_id = ?
        """,
        (review.review_id,),
    ).fetchone()
    assert row[:8] == (88, 91, 85, 90, 87, 86, 89, 93)
    assert row[8] == 1
    assert json.loads(row[9]) == []


def test_real_low_score_dimension_blocks_gate() -> None:
    """某维 < floor（默认 75）→ blocking_issues 含该维 → quality_gate_passed=0 → 拦 accept。"""
    conn, _, run_id = _make_soft_sealed_chapter()
    scores = {col: 88 for col in CHAPTER_REVIEW_DIMENSIONS}
    scores["motif_density"] = 70  # 低于 floor 75 → blocking
    review = ChapterReviewOrchestrator(conn, _gateway_with(conn, scores)).review_chapter(1, 1, run_id)

    assert review.quality_gate_passed is False
    assert review.blocking_issues == ("motif_density",)
    with pytest.raises(Exception):
        HumanReviewOrchestrator(conn).accept_chapter(1, 1, run_id, actor="author", reason="approve")
    # accept 被拦，章仍 soft_sealed，无 hard seal 文本。
    assert conn.execute("SELECT count(*) FROM writing_shot_revisions WHERE sealed_by = 'chapter_hard'").fetchone()[0] == 0


def test_llm_total_failure_raises_no_fake_score() -> None:
    """三 tier 全失败 → 抛 ChapterReviewLLMFailure，不写任何假分（无 chapter_review 行）。"""
    conn, _, run_id = _make_soft_sealed_chapter()
    gateway = LLMGateway(conn, provider=_AlwaysFailProvider())

    with pytest.raises(ChapterReviewLLMFailure):
        ChapterReviewOrchestrator(conn, gateway).review_chapter(1, 1, run_id)

    assert conn.execute("SELECT count(*) FROM writing_chapter_reviews").fetchone()[0] == 0


def test_missing_coherence_dimension_fails_closed_without_review_row() -> None:
    """旧 7 维返回不能绕过新增 coherence 维度，也不能落默认假分。"""
    conn, _, run_id = _make_soft_sealed_chapter()
    scores = {col: 90 for col in CHAPTER_REVIEW_DIMENSIONS if col != "chapter_coherence"}

    with pytest.raises(ChapterReviewLLMFailure):
        ChapterReviewOrchestrator(conn, _gateway_with(conn, scores)).review_chapter(
            1, 1, run_id
        )

    assert conn.execute("SELECT count(*) FROM writing_chapter_reviews").fetchone()[0] == 0


def test_low_coherence_dimension_blocks_gate() -> None:
    """coherence 是真实门槛维度，低分必须独立进入 blocking_issues。"""
    conn, _, run_id = _make_soft_sealed_chapter()
    scores = {col: 90 for col in CHAPTER_REVIEW_DIMENSIONS}
    scores["chapter_coherence"] = 74

    review = ChapterReviewOrchestrator(conn, _gateway_with(conn, scores)).review_chapter(
        1, 1, run_id
    )

    assert review.quality_gate_passed is False
    assert review.blocking_issues == ("chapter_coherence",)
    stored = conn.execute(
        "SELECT chapter_coherence FROM writing_chapter_reviews WHERE review_id = ?",
        (review.review_id,),
    ).fetchone()
    assert stored[0] == 74


def test_deterministic_overlap_cannot_be_overridden_by_high_coherence(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """文学 reviewer 全高分也不能推翻确定性同构阻断。"""
    conn, _, run_id = _make_soft_sealed_chapter()
    scores = {col: 99 for col in CHAPTER_REVIEW_DIMENSIONS}
    overlap = CoherenceGateResult(
        passed=False,
        threshold=0.55,
        overlaps=(
            ChapterOverlap(
                chapter_id=1,
                score=0.80,
                shared_tokens=("硫化车间", "压力表"),
            ),
        ),
    )
    monkeypatch.setattr(
        "ink.pipeline.chapter_review_orchestrator.evaluate_chapter_overlap",
        lambda *args, **kwargs: overlap,
    )

    review = ChapterReviewOrchestrator(conn, _gateway_with(conn, scores)).review_chapter(
        1, 1, run_id
    )

    assert review.quality_gate_passed is False
    assert "chapter_scene_overlap" in review.blocking_issues
    assert "chapter_coherence" not in review.blocking_issues
    notes = conn.execute(
        "SELECT review_notes FROM writing_chapter_reviews WHERE review_id = ?",
        (review.review_id,),
    ).fetchone()[0]
    assert "chapter_scene_overlap" in notes
    assert "chapter=1" in notes and "overlap=0.80" in notes


def test_review_notes_from_llm_evidence() -> None:
    """review_notes 取 LLM 返回的 evidence 文本。"""
    conn, _, run_id = _make_soft_sealed_chapter()
    scores = {col: 90 for col in CHAPTER_REVIEW_DIMENSIONS}
    gateway = _gateway_with(conn, scores)
    # 替换 notes：用一个固定 notes 的 provider。
    gateway = LLMGateway(
        conn,
        provider=_FixedScoreProvider(scores, notes="章末钩子偏弱，节奏前紧后松。"),
    )
    review = ChapterReviewOrchestrator(conn, gateway).review_chapter(1, 1, run_id)
    row = conn.execute(
        "SELECT review_notes FROM writing_chapter_reviews WHERE review_id = ?",
        (review.review_id,),
    ).fetchone()
    assert row[0].count("章末钩子偏弱，节奏前紧后松。") == 3
    assert "[reviewer-1]" in row[0] and "[reviewer-3]" in row[0]
