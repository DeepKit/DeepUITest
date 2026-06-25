"""Test baseline importer."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from inkflow.importers.baseline_importer import BaselineImporter
from inkflow.db import init_project_db


SAMPLE_CHAPTER = """# 第 01 章：测试章节

## 一

右腿膝盖里像有把生锈的螺丝刀一圈圈往里拧。

阿坤醒了。不是被闹钟叫醒的——是被膝盖拧醒的。

## 二

清晨五点。白英推开望鹤茶社的木门。

竹椅上有露水。成都的清晨从来都是湿的。

## 三

老张七十二岁，退休中学教师。

他的杯子是自带的——玻璃杯，杯底有一道磕痕。
"""


@pytest.fixture
def importer(db):
    """BaselineImporter with project set up."""
    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    db.commit()
    return BaselineImporter(db, "proj_01")


class TestImportChapter:
    """Import a chapter markdown file"""

    def test_import_creates_shots(self, importer, tmp_dir: Path):
        chapter_path = tmp_dir / "chapter.md"
        chapter_path.write_text(SAMPLE_CHAPTER, encoding="utf-8")

        result = importer.import_chapter("v01.c01", str(chapter_path))

        assert result["chapter_key"] == "v01.c01"
        assert result["shot_count"] == 3
        assert result["total_chars"] > 0

    def test_import_file_not_found(self, importer, tmp_dir: Path):
        with pytest.raises(FileNotFoundError):
            importer.import_chapter("v01.c01", str(tmp_dir / "nonexistent.md"))

    def test_baseline_shots_are_locked(self, importer, tmp_dir: Path):
        chapter_path = tmp_dir / "chapter.md"
        chapter_path.write_text(SAMPLE_CHAPTER, encoding="utf-8")

        importer.import_chapter("v01.c01", str(chapter_path))

        shots = importer.get_baseline_shots("v01.c01")
        assert len(shots) == 3

        for shot in shots:
            assert shot["shot_status"] == "done_green"
            assert shot["writer_persona"] == "human_baseline"
            assert shot["light_status"] == "green"

            gate = json.loads(shot["gate_result_json"])
            assert gate["locked"] is True
            assert gate["source"] == "human_baseline"

    def test_lock_baseline(self, importer, tmp_dir: Path):
        chapter_path = tmp_dir / "chapter.md"
        chapter_path.write_text(SAMPLE_CHAPTER, encoding="utf-8")

        importer.import_chapter("v01.c01", str(chapter_path))
        importer.lock_baseline("v01.c01")
        assert importer.is_baseline_locked("v01.c01")

    def test_idempotent_import(self, importer, tmp_dir: Path):
        """Importing same chapter twice should not duplicate"""
        chapter_path = tmp_dir / "chapter.md"
        chapter_path.write_text(SAMPLE_CHAPTER, encoding="utf-8")

        result1 = importer.import_chapter("v01.c01", str(chapter_path))
        assert result1["shot_count"] == 3

        # Verify DB state before second import
        count1 = importer.db.execute(
            "SELECT COUNT(*) as cnt FROM writing_shots "
            "WHERE project_id = ?", (importer.project_id,)
        ).fetchone()["cnt"]
        assert count1 == 3

        result2 = importer.import_chapter("v01.c01", str(chapter_path))
        assert result2["shot_count"] == 3

        # Verify no duplicates in DB
        count2 = importer.db.execute(
            "SELECT COUNT(*) as cnt FROM writing_shots "
            "WHERE project_id = ?", (importer.project_id,)
        ).fetchone()["cnt"]
        assert count2 == 3, f"Import not idempotent: {count1} → {count2}"

    def test_chapter_structure_created(self, importer, tmp_dir: Path):
        chapter_path = tmp_dir / "chapter.md"
        chapter_path.write_text(SAMPLE_CHAPTER, encoding="utf-8")

        importer.import_chapter("v01.c01", str(chapter_path))

        row = importer.db.execute(
            "SELECT * FROM writing_project_structure WHERE layer_key = ?",
            ("v01.c01",),
        ).fetchone()
        assert row is not None
        assert row["layer_type"] == "chapter"

    def test_session_created(self, importer, tmp_dir: Path):
        chapter_path = tmp_dir / "chapter.md"
        chapter_path.write_text(SAMPLE_CHAPTER, encoding="utf-8")

        importer.import_chapter("v01.c01", str(chapter_path))

        sessions = importer.db.execute(
            "SELECT * FROM writing_sessions WHERE project_id = ?",
            ("proj_01",),
        ).fetchall()
        assert len(sessions) >= 1