"""Scene-first invariant tests for the P0-2..P0-5 shadow layer.

These tests exercise the new repository methods directly against a fresh
schema DB (no production path touched). They lock down:

  * INV-CONTRACT-002/003: dual-master blind contract review (architect
    self-check → independent blind reviewer from a different family).
  * INV-CONTRACT-006: AI Scene revisions must reference a real, in-scope
    generation (candidate branch) task.
  * INV-AUTH-002: AI actor cannot activate a Scene Contract.
  * INV-ACCEPT-004: scene-first accept requires a non-null decision id.
  * INV-FACT-004: fact proposal confirmation is human-gated and writes an
    enforceable fact anchor.
"""
from __future__ import annotations

import sqlite3

import pytest

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.scene_repository import SceneRepository
from ink.errors import DataIntegrityError
from factories import NOW, make_schema_db


def _project(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'sf-inv', 'SF Invariants',
             '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c"]', ?)
        """,
        (NOW,),
    )


def _draft_contract_fixture(conn: sqlite3.Connection):
    """A scene with a DRAFT (non-activated) contract authored by model:glm,
    plus a planned generation round (id=1)."""
    _project(conn)
    conn.execute(
        "INSERT INTO writing_chapter_generation_rounds "
        "(generation_round_id, project_id, chapter_id, round_number, status, created_at, updated_at) "
        "VALUES (1, 1, 1, 1, 'planned', ?, ?)",
        (NOW, NOW),
    )
    scene_repo = SceneRepository(conn)
    snapshot_repo = ChapterSnapshotRepository(conn)
    scene_id = scene_repo.create_scene(
        project_id=1, chapter_id=1, logical_scene_key="scene-1", scene_order=1
    )
    contract_id = scene_repo.create_contract(
        scene_id=scene_id, version=1, contract_hash="c-hash",
        source_bundle_hash="s-hash", created_by="model:glm",
        status="draft",
    )
    return scene_repo, snapshot_repo, scene_id, contract_id


def _branch(snapshot_repo, round_id=1, candidate_index=1):
    branch_id = snapshot_repo.create_branch(
        generation_round_id=round_id, candidate_index=candidate_index,
        writer_model=f"writer-{candidate_index}",
        generation_strategy=f"strategy-{candidate_index}",
    )
    version_id = snapshot_repo.create_branch_version(branch_id=branch_id, version=1)
    return branch_id, version_id


# ── P0-3: four-layer assembly ────────────────────────────────────────────

def test_assemble_four_layer_contract_requires_two_creative_openings() -> None:
    conn = make_schema_db()
    scene_repo, _, _, contract_id = _draft_contract_fixture(conn)
    with pytest.raises(DataIntegrityError, match="two creative_opening"):
        scene_repo.assemble_four_layer_contract(
            scene_contract_id=contract_id,
            hard_constraints=[{"clause_key": "h1", "clause_text": "hard"}],
            source_dna=[{"clause_key": "d1", "clause_text": "dna"}],
            soft_goals=[{"clause_key": "g1", "clause_text": "goal"}],
            creative_openings=[{"clause_key": "o1", "clause_text": "only one"}],
        )


def test_assemble_four_layer_contract_inserts_all_layers() -> None:
    conn = make_schema_db()
    scene_repo, _, _, contract_id = _draft_contract_fixture(conn)
    scene_repo.assemble_four_layer_contract(
        scene_contract_id=contract_id,
        hard_constraints=[{"clause_key": "h1", "clause_text": "hard"}],
        source_dna=[{"clause_key": "d1", "clause_text": "dna"}],
        soft_goals=[{"clause_key": "g1", "clause_text": "goal"}],
        creative_openings=[
            {"clause_key": "o1", "clause_text": "open A"},
            {"clause_key": "o2", "clause_text": "open B"},
        ],
    )
    layers = dict(
        conn.execute(
            "SELECT layer, count(*) FROM writing_scene_contract_clauses "
            "WHERE scene_contract_id = ? GROUP BY layer",
            (contract_id,),
        ).fetchall()
    )
    assert layers == {"hard_constraint": 1, "source_dna": 1, "soft_goal": 1, "creative_opening": 2}


# ── P0-3: dual-master blind review (INV-CONTRACT-002/003) ───────────────

def test_contract_self_check_moves_draft_to_self_checked() -> None:
    conn = make_schema_db()
    scene_repo, _, _, contract_id = _draft_contract_fixture(conn)
    scene_repo.self_check_contract(
        scene_contract_id=contract_id, reviewer_model="model:glm",
        reviewer_family="glm", prompt_hash="p1",
        blind_context_hash="b1", verdict="approve", evidence_json="{}",
    )
    status = conn.execute(
        "SELECT status FROM writing_scene_contracts WHERE scene_contract_id = ?",
        (contract_id,),
    ).fetchone()[0]
    assert status == "self_checked"


def test_independent_review_requires_self_checked_and_different_family() -> None:
    conn = make_schema_db()
    scene_repo, _, _, contract_id = _draft_contract_fixture(conn)
    # not self_checked yet → reject
    with pytest.raises(DataIntegrityError, match="self_checked"):
        scene_repo.independent_review_contract(
            scene_contract_id=contract_id, reviewer_model="model:qwen",
            reviewer_family="qwen", prompt_hash="p2",
            blind_context_hash="b2", verdict="approve", evidence_json="{}",
        )
    scene_repo.self_check_contract(
        scene_contract_id=contract_id, reviewer_model="model:glm",
        reviewer_family="glm", prompt_hash="p1",
        blind_context_hash="b1", verdict="approve", evidence_json="{}",
    )
    # same family as architect (glm) → reject
    with pytest.raises(DataIntegrityError, match="family must differ"):
        scene_repo.independent_review_contract(
            scene_contract_id=contract_id, reviewer_model="model:glm2",
            reviewer_family="glm", prompt_hash="p2",
            blind_context_hash="b2", verdict="approve", evidence_json="{}",
        )
    # different family (qwen) → ok, moves to under_review
    scene_repo.independent_review_contract(
        scene_contract_id=contract_id, reviewer_model="model:qwen",
        reviewer_family="qwen", prompt_hash="p2",
        blind_context_hash="b2", verdict="approve", evidence_json="{}",
    )
    status = conn.execute(
        "SELECT status FROM writing_scene_contracts WHERE scene_contract_id = ?",
        (contract_id,),
    ).fetchone()[0]
    assert status == "under_review"


def test_review_order_auto_increments_per_contract() -> None:
    conn = make_schema_db()
    scene_repo, _, _, contract_id = _draft_contract_fixture(conn)
    scene_repo.self_check_contract(
        scene_contract_id=contract_id, reviewer_model="model:glm",
        reviewer_family="glm", prompt_hash="p1",
        blind_context_hash="b1", verdict="approve", evidence_json="{}",
    )
    scene_repo.independent_review_contract(
        scene_contract_id=contract_id, reviewer_model="model:qwen",
        reviewer_family="qwen", prompt_hash="p2",
        blind_context_hash="b2", verdict="revise", evidence_json="{}",
    )
    orders = [
        r[0] for r in conn.execute(
            "SELECT review_order FROM writing_scene_contract_reviews "
            "WHERE scene_contract_id = ? ORDER BY review_order",
            (contract_id,),
        ).fetchall()
    ]
    assert orders == [1, 2]


# ── P0-3: human-only contract activation (INV-AUTH-002) ─────────────────

def test_ai_actor_cannot_activate_contract() -> None:
    conn = make_schema_db()
    scene_repo, _, _, contract_id = _draft_contract_fixture(conn)
    scene_repo.self_check_contract(
        scene_contract_id=contract_id, reviewer_model="model:glm",
        reviewer_family="glm", prompt_hash="p1",
        blind_context_hash="b1", verdict="approve", evidence_json="{}",
    )
    scene_repo.independent_review_contract(
        scene_contract_id=contract_id, reviewer_model="model:qwen",
        reviewer_family="qwen", prompt_hash="p2",
        blind_context_hash="b2", verdict="approve", evidence_json="{}",
    )
    from ink.core.actor_guard import ActorPermissionError
    with pytest.raises(ActorPermissionError):
        scene_repo.human_activate_contract(scene_contract_id=contract_id, actor="ai:auto")
    # human actor succeeds
    scene_repo.human_activate_contract(scene_contract_id=contract_id, actor="author")
    status = conn.execute(
        "SELECT status FROM writing_scene_contracts WHERE scene_contract_id = ?",
        (contract_id,),
    ).fetchone()[0]
    assert status == "active"
    # runtime event emitted
    n = conn.execute(
        "SELECT count(*) FROM writing_runtime_events WHERE event_type = 'contract_activated'"
    ).fetchone()[0]
    assert n == 1


# ── P0-3: amendment records (INV-CONTRACT-005) ──────────────────────────

def test_submit_amendment_records_history_without_mutating_clauses() -> None:
    conn = make_schema_db()
    scene_repo, _, _, contract_id = _draft_contract_fixture(conn)
    scene_repo.add_contract_clause(
        scene_contract_id=contract_id, layer="hard_constraint",
        clause_key="h1", clause_text="original", severity="hard",
    )
    amid = scene_repo.submit_amendment(
        scene_contract_id=contract_id, amending_actor="author",
        amendment_reason="tighten continuity", clause_changes_json='{"h1":"updated"}',
    )
    assert amid is not None
    # original clause text untouched (append-only lineage)
    txt = conn.execute(
        "SELECT clause_text FROM writing_scene_contract_clauses "
        "WHERE scene_contract_id = ? AND clause_key = 'h1'",
        (contract_id,),
    ).fetchone()[0]
    assert txt == "original"


# ── P0-5: guidance cards + fact proposals ───────────────────────────────

def test_guidance_card_lifecycle() -> None:
    conn = make_schema_db()
    _project(conn)
    scene_repo = SceneRepository(conn)
    scene_id = scene_repo.create_scene(
        project_id=1, chapter_id=1, logical_scene_key="s1", scene_order=1
    )
    card_id = scene_repo.create_guidance_card(
        project_id=1, chapter_id=1, scene_id=scene_id,
        card_type="continuity_warning", trigger_context="scene 3 vs scene 1",
        guidance_text="reconcile the bruise timeline", model_name="model:glm",
        prompt_hash="ph",
    )
    assert card_id is not None
    status = conn.execute(
        "SELECT status FROM writing_guidance_cards WHERE guidance_card_id = ?",
        (card_id,),
    ).fetchone()[0]
    assert status == "active"
    scene_repo.dismiss_guidance_card(guidance_card_id=card_id)
    status = conn.execute(
        "SELECT status FROM writing_guidance_cards WHERE guidance_card_id = ?",
        (card_id,),
    ).fetchone()[0]
    assert status == "dismissed"
    with pytest.raises(DataIntegrityError, match="unknown guidance card"):
        scene_repo.dismiss_guidance_card(guidance_card_id=999999)


def test_fact_proposal_confirmation_is_human_gated_and_writes_anchor() -> None:
    conn = make_schema_db()
    _project(conn)
    scene_repo = SceneRepository(conn)
    scene_id = scene_repo.create_scene(
        project_id=1, chapter_id=1, logical_scene_key="s1", scene_order=1
    )
    fp_id = scene_repo.create_fact_proposal(
        project_id=1, chapter_id=1, scene_id=scene_id,
        proposed_fact="character X has a scar on left hand",
        fact_type="character_state", source_text="she hid her left hand",
        source_revision_id=None, confidence=0.92, model_name="model:glm",
    )
    from ink.core.actor_guard import ActorPermissionError
    with pytest.raises(ActorPermissionError):
        scene_repo.confirm_fact_proposal(fact_proposal_id=fp_id, actor="ai:auto")
    anchor_id = scene_repo.confirm_fact_proposal(fact_proposal_id=fp_id, actor="author")
    assert anchor_id is not None
    status = conn.execute(
        "SELECT status FROM writing_fact_proposals WHERE fact_proposal_id = ?",
        (fp_id,),
    ).fetchone()[0]
    assert status == "confirmed"
    # anchor written and enforceable
    n = conn.execute(
        "SELECT count(*) FROM writing_fact_anchors WHERE project_id = 1"
    ).fetchone()[0]
    assert n == 1
    # cannot confirm twice
    with pytest.raises(DataIntegrityError, match="only a proposed fact"):
        scene_repo.confirm_fact_proposal(fact_proposal_id=fp_id, actor="author")


def test_fact_proposal_rejection_is_human_gated() -> None:
    conn = make_schema_db()
    _project(conn)
    scene_repo = SceneRepository(conn)
    scene_id = scene_repo.create_scene(
        project_id=1, chapter_id=1, logical_scene_key="s1", scene_order=1
    )
    fp_id = scene_repo.create_fact_proposal(
        project_id=1, chapter_id=1, scene_id=scene_id,
        proposed_fact="bad fact", fact_type="world_rule",
        source_text="x", source_revision_id=None, confidence=0.3,
        model_name="model:glm",
    )
    from ink.core.actor_guard import ActorPermissionError
    with pytest.raises(ActorPermissionError):
        scene_repo.reject_fact_proposal(fact_proposal_id=fp_id, actor="ai:auto")
    scene_repo.reject_fact_proposal(fact_proposal_id=fp_id, actor="author")
    status = conn.execute(
        "SELECT status FROM writing_fact_proposals WHERE fact_proposal_id = ?",
        (fp_id,),
    ).fetchone()[0]
    assert status == "rejected"


# ── P0-2: scene-first accept requires a decision id (INV-ACCEPT-004) ────

def test_accept_chapter_requires_decision_id_by_default() -> None:
    conn = make_schema_db()
    _project(conn)
    conn.execute(
        "INSERT INTO writing_chapter_generation_rounds "
        "(generation_round_id, project_id, chapter_id, round_number, status, created_at, updated_at) "
        "VALUES (1, 1, 1, 1, 'planned', ?, ?)",
        (NOW, NOW),
    )
    scene_repo = SceneRepository(conn)
    snapshots = ChapterSnapshotRepository(conn)
    scene_id = scene_repo.create_scene(
        project_id=1, chapter_id=1, logical_scene_key="s1", scene_order=1
    )
    contract_id = scene_repo.create_contract(
        scene_id=scene_id, version=1, contract_hash="c",
        source_bundle_hash="s", created_by="arch", status="approved",
    )
    scene_repo.activate_contract(contract_id)
    branch_id, bv_id = _branch(snapshots)
    scene_repo.create_revision(
        scene_id=scene_id, branch_version_id=bv_id, scene_order=1,
        expected_parent_revision_id=None, scene_contract_id=contract_id,
        text="t", actor_type="ai", actor_id="w",
        change_reason="c", generation_task_id=branch_id,
    )
    snapshots.freeze_branch_version(bv_id)
    conn.execute(
        "UPDATE writing_chapter_candidate_branches SET status='eligible' WHERE branch_id=?",
        (branch_id,),
    )
    snapshots.select_branch(branch_id)
    with pytest.raises(DataIntegrityError, match="decision_id"):
        snapshots.accept_chapter(
            branch_version_id=bv_id, expected_head_version=0,
            accepted_decision_id=None,
        )
