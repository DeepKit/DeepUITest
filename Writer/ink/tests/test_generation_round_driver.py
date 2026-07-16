from __future__ import annotations

import sqlite3

import pytest

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.pipeline.generation_round_driver import (
    GenerationPort,
    GenerationRoundDriver,
    RoundOutcome,
    SelectionPort,
    ValidationPort,
)
from factories import NOW, insert_contract_approve_reviews, make_schema_db


# ── shared harness ──

def _repo() -> tuple[sqlite3.Connection, ChapterSnapshotRepository, int]:
    """Build a project + one generation round (status='planned')."""
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'round', 'Round',
                '["writer-a","writer-b","writer-c"]',
                '["judge-a","judge-b","judge-c"]', ?)
        """,
        (NOW,),
    )
    snapshots = ChapterSnapshotRepository(conn)
    round_id = snapshots.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    return conn, snapshots, round_id


class StubGenerationPort:
    """Creates a branch with one frozen branch_version + one scene binding,
    then moves the branch to 'validating' so ValidationPort can run.

    No LLM call. Records the branch_ids it created, in order.
    """

    def __init__(self) -> None:
        self.created: list[int] = []

    def generate_candidate(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
        candidate_index: int,
    ) -> int:
        branch_id = repo.create_branch(
            generation_round_id=round_id,
            candidate_index=candidate_index,
            writer_model="writer-a",
            generation_strategy="stub",
        )
        # select_branch (Repository) hard-requires a frozen branch_version, so
        # the stub must build the minimal scene→revision→branch_version→binding
        # chain and freeze it. Real generation (LLM text, real contracts) is
        # the GenerationPort implementer's job, wired in a later task.
        _seed_frozen_version(conn, repo, branch_id=branch_id, version=1)
        repo.start_validating_branch(branch_id=branch_id)
        self.created.append(branch_id)
        return branch_id


class StubValidationPort:
    """Marks branches whose candidate_index is in ``eligible_indices`` as
    eligible (record_eligible_branch + advance_to_literary_review). Others
    are left in 'validating' (treated as failed validation)."""

    def __init__(self, eligible_indices: set[int]) -> None:
        self._eligible = eligible_indices

    def validate_candidate(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
        branch_id: int,
    ) -> bool:
        row = conn.execute(
            "SELECT candidate_index FROM writing_chapter_candidate_branches "
            "WHERE branch_id = ?",
            (branch_id,),
        ).fetchone()
        index = int(row[0])
        if index in self._eligible:
            repo.record_eligible_branch(round_id=round_id, branch_id=branch_id)
            repo.advance_to_literary_review(branch_id=branch_id)
            return True
        return False


class StubSelectionPort:
    """Selects the lowest-candidate_index eligible branch.

    ``has_substantive_difference`` returns the configured flag (default True);
    when False, the driver routes to diversity_shortage."""

    def __init__(self, *, substantive: bool = True) -> None:
        self._substantive = substantive

    def has_substantive_difference(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
    ) -> bool:
        return self._substantive

    def select_winner(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
    ) -> int:
        row = conn.execute(
            "SELECT branch_id FROM writing_chapter_candidate_branches "
            "WHERE generation_round_id = ? AND status = 'literary_review' "
            "ORDER BY candidate_index LIMIT 1",
            (round_id,),
        ).fetchone()
        return int(row[0])


def _seed_frozen_version(
    conn: sqlite3.Connection,
    repo: ChapterSnapshotRepository,
    *,
    branch_id: int,
    version: int,
) -> None:
    """Build the minimal scene→revision→branch_version→binding chain and
    freeze it, so ``select_branch`` (which requires a frozen version) accepts
    the branch. The shared scene/contract/revision trio is seeded once."""
    cur = conn.execute("SELECT 1 FROM writing_scenes WHERE scene_id = 1").fetchone()
    if cur is None:
        conn.execute(
            """
            INSERT INTO writing_scenes
                (scene_id, project_id, chapter_id, logical_scene_key,
                 scene_order, created_at)
            VALUES (1, 1, 1, 's1', 0, ?)
            """,
            (NOW,),
        )
        conn.execute(
            """
            INSERT INTO writing_scene_contracts
                (scene_contract_id, scene_id, version, status, contract_hash,
                 source_bundle_hash, created_by, created_at)
            VALUES (1, 1, 1, 'approved', 'h1', 'b1', 'stub', ?)
            """,
            (NOW,),
        )
        for layer, key in (
            ("hard_constraint", "hard-1"),
            ("source_dna", "source-1"),
            ("soft_goal", "soft-1"),
            ("creative_opening", "opening-1"),
            ("creative_opening", "opening-2"),
        ):
            conn.execute(
                """
                INSERT INTO writing_scene_contract_clauses
                    (scene_contract_id, layer, clause_key, clause_text, severity,
                     authority_rank, created_at)
                VALUES (1, ?, ?, 'text', 'hard', 10, ?)
                """,
                (layer, key, NOW),
            )
        insert_contract_approve_reviews(conn, 1)
        conn.execute(
            "UPDATE writing_scene_contracts SET status = 'active', activated_at = ? "
            "WHERE scene_contract_id = 1",
            (NOW,),
        )
        conn.execute(
            """
            INSERT INTO writing_scene_revisions
                (scene_revision_id, scene_id, scene_contract_id, text, text_hash,
                 actor_type, actor_id, change_reason, created_at)
            VALUES (1, 1, 1, 'stub prose', 'rh1', 'ai', 'stub', 'seed', ?)
            """,
            (NOW,),
        )
    bv_id = repo.create_branch_version(branch_id=branch_id, version=version)
    conn.execute(
        """
        INSERT INTO writing_branch_scenes
            (branch_version_id, scene_order, scene_id, scene_revision_id)
        VALUES (?, 0, 1, 1)
        """,
        (bv_id,),
    )
    repo.freeze_branch_version(bv_id)


def _drive(
    conn: sqlite3.Connection,
    repo: ChapterSnapshotRepository,
    round_id: int,
    *,
    eligible_indices: set[int],
    substantive: bool = True,
    call_budget: int | None = None,
) -> RoundOutcome:
    driver = GenerationRoundDriver(
        conn,
        repo,
        generation_port=StubGenerationPort(),
        validation_port=StubValidationPort(eligible_indices),
        selection_port=StubSelectionPort(substantive=substantive),
        call_budget=call_budget,
    )
    return driver.drive(round_id=round_id)


# ── INV-ROUND-011: full path planned -> selected ──

def test_driver_advances_planned_to_selected():
    conn, repo, round_id = _repo()
    # initial batch = 2 (indices 1,2); make both eligible, then supplement
    # adds 3 more (indices 3,4,5) of which index 3 also passes -> 3 eligible.
    outcome = _drive(conn, repo, round_id, eligible_indices={1, 2, 3})
    assert outcome.final_status == "selected"
    assert outcome.eligible_count == 3
    # winning branch is the lowest-index eligible (index 1).
    winner = conn.execute(
        "SELECT candidate_index FROM writing_chapter_candidate_branches "
        "WHERE generation_round_id = ? AND status = 'selected'",
        (round_id,),
    ).fetchone()
    assert int(winner[0]) == 1


# ── INV-ROUND-012: 0 eligible in initial -> initial_zero_pass ──

def test_driver_initial_zero_pass_on_zero_eligible():
    conn, repo, round_id = _repo()
    outcome = _drive(conn, repo, round_id, eligible_indices=set())
    assert outcome.final_status == "initial_zero_pass"
    assert outcome.eligible_count == 0
    # no supplement batch was created (still only 2 branches).
    count = conn.execute(
        "SELECT COUNT(*) FROM writing_chapter_candidate_branches "
        "WHERE generation_round_id = ?",
        (round_id,),
    ).fetchone()[0]
    assert count == 2


# ── INV-ROUND-013: 1-2 eligible -> supplement 3 more ──

def test_driver_supplements_when_partial_initial_pass():
    conn, repo, round_id = _repo()
    # index 1 passes in initial; supplement indices 3,4,5 — make 3 pass too.
    outcome = _drive(conn, repo, round_id, eligible_indices={1, 3, 4, 5})
    assert outcome.final_status == "selected"
    assert outcome.eligible_count == 4
    # exactly 5 branches total (2 initial + 3 supplement), proving supplement ran.
    count = conn.execute(
        "SELECT COUNT(*) FROM writing_chapter_candidate_branches "
        "WHERE generation_round_id = ?",
        (round_id,),
    ).fetchone()[0]
    assert count == 5


# ── INV-ROUND-014: after supplement, <3 eligible -> candidate_shortage ──

def test_driver_candidate_shortage_after_supplement():
    conn, repo, round_id = _repo()
    # index 1 passes initial (1 eligible) -> supplement. In supplement only
    # index 3 passes -> total 2 < 3 -> candidate_shortage.
    outcome = _drive(conn, repo, round_id, eligible_indices={1, 3})
    assert outcome.final_status == "candidate_shortage"
    assert outcome.eligible_count == 2
    assert "2 eligible after supplement" in (outcome.failure_reason or "")


# ── INV-ROUND-015: >=3 eligible but no substantive difference -> diversity_shortage ──

def test_driver_diversity_shortage_when_no_substantive_difference():
    conn, repo, round_id = _repo()
    outcome = _drive(
        conn, repo, round_id, eligible_indices={1, 2, 3}, substantive=False
    )
    assert outcome.final_status == "diversity_shortage"
    assert outcome.eligible_count == 3
    assert "substantive difference" in (outcome.failure_reason or "")


# ── INV-ROUND-016: call_count budget -> failed ──

def test_driver_call_count_circuit_breaker():
    conn, repo, round_id = _repo()
    # budget of 1: the very first generate_candidate trips the breaker.
    outcome = _drive(conn, repo, round_id, eligible_indices={1, 2, 3}, call_budget=1)
    assert outcome.final_status == "failed"
    assert outcome.call_count == 1
    assert "budget" in (outcome.failure_reason or "")


def test_driver_seals_port_exception_as_failed_terminal():
    conn, repo, round_id = _repo()

    class FailingGenerationPort:
        def generate_candidate(self, conn, repo, *, round_id, candidate_index):
            raise RuntimeError("provider unavailable")

    outcome = GenerationRoundDriver(
        conn,
        repo,
        generation_port=FailingGenerationPort(),
        validation_port=StubValidationPort(set()),
        selection_port=StubSelectionPort(),
    ).drive(round_id=round_id)

    assert outcome.final_status == "failed"
    assert "RuntimeError: provider unavailable" in (outcome.failure_reason or "")


# ── INV-ROUND-017: idempotent resume from intermediate state ──

def test_driver_resumes_from_intermediate_state():
    conn, repo, round_id = _repo()
    # Manually walk the round to validating_initial with 2 branches already in
    # 'validating' (as if generation ran and crashed before validation).
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    repo.transition_generation_round(
        round_id=round_id, to="validating_initial", expected_status="generating_initial"
    )
    gen = StubGenerationPort()
    gen.generate_candidate(conn, repo, round_id=round_id, candidate_index=1)
    gen.generate_candidate(conn, repo, round_id=round_id, candidate_index=2)
    repo.increment_call_count(round_id=round_id, by=2)
    branches_before = conn.execute(
        "SELECT COUNT(*) FROM writing_chapter_candidate_branches "
        "WHERE generation_round_id = ?",
        (round_id,),
    ).fetchone()[0]
    assert branches_before == 2

    # Drive from validating_initial: should pick up the 2 validating branches
    # (2 eligible -> supplement -> gen makes 3 more, index 3 passes -> selected)
    # WITHOUT regenerating the 2 already-validated branches.
    outcome = GenerationRoundDriver(
        conn,
        repo,
        generation_port=gen,
        validation_port=StubValidationPort({1, 2, 3}),
        selection_port=StubSelectionPort(),
    ).drive(round_id=round_id)
    assert outcome.final_status == "selected"
    assert outcome.eligible_count == 3

    # 2 pre-existing + 3 supplement = 5; resume did not duplicate the initial 2.
    count = conn.execute(
        "SELECT COUNT(*) FROM writing_chapter_candidate_branches "
        "WHERE generation_round_id = ?",
        (round_id,),
    ).fetchone()[0]
    assert count == 5
    # And re-driving a terminal round is a no-op.
    again = GenerationRoundDriver(
        conn,
        repo,
        generation_port=gen,
        validation_port=StubValidationPort({1, 2, 3}),
        selection_port=StubSelectionPort(),
    ).drive(round_id=round_id)
    assert again.final_status == "selected"
    assert again.eligible_count == 3
