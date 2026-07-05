from __future__ import annotations

import sqlite3
from collections.abc import Callable, Mapping

from ink.core.llm_gateway import LLMGateway
from ink.errors import DataIntegrityError
from ink.pipeline.gate_orchestrator import GateOrchestrator
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.jury_orchestrator import JuryOrchestrator
from ink.pipeline.polish_orchestrator import PolishOrchestrator
from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator


ResumeHandler = Callable[[str, int], object]


def build_shot_resume_handlers(
    conn: sqlite3.Connection,
    gateway: LLMGateway | None = None,
) -> dict[str, ResumeHandler]:
    handlers: dict[str, ResumeHandler] = {}
    orchestrators = (
        PreDraftingOrchestrator(conn, gateway),
        WriteOrchestrator(conn, gateway),
        HardGateOrchestrator(conn),
        JuryOrchestrator(conn),
        GateOrchestrator(conn),
        PolishOrchestrator(conn, gateway),
    )
    for orchestrator in orchestrators:
        _merge_handlers(handlers, orchestrator.resume_handlers())
    return handlers


def _merge_handlers(target: dict[str, ResumeHandler], incoming: Mapping[str, object]) -> None:
    for action, handler in incoming.items():
        if action in target:
            raise DataIntegrityError(f"duplicate resume handler: {action}")
        if not callable(handler):
            raise DataIntegrityError(f"resume handler is not callable: {action}")
        target[action] = handler
