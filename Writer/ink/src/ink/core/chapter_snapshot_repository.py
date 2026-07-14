from __future__ import annotations

import hashlib
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from itertools import count
from typing import Iterator

from ink.errors import (
    ConcurrentModificationError,
    DataIntegrityError,
    IllegalTransitionError,
    TerminalStateError,
)
from ink.time import now_utc_iso


_SAVEPOINT_IDS = count(1)


@dataclass(frozen=True)
class ChapterHead:
    project_id: int
    chapter_id: int
    active_snapshot_id: int
    version: int


@dataclass(frozen=True)
class RoundState:
    """Recovery-point snapshot of a Generation Round."""

    round_id: int
    status: str
    eligible_count: int
    call_count: int
    failure_reason: str | None
    initial_target_count: int
    supplement_target_count: int
    updated_at: str


# Generation Round state machine (implementation-contract.md §3.1).
# Keys = legal source status; values = legal target statuses.
# Superseded/failed are reachable only from non-terminal states.
_LEGAL_TRANSITIONS: dict[str, frozenset[str]] = {
    "planned": frozenset({"generating_initial"}),
    "generating_initial": frozenset({"validating_initial"}),
    "validating_initial": frozenset(
        {"supplementing", "initial_zero_pass", "ready_for_selection"}
    ),
    "supplementing": frozenset({"validating_supplement"}),
    "validating_supplement": frozenset(
        {"ready_for_selection", "candidate_shortage", "diversity_shortage"}
    ),
    "ready_for_selection": frozenset({"selecting"}),
    "selecting": frozenset({"selected"}),
}

_TERMINAL_STATES = frozenset(
    {
        "selected",
        "initial_zero_pass",
        "candidate_shortage",
        "diversity_shortage",
        "failed",
        "superseded",
    }
)


class ChapterSnapshotRepository:
    """Build, freeze, accept and read Scene-first chapter candidates."""

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def create_generation_round(
        self,
        *,
        project_id: int,
        chapter_id: int,
        round_number: int,
        outline_version_id: int | None = None,
        chapter_contract_version_id: int | None = None,
    ) -> int:
        now = now_utc_iso()
        cursor = self.conn.execute(
            """
            INSERT INTO writing_chapter_generation_rounds
                (project_id, chapter_id, outline_version_id,
                 chapter_contract_version_id, round_number, status,
                 created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, 'planned', ?, ?)
            """,
            (
                project_id,
                chapter_id,
                outline_version_id,
                chapter_contract_version_id,
                round_number,
                now,
                now,
            ),
        )
        return int(cursor.lastrowid)

    def create_branch(
        self,
        *,
        generation_round_id: int,
        candidate_index: int,
        writer_model: str,
        generation_strategy: str,
    ) -> int:
        cursor = self.conn.execute(
            """
            INSERT INTO writing_chapter_candidate_branches
                (generation_round_id, candidate_index, writer_model,
                 generation_strategy, status, created_at)
            VALUES (?, ?, ?, ?, 'generating', ?)
            """,
            (
                generation_round_id,
                candidate_index,
                writer_model,
                generation_strategy,
                now_utc_iso(),
            ),
        )
        return int(cursor.lastrowid)

    def create_branch_version(
        self,
        *,
        branch_id: int,
        version: int,
        parent_branch_version_id: int | None = None,
        outline_version_id: int | None = None,
        chapter_contract_version_id: int | None = None,
        world_snapshot_id: int | None = None,
        fact_snapshot_id: int | None = None,
    ) -> int:
        cursor = self.conn.execute(
            """
            INSERT INTO writing_chapter_candidate_branch_versions
                (branch_id, version, parent_branch_version_id, outline_version_id,
                 chapter_contract_version_id, world_snapshot_id, fact_snapshot_id,
                 status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'building', ?)
            """,
            (
                branch_id,
                version,
                parent_branch_version_id,
                outline_version_id,
                chapter_contract_version_id,
                world_snapshot_id,
                fact_snapshot_id,
                now_utc_iso(),
            ),
        )
        return int(cursor.lastrowid)

    def freeze_branch_version(self, branch_version_id: int) -> str:
        row = self.conn.execute(
            """
            SELECT status
            FROM writing_chapter_candidate_branch_versions
            WHERE branch_version_id = ?
            """,
            (branch_version_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"unknown branch version: {branch_version_id}")
        if str(row[0]) != "building":
            raise DataIntegrityError("branch version is already frozen")
        bindings = self._branch_bindings(branch_version_id)
        if not bindings:
            raise DataIntegrityError("cannot freeze a branch version without Scenes")
        content_hash = _bindings_hash(bindings)
        updated = self.conn.execute(
            """
            UPDATE writing_chapter_candidate_branch_versions
            SET status = 'frozen', content_hash = ?, frozen_at = ?
            WHERE branch_version_id = ? AND status = 'building'
            """,
            (content_hash, now_utc_iso(), branch_version_id),
        )
        if updated.rowcount != 1:
            raise ConcurrentModificationError("branch version changed while freezing")
        return content_hash

    def select_branch(self, branch_id: int) -> None:
        row = self.conn.execute(
            """
            SELECT b.generation_round_id, b.status,
                   EXISTS (
                       SELECT 1
                       FROM writing_chapter_candidate_branch_versions bv
                       WHERE bv.branch_id = b.branch_id AND bv.status = 'frozen'
                   )
            FROM writing_chapter_candidate_branches b
            WHERE b.branch_id = ?
            """,
            (branch_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"unknown branch: {branch_id}")
        if str(row[1]) not in {"eligible", "literary_review", "selected"}:
            raise DataIntegrityError("only an eligible or reviewed branch may be selected")
        if int(row[2]) != 1:
            raise DataIntegrityError("selected branch must have a frozen version")
        selected = self.conn.execute(
            """
            SELECT branch_id
            FROM writing_chapter_candidate_branches
            WHERE generation_round_id = ? AND status = 'selected'
            """,
            (int(row[0]),),
        ).fetchone()
        if selected is not None and int(selected[0]) != branch_id:
            raise DataIntegrityError("the generation round already has a selected branch")
        with _atomic(self.conn):
            self.conn.execute(
                """
                UPDATE writing_chapter_candidate_branches
                SET status = CASE WHEN branch_id = ? THEN 'selected' ELSE 'rejected' END
                WHERE generation_round_id = ?
                  AND status IN ('eligible','literary_review','selected','rejected')
                """,
                (branch_id, int(row[0])),
            )
            self.conn.execute(
                "UPDATE writing_chapter_candidate_branches SET status = 'selected' WHERE branch_id = ?",
                (branch_id,),
            )

    # ── Generation Round bounded state machine (implementation-contract.md §3.1) ──

    def transition_generation_round(
        self,
        *,
        round_id: int,
        to: str,
        expected_status: str,
        failure_reason: str | None = None,
    ) -> str:
        """Single state write entry point for Generation Rounds.

        Enforces the legal-transition table, terminal-state lock, and a
        compare-and-swap on ``expected_status``. Convenience methods
        (``mark_*`` / ``start_supplement`` / ``begin_selection`` /
        ``complete_selection``) delegate here and contain no UPDATE SQL.
        """
        self._assert_legal_transition(expected_status, to)
        now = now_utc_iso()
        updated = self.conn.execute(
            """
            UPDATE writing_chapter_generation_rounds
            SET status = ?, failure_reason = ?, updated_at = ?
            WHERE generation_round_id = ? AND status = ?
            """,
            (to, failure_reason, now, round_id, expected_status),
        )
        if updated.rowcount != 1:
            raise ConcurrentModificationError(
                f"generation round {round_id} changed while transitioning "
                f"{expected_status} -> {to}"
            )
        return to

    def record_eligible_branch(self, *, round_id: int, branch_id: int) -> None:
        """Mark a branch eligible and atomically bump the round's eligible_count.

        Both CAS steps run in one ``BEGIN IMMEDIATE`` transaction; if the
        branch CAS fails the round counter is not touched.
        """
        with _atomic(self.conn):
            now = now_utc_iso()
            branch_updated = self.conn.execute(
                """
                UPDATE writing_chapter_candidate_branches
                SET status = 'eligible'
                WHERE branch_id = ? AND status = 'validating'
                """,
                (branch_id,),
            )
            if branch_updated.rowcount != 1:
                raise ConcurrentModificationError(
                    f"branch {branch_id} is not in validating state"
                )
            count_row = self.conn.execute(
                """
                SELECT eligible_count
                FROM writing_chapter_generation_rounds
                WHERE generation_round_id = ?
                """,
                (round_id,),
            ).fetchone()
            if count_row is None:
                raise DataIntegrityError(f"unknown generation round: {round_id}")
            current_count = int(count_row[0])
            round_updated = self.conn.execute(
                """
                UPDATE writing_chapter_generation_rounds
                SET eligible_count = ?, updated_at = ?
                WHERE generation_round_id = ? AND eligible_count = ?
                """,
                (current_count + 1, now, round_id, current_count),
            )
            if round_updated.rowcount != 1:
                raise ConcurrentModificationError(
                    f"generation round {round_id} eligible_count changed concurrently"
                )

    def start_validating_branch(self, *, branch_id: int) -> None:
        """Advance a candidate branch from ``generating`` to ``validating``.

        CAS on the branch ``status``; rejects if the branch is not currently
        ``generating``. This is the entry the round driver uses before running
        hard-gate + jury review (which, if it passes, calls
        ``record_eligible_branch``).
        """
        with _atomic(self.conn):
            updated = self.conn.execute(
                """
                UPDATE writing_chapter_candidate_branches
                SET status = 'validating'
                WHERE branch_id = ? AND status = 'generating'
                """,
                (branch_id,),
            )
            if updated.rowcount != 1:
                row = self.conn.execute(
                    "SELECT status FROM writing_chapter_candidate_branches WHERE branch_id = ?",
                    (branch_id,),
                ).fetchone()
                if row is None:
                    raise DataIntegrityError(f"unknown branch: {branch_id}")
                raise ConcurrentModificationError(
                    f"branch {branch_id} is not in generating state (was {row[0]!r})"
                )

    def advance_to_literary_review(self, *, branch_id: int) -> None:
        """Advance an eligible branch into ``literary_review``.

        CAS on the branch ``status`` from ``eligible`` to ``literary_review``.
        Used by the round driver after a branch has passed validation, before
        the selection step. Rejects if the branch is not currently ``eligible``.
        """
        with _atomic(self.conn):
            updated = self.conn.execute(
                """
                UPDATE writing_chapter_candidate_branches
                SET status = 'literary_review'
                WHERE branch_id = ? AND status = 'eligible'
                """,
                (branch_id,),
            )
            if updated.rowcount != 1:
                row = self.conn.execute(
                    "SELECT status FROM writing_chapter_candidate_branches WHERE branch_id = ?",
                    (branch_id,),
                ).fetchone()
                if row is None:
                    raise DataIntegrityError(f"unknown branch: {branch_id}")
                raise ConcurrentModificationError(
                    f"branch {branch_id} is not in eligible state (was {row[0]!r})"
                )

    def mark_initial_zero_pass(self, *, round_id: int) -> None:
        self.transition_generation_round(
            round_id=round_id,
            to="initial_zero_pass",
            expected_status="validating_initial",
            failure_reason="initial batch passed zero candidates",
        )

    def mark_candidate_shortage(self, *, round_id: int, reason: str) -> None:
        if not reason:
            raise ValueError("candidate shortage requires a reason")
        self.transition_generation_round(
            round_id=round_id,
            to="candidate_shortage",
            expected_status="validating_supplement",
            failure_reason=reason,
        )

    def mark_diversity_shortage(self, *, round_id: int, reason: str) -> None:
        if not reason:
            raise ValueError("diversity shortage requires a reason")
        self.transition_generation_round(
            round_id=round_id,
            to="diversity_shortage",
            expected_status="validating_supplement",
            failure_reason=reason,
        )

    def mark_failed(self, *, round_id: int, reason: str, expected_status: str | None = None) -> None:
        if not reason:
            raise ValueError("failure requires a reason")
        if expected_status is None:
            row = self.conn.execute(
                "SELECT status FROM writing_chapter_generation_rounds WHERE generation_round_id = ?",
                (round_id,),
            ).fetchone()
            if row is None:
                raise DataIntegrityError(f"unknown generation round: {round_id}")
            expected_status = str(row[0])
        self.transition_generation_round(
            round_id=round_id,
            to="failed",
            expected_status=expected_status,
            failure_reason=reason,
        )

    def mark_superseded(self, *, round_id: int, expected_status: str | None = None) -> None:
        if expected_status is None:
            row = self.conn.execute(
                "SELECT status FROM writing_chapter_generation_rounds WHERE generation_round_id = ?",
                (round_id,),
            ).fetchone()
            if row is None:
                raise DataIntegrityError(f"unknown generation round: {round_id}")
            expected_status = str(row[0])
        self.transition_generation_round(
            round_id=round_id,
            to="superseded",
            expected_status=expected_status,
            failure_reason="superseded by newer round",
        )

    def start_supplement(self, *, round_id: int) -> None:
        self.transition_generation_round(
            round_id=round_id,
            to="supplementing",
            expected_status="validating_initial",
        )

    def begin_selection(self, *, round_id: int) -> None:
        state = self.get_generation_round_state(round_id=round_id)
        if state.eligible_count < 3:
            raise DataIntegrityError(
                f"ready_for_selection requires >=3 eligible, got {state.eligible_count}"
            )
        self.transition_generation_round(
            round_id=round_id,
            to="selecting",
            expected_status="ready_for_selection",
        )

    def complete_selection(self, *, round_id: int) -> None:
        self.transition_generation_round(
            round_id=round_id,
            to="selected",
            expected_status="selecting",
        )

    def increment_call_count(self, *, round_id: int, by: int = 1) -> int:
        if by < 0:
            raise ValueError("increment_call_count requires a non-negative delta")
        with _atomic(self.conn):
            row = self.conn.execute(
                """
                SELECT call_count
                FROM writing_chapter_generation_rounds
                WHERE generation_round_id = ?
                """,
                (round_id,),
            ).fetchone()
            if row is None:
                raise DataIntegrityError(f"unknown generation round: {round_id}")
            next_count = int(row[0]) + by
            self.conn.execute(
                """
                UPDATE writing_chapter_generation_rounds
                SET call_count = ?, updated_at = ?
                WHERE generation_round_id = ?
                """,
                (next_count, now_utc_iso(), round_id),
            )
            return next_count

    def get_generation_round_state(self, *, round_id: int) -> RoundState:
        row = self.conn.execute(
            """
            SELECT generation_round_id, status, eligible_count, call_count,
                   failure_reason, initial_target_count, supplement_target_count,
                   updated_at
            FROM writing_chapter_generation_rounds
            WHERE generation_round_id = ?
            """,
            (round_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"unknown generation round: {round_id}")
        return RoundState(
            round_id=int(row[0]),
            status=str(row[1]),
            eligible_count=int(row[2]),
            call_count=int(row[3]),
            failure_reason=None if row[4] is None else str(row[4]),
            initial_target_count=int(row[5]),
            supplement_target_count=int(row[6]),
            updated_at=str(row[7]),
        )

    @staticmethod
    def _assert_legal_transition(from_status: str, to_status: str) -> None:
        if to_status in _TERMINAL_STATES and from_status in _TERMINAL_STATES:
            raise TerminalStateError(
                f"terminal state {from_status} cannot transition to {to_status}"
            )
        if from_status in _TERMINAL_STATES:
            raise TerminalStateError(
                f"terminal state {from_status} cannot transition further"
            )
        legal_targets = _LEGAL_TRANSITIONS.get(from_status)
        # superseded / failed are reachable from any non-terminal status.
        if to_status in {"superseded", "failed"}:
            return
        if legal_targets is None or to_status not in legal_targets:
            raise IllegalTransitionError(
                f"illegal transition {from_status} -> {to_status}"
            )

    def accept_chapter(
        self,
        *,
        branch_version_id: int,
        expected_head_version: int,
        accepted_decision_id: int | None,
        require_decision_id: bool = True,
    ) -> ChapterHead:
        """Atomically snapshot a selected frozen branch and CAS the chapter head.

        When ``require_decision_id`` is True (default), a non-null
        ``accepted_decision_id`` is mandatory — the Scene-first Accept path
        always links the sealed Snapshot to the human decision that authorised it
        (INV-ACCEPT-004). Test-only callers that exercise legacy NULL semantics
        pass ``require_decision_id=False``.
        """

        if require_decision_id and accepted_decision_id is None:
            raise DataIntegrityError(
                "scene-first accept requires a non-null accepted_decision_id"
            )

        with _atomic(self.conn):
            row = self.conn.execute(
                """
                SELECT bv.status, bv.content_hash, bv.chapter_contract_version_id,
                       bv.world_snapshot_id, bv.fact_snapshot_id, b.status,
                       r.project_id, r.chapter_id
                FROM writing_chapter_candidate_branch_versions bv
                JOIN writing_chapter_candidate_branches b ON b.branch_id = bv.branch_id
                JOIN writing_chapter_generation_rounds r
                  ON r.generation_round_id = b.generation_round_id
                WHERE bv.branch_version_id = ?
                """,
                (branch_version_id,),
            ).fetchone()
            if row is None:
                raise DataIntegrityError(f"unknown branch version: {branch_version_id}")
            if str(row[0]) != "frozen" or not row[1]:
                raise DataIntegrityError("chapter accept requires a hash-bound frozen branch version")
            if str(row[5]) != "selected":
                raise DataIntegrityError("chapter accept requires the selected candidate branch")

            project_id = int(row[6])
            chapter_id = int(row[7])
            current = self.conn.execute(
                """
                SELECT active_snapshot_id, version
                FROM writing_chapter_heads
                WHERE project_id = ? AND chapter_id = ?
                """,
                (project_id, chapter_id),
            ).fetchone()
            actual_version = 0 if current is None else int(current[1])
            if actual_version != expected_head_version:
                raise ConcurrentModificationError(
                    f"chapter head version mismatch: expected {expected_head_version}, "
                    f"found {actual_version}"
                )

            bindings = self._branch_bindings(branch_version_id)
            snapshot_hash = _bindings_hash(bindings)
            if snapshot_hash != str(row[1]):
                raise DataIntegrityError("frozen branch content hash no longer matches its bindings")

            now = now_utc_iso()
            cursor = self.conn.execute(
                """
                INSERT INTO writing_chapter_snapshots
                    (project_id, chapter_id, source_branch_version_id,
                     chapter_contract_version_id, world_snapshot_id, fact_snapshot_id,
                     snapshot_hash, accepted_decision_id, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    project_id,
                    chapter_id,
                    branch_version_id,
                    row[2],
                    row[3],
                    row[4],
                    snapshot_hash,
                    accepted_decision_id,
                    now,
                ),
            )
            snapshot_id = int(cursor.lastrowid)
            self.conn.executemany(
                """
                INSERT INTO writing_chapter_snapshot_scenes
                    (snapshot_id, scene_order, scene_id, scene_revision_id)
                VALUES (?, ?, ?, ?)
                """,
                [
                    (snapshot_id, scene_order, scene_id, revision_id)
                    for scene_order, scene_id, revision_id, _ in bindings
                ],
            )
            self.conn.execute(
                "UPDATE writing_chapter_snapshots SET sealed_at = ? WHERE snapshot_id = ?",
                (now, snapshot_id),
            )

            next_version = expected_head_version + 1
            if current is None:
                try:
                    self.conn.execute(
                        """
                        INSERT INTO writing_chapter_heads
                            (project_id, chapter_id, active_snapshot_id, version, updated_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        (project_id, chapter_id, snapshot_id, next_version, now),
                    )
                except sqlite3.IntegrityError as exc:
                    raise ConcurrentModificationError(
                        "chapter head was created concurrently"
                    ) from exc
            else:
                updated = self.conn.execute(
                    """
                    UPDATE writing_chapter_heads
                    SET active_snapshot_id = ?, version = ?, updated_at = ?
                    WHERE project_id = ? AND chapter_id = ? AND version = ?
                    """,
                    (
                        snapshot_id,
                        next_version,
                        now,
                        project_id,
                        chapter_id,
                        expected_head_version,
                    ),
                )
                if updated.rowcount != 1:
                    raise ConcurrentModificationError("chapter head changed during accept")
            return ChapterHead(project_id, chapter_id, snapshot_id, next_version)

    def read_active_chapter_text(self, *, project_id: int, chapter_id: int) -> str:
        rows = self.conn.execute(
            """
            SELECT sr.text
            FROM writing_chapter_heads h
            JOIN writing_chapter_snapshots s
              ON s.snapshot_id = h.active_snapshot_id AND s.sealed_at IS NOT NULL
            JOIN writing_chapter_snapshot_scenes ss ON ss.snapshot_id = s.snapshot_id
            JOIN writing_scene_revisions sr ON sr.scene_revision_id = ss.scene_revision_id
            WHERE h.project_id = ? AND h.chapter_id = ?
            ORDER BY ss.scene_order
            """,
            (project_id, chapter_id),
        ).fetchall()
        if not rows:
            raise DataIntegrityError(f"no active Chapter Snapshot for {project_id}/{chapter_id}")
        return "\n\n".join(str(row[0]) for row in rows)

    def read_branch_version_text(self, branch_version_id: int) -> str:
        """Assemble a candidate branch's full chapter text by joining
        ``writing_branch_scenes`` → ``writing_scene_revisions`` in scene order.

        Used by the real-model Selection/Validation ports to feed candidate
        text to the jury LLM. The branch_version must be frozen (its scene
        bindings are immutable post-freeze — see ``freeze_branch_version``).
        """
        rows = self.conn.execute(
            """
            SELECT sr.text
            FROM writing_branch_scenes bs
            JOIN writing_scene_revisions sr
              ON sr.scene_revision_id = bs.scene_revision_id
             AND sr.scene_id = bs.scene_id
            WHERE bs.branch_version_id = ?
            ORDER BY bs.scene_order
            """,
            (branch_version_id,),
        ).fetchall()
        if not rows:
            raise DataIntegrityError(f"no scene bindings for branch_version {branch_version_id}")
        return "\n\n".join(str(row[0]) for row in rows)

    def frozen_branch_version_id(self, branch_id: int) -> int:
        """Latest ``status='frozen'`` branch_version for a branch."""
        row = self.conn.execute(
            """
            SELECT branch_version_id
            FROM writing_chapter_candidate_branch_versions
            WHERE branch_id = ? AND status = 'frozen'
            ORDER BY version DESC
            LIMIT 1
            """,
            (branch_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"no frozen branch_version for branch {branch_id}")
        return int(row[0])

    def _branch_bindings(
        self, branch_version_id: int
    ) -> list[tuple[int, int, int, str]]:
        rows = self.conn.execute(
            """
            SELECT bs.scene_order, bs.scene_id, bs.scene_revision_id, sr.text_hash
            FROM writing_branch_scenes bs
            JOIN writing_scene_revisions sr
              ON sr.scene_revision_id = bs.scene_revision_id
             AND sr.scene_id = bs.scene_id
            WHERE bs.branch_version_id = ?
            ORDER BY bs.scene_order
            """,
            (branch_version_id,),
        ).fetchall()
        return [
            (int(row[0]), int(row[1]), int(row[2]), str(row[3]))
            for row in rows
        ]


def _bindings_hash(bindings: list[tuple[int, int, int, str]]) -> str:
    payload = "".join(
        f"{scene_order}:{scene_id}:{revision_id}:{text_hash}\n"
        for scene_order, scene_id, revision_id, text_hash in bindings
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


@contextmanager
def _atomic(conn: sqlite3.Connection) -> Iterator[None]:
    if conn.in_transaction:
        name = f"ink_scene_accept_{next(_SAVEPOINT_IDS)}"
        conn.execute(f"SAVEPOINT {name}")
        try:
            yield
        except Exception:
            conn.execute(f"ROLLBACK TO SAVEPOINT {name}")
            conn.execute(f"RELEASE SAVEPOINT {name}")
            raise
        else:
            conn.execute(f"RELEASE SAVEPOINT {name}")
        return

    conn.execute("BEGIN IMMEDIATE")
    try:
        yield
    except Exception:
        conn.rollback()
        raise
    else:
        conn.commit()
