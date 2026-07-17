"""Fact lifecycle state machine + Contract binding (BFX-089 阶段2+3).

Covers:
- proposal → confirm produces an anchor with version_hash / scene_id /
  chapter_id, and persist review evidence on the proposal.
- reject persists review evidence.
- bind_contract_fact refuses non-active Contracts and non-confirmed anchors.
- list_fact_anchors_for_contract returns bound facts with version snapshot.
- supersede_fact_anchor moves old anchor to superseded, propagates stale
  marks, but leaves the Contract itself active (fact change ≠ contract
  supersede). See test_fact_stale_propagation.py for the propagation detail.
"""
from __future__ import annotations

import sqlite3

import pytest

from factories import NOW, make_schema_db
from ink.core.scene_repository import SceneRepository
from ink.errors import DataIntegrityError


def _setup() -> tuple[sqlite3.Connection, SceneRepository, int, int]:
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'fact', 'Fact', '["writer-a","writer-b","writer-c"]',
                '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
        """,
        (NOW,),
    )
    scenes = SceneRepository(conn)
    scene_id = scenes.create_scene(
        project_id=1, chapter_id=1, logical_scene_key="s1", scene_order=1
    )
    contract_id = scenes.create_contract(
        scene_id=scene_id, version=1, contract_hash="h1",
        source_bundle_hash="src1", created_by="arch", status="approved",
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
    # Activate the contract so binding is allowed.
    from factories import insert_contract_approve_reviews
    insert_contract_approve_reviews(conn, contract_id)
    scenes.human_activate_contract(scene_contract_id=contract_id, actor="author")
    return conn, scenes, scene_id, contract_id


def _propose(scenes: SceneRepository, scene_id: int) -> int:
    return scenes.create_fact_proposal(
        project_id=1, chapter_id=1, scene_id=scene_id,
        proposed_fact="角色X拥有金色长发", fact_type="character_state",
        source_text="原文:她金发随风扬起", source_revision_id=None,
        confidence=0.9, model_name="extractor-qwen",
    )


def test_confirm_writes_anchor_with_version_hash_and_review_evidence() -> None:
    conn, scenes, scene_id, contract_id = _setup()
    proposal_id = _propose(scenes, scene_id)
    anchor_id = scenes.confirm_fact_proposal(
        fact_proposal_id=proposal_id, actor="reviewer"
    )
    anchor = conn.execute(
        "SELECT version_hash, scene_id, chapter_id, status FROM writing_fact_anchors "
        "WHERE anchor_id = ?",
        (anchor_id,),
    ).fetchone()
    assert anchor[0]  # version_hash non-empty
    assert int(anchor[1]) == scene_id
    assert int(anchor[2]) == 1
    assert str(anchor[3]) == "confirmed"

    proposal = conn.execute(
        "SELECT status, reviewed_by, reviewed_at, reviewer_model, review_evidence_json "
        "FROM writing_fact_proposals WHERE fact_proposal_id = ?",
        (proposal_id,),
    ).fetchone()
    assert str(proposal[0]) == "confirmed"
    assert str(proposal[1]) == "reviewer"
    assert proposal[2]  # reviewed_at set
    assert str(proposal[3]) == "extractor-qwen"
    assert proposal[4]  # review_evidence_json set


def test_reject_persists_review_evidence() -> None:
    conn, scenes, scene_id, _ = _setup()
    proposal_id = _propose(scenes, scene_id)
    scenes.reject_fact_proposal(fact_proposal_id=proposal_id, actor="reviewer")
    row = conn.execute(
        "SELECT status, reviewed_by, reviewed_at, review_evidence_json "
        "FROM writing_fact_proposals WHERE fact_proposal_id = ?",
        (proposal_id,),
    ).fetchone()
    assert str(row[0]) == "rejected"
    assert str(row[1]) == "reviewer"
    assert row[2]
    assert row[3]


def test_bind_contract_fact_requires_active_contract_and_confirmed_anchor() -> None:
    conn, scenes, scene_id, contract_id = _setup()
    anchor_id = scenes.confirm_fact_proposal(
        fact_proposal_id=_propose(scenes, scene_id), actor="reviewer"
    )
    # Happy path.
    binding_id = scenes.bind_contract_fact(
        scene_contract_id=contract_id, fact_anchor_id=anchor_id,
        binding_type="required", actor="architect",
    )
    assert binding_id
    listed = scenes.list_fact_anchors_for_contract(contract_id)
    assert len(listed) == 1
    assert listed[0]["anchor_id"] == anchor_id
    assert listed[0]["binding_type"] == "required"
    assert listed[0]["bound_version_hash"] == listed[0]["version_hash"]

    # Bad binding_type.
    with pytest.raises(DataIntegrityError):
        scenes.bind_contract_fact(
            scene_contract_id=contract_id, fact_anchor_id=anchor_id,
            binding_type="nope", actor="architect",
        )

    # Unknown contract.
    with pytest.raises(DataIntegrityError):
        scenes.bind_contract_fact(
            scene_contract_id=999, fact_anchor_id=anchor_id,
            binding_type="context", actor="architect",
        )

    # Unknown anchor.
    with pytest.raises(DataIntegrityError):
        scenes.bind_contract_fact(
            scene_contract_id=contract_id, fact_anchor_id=999,
            binding_type="context", actor="architect",
        )


def test_supersede_fact_anchor_moves_status_and_records_replacement() -> None:
    conn, scenes, scene_id, contract_id = _setup()
    old = scenes.confirm_fact_proposal(
        fact_proposal_id=_propose(scenes, scene_id), actor="reviewer"
    )
    scenes.bind_contract_fact(
        scene_contract_id=contract_id, fact_anchor_id=old,
        binding_type="required", actor="architect",
    )
    # A new confirmed fact to supersede onto.
    new_proposal = scenes.create_fact_proposal(
        project_id=1, chapter_id=1, scene_id=scene_id,
        proposed_fact="角色X拥有银色长发", fact_type="character_state",
        source_text="原文:银发闪烁", source_revision_id=None,
        confidence=0.95, model_name="extractor-qwen",
    )
    new_anchor = scenes.confirm_fact_proposal(
        fact_proposal_id=new_proposal, actor="reviewer"
    )
    scenes.supersede_fact_anchor(
        old_anchor_id=old, new_anchor_id=new_anchor,
        actor="editor", reason="设定变更:金发→银发",
    )
    old_row = conn.execute(
        "SELECT status, superseded_by_anchor_id, supersede_reason "
        "FROM writing_fact_anchors WHERE anchor_id = ?",
        (old,),
    ).fetchone()
    assert str(old_row[0]) == "superseded"
    assert int(old_row[1]) == new_anchor
    assert "设定变更" in str(old_row[2])
    # The Contract itself is NOT superseded — fact change ≠ contract supersede.
    contract_status = conn.execute(
        "SELECT status FROM writing_scene_contracts WHERE scene_contract_id = ?",
        (contract_id,),
    ).fetchone()
    assert str(contract_status[0]) == "active"


def test_supersede_requires_confirmed_old_and_new() -> None:
    conn, scenes, scene_id, contract_id = _setup()
    with pytest.raises(DataIntegrityError):
        scenes.supersede_fact_anchor(
            old_anchor_id=999, new_anchor_id=None, actor="editor", reason="x"
        )
    old = scenes.confirm_fact_proposal(
        fact_proposal_id=_propose(scenes, scene_id), actor="reviewer"
    )
    # New anchor not yet confirmed → supersede must refuse.
    pending_new = scenes.create_fact_proposal(
        project_id=1, chapter_id=1, scene_id=scene_id,
        proposed_fact="草稿事实", fact_type="world_rule",
        source_text="src", source_revision_id=None,
        confidence=0.5, model_name="extractor-qwen",
    )
    with pytest.raises(DataIntegrityError):
        scenes.supersede_fact_anchor(
            old_anchor_id=old, new_anchor_id=pending_new,
            actor="editor", reason="x",
        )
    # Empty reason refused.
    with pytest.raises(DataIntegrityError):
        scenes.supersede_fact_anchor(
            old_anchor_id=old, new_anchor_id=None, actor="editor", reason="  "
        )


def test_deprecate_fact_anchor_marks_deprecated_with_no_replacement() -> None:
    conn, scenes, scene_id, contract_id = _setup()
    anchor_id = scenes.confirm_fact_proposal(
        fact_proposal_id=_propose(scenes, scene_id), actor="reviewer"
    )
    scenes.bind_contract_fact(
        scene_contract_id=contract_id, fact_anchor_id=anchor_id,
        binding_type="context", actor="architect",
    )
    scenes.deprecate_fact_anchor(anchor_id=anchor_id, actor="editor", reason="作废")
    row = conn.execute(
        "SELECT status, superseded_by_anchor_id FROM writing_fact_anchors WHERE anchor_id = ?",
        (anchor_id,),
    ).fetchone()
    assert str(row[0]) == "deprecated"
    assert row[1] is None
