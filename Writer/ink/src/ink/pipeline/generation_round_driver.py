"""Generation Round driver — the thin scheduler that advances a Generation
Round from ``planned`` to a terminal state by delegating the real work
(LLM generation, hard-gate + jury validation, literary selection) to
injectable ports.

This is a **shadow-layer** module (spec
``docs/superpowers/specs/2026-07-14-generation-round-state-machine-design.md``
§11). It does **not**:

- import or call ``LLMGateway`` / ``WriteOrchestrator`` / ``JuryOrchestrator``
  / ``HardGateOrchestrator`` directly — real-model wiring is provided by
  separate Protocol implementations.
- touch the CLI.
- switch the legacy Shot production path.

Substantive-difference and literary-absolute-threshold judgements are delegated
to ``SelectionPort``. The driver owns every round/branch selection state write;
ports generate evidence or return a decision only.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from typing import Protocol, runtime_checkable

from ink.core.chapter_snapshot_repository import (
    ChapterSnapshotRepository,
    RoundState,
)
from ink.errors import DataIntegrityError

# Round statuses (mirror implementation-contract.md §3.1 / _LEGAL_TRANSITIONS).
_TERMINAL = frozenset(
    {
        "selected",
        "initial_zero_pass",
        "candidate_shortage",
        "diversity_shortage",
        "failed",
        "superseded",
    }
)


@dataclass(frozen=True)
class RoundOutcome:
    """Final result of driving a Generation Round."""

    round_id: int
    final_status: str
    failure_reason: str | None
    eligible_count: int
    call_count: int


@runtime_checkable
class GenerationPort(Protocol):
    """Produce one candidate branch.

    Implementations create the branch + its first branch_version + scene
    bindings + freeze, then call ``repo.start_validating_branch`` so the
    branch is ready for validation. Returns the branch_id.
    """

    def generate_candidate(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
        candidate_index: int,
    ) -> int: ...


@runtime_checkable
class ValidationPort(Protocol):
    """Validate one candidate (hard gate + jury).

    On pass: call ``repo.record_eligible_branch`` (which atomically bumps
    ``eligible_count`` and moves the branch to ``eligible``) and optionally
    ``repo.advance_to_literary_review``. On fail: leave the branch where it is
    (the driver does not track per-branch failure states beyond eligible
    count). Returns whether the branch passed validation.
    """

    def validate_candidate(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
        branch_id: int,
    ) -> bool: ...


@runtime_checkable
class SelectionPort(Protocol):
    """Judge substantive difference and return a winning branch id.

    Implementations run the literary evidence calls but must not mutate branch
    or round status. The driver is the single state-writing owner.
    """

    def has_substantive_difference(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
    ) -> bool: ...

    def select_winner(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
    ) -> int: ...


class GenerationRoundDriver:
    """Idempotent scheduler for a Generation Round.

    ``drive`` reads the current ``RoundState`` and resumes from wherever the
    round is — so a round interrupted mid-way (e.g. by a crash or the call
    budget) can be driven again. Already-terminal rounds return immediately.

    Parameters
    ----------
    call_budget:
        Hard ceiling on ``call_count``. When the round's call_count reaches
        it after a generation step, the round is driven to ``failed``. ``None``
        means no circuit breaker (INV-ROUND-016 only fires when a budget is
        set).
    """

    def __init__(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        generation_port: GenerationPort,
        validation_port: ValidationPort,
        selection_port: SelectionPort,
        call_budget: int | None = None,
    ) -> None:
        self._conn = conn
        self._repo = repo
        self._generation = generation_port
        self._validation = validation_port
        self._selection = selection_port
        self._call_budget = call_budget

    def drive(self, *, round_id: int) -> RoundOutcome:
        state = self._repo.get_generation_round_state(round_id=round_id)
        if state.status in _TERMINAL:
            return self._outcome(state)

        try:
            if state.status == "planned":
                self._repo.transition_generation_round(
                    round_id=round_id, to="generating_initial", expected_status="planned"
                )

            state = self._repo.get_generation_round_state(round_id=round_id)
            if state.status == "generating_initial":
                self._generate_initial(round_id=round_id, state=state)
                self._repo.transition_generation_round(
                    round_id=round_id,
                    to="validating_initial",
                    expected_status="generating_initial",
                )

            state = self._repo.get_generation_round_state(round_id=round_id)
            if state.status == "validating_initial":
                outcome = self._validate_initial(round_id=round_id, state=state)
                if outcome is not None:
                    return outcome

            state = self._repo.get_generation_round_state(round_id=round_id)
            if state.status == "supplementing":
                self._generate_supplement(round_id=round_id, state=state)
                self._repo.transition_generation_round(
                    round_id=round_id,
                    to="validating_supplement",
                    expected_status="supplementing",
                )

            state = self._repo.get_generation_round_state(round_id=round_id)
            if state.status == "validating_supplement":
                outcome = self._validate_supplement(round_id=round_id, state=state)
                if outcome is not None:
                    return outcome

            state = self._repo.get_generation_round_state(round_id=round_id)
            if state.status in ("ready_for_selection", "selecting"):
                return self._do_selection(round_id=round_id, state=state)

            # Should not reach here: every non-terminal status is handled above.
            raise DataIntegrityError(
                f"round {round_id} stalled in unexpected status {state.status!r}"
            )
        except _CallBudgetReached:
            # The failing branch already called mark_failed; return the outcome.
            state = self._repo.get_generation_round_state(round_id=round_id)
            return self._outcome(state)
        except Exception as exc:
            state = self._repo.get_generation_round_state(round_id=round_id)
            if state.status not in _TERMINAL:
                self._repo.mark_failed(
                    round_id=round_id,
                    expected_status=state.status,
                    reason=f"{type(exc).__name__}: {exc}",
                )
                return self._outcome(
                    self._repo.get_generation_round_state(round_id=round_id)
                )
            raise

    # ── generation steps ──

    def _generate_initial(self, *, round_id: int, state: RoundState) -> None:
        for index in range(1, state.initial_target_count + 1):
            self._generate_one(round_id=round_id, candidate_index=index)

    def _generate_supplement(self, *, round_id: int, state: RoundState) -> None:
        # candidate_index continues after the initial batch.
        for index in range(
            state.initial_target_count + 1,
            state.initial_target_count + state.supplement_target_count + 1,
        ):
            self._generate_one(round_id=round_id, candidate_index=index)

    def _generate_one(self, *, round_id: int, candidate_index: int) -> None:
        branch_id = self._generation.generate_candidate(
            self._conn,
            self._repo,
            round_id=round_id,
            candidate_index=candidate_index,
        )
        calls = self._repo.increment_call_count(round_id=round_id, by=1)
        if self._call_budget is not None and calls >= self._call_budget:
            self._repo.mark_failed(
                round_id=round_id,
                reason=f"call_count reached budget {self._call_budget}",
            )
            raise _CallBudgetReached(round_id)

    # ── validation steps ──

    def _validate_initial(
        self, *, round_id: int, state: RoundState
    ) -> RoundOutcome | None:
        self._validate_pending(round_id=round_id, state=state)
        state = self._repo.get_generation_round_state(round_id=round_id)

        if state.eligible_count == 0:
            self._repo.mark_initial_zero_pass(round_id=round_id)
            return self._outcome(self._repo.get_generation_round_state(round_id=round_id))

        if state.eligible_count >= 3:
            self._repo.transition_generation_round(
                round_id=round_id,
                to="ready_for_selection",
                expected_status="validating_initial",
            )
            return None

        # 1 or 2 eligible -> supplement once.
        self._repo.start_supplement(round_id=round_id)
        return None

    def _validate_supplement(
        self, *, round_id: int, state: RoundState
    ) -> RoundOutcome | None:
        self._validate_pending(round_id=round_id, state=state)
        state = self._repo.get_generation_round_state(round_id=round_id)

        if state.eligible_count < 3:
            self._repo.mark_candidate_shortage(
                round_id=round_id,
                reason=f"only {state.eligible_count} eligible after supplement",
            )
            return self._outcome(self._repo.get_generation_round_state(round_id=round_id))

        if not self._selection.has_substantive_difference(
            self._conn, self._repo, round_id=round_id
        ):
            self._repo.mark_diversity_shortage(
                round_id=round_id,
                reason="eligible candidates lack substantive difference",
            )
            return self._outcome(self._repo.get_generation_round_state(round_id=round_id))

        self._repo.transition_generation_round(
            round_id=round_id,
            to="ready_for_selection",
            expected_status="validating_supplement",
        )
        return None

    def _validate_pending(self, *, round_id: int, state: RoundState) -> None:
        """Run validation on every branch still in 'validating'."""
        rows = self._conn.execute(
            """
            SELECT branch_id, candidate_index
            FROM writing_chapter_candidate_branches
            WHERE generation_round_id = ? AND status = 'validating'
            ORDER BY candidate_index
            """,
            (round_id,),
        ).fetchall()
        for branch_id, _index in rows:
            self._validation.validate_candidate(
                self._conn,
                self._repo,
                round_id=round_id,
                branch_id=int(branch_id),
            )

    # ── selection ──

    def _do_selection(self, *, round_id: int, state: RoundState) -> RoundOutcome:
        if state.status == "ready_for_selection":
            self._repo.begin_selection(round_id=round_id)
        winner = self._selection.select_winner(
            self._conn, self._repo, round_id=round_id
        )
        # select_branch marks the winner 'selected' and others 'rejected'.
        self._repo.select_branch(winner)
        self._repo.complete_selection(round_id=round_id)
        return self._outcome(self._repo.get_generation_round_state(round_id=round_id))

    # ── helpers ──

    def _outcome(self, state: RoundState) -> RoundOutcome:
        return RoundOutcome(
            round_id=state.round_id,
            final_status=state.status,
            failure_reason=state.failure_reason,
            eligible_count=state.eligible_count,
            call_count=state.call_count,
        )


class _CallBudgetReached(Exception):
    """Internal signal that the call budget was hit mid-batch."""

    def __init__(self, round_id: int) -> None:
        super().__init__(f"call budget reached for round {round_id}")
        self.round_id = round_id
