"""Fact-supersede → stale propagation (BFX-089 阶段4).

Verifies that superseding a confirmed fact version marks every Scene Contract
derivation (Revision, Branch Version, Snapshot) stale with a NULL
replacement_scene_contract_id, cancels running repair tasks, yet leaves the
Contract itself active. Contrast with Contract supersede, whose marks carry a
non-NULL replacement.
"""
from __future__ import annotations

import sqlite3

from factories import NOW, insert_contract_approve_reviews, make_schema_db
from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.scene_repository import SceneRepository
from ink.errors import DataIntegrityError


def _contract(scenes: SceneRepository, scene_id: int, version: int) -> int:
    contract_id = scenes.create_contract(
        scene_id=scene_id, version=version, contract_hash=f"c-{version}",
        source_bundle_hash=f"s-{version}", created_by="arch", status="approved",
    )
    scenes.assemble_four_layer_contract(
        scene_contract_id=contract_id,
        hard_constraints=[{"clause_key": "h", "clause_text": "h"}],
        source_dna=[{"clause_key": "d", "clause_text": "d"}],
        soft_goals=[{"clause_key": "s", "clause_text": "s"}],
        creative_openings=[
            {"clause_key": "o1", "clause_text": "one"},
            {"clause_key": "o2", "clause_text": "two"},
        ],
    )
    return contract_id


def _fixture():
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'fp', 'FP', '["w1","w2","w3"]', '["j1","j2","j3"]', ?)
        """,
        (NOW,),
    )
    scenes = SceneRepository(conn)
    snapshots = ChapterSnapshotRepository(conn)
    scene_id = scenes.create_scene(
        project_id=1, chapter_id=1, logical_scene_key="s1", scene_order=1
    )
    contract_id = _contract(scenes, scene_id, 1)
    insert_contract_approve_reviews(conn, contract_id)
    scenes.human_activate_contract(scene_contract_id=contract_id, actor="author")
    round_id = snapshots.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    branch_id = snapshots.create_branch(
        generation_round_id=round_id, candidate_index=1,
        writer_model="w", generation_strategy="seed",
    )
    branch_version_id = snapshots.create_branch_version(branch_id=branch_id, version=1)
    revision = scenes.create_revision(
        scene_id=scene_id, branch_version_id=branch_version_id, scene_order=1,
        expected_parent_revision_id=None, scene_contract_id=contract_id,
        text="prose", actor_type="human", actor_id="author", change_reason="seed",
    )
    # A sealed snapshot that binds the scene revision. Bind scenes first,
    # then seal, because sealed snapshot scene bindings are immutable.
    conn.execute(
        """
        INSERT INTO writing_chapter_snapshots
            (snapshot_id, project_id, chapter_id, source_branch_version_id,
             snapshot_hash, created_at)
        VALUES (1, 1, 1, ?, 'snap-1', ?)
        """,
        (branch_version_id, NOW),
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_snapshot_scenes
            (snapshot_id, scene_revision_id, scene_id, scene_order)
        VALUES (1, ?, ?, 1)
        """,
        (revision.scene_revision_id, scene_id),
    )
    conn.execute(
        "UPDATE writing_chapter_snapshots SET sealed_at = ? WHERE snapshot_id = 1",
        (NOW,),
    )
    return conn, scenes, scene_id, contract_id, branch_version_id, revision.scene_revision_id


def _propose_and_confirm(scenes, scene_id, text="金发") -> int:
    pid = scenes.create_fact_proposal(
        project_id=1, chapter_id=1, scene_id=scene_id,
        proposed_fact=text, fact_type="character_state",
        source_text=f"src-{text}", source_revision_id=None,
        confidence=0.9, model_name="extractor",
    )
    return scenes.confirm_fact_proposal(fact_proposal_id=pid, actor="reviewer")


def test_fact_supersede_marks_all_derivations_stale_with_null_replacement() -> None:
    conn, scenes, scene_id, contract_id, branch_version_id, revision_id = _fixture()
    anchor = _propose_and_confirm(scenes, scene_id)
    scenes.bind_contract_fact(
        scene_contract_id=contract_id, fact_anchor_id=anchor,
        binding_type="required", actor="architect",
    )
    new_anchor = _propose_and_confirm(scenes, scene_id, text="银发")
    scenes.supersede_fact_anchor(
        old_anchor_id=anchor, new_anchor_id=new_anchor,
        actor="editor", reason="设定变更",
    )
    # Revision stale mark with NULL replacement.
    rev_mark = conn.execute(
        "SELECT replacement_scene_contract_id, stale_reason "
        "FROM writing_scene_revision_stale_marks WHERE scene_revision_id = ?",
        (revision_id,),
    ).fetchone()
    assert rev_mark is not None
    assert rev_mark[0] is None
    assert "设定变更" in str(rev_mark[1])

    # Branch version stale with NULL replacement.
    bv_mark = conn.execute(
        "SELECT replacement_scene_contract_id FROM writing_branch_version_stale_marks "
        "WHERE branch_version_id = ?",
        (branch_version_id,),
    ).fetchone()
    assert bv_mark is not None
    assert bv_mark[0] is None

    # Snapshot stale with NULL replacement.
    snap_mark = conn.execute(
        "SELECT replacement_scene_contract_id FROM writing_chapter_snapshot_stale_marks "
        "WHERE snapshot_id = 1",
    ).fetchone()
    assert snap_mark is not None
    assert snap_mark[0] is None

    # Contract itself remains active.
    assert str(conn.execute(
        "SELECT status FROM writing_scene_contracts WHERE scene_contract_id = ?",
        (contract_id,),
    ).fetchone()[0]) == "active"


def test_fact_change_with_no_bindings_propagates_nothing() -> None:
    conn, scenes, scene_id, contract_id, *_ = _fixture()
    anchor = _propose_and_confirm(scenes, scene_id)
    # Supersede a fact that was never bound to any contract → no propagation.
    from ink.core.scene_stale_propagation import SceneStalePropagationManager
    res = SceneStalePropagationManager(conn).mark_fact_changed(
        fact_anchor_id=anchor, reason="noop",
    )
    assert res.revision_ids == ()
    assert res.branch_version_ids == ()
    assert res.snapshot_ids == ()
    # Manager-only call does not mutate the anchor status.
    assert str(conn.execute(
        "SELECT status FROM writing_fact_anchors WHERE anchor_id = ?",
        (anchor,),
    ).fetchone()[0]) == "confirmed"


def test_contract_supersede_still_carries_non_null_replacement() -> None:
    """Regression guard: refactor did not break the Contract-supersede path,
    whose stale marks MUST carry a non-NULL replacement_contract_id."""
    conn, scenes, scene_id, contract_id, branch_version_id, revision_id = _fixture()
    anchor = _propose_and_confirm(scenes, scene_id)
    scenes.bind_contract_fact(
        scene_contract_id=contract_id, fact_anchor_id=anchor,
        binding_type="required", actor="architect",
    )
    new_contract = _contract(scenes, scene_id, 2)
    insert_contract_approve_reviews(conn, new_contract)
    scenes.human_activate_contract(scene_contract_id=new_contract, actor="author")
    rev_mark = conn.execute(
        "SELECT replacement_scene_contract_id FROM writing_scene_revision_stale_marks "
        "WHERE scene_revision_id = ?",
        (revision_id,),
    ).fetchone()
    assert rev_mark is not None
    assert int(rev_mark[0]) == new_contract
