from __future__ import annotations


def cjk_bigram_overlap(source: str, candidate: str) -> float:
    """Return contract-source bigram recall in the candidate.

    This is intentionally directional.  An outline candidate is expected to be
    much longer than the compact contract source; Jaccard similarity divided by
    the candidate's many legitimate new bigrams and falsely rejected detailed
    real-model outlines.  Drift means dropping the contract anchors, so the
    correct denominator is the source bigram set.
    """
    source_bigrams = _bigrams(_cjk_chars(source))
    candidate_bigrams = _bigrams(_cjk_chars(candidate))
    if not source_bigrams or not candidate_bigrams:
        return 0.0
    return len(source_bigrams & candidate_bigrams) / len(source_bigrams)


def is_drift_rejected(drift_score: float, threshold: float) -> bool:
    return drift_score < threshold


def _cjk_chars(text: str) -> str:
    return "".join(ch for ch in text if "\u4e00" <= ch <= "\u9fff")


def _bigrams(text: str) -> set[str]:
    return {text[index : index + 2] for index in range(max(0, len(text) - 1))}
