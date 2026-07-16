"""SourceNormalizer 测试。"""
from __future__ import annotations

import os
import sqlite3
import tempfile
from pathlib import Path

import pytest

from factories import NOW, make_schema_db
from ink.source_normalizer import (
    Conflict,
    ConflictQuestion,
    NormalizeResult,
    SourceNormalizer,
)


def _insert_project(conn: sqlite3.Connection) -> None:
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


@pytest.fixture
def conn() -> sqlite3.Connection:
    c = make_schema_db()
    _insert_project(c)
    return c


@pytest.fixture
def normalizer(conn: sqlite3.Connection) -> SourceNormalizer:
    return SourceNormalizer(conn)


class TestNormalizeSourceDirectory:
    """normalize_source_directory 测试。"""

    def test_normalize_reads_markdown_files(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """读取目录中的 .md 文件并注册。"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # 创建测试文件
            (Path(tmpdir) / "writing_guide.md").write_text(
                "# Writing Guide\nAlways use active voice.\nNever start with 'In conclusion'.\n"
            )
            (Path(tmpdir) / "character_bible.md").write_text(
                "# Character Bible\nProtagonist is brave but flawed.\n"
            )

            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

            assert len(result.registered_source_ids) == 2
            assert len(result.extracted_clause_ids) > 0

    def test_normalize_skips_non_text_files(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """跳过非 .md/.txt 文件。"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / "image.png").write_bytes(b"\x89PNG")
            (Path(tmpdir) / "data.json").write_text("{}")
            (Path(tmpdir) / "guide.md").write_text("Use active voice.\n")

            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

            assert len(result.registered_source_ids) == 1

    def test_normalize_infers_source_kind(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """从文件名推断 source_kind。"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / "writing_guide.md").write_text("Rule one.\n")
            (Path(tmpdir) / "character_bible.md").write_text("Character rule.\n")
            (Path(tmpdir) / "world_setting.md").write_text("World rule.\n")
            (Path(tmpdir) / "outline.md").write_text("Plot point.\n")

            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

            # 验证 source_kind
            rows = conn.execute(
                "SELECT source_kind FROM writing_source_documents WHERE project_id = 1 ORDER BY source_document_id"
            ).fetchall()
            kinds = {str(row[0]) for row in rows}
            assert "guide" in kinds
            assert "character" in kinds
            assert "world" in kinds
            assert "outline" in kinds

    def test_normalize_directory_not_found(self, normalizer: SourceNormalizer) -> None:
        """目录不存在时抛 FileNotFoundError。"""
        with pytest.raises(FileNotFoundError):
            normalizer.normalize_source_directory(
                project_id=1,
                source_directory="/nonexistent/path",
            )

    def test_normalize_extracts_clauses(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """抽取器生成原子条款。"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / "guide.md").write_text("Use active voice.\nAvoid adverbs.\n")

            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

            assert len(result.extracted_clause_ids) >= 2

            # 验证条款写入
            rows = conn.execute(
                "SELECT clause_text FROM writing_atomic_source_clauses WHERE source_document_id = ?",
                (result.registered_source_ids[0],),
            ).fetchall()
            texts = [str(row[0]) for row in rows]
            assert any("active voice" in t for t in texts)

    def test_normalize_records_extraction_run(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """记录抽取运行。"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / "guide.md").write_text("Test clause.\n")

            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

            row = conn.execute(
                "SELECT status FROM writing_source_extraction_runs WHERE source_document_id = ?",
                (result.registered_source_ids[0],),
            ).fetchone()
            assert str(row[0]) == "completed"


class TestMergeAndDeduplicate:
    """merge_and_deduplicate 测试。"""

    def test_dedup_exact_text(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """完全相同的条款文本去重。"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / "guide.md").write_text(
                "Use active voice.\nUse active voice.\n"
            )

            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

            # 应该有去重
            assert result.duplicate_count >= 1

            # 验证：重复条款状态为 superseded
            rows = conn.execute(
                "SELECT status FROM writing_atomic_source_clauses WHERE source_document_id = ? ORDER BY atomic_clause_id",
                (result.registered_source_ids[0],),
            ).fetchall()
            statuses = [str(row[0]) for row in rows]
            assert "superseded" in statuses

    def test_no_dedup_for_different_text(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """不同文本不去重。"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / "guide.md").write_text(
                "Use active voice.\nAvoid adverbs.\n"
            )

            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

            assert result.duplicate_count == 0


class TestDetectConflicts:
    """detect_conflicts 测试。"""

    def test_detect_conflict_same_scope_hard(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """同 scope 内多条 hard 条款标记为冲突。"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # 创建自定义抽取器生成 hard 条款
            def custom_extraction(content: str, filename: str) -> list[dict]:
                return [
                    {
                        "scope_type": "book",
                        "scope_id": None,
                        "clause_type": "quality",
                        "severity": "hard",
                        "clause_text": "Rule A: must be short",
                    },
                    {
                        "scope_type": "book",
                        "scope_id": None,
                        "clause_type": "quality",
                        "severity": "hard",
                        "clause_text": "Rule B: must be long",
                    },
                ]

            normalizer._extraction_fn = custom_extraction
            (Path(tmpdir) / "guide.md").write_text("dummy")

            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

            conflicts = normalizer.detect_conflicts(project_id=1)
            assert len(conflicts) >= 1
            assert conflicts[0].scope_type == "book"

    def test_no_conflict_single_hard(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """单条 hard 条款不冲突。"""
        with tempfile.TemporaryDirectory() as tmpdir:
            def custom_extraction(content: str, filename: str) -> list[dict]:
                return [
                    {
                        "scope_type": "book",
                        "scope_id": None,
                        "clause_type": "quality",
                        "severity": "hard",
                        "clause_text": "Single hard rule",
                    },
                ]

            normalizer._extraction_fn = custom_extraction
            (Path(tmpdir) / "guide.md").write_text("dummy")

            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

            conflicts = normalizer.detect_conflicts(project_id=1)
            assert len(conflicts) == 0

    def test_no_conflict_for_soft(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """soft 条款不检测冲突。"""
        with tempfile.TemporaryDirectory() as tmpdir:
            def custom_extraction(content: str, filename: str) -> list[dict]:
                return [
                    {"scope_type": "book", "scope_id": None, "clause_type": "quality",
                     "severity": "soft", "clause_text": "Soft rule A"},
                    {"scope_type": "book", "scope_id": None, "clause_type": "quality",
                     "severity": "soft", "clause_text": "Soft rule B"},
                ]

            normalizer._extraction_fn = custom_extraction
            (Path(tmpdir) / "guide.md").write_text("dummy")

            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

            conflicts = normalizer.detect_conflicts(project_id=1)
            assert len(conflicts) == 0


class TestGenerateConflictQuestions:
    """generate_conflict_questions 测试。"""

    def test_generate_question(self, conn: sqlite3.Connection, normalizer: SourceNormalizer) -> None:
        """为冲突生成选择题。"""
        # 先创建两条冲突条款
        source_id = normalizer._store.register_source_document(
            project_id=1, source_path="/test.md", source_kind="guide",
            content_hash="abc", priority=100, status="active",
        )
        clause_a = normalizer._store.record_atomic_clause(
            project_id=1, source_document_id=source_id,
            scope_type="book", scope_id=None, clause_type="quality",
            severity="hard", clause_text="Must be concise",
            source_refs=["test.md"], source_hashes=["abc"],
        )
        clause_b = normalizer._store.record_atomic_clause(
            project_id=1, source_document_id=source_id,
            scope_type="book", scope_id=None, clause_type="quality",
            severity="hard", clause_text="Must be detailed",
            source_refs=["test.md"], source_hashes=["abc"],
        )

        conflict = Conflict(
            clause_a_id=clause_a,
            clause_b_id=clause_b,
            scope_type="book",
            scope_id=None,
            reason="test conflict",
        )

        questions = normalizer.generate_conflict_questions(
            project_id=1,
            conflicts=[conflict],
        )

        assert len(questions) == 1
        assert questions[0].clause_a_id == clause_a
        assert questions[0].clause_b_id == clause_b

        # 验证 DecisionSession 创建
        row = conn.execute(
            "SELECT status, target_type FROM writing_decision_sessions WHERE decision_session_id = ?",
            (questions[0].question_id,),
        ).fetchone()
        assert str(row[0]) == "collecting"
        assert str(row[1]) == "ConflictResolution"

        # 验证选项集创建
        row = conn.execute(
            "SELECT options_json FROM writing_decision_option_sets WHERE decision_session_id = ?",
            (questions[0].question_id,),
        ).fetchone()
        import json
        options = json.loads(str(row[0]))
        assert len(options) == 4  # 保留 A / 保留 B / 合并 / 删除


class TestInferSourceKind:
    """_infer_source_kind 测试。"""

    def test_infer_guide(self, normalizer: SourceNormalizer) -> None:
        assert normalizer._infer_source_kind("writing_guide.md") == "guide"

    def test_infer_character(self, normalizer: SourceNormalizer) -> None:
        assert normalizer._infer_source_kind("character_bible.txt") == "character"

    def test_infer_world(self, normalizer: SourceNormalizer) -> None:
        assert normalizer._infer_source_kind("world_setting.md") == "world"

    def test_infer_outline(self, normalizer: SourceNormalizer) -> None:
        assert normalizer._infer_source_kind("outline.md") == "outline"

    def test_infer_other(self, normalizer: SourceNormalizer) -> None:
        assert normalizer._infer_source_kind("random_file.md") == "other"
