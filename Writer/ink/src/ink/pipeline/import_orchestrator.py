from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path

from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


IMPORT_EXTENSIONS = {".md", ".txt"}


@dataclass(frozen=True)
class ImportDryRunResult:
    import_run_id: int
    manifest_count: int
    question_count: int


@dataclass(frozen=True)
class ImportFinalizeResult:
    import_decision_id: int
    human_decision_id: int


class ImportOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def dry_run(self, project_id: int, source_root: str) -> ImportDryRunResult:
        root = Path(source_root)
        if not root.exists() or not root.is_dir():
            raise DataIntegrityError(f"import source root is not a directory: {source_root}")

        files = [path for path in sorted(root.rglob("*")) if path.is_file() and path.suffix.lower() in IMPORT_EXTENSIONS]
        if not files:
            raise DataIntegrityError(f"import source root has no supported files: {source_root}")

        try:
            self.conn.execute("SAVEPOINT import_dry_run")
            cursor = self.conn.execute(
                """
                INSERT INTO writing_import_runs
                    (project_id, mode, source_root, status, created_at)
                VALUES (?, 'dry_run', ?, 'completed', ?)
                """,
                (project_id, str(root), now_utc_iso()),
            )
            import_run_id = int(cursor.lastrowid)
            for index, path in enumerate(files, start=1):
                _insert_manifest(self.conn, import_run_id, root, path, index)
        except Exception:
            self.conn.execute("ROLLBACK TO import_dry_run")
            self.conn.execute("RELEASE import_dry_run")
            raise
        else:
            self.conn.execute("RELEASE import_dry_run")
            return ImportDryRunResult(import_run_id=import_run_id, manifest_count=len(files), question_count=0)

    def finalize(self, import_run_id: int, *, actor: str, reason: str) -> ImportFinalizeResult:
        run = _load_import_run(self.conn, import_run_id)
        manifests = _load_manifests(self.conn, import_run_id)
        if not manifests:
            raise DataIntegrityError(f"import run has no manifest rows: {import_run_id}")
        unresolved = self.conn.execute(
            """
            SELECT count(*)
            FROM writing_import_questions
            WHERE import_run_id = ? AND resolution IS NULL
            """,
            (import_run_id,),
        ).fetchone()[0]
        if int(unresolved) > 0:
            raise DataIntegrityError("import finalize requires all questions resolved")
        _verify_manifest_hashes(Path(str(run["source_root"])), manifests)
        applied_manifest_hash = _manifest_hash(manifests)

        try:
            self.conn.execute("SAVEPOINT import_finalize")
            human_decision_id = _insert_human_decision(
                self.conn,
                project_id=int(run["project_id"]),
                actor=actor,
                reason=reason,
                preconditions={
                    "import_run_id": import_run_id,
                    "manifest_count": len(manifests),
                    "source_hash_verified": True,
                },
            )
            cursor = self.conn.execute(
                """
                INSERT INTO writing_import_decisions
                    (import_run_id, human_decision_id, applied_manifest_hash, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (import_run_id, human_decision_id, applied_manifest_hash, now_utc_iso()),
            )
            self.conn.execute(
                """
                UPDATE writing_import_runs
                SET status = 'completed', finalized_at = ?
                WHERE import_run_id = ?
                """,
                (now_utc_iso(), import_run_id),
            )
        except Exception:
            self.conn.execute("ROLLBACK TO import_finalize")
            self.conn.execute("RELEASE import_finalize")
            raise
        else:
            self.conn.execute("RELEASE import_finalize")
            return ImportFinalizeResult(import_decision_id=int(cursor.lastrowid), human_decision_id=human_decision_id)


def _insert_manifest(conn: sqlite3.Connection, import_run_id: int, root: Path, path: Path, index: int) -> None:
    relative_path = path.relative_to(root).as_posix()
    conn.execute(
        """
        INSERT INTO writing_import_manifests
            (import_run_id, source_path, source_hash, target_chapter_id,
             target_logical_shot_id, confidence, action, created_at)
        VALUES (?, ?, ?, ?, NULL, 1.0, 'create', ?)
        """,
        (import_run_id, relative_path, _file_hash(path), index, now_utc_iso()),
    )


def _load_import_run(conn: sqlite3.Connection, import_run_id: int) -> dict[str, object]:
    row = conn.execute(
        """
        SELECT project_id, mode, source_root, status
        FROM writing_import_runs
        WHERE import_run_id = ?
        """,
        (import_run_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"import run not found: {import_run_id}")
    if str(row[1]) != "dry_run":
        raise DataIntegrityError(f"import finalize requires dry_run mode, got: {row[1]}")
    if str(row[3]) not in {"completed", "needs_human"}:
        raise DataIntegrityError(f"import run is not finalizable: {row[3]}")
    return {"project_id": int(row[0]), "mode": str(row[1]), "source_root": str(row[2]), "status": str(row[3])}


def _load_manifests(conn: sqlite3.Connection, import_run_id: int) -> list[dict[str, object]]:
    rows = conn.execute(
        """
        SELECT manifest_id, source_path, source_hash, target_chapter_id, target_logical_shot_id, confidence, action
        FROM writing_import_manifests
        WHERE import_run_id = ?
        ORDER BY manifest_id
        """,
        (import_run_id,),
    ).fetchall()
    return [
        {
            "manifest_id": int(row[0]),
            "source_path": str(row[1]),
            "source_hash": str(row[2]),
            "target_chapter_id": None if row[3] is None else int(row[3]),
            "target_logical_shot_id": None if row[4] is None else str(row[4]),
            "confidence": float(row[5]),
            "action": str(row[6]),
        }
        for row in rows
    ]


def _verify_manifest_hashes(root: Path, manifests: list[dict[str, object]]) -> None:
    for manifest in manifests:
        path = root / str(manifest["source_path"])
        if _file_hash(path) != manifest["source_hash"]:
            raise DataIntegrityError(f"import source changed after dry-run: {manifest['source_path']}")


def _insert_human_decision(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    actor: str,
    reason: str,
    preconditions: dict[str, object],
) -> int:
    cursor = conn.execute(
        """
        INSERT INTO writing_human_decisions
            (project_id, decision_type, actor, reason, preconditions_json, quality_report_json,
             hard_quality_override, created_at)
        VALUES (?, 'import_finalize', ?, ?, ?, '{}', 0, ?)
        """,
        (
            project_id,
            actor,
            reason,
            json.dumps(preconditions, ensure_ascii=False, sort_keys=True),
            now_utc_iso(),
        ),
    )
    return int(cursor.lastrowid)


def _manifest_hash(manifests: list[dict[str, object]]) -> str:
    payload = json.dumps(manifests, ensure_ascii=False, sort_keys=True)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _file_hash(path: Path) -> str:
    if not path.exists() or not path.is_file():
        raise DataIntegrityError(f"import source file missing: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()
