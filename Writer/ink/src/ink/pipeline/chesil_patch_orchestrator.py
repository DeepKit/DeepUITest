from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path

from ink.core.text_repository import TextRepository
from ink.errors import ConfigError, DataIntegrityError
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.time import now_utc_iso


@dataclass(frozen=True)
class ChesilPatchResult:
    applied_revision_ids: tuple[int, ...]
    reviewed_chapters: tuple[int, ...]
    review_ids: tuple[int, ...]


class ChesilPatchOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway) -> None:
        self.conn = conn
        self.gateway = gateway

    def apply(self, package_path: str | Path, *, project_id: int) -> ChesilPatchResult:
        package = json.loads(Path(package_path).read_text(encoding="utf-8"))
        if package.get("handoff_type") != "chesil_to_ink_candidate_patch":
            raise ValueError("not a Chesil→Ink patch package")
        governance = package.get("governance", {})
        if not governance.get("apply_as_new_revision_only"):
            raise ValueError("unsafe patch package: new-revision-only gate missing")
        if not governance.get("rerun_ink_review_required"):
            raise ValueError("unsafe patch package: review gate missing")
        if int(package.get("source_project_id")) != project_id:
            raise ValueError("patch project does not match target project")
        patches = package.get("patches")
        if not isinstance(patches, list) or not patches:
            raise ValueError("patch package contains no revisions")

        repository = TextRepository(self.conn)
        applied: list[int] = []
        chapters: set[int] = set()
        started = not self.conn.in_transaction
        try:
            if started:
                self.conn.execute("BEGIN")
            for patch in patches:
                shot_id = str(patch["ink_shot_id"])
                run_id = int(patch["ink_run_id"])
                shot = self.conn.execute(
                    """
                    SELECT chapter_id,status FROM writing_shots
                    WHERE project_id=? AND shot_id=? AND run_id=?
                    """,
                    (project_id, shot_id, run_id),
                ).fetchone()
                if shot is None:
                    raise DataIntegrityError(f"patch target not found: {shot_id}/{run_id}")
                if str(shot[1]) != "soft_sealed":
                    raise DataIntegrityError(
                        f"Chesil patch requires soft_sealed target, got {shot[1]}: {shot_id}"
                    )
                current = self.conn.execute(
                    """
                    SELECT revision_id,text FROM v_current_text
                    WHERE shot_id=? AND run_id=?
                    """,
                    (shot_id, run_id),
                ).fetchone()
                if current is None:
                    raise DataIntegrityError(f"current text missing: {shot_id}/{run_id}")
                current_hash = hashlib.sha256(str(current[1]).encode("utf-8")).hexdigest()
                if current_hash != str(patch["expected_source_text_sha256"]):
                    raise DataIntegrityError(
                        f"stale Chesil patch: current text changed for {shot_id}/{run_id}"
                    )
                replacement = str(patch["replacement_text"])
                replacement_hash = hashlib.sha256(replacement.encode("utf-8")).hexdigest()
                if replacement_hash != str(patch["replacement_text_sha256"]):
                    raise DataIntegrityError(f"replacement hash mismatch: {shot_id}/{run_id}")
                revision_id = repository.write_revision(
                    shot_id,
                    run_id,
                    replacement,
                    source_revision_id=int(current[0]),
                    seal="none",
                )
                applied.append(revision_id)
                chapters.add(int(shot[0]))
                self.conn.execute(
                    """
                    INSERT INTO writing_runtime_events
                        (project_id,run_id,shot_id,event_type,event_payload,created_at)
                    VALUES (?,?,?,?,?,?)
                    """,
                    (
                        project_id,
                        run_id,
                        shot_id,
                        "chesil_patch_applied",
                        json.dumps(
                            {
                                "ink_revision_id": revision_id,
                                "source_revision_id": int(current[0]),
                                "chesil_revision_id": patch.get("chisel_revision_id"),
                                "replacement_text_sha256": replacement_hash,
                                "reason": patch.get("reason"),
                            },
                            ensure_ascii=False,
                            sort_keys=True,
                        ),
                        now_utc_iso(),
                    ),
                )
            if started:
                self.conn.commit()
        except Exception:
            if started:
                self.conn.rollback()
            raise

        review_ids: list[int] = []
        for chapter_id in sorted(chapters):
            run_rows = {
                int(row[0])
                for row in self.conn.execute(
                    """
                    SELECT DISTINCT run_id FROM writing_shots
                    WHERE project_id=? AND chapter_id=? AND shot_id IN ({})
                    """.format(",".join("?" for _ in patches)),
                    (project_id, chapter_id, *[str(p["ink_shot_id"]) for p in patches]),
                ).fetchall()
            }
            if len(run_rows) != 1:
                raise ConfigError(
                    f"Chesil patch chapter {chapter_id} spans multiple runs: {sorted(run_rows)}"
                )
            review = ChapterReviewOrchestrator(self.conn, self.gateway).review_chapter(
                project_id, chapter_id, next(iter(run_rows))
            )
            review_ids.append(review.review_id)
        return ChesilPatchResult(tuple(applied), tuple(sorted(chapters)), tuple(review_ids))
