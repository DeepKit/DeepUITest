"""Services module — lazy imports to avoid pulling all dependencies on single-command CLI startup."""

from __future__ import annotations

import importlib
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .session_manager import SessionManager
    from .contract_compiler import ContractCompiler
    from .prompt_compiler import PromptCompiler
    from .writer_dispatcher import WriterDispatcher
    from .jury_service import JuryService
    from .quality_controller import QualityController
    from .fact_anchor_extractor import FactAnchorExtractor
    from .motif_tracker import MotifTracker
    from .model_client import (
        ModelClient,
        ModelRequest,
        ModelResponse,
        LocalDefaultGenerator,
        create_model_client,
    )
    from .architect_gate import ArchitectGate
    from .outline_evaluator import OutlineEvaluator
    from .book_constitution import BookConstitutionService
    from .volume_rhythm import VolumeRhythmService
    from .text_repository import TextRepository
    from .style_preference import StylePreferenceService
    from .anti_contract import AntiContractSandbox
    from .polish_service import PolishService
    from .retry_budget import RetryBudgetService, RetryBudgetExhausted, CircuitBreakerTriggered, classify_failure_type

_LAZY_MAP = {
    "SessionManager": "session_manager",
    "ContractCompiler": "contract_compiler",
    "PromptCompiler": "prompt_compiler",
    "WriterDispatcher": "writer_dispatcher",
    "JuryService": "jury_service",
    "QualityController": "quality_controller",
    "FactAnchorExtractor": "fact_anchor_extractor",
    "MotifTracker": "motif_tracker",
    "ArchitectGate": "architect_gate",
    "OutlineEvaluator": "outline_evaluator",
    "BookConstitutionService": "book_constitution",
    "VolumeRhythmService": "volume_rhythm",
    "TextRepository": "text_repository",
    "StylePreferenceService": "style_preference",
    "AntiContractSandbox": "anti_contract",
    "PolishService": "polish_service",
    "RetryBudgetService": "retry_budget",
    "RetryBudgetExhausted": "retry_budget",
    "CircuitBreakerTriggered": "retry_budget",
    "classify_failure_type": "retry_budget",
    "ModelClient": "model_client",
    "ModelRequest": "model_client",
    "ModelResponse": "model_client",
    "LocalDefaultGenerator": "model_client",
    "create_model_client": "model_client",
}

__all__ = list(_LAZY_MAP.keys())


def __getattr__(name: str):
    if name in _LAZY_MAP:
        mod = importlib.import_module(f".{_LAZY_MAP[name]}", __name__)
        cls = getattr(mod, name)
        globals()[name] = cls
        return cls
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
