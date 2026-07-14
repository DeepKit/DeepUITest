from __future__ import annotations

import sqlite3

import pytest

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.scene_repository import SceneRepository
from ink.errors import ConcurrentModificationError
from factories import NOW, make_schema_db


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
    snapshots.freeze_branch_version(branch_version_id)
    conn.execute(
        "UPDATE writing_chapter_candidate_branches SET status = 'eligible' WHERE branch_id = ?",
        (branch_id,),
    )
    snapshots.select_branch(branch_id)
    head = snapshots.accept_chapter(
        branch_version_id=branch_version_id,
        expected_head_version=0,
        accepted_decision_id=None,
        require_decision_id=False,
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
    with pytest.raises(ConcurrentModificationError, match="expected 0"):
        snapshots.accept_chapter(
            branch_version_id=branch_version_id,
            expected_head_version=0,
            accepted_decision_id=None,
            require_decision_id=False,
        )
    after = int(
        conn.execute("SELECT COUNT(*) FROM writing_chapter_snapshots").fetchone()[0]
    )
    assert after == before
