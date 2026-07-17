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
from factories import NOW, insert_contract_approve_reviews, insert_passing_accept_gates


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
        insert_passing_accept_gates(conn, bv_id)
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
    assert payload["data"]["would"] == (
        "run hard gates + record decisions + seal snapshot + CAS head + emit CHAPTER_ACCEPTED"
    )
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
    assert payload["data"]["canonical_command"] == "export"
    assert payload["data"]["snapshot_ids"] == [payload_accept_snapshot := payload["data"]["snapshot_ids"][0]]
    assert payload_accept_snapshot > 0

    rc, canonical = _run(db_path, ["export", "--project-id", "1"])
    assert rc == 0, canonical
    assert canonical["data"]["artifact"] == "定稿正文。"
    assert canonical["data"]["snapshot_ids"] == [payload_accept_snapshot]

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


def test_canonical_export_writes_text_sidecar_and_trace_event() -> None:
    db_path = _make_file_db()
    bv_id = _seed_selected_frozen_branch(db_path)
    rc, accepted = _run(db_path, [
        "scene-accept", "--project-id", "1", "--chapter-id", "1",
        "--branch-version-id", str(bv_id), "--actor", "editor:zhang",
    ])
    assert rc == 0, accepted
    output = Path(db_path).with_suffix(".txt")
    rc, payload = _run(db_path, [
        "export", "--project-id", "1", "--output", str(output),
    ])
    assert rc == 0, payload
    assert output.read_bytes().decode("utf-8") == "定稿正文。"
    sidecar = Path(f"{output}.metadata.json")
    metadata = json.loads(sidecar.read_text(encoding="utf-8"))
    assert metadata["authority"] == "active_sealed_non_stale_chapter_snapshot"
    assert metadata["artifact_sha256"] == payload["data"]["artifact_sha256"]
    assert metadata["chapters"][0]["snapshot_id"] == accepted["data"]["snapshot_id"]
    conn = sqlite3.connect(db_path)
    event = conn.execute(
        "SELECT event_payload FROM writing_runtime_events WHERE event_type = 'EXPORT_COMPLETED' ORDER BY event_id DESC LIMIT 1"
    ).fetchone()
    conn.close()
    assert json.loads(event[0])["artifact_sha256"] == metadata["artifact_sha256"]
    output.unlink(missing_ok=True)
    sidecar.unlink(missing_ok=True)
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
    assert data["legacy_status"] == "unavailable"
    assert data["scene_status"] == "ok"
    assert data["match"] is False
    Path(db_path).unlink(missing_ok=True)


def test_export_fails_closed_for_stale_active_snapshot() -> None:
    db_path = _make_file_db()
    bv_id = _seed_selected_frozen_branch(db_path)
    rc, accepted = _run(db_path, [
        "scene-accept", "--project-id", "1", "--chapter-id", "1",
        "--branch-version-id", str(bv_id), "--actor", "editor:zhang",
    ])
    assert rc == 0, accepted
    conn = sqlite3.connect(db_path)
    source_contract = conn.execute(
        "SELECT scene_contract_id FROM writing_scene_revisions LIMIT 1"
    ).fetchone()[0]
    conn.execute(
        """
        INSERT INTO writing_chapter_snapshot_stale_marks (
            snapshot_id, source_scene_contract_id,
            replacement_scene_contract_id, stale_reason, marked_at
        ) VALUES (?, ?, ?, 'counterfactual stale', '2026-07-15T00:00:00Z')
        """,
        (accepted["data"]["snapshot_id"], source_contract, source_contract),
    )
    conn.commit()
    conn.close()
    rc, _ = _run(db_path, ["export", "--project-id", "1"])
    assert rc != 0
    Path(db_path).unlink(missing_ok=True)


def test_export_ignores_legacy_accepted_shot_when_snapshot_exists() -> None:
    db_path = _make_file_db()
    bv_id = _seed_selected_frozen_branch(db_path)
    rc, accepted = _run(db_path, [
        "scene-accept", "--project-id", "1", "--chapter-id", "1",
        "--branch-version-id", str(bv_id), "--actor", "editor:zhang",
    ])
    assert rc == 0, accepted
    conn = sqlite3.connect(db_path)
    conn.execute(
        "INSERT INTO writing_sessions (session_id, project_id, started_at) VALUES (99, 1, '2026-07-15T00:00:00Z')"
    )
    conn.execute(
        "INSERT INTO writing_runs (run_id, project_id, session_id, run_attempt, started_at, status) VALUES (99, 1, 99, 1, '2026-07-15T00:00:00Z', 'completed')"
    )
    conn.execute(
        """
        INSERT INTO writing_shots (
            shot_id, project_id, chapter_id, run_id, logical_shot_id,
            status, created_at, updated_at
        ) VALUES ('legacy-x', 1, 1, 99, 'legacy-x', 'hard_sealed',
                  '2026-07-15T00:00:00Z', '2026-07-15T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_reviews (
            project_id, chapter_id, run_id, status,
            chapter_continuity_hard, pov_consistency, character_consistency,
            chapter_hook_soft, rhythm_curve, motif_density,
            info_gap_lifecycle, chapter_coherence, quality_gate_passed,
            reviewed_at
        ) VALUES (1, 1, 99, 'accepted',
                  90, 90, 90, 90, 90, 90, 90, 90, 1,
                  '2026-07-15T00:00:00Z')
        """
    )
    conn.commit()
    conn.close()
    rc, payload = _run(db_path, ["export", "--project-id", "1"])
    assert rc == 0, payload
    assert payload["data"]["artifact"] == "定稿正文。"
    Path(db_path).unlink(missing_ok=True)
