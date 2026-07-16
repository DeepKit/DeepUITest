from __future__ import annotations

from ink.core.capacity_planning import recommended_llm_capacity


def test_default_capacity_covers_creative_candidates_retry_and_escalation() -> None:
    plan = recommended_llm_capacity(
        draft_count=3,
        creative_shot_extra=3,
        redo_candidate_count=2,
        escalated_jury_count=5,
    )

    assert plan.max_candidates == 6
    assert plan.jury_calls == 42
    assert plan.total_calls >= 64
