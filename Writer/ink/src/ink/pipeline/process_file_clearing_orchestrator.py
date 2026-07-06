from __future__ import annotations

import hashlib
import sqlite3
from dataclasses import dataclass
from pathlib import Path

from ink.errors import DataIntegrityError
from ink.source_workflow import SourceWorkflowStore


@dataclass(frozen=True)
class ProcessFileClearingResult:
    source_document_id: int
    manifest_id: int
    content_hash: str
    processed_hash: str
    cleared_at: str


class ProcessFileClearingOrchestrator:
    """过程文件清空执行器。

    将 ``better.md`` 等过程草稿（``source_kind='process_scratch'``）作为抽取输入；
    在抽取并合并完成后：

    1. 校验该文件未被清空过（幂等：重复清空报错）。
    2. 计算原文 ``content_hash`` 与清空后 ``processed_hash``（空内容 hash）。
    3. 清空磁盘文件内容（写空字符串）。
    4. 写 ``writing_process_file_manifests`` 记录抽取的 clause_ids、contract_patch_ids、
       decision_session_ids，并把 source document 置 ``status='cleared'``。
    5. 此后 prompt/contract 不得直接引用该路径——由 ``SourceWorkflowStore.is_process_file_cleared``
       在写入点阻断。
    """

    EMPTY_PROCESSED_HASH = hashlib.sha256(b"").hexdigest()

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn
        self.store = SourceWorkflowStore(conn)

    def clear_process_file(
        self,
        *,
        project_id: int,
        source_path: str,
        extracted_clause_ids: list[int] | None = None,
        contract_patch_ids: list[int] | None = None,
        decision_session_ids: list[int] | None = None,
    ) -> ProcessFileClearingResult:
        path = Path(source_path)
        if not path.is_absolute():
            raise DataIntegrityError(
                f"process file path must be absolute: {source_path}"
            )
        if self.store.is_process_file_cleared(project_id=project_id, source_path=source_path):
            raise DataIntegrityError(
                f"process file already cleared; cannot re-clear: {source_path}"
            )

        # 读取原文计算 content_hash；清空后写空内容
        if path.exists():
            original_bytes = path.read_bytes()
            content_hash = hashlib.sha256(original_bytes).hexdigest()
        else:
            content_hash = hashlib.sha256(b"").hexdigest()

        # 注册或复用 source document（process_scratch）
        source_document_id = self._ensure_process_scratch_document(
            project_id=project_id, source_path=source_path, content_hash=content_hash,
        )

        manifest_id = self.store.record_process_file_manifest(
            project_id=project_id,
            source_document_id=source_document_id,
            source_path=source_path,
            content_hash=content_hash,
            processed_hash=self.EMPTY_PROCESSED_HASH,
            extracted_clause_ids=extracted_clause_ids or [],
            contract_patch_ids=contract_patch_ids or [],
            decision_session_ids=decision_session_ids or [],
        )

        # 清空磁盘文件内容
        path.write_bytes(b"")

        row = self.conn.execute(
            "SELECT cleared_at FROM writing_process_file_manifests WHERE process_manifest_id = ?",
            (manifest_id,),
        ).fetchone()
        cleared_at = str(row[0]) if row is not None else ""

        return ProcessFileClearingResult(
            source_document_id=source_document_id,
            manifest_id=manifest_id,
            content_hash=content_hash,
            processed_hash=self.EMPTY_PROCESSED_HASH,
            cleared_at=cleared_at,
        )

    def _ensure_process_scratch_document(self, *, project_id: int, source_path: str, content_hash: str) -> int:
        row = self.conn.execute(
            """
            SELECT source_document_id FROM writing_source_documents
            WHERE project_id = ? AND source_path = ? AND content_hash = ?
            """,
            (project_id, source_path, content_hash),
        ).fetchone()
        if row is not None:
            return int(row[0])
        return self.store.register_source_document(
            project_id=project_id,
            source_path=source_path,
            source_kind="process_scratch",
            content_hash=content_hash,
        )
