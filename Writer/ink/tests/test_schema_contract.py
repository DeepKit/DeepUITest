from __future__ import annotations

import sqlite3

import pytest

from factories import NOW, insert_minimal_draft, insert_raw_score, make_schema_db
from ink.schema import load_schema_sql


def test_schema_executes_all_ddl() -> None:
    conn = make_schema_db()

    counts = dict(
        conn.execute(
            """
            SELECT type, count(*)
            FROM sqlite_master
            WHERE type IN ('table','index','trigger','view')
            GROUP BY type
            """
        ).fetchall()
    )

    assert counts == {"index": 105, "table": 79, "trigger": 31, "view": 1}
    assert conn.execute("PRAGMA foreign_key_check").fetchall() == []


def test_schema_includes_v11_decision_and_source_tables() -> None:
    conn = make_schema_db()
    table_names = {
        row[0]
        for row in conn.execute(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'table'
            """
        ).fetchall()
    }

    expected = {
        "writing_source_documents",
        "writing_atomic_source_clauses",
        "writing_source_extraction_runs",
        "writing_decision_sessions",
        "writing_decision_option_sets",
        "writing_contract_versions",
        "writing_contract_patches",
        "writing_source_coverage_matrix",
        "writing_process_file_manifests",
    }
    assert expected <= table_names


def test_schema_does_not_contain_pre_m0_legacy_patterns() -> None:
    schema = load_schema_sql()

    forbidden = [
        "UNIQUE (draft_id, judge_role)",
        "occurred_at",
        "writing_shots WHERE session_id",
        "WHERE session_id = ? FROM writing_shots",
    ]
    for pattern in forbidden:
        assert pattern not in schema


def test_runtime_events_use_created_at() -> None:
    conn = make_schema_db()
    columns = {
        row[1]
        for row in conn.execute("PRAGMA table_info(writing_runtime_events)").fetchall()
    }

    assert "created_at" in columns
    assert "occurred_at" not in columns


def test_jury_raw_scores_support_base_and_escalated_rounds() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)

    for slot, model, role in [
        (1, "judge-a", "text"),
        (2, "judge-b", "literary"),
        (3, "judge-c", "cross_shot"),
    ]:
        insert_raw_score(conn, ids["draft_id"], ids["shot_contract_id"], 1, slot, model, role)

    roles = ["text", "literary", "cross_shot", "text", "literary"]
    for slot in range(1, 6):
        insert_raw_score(
            conn,
            ids["draft_id"],
            ids["shot_contract_id"],
            2,
            slot,
            f"judge-upgrade-{slot}",
            roles[slot - 1],
        )

    rows = conn.execute(
        """
        SELECT jury_round, count(*), count(DISTINCT judge_model), max(judge_slot)
        FROM writing_jury_raw_scores
        GROUP BY jury_round
        ORDER BY jury_round
        """
    ).fetchall()
    assert rows == [(1, 3, 3, 3), (2, 5, 5, 5)]


def test_jury_raw_scores_reject_duplicate_slot_or_model_in_same_round() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    insert_raw_score(conn, ids["draft_id"], ids["shot_contract_id"], 1, 1, "judge-a", "text")

    with pytest.raises(sqlite3.IntegrityError):
        insert_raw_score(conn, ids["draft_id"], ids["shot_contract_id"], 1, 1, "judge-b", "literary")

    with pytest.raises(sqlite3.IntegrityError):
        insert_raw_score(conn, ids["draft_id"], ids["shot_contract_id"], 1, 2, "judge-a", "literary")


def test_jury_raw_scores_reject_self_judging_and_audit_is_empty() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn, writer_model="writer-a")

    with pytest.raises(sqlite3.IntegrityError):
        insert_raw_score(conn, ids["draft_id"], ids["shot_contract_id"], 1, 1, "writer-a", "text")

    insert_raw_score(conn, ids["draft_id"], ids["shot_contract_id"], 1, 1, "judge-a", "text")

    audit_rows = conn.execute(
        """
        SELECT r.draft_id, r.judge_model, d.writer_model
        FROM writing_jury_raw_scores r
        JOIN writing_drafts d ON r.draft_id = d.draft_id
        WHERE r.judge_model = d.writer_model
        """
    ).fetchall()
    assert audit_rows == []


def test_session_checkpoints_allow_null_shot_id_and_reject_bad_shot_id_shape() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)

    conn.execute(
        """
        INSERT INTO writing_session_checkpoints
            (session_id, run_id, shot_id, phase, checkpoint_payload, payload_checksum, created_at)
        VALUES (?, ?, NULL, 'session', '{}', 'hash-session', ?)
        """,
        (ids["session_id"], ids["run_id"], NOW),
    )

    with pytest.raises(sqlite3.IntegrityError):
        conn.execute(
            """
            INSERT INTO writing_session_checkpoints
                (session_id, run_id, shot_id, phase, checkpoint_payload, payload_checksum, created_at)
            VALUES (?, ?, 'shot-without-run', 'shot', '{}', 'hash-bad', ?)
            """,
            (ids["session_id"], ids["run_id"], NOW),
        )

    conn.execute(
        """
        INSERT INTO writing_session_checkpoints
            (session_id, run_id, shot_id, phase, checkpoint_payload, payload_checksum, created_at)
        VALUES (?, ?, ?, 'shot', '{}', 'hash-shot', ?)
        """,
        (ids["session_id"], ids["run_id"], ids["shot_id"], NOW),
    )


def test_v_current_text_returns_single_current_revision_over_latest_unsealed() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)

    conn.execute(
        """
        INSERT INTO writing_shot_revisions
            (shot_id, run_id, revision_sequence, text, is_current, sealed_at, sealed_by, created_at)
        VALUES (?, ?, 1, 'sealed text', 1, ?, 'shot_soft', ?)
        """,
        (ids["shot_id"], ids["run_id"], NOW, NOW),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_revisions
            (shot_id, run_id, revision_sequence, text, is_current, created_at)
        VALUES (?, ?, 2, 'newer unsealed text', 0, ?)
        """,
        (ids["shot_id"], ids["run_id"], NOW),
    )

    rows = conn.execute(
        "SELECT text, revision_sequence, is_current FROM v_current_text WHERE shot_id = ?",
        (ids["shot_id"],),
    ).fetchall()
    assert rows == [("sealed text", 1, 1)]
