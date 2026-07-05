from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from typing import Literal

from ink.core.retry_budget import SoftGateCounter
from ink.core.state_machine import load_status, transition
from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


GateClass = Literal["soft", "quality_blocking"]
GateAction = Literal["pass", "block", "redo", "failed", "diagnostic", "redo_in_progress"]


@dataclass(frozen=True)
class GateFailure:
    gate_name: str
    gate_class: GateClass
    n: int
    level: int
    detail: str


@dataclass(frozen=True)
class GateResult:
    passed: bool
    action: GateAction
    failures: tuple[GateFailure, ...] = ()


def run_soft_gates(shot_id: str, run_id: int) -> GateResult:
    raise DataIntegrityError("gate orchestrator is not configured")


class GateOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn
        self.counter = SoftGateCounter(conn)

    def run_soft_gates(self, shot_id: str, run_id: int) -> GateResult:
        context = _load_context(self.conn, shot_id, run_id)
        if context.status != "winner_selected":
            raise DataIntegrityError(f"soft gates require winner_selected, got: {context.status}")
        if context.redo_in_progress:
            return GateResult(passed=False, action="redo_in_progress")

        checks = _evaluate_soft_gates(context.winner_text)
        try:
            self.conn.execute("SAVEPOINT soft_gate_orchestrator")
            if not checks:
                for gate_name in _KNOWN_GATE_NAMES:
                    self.counter.reset(context.project_id, context.logical_shot_id, gate_name)
                _sync_counter_snapshot(self.conn, context)
                result = GateResult(passed=True, action="pass")
            else:
                failures = tuple(self._record_failed_check(context, check) for check in checks)
                _sync_counter_snapshot(self.conn, context)
                result = self._apply_failure_action(context, failures)
        except Exception:
            self.conn.execute("ROLLBACK TO soft_gate_orchestrator")
            self.conn.execute("RELEASE soft_gate_orchestrator")
            raise
        else:
            self.conn.execute("RELEASE soft_gate_orchestrator")
            return result

    def resume_handlers(self) -> dict[str, object]:
        return {"rerun_soft_gate": self.run_soft_gates}

    def _record_failed_check(self, context: "_GateContext", check: "_GateCheck") -> GateFailure:
        n = self.counter.increment(context.project_id, context.logical_shot_id, check.gate_name)
        level = self.counter.get_level(context.project_id, context.logical_shot_id, check.gate_name)
        failure = GateFailure(
            gate_name=check.gate_name,
            gate_class=check.gate_class,
            n=n,
            level=level,
            detail=check.detail,
        )
        _insert_failure_attribution(self.conn, context, failure)
        return failure

    def _apply_failure_action(self, context: "_GateContext", failures: tuple[GateFailure, ...]) -> GateResult:
        if any(failure.gate_class == "quality_blocking" and failure.level >= 3 for failure in failures):
            transition(self.conn, context.shot_id, context.run_id, "winner_selected", "failed")
            return GateResult(passed=False, action="failed", failures=failures)
        if any(failure.level == 2 for failure in failures):
            _mark_redo_in_progress(self.conn, context, failures)
            return GateResult(passed=False, action="redo", failures=failures)
        if all(failure.gate_class == "soft" and failure.level >= 3 for failure in failures):
            return GateResult(passed=True, action="diagnostic", failures=failures)
        return GateResult(passed=False, action="block", failures=failures)


class _GateContext:
    def __init__(
        self,
        *,
        shot_id: str,
        run_id: int,
        project_id: int,
        logical_shot_id: str,
        status: str,
        redo_in_progress: bool,
        winner_draft_id: int,
        winner_text: str,
    ) -> None:
        self.shot_id = shot_id
        self.run_id = run_id
        self.project_id = project_id
        self.logical_shot_id = logical_shot_id
        self.status = status
        self.redo_in_progress = redo_in_progress
        self.winner_draft_id = winner_draft_id
        self.winner_text = winner_text


@dataclass(frozen=True)
class _GateCheck:
    gate_name: str
    gate_class: GateClass
    detail: str


_KNOWN_GATE_NAMES = ("reader_pull", "chapter_hook")


def _load_context(conn: sqlite3.Connection, shot_id: str, run_id: int) -> _GateContext:
    status = load_status(conn, shot_id, run_id)
    row = conn.execute(
        """
        SELECT s.project_id, s.logical_shot_id, s.redo_in_progress, d.draft_id, d.text
        FROM writing_shots s
        JOIN writing_jury_aggregates a ON a.shot_id = s.shot_id AND a.is_winner = 1
        JOIN writing_drafts d ON d.draft_id = a.draft_id
        WHERE s.shot_id = ? AND s.run_id = ?
        """,
        (shot_id, run_id),
    ).fetchone()
    if status is None or row is None:
        raise DataIntegrityError(f"soft gate context not found: {shot_id}/{run_id}")
    return _GateContext(
        shot_id=shot_id,
        run_id=run_id,
        project_id=int(row[0]),
        logical_shot_id=str(row[1]),
        status=status,
        redo_in_progress=bool(row[2]),
        winner_draft_id=int(row[3]),
        winner_text=str(row[4]),
    )


def _evaluate_soft_gates(winner_text: str) -> tuple[_GateCheck, ...]:
    checks: list[_GateCheck] = []
    if "[soft-fail]" in winner_text:
        checks.append(
            _GateCheck(
                gate_name="reader_pull",
                gate_class="soft",
                detail="reader pull soft gate failed",
            )
        )
    if "[quality-blocking]" in winner_text:
        checks.append(
            _GateCheck(
                gate_name="chapter_hook",
                gate_class="quality_blocking",
                detail="chapter hook quality gate failed",
            )
        )
    return tuple(checks)


def _insert_failure_attribution(conn: sqlite3.Connection, context: _GateContext, failure: GateFailure) -> None:
    conn.execute(
        """
        INSERT INTO writing_failure_attributions
            (draft_id, shot_id, failure_category, failure_level, gate_name,
             soft_gate_n, failure_detail, degraded, created_at)
        VALUES (?, ?, ?, 'soft_gate', ?, ?, ?, 0, ?)
        """,
        (
            context.winner_draft_id,
            context.shot_id,
            failure.gate_class,
            failure.gate_name,
            failure.n,
            json.dumps(
                {"detail": failure.detail, "level": failure.level},
                ensure_ascii=False,
                sort_keys=True,
            ),
            now_utc_iso(),
        ),
    )


def _sync_counter_snapshot(conn: sqlite3.Connection, context: _GateContext) -> None:
    rows = conn.execute(
        """
        SELECT gate_name, n
        FROM writing_soft_gate_counters
        WHERE project_id = ? AND logical_shot_id = ?
        ORDER BY gate_name
        """,
        (context.project_id, context.logical_shot_id),
    ).fetchall()
    snapshot = {str(row[0]): int(row[1]) for row in rows if int(row[1]) > 0}
    conn.execute(
        """
        UPDATE writing_shots
        SET soft_fail_counts_snapshot = ?, updated_at = ?
        WHERE shot_id = ? AND run_id = ?
        """,
        (json.dumps(snapshot, ensure_ascii=False, sort_keys=True), now_utc_iso(), context.shot_id, context.run_id),
    )


def _mark_redo_in_progress(conn: sqlite3.Connection, context: _GateContext, failures: tuple[GateFailure, ...]) -> None:
    resume_point = {
        "phase": "soft_gate",
        "gate_names": [failure.gate_name for failure in failures if failure.level == 2],
    }
    cursor = conn.execute(
        """
        UPDATE writing_shots
        SET redo_in_progress = 1, resume_point = ?, updated_at = ?
        WHERE shot_id = ? AND run_id = ? AND redo_in_progress = 0
        """,
        (
            json.dumps(resume_point, ensure_ascii=False, sort_keys=True),
            now_utc_iso(),
            context.shot_id,
            context.run_id,
        ),
    )
    if cursor.rowcount != 1:
        raise DataIntegrityError(f"could not mark redo_in_progress for soft gate: {context.shot_id}")
