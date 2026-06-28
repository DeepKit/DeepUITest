"""Test CLI commands."""

from __future__ import annotations

import pytest
from click.testing import CliRunner
from pathlib import Path

from inkflow.cli import (
    main,
    _extract_chapter_2_events,
    _extract_chapter_events,
    _format_jury_draft_score,
    _build_previous_context,
    _jury_unavailable_detail,
    _jury_verdict_all_unavailable,
    _validate_chapter_run_preflight,
    _validate_contract_scope_for_chapter,
)
from inkflow.models.enums import ShotStatus


@pytest.fixture
def runner():
    return CliRunner()


@pytest.fixture
def sample_project(tmp_dir: Path):
    """Set up a minimal project with inkflow.db."""
    from inkflow.db import init_project_db

    # Create story directory structure
    story_dir = tmp_dir / "_Story" / "《测试》"
    inkflow_dir = story_dir / ".inkflow"
    inkflow_dir.mkdir(parents=True)

    # Create .models
    models_path = inkflow_dir / ".models"
    models_path.write_text(
        "providers:\n  test:\n    api_key: sk-test\n    base_url: https://test.example.com/v1\n    protocol: openai\n"
        "architect:\n  primary: claude-opus-4-6\n  candidates: []\n  fallback: gpt-5\n"
        "writer:\n  primary: claude-sonnet-4-6\n  candidates: []\n  fallback: local-default\n"
        "jury:\n  primary: claude-sonnet-4-6\n  candidates: []\n  fallback: local-default\n",
        encoding="utf-8",
    )

    # Create chapter file
    chapter_dir = story_dir / "正文"
    chapter_dir.mkdir(parents=True)
    chapter_path = chapter_dir / "V01_第01章.md"
    chapter_path.write_text(
        "# 第 01 章：测试\n\n## 一\n\n正文内容第一段。\n\n## 二\n\n正文内容第二段。\n",
        encoding="utf-8",
    )

    db_path = inkflow_dir / "inkflow.db"
    db = init_project_db(db_path)
    db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', '测试')")
    db.commit()
    db.close()

    return tmp_dir


class TestCLIBasics:
    """Basic CLI functionality"""

    def test_help(self, runner):
        result = runner.invoke(main, ["--help"])
        assert result.exit_code == 0
        assert "import-baseline" in result.output
        assert "init" in result.output
        assert "setup" in result.output
        assert "run" in result.output
        assert "run-book" in result.output
        assert "book-report" in result.output
        assert "review" in result.output

    def test_version(self, runner):
        result = runner.invoke(main, ["--version"])
        assert result.exit_code == 0
        assert "3.6.0" in result.output

    def test_format_jury_draft_score_labels_gate_failure(self):
        line = _format_jury_draft_score(
            "01KW3Q5NCBPZWRG254EXAH2PK1",
            {
                "eligible": False,
                "trimmed_mean": 0,
                "raw_scores": [95, 70, 75],
                "failure_stage": "type_gate",
                "failure_summary": {
                    "label": "类型职责未通过",
                    "reasons": ["钩子/信息释放 72<80"],
                },
            },
        )

        assert "未入选" in line
        assert "类型职责未通过" in line
        assert "均分: 0" not in line

    def test_jury_verdict_all_unavailable_is_infrastructure_failure(self):
        verdict = {
            "winner_draft_id": None,
            "draft_scores": {
                "d1": {
                    "eligible": False,
                    "failure_stage": "jury_unavailable",
                    "missing_dimensions": ["reading_fluency"],
                },
                "d2": {
                    "eligible": False,
                    "failure_stage": "jury_unavailable",
                    "missing_dimensions": ["reading_fluency"],
                },
            },
        }

        assert _jury_verdict_all_unavailable(verdict) is True
        assert _jury_unavailable_detail(verdict) == "missing_dimensions=reading_fluency"


class TestImportBaseline:
    """import-baseline command"""

    def test_help(self, runner):
        result = runner.invoke(main, ["import-baseline", "--help"])
        assert result.exit_code == 0
        assert "--chapter" in result.output
        assert "--file" in result.output

    def test_missing_project_dir(self, runner, tmp_dir: Path):
        """Project directory doesn't exist → error"""
        # Override the story base for testing
        import unittest.mock as mock
        import inkflow.cli as cli
        import click
        with mock.patch.object(cli, '_resolve_project_db', side_effect=click.ClickException("项目目录不存在")):
            result = runner.invoke(main, [
                "import-baseline", "不存在", "--chapter", "v01.c01",
                "--file", str(tmp_dir / "test.md"),
            ])
            assert result.exit_code != 0


class TestSessions:
    """sessions commands"""

    def test_list_help(self, runner):
        result = runner.invoke(main, ["sessions", "list", "--help"])
        assert result.exit_code == 0

    def test_abort_help(self, runner):
        result = runner.invoke(main, ["sessions", "abort", "--help"])
        assert result.exit_code == 0


class TestSetup:
    """setup command"""

    def test_help(self, runner):
        result = runner.invoke(main, ["setup", "--help"])
        assert result.exit_code == 0
        assert "--chapter" in result.output


class TestBookRun:
    """Book-run orchestration commands."""

    def test_run_book_help(self, runner):
        result = runner.invoke(main, ["run-book", "--help"])
        assert result.exit_code == 0
        assert "--from" in result.output
        assert "--to" in result.output
        assert "--plan-only" in result.output

    def test_run_book_plan_only_creates_batch(self, runner, sample_project):
        import unittest.mock as mock
        import inkflow.cli as cli
        from inkflow.db import open_db

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)):
            result = runner.invoke(
                main,
                [
                    "run-book", "测试",
                    "--from", "v01.c02",
                    "--to", "v01.c03",
                    "--plan-only",
                ],
            )

        assert result.exit_code == 0, result.output
        assert "Book Run:" in result.output
        assert "未调用 setup/run" in result.output

        db = open_db(db_path)
        book_run = db.execute("SELECT * FROM writing_book_runs").fetchone()
        chapters = db.execute(
            "SELECT chapter_key, status FROM writing_book_run_chapters "
            "ORDER BY chapter_order"
        ).fetchall()
        db.close()

        assert book_run["from_chapter"] == "v01.c02"
        assert book_run["to_chapter"] == "v01.c03"
        assert book_run["status"] == "planned"
        assert [row["chapter_key"] for row in chapters] == ["v01.c02", "v01.c03"]
        assert {row["status"] for row in chapters} == {"planned"}

    def test_book_report_shows_latest_batch(self, runner, sample_project):
        import unittest.mock as mock
        import inkflow.cli as cli
        from inkflow.db import open_db

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        db = open_db(db_path)
        db.execute(
            "INSERT INTO writing_book_runs "
            "(book_run_id, project_id, from_chapter, to_chapter, status, total_chapters) "
            "VALUES ('book_01', 'p1', 'v01.c02', 'v01.c03', 'planned', 2)"
        )
        db.execute(
            "INSERT INTO writing_book_run_chapters "
            "(book_run_chapter_id, book_run_id, project_id, chapter_key, chapter_order, status) "
            "VALUES ('brc_01', 'book_01', 'p1', 'v01.c02', 1, 'planned')"
        )
        db.execute(
            "INSERT INTO writing_book_run_chapters "
            "(book_run_chapter_id, book_run_id, project_id, chapter_key, chapter_order, status) "
            "VALUES ('brc_02', 'book_01', 'p1', 'v01.c03', 2, 'planned')"
        )
        db.commit()
        db.close()

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)):
            result = runner.invoke(main, ["book-report", "测试"])

        assert result.exit_code == 0, result.output
        assert "Book Run: book_01" in result.output
        assert "v01.c02: planned" in result.output
        assert "v01.c03: planned" in result.output

    def test_run_book_executes_chapter_callbacks(self, runner, sample_project):
        import unittest.mock as mock
        import inkflow.cli as cli
        from inkflow.db import open_db

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        seen: dict[str, str] = {}

        def fake_setup(*, project, chapter, force):
            seen["setup"] = f"{project}:{chapter}:{force}"

        def fake_run(
            *,
            project,
            chapter,
            shot_id,
            writer_count,
            shot_count,
            resume,
            local_jury,
            resume_session_id,
            book_run_id,
        ):
            seen["book_run_id"] = book_run_id
            db = open_db(db_path)
            db.execute(
                "INSERT INTO writing_sessions "
                "(session_id, project_id, run_id, act_id, status, total_shots, completed_shots) "
                "VALUES ('sess_run_book', 'p1', 'run_book_chapter', ?, 'completed', 1, 1)",
                (chapter,),
            )
            db.execute(
                "INSERT INTO writing_shots "
                "(shot_id, logical_shot_id, project_id, run_id, layer_key, shot_index, "
                "shot_status, light_status, current_revision_id) "
                "VALUES (?, ?, 'p1', 'run_book_chapter', ?, 1, "
                "'done_green', 'green', 'rev_run_book')",
                (f"{chapter}.s01@run_book_chapter", f"{chapter}.s01", chapter),
            )
            db.commit()
            db.close()

        with (
            mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)),
            mock.patch.object(cli.setup_project, "callback", side_effect=fake_setup),
            mock.patch.object(cli.run_project, "callback", side_effect=fake_run),
        ):
            result = runner.invoke(
                main,
                [
                    "run-book", "测试",
                    "--from", "v01.c02",
                    "--to", "v01.c02",
                    "--force-setup",
                ],
            )

        assert result.exit_code == 0, result.output
        assert seen["setup"] == "测试:v01.c02:True"
        assert seen["book_run_id"]

        db = open_db(db_path)
        book_run = db.execute("SELECT * FROM writing_book_runs").fetchone()
        chapter = db.execute("SELECT * FROM writing_book_run_chapters").fetchone()
        db.close()

        assert book_run["status"] == "completed"
        assert book_run["completed_chapters"] == 1
        assert chapter["status"] == "completed"
        assert chapter["run_id"] == "run_book_chapter"


class TestInit:
    """init command"""

    def test_help(self, runner):
        result = runner.invoke(main, ["init", "--help"])
        assert result.exit_code == 0
        assert "--chapter-file" in result.output


class TestReview:
    """review command"""

    def test_help(self, runner):
        result = runner.invoke(main, ["review", "--help"])
        assert result.exit_code == 0
        assert "--accept" in result.output
        assert "--revise" in result.output
        assert "--reject" in result.output


class TestChapterEventExtraction:
    """Chapter outline event extraction."""

    def test_extracts_arbitrary_chapter_events(self):
        outline = """\
### 第 02 章：绕城

**阿坤线**：第二章事件一。
继续补充。

**苏然线**：第二章事件二。

### 第 03 章：内江

**白英线**：第三章事件。

### 第 04 章：清场

**韩教授线**：第四章事件一。
水痕出现。

**阿坤线**：第四章事件二。

### 第 05 章：茶社
"""

        chapter_4 = _extract_chapter_events(outline, 4)

        assert len(chapter_4) == 2
        assert chapter_4[0]["shot"] == 1
        assert chapter_4[0]["pov"] == "韩教授"
        assert "水痕出现" in chapter_4[0]["event"]
        assert chapter_4[1]["pov"] == "阿坤"

    def test_chapter_2_wrapper_uses_generic_extractor(self):
        outline = """\
### 第 02 章：绕城

**阿坤线**：第二章事件。

### 第 03 章：内江
"""

        events = _extract_chapter_2_events(outline)

        assert len(events) == 1
        assert events[0]["pov"] == "阿坤"


class TestRun:
    """run command"""

    def test_help(self, runner):
        result = runner.invoke(main, ["run", "--help"])
        assert result.exit_code == 0
        assert "--chapter" in result.output
        assert "--writer-count" in result.output
        assert "--resume" in result.output


class TestRepair:
    """repair command"""

    def test_help(self, runner):
        result = runner.invoke(main, ["repair", "--help"])
        assert result.exit_code == 0
        assert "--red" in result.output
        assert "--yellow" in result.output


class TestStatus:
    """status command"""

    def test_help(self, runner):
        result = runner.invoke(main, ["status", "--help"])
        assert result.exit_code == 0


class TestReviewShots:
    """review-shots command (M4)"""

    def test_help(self, runner):
        result = runner.invoke(main, ["review-shots", "--help"])
        assert result.exit_code == 0
        assert "--chapter" in result.output


class TestResume:
    """resume command"""

    def test_help(self, runner):
        result = runner.invoke(main, ["resume", "--help"])
        assert result.exit_code == 0


# ═══════════════════════════════════════════════════════
# CLI smoke tests using sample_project fixture
# ═══════════════════════════════════════════════════════


class TestInitSmoke:
    """init command smoke test"""

    def test_init_creates_contract_draft(self, runner, sample_project, tmp_dir):
        """init should create contract-draft.yaml"""
        import unittest.mock as mock
        import inkflow.cli as cli

        story_dir = tmp_dir / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        draft_path = story_dir / ".inkflow" / "contract-draft.yaml"
        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(main, ["init", "测试"])
            assert result.exit_code == 0, result.output
            assert draft_path.exists(), "contract-draft.yaml should be created"
            content = draft_path.read_text(encoding="utf-8")
            assert "P0 只生成第 2 章" not in content
            assert "500-800 字/段落" not in content


class TestChapterSetupSmoke:
    """Chapter setup command smoke tests."""

    def _confirm_chapter_contract(self, db_path):
        from inkflow.db import open_db
        from inkflow.services import ContractCompiler

        db = open_db(db_path)
        compiler = ContractCompiler(db, "p1")
        mc_id = compiler.create_meta_contract({
            "identity": {"title": "测试"},
            "narrative_voice": {},
            "hard_boundaries": {},
            "anti_reveal": {},
            "world_knowledge": {},
            "structure_rules": {
                "chapter_3_events": [
                    {"shot": 1, "title": "第一镜", "pov": "角色A", "event": "事件一"},
                    {"shot": 2, "title": "第二镜", "pov": "角色B", "event": "事件二"},
                ],
            },
            "anti_patterns": {},
            "style_locks": {},
            "motif_system": {},
            "creative_zones": {},
            "suspense_config": {"chapter_hooks": ["最后一句必须未完成"]},
        })
        compiler.update_contract_status(mc_id, "human_review")
        compiler.update_contract_status(mc_id, "confirmed")
        db.close()

    def test_setup_chapter_creates_production_package(self, runner, sample_project, tmp_dir):
        import unittest.mock as mock
        import inkflow.cli as cli

        story_dir = sample_project / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        setup_path = story_dir / ".inkflow" / "chapter-setups" / "v01.c03.yaml"

        self._confirm_chapter_contract(db_path)

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(main, ["setup", "测试", "--chapter", "v01.c03"])

        assert result.exit_code == 0, result.output
        assert setup_path.exists()
        content = setup_path.read_text(encoding="utf-8")
        assert "inkflow.chapter_setup.v1" in content
        assert "exposition_gate" in content

    def test_run_requires_chapter_setup(self, runner, sample_project, tmp_dir):
        import unittest.mock as mock
        import inkflow.cli as cli

        story_dir = sample_project / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        self._confirm_chapter_contract(db_path)

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(
                main,
                ["run", "测试", "--chapter", "v01.c03", "--local-jury"],
            )

        assert result.exit_code != 0
        assert "ink setup" in result.output

    def test_contract_scope_rejects_stale_chapter_only_rule(self):
        with pytest.raises(Exception) as exc:
            _validate_contract_scope_for_chapter(
                "v01.c03",
                {
                    "hard_boundaries": {
                        "world_rules": [
                            "P0 只生成第 2 章，不引入第 3 章及以后的新角色/新事件",
                        ],
                    },
                    "style_locks": {},
                },
            )

        assert "只生成第 2 章" in str(exc.value)

    def test_contract_scope_rejects_deprecated_character_alias(self):
        with pytest.raises(Exception) as exc:
            _validate_contract_scope_for_chapter(
                "v01.c03",
                {
                    "identity": {
                        "pov_characters": ["郑坤", "白英", "苏然", "韩教授"],
                    },
                    "hard_boundaries": {
                        "characters_alive": ["郑坤", "白英", "苏然", "韩教授"],
                        "fixed_events": "阿坤到了太古里。",
                    },
                    "style_locks": {},
                },
            )

        assert "角色名仍含旧称 阿坤" in str(exc.value)
        assert "郑坤" in str(exc.value)

    def test_run_preflight_rejects_setup_from_old_contract(self):
        with pytest.raises(Exception) as exc:
            _validate_chapter_run_preflight(
                "测试",
                "v01.c03",
                {
                    "source_contract": {"meta_contract_id": "old"},
                    "shots": [{"shot": 1}],
                },
                {"meta_contract_id": "new"},
                {"hard_boundaries": {}, "style_locks": {}},
                [{"shot": 1, "event": "事件"}],
            )

        assert "旧元契约" in str(exc.value)

    def test_run_preflight_rejects_setup_with_deprecated_alias(self):
        with pytest.raises(Exception) as exc:
            _validate_chapter_run_preflight(
                "测试",
                "v01.c03",
                {
                    "source_contract": {"meta_contract_id": "mc"},
                    "shots": [{"shot": 1, "must_land": "阿坤到了太古里。"}],
                },
                {"meta_contract_id": "mc"},
                {
                    "identity": {
                        "pov_characters": ["郑坤", "白英", "苏然", "韩教授"],
                    },
                    "hard_boundaries": {
                        "characters_alive": ["郑坤", "白英", "苏然", "韩教授"],
                    },
                    "style_locks": {},
                },
                [{"shot": 1, "event": "郑坤到了太古里。"}],
            )

        assert "setup 包仍含废弃角色名" in str(exc.value)

    def test_review_writes_chapter_review(self, runner, sample_project, tmp_dir):
        import unittest.mock as mock
        import inkflow.cli as cli
        from inkflow.db import open_db

        story_dir = sample_project / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        review_path = story_dir / ".inkflow" / "chapter-reviews" / "v01.c03.yaml"
        db = open_db(db_path)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('sess_review', 'p1', 'run_review', 'completed')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, "
            "light_status, current_revision_id) "
            "VALUES ('shot_review', 'p1', 'run_review', 'v01.c03', 1, "
            "'done_green', 'green', 'rev_review')"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('contract_review', 'p1', 'run_review', 'shot_review', "
            "'v01.c03', 'locked', 'hash_review', '{}', '{}', '{}')"
        )
        db.execute(
            "INSERT INTO shot_revisions "
            "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
            "text, text_hash_normalized, is_current, attempt_id) "
            "VALUES ('rev_review', 'shot_review', 'run_review', 'contract_review', 1, "
            "'write_generate', '审稿正文。', 'text_hash_review', 1, 'attempt_review')"
        )
        db.execute(
            "INSERT INTO writing_architect_gates "
            "(gate_id, run_id, level, scope_key, status, check_result_json) "
            "VALUES ('gate_review_l3', 'run_review', 'L3', 'v01.c03', "
            "'passed', '{\"passed\":true}')"
        )
        db.commit()
        db.close()

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(
                main,
                ["review", "测试", "--chapter", "v01.c03", "--accept"],
            )

        assert result.exit_code == 0, result.output
        assert review_path.exists()
        content = review_path.read_text(encoding="utf-8")
        assert "inkflow.chapter_review.v1" in content
        assert "accepted" in content
        assert "run_review" in content
        db = open_db(db_path)
        row = db.execute(
            "SELECT status, run_id FROM writing_chapter_reviews "
            "WHERE project_id = 'p1' AND chapter_key = 'v01.c03'"
        ).fetchone()
        db.close()
        assert row["status"] == "accepted"
        assert row["run_id"] == "run_review"

    def test_review_reject_invalidates_latest_run_shots(self, runner, sample_project, tmp_dir):
        import unittest.mock as mock
        import inkflow.cli as cli
        from inkflow.db import open_db

        story_dir = sample_project / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        db = open_db(db_path)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('sess_reject', 'p1', 'run_reject', 'completed')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, "
            "light_status, current_revision_id) "
            "VALUES ('shot_reject', 'p1', 'run_reject', 'v01.c04', 1, "
            "'done_green', 'green', 'rev_reject')"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('contract_reject', 'p1', 'run_reject', 'shot_reject', "
            "'v01.c04', 'locked', 'hash_reject', '{}', '{}', '{}')"
        )
        db.execute(
            "INSERT INTO shot_revisions "
            "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
            "text, text_hash_normalized, is_current, attempt_id) "
            "VALUES ('rev_reject', 'shot_reject', 'run_reject', 'contract_reject', 1, "
            "'write_generate', '被拒正文。', 'text_hash_reject', 1, 'attempt_reject')"
        )
        db.commit()
        db.close()

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(
                main,
                ["review", "测试", "--chapter", "v01.c04", "--reject", "--notes", "整体重写"],
            )

        assert result.exit_code == 0, result.output
        db = open_db(db_path)
        shot = db.execute(
            "SELECT shot_status, placeholder_type FROM writing_shots "
            "WHERE shot_id = 'shot_reject'"
        ).fetchone()
        review = db.execute(
            "SELECT status FROM writing_chapter_reviews WHERE run_id = 'run_reject'"
        ).fetchone()
        db.close()
        assert shot["shot_status"] == "redo"
        assert shot["placeholder_type"] == "redo_placeholder"
        assert review["status"] == "rejected"


class TestConstitutionCommand:
    """ARCH-4: constitution CLI command"""

    def test_existing_constitution_displays_without_regeneration(self, runner, sample_project, tmp_dir):
        import unittest.mock as mock
        import inkflow.cli as cli

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        from inkflow.db.connection import open_db

        db = open_db(str(db_path))
        db.execute(
            "INSERT INTO writing_book_constitutions ("
            "constitution_id, project_id, version, arc_shape, tension_peak_chapter, "
            "volume_map_json, chapter_roles_json, motif_lifecycle_json, "
            "global_deviation_mean, global_deviation_range_json, status"
            ") VALUES ("
            "'const_01', 'p1', 1, 'slow_build', 'v01.c04', "
            "'{}', '{}', '[]', 0.45, '[0.2, 0.7]', 'draft'"
            ")"
        )
        db.commit()
        db.close()

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(main, ["constitution", "测试"])

        assert result.exit_code == 0, result.output
        assert "已有宪法" in result.output
        assert "slow_build" in result.output


class TestConfirmContract:
    """P0-1 / B13: confirm-contract CLI command"""

    def _create_draft_yaml(self, sample_project):
        """Create a minimal valid contract-draft.yaml."""
        draft_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "contract-draft.yaml"
        draft_path.parent.mkdir(parents=True, exist_ok=True)
        draft_path.write_text("""\
identity:
  title: 测试
  genre: 文学小说
  setting: 测试城
  pov_count: 2
  pov_characters:
    - 角色A
    - 角色B
  character_arcs: 角色A从迷茫到坚定，角色B从固执到放下

narrative_voice:
  style: 测试风
  sensory_density: 中
  body_moment: 是
  dialogue_ratio: 低
  register: 测试语气
  register_tone: 冷静克制

hard_boundaries:
  characters_alive:
    - 角色A
    - 角色B
  world_rules:
    - 测试规则
  fixed_events: 角色A遇到角色B

style_locks:
  opening: 身体时刻开场
  ending: 沉默结尾
  sensory: 每段有感官描写
  dialect: 方言点缀
  paragraph_length: 500字

anti_patterns:
  avoid:
    - 概念总结
    - 系统是恶人

world_knowledge:
  locations:
    - 测试城
  key_objects:
    - 测试物件
  time_period: 当代
  season: 冬天
  weather: 雾

motif_system:
  primary:
    - 测试意象
  secondary:
    - 次要意象
  visual_markers:
    - 视觉符号

creative_zones:
  allowed_freedom: 对话细节
  must_consult: 核心情节
  chapter_2_scope: 严格执行大纲
  chapter_2_interpretation: 测试诠释

chapter_2_events:
  - shot: 1
    pov: 角色A
    event: 测试事件1
  - shot: 2
    pov: 角色B
    event: 测试事件2

suspense_config:
  reader_anchor: 测试抓手
  information_gap:
    - 测试信息差
  core_objects:
    测试物件: 背景→线索→证据
  chapter_hooks:
    - 测试钩子
  numbers_with_temperature:
    - 测试数字
  suspense_density: 测试密度
""", encoding="utf-8")

    def test_confirm_draft_to_confirmed(self, runner, sample_project, tmp_dir):
        """confirm-contract should read draft YAML and transition to confirmed"""
        import unittest.mock as mock
        import inkflow.cli as cli

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            # Run init first
            result = runner.invoke(main, ["init", "测试"])
            assert result.exit_code == 0

            # Create valid draft YAML
            self._create_draft_yaml(sample_project)

            # Confirm
            result = runner.invoke(main, ["confirm-contract", "测试"])
            assert result.exit_code == 0, result.output
            assert "confirmed" in result.output.lower() or "✅" in result.output

            from inkflow.db.connection import open_db
            db = open_db(str(db_path))
            row = db.execute(
                "SELECT status FROM writing_meta_contract WHERE project_id = "
                "(SELECT project_id FROM projects WHERE name = '测试') "
                "ORDER BY created_at DESC LIMIT 1"
            ).fetchone()
            assert row["status"] == "confirmed"
            db.close()

    def test_confirm_no_draft_fails(self, runner, sample_project, tmp_dir):
        """confirm-contract without draft YAML should fail"""
        import unittest.mock as mock
        import inkflow.cli as cli

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(main, ["confirm-contract", "测试"])
            assert result.exit_code != 0
            assert "contract-draft.yaml" in result.output or "setup" in result.output

    def test_confirm_missing_character_arcs_fails(self, runner, sample_project, tmp_dir):
        """confirm-contract should reject draft without character_arcs"""
        import unittest.mock as mock
        import inkflow.cli as cli

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            runner.invoke(main, ["init", "测试"])

            self._create_draft_yaml(sample_project)
            # Corrupt the draft: remove character_arcs
            draft_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "contract-draft.yaml"
            content = draft_path.read_text(encoding="utf-8")
            # Replace the character_arcs value with the placeholder
            import re
            content = re.sub(
                r'character_arcs:.*',
                'character_arcs: "<<请填写: 各角色核心弧线>>"',
                content,
            )
            draft_path.write_text(content, encoding="utf-8")

            result = runner.invoke(main, ["confirm-contract", "测试"])
            assert result.exit_code != 0, result.output
            assert "character_arcs" in result.output


class TestReviewShotsSmoke:
    """M4: review-shots command smoke test"""

    def test_review_shots_with_imported_data(self, runner, sample_project):
        import unittest.mock as mock
        import inkflow.cli as cli

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        chapter_file = sample_project / "_Story" / "《测试》" / "正文" / "V01_第01章.md"
        chapter_file.write_text(
            "# 第 01 章\n\n## 一\n\n第一段内容。\n\n## 二\n\n第二段内容。\n",
            encoding="utf-8",
        )

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)):
            # Import first so there are shots to review
            runner.invoke(main, [
                "import-baseline", "测试",
                "--chapter", "v01.c01",
                "--file", str(chapter_file),
            ])
            result = runner.invoke(main, [
                "review-shots", "测试", "--chapter", "v01.c01",
            ])
            assert result.exit_code == 0


class TestStatusSmoke:
    """T3: status command execution smoke test"""

    def test_status_with_project(self, runner, sample_project):
        """status should show project info"""
        import unittest.mock as mock
        import inkflow.cli as cli

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)):
            result = runner.invoke(main, ["status", "测试"])
            assert result.exit_code == 0
            assert "测试" in result.output

    def test_status_shows_chapter_canonical_state(self, runner, sample_project):
        """status should expose latest run and accepted canonical state."""
        import unittest.mock as mock
        import inkflow.cli as cli
        from inkflow.db import open_db

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        db = open_db(db_path)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('sess_status', 'p1', 'run_status', 'completed')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, logical_shot_id, project_id, run_id, layer_key, shot_index, "
            "shot_status, current_revision_id) "
            "VALUES ('v01.c02.s01@runstatusrunstatusruns1', 'v01.c02.s01', "
            "'p1', 'run_status', 'v01.c02', 1, 'done_green', 'rev_status')"
        )
        db.execute(
            "INSERT INTO writing_chapter_reviews "
            "(review_id, project_id, chapter_key, run_id, status) "
            "VALUES ('review_status', 'p1', 'v01.c02', 'run_status', 'accepted')"
        )
        db.commit()
        db.close()

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)):
            result = runner.invoke(main, ["status", "测试"])

        assert result.exit_code == 0, result.output
        assert "章节 Latest Run" in result.output
        assert "v01.c02: completed 1/1 run=run_status" in result.output
        assert "章节 Canonical" in result.output
        assert "v01.c02: accepted run=run_status" in result.output


class TestExportSmoke:
    """Export command path smoke tests."""

    def test_export_defaults_to_story_text_dir(self, runner, sample_project, tmp_dir):
        """默认导出应写入项目 正文 目录，而不是 .inkflow/export。"""
        import unittest.mock as mock
        import inkflow.cli as cli

        story_dir = sample_project / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        out_path = story_dir / "正文" / "测试_v01.c02_导出.md"
        old_export_dir = story_dir / ".inkflow" / "export"

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(main, ["export", "测试", "--chapter", "v01.c02"])

        assert result.exit_code == 0, result.output
        assert out_path.exists()
        assert "导出完成" in result.output
        assert not old_export_dir.exists()

    def test_relative_export_output_resolves_under_story_text_dir(self, runner, sample_project, tmp_dir):
        """相对 -o 路径应落在项目 正文 目录下。"""
        import unittest.mock as mock
        import inkflow.cli as cli

        story_dir = sample_project / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        out_path = story_dir / "正文" / "custom.md"

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(main, ["export", "测试", "--chapter", "v01.c02", "-o", "custom.md"])

        assert result.exit_code == 0, result.output
        assert out_path.exists()

    def test_markdown_export_hides_pipeline_metadata(self, runner, sample_project, tmp_dir):
        """编辑稿导出不应泄露灯色、精彩/坏味评分或 POV 路由。"""
        import unittest.mock as mock
        import inkflow.cli as cli
        from inkflow.db import open_db

        story_dir = sample_project / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        out_path = story_dir / "正文" / "测试_v01.c02_导出.md"

        db = open_db(db_path)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('sess_export', 'p1', 'run_export', 'active')"
        )
        db.execute(
            "INSERT INTO writing_shots ("
            "shot_id, project_id, run_id, layer_key, shot_index, shot_status, "
            "light_status, brilliance_level, badsmell_level"
            ") VALUES ("
            "'shot_export', 'p1', 'run_export', 'v01.c02', 5, 'done_green', "
            "'green', 'A', 'B'"
            ")"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts ("
            "contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, pov_routing_json, contract_json"
            ") VALUES ("
            "'contract_export', 'p1', 'run_export', 'shot_export', 'v01.c02', 'locked', "
            "'hash_export', '{\"title\":\"慢下来\"}', '{}', "
            "'{\"pov_character\":\"韩教授\"}', '{}'"
            ")"
        )
        db.execute(
            "INSERT INTO shot_revisions ("
            "revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
            "text, text_hash_normalized, is_current, attempt_id"
            ") VALUES ("
            "'rev_export', 'shot_export', 'run_export', 'contract_export', 1, "
            "'write_generate', '他把屏幕合上。', 'text_hash_export', 1, 'attempt_export'"
            ")"
        )
        db.execute(
            "UPDATE writing_shots SET current_revision_id = 'rev_export' "
            "WHERE shot_id = 'shot_export'"
        )
        db.commit()
        db.close()

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(
                main, ["export", "测试", "--chapter", "v01.c02", "--draft"],
            )

        assert result.exit_code == 0, result.output
        content = out_path.read_text(encoding="utf-8")
        assert "### 慢下来" in content
        assert "### 场景" not in content
        assert "green" not in content
        assert "brilliance=" not in content
        assert "badsmell=" not in content
        assert "POV=" not in content

    def test_markdown_export_strips_generated_headings(self, runner, sample_project, tmp_dir):
        """模型正文里重复生成的 Markdown 标题不应进入审稿导出。"""
        import unittest.mock as mock
        import inkflow.cli as cli
        from inkflow.db import open_db

        story_dir = sample_project / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        out_path = story_dir / "正文" / "测试_v01.c02_导出.md"

        db = open_db(db_path)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('sess_heading', 'p1', 'run_heading', 'active')"
        )
        db.execute(
            "INSERT INTO writing_shots ("
            "shot_id, project_id, run_id, layer_key, shot_index, shot_status"
            ") VALUES ('shot_heading', 'p1', 'run_heading', 'v01.c02', 1, 'done_green')"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts ("
            "contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json"
            ") VALUES ("
            "'contract_heading', 'p1', 'run_heading', 'shot_heading', 'v01.c02', 'locked', "
            "'hash_heading', '{\"title\":\"玻璃里的保鲜膜\"}', '{}', '{}'"
            ")"
        )
        db.execute(
            "INSERT INTO shot_revisions ("
            "revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
            "text, text_hash_normalized, is_current, attempt_id"
            ") VALUES ("
            "'rev_heading', 'shot_heading', 'run_heading', 'contract_heading', 1, "
            "'write_generate', '# 玻璃里的保鲜膜\n\n雨落在玻璃上。', "
            "'text_hash_heading', 1, 'attempt_heading'"
            ")"
        )
        db.execute(
            "UPDATE writing_shots SET current_revision_id = 'rev_heading' "
            "WHERE shot_id = 'shot_heading'"
        )
        db.commit()
        db.close()

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(
                main, ["export", "测试", "--chapter", "v01.c02", "--draft"],
            )

        assert result.exit_code == 0, result.output
        content = out_path.read_text(encoding="utf-8")
        assert "### 玻璃里的保鲜膜" in content
        assert "\n# 玻璃里的保鲜膜\n" not in content
        assert "雨落在玻璃上。" in content

    def test_markdown_export_uses_contract_json_title_when_must_land_title_lost(
        self, db, tmp_dir,
    ):
        """大纲重写丢失 must_land.title 时，导出应回退到完整 contract title。"""
        from inkflow.export import export_markdown

        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', '测试')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('sess_title_fallback', 'p1', 'run_title_fallback', 'active')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, current_revision_id) "
            "VALUES ('shot_title_fallback', 'p1', 'run_title_fallback', 'v01.c02', 1, "
            "'done_green', 'rev_title_fallback')"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('contract_title_fallback', 'p1', 'run_title_fallback', "
            "'shot_title_fallback', 'v01.c02', 'locked', 'hash_title_fallback', "
            "'{\"beats\":\"事件序列\"}', '{}', "
            "'{\"must_land\":{\"title\":\"四份通知\",\"beats\":\"## 四份通知\\n\\n- 事件\"}}')"
        )
        db.execute(
            "INSERT INTO shot_revisions "
            "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
            "text, text_hash_normalized, is_current, attempt_id) "
            "VALUES ('rev_title_fallback', 'shot_title_fallback', 'run_title_fallback', "
            "'contract_title_fallback', 1, 'write_generate', '白英把门掩上。', "
            "'text_hash_title_fallback', 1, 'attempt_title_fallback')"
        )
        db.commit()

        out_path = export_markdown(
            db, tmp_dir / "title_fallback.md",
            chapters=["v01.c02"],
            run_id="run_title_fallback",
        )

        content = out_path.read_text(encoding="utf-8")
        assert "### 四份通知" in content
        assert "白英把门掩上。" in content

    def test_markdown_export_formats_paragraphs_and_scene_breaks(self, runner, sample_project, tmp_dir):
        """编辑稿导出应拆分过长自然段，并在镜头之间加入分隔线。"""
        import unittest.mock as mock
        import inkflow.cli as cli
        from inkflow.db import open_db

        story_dir = sample_project / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        out_path = story_dir / "正文" / "测试_v01.c02_导出.md"

        sentence = (
            "雨水贴着窗缝往里钻，屏幕上的蓝线在她眼底一闪，"
            "像有人把城市的边缘重新描了一遍。"
        )
        long_paragraph = sentence * 12

        db = open_db(db_path)
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('sess_layout', 'p1', 'run_layout', 'active')"
        )
        for index, title, text in [
            (1, "第一镜", long_paragraph),
            (2, "第二镜", "她把报告合上。"),
        ]:
            shot_id = f"shot_layout_{index}"
            contract_id = f"contract_layout_{index}"
            revision_id = f"rev_layout_{index}"
            db.execute(
                "INSERT INTO writing_shots ("
                "shot_id, project_id, run_id, layer_key, shot_index, shot_status"
                ") VALUES (?, 'p1', 'run_layout', 'v01.c02', ?, 'done_green')",
                (shot_id, index),
            )
            db.execute(
                "INSERT INTO writing_shot_contracts ("
                "contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
                "snapshot_hash, must_land_json, anti_write_json, contract_json"
                ") VALUES (?, 'p1', 'run_layout', ?, 'v01.c02', 'locked', "
                "'hash_layout', ?, '{}', '{}')",
                (contract_id, shot_id, f'{{"title":"{title}"}}'),
            )
            db.execute(
                "INSERT INTO shot_revisions ("
                "revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
                "text, text_hash_normalized, is_current, attempt_id"
                ") VALUES (?, ?, 'run_layout', ?, 1, "
                "'write_generate', ?, ?, 1, ?)",
                (revision_id, shot_id, contract_id, text, f"text_hash_layout_{index}", f"attempt_layout_{index}"),
            )
            db.execute(
                "UPDATE writing_shots SET current_revision_id = ? WHERE shot_id = ?",
                (revision_id, shot_id),
            )
        db.commit()
        db.close()

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(
                main, ["export", "测试", "--chapter", "v01.c02", "--draft"],
            )

        assert result.exit_code == 0, result.output
        content = out_path.read_text(encoding="utf-8")
        assert "### 第一镜" in content
        assert "\n---\n" in content
        assert "### 第二镜" in content
        assert long_paragraph not in content

        prose_blocks = [
            block.strip()
            for block in content.split("\n\n")
            if block.strip()
            and not block.startswith("#")
            and block.strip() != "---"
        ]
        assert any(sentence in block for block in prose_blocks)
        assert all(len(block) <= 420 for block in prose_blocks)

    def test_markdown_export_filters_to_requested_run_id(self, db, tmp_dir):
        """自动导出当前 run 时不应混入同章节旧 run 的正文。"""
        from inkflow.export import export_markdown

        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', '测试')")
        for run_id, session_id, shot_id, contract_id, revision_id, title, text in [
            ("run_old", "sess_old", "shot_old", "contract_old", "rev_old", "旧镜", "旧 run 正文。"),
            ("run_new", "sess_new", "shot_new", "contract_new", "rev_new", "新镜", "当前 run 正文。"),
        ]:
            db.execute(
                "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
                "VALUES (?, 'p1', ?, 'active')",
                (session_id, run_id),
            )
            db.execute(
                "INSERT INTO writing_shots "
                "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, current_revision_id) "
                "VALUES (?, 'p1', ?, 'v01.c02', 1, 'done_green', ?)",
                (shot_id, run_id, revision_id),
            )
            db.execute(
                "INSERT INTO writing_shot_contracts "
                "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
                "snapshot_hash, must_land_json, anti_write_json, contract_json) "
                "VALUES (?, 'p1', ?, ?, 'v01.c02', 'locked', ?, ?, '{}', '{}')",
                (contract_id, run_id, shot_id, f"hash_{run_id}", f'{{"title":"{title}"}}'),
            )
            db.execute(
                "INSERT INTO shot_revisions "
                "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
                "text, text_hash_normalized, is_current, attempt_id) "
                "VALUES (?, ?, ?, ?, 1, 'write_generate', ?, ?, 1, ?)",
                (revision_id, shot_id, run_id, contract_id, text, f"text_hash_{run_id}", f"attempt_{run_id}"),
            )
        db.commit()

        out_path = export_markdown(
            db, tmp_dir / "out.md", chapters=["v01.c02"], run_id="run_new",
        )
        content = out_path.read_text(encoding="utf-8")

        assert "当前 run 正文。" in content
        assert "### 新镜" in content
        assert "旧 run 正文。" not in content
        assert "### 旧镜" not in content

    def test_markdown_export_accepted_only_uses_reviewed_run(self, db, tmp_dir):
        """正式导出应只取人工 accepted 的章节 run。"""
        from inkflow.export import export_markdown

        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', '测试')")
        for run_id, session_id, shot_id, contract_id, revision_id, title, text in [
            ("run_rejected", "sess_rejected", "shot_rejected", "contract_rejected", "rev_rejected", "退稿", "不应导出。"),
            ("run_accepted", "sess_accepted", "shot_accepted", "contract_accepted", "rev_accepted", "定稿", "应导出。"),
        ]:
            db.execute(
                "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
                "VALUES (?, 'p1', ?, 'completed')",
                (session_id, run_id),
            )
            db.execute(
                "INSERT INTO writing_shots "
                "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, current_revision_id) "
                "VALUES (?, 'p1', ?, 'v01.c02', 1, 'done_green', ?)",
                (shot_id, run_id, revision_id),
            )
            db.execute(
                "INSERT INTO writing_shot_contracts "
                "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
                "snapshot_hash, must_land_json, anti_write_json, contract_json) "
                "VALUES (?, 'p1', ?, ?, 'v01.c02', 'locked', ?, ?, '{}', '{}')",
                (contract_id, run_id, shot_id, f"hash_{run_id}", f'{{"title":"{title}"}}'),
            )
            db.execute(
                "INSERT INTO shot_revisions "
                "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
                "text, text_hash_normalized, is_current, attempt_id) "
                "VALUES (?, ?, ?, ?, 1, 'write_generate', ?, ?, 1, ?)",
                (revision_id, shot_id, run_id, contract_id, text, f"text_hash_{run_id}", f"attempt_{run_id}"),
            )
        db.execute(
            "INSERT INTO writing_chapter_reviews "
            "(review_id, project_id, chapter_key, run_id, status) "
            "VALUES ('review_accepted', 'p1', 'v01.c02', 'run_accepted', 'accepted')"
        )
        db.execute(
            "INSERT INTO writing_chapter_reviews "
            "(review_id, project_id, chapter_key, run_id, status) "
            "VALUES ('review_rejected', 'p1', 'v01.c02', 'run_rejected', 'rejected')"
        )
        db.commit()

        out_path = export_markdown(
            db, tmp_dir / "accepted.md", chapters=["v01.c02"], accepted_only=True,
        )
        content = out_path.read_text(encoding="utf-8")

        assert "应导出。" in content
        assert "### 定稿" in content
        assert "不应导出。" not in content
        assert "### 退稿" not in content

    def test_previous_context_uses_only_accepted_historical_runs(self, db):
        """前文上下文不应读取 rejected/unaccepted 历史 run。"""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', '测试')")
        for run_id, session_id, shot_id, contract_id, revision_id, status, text in [
            ("run_rejected", "sess_rejected", "shot_rejected_ctx", "contract_rejected_ctx", "rev_rejected_ctx", "rejected", "退稿里的韩教授。"),
            ("run_accepted", "sess_accepted", "shot_accepted_ctx", "contract_accepted_ctx", "rev_accepted_ctx", "accepted", "定稿里的韩教授。"),
        ]:
            db.execute(
                "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
                "VALUES (?, 'p1', ?, 'completed')",
                (session_id, run_id),
            )
            db.execute(
                "INSERT INTO writing_shots "
                "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, current_revision_id) "
                "VALUES (?, 'p1', ?, 'v01.c02', 1, 'done_green', ?)",
                (shot_id, run_id, revision_id),
            )
            db.execute(
                "INSERT INTO writing_shot_contracts "
                "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
                "snapshot_hash, must_land_json, anti_write_json, pov_routing_json, contract_json) "
                "VALUES (?, 'p1', ?, ?, 'v01.c02', 'locked', ?, '{}', '{}', "
                "'{\"pov_character\":\"韩教授\"}', '{}')",
                (contract_id, run_id, shot_id, f"hash_{run_id}"),
            )
            db.execute(
                "INSERT INTO shot_revisions "
                "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
                "text, text_hash_normalized, is_current, attempt_id) "
                "VALUES (?, ?, ?, ?, 1, 'write_generate', ?, ?, 1, ?)",
                (revision_id, shot_id, run_id, contract_id, text, f"text_hash_{run_id}", f"attempt_{run_id}"),
            )
            db.execute(
                "INSERT INTO writing_chapter_reviews "
                "(review_id, project_id, chapter_key, run_id, status) "
                "VALUES (?, 'p1', 'v01.c02', ?, ?)",
                (f"review_{run_id}", run_id, status),
            )
        db.commit()

        context = _build_previous_context(
            db,
            "run_current",
            [],
            0,
            pov_character="韩教授",
            project_id="p1",
        )

        assert context
        assert "定稿里的韩教授" in context[0]["text"]
        assert "退稿里的韩教授" not in context[0]["text"]

    def test_plain_text_export_strips_generated_heading_lines(self, db, tmp_dir):
        """纯文本导出也应清掉模型生成标题，并保留同块正文。"""
        from inkflow.export import export_plain_text

        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', '测试')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('sess_plain', 'p1', 'run_plain', 'active')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, current_revision_id) "
            "VALUES ('shot_plain', 'p1', 'run_plain', 'v01.c02', 1, 'done_green', 'rev_plain')"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('contract_plain', 'p1', 'run_plain', 'shot_plain', 'v01.c02', "
            "'locked', 'hash_plain', '{}', '{}', '{}')"
        )
        db.execute(
            "INSERT INTO shot_revisions "
            "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
            "text, text_hash_normalized, is_current, attempt_id) "
            "VALUES ('rev_plain', 'shot_plain', 'run_plain', 'contract_plain', 1, "
            "'write_generate', '# 内部标题\n同一段正文保留。\n\n## 第二标题\n下一段正文。', "
            "'text_hash_plain', 1, 'attempt_plain')"
        )
        db.commit()

        out_path = export_plain_text(
            db, tmp_dir / "plain.txt", chapters=["v01.c02"], run_id="run_plain",
        )
        content = out_path.read_text(encoding="utf-8")

        assert "内部标题" not in content
        assert "第二标题" not in content
        assert "同一段正文保留。" in content
        assert "下一段正文。" in content


class TestImportBaselineSmoke:
    """T3: import-baseline idempotent re-import"""

    def test_import_twice_no_duplicates(self, runner, sample_project):
        """Re-importing same chapter should not create duplicates"""
        from inkflow.db import open_db
        import unittest.mock as mock
        import inkflow.cli as cli

        db_path = sample_project / "_Story" / "《测试》" / ".inkflow" / "inkflow.db"
        chapter_file = sample_project / "_Story" / "《测试》" / "正文" / "V01_第01章.md"

        # Write a real chapter file for import
        chapter_file.write_text(
            "# 第 01 章\n\n## 一\n\n第一段内容。\n\n## 二\n\n第二段内容。\n",
            encoding="utf-8",
        )

        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)):
            # First import
            r1 = runner.invoke(main, [
                "import-baseline", "测试",
                "--chapter", "v01.c01",
                "--file", str(chapter_file),
            ])
            assert r1.exit_code == 0, f"First import failed: {r1.output}"

            # Count shots after first import
            db = open_db(db_path)
            count1 = db.execute(
                "SELECT COUNT(*) as cnt FROM writing_shots WHERE project_id = "
                "(SELECT project_id FROM projects WHERE name = '测试')"
            ).fetchone()["cnt"]
            db.close()

            # Second import (should be idempotent)
            r2 = runner.invoke(main, [
                "import-baseline", "测试",
                "--chapter", "v01.c01",
                "--file", str(chapter_file),
            ])
            assert r2.exit_code == 0, f"Second import failed: {r2.output}"

            # Count shots after second import — should be same
            db = open_db(db_path)
            count2 = db.execute(
                "SELECT COUNT(*) as cnt FROM writing_shots WHERE project_id = "
                "(SELECT project_id FROM projects WHERE name = '测试')"
            ).fetchone()["cnt"]
            db.close()

        assert count1 == count2, f"Import not idempotent: {count1} → {count2}"


# ═══════════════════════════════════════════════════════
# T4: End-to-end pipeline integration test
# ═══════════════════════════════════════════════════════


class TestPipelineE2E:
    """T4: Full pipeline: meta-contract → compile → dispatch → jury → gate → finalize"""

    def test_full_pipeline_one_shot(self, setup_run):
        """E2E test for a single shot through the full pipeline."""
        from inkflow.services import (
            ContractCompiler, WriterDispatcher, JuryService, QualityController,
        )

        db = setup_run
        project_id = "proj_01"
        run_id = "run_01"

        # Insert a separate E2E shot (setup_run already has shot_01 with a contract)
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('shot_e2e', 'proj_01', 'run_01', 'v01.c02', 2, 'pending')"
        )
        # Remove fixture's pre-existing contract so get_meta_contract() returns ours
        db.execute("DELETE FROM writing_meta_contract WHERE meta_contract_id = 'mc1'")
        db.commit()

        # 1. Create meta-contract
        compiler = ContractCompiler(db, project_id)
        mc_data = {
            "identity": {"title": "分流", "genre": "文学小说"},
            "narrative_voice": {"pov": "多POV"},
            "hard_boundaries": {},
            "anti_reveal": {},
            "world_knowledge": {},
            "structure_rules": {},
            "anti_patterns": {},
            "style_locks": {},
            "motif_system": {},
            "creative_zones": {},
        }
        mc_id = compiler.create_meta_contract(mc_data)
        compiler.confirm_contract(mc_id)
        assert compiler.is_contract_confirmed()

        # 2. Compile shot contracts
        contract = compiler.get_meta_contract()
        shots = [{"shot_id": "shot_e2e", "shot_index": 2, "layer_key": "v01.c02"}]
        cids = compiler.compile_shot_contracts(run_id, shots, contract["layers_json"])
        assert len(cids) == 1
        compiler.lock_shot_contracts(run_id)

        # 3. Create drafts (simulate writer race output)
        db.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_e2e_1', 'shot_e2e', 'run_01', '意象师', 0, ?, 'att_e2e_1')",
            ("右腿膝盖里像有把生锈的螺丝刀一圈圈往里拧。阿坤醒了。不是被闹钟叫醒的。窗外的天还是灰的。成都十二月的那种灰。他从枕头下面摸出保鲜膜。",)
        )
        db.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_e2e_2', 'shot_e2e', 'run_01', '节奏师', 1, ?, 'att_e2e_2')",
            ("螺丝刀在膝盖里面转了一圈。疼痛把他从梦里拽出来。窗帘没拉严。灰光照在皱巴巴的床单上。他从枕头下面摸出保鲜膜，紧紧缠住膝盖。",)
        )
        db.commit()

        # 4. Gate 1
        qc = QualityController(db, run_id)
        passed = qc.gate1_check("shot_e2e", ["d_e2e_1", "d_e2e_2"])
        assert len(passed) == 2

        # 5. Jury scoring
        jury = JuryService(db, run_id, {})
        verdict = jury.score_candidates("shot_e2e", passed)
        assert verdict["winner_draft_id"] is not None
        assert "winner_score" in verdict

        # 6. Gate 2
        gate2 = qc.gate2_check("shot_e2e", verdict["winner_draft_id"], verdict)
        assert "passed" in gate2
        assert "light_status" in gate2

        # 7. Finalize
        final_status = qc.finalize_shot("shot_e2e", verdict["winner_draft_id"], gate2)
        assert final_status in (
            ShotStatus.DONE_GREEN,
            ShotStatus.DONE_YELLOW,
            ShotStatus.PLACEHOLDER,
        )

    def test_yellow_status_preserved(self, setup_run):
        """B16: Yellow winner should NOT be overwritten to done_green."""
        from inkflow.services import JuryService, QualityController

        db = setup_run
        # Insert a draft for the shot
        db.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_yel', 'shot_01', 'run_01', '意象师', 0, 'test text for yellow', 'att_yel')"
        )
        db.commit()

        jury = JuryService(db, "run_01", {})
        # Force yellow verdict (score 75 → 65 <= 75 < 85)
        verdict = jury.score_candidates("shot_01", ["d_yel"], score_override=75)
        assert verdict["light_status"] == "yellow"

        qc = QualityController(db, "run_01")
        gate2 = qc.gate2_check("shot_01", "d_yel", verdict)
        final_status = qc.finalize_shot("shot_01", "d_yel", gate2)

        # The shot should be done_yellow, NOT done_green
        assert final_status == ShotStatus.DONE_YELLOW

        # Verify DB state
        row = db.execute(
            "SELECT shot_status, light_status FROM writing_shots WHERE shot_id = 'shot_01'"
        ).fetchone()
        assert row["shot_status"] == "done_yellow"
        assert row["light_status"] == "yellow"
