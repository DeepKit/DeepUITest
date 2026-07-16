from __future__ import annotations

import sqlite3

import pytest

from factories import NOW, insert_contract_approve_reviews, make_schema_db


def _insert_project(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'scene-first', 'Scene First',
             '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c"]', ?)
        """,
        (NOW,),
    )


def test_scene_first_shadow_tables_exist_without_removing_legacy_tables() -> None:
    conn = make_schema_db()
    names = {
        str(row[0])
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        ).fetchall()
    }
    assert {
        "writing_scenes",
        "writing_scene_contracts",
        "writing_scene_contract_clauses",
        "writing_scene_revisions",
        "writing_scene_internal_shots",
        "writing_chapter_generation_rounds",
        "writing_chapter_candidate_branches",
        "writing_chapter_candidate_branch_versions",
        "writing_branch_scenes",
        "writing_chapter_snapshots",
        "writing_chapter_snapshot_scenes",
        "writing_chapter_heads",
        "writing_shots",
        "writing_shot_revisions",
    } <= names


def test_internal_shot_has_no_canonical_or_acceptance_columns() -> None:
    conn = make_schema_db()
    columns = {
        str(row[1])
        for row in conn.execute(
            "PRAGMA table_info(writing_scene_internal_shots)"
        ).fetchall()
    }
    assert columns == {
        "internal_shot_id",
        "scene_revision_id",
        "shot_order",
        "purpose",
        "text_start",
        "text_end",
        "created_at",
    }
    assert not ({"is_current", "is_canonical", "accepted", "sealed_at"} & columns)


def test_same_scene_allows_only_one_active_contract() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    scene_id = conn.execute(
        """
        INSERT INTO writing_scenes
            (project_id, chapter_id, logical_scene_key, scene_order, created_at)
        VALUES (1, 1, 's1', 1, ?)
        """,
        (NOW,),
    ).lastrowid
    first_id = conn.execute(
        """
        INSERT INTO writing_scene_contracts
            (scene_id, version, status, contract_hash, source_bundle_hash,
             created_by, created_at)
        VALUES (?, 1, 'approved', 'h1', 'source-1', 'architect-a', ?)
        """,
        (scene_id, NOW),
    ).lastrowid
    second_id = conn.execute(
        """
        INSERT INTO writing_scene_contracts
            (scene_id, version, status, contract_hash, source_bundle_hash,
             created_by, created_at)
        VALUES (?, 2, 'approved', 'h2', 'source-2', 'architect-b', ?)
        """,
        (scene_id, NOW),
    ).lastrowid
    for contract_id in (first_id, second_id):
        for layer, key in (
            ("hard_constraint", "hard-1"),
            ("source_dna", "source-1"),
            ("soft_goal", "soft-1"),
            ("creative_opening", "opening-1"),
            ("creative_opening", "opening-2"),
        ):
            conn.execute(
                """
                INSERT INTO writing_scene_contract_clauses
                    (scene_contract_id, layer, clause_key, clause_text, severity,
                     authority_rank, created_at)
                VALUES (?, ?, ?, 'text', 'hard', 10, ?)
                """,
                (contract_id, layer, key, NOW),
            )
    insert_contract_approve_reviews(conn, int(first_id))
    insert_contract_approve_reviews(conn, int(second_id))
    conn.execute(
        "UPDATE writing_scene_contracts SET status = 'active' WHERE scene_contract_id = ?",
        (first_id,),
    )
    with pytest.raises(sqlite3.IntegrityError):
        conn.execute(
            "UPDATE writing_scene_contracts SET status = 'active' WHERE scene_contract_id = ?",
            (second_id,),
        )


def test_scene_revision_update_is_blocked_by_database_trigger() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    scene_id = conn.execute(
        """
        INSERT INTO writing_scenes
            (project_id, chapter_id, logical_scene_key, scene_order, created_at)
        VALUES (1, 1, 's1', 1, ?)
        """,
        (NOW,),
    ).lastrowid
    contract_id = conn.execute(
        """
        INSERT INTO writing_scene_contracts
            (scene_id, version, status, contract_hash, source_bundle_hash,
             created_by, created_at)
        VALUES (?, 1, 'approved', 'h1', 'source-1', 'architect-a', ?)
        """,
        (scene_id, NOW),
    ).lastrowid
    for layer, key, text in (
        ("hard_constraint", "hard-1", "hard"),
        ("source_dna", "source-1", "source"),
        ("soft_goal", "soft-1", "soft"),
        ("creative_opening", "opening-1", "opening one"),
        ("creative_opening", "opening-2", "opening two"),
    ):
        conn.execute(
            """
            INSERT INTO writing_scene_contract_clauses
                (scene_contract_id, layer, clause_key, clause_text, severity,
                 authority_rank, created_at)
            VALUES (?, ?, ?, ?, 'hard', 10, ?)
            """,
            (contract_id, layer, key, text, NOW),
        )
    insert_contract_approve_reviews(conn, int(contract_id))
    conn.execute(
        "UPDATE writing_scene_contracts SET status = 'active' WHERE scene_contract_id = ?",
        (contract_id,),
    )
    revision_id = conn.execute(
        """
        INSERT INTO writing_scene_revisions
            (scene_id, scene_contract_id, text, text_hash, actor_type, actor_id,
             change_reason, created_at)
        VALUES (?, ?, 'original', 'text-hash', 'human', 'author', 'seed', ?)
        """,
        (scene_id, contract_id, NOW),
    ).lastrowid
    with pytest.raises(sqlite3.IntegrityError, match="immutable"):
        conn.execute(
            "UPDATE writing_scene_revisions SET text = 'mutated' WHERE scene_revision_id = ?",
            (revision_id,),
        )
