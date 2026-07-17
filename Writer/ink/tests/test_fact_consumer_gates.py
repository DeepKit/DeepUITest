"""Fact-stale consumer gate (BFX-089 阶段5).

End-to-end invariant: once a confirmed fact bound to a Scene Contract is
superseded, the downstream Branch Version's Scene lineage is stale, and the
consumer gates must fail-closed — accept-gate evidence recording refuses the
branch, and the active-snapshot read path refuses a stale snapshot. This
proves Fact-supersede propagation plugs into the same fail-closed doors as
Contract-supersede, without any new bypass.
"""
from __future__ import annotations

import sqlite3

import pytest

from factories import NOW, insert_contract_approve_reviews, make_schema_db
from ink.core.chapter_accept_gate_repository import ChapterAcceptGateRepository
from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.scene_repository import SceneRepository
from ink.errors import DataIntegrityError


def _fixture():
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'fg', 'FG', '["w1","w2","w3"]', '["j1","j2","j3"]', ?)
        """,
        (NOW,),
    )
    scenes = SceneRepository(conn)
    snapshots = ChapterSnapshotRepository(conn)
    gates = ChapterAcceptGateRepository(conn)
    scene_id = scenes.create_scene(
        project_id=1, chapter_id=1, logical_scene_key="s1", scene_order=1
    )
    contract_id = scenes.create_contract(
        scene_id=scene_id, version=1, contract_hash="h1",
        source_bundle_hash="s1", created_by="arch", status="approved",
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
    return conn, scenes, snapshots, gates, scene_id, contract_id, branch_version_id, revision.scene_revision_id


def _confirm_fact(scenes, scene_id, text="金发") -> int:
    pid = scenes.create_fact_proposal(
        project_id=1, chapter_id=1, scene_id=scene_id,
        proposed_fact=text, fact_type="character_state",
        source_text=f"src-{text}", source_revision_id=None,
        confidence=0.9, model_name="extractor",
    )
    return scenes.confirm_fact_proposal(fact_proposal_id=pid, actor="reviewer")


def test_accept_gate_refuses_branch_after_fact_supersede() -> None:
    conn, scenes, snapshots, gates, scene_id, contract_id, branch_version_id, _ = _fixture()
    anchor = _confirm_fact(scenes, scene_id)
    scenes.bind_contract_fact(
        scene_contract_id=contract_id, fact_anchor_id=anchor,
        binding_type="required", actor="architect",
    )
    # Branch lineage is fresh before supersede — consumer door passes.
    gates._assert_branch_fresh(branch_version_id)

    new_anchor = _confirm_fact(scenes, scene_id, text="银发")
    scenes.supersede_fact_anchor(
        old_anchor_id=anchor, new_anchor_id=new_anchor,
        actor="editor", reason="设定变更",
    )
    # After supersede the branch lineage is stale — the consumer door that
    # accept-gate evidence recording relies on must fail-closed.
    with pytest.raises(DataIntegrityError):
        gates._assert_branch_fresh(branch_version_id)


def test_active_snapshot_read_refuses_stale_after_fact_supersede() -> None:
    conn, scenes, snapshots, gates, scene_id, contract_id, branch_version_id, _ = _fixture()
    anchor = _confirm_fact(scenes, scene_id)
    scenes.bind_contract_fact(
        scene_contract_id=contract_id, fact_anchor_id=anchor,
        binding_type="required", actor="architect",
    )
    # Build + seal a snapshot and point the chapter head at it.
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
            (snapshot_id, scene_order, scene_id, scene_revision_id)
        VALUES (1, 0, ?, (SELECT scene_revision_id FROM writing_scene_revisions
                          WHERE scene_contract_id = ? LIMIT 1))
        """,
        (scene_id, contract_id),
    )
    conn.execute("UPDATE writing_chapter_snapshots SET sealed_at = ? WHERE snapshot_id = 1", (NOW,))
    conn.execute(
        """
        INSERT INTO writing_chapter_heads
            (project_id, chapter_id, active_snapshot_id, version, updated_at)
        VALUES (1, 1, 1, 1, ?)
        """,
        (NOW,),
    )
    # Fresh read works.
    assert snapshots.get_active_snapshot_id(project_id=1, chapter_id=1) == 1

    # Supersede the bound fact → snapshot becomes stale → read must refuse.
    new_anchor = _confirm_fact(scenes, scene_id, text="银发")
    scenes.supersede_fact_anchor(
        old_anchor_id=anchor, new_anchor_id=new_anchor,
        actor="editor", reason="设定变更",
    )
    with pytest.raises(DataIntegrityError):
        snapshots.get_active_snapshot_id(project_id=1, chapter_id=1)
