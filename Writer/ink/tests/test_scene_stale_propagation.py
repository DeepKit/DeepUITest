from __future__ import annotations

import sqlite3

import pytest

from factories import (
    NOW,
    insert_contract_approve_reviews,
    insert_passing_accept_gates,
    make_schema_db,
)
from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.scene_repository import SceneRepository
from ink.errors import DataIntegrityError


def _contract(repo: SceneRepository, scene_id: int, version: int) -> int:
    contract_id = repo.create_contract(
        scene_id=scene_id,
        version=version,
        contract_hash=f"contract-{version}",
        source_bundle_hash=f"source-{version}",
        created_by="architect",
        status="approved",
    )
    repo.assemble_four_layer_contract(
        scene_contract_id=contract_id,
        hard_constraints=[{"clause_key": "hard", "clause_text": "hard"}],
        source_dna=[{"clause_key": "dna", "clause_text": "dna"}],
        soft_goals=[{"clause_key": "soft", "clause_text": "soft"}],
        creative_openings=[
            {"clause_key": "open-1", "clause_text": "one"},
            {"clause_key": "open-2", "clause_text": "two"},
        ],
    )
    return contract_id


def _fixture() -> tuple[sqlite3.Connection, SceneRepository, ChapterSnapshotRepository, int, int, int, int, int]:
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'stale', 'Stale', '["w1","w2","w3"]', '["j1","j2","j3"]', ?)
        """,
        (NOW,),
    )
    scenes = SceneRepository(conn)
    snapshots = ChapterSnapshotRepository(conn)
    scene_id = scenes.create_scene(
        project_id=1, chapter_id=1, logical_scene_key="scene-1", scene_order=1
    )
    contract_id = _contract(scenes, scene_id, 1)
    insert_contract_approve_reviews(conn, contract_id)
    scenes.human_activate_contract(scene_contract_id=contract_id, actor="author")
    round_id = snapshots.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    branch_id = snapshots.create_branch(
        generation_round_id=round_id,
        candidate_index=1,
        writer_model="writer",
        generation_strategy="seed",
    )
    branch_version_id = snapshots.create_branch_version(branch_id=branch_id, version=1)
    revision = scenes.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        scene_order=1,
        expected_parent_revision_id=None,
        scene_contract_id=contract_id,
        text="old prose",
        actor_type="human",
        actor_id="author",
        change_reason="seed",
    )
    return conn, scenes, snapshots, scene_id, contract_id, branch_id, branch_version_id, revision.scene_revision_id


def test_successor_activation_marks_revision_and_branch_stale() -> None:
    conn, scenes, snapshots, scene_id, old_contract, branch_id, branch_version_id, revision_id = _fixture()
    new_contract = _contract(scenes, scene_id, 2)
    insert_contract_approve_reviews(conn, new_contract)

    scenes.human_activate_contract(scene_contract_id=new_contract, actor="author")

    assert conn.execute(
        "SELECT status FROM writing_scene_contracts WHERE scene_contract_id = ?",
        (old_contract,),
    ).fetchone()[0] == "superseded"
    assert conn.execute(
        "SELECT replacement_scene_contract_id FROM writing_scene_revision_stale_marks "
        "WHERE scene_revision_id = ?",
        (revision_id,),
    ).fetchone()[0] == new_contract
    assert conn.execute(
        "SELECT replacement_scene_contract_id FROM writing_branch_version_stale_marks "
        "WHERE branch_version_id = ?",
        (branch_version_id,),
    ).fetchone()[0] == new_contract
    assert conn.execute(
        "SELECT count(*) FROM writing_runtime_events "
        "WHERE event_type = 'scene_contract_superseded'"
    ).fetchone()[0] == 1
    with pytest.raises(DataIntegrityError, match="stale Scene lineage"):
        snapshots.freeze_branch_version(branch_version_id, actor="author")


def test_building_branch_can_repair_stale_revision_under_successor_contract() -> None:
    conn, scenes, snapshots, scene_id, old_contract, branch_id, branch_version_id, revision_id = _fixture()
    new_contract = _contract(scenes, scene_id, 2)
    insert_contract_approve_reviews(conn, new_contract)
    scenes.human_activate_contract(scene_contract_id=new_contract, actor="author")
    repair_task_id = scenes.create_repair_task(
        project_id=1,
        chapter_id=1,
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        source_revision_id=revision_id,
        scene_contract_id=new_contract,
        issue="rewrite under successor",
        created_by="author",
    )
    repaired = scenes.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        scene_order=1,
        expected_parent_revision_id=revision_id,
        scene_contract_id=new_contract,
        text="fresh prose",
        actor_type="ai",
        actor_id="model:writer",
        change_reason="repair",
        repair_task_id=repair_task_id,
    )
    assert repaired.parent_revision_id == revision_id
    assert conn.execute(
        "SELECT 1 FROM writing_branch_version_stale_marks WHERE branch_version_id = ?",
        (branch_version_id,),
    ).fetchone() is None
    snapshots.freeze_branch_version(branch_version_id, actor="author")


def test_generation_task_cannot_extend_stale_parent() -> None:
    conn, scenes, snapshots, scene_id, old_contract, branch_id, branch_version_id, revision_id = _fixture()
    new_contract = _contract(scenes, scene_id, 2)
    insert_contract_approve_reviews(conn, new_contract)
    scenes.human_activate_contract(scene_contract_id=new_contract, actor="author")
    with pytest.raises(DataIntegrityError, match="cannot extend a stale"):
        scenes.create_revision(
            scene_id=scene_id,
            branch_version_id=branch_version_id,
            scene_order=1,
            expected_parent_revision_id=revision_id,
            scene_contract_id=new_contract,
            text="bypass",
            actor_type="ai",
            actor_id="model:writer",
            change_reason="generate",
            generation_task_id=branch_id,
        )


def test_supersede_marks_active_snapshot_unreadable() -> None:
    conn, scenes, snapshots, scene_id, old_contract, branch_id, branch_version_id, revision_id = _fixture()
    snapshots.freeze_branch_version(branch_version_id, actor="author")
    conn.execute(
        "UPDATE writing_chapter_candidate_branches SET status = 'eligible' WHERE branch_id = ?",
        (branch_id,),
    )
    snapshots.select_branch(branch_id)
    insert_passing_accept_gates(conn, branch_version_id)
    head = snapshots.accept_chapter(
        branch_version_id=branch_version_id,
        expected_head_version=0,
        actor="author",
        reason="accept old contract prose",
        preconditions_json={},
        selection_decision_type="auto_selected",
        selection_evidence_json={"test": "stale propagation"},
    )
    assert snapshots.read_active_chapter_text(project_id=1, chapter_id=1) == "old prose"

    new_contract = _contract(scenes, scene_id, 2)
    insert_contract_approve_reviews(conn, new_contract)
    scenes.human_activate_contract(scene_contract_id=new_contract, actor="author")

    assert conn.execute(
        "SELECT replacement_scene_contract_id FROM writing_chapter_snapshot_stale_marks "
        "WHERE snapshot_id = ?",
        (head.active_snapshot_id,),
    ).fetchone()[0] == new_contract
    with pytest.raises(DataIntegrityError, match="stale Scene lineage"):
        snapshots.read_active_chapter_text(project_id=1, chapter_id=1)
    with pytest.raises(DataIntegrityError, match="stale Scene lineage"):
        snapshots.get_active_snapshot_id(project_id=1, chapter_id=1)
    with pytest.raises(DataIntegrityError, match="stale Scene lineage"):
        snapshots.read_branch_version_text(branch_version_id)


def test_supersede_cancels_open_old_contract_repair_tasks_idempotently() -> None:
    conn, scenes, snapshots, scene_id, old_contract, branch_id, branch_version_id, revision_id = _fixture()
    task_id = scenes.create_repair_task(
        project_id=1,
        chapter_id=1,
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        source_revision_id=revision_id,
        scene_contract_id=old_contract,
        issue="old repair",
        created_by="author",
    )
    new_contract = _contract(scenes, scene_id, 2)
    insert_contract_approve_reviews(conn, new_contract)
    scenes.human_activate_contract(scene_contract_id=new_contract, actor="author")
    assert conn.execute(
        "SELECT status FROM writing_scene_repair_tasks WHERE repair_task_id = ?",
        (task_id,),
    ).fetchone()[0] == "cancelled"
    from ink.core.scene_stale_propagation import SceneStalePropagationManager

    result = SceneStalePropagationManager(conn).mark_contract_superseded(
        source_scene_contract_id=old_contract,
        replacement_scene_contract_id=new_contract,
        reason="repeat",
    )
    assert result.cancelled_repair_task_ids == ()
    assert conn.execute("SELECT count(*) FROM writing_scene_revision_stale_marks").fetchone()[0] == 1
