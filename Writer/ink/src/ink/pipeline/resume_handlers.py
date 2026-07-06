from __future__ import annotations

import sqlite3
from collections.abc import Callable, Mapping

from ink.core.llm_gateway import LLMGateway
from ink.errors import DataIntegrityError
from ink.pipeline.book_rolling_check_orchestrator import BookRollingCheckOrchestrator
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.pipeline.gate_orchestrator import GateOrchestrator
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.import_orchestrator import ImportOrchestrator
from ink.pipeline.jury_orchestrator import JuryOrchestrator
from ink.pipeline.polish_orchestrator import PolishOrchestrator
from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator


ResumeHandler = Callable[[str, int], object]
NonShotResumeHandler = Callable[[Mapping[str, object]], object]


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


def build_non_shot_resume_handlers(conn: sqlite3.Connection) -> dict[str, NonShotResumeHandler]:
    chapter_review = ChapterReviewOrchestrator(conn)
    book_check = BookRollingCheckOrchestrator(conn)
    import_orchestrator = ImportOrchestrator(conn)
    return {
        "chapter_review": lambda payload: chapter_review.review_chapter(
            _require_int(payload, "project_id"),
            _require_int(payload, "chapter_id"),
            _require_int(payload, "run_id"),
        ),
        "book_check": lambda payload: book_check.run_if_due(
            _require_int(payload, "project_id"),
            _require_int(payload, "up_to_chapter"),
        ),
        "import_finalize": lambda payload: import_orchestrator.finalize(
            _require_int(payload, "import_run_id"),
            actor=_require_text(payload, "actor"),
            reason=_require_text(payload, "reason"),
        ),
    }


def _merge_handlers(target: dict[str, ResumeHandler], incoming: Mapping[str, object]) -> None:
    for action, handler in incoming.items():
        if action in target:
            raise DataIntegrityError(f"duplicate resume handler: {action}")
        if not callable(handler):
            raise DataIntegrityError(f"resume handler is not callable: {action}")
        target[action] = handler


def _require_int(payload: Mapping[str, object], key: str) -> int:
    value = payload.get(key)
    if not isinstance(value, int) or isinstance(value, bool):
        raise DataIntegrityError(f"resume payload field must be an integer: {key}")
    return value


def _require_text(payload: Mapping[str, object], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        raise DataIntegrityError(f"resume payload field must be a non-empty string: {key}")
    return value
