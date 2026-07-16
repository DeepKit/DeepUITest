from __future__ import annotations

import hashlib
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from factories import NOW, insert_minimal_draft, make_schema_db
from ink.errors import DataIntegrityError
from ink.pipeline.chesil_patch_orchestrator import ChesilPatchOrchestrator


def _setup():
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    conn.execute(
        """
        INSERT INTO writing_shot_revisions
            (revision_id,shot_id,run_id,revision_sequence,text,is_current,
             sealed_at,sealed_by,created_at)
        VALUES (101,?,?,1,'原始正文。',0,?,'shot_soft',?)
        """,
        (ids["shot_id"], ids["run_id"], NOW, NOW),
    )
    conn.execute(
        "UPDATE writing_shots SET status='soft_sealed' WHERE shot_id=?",
        (ids["shot_id"],),
    )
    conn.commit()
    return conn, ids


def _package(path: Path, ids: dict, source_text: str = "原始正文。") -> Path:
    replacement = "Chesil校正正文。"
    path.write_text(
        json.dumps(
            {
                "handoff_type": "chesil_to_ink_candidate_patch",
                "source_project_id": 1,
                "governance": {
                    "apply_as_new_revision_only": True,
                    "rerun_ink_review_required": True,
                },
                "patches": [
                    {
                        "ink_shot_id": ids["shot_id"],
                        "ink_run_id": ids["run_id"],
                        "expected_source_text_sha256": hashlib.sha256(
                            source_text.encode()
                        ).hexdigest(),
                        "replacement_text": replacement,
                        "replacement_text_sha256": hashlib.sha256(
                            replacement.encode()
                        ).hexdigest(),
                        "chisel_revision_id": "cr-1",
                        "reason": "LCW-R1 approved",
                    }
                ],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    return path


def test_apply_chesil_patch_writes_lineage_event_and_reruns_review(
    tmp_path, monkeypatch
) -> None:
    conn, ids = _setup()

    class FakeReview:
        def __init__(self, conn, gateway):
            pass

        def review_chapter(self, project_id, chapter_id, run_id):
            assert (project_id, chapter_id, run_id) == (1, 1, 20)
            return SimpleNamespace(review_id=77)

    monkeypatch.setattr(
        "ink.pipeline.chesil_patch_orchestrator.ChapterReviewOrchestrator",
        FakeReview,
    )
    result = ChesilPatchOrchestrator(conn, object()).apply(
        _package(tmp_path / "patch.json", ids), project_id=1
    )

    assert result.review_ids == (77,)
    revision = conn.execute(
        """
        SELECT text,source_revision_id FROM writing_shot_revisions
        WHERE revision_id=?
        """,
        (result.applied_revision_ids[0],),
    ).fetchone()
    assert tuple(revision) == ("Chesil校正正文。", 101)
    event = conn.execute(
        "SELECT event_type,event_payload FROM writing_runtime_events"
    ).fetchone()
    assert event[0] == "chesil_patch_applied"
    assert json.loads(event[1])["chesil_revision_id"] == "cr-1"


def test_apply_chesil_patch_rejects_stale_source(tmp_path) -> None:
    conn, ids = _setup()
    with pytest.raises(DataIntegrityError, match="stale Chesil patch"):
        ChesilPatchOrchestrator(conn, object()).apply(
            _package(tmp_path / "patch.json", ids, source_text="旧正文"),
            project_id=1,
        )
    assert conn.execute(
        "SELECT count(*) FROM writing_shot_revisions"
    ).fetchone()[0] == 1
