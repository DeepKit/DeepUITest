from __future__ import annotations

import hashlib

from factories import NOW, make_schema_db
from ink.errors import DataIntegrityError
from ink.pipeline.process_file_clearing_orchestrator import (
    ProcessFileClearingOrchestrator,
)
from ink.source_workflow import SourceWorkflowStore


def _insert_project(conn) -> None:
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'demo', 'Demo', '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
        """,
        (NOW,),
    )


def test_clear_process_file_empties_disk_and_writes_manifest(tmp_path) -> None:
    conn = make_schema_db()
    _insert_project(conn)
    better_md = tmp_path / "better.md"
    original_text = "过程草稿：第一章需要前置钩子。"
    better_md.write_text(original_text, encoding="utf-8")
    expected_hash = hashlib.sha256(original_text.encode("utf-8")).hexdigest()

    orchestrator = ProcessFileClearingOrchestrator(conn)
    result = orchestrator.clear_process_file(
        project_id=1,
        source_path=str(better_md),
        extracted_clause_ids=[101, 102],
        contract_patch_ids=[51],
        decision_session_ids=[7],
    )

    assert result.content_hash == expected_hash
    assert result.processed_hash == ProcessFileClearingOrchestrator.EMPTY_PROCESSED_HASH
    assert result.manifest_id > 0
    # 磁盘文件被清空
    assert better_md.read_text(encoding="utf-8") == ""

    manifest = conn.execute(
        """
        SELECT source_document_id, source_path, content_hash, processed_hash,
               extracted_clause_ids_json, contract_patch_ids_json, decision_session_ids_json
        FROM writing_process_file_manifests WHERE process_manifest_id = ?
        """,
        (result.manifest_id,),
    ).fetchone()
    assert manifest[1] == str(better_md)
    assert manifest[2] == expected_hash
    assert manifest[3] == ProcessFileClearingOrchestrator.EMPTY_PROCESSED_HASH
    import json

    assert json.loads(manifest[4]) == [101, 102]
    assert json.loads(manifest[5]) == [51]
    assert json.loads(manifest[6]) == [7]

    # source document 置 cleared
    status = conn.execute(
        "SELECT status FROM writing_source_documents WHERE source_document_id = ?",
        (result.source_document_id,),
    ).fetchone()[0]
    assert status == "cleared"


def test_clear_process_file_rejects_relative_path() -> None:
    conn = make_schema_db()
    _insert_project(conn)
    orchestrator = ProcessFileClearingOrchestrator(conn)
    try:
        orchestrator.clear_process_file(project_id=1, source_path="relative/better.md")
    except DataIntegrityError:
        return
    raise AssertionError("expected DataIntegrityError for relative path")


def test_clear_process_file_is_idempotent_blocked(tmp_path) -> None:
    conn = make_schema_db()
    _insert_project(conn)
    better_md = tmp_path / "better.md"
    better_md.write_text("草稿内容", encoding="utf-8")

    orchestrator = ProcessFileClearingOrchestrator(conn)
    orchestrator.clear_process_file(project_id=1, source_path=str(better_md))

    # 第二次清空同一文件必须报错（已被清空，不允许重复清空）
    try:
        orchestrator.clear_process_file(project_id=1, source_path=str(better_md))
    except DataIntegrityError:
        return
    raise AssertionError("expected DataIntegrityError for re-clearing")


def test_is_process_file_cleared_blocks_reference_after_clearing(tmp_path) -> None:
    conn = make_schema_db()
    _insert_project(conn)
    store = SourceWorkflowStore(conn)
    better_md = tmp_path / "better.md"
    better_md.write_text("草稿内容", encoding="utf-8")

    # 清空前：未清空，引用允许
    assert store.is_process_file_cleared(project_id=1, source_path=str(better_md)) is False

    ProcessFileClearingOrchestrator(conn).clear_process_file(
        project_id=1, source_path=str(better_md),
    )

    # 清空后：引用被阻断——prompt/contract 不得直接引用该路径
    assert store.is_process_file_cleared(project_id=1, source_path=str(better_md)) is True

    # 未注册的路径不阻断
    assert store.is_process_file_cleared(project_id=1, source_path=str(tmp_path / "other.md")) is False
