"""Baseline importer — imports human-written chapters as locked baselines.

P0: imports Chapter 1 of 《分流》 as locked human_baseline.
The imported text is stored in shot_revisions with operation='write_generate'
and writer_persona='human_baseline', is_current=1, gate_result_json with locked=true.

This is a temporary P0 convention — the operation enum may be extended to
include 'human_baseline' in a future migration.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.utils.shot_id import generate as generate_shot_id
from inkflow.utils.hashing import text_hash_normalized
from inkflow.importers.shot_splitter import detect_shots, format_shot_review
from inkflow.models.enums import (
    ShotStatus,
    RevisionOperation,
    ContractStatus,
)


class BaselineImporter:
    """Import human-written chapters as locked baselines."""

    def __init__(self, db: sqlite3.Connection, project_id: str):
        self.db = db
        self.project_id = project_id

    def import_chapter(
        self,
        chapter_key: str,
        file_path: str | Path,
        *,
        run_id: str | None = None,
    ) -> dict:
        """Import a chapter Markdown file as locked baseline.

        Steps:
        1. Read the markdown file
        2. Detect shot boundaries
        3. Create project structure record for the chapter
        4. Create shots in writing_shots (status=done_green, locked)
        5. Create shot_contracts (status=locked)
        6. Write shot_revisions (operation=write_generate, persona=human_baseline, is_current=1)

        Args:
            chapter_key: Chapter key like 'v01.c01'.
            file_path: Path to the chapter Markdown file.
            run_id: Optional run_id. If None, generates one.

        Returns:
            Dict: {chapter_key, shot_count, total_chars, shots: [...]}
        """
        file_path = Path(file_path)
        if not file_path.exists():
            raise FileNotFoundError(f"文件不存在: {file_path}")

        text = file_path.read_text(encoding="utf-8")

        # Idempotency: reuse existing run_id for this chapter if baseline exists
        if run_id is None:
            existing = self.db.execute(
                "SELECT run_id FROM writing_shots "
                "WHERE project_id = ? AND layer_key = ? LIMIT 1",
                (self.project_id, chapter_key),
            ).fetchone()
            if existing:
                run_id = existing["run_id"]
            else:
                run_id = generate_ulid()

        # Detect shot boundaries
        shot_analysis = detect_shots(text, chapter_key)

        # Create project structure for this chapter
        layer_key = chapter_key
        self._ensure_chapter_structure(layer_key, shot_analysis["shot_count"])

        # Create a session if one doesn't exist for this run_id
        self._ensure_session(run_id, chapter_key, shot_analysis["shot_count"])

        # Import each shot
        imported_shots = []
        for shot in shot_analysis["shots"]:
            shot_id = self._import_shot(
                run_id=run_id,
                shot=shot,
                chapter_key=chapter_key,
            )
            imported_shots.append({
                "shot_id": shot_id,
                "shot_key": shot["shot_key"],
                "shot_index": shot["shot_index"],
                "title": shot["title"],
                "char_count": shot["char_count"],
            })

        total_chars = sum(s["char_count"] for s in imported_shots)

        # Mark the baseline session as completed
        self.db.execute(
            "UPDATE writing_sessions SET status = 'completed', "
            "completed_shots = total_shots, updated_at = datetime('now') "
            "WHERE run_id = ? AND status = 'active'",
            (run_id,),
        )
        self.db.commit()

        return {
            "chapter_key": chapter_key,
            "shot_count": len(imported_shots),
            "total_chars": total_chars,
            "shots": imported_shots,
        }

    def _ensure_chapter_structure(self, chapter_key: str, shot_count: int) -> None:
        """Ensure the chapter exists in project_structure."""
        existing = self.db.execute(
            "SELECT 1 FROM writing_project_structure "
            "WHERE project_id = ? AND layer_key = ?",
            (self.project_id, chapter_key),
        ).fetchone()

        if existing:
            return  # Already exists

        structure_id = generate_ulid()
        self.db.execute(
            "INSERT INTO writing_project_structure "
            "(structure_id, project_id, layer_type, layer_key, "
            "parent_layer_key, layer_index, human_confirm_layer, metadata_json) "
            "VALUES (?, ?, 'chapter', ?, NULL, 1, 2, ?)",
            (structure_id, self.project_id, chapter_key, f'{{"shot_count": {shot_count}}}'),
        )
        self.db.commit()

    def _ensure_session(self, run_id: str, chapter_key: str, total_shots: int) -> None:
        """Ensure a session exists for this run_id."""
        existing = self.db.execute(
            "SELECT 1 FROM writing_sessions WHERE run_id = ?",
            (run_id,),
        ).fetchone()

        if existing:
            return

        session_id = generate_ulid()
        self.db.execute(
            "INSERT INTO writing_sessions "
            "(session_id, project_id, run_id, act_id, status, total_shots) "
            "VALUES (?, ?, ?, ?, 'active', ?)",
            (session_id, self.project_id, run_id, chapter_key, total_shots),
        )
        self.db.commit()

    def _import_shot(
        self,
        run_id: str,
        shot: dict,
        chapter_key: str,
    ) -> str:
        """Import a single shot as locked baseline.

        Returns:
            shot_id
        """
        # Idempotency check: skip if shot already exists for this (run_id, shot_index)
        existing = self.db.execute(
            "SELECT shot_id FROM writing_shots "
            "WHERE run_id = ? AND layer_key = ? AND shot_index = ?",
            (run_id, chapter_key, shot["shot_index"]),
        ).fetchone()
        if existing:
            # Check if text changed (hash mismatch) — warn but don't overwrite
            existing_rev = self.db.execute(
                "SELECT text_hash_normalized FROM shot_revisions "
                "WHERE shot_id = ? AND is_current = 1",
                (existing["shot_id"],),
            ).fetchone()
            new_hash = text_hash_normalized(shot["text"])
            if existing_rev and existing_rev["text_hash_normalized"] != new_hash:
                import warnings
                warnings.warn(
                    f"Shot {chapter_key}.s{shot['shot_index']:02d} text has changed "
                    f"since last import. Skipping (use --force to overwrite).",
                    stacklevel=2,
                )
            return existing["shot_id"]

        # 8层复合ID: {volume}.{chapter}.s{section}
        shot_id = generate_shot_id(chapter_key, shot["shot_index"])
        contract_id = generate_ulid()
        revision_id = generate_ulid()
        attempt_id = generate_ulid()
        text_hash = text_hash_normalized(shot["text"])

        # 1. Create shot record (done_green, locked, is_baseline=1)
        self.db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, "
            "light_status, current_revision_id, is_baseline) "
            "VALUES (?, ?, ?, ?, ?, ?, 'green', ?, 1)",
            (shot_id, self.project_id, run_id, chapter_key, shot["shot_index"],
             ShotStatus.DONE_GREEN, revision_id),
        )

        # 2. Create shot contract (locked)
        shot_snapshot = text_hash_normalized(shot["text"])
        self.db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, '{}', '{}', '{}')",
            (contract_id, self.project_id, run_id, shot_id, chapter_key,
             ContractStatus.LOCKED, shot_snapshot),
        )

        # 3. Write revision (human_baseline, locked)
        import json
        gate_result = json.dumps({"locked": True, "source": "human_baseline"}, ensure_ascii=False)

        self.db.execute(
            "INSERT INTO shot_revisions "
            "(revision_id, shot_id, run_id, contract_id, revision_sequence, "
            "operation, text, text_hash_normalized, writer_persona, "
            "gate_result_json, is_current, attempt_id) "
            "VALUES (?, ?, ?, ?, 1, ?, ?, ?, 'human_baseline', ?, 1, ?)",
            (revision_id, shot_id, run_id, contract_id,
             RevisionOperation.WRITE_GENERATE, shot["text"], text_hash,
             gate_result, attempt_id),
        )

        self.db.commit()
        return shot_id

    def get_baseline_shots(self, chapter_key: str) -> list[dict]:
        """Get all baseline shots for a chapter.

        Returns shots with their current revision text.
        """
        rows = self.db.execute(
            "SELECT s.shot_id, s.shot_index, s.layer_key, s.shot_status, "
            "s.light_status, s.current_revision_id, "
            "r.text, r.text_hash_normalized, r.writer_persona, "
            "r.gate_result_json "
            "FROM writing_shots s "
            "LEFT JOIN shot_revisions r ON s.current_revision_id = r.revision_id "
            "WHERE s.project_id = ? AND s.layer_key = ? "
            "ORDER BY s.shot_index",
            (self.project_id, chapter_key),
        ).fetchall()

        return [dict(r) for r in rows]

    def lock_baseline(self, chapter_key: str) -> None:
        """Ensure all shots for a chapter are locked (human_baseline).

        Updates shot_contracts to 'locked' status.
        """
        self.db.execute(
            "UPDATE writing_shot_contracts SET contract_status = ? "
            "WHERE project_id = ? AND layer_key = ? AND contract_status != 'locked'",
            (ContractStatus.LOCKED, self.project_id, chapter_key),
        )
        self.db.commit()

    def is_baseline_locked(self, chapter_key: str) -> bool:
        """Check if all shots in a chapter are locked."""
        row = self.db.execute(
            "SELECT COUNT(*) as cnt FROM writing_shot_contracts "
            "WHERE project_id = ? AND layer_key = ? AND contract_status != 'locked'",
            (self.project_id, chapter_key),
        ).fetchone()
        return row["cnt"] == 0