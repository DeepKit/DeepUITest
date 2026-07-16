from __future__ import annotations

import json

import pytest

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.errors import DataIntegrityError
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.pipeline.ethics_review_orchestrator import EthicsReviewOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from test_m5_chapter_review import (
    _chapter_review_gateway,
    _ids,
    make_soft_sealed_chapter,
)


class EthicsProvider:
    def __init__(self, *, recommendation: str = "approve", risk: str = "medium") -> None:
        self.recommendation = recommendation
        self.risk = risk

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        payload = {
            "responsibility_question": "谁决定让不确定的密封件继续流向前线？",
            "affected_parties": ["前线使用者", "质检员", "签字责任人"],
            "irreversible_harm": "失效可能造成无法挽回的人身伤害。",
            "agency_obscured": False,
            "evidence_sentences": ["表格上没有最终后果这一栏。"],
            "risk_level": self.risk,
            "recommendation": self.recommendation,
            "review_notes": "文本保留了行动者与后果，没有把伤害浪漫化。",
        }
        return ModelResult(
            text=json.dumps(payload, ensure_ascii=False),
            model_name=model_name,
            token_input=10,
            token_output=10,
        )


def test_three_reviewer_ethics_review_records_actor_models_and_evidence() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)

    result = EthicsReviewOrchestrator(
        conn,
        LLMGateway(conn, provider=EthicsProvider(), provider_name="ethics-test"),
    ).review_chapter(1, 1, int(ids["run_id"]), reviewer_actor="editor-li")

    assert result.recommendation == "approve"
    assert result.risk_level == "medium"
    row = conn.execute(
        """
        SELECT reviewer_actor, reviewer_models_json, affected_parties_json,
               evidence_sentences_json, recommendation
        FROM writing_chapter_ethics_reviews
        """
    ).fetchone()
    assert row[0] == "editor-li"
    assert len(json.loads(row[1])) == 3
    assert "前线使用者" in json.loads(row[2])
    assert json.loads(row[3]) == ["表格上没有最终后果这一栏。"]
    assert row[4] == "approve"


def test_required_ethics_review_blocks_accept_until_approved() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(
        1, 1, int(ids["run_id"])
    )
    conn.execute("UPDATE writing_projects SET require_ethics_review=1 WHERE project_id=1")

    with pytest.raises(DataIntegrityError, match="ethics review is missing"):
        HumanReviewOrchestrator(conn).accept_chapter(
            1, 1, int(ids["run_id"]), actor="author", reason="accept"
        )

    EthicsReviewOrchestrator(
        conn,
        LLMGateway(conn, provider=EthicsProvider(), provider_name="ethics-test"),
    ).review_chapter(1, 1, int(ids["run_id"]), reviewer_actor="responsibility-editor")

    decision_id = HumanReviewOrchestrator(conn).accept_chapter(
        1, 1, int(ids["run_id"]), actor="author", reason="quality and ethics passed"
    )
    assert decision_id > 0


def test_blocking_ethics_review_prevents_accept() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(
        1, 1, int(ids["run_id"])
    )
    conn.execute("UPDATE writing_projects SET require_ethics_review=1 WHERE project_id=1")
    EthicsReviewOrchestrator(
        conn,
        LLMGateway(
            conn,
            provider=EthicsProvider(recommendation="revise", risk="blocking"),
            provider_name="ethics-test",
        ),
    ).review_chapter(1, 1, int(ids["run_id"]), reviewer_actor="responsibility-editor")

    with pytest.raises(DataIntegrityError, match="ethics review prevents accept"):
        HumanReviewOrchestrator(conn).accept_chapter(
            1, 1, int(ids["run_id"]), actor="author", reason="accept anyway"
        )
