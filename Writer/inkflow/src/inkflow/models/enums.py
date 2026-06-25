"""Enums matching all CHECK constraints from the InkFlow schema.

Each enum corresponds to a CHECK constraint column in the 25-table DDL.
Values are the Python-side string constants used across services.
"""

from __future__ import annotations

from enum import Enum


# ── projects ──

class ProjectStatus(str, Enum):
    ACTIVE = "active"
    ARCHIVED = "archived"


# ── writing_meta_contract ──

class ContractStatus(str, Enum):
    DRAFT = "draft"
    HUMAN_REVIEW = "human_review"
    CONFIRMED = "confirmed"
    LOCKED = "locked"
    REPAIRING = "repairing"
    EVOLVING = "evolving"


class ContractChangedBy(str, Enum):
    HUMAN = "human"
    AI = "ai"
    UPGRADE = "upgrade"


# ── writing_shots ──

class ShotStatus(str, Enum):
    PENDING = "pending"
    GENERATING = "generating"
    GATE1_CHECK = "gate1_check"
    JURY_SCORING = "jury_scoring"
    FINAL_GATE = "final_gate"
    DONE_GREEN = "done_green"
    DONE_YELLOW = "done_yellow"
    PLACEHOLDER = "placeholder"
    REDO = "redo"
    DONE_RED_PERMANENT = "done_red_permanent"


class PlaceholderType(str, Enum):
    BEST_FAILED_CANDIDATE = "best_failed_candidate"
    REDO_PLACEHOLDER = "redo_placeholder"
    PERMANENT_RED = "permanent_red"


class LightStatus(str, Enum):
    GREEN = "green"
    YELLOW = "yellow"
    RED = "red"


class BrillianceLevel(str, Enum):
    A = "A"
    A_PLUS = "A+"
    S = "S"


class BadsmellLevel(str, Enum):
    B = "B"
    Br = "Br"
    Bz = "Bz"


class ContextInjectionStatus(str, Enum):
    FULL = "full"
    WARNING = "warning"
    SUMMARY_ONLY = "summary_only"


# ── shot_revisions ──

class RevisionOperation(str, Enum):
    WRITE_GENERATE = "write_generate"
    WRITE_PLACEHOLDER = "write_placeholder"
    WRITE_REPAIR = "write_repair"
    WRITE_REDO = "write_redo"
    WRITE_POLISH = "write_polish"
    # P0: human_baseline uses write_generate temporarily
    # Future: may add HUMAN_BASELINE = "human_baseline"


# ── writing_fact_anchors ──

class AnchorType(str, Enum):
    CHARACTER_STATE = "character_state"
    CHARACTER_TRAIT = "character_trait"
    OBJECT_LOCATION = "object_location"
    OBJECT_PROPERTY = "object_property"
    EVENT_OCCURRED = "event_occurred"
    RELATIONSHIP = "relationship"
    WORLD_RULE = "world_rule"
    TIMELINE = "timeline"
    KNOWLEDGE = "knowledge"


class AnchorOverrideSource(str, Enum):
    UNIVERSE = "universe"
    PROJECT_OVERRIDE = "project_override"
    PROJECT_FORK = "project_fork"


# ── writing_motif_instances ──

class EvolutionPhase(str, Enum):
    ESTABLISHMENT = "establishment"
    VARIATION = "variation"
    SUBVERSION = "subversion"
    RESOLUTION = "resolution"


# ── writing_motif_tracker ──

class DensityStatus(str, Enum):
    GREEN = "green"
    YELLOW = "yellow"
    BLUE = "blue"
    RED = "red"
    GRAY = "gray"


# ── writing_jury_scores ──

class JuryPhase(str, Enum):
    INDEPENDENT = "independent"
    COMPARATIVE = "comparative"
    FINAL = "final"


class JuryDimension(str, Enum):
    # 旧维度 (v3, 向后兼容)
    LITERARY_QUALITY = "literary_quality"
    NARRATIVE_PACING = "narrative_pacing"
    VOICE_CONSISTENCY = "voice_consistency"
    CONTRACT_COMPLIANCE = "contract_compliance"
    MOTIF_COMPATIBILITY = "motif_compatibility"
    ANTI_PATTERN_AVOIDANCE = "anti_pattern_avoidance"
    HOOK_TRANSITION = "hook_transition"
    CHARACTER_COHERENCE = "character_coherence"
    READER_ENGAGEMENT = "reader_engagement"
    # 新维度 (v4, 九评委)
    FORBIDDEN_EXPRESSION = "forbidden_expression"
    READING_FLUENCY = "reading_fluency"


# ── v4 九评委常量 ──

JURY_V4_DIMENSIONS = [
    "contract_compliance",       # 契约履约
    "forbidden_expression",      # 禁用表达 + AI味
    "reading_fluency",           # 阅读流畅
    "suspense_effectiveness",    # 悬疑效果 (D-25)
    "unexpected_value",          # 意外价值 (CREATIVE-1)
]

JURY_V4_DIMENSION_DISPLAY = {
    "contract_compliance": "契约履约",
    "forbidden_expression": "禁用表达",
    "reading_fluency": "阅读流畅",
    "suspense_effectiveness": "悬疑效果",
    "unexpected_value": "意外价值",
}

JURY_V4_MODELS_DEFAULT = [
    "deepseek/deepseek-v4-pro",
    "bailian/qwen3.7-plus",
    "stepfun/step-router-v1",
]


# ── writing_repair_audit ──

class RepairLayer(str, Enum):
    L1 = "L1"
    L2 = "L2"
    L3 = "L3"
    L4 = "L4"


# ── writing_exception_events ──

class ExceptionEventType(str, Enum):
    UNRESOLVABLE = "unresolvable"
    ESCAPE = "escape"
    DRIFT_ALERT = "drift_alert"


class ArchitectReviewStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    DEFERRED = "deferred"


# ── writing_deviation_notes ──

class DeviationNoteType(str, Enum):
    INTENT_DRIFT = "intent_drift"
    CONTRACT_VIOLATION = "contract_violation"
    HUMAN_FLAG = "human_flag"


class Severity(str, Enum):
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


# ── writing_sessions ──

class SessionStatus(str, Enum):
    ACTIVE = "active"
    PAUSED = "paused"
    COMPLETED = "completed"
    ABORTED = "aborted"
    CRASHED = "crashed"


# ── writing_reference_pool ──

class SampleType(str, Enum):
    POSITIVE = "positive"
    NEGATIVE = "negative"


class ReviewStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


# ── writing_project_structure ──

class LayerType(str, Enum):
    UNIVERSE = "universe"
    PROJECT = "project"
    ACT = "act"
    VOLUME = "volume"
    CHAPTER = "chapter"
    SCENE = "scene"


# ── writing_writer_profiles ──

class WriterPersona(str, Enum):
    IMAGIST = "意象师"
    PACER = "节奏师"
    DIALOGIST = "对话师"
    STRUCTURALIST = "结构师"


# ShotContractStatus is an alias — both meta_contract and shot_contracts share
# the same status lifecycle. The schema CHECK is identical for both tables.
ShotContractStatus = ContractStatus

# ── Smart-Redo levels ──

class RedoLevel(int, Enum):
    L0 = 0  # Retry same prompt
    L1 = 1  # Fast model retry
    L2 = 2  # Full redo with redo_model


# ── Gate thresholds ──

class LightThreshold(int, Enum):
    GREEN_MIN = 85
    YELLOW_MIN = 65
    # < 65 → RED


# ── Writer count ──

class WriterCount(int, Enum):
    MIN = 2
    MAX = 4
    DEFAULT = 2


# ── Jury personas ──

JURY_BASE_PERSONAS = [
    "契约官",   # Contract compliance
    "声音官",   # Voice consistency
    "衔接官",   # Hook/transition
    "禁元官",   # Anti-pattern / AI flavor detection
    "可读官",   # Readability
    "完整官",   # Shot completeness
]

JURY_DYNAMIC_PERSONAS = [
    "悬念官",   # Suspense
    "主题官",   # Theme
    "伏笔官",   # Foreshadow
    "弧线官",   # Character arc
    "状态官",   # Character state
    "对话官",   # Dialogue
    "身体官",   # Body moments
    "术语官",   # Terminology
]
