from __future__ import annotations

import sqlite3

import pytest

from ink.core.chapter_snapshot_repository import (
    ChapterSnapshotRepository,
    RoundState,
)
from ink.errors import (
    ConcurrentModificationError,
    DataIntegrityError,
    IllegalTransitionError,
    TerminalStateError,
)
from factories import NOW, make_schema_db


def _repo() -> tuple[sqlite3.Connection, ChapterSnapshotRepository, int]:
    """Build a project + one generation round (status='planned') ready to drive."""
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'round', 'Round',
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


def _branch(repo: ChapterSnapshotRepository, round_id: int, index: int = 1) -> int:
    branch_id = repo.create_branch(
        generation_round_id=round_id,
        candidate_index=index,
        writer_model="writer-a",
        generation_strategy="quiet-pressure",
    )
    # generating -> validating is owned by the branch lifecycle (not this spec);
    # set it directly so record_eligible_branch can drive validating -> eligible.
    repo.conn.execute(
        "UPDATE writing_chapter_candidate_branches SET status = 'validating' "
        "WHERE branch_id = ?",
        (branch_id,),
    )
    return branch_id


def _state(repo: ChapterSnapshotRepository, round_id: int) -> RoundState:
    return repo.get_generation_round_state(round_id=round_id)


# ── INV-ROUND-001 ──

def test_round_legal_transitions_advance(repo=None):
    conn, repo, round_id = _repo()
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    repo.transition_generation_round(
        round_id=round_id, to="validating_initial", expected_status="generating_initial"
    )
    repo.transition_generation_round(
        round_id=round_id, to="supplementing", expected_status="validating_initial"
    )
    repo.transition_generation_round(
        round_id=round_id, to="validating_supplement", expected_status="supplementing"
    )
    repo.transition_generation_round(
        round_id=round_id, to="ready_for_selection", expected_status="validating_supplement"
    )
    repo.transition_generation_round(
        round_id=round_id, to="selecting", expected_status="ready_for_selection"
    )
    repo.transition_generation_round(
        round_id=round_id, to="selected", expected_status="selecting"
    )
    assert _state(repo, round_id).status == "selected"


def test_round_transition_not_in_table_is_illegal():
    conn, repo, round_id = _repo()
    # planned -> selected is not in the legal-transition table.
    with pytest.raises(IllegalTransitionError):
        repo.transition_generation_round(
            round_id=round_id, to="selected", expected_status="planned"
        )
    # validating_initial -> supplementing is legal, but -> generating_initial is not.
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    repo.transition_generation_round(
        round_id=round_id, to="validating_initial", expected_status="generating_initial"
    )
    with pytest.raises(IllegalTransitionError):
        repo.transition_generation_round(
            round_id=round_id, to="generating_initial", expected_status="validating_initial"
        )


# ── INV-ROUND-002 ──

def test_round_illegal_transition_raises_illegal_transition_error():
    conn, repo, round_id = _repo()
    with pytest.raises(IllegalTransitionError):
        repo.transition_generation_round(
            round_id=round_id, to="diversity_shortage", expected_status="planned"
        )


# ── INV-ROUND-003 ──

def test_round_cas_rejects_stale_expected_status():
    conn, repo, round_id = _repo()
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    # The round is now generating_initial. Re-issuing the *same legal* edge
    # (planned -> generating_initial) with the stale expected_status must be
    # rejected by the CAS rowcount guard, not by the transition validator.
    with pytest.raises(ConcurrentModificationError):
        repo.transition_generation_round(
            round_id=round_id, to="generating_initial", expected_status="planned"
        )
    assert _state(repo, round_id).status == "generating_initial"


# ── INV-ROUND-004 ──

def test_round_initial_zero_pass_terminates_round():
    conn, repo, round_id = _repo()
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    repo.transition_generation_round(
        round_id=round_id, to="validating_initial", expected_status="generating_initial"
    )
    repo.mark_initial_zero_pass(round_id=round_id)
    state = _state(repo, round_id)
    assert state.status == "initial_zero_pass"
    assert state.failure_reason is not None


# ── INV-ROUND-005 ──

def test_round_supplement_only_once_from_validating_initial():
    conn, repo, round_id = _repo()
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    repo.transition_generation_round(
        round_id=round_id, to="validating_initial", expected_status="generating_initial"
    )
    repo.start_supplement(round_id=round_id)
    assert _state(repo, round_id).status == "supplementing"
    # Once past supplementing, cannot re-enter it (no reflow): the only legal
    # edge from validating_supplement is ready_for_selection / *_shortage.
    repo.transition_generation_round(
        round_id=round_id, to="validating_supplement", expected_status="supplementing"
    )
    with pytest.raises(IllegalTransitionError):
        repo.transition_generation_round(
            round_id=round_id,
            to="supplementing",
            expected_status="validating_supplement",
        )
    # And start_supplement (which targets supplementing from validating_initial)
    # must fail the CAS because the round is no longer in validating_initial.
    with pytest.raises(ConcurrentModificationError):
        repo.start_supplement(round_id=round_id)


# ���─ INV-ROUND-006 ──

def test_round_ready_for_selection_requires_three_eligible():
    conn, repo, round_id = _repo()
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    repo.transition_generation_round(
        round_id=round_id, to="validating_initial", expected_status="generating_initial"
    )
    # Only 2 eligible -> cannot begin selection even if driven to ready_for_selection first.
    b1 = _branch(repo, round_id, 1)
    b2 = _branch(repo, round_id, 2)
    repo.record_eligible_branch(round_id=round_id, branch_id=b1)
    repo.record_eligible_branch(round_id=round_id, branch_id=b2)
    assert _state(repo, round_id).eligible_count == 2
    # Force the round into ready_for_selection to exercise begin_selection's gate.
    repo.transition_generation_round(
        round_id=round_id, to="ready_for_selection", expected_status="validating_initial"
    )
    with pytest.raises(DataIntegrityError):
        repo.begin_selection(round_id=round_id)


# ── INV-ROUND-007a ──

def test_round_terminal_state_rejects_further_transition():
    conn, repo, round_id = _repo()
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    repo.transition_generation_round(
        round_id=round_id, to="validating_initial", expected_status="generating_initial"
    )
    repo.mark_initial_zero_pass(round_id=round_id)
    # initial_zero_pass is terminal: any further transition must be rejected.
    with pytest.raises(TerminalStateError):
        repo.transition_generation_round(
            round_id=round_id,
            to="ready_for_selection",
            expected_status="initial_zero_pass",
        )


# ── INV-ROUND-007b ──

def test_round_superseded_only_from_non_terminal():
    conn, repo, round_id = _repo()
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    # Non-terminal -> superseded is legal.
    repo.mark_superseded(round_id=round_id, expected_status="generating_initial")
    assert _state(repo, round_id).status == "superseded"
    assert _state(repo, round_id).failure_reason == "superseded by newer round"

    # Terminal -> superseded is illegal.
    conn2, repo2, round2 = _repo()
    repo2.transition_generation_round(
        round_id=round2, to="generating_initial", expected_status="planned"
    )
    repo2.transition_generation_round(
        round_id=round2, to="validating_initial", expected_status="generating_initial"
    )
    repo2.mark_initial_zero_pass(round_id=round2)
    with pytest.raises(TerminalStateError):
        repo2.mark_superseded(round_id=round2, expected_status="initial_zero_pass")


# ── INV-ROUND-008a ──

def test_record_eligible_branch_increments_count_atomically():
    conn, repo, round_id = _repo()
    b1 = _branch(repo, round_id, 1)
    repo.record_eligible_branch(round_id=round_id, branch_id=b1)
    state = _state(repo, round_id)
    assert state.eligible_count == 1
    # Branch is now eligible; re-recording the same branch fails (CAS).
    with pytest.raises(ConcurrentModificationError):
        repo.record_eligible_branch(round_id=round_id, branch_id=b1)
    # Count unchanged after failed CAS.
    assert _state(repo, round_id).eligible_count == 1


# ── INV-ROUND-009a ──

def test_increment_call_count_is_monotonic():
    conn, repo, round_id = _repo()
    assert _state(repo, round_id).call_count == 0
    assert repo.increment_call_count(round_id=round_id, by=3) == 3
    assert repo.increment_call_count(round_id=round_id) == 4
    with pytest.raises(ValueError):
        repo.increment_call_count(round_id=round_id, by=-1)
    assert _state(repo, round_id).call_count == 4


# ── INV-ROUND-010 ──

def test_get_round_state_returns_full_recovery_point():
    conn, repo, round_id = _repo()
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    repo.transition_generation_round(
        round_id=round_id, to="validating_initial", expected_status="generating_initial"
    )
    repo.increment_call_count(round_id=round_id, by=2)
    b1 = _branch(repo, round_id, 1)
    repo.record_eligible_branch(round_id=round_id, branch_id=b1)
    repo.mark_initial_zero_pass(round_id=round_id)
    state = _state(repo, round_id)
    assert state.round_id == round_id
    assert state.status == "initial_zero_pass"
    assert state.eligible_count == 1
    assert state.call_count == 2
    assert state.failure_reason is not None
    assert state.initial_target_count == 2  # schema DEFAULT
    assert state.supplement_target_count == 3  # schema DEFAULT
    assert state.updated_at  # non-empty timestamp


# ── missing round_id ──

def test_get_round_state_missing_raises_data_integrity():
    conn, repo, round_id = _repo()
    with pytest.raises(DataIntegrityError):
        repo.get_generation_round_state(round_id=round_id + 999)


# ── mark_failed from any non-terminal ──

def test_mark_failed_from_non_terminal_with_reason():
    conn, repo, round_id = _repo()
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    repo.mark_failed(round_id=round_id, reason="writer provider down")
    state = _state(repo, round_id)
    assert state.status == "failed"
    assert state.failure_reason == "writer provider down"
    # Once failed (terminal), cannot fail again.
    with pytest.raises(TerminalStateError):
        repo.mark_failed(round_id=round_id, reason="again")


# ── candidate_shortage vs diversity_shortage require reason ──

def test_mark_shortage_requires_reason():
    conn, repo, round_id = _repo()
    repo.transition_generation_round(
        round_id=round_id, to="generating_initial", expected_status="planned"
    )
    repo.transition_generation_round(
        round_id=round_id, to="validating_initial", expected_status="generating_initial"
    )
    repo.start_supplement(round_id=round_id)
    repo.transition_generation_round(
        round_id=round_id, to="validating_supplement", expected_status="supplementing"
    )
    with pytest.raises(ValueError):
        repo.mark_candidate_shortage(round_id=round_id, reason="")
    repo.mark_candidate_shortage(round_id=round_id, reason="only 2 passed after supplement")
    assert _state(repo, round_id).status == "candidate_shortage"


# ── INV-ROUND-018: start_validating_branch CAS ──

def test_start_validating_branch_cas_rejects_non_generating():
    conn, repo, round_id = _repo()
    b1 = repo.create_branch(
        generation_round_id=round_id,
        candidate_index=1,
        writer_model="writer-a",
        generation_strategy="quiet-pressure",
    )
    # generating -> validating via the CAS method.
    repo.start_validating_branch(branch_id=b1)
    status = repo.conn.execute(
        "SELECT status FROM writing_chapter_candidate_branches WHERE branch_id = ?",
        (b1,),
    ).fetchone()[0]
    assert status == "validating"

    # Already validating: CAS rejects (expected generating, was validating).
    with pytest.raises(ConcurrentModificationError):
        repo.start_validating_branch(branch_id=b1)

    # A second branch still generating can advance independently.
    b2 = repo.create_branch(
        generation_round_id=round_id,
        candidate_index=2,
        writer_model="writer-b",
        generation_strategy="slow-burn",
    )
    repo.start_validating_branch(branch_id=b2)
    assert repo.conn.execute(
        "SELECT status FROM writing_chapter_candidate_branches WHERE branch_id = ?",
        (b2,),
    ).fetchone()[0] == "validating"

    # Unknown branch id -> DataIntegrityError, not a silent no-op.
    with pytest.raises(DataIntegrityError):
        repo.start_validating_branch(branch_id=b2 + 9999)


# ── INV-ROUND-019: advance_to_literary_review CAS ──

def test_advance_to_literary_review_cas_rejects_non_eligible():
    conn, repo, round_id = _repo()
    b1 = repo.create_branch(
        generation_round_id=round_id,
        candidate_index=1,
        writer_model="writer-a",
        generation_strategy="quiet-pressure",
    )
    # Branch is 'generating' -> not eligible -> CAS rejects.
    with pytest.raises(ConcurrentModificationError):
        repo.advance_to_literary_review(branch_id=b1)

    # Walk generating -> validating -> eligible, then literary_review is legal.
    repo.start_validating_branch(branch_id=b1)
    repo.record_eligible_branch(round_id=round_id, branch_id=b1)
    repo.advance_to_literary_review(branch_id=b1)
    status = repo.conn.execute(
        "SELECT status FROM writing_chapter_candidate_branches WHERE branch_id = ?",
        (b1,),
    ).fetchone()[0]
    assert status == "literary_review"

    # Already literary_review: CAS rejects (expected eligible).
    with pytest.raises(ConcurrentModificationError):
        repo.advance_to_literary_review(branch_id=b1)

    # Unknown branch id -> DataIntegrityError.
    with pytest.raises(DataIntegrityError):
        repo.advance_to_literary_review(branch_id=b1 + 9999)
