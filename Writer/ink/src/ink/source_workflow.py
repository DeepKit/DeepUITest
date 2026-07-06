from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from typing import Sequence

from ink.time import now_utc_iso


@dataclass(frozen=True)
class SourceDocumentRecord:
    source_document_id: int
    project_id: int
    source_path: str
    source_kind: str
    content_hash: str
    status: str


class SourceWorkflowStore:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def register_source_document(
        self,
        *,
        project_id: int,
        source_path: str,
        source_kind: str,
        content_hash: str,
        priority: int = 100,
        status: str = "active",
    ) -> int:
        now = now_utc_iso()
        cursor = self.conn.execute(
            """
            INSERT INTO writing_source_documents
                (project_id, source_path, source_kind, priority, content_hash, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (project_id, source_path, source_kind, priority, content_hash, status, now, now),
        )
        return int(cursor.lastrowid)

    def record_atomic_clause(
        self,
        *,
        project_id: int,
        source_document_id: int,
        scope_type: str,
        scope_id: str | None,
        clause_type: str,
        severity: str,
        clause_text: str,
        source_refs: Sequence[str],
        source_hashes: Sequence[str],
        status: str = "proposed",
        supersedes_clause_id: int | None = None,
    ) -> int:
        now = now_utc_iso()
        cursor = self.conn.execute(
            """
            INSERT INTO writing_atomic_source_clauses
                (project_id, source_document_id, scope_type, scope_id, clause_type, severity,
                 clause_text, source_refs_json, source_hashes_json, status, supersedes_clause_id,
                 created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                project_id,
                source_document_id,
                scope_type,
                scope_id,
                clause_type,
                severity,
                clause_text,
                _json(list(source_refs)),
                _json(list(source_hashes)),
                status,
                supersedes_clause_id,
                now,
                now,
            ),
        )
        return int(cursor.lastrowid)

    def record_extraction_run(
        self,
        *,
        project_id: int,
        source_document_id: int,
        extractor_slot: str,
        model_provider: str,
        model_name: str,
        source_hash: str,
        extracted_clause_ids: Sequence[int],
        low_confidence_refs: Sequence[str] = (),
        status: str = "completed",
    ) -> int:
        now = now_utc_iso()
        cursor = self.conn.execute(
            """
            INSERT INTO writing_source_extraction_runs
                (project_id, source_document_id, extractor_slot, model_provider, model_name,
                 source_hash, extracted_clause_ids_json, low_confidence_refs_json, status,
                 created_at, finished_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                project_id,
                source_document_id,
                extractor_slot,
                model_provider,
                model_name,
                source_hash,
                _json(list(extracted_clause_ids)),
                _json(list(low_confidence_refs)),
                status,
                now,
                now if status in {"completed", "failed", "superseded"} else None,
            ),
        )
        return int(cursor.lastrowid)

    def record_coverage(
        self,
        *,
        project_id: int,
        contract_scope_type: str,
        contract_scope_id: str | None,
        contract_field_path: str,
        coverage_status: str,
        atomic_clause_id: int | None = None,
        decision_session_id: int | None = None,
        evidence: dict[str, object] | None = None,
    ) -> int:
        now = now_utc_iso()
        cursor = self.conn.execute(
            """
            INSERT INTO writing_source_coverage_matrix
                (project_id, atomic_clause_id, contract_scope_type, contract_scope_id,
                 contract_field_path, coverage_status, decision_session_id, evidence_json,
                 created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                project_id,
                atomic_clause_id,
                contract_scope_type,
                contract_scope_id,
                contract_field_path,
                coverage_status,
                decision_session_id,
                _json(evidence or {}),
                now,
                now,
            ),
        )
        return int(cursor.lastrowid)

    def resolve_coverage(
        self,
        coverage_id: int,
        *,
        coverage_status: str,
        decision_session_id: int | None = None,
        evidence: dict[str, object] | None = None,
    ) -> None:
        self.conn.execute(
            """
            UPDATE writing_source_coverage_matrix
            SET coverage_status = ?,
                decision_session_id = COALESCE(?, decision_session_id),
                evidence_json = COALESCE(?, evidence_json),
                updated_at = ?
            WHERE coverage_id = ?
            """,
            (
                coverage_status,
                decision_session_id,
                None if evidence is None else _json(evidence),
                now_utc_iso(),
                coverage_id,
            ),
        )

    def has_blocking_coverage_gaps(
        self,
        *,
        project_id: int,
        contract_scope_type: str | None = None,
        contract_scope_id: str | None = None,
    ) -> bool:
        query = [
            "SELECT count(*) FROM writing_source_coverage_matrix",
            "WHERE project_id = ? AND coverage_status IN ('gap','conflict')",
        ]
        params: list[object] = [project_id]
        if contract_scope_type is not None:
            query.append("AND contract_scope_type = ?")
            params.append(contract_scope_type)
        if contract_scope_id is not None:
            query.append("AND contract_scope_id = ?")
            params.append(contract_scope_id)
        row = self.conn.execute("\n".join(query), params).fetchone()
        return int(row[0]) > 0

    def record_process_file_manifest(
        self,
        *,
        project_id: int,
        source_document_id: int,
        source_path: str,
        content_hash: str,
        processed_hash: str,
        extracted_clause_ids: Sequence[int],
        contract_patch_ids: Sequence[int],
        decision_session_ids: Sequence[int],
    ) -> int:
        now = now_utc_iso()
        try:
            self.conn.execute("SAVEPOINT process_file_manifest")
            cursor = self.conn.execute(
                """
                INSERT INTO writing_process_file_manifests
                    (project_id, source_document_id, source_path, content_hash, processed_hash,
                     cleared_at, extracted_clause_ids_json, contract_patch_ids_json,
                     decision_session_ids_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    project_id,
                    source_document_id,
                    source_path,
                    content_hash,
                    processed_hash,
                    now,
                    _json(list(extracted_clause_ids)),
                    _json(list(contract_patch_ids)),
                    _json(list(decision_session_ids)),
                    now,
                ),
            )
            self.conn.execute(
                """
                UPDATE writing_source_documents
                SET status = 'cleared', processed_hash = ?, updated_at = ?
                WHERE source_document_id = ?
                """,
                (processed_hash, now, source_document_id),
            )
        except Exception:
            self.conn.execute("ROLLBACK TO process_file_manifest")
            self.conn.execute("RELEASE process_file_manifest")
            raise
        else:
            self.conn.execute("RELEASE process_file_manifest")
            return int(cursor.lastrowid)

    def is_process_file_cleared(self, *, project_id: int, source_path: str) -> bool:
        """查询某个过程文件是否已被清空（status='cleared' 且有 manifest）。

        抽取并合并完成后清空文件、写 manifest；此后 prompt/contract 不得直接引用
        已清空的过程文件原文——必须改走 atomic clauses / contract patches。
        """
        row = self.conn.execute(
            """
            SELECT d.status, (
                SELECT count(*) FROM writing_process_file_manifests m
                WHERE m.project_id = d.project_id AND m.source_path = d.source_path
            )
            FROM writing_source_documents d
            WHERE d.project_id = ? AND d.source_path = ?
            ORDER BY d.source_document_id DESC LIMIT 1
            """,
            (project_id, source_path),
        ).fetchone()
        if row is None:
            return False
        return str(row[0]) == "cleared" and int(row[1]) > 0


def _json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)
