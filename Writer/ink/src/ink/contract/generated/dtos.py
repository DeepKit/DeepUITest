from __future__ import annotations

from dataclasses import dataclass


class GeneratedContractDTO:
    def unpack(self) -> dict[str, object]:
        return {name: getattr(self, name) for name in self.__dataclass_fields__}

@dataclass(frozen=True)
class MetaContractDTO(GeneratedContractDTO):
    meta_contract_id: int
    project_id: int
    identity: dict[str, object]
    narrative_voice: dict[str, object]
    hard_boundaries: dict[str, object]
    style_locks: dict[str, object]
    world_knowledge: dict[str, object]
    motif_system: dict[str, object]
    creative_zones: dict[str, object]
    style_quality_profile: dict[str, object]
    status: str

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
class OutlineSpecDTO(GeneratedContractDTO):
    outline_id: int
    shot_contract_id: int
    evaluated_outline_text: str
    drift_score: float
    is_winner: bool

@dataclass(frozen=True)
class TaskCardDTO(GeneratedContractDTO):
    task_card_id: int
    shot_contract_id: int
    compiled_instructions: str
    superseded_at: str | None

@dataclass(frozen=True)
class PromptSpecDTO(GeneratedContractDTO):
    prompt_id: int
    task_card_id: int
    persona: str
    full_prompt_text: str
    prompt_size_bytes: int
    relaxed_soft: bool
    superseded_at: str | None

@dataclass(frozen=True)
class DraftSpecDTO(GeneratedContractDTO):
    draft_id: int
    shot_id: str
    prompt_id: int
    persona: str
    writer_model: str
    text: str
    byte_count: int
    degraded: bool
    failure_category: str | None
    retry_count: int
    is_deviant: bool

@dataclass(frozen=True)
class JuryInputDTO(GeneratedContractDTO):
    draft_id: int
    shot_contract_id: int
    jury_round: int
    judge_model_pool: tuple[str, ...]

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

