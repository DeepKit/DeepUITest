"""Canonical Scene-first export from active Chapter Snapshots."""
from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.errors import DataIntegrityError
from ink.pipeline.export_orchestrator import _clean_export_text
from ink.time import now_utc_iso


@dataclass(frozen=True)
class ExportChapterMetadata:
    chapter_id: int
    snapshot_id: int
    snapshot_hash: str
    sealed_at: str


@dataclass(frozen=True)
class SceneExportArtifact:
    project_id: int
    text: str
    artifact_sha256: str
    bytes: int
    chapters: tuple[ExportChapterMetadata, ...]

    def metadata(self, *, delivery: str, generated_at: str) -> dict[str, object]:
        return {
            "artifact_type": "formal_chapter_snapshot_export",
            "authority": "active_sealed_non_stale_chapter_snapshot",
            "policy_version": "scene-export-v1",
            "project_id": self.project_id,
            "chapter_count": len(self.chapters),
            "bytes": self.bytes,
            "artifact_sha256": self.artifact_sha256,
            "chapters": [asdict(chapter) for chapter in self.chapters],
            "delivery": delivery,
            "generated_at": generated_at,
        }


class SceneExportOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn
        self.snapshots = ChapterSnapshotRepository(conn)

    def build_chapter(self, project_id: int, chapter_id: int) -> SceneExportArtifact:
        snapshot = self.snapshots.read_active_chapter_snapshot(
            project_id=project_id, chapter_id=chapter_id
        )
        text = _clean_export_text(snapshot.text)
        return _artifact(
            project_id,
            text,
            (
                ExportChapterMetadata(
                    chapter_id=snapshot.chapter_id,
                    snapshot_id=snapshot.snapshot_id,
                    snapshot_hash=snapshot.snapshot_hash,
                    sealed_at=snapshot.sealed_at,
                ),
            ),
        )

    def build_project(self, project_id: int) -> SceneExportArtifact:
        chapter_rows = self.conn.execute(
            """
            SELECT chapter_id
            FROM writing_chapter_heads
            WHERE project_id = ?
            ORDER BY chapter_id
            """,
            (project_id,),
        ).fetchall()
        if not chapter_rows:
            raise DataIntegrityError(f"no accepted Chapter Snapshots to export: {project_id}")
        chapters = [
            self.snapshots.read_active_chapter_snapshot(
                project_id=project_id, chapter_id=int(row[0])
            )
            for row in chapter_rows
        ]
        texts = [_clean_export_text(chapter.text) for chapter in chapters]
        metadata = tuple(
            ExportChapterMetadata(
                chapter_id=chapter.chapter_id,
                snapshot_id=chapter.snapshot_id,
                snapshot_hash=chapter.snapshot_hash,
                sealed_at=chapter.sealed_at,
            )
            for chapter in chapters
        )
        return _artifact(project_id, "\n\n".join(texts), metadata)

    def export_chapter(self, project_id: int, chapter_id: int) -> str:
        artifact = self.build_chapter(project_id, chapter_id)
        self.record_completed(artifact, delivery="stdout")
        return artifact.text

    def export_project(self, project_id: int) -> str:
        artifact = self.build_project(project_id)
        self.record_completed(artifact, delivery="stdout")
        return artifact.text

    def record_completed(
        self, artifact: SceneExportArtifact, *, delivery: str = "stdout"
    ) -> None:
        self.snapshots.emit_runtime_event(
            project_id=artifact.project_id,
            event_type="EXPORT_COMPLETED",
            event_payload=artifact.metadata(
                delivery=delivery, generated_at=now_utc_iso()
            ),
        )

    def deliver_project(self, project_id: int, output: str | Path) -> SceneExportArtifact:
        artifact = self.build_project(project_id)
        self._deliver(artifact, Path(output))
        return artifact

    def deliver_chapter(
        self, project_id: int, chapter_id: int, output: str | Path
    ) -> SceneExportArtifact:
        artifact = self.build_chapter(project_id, chapter_id)
        self._deliver(artifact, Path(output))
        return artifact

    def preview_project(self, project_id: int) -> dict[str, object]:
        artifact = self.build_project(project_id)
        return {
            "project_id": project_id,
            "accepted_chapters": len(artifact.chapters),
            "bytes": artifact.bytes,
            "artifact_sha256": artifact.artifact_sha256,
            "snapshot_ids": [chapter.snapshot_id for chapter in artifact.chapters],
        }

    def check_export_parity(self, project_id: int) -> dict[str, object]:
        """Compare legacy and Snapshot exports without writing events or files."""
        from ink.pipeline.export_orchestrator import ExportOrchestrator

        legacy_text, legacy_error = _read_legacy_parity(
            ExportOrchestrator(self.conn), project_id
        )
        try:
            scene_text = self.build_project(project_id).text
            scene_error = None
        except DataIntegrityError as exc:
            scene_text = ""
            scene_error = str(exc)
        legacy_bytes = legacy_text.encode("utf-8")
        scene_bytes = scene_text.encode("utf-8")
        return {
            "match": legacy_error is None
            and scene_error is None
            and legacy_bytes == scene_bytes,
            "legacy_status": "ok" if legacy_error is None else "unavailable",
            "scene_status": "ok" if scene_error is None else "unavailable",
            "legacy_error": legacy_error,
            "scene_error": scene_error,
            "legacy_len": len(legacy_text),
            "scene_len": len(scene_text),
            "legacy_bytes": len(legacy_bytes),
            "scene_bytes": len(scene_bytes),
            "legacy_sha256": hashlib.sha256(legacy_bytes).hexdigest(),
            "scene_sha256": hashlib.sha256(scene_bytes).hexdigest(),
        }

    def _deliver(self, artifact: SceneExportArtifact, output: Path) -> None:
        generated_at = now_utc_iso()
        sidecar = Path(f"{output}.metadata.json")
        metadata = artifact.metadata(delivery=str(output), generated_at=generated_at)
        _atomic_write_text(output, artifact.text)
        try:
            _atomic_write_text(
                sidecar,
                json.dumps(metadata, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            )
        except Exception:
            output.unlink(missing_ok=True)
            raise
        self.snapshots.emit_runtime_event(
            project_id=artifact.project_id,
            event_type="EXPORT_COMPLETED",
            event_payload=metadata,
        )

def _artifact(
    project_id: int,
    text: str,
    chapters: tuple[ExportChapterMetadata, ...],
) -> SceneExportArtifact:
    encoded = text.encode("utf-8")
    return SceneExportArtifact(
        project_id=project_id,
        text=text,
        artifact_sha256=hashlib.sha256(encoded).hexdigest(),
        bytes=len(encoded),
        chapters=chapters,
    )


def _atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        Path(temporary).unlink(missing_ok=True)
        raise


def _read_legacy_parity(
    exporter, project_id: int
) -> tuple[str, str | None]:
    try:
        return exporter.build_project(project_id), None
    except DataIntegrityError as exc:
        return "", str(exc)
