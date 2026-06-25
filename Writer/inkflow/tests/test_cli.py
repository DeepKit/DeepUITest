"""Test CLI commands."""

from __future__ import annotations

import pytest
from click.testing import CliRunner
from pathlib import Path

from inkflow.cli import main, _extract_chapter_2_events, _extract_chapter_events
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
        assert "setup" in result.output
        assert "run" in result.output

    def test_version(self, runner):
        result = runner.invoke(main, ["--version"])
        assert result.exit_code == 0
        assert "3.6.0" in result.output


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


class TestSetupSmoke:
    """M5: setup command smoke test"""

    def test_setup_creates_contract_draft(self, runner, sample_project, tmp_dir):
        """setup should create contract-draft.yaml"""
        import unittest.mock as mock
        import inkflow.cli as cli

        story_dir = tmp_dir / "_Story" / "《测试》"
        db_path = story_dir / ".inkflow" / "inkflow.db"
        draft_path = story_dir / ".inkflow" / "contract-draft.yaml"
        with mock.patch.object(cli, "_resolve_project_db", return_value=str(db_path)), \
             mock.patch.object(cli, "_STORY_BASE", tmp_dir / "_Story"):
            result = runner.invoke(main, ["setup", "测试"])
            assert result.exit_code == 0, result.output
            assert draft_path.exists(), "contract-draft.yaml should be created"


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
            # Run setup first
            result = runner.invoke(main, ["setup", "测试"])
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
            runner.invoke(main, ["setup", "测试"])

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
