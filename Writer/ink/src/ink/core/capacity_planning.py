from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class LLMCapacityPlan:
    max_candidates: int
    jury_calls: int
    total_calls: int


def recommended_llm_capacity(
    *,
    draft_count: int,
    creative_shot_extra: int,
    redo_candidate_count: int,
    escalated_jury_count: int,
) -> LLMCapacityPlan:
    """Conservative capacity for one shot without scoring unchanged drafts twice.

    Jury allowance covers:
    - every possible base/creative candidate with three judges;
    - one polished candidate with three judges;
    - one retry wave;
    - up to three disagreement escalations.
    """
    max_candidates = max(1, draft_count + creative_shot_extra)
    jury_calls = (
        3 * max_candidates
        + 3  # one polished candidate
        + 3 * max(0, redo_candidate_count)
        + 3 * max(3, escalated_jury_count)
    )
    non_jury_calls = max_candidates + max(0, redo_candidate_count) + 1 + 1 + 12
    return LLMCapacityPlan(
        max_candidates=max_candidates,
        jury_calls=max(8, jury_calls),
        total_calls=max(40, jury_calls + non_jury_calls),
    )
