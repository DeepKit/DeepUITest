"""Guidance/Anti-pattern Card lifecycle (BFX-089 阶段6).

Invariants:
- A card is created ``active``.
- ``apply_guidance_card`` flips it to ``applied``, bumps ``use_count``, and
  refuses non-active cards (no re-application of dismissed/stale/applied).
- ``apply_guidance_card`` enforces ``max_uses``.
- ``dismiss_guidance_card`` flips to ``dismissed`` and blocks later apply.
- When a bound fact is superseded OR the Scene Contract is superseded, the
  scene-scoped active cards flip to ``stale`` automatically — guidance issued
  against a superseded source of truth cannot be applied to fresh work.
"""
from __future__ import annotations

import pytest

from factories import NOW, insert_contract_approve_reviews, make_schema_db
from ink.core.scene_repository import SceneRepository
from ink.errors import DataIntegrityError


def _fixture():
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'gc', 'GC', '["w1","w2","w3"]', '["j1","j2","j3"]', ?)
        """,
        (NOW,),
    )
    scenes = SceneRepository(conn)
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
    return conn, scenes, scene_id, contract_id


def _card_id(scenes, scene_id, **kw) -> int:
    return scenes.create_guidance_card(
        project_id=1, chapter_id=1, scene_id=scene_id,
        card_type="continuity_warning", trigger_context="ctx",
        guidance_text="watch the timeline", model_name="reviewer",
        prompt_hash="p1", **kw,
    )


def test_apply_flips_active_to_applied_and_bumps_use_count() -> None:
    conn, scenes, scene_id, _ = _fixture()
    cid = _card_id(scenes, scene_id)
    scenes.apply_guidance_card(guidance_card_id=cid, applied_to_chapter_id=1)
    row = conn.execute(
        "SELECT status, use_count, applied_at, applied_to_chapter_id "
        "FROM writing_guidance_cards WHERE guidance_card_id = ?",
        (cid,),
    ).fetchone()
    assert str(row[0]) == "applied"
    assert int(row[1]) == 1
    assert row[2] is not None
    assert int(row[3]) == 1


def test_apply_refuses_non_active_card() -> None:
    conn, scenes, scene_id, _ = _fixture()
    cid = _card_id(scenes, scene_id)
    scenes.dismiss_guidance_card(guidance_card_id=cid)
    with pytest.raises(DataIntegrityError):
        scenes.apply_guidance_card(guidance_card_id=cid, applied_to_chapter_id=1)


def test_apply_refuses_reapply_after_applied() -> None:
    conn, scenes, scene_id, _ = _fixture()
    cid = _card_id(scenes, scene_id)
    scenes.apply_guidance_card(guidance_card_id=cid, applied_to_chapter_id=1)
    with pytest.raises(DataIntegrityError):
        scenes.apply_guidance_card(guidance_card_id=cid, applied_to_chapter_id=1)


def test_apply_enforces_max_uses_ceiling() -> None:
    conn, scenes, scene_id, _ = _fixture()
    cid = _card_id(scenes, scene_id)
    # Consume the single allowed use, then re-arm the card as active so the
    # status guard does not fire first — the max_uses guard must catch it.
    conn.execute(
        "UPDATE writing_guidance_cards SET max_uses = 1, use_count = 1, status = 'active' "
        "WHERE guidance_card_id = ?",
        (cid,),
    )
    with pytest.raises(DataIntegrityError):
        scenes.apply_guidance_card(guidance_card_id=cid, applied_to_chapter_id=1)


def test_fact_supersede_flips_scene_active_cards_stale() -> None:
    conn, scenes, scene_id, contract_id = _fixture()
    anchor = scenes.create_fact_proposal(
        project_id=1, chapter_id=1, scene_id=scene_id,
        proposed_fact="金发", fact_type="character_state",
        source_text="src", source_revision_id=None,
        confidence=0.9, model_name="ext",
    )
    anchor = scenes.confirm_fact_proposal(fact_proposal_id=anchor, actor="rev")
    scenes.bind_contract_fact(
        scene_contract_id=contract_id, fact_anchor_id=anchor,
        binding_type="required", actor="arch",
    )
    fresh = _card_id(scenes, scene_id)
    dismissed = _card_id(scenes, scene_id)
    scenes.dismiss_guidance_card(guidance_card_id=dismissed)

    new_anchor = scenes.create_fact_proposal(
        project_id=1, chapter_id=1, scene_id=scene_id,
        proposed_fact="银发", fact_type="character_state",
        source_text="src2", source_revision_id=None,
        confidence=0.9, model_name="ext",
    )
    new_anchor = scenes.confirm_fact_proposal(fact_proposal_id=new_anchor, actor="rev")
    scenes.supersede_fact_anchor(
        old_anchor_id=anchor, new_anchor_id=new_anchor,
        actor="editor", reason="设定变更",
    )

    statuses = dict(
        conn.execute(
            "SELECT guidance_card_id, status FROM writing_guidance_cards "
            "WHERE guidance_card_id IN (?, ?)",
            (fresh, dismissed),
        ).fetchall()
    )
    assert statuses[fresh] == "stale"
    # A previously-dismissed card is not touched by the stale sweep.
    assert statuses[dismissed] == "dismissed"

    # A stale card cannot be applied to fresh work.
    with pytest.raises(DataIntegrityError):
        scenes.apply_guidance_card(guidance_card_id=fresh, applied_to_chapter_id=1)


def test_contract_supersede_flips_scene_active_cards_stale() -> None:
    conn, scenes, scene_id, contract_id = _fixture()
    fresh = _card_id(scenes, scene_id)

    # Activate a new contract version for the same scene — this supersedes the
    # previous active contract and must sweep the scene's active cards to stale.
    new_contract_id = scenes.create_contract(
        scene_id=scene_id, version=2, contract_hash="h2",
        source_bundle_hash="s2", created_by="arch", status="approved",
    )
    scenes.assemble_four_layer_contract(
        scene_contract_id=new_contract_id,
        hard_constraints=[{"clause_key": "h", "clause_text": "h2"}],
        source_dna=[{"clause_key": "d", "clause_text": "d2"}],
        soft_goals=[{"clause_key": "s", "clause_text": "s2"}],
        creative_openings=[
            {"clause_key": "o1", "clause_text": "one2"},
            {"clause_key": "o2", "clause_text": "two2"},
        ],
    )
    insert_contract_approve_reviews(conn, new_contract_id)
    scenes.human_activate_contract(scene_contract_id=new_contract_id, actor="author")

    status = conn.execute(
        "SELECT status FROM writing_guidance_cards WHERE guidance_card_id = ?",
        (fresh,),
    ).fetchone()[0]
    assert str(status) == "stale"
