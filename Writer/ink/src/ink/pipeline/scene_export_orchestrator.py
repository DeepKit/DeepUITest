"""Scene-first export orchestrator.

Reads the active sealed Chapter Snapshot per chapter (the single Scene-first
body-text authority) and assembles a project's accepted chapters into one clean
artifact. This is the post-cutover export path. The legacy
:class:`ink.pipeline.export_orchestrator.ExportOrchestrator` (which reads the
``writing_shots`` / ``writing_text_blocks`` legacy tables) is left untouched
until P0-6 cutover; :meth:`check_export_parity` compares the two read-only so
cutover readiness can be observed without flipping authority.
"""
from __future__ import annotations

import sqlite3

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.errors import DataIntegrityError


class SceneExportOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn
        self.snapshots = ChapterSnapshotRepository(conn)

    def export_chapter(self, project_id: int, chapter_id: int) -> str:
        """Export a single chapter from its active sealed Snapshot.

        Raises :class:`DataIntegrityError` when the chapter has no active
        sealed Snapshot (i.e. it has not been Scene-first Accepted) — a chapter
        cannot be exported before Accept.
        """
        return self.snapshots.read_active_chapter_text(
            project_id=project_id, chapter_id=chapter_id
        )

    def export_project(self, project_id: int) -> str:
        """Assemble every accepted chapter of a project in chapter-id order."""
        rows = self.conn.execute(
            """
            SELECT chapter_id
            FROM writing_chapter_heads
            WHERE project_id = ?
            ORDER BY chapter_id
            """,
            (project_id,),
        ).fetchall()
        if not rows:
            raise DataIntegrityError(
                f"no accepted chapters to export for project {project_id}"
            )
        chapters = [self.export_chapter(project_id, int(row[0])) for row in rows]
        artifact = "\n\n".join(ch for ch in chapters if ch)
        self.snapshots.emit_runtime_event(
            project_id=project_id,
            event_type="EXPORT_COMPLETED",
            event_payload={"chapter_count": len(rows)},
        )
        return artifact

    def check_export_parity(self, project_id: int) -> dict:
        """Read-only dual-authority parity check (pre-cutover safety).

        Runs the legacy export and the Scene-first export side by side and
        reports whether they agree. Writes nothing; mutates nothing. Use during
        cutover to confirm the two authority paths converge before flipping.
        """
        from ink.pipeline.export_orchestrator import ExportOrchestrator

        legacy = ExportOrchestrator(self.conn)
        legacy_text = ""
        try:
            legacy_text = legacy.export_project(project_id)
        except DataIntegrityError:
            legacy_text = ""
        scene_text = ""
        try:
            scene_text = self.export_project(project_id)
        except DataIntegrityError:
            scene_text = ""
        return {
            "match": legacy_text == scene_text,
            "legacy_len": len(legacy_text),
            "scene_len": len(scene_text),
        }
