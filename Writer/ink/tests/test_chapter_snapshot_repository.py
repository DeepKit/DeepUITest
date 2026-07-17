from __future__ import annotations

import json
import sqlite3

import pytest

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.scene_repository import SceneRepository
from ink.errors import ConcurrentModificationError
from factories import (
    NOW,
    insert_contract_approve_reviews,
    insert_passing_accept_gates,
    make_schema_db,
)


def _accepted_fixture() -> tuple[
    sqlite3.Connection,
    SceneRepository,
    ChapterSnapshotRepository,
    int,
    int,
    int,
    int,
]:
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'snapshot', 'Snapshot',
             '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c"]', ?)
        """,
        (NOW,),
    )
    scenes = SceneRepository(conn)
    snapshots = ChapterSnapshotRepository(conn)
    scene_id = scenes.create_scene(
        project_id=1,
        chapter_id=1,
        logical_scene_key="scene-1",
        scene_order=1,
    )
    contract_id = scenes.create_contract(
        scene_id=scene_id,
        version=1,
        contract_hash="contract",
        source_bundle_hash="source",
        created_by="architect",
        status="approved",
    )
    scenes.assemble_four_layer_contract(
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
    scenes.activate_contract(contract_id)
    round_id = snapshots.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    branch_id = snapshots.create_branch(
        generation_round_id=round_id,
        candidate_index=1,
        writer_model="writer-a",
        generation_strategy="quiet-pressure",
    )
    branch_version_id = snapshots.create_branch_version(branch_id=branch_id, version=1)
    revision = scenes.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        scene_order=1,
        expected_parent_revision_id=None,
        scene_contract_id=contract_id,
        text="被接受的场景正文。",
        actor_type="ai",
        actor_id="writer-a",
        change_reason="candidate",
        generation_task_id=branch_id,
    )
    snapshots.freeze_branch_version(branch_version_id, actor="author")
    insert_passing_accept_gates(conn, branch_version_id)
    conn.execute(
        "UPDATE writing_chapter_candidate_branches SET status = 'eligible' WHERE branch_id = ?",
        (branch_id,),
    )
    snapshots.select_branch(branch_id)
    head = snapshots.accept_chapter(
        branch_version_id=branch_version_id,
        expected_head_version=0,
        actor="editor:zhang",
        reason="approved fixture",
        preconditions_json={"branch_version_id": branch_version_id},
        selection_decision_type="auto_selected",
        selection_evidence_json={"fixture": True},
    )
    return (
        conn,
        scenes,
        snapshots,
        scene_id,
        contract_id,
        branch_id,
        revision.scene_revision_id,
    )


def _next_selected_candidate(
    conn: sqlite3.Connection,
    scenes: SceneRepository,
    snapshots: ChapterSnapshotRepository,
    *,
    scene_id: int,
    contract_id: int,
) -> int:
    round_id = snapshots.create_generation_round(
        project_id=1, chapter_id=1, round_number=2
    )
    branch_id = snapshots.create_branch(
        generation_round_id=round_id,
        candidate_index=1,
        writer_model="writer-b",
        generation_strategy="fault-injection",
    )
    branch_version_id = snapshots.create_branch_version(branch_id=branch_id, version=1)
    scenes.create_revision(
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        scene_order=1,
        expected_parent_revision_id=None,
        scene_contract_id=contract_id,
        text="第二个候选场景正文。",
        actor_type="ai",
        actor_id="writer-b",
        change_reason="fault injection candidate",
        generation_task_id=branch_id,
    )
    snapshots.freeze_branch_version(branch_version_id, actor="author")
    insert_passing_accept_gates(conn, branch_version_id)
    conn.execute(
        "UPDATE writing_chapter_candidate_branches SET status = 'eligible' WHERE branch_id = ?",
        (branch_id,),
    )
    snapshots.select_branch(branch_id)
    return branch_version_id


def test_accept_creates_sealed_snapshot_and_active_head() -> None:
    conn, _, snapshots, _, _, _, _ = _accepted_fixture()
    head = conn.execute(
        """
        SELECT h.active_snapshot_id, h.version, s.sealed_at, s.snapshot_hash
        FROM writing_chapter_heads h
        JOIN writing_chapter_snapshots s ON s.snapshot_id = h.active_snapshot_id
        WHERE h.project_id = 1 AND h.chapter_id = 1
        """
    ).fetchone()
    assert head is not None
    assert int(head[1]) == 1
    assert head[2] is not None
    assert len(str(head[3])) == 64
    assert snapshots.read_active_chapter_text(project_id=1, chapter_id=1) == "被接受的场景正文。"
    snapshot_id = int(head[0])
    decision = conn.execute(
        "SELECT accepted_decision_id FROM writing_chapter_snapshots WHERE snapshot_id = ?",
        (snapshot_id,),
    ).fetchone()
    assert decision is not None and decision[0] is not None
    assert int(conn.execute("SELECT COUNT(*) FROM writing_selection_decisions").fetchone()[0]) == 1
    assert int(conn.execute("SELECT COUNT(*) FROM writing_human_decisions").fetchone()[0]) == 1
    event = conn.execute(
        "SELECT event_payload FROM writing_runtime_events WHERE event_type = 'CHAPTER_ACCEPTED'"
    ).fetchone()
    assert event is not None
    payload = json.loads(str(event[0]))
    assert payload["accepted_decision_id"] == int(decision[0])
    assert isinstance(payload["selection_decision_id"], int)


@pytest.mark.parametrize(
    ("trigger_table", "trigger_action"),
    [
        ("writing_selection_decisions", "INSERT"),
        ("writing_human_decisions", "INSERT"),
        ("writing_chapter_snapshots", "INSERT"),
        ("writing_chapter_heads", "UPDATE"),
        ("writing_runtime_events", "INSERT"),
    ],
)
def test_accept_fault_rolls_back_all_authority_rows(
    trigger_table: str,
    trigger_action: str,
) -> None:
    conn, scenes, snapshots, scene_id, contract_id, _, _ = _accepted_fixture()
    branch_version_id = _next_selected_candidate(
        conn, scenes, snapshots, scene_id=scene_id, contract_id=contract_id
    )
    before = {
        "selection": int(conn.execute("SELECT COUNT(*) FROM writing_selection_decisions").fetchone()[0]),
        "human": int(conn.execute("SELECT COUNT(*) FROM writing_human_decisions").fetchone()[0]),
        "snapshot": int(conn.execute("SELECT COUNT(*) FROM writing_chapter_snapshots").fetchone()[0]),
        "binding": int(conn.execute("SELECT COUNT(*) FROM writing_chapter_snapshot_scenes").fetchone()[0]),
        "event": int(conn.execute("SELECT COUNT(*) FROM writing_runtime_events WHERE event_type='CHAPTER_ACCEPTED'").fetchone()[0]),
    }
    head_before = tuple(conn.execute(
        "SELECT active_snapshot_id, version FROM writing_chapter_heads WHERE project_id=1 AND chapter_id=1"
    ).fetchone())
    conn.execute(
        f"""
        CREATE TEMP TRIGGER fail_accept_stage
        BEFORE {trigger_action} ON {trigger_table}
        BEGIN
            SELECT RAISE(ABORT, 'injected accept failure');
        END
        """
    )
    with pytest.raises(sqlite3.IntegrityError, match="injected accept failure"):
        snapshots.accept_chapter(
            branch_version_id=branch_version_id,
            expected_head_version=1,
            actor="editor:zhang",
            reason="fault injection",
            preconditions_json={"branch_version_id": branch_version_id},
            selection_decision_type="human_override",
            selection_evidence_json={"fault": trigger_table},
        )
    assert int(conn.execute("SELECT COUNT(*) FROM writing_selection_decisions").fetchone()[0]) == before["selection"]
    assert int(conn.execute("SELECT COUNT(*) FROM writing_human_decisions").fetchone()[0]) == before["human"]
    assert int(conn.execute("SELECT COUNT(*) FROM writing_chapter_snapshots").fetchone()[0]) == before["snapshot"]
    assert int(conn.execute("SELECT COUNT(*) FROM writing_chapter_snapshot_scenes").fetchone()[0]) == before["binding"]
    assert int(conn.execute("SELECT COUNT(*) FROM writing_runtime_events WHERE event_type='CHAPTER_ACCEPTED'").fetchone()[0]) == before["event"]
    assert tuple(conn.execute(
        "SELECT active_snapshot_id, version FROM writing_chapter_heads WHERE project_id=1 AND chapter_id=1"
    ).fetchone()) == head_before


def test_chapter_head_is_unique_per_project_chapter() -> None:
    conn, _, _, _, _, _, _ = _accepted_fixture()
    snapshot_id = int(
        conn.execute(
            "SELECT active_snapshot_id FROM writing_chapter_heads WHERE project_id = 1 AND chapter_id = 1"
        ).fetchone()[0]
    )
    with pytest.raises(sqlite3.IntegrityError):
        conn.execute(
            """
            INSERT INTO writing_chapter_heads
                (project_id, chapter_id, active_snapshot_id, version, updated_at)
            VALUES (1, 1, ?, 2, ?)
            """,
            (snapshot_id, NOW),
        )


def test_snapshot_and_snapshot_bindings_are_immutable() -> None:
    conn, _, _, _, _, _, _ = _accepted_fixture()
    snapshot_id = int(
        conn.execute(
            "SELECT active_snapshot_id FROM writing_chapter_heads WHERE project_id = 1 AND chapter_id = 1"
        ).fetchone()[0]
    )
    with pytest.raises(sqlite3.IntegrityError, match="immutable"):
        conn.execute(
            "UPDATE writing_chapter_snapshots SET snapshot_hash = 'changed' WHERE snapshot_id = ?",
            (snapshot_id,),
        )
    with pytest.raises(sqlite3.IntegrityError, match="immutable"):
        conn.execute(
            """
            UPDATE writing_chapter_snapshot_scenes
            SET scene_order = 2
            WHERE snapshot_id = ?
            """,
            (snapshot_id,),
        )
    with pytest.raises(sqlite3.IntegrityError, match="cannot be deleted"):
        conn.execute(
            "DELETE FROM writing_chapter_snapshots WHERE snapshot_id = ?",
            (snapshot_id,),
        )


def test_referenced_scene_revision_cannot_be_deleted() -> None:
    conn, _, _, _, _, _, accepted_revision_id = _accepted_fixture()
    with pytest.raises(sqlite3.IntegrityError, match="referenced"):
        conn.execute(
            "DELETE FROM writing_scene_revisions WHERE scene_revision_id = ?",
            (accepted_revision_id,),
        )


def test_snapshot_text_does_not_follow_later_scene_revision() -> None:
    conn, scenes, snapshots, scene_id, contract_id, selected_branch_id, accepted_revision_id = (
        _accepted_fixture()
    )
    later_version_id = snapshots.create_branch_version(
        branch_id=selected_branch_id,
        version=2,
        parent_branch_version_id=1,
    )
    scenes.bind_existing_revision(
        branch_version_id=later_version_id,
        scene_order=1,
        scene_id=scene_id,
        scene_revision_id=accepted_revision_id,
    )
    scenes.create_revision(
        scene_id=scene_id,
        branch_version_id=later_version_id,
        scene_order=1,
        expected_parent_revision_id=accepted_revision_id,
        scene_contract_id=contract_id,
        text="尚未被接受的后续修订。",
        actor_type="human",
        actor_id="author",
        change_reason="post-accept repair",
    )
    assert snapshots.read_active_chapter_text(project_id=1, chapter_id=1) == "被接受的场景正文。"


def test_stale_expected_head_version_rolls_back_without_new_snapshot() -> None:
    conn, _, snapshots, _, _, selected_branch_id, _ = _accepted_fixture()
    branch_version_id = int(
        conn.execute(
            """
            SELECT branch_version_id
            FROM writing_chapter_candidate_branch_versions
            WHERE branch_id = ? AND version = 1
            """,
            (selected_branch_id,),
        ).fetchone()[0]
    )
    before = int(
        conn.execute("SELECT COUNT(*) FROM writing_chapter_snapshots").fetchone()[0]
    )
    before_decisions = int(
        conn.execute("SELECT COUNT(*) FROM writing_human_decisions").fetchone()[0]
    )
    with pytest.raises(ConcurrentModificationError, match="expected 0"):
        snapshots.accept_chapter(
            branch_version_id=branch_version_id,
            expected_head_version=0,
            actor="editor:zhang",
            reason="stale CAS attempt",
            preconditions_json={},
            selection_decision_type="human_override",
            selection_evidence_json={"stale": True},
        )
    after = int(
        conn.execute("SELECT COUNT(*) FROM writing_chapter_snapshots").fetchone()[0]
    )
    assert after == before
    assert int(
        conn.execute("SELECT COUNT(*) FROM writing_human_decisions").fetchone()[0]
    ) == before_decisions
