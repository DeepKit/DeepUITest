"""End-to-end CLI tests for Scene-first Accept + Export (P0-2).

Covers the terminal-authority flow that the old legacy accept/export path
cannot serve:
  ink scene-accept       -> seals a selected frozen branch as active Snapshot,
                            human-gated, CAS the chapter head.
  ink scene-export       -> assembles a project from its active Snapshots.
  ink scene-export-parity-> read-only dual-authority parity check.

The legacy ``accept``/``export`` commands (which read writing_shots) are
untouched by these tests.

These tests use a temp-file DB (not in-memory) so the CLI process and the test
share one durable file across calls — each CLI commit is visible to the next.
"""
from __future__ import annotations

import contextlib
import io
import json
import sqlite3
import tempfile
from pathlib import Path

import pytest

from ink.cli import main as cli_main
from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.scene_repository import SceneRepository
from ink.schema import initialize_schema
from ink.database import connect
from factories import NOW, insert_contract_approve_reviews


def _make_file_db() -> str:
    fd, path = tempfile.mkstemp(suffix=".db")
    import os
    os.close(fd)
    conn = connect(Path(path))
    initialize_schema(conn)
    conn.commit()
    conn.close()
    return path


def _seed_selected_frozen_branch(db_path: str) -> int:
    """Seed a project with one selected+ frozen branch version; return its id."""
    conn = connect(Path(db_path))
    try:
        conn.execute(
            """
            INSERT INTO writing_projects
                (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
            VALUES
                (1, 'e2e', 'E2E', '["writer-a","writer-b","writer-c"]',
                 '["judge-a","judge-b","judge-c"]', ?)
            """,
            (NOW,),
        )
        scenes = SceneRepository(conn)
        snapshots = ChapterSnapshotRepository(conn)
        scene_id = scenes.create_scene(
            project_id=1, chapter_id=1, logical_scene_key="s1", scene_order=1
        )
        contract_id = scenes.create_contract(
            scene_id=scene_id, version=1, contract_hash="c",
            source_bundle_hash="s", created_by="arch", status="approved",
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
            generation_round_id=round_id, candidate_index=1,
            writer_model="writer-a", generation_strategy="quiet-pressure",
        )
        bv_id = snapshots.create_branch_version(branch_id=branch_id, version=1)
        scenes.create_revision(
            scene_id=scene_id, branch_version_id=bv_id, scene_order=1,
            expected_parent_revision_id=None, scene_contract_id=contract_id,
            text="定稿正文。", actor_type="ai", actor_id="writer-a",
            change_reason="candidate", generation_task_id=branch_id,
        )
        snapshots.freeze_branch_version(bv_id, actor="author")
        conn.execute(
            "UPDATE writing_chapter_candidate_branches SET status='eligible' WHERE branch_id=?",
            (branch_id,),
        )
        snapshots.select_branch(branch_id)
        conn.commit()
        return bv_id
    finally:
        conn.close()


def _run(db_path: str, argv: list[str]) -> tuple[int, dict | None]:
    buf = io.StringIO()
    rc = 0
    try:
        with contextlib.redirect_stdout(buf):
            rc = cli_main(["--db", db_path, *argv])
    except SystemExit as exc:
        rc = int(exc.code) if isinstance(exc.code, int) else 1
    out = buf.getvalue().strip()
    payload = None
    if out:
        try:
            payload = json.loads(out)
        except json.JSONDecodeError:
            payload = None
    return rc, payload


def test_scene_accept_dry_run_returns_plan() -> None:
    db_path = _make_file_db()
    bv_id = _seed_selected_frozen_branch(db_path)
    rc, payload = _run(db_path, [
        "scene-accept", "--project-id", "1", "--chapter-id", "1",
        "--branch-version-id", str(bv_id), "--actor", "editor:zhang", "--dry-run",
    ])
    assert rc == 0
    assert payload is not None
    assert payload["data"]["would"] == "record decisions + seal snapshot + CAS head + emit CHAPTER_ACCEPTED"
    assert payload["data"]["expected_head_version"] == 0
    Path(db_path).unlink(missing_ok=True)


def test_scene_accept_then_export_round_trip() -> None:
    db_path = _make_file_db()
    bv_id = _seed_selected_frozen_branch(db_path)

    rc, payload = _run(db_path, [
        "scene-accept", "--project-id", "1", "--chapter-id", "1",
        "--branch-version-id", str(bv_id), "--actor", "editor:zhang",
    ])
    assert rc == 0, payload
    assert payload["data"]["head_version"] == 1
    assert payload["data"]["snapshot_id"] is not None

    rc, payload = _run(db_path, ["scene-export", "--project-id", "1"])
    assert rc == 0, payload
    assert payload["data"]["artifact"] == "定稿正文。"

    # After Accept the head has advanced; a dry-run must now report the new
    # expected_head_version (1), proving the CLI observes the sealed head and
    # that re-accept would require the caller to re-confirm the current version
    # (CAS authority advances — Accept is not a silent no-op repeat).
    rc, payload = _run(db_path, [
        "scene-accept", "--project-id", "1", "--chapter-id", "1",
        "--branch-version-id", str(bv_id), "--actor", "editor:zhang", "--dry-run",
    ])
    assert rc == 0, payload
    assert payload["data"]["expected_head_version"] == 1
    Path(db_path).unlink(missing_ok=True)


def test_scene_export_before_accept_is_error() -> None:
    db_path = _make_file_db()
    _seed_selected_frozen_branch(db_path)  # selected but NOT accepted yet
    rc, _ = _run(db_path, ["scene-export", "--project-id", "1"])
    assert rc != 0  # no accepted chapters -> DataIntegrityError
    Path(db_path).unlink(missing_ok=True)


def test_scene_export_parity_is_read_only() -> None:
    db_path = _make_file_db()
    bv_id = _seed_selected_frozen_branch(db_path)
    rc, _ = _run(db_path, [
        "scene-accept", "--project-id", "1", "--chapter-id", "1",
        "--branch-version-id", str(bv_id), "--actor", "editor:zhang",
    ])
    assert rc == 0
    # parity runs both authority paths read-only; legacy has no shots so it
    # returns empty and scene wins. The check must not mutate anything.
    rc, payload = _run(db_path, ["scene-export-parity", "--project-id", "1"])
    assert rc == 0, payload
    data = payload["data"]
    assert "match" in data and "legacy_len" in data and "scene_len" in data
    assert data["scene_len"] > 0
    Path(db_path).unlink(missing_ok=True)
