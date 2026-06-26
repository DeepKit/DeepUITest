"""CLI-1/CLI-2: Standard P0 happy path + resume idempotency tests."""

from __future__ import annotations

import pytest
from click.testing import CliRunner
from pathlib import Path


class TestCliHappyPath:
    """CLI-1: Test import-baseline → review-shots → init → confirm → setup → status."""

    @pytest.fixture
    def happy_project(self, tmp_path):
        """Set up a complete project for happy path testing."""
        story_dir = tmp_path / "_Story" / "《分流》"
        inkflow_dir = story_dir / ".inkflow"
        inkflow_dir.mkdir(parents=True)

        (inkflow_dir / ".models").write_text(
            "providers:\n  test:\n    api_key: sk-test\n    base_url: https://test.example.com/v1\n    protocol: openai\n"
            "architect:\n  primary: claude-opus-4-6\n  candidates: []\n  fallback: gpt-5\n"
            "writer:\n  primary: local-default\n  candidates: []\n  fallback: local-default\n"
            "jury:\n  primary: local-default\n  candidates: []\n  fallback: local-default\n",
            encoding="utf-8",
        )

        chapter_dir = story_dir / "正文"
        chapter_dir.mkdir(parents=True)
        chapter_file = chapter_dir / "V01_第01章.md"
        chapter_file.write_text(
            "# 第 01 章\n\n## 一\n\n阿坤醒了。他从枕头下面摸出保鲜膜。\n\n## 二\n\n他走到门口。\n",
            encoding="utf-8",
        )

        return story_dir, chapter_file

    def test_full_happy_path(self, happy_project):
        """CLI-1: import-baseline → review-shots → init → confirm → setup → status."""
        import unittest.mock as mock
        import inkflow.cli as cli
        from inkflow.cli import main

        story_dir, chapter_file = happy_project
        db_path = story_dir / ".inkflow" / "inkflow.db"
        runner = CliRunner()

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", story_dir.parent):

            result = runner.invoke(main, [
                "import-baseline", "分流", "--chapter", "v01.c01", "--file", str(chapter_file),
            ])
            assert result.exit_code == 0, f"import-baseline: {result.output}"

            result = runner.invoke(main, ["review-shots", "分流", "--chapter", "v01.c01"])
            assert result.exit_code == 0, f"review-shots: {result.output}"

            result = runner.invoke(main, ["init", "分流"])
            assert result.exit_code == 0, f"init: {result.output}"

            # Fill in required high-creativity fields
            draft_path = story_dir / ".inkflow" / "contract-draft.yaml"
            content = draft_path.read_text(encoding="utf-8")
            content = content.replace("<<请填写: 各角色核心弧线, 如: 阿坤: 从被动承受到主动选择>>", "测试弧线")
            content = content.replace("<<请填写: 叙事语气基调, 如: 冷静克制, 不煽情, 让事实本身说话>>", "冷静克制")
            content = content.replace("<<请填写: 第 2 章的创作诠释, 如: 这一章的核心情绪是什么? 希望读者感受到什么?>>", "测试诠释")
            content = content.replace("<<请填写: 第 2 章中不可改变的事件, 如: 阿坤遇到拖行李箱的年轻人>>", "阿坤遇到年轻人")
            draft_path.write_text(content, encoding="utf-8")

            result = runner.invoke(main, ["confirm-contract", "分流"])
            assert result.exit_code == 0, f"confirm-contract: {result.output}"

            result = runner.invoke(main, ["setup", "分流", "--chapter", "v01.c02"])
            assert result.exit_code == 0, f"chapter setup: {result.output}"

            result = runner.invoke(main, ["status", "分流"])
            assert result.exit_code == 0, f"status: {result.output}"


class TestCliResumeIdempotent:
    """CLI-2: resume should not create duplicate shots/snapshots/prompts."""

    @pytest.fixture
    def resume_project(self, tmp_path):
        story_dir = tmp_path / "_Story" / "《分流》"
        inkflow_dir = story_dir / ".inkflow"
        inkflow_dir.mkdir(parents=True)

        (inkflow_dir / ".models").write_text(
            "providers:\n  test:\n    api_key: sk-test\n    base_url: https://test.example.com/v1\n    protocol: openai\n"
            "writer:\n  primary: local-default\n  candidates: []\n  fallback: local-default\n"
            "jury:\n  primary: local-default\n  candidates: []\n  fallback: local-default\n"
            "architect:\n  primary: claude-opus-4-6\n  candidates: []\n  fallback: gpt-5\n",
            encoding="utf-8",
        )

        chapter_dir = story_dir / "正文"
        chapter_dir.mkdir(parents=True)
        chapter_file = chapter_dir / "V01_第01章.md"
        chapter_file.write_text(
            "# 第 01 章\n\n## 一\n\n第一段。\n\n## 二\n\n第二段。\n", encoding="utf-8"
        )

        return story_dir, chapter_file

    def test_create_shots_idempotent(self, db):
        """create_shots with same (run_id, shot_index) should not duplicate."""
        from inkflow.services.session_manager import SessionManager

        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        db.commit()

        mgr = SessionManager(db, "p1")
        shots = [{"layer_key": "v01.c02", "shot_index": 1}]

        ids1 = mgr.create_shots("run_01", shots)
        ids2 = mgr.create_shots("run_01", shots)

        assert ids1 == ids2
        assert len(ids1) == 1

        # DB count should be 1, not 2
        count = db.execute(
            "SELECT COUNT(*) as cnt FROM writing_shots WHERE run_id = 'run_01'"
        ).fetchone()["cnt"]
        assert count == 1

    def test_resume_specific_aborted_session_reuses_requested_session(self, db):
        """Explicit resume must bind to the requested session, even if aborted."""
        from inkflow.cli import _resume_or_create_session
        from inkflow.services.session_manager import SessionManager

        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.commit()
        mgr = SessionManager(db, "p1")
        aborted_id = mgr.create_session(act_id="v01.c02", total_shots=2)
        aborted_run = mgr.get_session(aborted_id)["run_id"]
        mgr.abort_session(aborted_id)
        active_id = mgr.create_session(act_id="v01.c02", total_shots=2)

        session_id, run_id = _resume_or_create_session(
            mgr,
            db,
            "p1",
            "v01.c02",
            2,
            requested_session_id=aborted_id,
        )

        assert session_id == aborted_id
        assert run_id == aborted_run
        assert session_id != active_id
        assert mgr.get_session(aborted_id)["status"] == "active"
