from __future__ import annotations

import json

import pytest

from ink.core.llm_gateway import LLMGateway
from ink.core.text_repository import TextRepository
from ink.contract.loader import load_shot_contract
from ink.errors import DataIntegrityError
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from ink.pipeline.jury_orchestrator import JuryOrchestrator
from ink.pipeline.polish_orchestrator import PolishOrchestrator
from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator
from test_m4_review_pipeline import PolishProvider, make_winner_selected_shot


def test_chapter_quality_gate_blocks_accept() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    conn.execute(
        "UPDATE writing_shot_revisions SET text = text || ' [chapter-fail]' WHERE sealed_by = 'shot_soft'"
    )

    review = ChapterReviewOrchestrator(conn).review_chapter(1, 1, int(ids["run_id"]))

    assert review.quality_gate_passed is False
    assert review.blocking_issues == ("rhythm_curve",)
    assert conn.execute(
        "SELECT quality_gate_passed, status, blocking_issues FROM writing_chapter_reviews"
    ).fetchone() == (0, "pending", '["rhythm_curve"]')
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "soft_sealed"


def test_human_accept_cannot_override_quality_failure() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    conn.execute(
        "UPDATE writing_shot_revisions SET text = text || ' [chapter-fail]' WHERE sealed_by = 'shot_soft'"
    )
    ChapterReviewOrchestrator(conn).review_chapter(1, 1, int(ids["run_id"]))

    with pytest.raises(DataIntegrityError):
        HumanReviewOrchestrator(conn).accept_chapter(1, 1, int(ids["run_id"]), actor="author", reason="approve")

    assert conn.execute("SELECT count(*) FROM writing_human_decisions").fetchone()[0] == 0
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "soft_sealed"
    assert conn.execute("SELECT count(*) FROM writing_shot_revisions WHERE sealed_by = 'chapter_hard'").fetchone()[0] == 0


def test_human_accept_writes_decision_and_hard_seals_chapter() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    review = ChapterReviewOrchestrator(conn).review_chapter(1, 1, int(ids["run_id"]))

    decision_id = HumanReviewOrchestrator(conn).accept_chapter(
        1,
        1,
        int(ids["run_id"]),
        actor="author",
        reason="chapter quality passed",
    )

    assert review.quality_gate_passed is True
    assert conn.execute("SELECT status FROM writing_chapter_reviews WHERE review_id = ?", (review.review_id,)).fetchone()[0] == "accepted"
    decision = conn.execute(
        """
        SELECT decision_type, actor, reason, preconditions_json, quality_report_json, hard_quality_override
        FROM writing_human_decisions
        WHERE decision_id = ?
        """,
        (decision_id,),
    ).fetchone()
    assert decision[:3] == ("accept", "author", "chapter quality passed")
    assert json.loads(decision[3])["quality_gate_passed"] is True
    assert json.loads(decision[4])["evidence_class"] == "SEMI_ES"
    assert decision[5] == 0
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "hard_sealed"
    assert TextRepository(conn).is_hard_sealed(str(ids["shot_id"]), int(ids["run_id"])) is True
    assert conn.execute(
        "SELECT text, is_current FROM writing_shot_revisions WHERE sealed_by = 'chapter_hard'"
    ).fetchone() == ("polished text", 1)


def test_human_reject_writes_decision_without_hard_seal() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    review = ChapterReviewOrchestrator(conn).review_chapter(1, 1, int(ids["run_id"]))

    decision_id = HumanReviewOrchestrator(conn).reject_chapter(
        1,
        1,
        int(ids["run_id"]),
        actor="author",
        reason="reject this direction",
    )

    assert conn.execute("SELECT status FROM writing_chapter_reviews WHERE review_id = ?", (review.review_id,)).fetchone()[0] == "rejected"
    decision = conn.execute(
        """
        SELECT decision_type, actor, reason, preconditions_json
        FROM writing_human_decisions
        WHERE decision_id = ?
        """,
        (decision_id,),
    ).fetchone()
    assert decision[:3] == ("reject", "author", "reject this direction")
    assert json.loads(decision[3])["action"] == "reject"
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "soft_sealed"
    assert conn.execute("SELECT count(*) FROM writing_shot_revisions WHERE sealed_by = 'chapter_hard'").fetchone()[0] == 0


def test_human_revise_writes_decision_and_clones_chapter_run() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    review = ChapterReviewOrchestrator(conn).review_chapter(1, 1, int(ids["run_id"]))

    revised = HumanReviewOrchestrator(conn).revise_chapter(
        1,
        1,
        int(ids["run_id"]),
        actor="author",
        reason="revise chapter pacing",
    )

    assert conn.execute("SELECT status FROM writing_chapter_reviews WHERE review_id = ?", (review.review_id,)).fetchone()[0] == "revised"
    assert revised.run_id != ids["run_id"]
    assert revised.shot_ids == (f"shot-001@{revised.run_id}",)
    assert conn.execute(
        "SELECT project_id, session_id, run_attempt, status FROM writing_runs WHERE run_id = ?",
        (revised.run_id,),
    ).fetchone() == (1, 10, 2, "running")
    assert conn.execute(
        "SELECT logical_shot_id, status FROM writing_shots WHERE shot_id = ?",
        (revised.shot_ids[0],),
    ).fetchone() == ("shot-001", "pending")
    assert load_shot_contract(conn, revised.shot_ids[0], revised.run_id).must_land["events"] == ["她走进档案室"]
    decision = conn.execute(
        """
        SELECT decision_type, preconditions_json
        FROM writing_human_decisions
        WHERE decision_id = ?
        """,
        (revised.decision_id,),
    ).fetchone()
    preconditions = json.loads(decision[1])
    assert decision[0] == "revise"
    assert preconditions["new_run_id"] == revised.run_id
    assert preconditions["source_run_id"] == ids["run_id"]
    assert preconditions["new_shot_count"] == 1
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "soft_sealed"
    assert conn.execute("SELECT count(*) FROM writing_shot_revisions WHERE sealed_by = 'chapter_hard'").fetchone()[0] == 0


def make_soft_sealed_chapter():
    conn = make_winner_selected_shot()
    ids = _ids(conn)
    PolishOrchestrator(conn, LLMGateway(conn, provider=PolishProvider())).polish_winner(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))
    JuryOrchestrator(conn).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))
    SoftSealOrchestrator(conn).soft_seal_if_polished(str(ids["shot_id"]), int(ids["run_id"]))
    return conn


def _ids(conn):
    row = conn.execute(
        "SELECT shot_id, run_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
    ).fetchone()
    return {"shot_id": row[0], "run_id": row[1]}
