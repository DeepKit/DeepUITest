from __future__ import annotations

import sqlite3

import pytest

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.scene_repository import SceneRepository
from ink.errors import ConcurrentModificationError, DataIntegrityError
from factories import NOW, insert_contract_approve_reviews, make_schema_db


def _project(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'scene-repo', 'Scene Repository',
             '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c"]', ?)
        """,
        (NOW,),
    )


def _active_scene_contract(
    conn: sqlite3.Connection,
) -> tuple[SceneRepository, ChapterSnapshotRepository, int, int]:
    _project(conn)
    scene_repo = SceneRepository(conn)
    snapshot_repo = ChapterSnapshotRepository(conn)
    scene_id = scene_repo.create_scene(
        project_id=1,
        chapter_id=1,
        logical_scene_key="scene-1",
        scene_order=1,
    )
    contract_id = scene_repo.create_contract(
        scene_id=scene_id,
        version=1,
        contract_hash="contract-hash",
        source_bundle_hash="source-hash",
        created_by="architect-a",
        status="approved",
    )
    scene_repo.assemble_four_layer_contract(
        scene_contract_id=contract_id,
        hard_constraints=[{"clause_key": "hard-1", "clause_text": "hard"}],
        source_dna=[{"clause_key": "source-1", "clause_text": "source"}],
        soft_goals=[{"clause_key": "soft-1", "clause_text": "soft"}],
        creative_openings=[
            {"clause_key": "opening-1", "clause_text": "opening one"},
            {"clause_key": "opening-2", "clause_text": "opening two"},
        ],
    )
    insert_contract_approve_reviews(conn, contract_id)
    scene_repo.activate_contract(contract_id)
    return scene_repo, snapshot_repo, scene_id, contract_id


def _branch(
    snapshot_repo: ChapterSnapshotRepository,
    *,
    generation_round_id: int,
    candidate_index: int,
) -> tuple[int, int]:
    branch_id = snapshot_repo.create_branch(
        generation_round_id=generation_round_id,
        candidate_index=candidate_index,
        writer_model=f"writer-{candidate_index}",
        generation_strategy=f"strategy-{candidate_index}",
    )
    version_id = snapshot_repo.create_branch_version(branch_id=branch_id, version=1)
    return branch_id, version_id


def test_activate_contract_rejects_approved_status_without_review_evidence() -> None:
    conn = make_schema_db()
    _project(conn)
    repo = SceneRepository(conn)
    scene_id = repo.create_scene(
        project_id=1, chapter_id=1, logical_scene_key="unreviewed", scene_order=1
    )
    contract_id = repo.create_contract(
        scene_id=scene_id, version=1, contract_hash="contract",
        source_bundle_hash="source", created_by="architect", status="approved",
    )
    repo.assemble_four_layer_contract(
        scene_contract_id=contract_id,
        hard_constraints=[{"clause_key": "hard-1", "clause_text": "hard"}],
        source_dna=[{"clause_key": "source-1", "clause_text": "source"}],
        soft_goals=[{"clause_key": "soft-1", "clause_text": "soft"}],
        creative_openings=[
            {"clause_key": "opening-1", "clause_text": "opening one"},
            {"clause_key": "opening-2", "clause_text": "opening two"},
        ],
    )

    with pytest.raises(DataIntegrityError, match="three blind approve reviews"):
        repo.activate_contract(contract_id)
    with pytest.raises(sqlite3.IntegrityError, match="three blind approve reviews"):
        conn.execute(
            "UPDATE writing_scene_contracts SET status='active' WHERE scene_contract_id=?",
            (contract_id,),
        )


def test_two_branches_can_fork_from_same_branch_local_parent() -> None:
    conn = make_schema_db()
    scene_repo, snapshot_repo, scene_id, contract_id = _active_scene_contract(conn)
    generation_round_id = snapshot_repo.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    _, base_version_id = _branch(
        snapshot_repo, generation_round_id=generation_round_id, candidate_index=1
    )
    base = scene_repo.create_revision(
        scene_id=scene_id,
        branch_version_id=base_version_id,
        scene_order=1,
        expected_parent_revision_id=None,
        scene_contract_id=contract_id,
        text="共同的父版本。",
        actor_type="human",
        actor_id="author",
        change_reason="seed",
    )

    # Use another round so each round retains its own unique candidate indexes.
    fork_round = snapshot_repo.create_generation_round(
        project_id=1, chapter_id=1, round_number=2
    )
    branch_a_id, branch_a_version = _branch(
        snapshot_repo, generation_round_id=fork_round, candidate_index=1
    )
    branch_b_id, branch_b_version = _branch(
        snapshot_repo, generation_round_id=fork_round, candidate_index=2
    )
    for branch_version_id in (branch_a_version, branch_b_version):
        scene_repo.bind_existing_revision(
            branch_version_id=branch_version_id,
            scene_order=1,
            scene_id=scene_id,
            scene_revision_id=base.scene_revision_id,
        )

    branch_a = scene_repo.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_a_version,
        scene_order=1,
        expected_parent_revision_id=base.scene_revision_id,
        scene_contract_id=contract_id,
        text="A分支沿着沉默推进。",
        actor_type="ai",
        actor_id="writer-a",
        change_reason="candidate A",
        generation_task_id=branch_a_id,
    )
    branch_b = scene_repo.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_b_version,
        scene_order=1,
        expected_parent_revision_id=base.scene_revision_id,
        scene_contract_id=contract_id,
        text="B分支用一次误解转向。",
        actor_type="ai",
        actor_id="writer-b",
        change_reason="candidate B",
        generation_task_id=branch_b_id,
    )

    assert branch_a.parent_revision_id == base.scene_revision_id
    assert branch_b.parent_revision_id == base.scene_revision_id
    assert branch_a.scene_revision_id != branch_b.scene_revision_id


def test_stale_branch_local_parent_is_rejected() -> None:
    conn = make_schema_db()
    scene_repo, snapshot_repo, scene_id, contract_id = _active_scene_contract(conn)
    round_id = snapshot_repo.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    branch_id, branch_version_id = _branch(
        snapshot_repo, generation_round_id=round_id, candidate_index=1
    )
    first = scene_repo.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        scene_order=1,
        expected_parent_revision_id=None,
        scene_contract_id=contract_id,
        text="第一版。",
        actor_type="human",
        actor_id="author",
        change_reason="seed",
    )
    scene_repo.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        scene_order=1,
        expected_parent_revision_id=first.scene_revision_id,
        scene_contract_id=contract_id,
        text="第二版。",
        actor_type="human",
        actor_id="author",
        change_reason="repair",
    )
    with pytest.raises(ConcurrentModificationError):
        scene_repo.create_revision(
            scene_id=scene_id,
            branch_version_id=branch_version_id,
            scene_order=1,
            expected_parent_revision_id=first.scene_revision_id,
            scene_contract_id=contract_id,
            text="从过期父版本继续。",
            actor_type="ai",
            actor_id="writer-a",
            change_reason="stale write",
            generation_task_id=branch_id,
        )


def test_frozen_branch_blocks_revision_and_binding_mutation() -> None:
    conn = make_schema_db()
    scene_repo, snapshot_repo, scene_id, contract_id = _active_scene_contract(conn)
    round_id = snapshot_repo.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    _, branch_version_id = _branch(
        snapshot_repo, generation_round_id=round_id, candidate_index=1
    )
    revision = scene_repo.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        scene_order=1,
        expected_parent_revision_id=None,
        scene_contract_id=contract_id,
        text="冻结文本。",
        actor_type="human",
        actor_id="author",
        change_reason="seed",
    )
    snapshot_repo.freeze_branch_version(branch_version_id)

    with pytest.raises(DataIntegrityError, match="frozen"):
        scene_repo.create_revision(
            scene_id=scene_id,
            branch_version_id=branch_version_id,
            scene_order=1,
            expected_parent_revision_id=revision.scene_revision_id,
            scene_contract_id=contract_id,
            text="不应写入。",
            actor_type="human",
            actor_id="author",
            change_reason="late edit",
        )
    with pytest.raises(sqlite3.IntegrityError, match="immutable"):
        conn.execute(
            """
            UPDATE writing_branch_scenes
            SET scene_order = 2
            WHERE branch_version_id = ?
            """,
            (branch_version_id,),
        )


def test_ai_revision_requires_auditable_generation_or_repair_task() -> None:
    conn = make_schema_db()
    scene_repo, snapshot_repo, scene_id, contract_id = _active_scene_contract(conn)
    round_id = snapshot_repo.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    _, branch_version_id = _branch(
        snapshot_repo, generation_round_id=round_id, candidate_index=1
    )
    with pytest.raises(DataIntegrityError, match="generation or repair task"):
        scene_repo.create_revision(
            scene_id=scene_id,
            branch_version_id=branch_version_id,
            scene_order=1,
            expected_parent_revision_id=None,
            scene_contract_id=contract_id,
            text="缺少任务审计的AI正文。",
            actor_type="ai",
            actor_id="writer-a",
            change_reason="candidate",
        )


def test_ai_repair_revision_requires_real_in_scope_eligible_task() -> None:
    conn = make_schema_db()
    scene_repo, snapshot_repo, scene_id, contract_id = _active_scene_contract(conn)
    round_id = snapshot_repo.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    branch_id, branch_version_id = _branch(
        snapshot_repo, generation_round_id=round_id, candidate_index=1
    )
    source = scene_repo.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        scene_order=1,
        expected_parent_revision_id=None,
        scene_contract_id=contract_id,
        text="待局部修复的正文。",
        actor_type="ai",
        actor_id="writer-a",
        change_reason="candidate",
        generation_task_id=branch_id,
    )

    with pytest.raises(DataIntegrityError, match="real repair task"):
        scene_repo.create_revision(
            scene_id=scene_id,
            branch_version_id=branch_version_id,
            scene_order=1,
            expected_parent_revision_id=source.scene_revision_id,
            scene_contract_id=contract_id,
            text="伪任务修复正文。",
            actor_type="ai",
            actor_id="repairer-a",
            change_reason="repair",
            repair_task_id=999,
        )

    repair_task_id = scene_repo.create_repair_task(
        project_id=1,
        chapter_id=1,
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        source_revision_id=source.scene_revision_id,
        scene_contract_id=contract_id,
        issue="修正动作连续性",
        created_by="reviewer-a",
    )
    repaired = scene_repo.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        scene_order=1,
        expected_parent_revision_id=source.scene_revision_id,
        scene_contract_id=contract_id,
        text="完成局部修复后的正文。",
        actor_type="ai",
        actor_id="repairer-a",
        change_reason="repair",
        repair_task_id=repair_task_id,
    )
    assert repaired.parent_revision_id == source.scene_revision_id

    conn.execute(
        "UPDATE writing_scene_repair_tasks SET status = 'completed' WHERE repair_task_id = ?",
        (repair_task_id,),
    )
    with pytest.raises(DataIntegrityError, match="not eligible"):
        scene_repo.create_revision(
            scene_id=scene_id,
            branch_version_id=branch_version_id,
            scene_order=1,
            expected_parent_revision_id=repaired.scene_revision_id,
            scene_contract_id=contract_id,
            text="重复消费已完成任务。",
            actor_type="ai",
            actor_id="repairer-a",
            change_reason="repair",
            repair_task_id=repair_task_id,
        )


def test_ai_revision_rejects_both_generation_and_repair_tasks() -> None:
    conn = make_schema_db()
    scene_repo, snapshot_repo, scene_id, contract_id = _active_scene_contract(conn)
    round_id = snapshot_repo.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    branch_id, branch_version_id = _branch(
        snapshot_repo, generation_round_id=round_id, candidate_index=1
    )
    with pytest.raises(DataIntegrityError, match="exactly one"):
        scene_repo.create_revision(
            scene_id=scene_id,
            branch_version_id=branch_version_id,
            scene_order=1,
            expected_parent_revision_id=None,
            scene_contract_id=contract_id,
            text="双任务来源不明确。",
            actor_type="ai",
            actor_id="writer-a",
            change_reason="candidate",
            generation_task_id=branch_id,
            repair_task_id=1,
        )


def test_branch_binding_rejects_revision_from_another_scene() -> None:
    conn = make_schema_db()
    scene_repo, snapshot_repo, scene_id, contract_id = _active_scene_contract(conn)
    other_scene_id = scene_repo.create_scene(
        project_id=1,
        chapter_id=1,
        logical_scene_key="scene-2",
        scene_order=2,
    )
    other_contract_id = scene_repo.create_contract(
        scene_id=other_scene_id,
        version=1,
        contract_hash="contract-2",
        source_bundle_hash="source-2",
        created_by="architect-b",
        status="approved",
    )
    scene_repo.assemble_four_layer_contract(
        scene_contract_id=other_contract_id,
        hard_constraints=[{"clause_key": "hard-1", "clause_text": "hard"}],
        source_dna=[{"clause_key": "source-1", "clause_text": "source"}],
        soft_goals=[{"clause_key": "soft-1", "clause_text": "soft"}],
        creative_openings=[
            {"clause_key": "opening-1", "clause_text": "opening one"},
            {"clause_key": "opening-2", "clause_text": "opening two"},
        ],
    )
    insert_contract_approve_reviews(conn, other_contract_id)
    scene_repo.activate_contract(other_contract_id)
    round_id = snapshot_repo.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    _, first_branch = _branch(
        snapshot_repo, generation_round_id=round_id, candidate_index=1
    )
    other_revision = scene_repo.create_revision(
        scene_id=other_scene_id,
        branch_version_id=first_branch,
        scene_order=2,
        expected_parent_revision_id=None,
        scene_contract_id=other_contract_id,
        text="属于第二场景。",
        actor_type="human",
        actor_id="author",
        change_reason="seed",
    )
    _, second_branch = _branch(
        snapshot_repo, generation_round_id=round_id, candidate_index=2
    )
    with pytest.raises(DataIntegrityError, match="does not belong"):
        scene_repo.bind_existing_revision(
            branch_version_id=second_branch,
            scene_order=1,
            scene_id=scene_id,
            scene_revision_id=other_revision.scene_revision_id,
        )


def test_create_contract_cannot_bypass_activation_path() -> None:
    conn = make_schema_db()
    _project(conn)
    scene_repo = SceneRepository(conn)
    scene_id = scene_repo.create_scene(
        project_id=1,
        chapter_id=1,
        logical_scene_key="scene-1",
        scene_order=1,
    )
    with pytest.raises(DataIntegrityError, match="cannot activate"):
        scene_repo.create_contract(
            scene_id=scene_id,
            version=1,
            contract_hash="contract",
            source_bundle_hash="source",
            created_by="architect",
            status="active",
        )
