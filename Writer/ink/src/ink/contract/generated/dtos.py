from __future__ import annotations

from dataclasses import dataclass


class GeneratedContractDTO:
    def unpack(self) -> dict[str, object]:
        return {name: getattr(self, name) for name in self.__dataclass_fields__}

@dataclass(frozen=True)
class ShotContractDTO(GeneratedContractDTO):
    shot_id: str
    run_id: int
    must_land: dict[str, object]
    anti_write: dict[str, object]
    scene_contract: dict[str, object]
    persona_assignment: dict[str, object]
    soft_constraints: dict[str, object]

@dataclass(frozen=True)
class ProjectConfigDTO(GeneratedContractDTO):
    project_id: int
    draft_count: int
    writer_model_pool: tuple[str, ...]
    jury_model_pool: tuple[str, ...]
    shot_quality_floor: int
    dimension_floor: int

@dataclass(frozen=True)
class QualityReportDTO(GeneratedContractDTO):
    evidence_class: str
    defect_class: str
    blind_review_passed: bool
    would_continue_reading_score: int
    blocking_items: tuple[str, ...]
    productive_deviations: tuple[str, ...]
    neutral_issues: tuple[str, ...]
    smart_model_required: bool

