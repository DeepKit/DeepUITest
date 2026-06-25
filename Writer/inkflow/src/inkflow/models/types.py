"""Type definitions for service interfaces.

TypedDict and Protocol classes for passing data between InkFlow services.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, TypedDict

if TYPE_CHECKING:
    from .enums import (
        AnchorType,
        BadsmellLevel,
        BrillianceLevel,
        ContractStatus,
        DensityStatus,
        JuryDimension,
        JuryPhase,
        LightStatus,
        PlaceholderType,
        RevisionOperation,
        SessionStatus,
        ShotContractStatus,
        ShotStatus,
        WriterPersona,
    )


# ── Session ──

class SessionInfo(TypedDict):
    session_id: str
    project_id: str
    run_id: str
    act_id: str | None
    status: SessionStatus
    current_shot_id: str | None
    completed_shots: int
    total_shots: int | None


class CheckpointData(TypedDict):
    checkpoint_id: str
    session_id: str
    shot_id: str
    checkpoint_json: dict
    checkpoint_storage_path: str
    context_hash: str


# ── Contract ──

class MetaContract(TypedDict):
    meta_contract_id: str
    project_id: str
    contract_version: str
    status: ContractStatus
    layers_json: dict
    human_confirm_layer: int


class ShotContract(TypedDict):
    contract_id: str
    project_id: str
    run_id: str
    shot_id: str
    layer_key: str
    contract_status: ShotContractStatus
    must_land_json: dict
    anti_write_json: dict
    exit_to_json: dict | None
    motif_tasks_json: dict | None
    pov_routing_json: dict | None
    contract_json: dict


# ── Writer Race ──

class WriterDraft(TypedDict):
    draft_id: str
    shot_id: str
    writer_persona: WriterPersona
    writer_index: int
    text: str
    self_note: str | None
    is_usable: bool


class WriterRaceRequest(TypedDict):
    attempt_id: str
    idempotency_key: str
    model_id: str
    messages: list[dict]
    max_tokens: int
    temperature: float


class WriterRaceResponse(TypedDict):
    attempt_id: str
    text: str
    self_note: str
    finish_reason: str
    usage: dict[str, int]


# ── Jury ──

class JuryScore(TypedDict):
    score_id: str
    draft_id: str
    shot_id: str
    jury_persona: str
    phase: JuryPhase
    dimension: JuryDimension
    score: int
    comment: str | None


class JuryVerdict(TypedDict):
    winner_draft_id: str
    scores: list[JuryScore]
    brilliance_markers: list[str]
    badsmell_markers: list[str]
    confidence: float


# ── Gate ──

class Gate1Result(TypedDict):
    passed: bool
    draft_id: str
    violations: list[str]


class Gate2Result(TypedDict):
    passed: bool
    score: float
    light_status: LightStatus
    brilliance_level: BrillianceLevel | None
    badsmell_level: BadsmellLevel | None
    violations: list[str]


# ── Fact Anchor ──

class FactAnchor(TypedDict):
    anchor_id: str
    project_id: str
    anchor_type: AnchorType
    anchor_key: str
    anchor_value: str
    confidence: float
    pov_scope: str | None
    source_revision_id: str | None


class AnchorConflict(TypedDict):
    anchor_a: str
    anchor_b: str
    conflict_type: str  # explicit_contradiction | implicit_inconsistency | timeline_misalignment | explainable_deviation | pov_contradiction
    description: str


# ── Motif ──

class MotifDefinition(TypedDict):
    motif_id: str
    name: str
    category: str | None
    description: str | None
    planned_density_json: dict
    variants_json: dict
    min_shot_gap: int


class MotifTask(TypedDict):
    required: list[str]
    suggested: list[str]
    forbidden: list[str]
    allowed: list[str]


class MotifTrackerState(TypedDict):
    tracker_id: str
    motif_id: str
    current_count: int
    density_status: DensityStatus
    last_used_shot_id: str | None


# ── Context Assembly ──

class ContextSnap(TypedDict):
    snap_id: str
    shot_id: str
    run_id: str
    previous_shots_json: dict
    fact_anchor_refs_json: dict
    motif_tracker_state_json: dict
    anti_samples_json: dict
    injected_with_warning: bool


# ── Project Config ──

class ProjectConfig(TypedDict):
    config_id: str
    project_id: str
    default_preset: str
    redo_model: str
    layers_json: dict


# ── Models Config ──

class FunctionModels(TypedDict):
    primary: str
    candidates: list[str]
    fallback: str


class ModelsConfig(TypedDict):
    architect: FunctionModels
    writer: FunctionModels
    jury: FunctionModels
    fact_anchor: FunctionModels
    repair: FunctionModels
    _meta: dict


# ── Shot ──

class ShotInfo(TypedDict):
    shot_id: str
    project_id: str
    run_id: str
    layer_key: str
    shot_index: int
    shot_status: ShotStatus
    placeholder_type: PlaceholderType | None
    redo_attempt: int
    light_status: LightStatus | None
    brilliance_level: BrillianceLevel | None
    badsmell_level: BadsmellLevel | None
    current_revision_id: str | None


# ── Revision ──

class RevisionInfo(TypedDict):
    revision_id: str
    shot_id: str
    run_id: str
    parent_revision_id: str | None
    contract_id: str
    revision_sequence: int
    operation: RevisionOperation
    text: str
    text_hash_normalized: str
    writer_persona: WriterPersona | None
    is_current: bool