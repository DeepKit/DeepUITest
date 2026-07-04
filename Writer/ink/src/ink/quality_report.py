from __future__ import annotations

from dataclasses import dataclass

from ink.errors import DataIntegrityError


EVIDENCE_CLASSES = {"ES", "SEMI_ES", "NES"}
DEFECT_CLASSES = {"destructive", "productive", "neutral"}


@dataclass(frozen=True)
class QualityReport:
    evidence_class: str
    defect_class: str
    blind_review_passed: bool
    would_continue_reading_score: int
    blocking_items: tuple[str, ...]
    productive_deviations: tuple[str, ...]
    neutral_issues: tuple[str, ...]
    smart_model_required: bool


def validate_quality_report(payload: dict) -> QualityReport:
    required = {
        "evidence_class",
        "defect_class",
        "blind_review_passed",
        "would_continue_reading_score",
        "blocking_items",
        "productive_deviations",
        "neutral_issues",
        "smart_model_required",
    }
    missing = sorted(required - set(payload))
    if missing:
        raise DataIntegrityError(f"quality report missing required fields: {', '.join(missing)}")

    evidence_class = str(payload["evidence_class"])
    defect_class = str(payload["defect_class"])
    if evidence_class not in EVIDENCE_CLASSES:
        raise DataIntegrityError(f"invalid evidence_class: {evidence_class}")
    if defect_class not in DEFECT_CLASSES:
        raise DataIntegrityError(f"invalid defect_class: {defect_class}")

    score = int(payload["would_continue_reading_score"])
    if score < 0 or score > 100:
        raise DataIntegrityError("would_continue_reading_score must be between 0 and 100")

    return QualityReport(
        evidence_class=evidence_class,
        defect_class=defect_class,
        blind_review_passed=bool(payload["blind_review_passed"]),
        would_continue_reading_score=score,
        blocking_items=tuple(str(item) for item in payload["blocking_items"]),
        productive_deviations=tuple(str(item) for item in payload["productive_deviations"]),
        neutral_issues=tuple(str(item) for item in payload["neutral_issues"]),
        smart_model_required=bool(payload["smart_model_required"]),
    )
