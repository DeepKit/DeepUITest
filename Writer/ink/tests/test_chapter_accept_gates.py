from __future__ import annotations

import json

import pytest

from factories import NOW, insert_contract_approve_reviews, make_schema_db
from ink.core.chapter_accept_gate_repository import ChapterAcceptGateRepository
from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.scene_repository import SceneRepository
from ink.errors import DataIntegrityError
from ink.pipeline.scene_first_acceptance_gate_orchestrator import (
    SceneFirstAcceptanceGateOrchestrator,
)


def _selected_branch():
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'accept-gates', 'Accept Gates', '[\"writer-a\",\"writer-b\",\"writer-c\"]', '[\"judge-a\",\"judge-b\",\"judge-c\"]', ?)
        """,
        (NOW,),
    )
    snapshots = ChapterSnapshotRepository(conn)
    scenes = SceneRepository(conn)
    scene_id = scenes.create_scene(
        project_id=1,
        chapter_id=1,
        logical_scene_key="gate-scene-1",
        scene_order=1,
    )
    contract_id = scenes.create_contract(
        scene_id=scene_id,
        version=1,
        contract_hash="gate-contract",
        source_bundle_hash="gate-source",
        created_by="architect",
        status="approved",
    )
    scenes.assemble_four_layer_contract(
        scene_contract_id=contract_id,
        hard_constraints=[{"clause_key": "hard", "clause_text": "必须发生"}],
        source_dna=[{"clause_key": "dna", "clause_text": "克制"}],
        soft_goals=[{"clause_key": "soft", "clause_text": "保持张力"}],
        creative_openings=[
            {"clause_key": "open-1", "clause_text": "入口一"},
            {"clause_key": "open-2", "clause_text": "入口二"},
        ],
    )
    insert_contract_approve_reviews(conn, contract_id)
    scenes.activate_contract(contract_id)
    round_id = snapshots.create_generation_round(project_id=1, chapter_id=1, round_number=1)
    branch_id = snapshots.create_branch(
        generation_round_id=round_id,
        candidate_index=1,
        writer_model="writer",
        generation_strategy="gate-test",
    )
    bv_id = snapshots.create_branch_version(branch_id=branch_id, version=1)
    scenes.create_revision(
        scene_id=scene_id,
        branch_version_id=bv_id,
        scene_order=1,
        expected_parent_revision_id=None,
        scene_contract_id=contract_id,
        text="门禁绑定的完整场景正文。",
        actor_type="ai",
        actor_id="writer",
        change_reason="test",
        generation_task_id=branch_id,
    )
    snapshots.freeze_branch_version(bv_id, actor="author")
    conn.execute(
        "UPDATE writing_chapter_candidate_branches SET status = 'eligible' WHERE branch_id = ?",
        (branch_id,),
    )
    snapshots.select_branch(branch_id)
    return conn, snapshots, bv_id


def _chapter_quality(conn, bv_id: int, *, passed: bool = True) -> int:
    return ChapterAcceptGateRepository(conn).record_evidence(
        branch_version_id=bv_id,
        gate_type="chapter_quality",
        passed=passed,
        evidence={
            "scores": {"fixture": 90 if passed else 20},
            "dimension_floor": 75,
            "blocking_issues": [] if passed else ["fixture"],
        },
        producer_actor="jury",
        reviewer_models=("model-a",),
    )


def test_accept_fails_closed_without_gate_bundle() -> None:
    _, snapshots, bv_id = _selected_branch()
    with pytest.raises(DataIntegrityError, match="gate evidence missing"):
        snapshots.accept_chapter(
            branch_version_id=bv_id,
            expected_head_version=0,
            actor="author",
            reason="accept",
            preconditions_json={},
            selection_decision_type="human_override",
            selection_evidence_json={"test": True},
        )


def test_orchestrator_persists_bundle_and_accept_binds_snapshot() -> None:
    conn, snapshots, bv_id = _selected_branch()
    _chapter_quality(conn, bv_id)
    SceneFirstAcceptanceGateOrchestrator(conn).prepare_acceptance(
        branch_version_id=bv_id, actor="author"
    )
    head = snapshots.accept_chapter(
        branch_version_id=bv_id,
        expected_head_version=0,
        actor="author",
        reason="accept",
        preconditions_json={"reviewed": True},
        selection_decision_type="human_override",
        selection_evidence_json={"test": True},
    )
    bound = conn.execute(
        "SELECT gate_type FROM writing_chapter_snapshot_gate_evidence "
        "WHERE snapshot_id = ? ORDER BY gate_type",
        (head.active_snapshot_id,),
    ).fetchall()
    assert [str(row[0]) for row in bound] == [
        "book_continuity", "chapter_quality", "ethics", "scene_integrity"
    ]
    preconditions = json.loads(conn.execute(
        "SELECT preconditions_json FROM writing_human_decisions WHERE decision_id = ?",
        (head.accepted_decision_id,),
    ).fetchone()[0])
    assert set(preconditions["accept_gate_evidence_ids"]) == {
        "book_continuity", "chapter_quality", "ethics", "scene_integrity"
    }


def test_failed_chapter_quality_cannot_be_replaced_by_status() -> None:
    conn, snapshots, bv_id = _selected_branch()
    _chapter_quality(conn, bv_id, passed=False)
    SceneFirstAcceptanceGateOrchestrator(conn).prepare_acceptance(
        branch_version_id=bv_id, actor="author"
    )
    with pytest.raises(DataIntegrityError, match="hard gate failed"):
        snapshots.accept_chapter(
            branch_version_id=bv_id,
            expected_head_version=0,
            actor="author",
            reason="accept",
            preconditions_json={},
            selection_decision_type="human_override",
            selection_evidence_json={"test": True},
        )


def test_atomic_gate_preparation_rolls_back_evidence_when_accept_fails() -> None:
    conn, _, bv_id = _selected_branch()
    gates = SceneFirstAcceptanceGateOrchestrator(conn)
    with pytest.raises(DataIntegrityError, match="chapter literary evidence is missing"):
        gates.accept_chapter(
            branch_version_id=bv_id,
            expected_head_version=0,
            actor="author",
            reason="accept",
            preconditions_json={},
            selection_decision_type="human_override",
            selection_evidence_json={"test": True},
        )
    assert conn.execute(
        "SELECT count(*) FROM writing_chapter_accept_gate_evidence WHERE branch_version_id = ?",
        (bv_id,),
    ).fetchone()[0] == 0


def test_book_evidence_is_invalidated_when_predecessor_head_changes() -> None:
    conn, snapshots, bv_id = _selected_branch()
    _chapter_quality(conn, bv_id)
    SceneFirstAcceptanceGateOrchestrator(conn).prepare_acceptance(
        branch_version_id=bv_id, actor="author"
    )
    conn.execute(
        "INSERT INTO writing_chapter_snapshots "
        "(project_id, chapter_id, source_branch_version_id, snapshot_hash, accepted_decision_id, created_at, sealed_at) "
        "VALUES (1, 0, ?, 'predecessor-hash', NULL, datetime('now'), datetime('now'))",
        (bv_id,),
    )
    snapshot_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
    conn.execute(
        "INSERT INTO writing_chapter_heads "
        "(project_id, chapter_id, active_snapshot_id, version, updated_at) "
        "VALUES (1, 0, ?, 1, datetime('now'))",
        (snapshot_id,),
    )
    with pytest.raises(DataIntegrityError, match="predecessor Heads are stale"):
        snapshots.accept_chapter(
            branch_version_id=bv_id,
            expected_head_version=0,
            actor="author",
            reason="accept",
            preconditions_json={},
            selection_decision_type="human_override",
            selection_evidence_json={"test": True},
        )
