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

            # Simulate the architect updating the draft after human discussion.
            draft_path = story_dir / ".inkflow" / "contract-draft.yaml"
            import yaml
            draft = yaml.safe_load(draft_path.read_text(encoding="utf-8"))
            draft["identity"]["pov_count"] = 4
            draft["identity"]["pov_characters"] = ["阿坤", "韩教授", "白英", "苏然"]
            draft["identity"]["character_arcs"] = "四条 POV 线都围绕外江侵蚀内江展开，各自从误认到看见代价。"
            draft["narrative_voice"]["register_tone"] = "冷静克制，不替读者解释主题。"
            draft["hard_boundaries"]["characters_alive"] = ["阿坤", "韩教授", "白英", "苏然"]
            draft["hard_boundaries"]["fixed_events"] = "阿坤遇到年轻人，韩教授发现骨片，白英看见茶社边界变化，苏然发现边界外推。"
            draft["creative_zones"]["chapter_2_interpretation"] = "本章让读者看见外江正在向内侵蚀，但不把机制说透。"
            draft["suspense_config"]["reader_anchor"] = "外江为什么会吞入三环内侧，谁会先被系统推出去？"
            draft["chapter_2_events"] = [
                {"shot": 1, "pov": "阿坤", "event": "阿坤在边界单中遇到拖行李箱的年轻人，膝盖疼痛暴露他的处境。"},
                {"shot": 2, "pov": "韩教授", "event": "韩教授在旧资料里发现骨片手势，意识到它和城市分流图形有相似处。"},
                {"shot": 3, "pov": "白英", "event": "白英发现茶社周围店铺被系统标注为外江边缘，客人开始减少。"},
                {"shot": 4, "pov": "苏然", "event": "苏然看到边界线向三环内侧移动，却还没有决定是否上报。", "type_roles": ["hook"]},
            ]
            draft_path.write_text(
                yaml.dump(draft, allow_unicode=True, sort_keys=False),
                encoding="utf-8",
            )

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
