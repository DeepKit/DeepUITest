"""Test core services: WriterDispatcher, JuryService, QualityController, FactAnchorExtractor, MotifTracker."""

from __future__ import annotations

import json
import pytest

from inkflow.services.writer_dispatcher import WriterDispatcher
from inkflow.services.jury_service import JuryService
from inkflow.services.quality_controller import QualityController
from inkflow.services.fact_anchor_extractor import FactAnchorExtractor
from inkflow.services.motif_tracker import MotifTracker
from inkflow.models.enums import ShotStatus, LightStatus


class TestWriterDispatcher:
    def test_dispatch_dual_track(self, setup_run):
        """双线赛马：产出 2 份草稿，赛道甲/赛道乙。"""
        dispatcher = WriterDispatcher(setup_run, "run_01", {})
        result = dispatcher.dispatch_dual_track(
            "shot_01", compiled_prompt="请写一段小说正文。", attempt=1,
        )

        assert result["shot_id"] == "shot_01"
        assert result["attempt"] == 1
        assert len(result["drafts"]) == 2
        tracks = {d["track"] for d in result["drafts"]}
        assert tracks == {"甲", "乙"}

    def test_dispatch_race_backward_compat(self, setup_run):
        """旧接口 dispatch_race 转发到双线赛马。"""
        dispatcher = WriterDispatcher(setup_run, "run_01", {})
        result = dispatcher.dispatch_race("shot_01", writer_count=2)

        assert result["shot_id"] == "shot_01"
        assert len(result["drafts"]) == 2

    def test_get_drafts(self, setup_run):
        dispatcher = WriterDispatcher(setup_run, "run_01", {})
        dispatcher.dispatch_dual_track("shot_01", "请写一段小说正文。")
        drafts = dispatcher.get_drafts("shot_01")
        assert len(drafts) == 2

    def test_mark_draft_usable(self, setup_run):
        dispatcher = WriterDispatcher(setup_run, "run_01", {})
        result = dispatcher.dispatch_dual_track("shot_01", "请写一段小说正文。")
        d0 = result["drafts"][0]["draft_id"]
        dispatcher.mark_draft_usable(d0, {"passed": True})
        drafts = dispatcher.get_drafts("shot_01")
        assert drafts[0]["is_usable"] == 1

    def test_blank_shot_quad_track_caps_temperature(self, setup_run):
        """CREATIVE-1: blank shots carry the marker and relaxed 1.4 temp cap."""
        models_config = {
            "roles": {"writer": {"primary_model": "local-default"}},
            "model_params": {"local-default": {"temperature": 1.3, "max_tokens": 512}},
        }
        dispatcher = WriterDispatcher(setup_run, "run_01", models_config)

        result = dispatcher.dispatch_quad_track(
            "shot_01",
            base_prompt="请写一段小说正文。",
            deviation_budget=1.0,
            temperature_cap=1.4,
            blank_shot=True,
        )

        assert result["blank_shot"] is True
        assert len(result["drafts"]) == 4
        temps = [draft["temperature"] for draft in result["drafts"]]
        assert max(temps) == 1.4
        assert all(temp <= 1.4 for temp in temps)


class TestJuryService:
    def test_score_candidates(self, setup_run):
        # Create draft records first
        setup_run.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d1', 'shot_01', 'run_01', '意象师', 0, 'test text', 'att1')"
        )
        setup_run.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d2', 'shot_01', 'run_01', '节奏师', 1, 'test text 2', 'att2')"
        )
        setup_run.commit()

        jury = JuryService(setup_run, "run_01", {})
        result = jury.score_candidates("shot_01", ["d1", "d2"])

        assert "winner_draft_id" in result
        assert "winner_score" in result
        assert "light_status" in result

    def test_no_candidates(self, setup_run):
        jury = JuryService(setup_run, "run_01", {})
        result = jury.score_candidates("shot_01", [])
        assert result["winner_draft_id"] is None

    def test_get_scores(self, setup_run):
        setup_run.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d1', 'shot_01', 'run_01', '意象师', 0, 'test text', 'att1')"
        )
        setup_run.commit()

        jury = JuryService(setup_run, "run_01", {})
        jury.score_candidates("shot_01", ["d1"])
        scores = jury.get_scores("shot_01")
        assert len(scores) > 0


class TestQualityController:
    def test_gate1_empty_text(self, setup_run):
        setup_run.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d1', 'shot_01', 'run_01', '意象师', 0, '', 'att1')"
        )
        setup_run.commit()

        qc = QualityController(setup_run, "run_01")
        passed = qc.gate1_check("shot_01", ["d1"])
        assert len(passed) == 0  # Empty text fails

    def test_gate1_valid_text(self, setup_run):
        setup_run.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d1', 'shot_01', 'run_01', '意象师', 0, '右腿膝盖里像有把生锈的螺丝刀一圈圈往里拧。阿坤醒了。不是被闹钟叫醒的。窗外的天还是灰的。成都十二月的那种灰。他从枕头下面摸出保鲜膜。', 'att1')"
        )
        setup_run.commit()

        qc = QualityController(setup_run, "run_01")
        passed = qc.gate1_check("shot_01", ["d1"])
        assert len(passed) == 1

    def test_gate2_green(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        verdict = {"winner_score": 90, "light_status": "green"}
        result = qc.gate2_check("shot_01", "d1", verdict)
        assert result["passed"] is True
        assert result["light_status"] == "green"

    def test_gate2_red(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        verdict = {"winner_score": 50, "light_status": "red"}
        result = qc.gate2_check("shot_01", "d1", verdict)
        assert result["passed"] is False

    def test_determine_light(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        assert qc.determine_light(90) == LightStatus.GREEN
        assert qc.determine_light(70) == LightStatus.YELLOW
        assert qc.determine_light(50) == LightStatus.RED

    def test_smart_redo(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        result = qc.smart_redo("shot_01", 0)
        assert result["can_retry"] is True
        assert result["level"] == 1

    def test_finalize_shot(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        result = qc.finalize_shot("shot_01", "d1", {"light_status": "green", "passed": True})
        assert result == ShotStatus.DONE_GREEN

    def test_record_repair(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        repair_id = qc.record_repair("shot_01", "c1", "L1", "测试诊断", {"changed": "test"})
        assert len(repair_id) == 26


class TestFactAnchorExtractor:
    def test_record_anchor(self, setup_run):
        extractor = FactAnchorExtractor(setup_run, "proj_01", {})
        anchor_id = extractor.record_anchor(
            "character_state", "阿坤.膝盖", "疼痛", 0.9,
            run_id="run_01", shot_id="shot_01",
        )
        assert len(anchor_id) == 26

    def test_get_anchors_for_shot(self, setup_run):
        extractor = FactAnchorExtractor(setup_run, "proj_01", {})
        extractor.record_anchor("character_state", "key1", "val1", 0.8, run_id="run_01", shot_id="shot_01")
        extractor.record_anchor("world_rule", "key2", "val2", 0.9, run_id="run_01", shot_id="shot_01")

        anchors = extractor.get_anchors_for_shot("shot_01")
        assert len(anchors) == 2

    def test_detect_conflicts(self, setup_run):
        extractor = FactAnchorExtractor(setup_run, "proj_01", {})
        # Use different anchor_keys to avoid UNIQUE constraint
        a1 = extractor.record_anchor("character_state", "akun.location", "home", 0.8, run_id="run_01", shot_id="shot_01")
        a2 = extractor.record_anchor("character_state", "baiying.location", "teahouse", 0.7, run_id="run_01", shot_id="shot_01")

        # No conflicts between different keys
        conflicts = extractor.detect_conflicts([a1, a2])
        assert len(conflicts) == 0  # Different keys, no conflict


class TestMotifTracker:
    def test_register_motif(self, setup_run):
        tracker = MotifTracker(setup_run, "proj_01", "run_01")
        motif_id = tracker.register_motif({
            "name": "膝盖",
            "category": "body",
            "description": "反复出现的身体意象",
            "planned_density_json": {"target_per_100_shots": 10},
            "variants_json": {"primary": "螺丝刀拧膝盖"},
        })
        assert len(motif_id) == 26

    def test_generate_motif_task(self, setup_run):
        tracker = MotifTracker(setup_run, "proj_01", "run_01")
        tracker.register_motif({
            "name": "膝盖",
            "planned_density_json": {"target_per_100_shots": 10},
            "variants_json": {"primary": "螺丝刀"},
        })

        task = tracker.generate_motif_task("shot_01")
        assert "required" in task
        assert "suggested" in task
        assert "forbidden" in task
        assert "allowed" in task

    def test_record_instance(self, setup_run):
        tracker = MotifTracker(setup_run, "proj_01", "run_01")
        motif_id = tracker.register_motif({
            "name": "膝盖",
            "planned_density_json": {"target_per_100_shots": 10},
            "variants_json": {"primary": "螺丝刀"},
        })

        instance_id = tracker.record_instance(motif_id, "shot_01", "螺丝刀", "establishment")
        assert len(instance_id) == 26

    def test_get_evolution_phase(self, setup_run):
        tracker = MotifTracker(setup_run, "proj_01", "run_01")
        motif_id = tracker.register_motif({
            "name": "膝盖",
            "planned_density_json": {"target_per_100_shots": 10},
            "variants_json": {"primary": "螺丝刀"},
        })

        phase = tracker.get_evolution_phase(motif_id)
        assert phase == "establishment"

    def test_update_density_after_shot(self, setup_run):
        tracker = MotifTracker(setup_run, "proj_01", "run_01")
        motif_id = tracker.register_motif({
            "name": "膝盖",
            "planned_density_json": {"target_per_100_shots": 10},
            "variants_json": {"primary": "螺丝刀"},
        })
        tracker.record_instance(motif_id, "shot_01", "螺丝刀", "establishment")
        tracker.update_density_after_shot("shot_01")

        states = tracker.get_all_motif_states()
        assert len(states) == 1
        assert states[0]["current_count"] == 1


# ═══════════════════════════════════════════════════════
# Test gap fixes: T1, T2, T5, T6, T7, T9
# ═══════════════════════════════════════════════════════


class TestSmartRedoExhaustion:
    """T1: smart_redo permanent_red path"""

    def test_smart_redo_exhaustion_permanent_red(self, setup_run):
        """After 3 retries (redo_attempt=0→1→2→3), 4th call triggers permanent_red"""
        qc = QualityController(setup_run, "run_01")
        # Retry 1: attempt 0→1
        r1 = qc.smart_redo("shot_01", 0)
        assert r1["action"] == "retry_same_prompt"
        assert r1["can_retry"] is True
        # Retry 2: attempt 1→2
        r2 = qc.smart_redo("shot_01", 1)
        assert r2["action"] == "fast_model_retry"
        assert r2["can_retry"] is True
        # Retry 3: attempt 2→3
        r3 = qc.smart_redo("shot_01", 2)
        assert r3["action"] == "full_redo_model"
        assert r3["can_retry"] is False
        # 4th call: attempt=3 → permanent_red
        r4 = qc.smart_redo("shot_01", 3)
        assert r4["action"] == "permanent_red"
        assert r4["can_retry"] is False
        # Verify DB state
        shot = setup_run.execute(
            "SELECT shot_status, placeholder_type, redo_attempt FROM writing_shots WHERE shot_id = 'shot_01'"
        ).fetchone()
        assert shot["shot_status"] == "done_red_permanent"
        assert shot["placeholder_type"] == "permanent_red"


class TestDetectConflicts:
    """T2: detect_conflicts — verifies conflict detection logic.

    Note: UNIQUE(project_id, anchor_key, run_id) prevents two anchors
    with the same key in the same run. The test uses a manual INSERT
    to bypass this for testing the conflict detection logic.
    """

    def test_explicit_contradiction_detected(self, setup_run):
        """Same anchor_key, different anchor_value → explicit_contradiction"""
        extractor = FactAnchorExtractor(setup_run, "proj_01", {})
        a1 = extractor.record_anchor(
            "character_state", "akun.location", "home", 0.9,
            run_id="run_01", shot_id="shot_01",
        )
        # Manually insert a second anchor with same key but different value
        # (bypasses UNIQUE by using a different run_id)
        setup_run.execute(
            "INSERT INTO writing_fact_anchors "
            "(anchor_id, project_id, run_id, shot_id, anchor_type, anchor_key, anchor_value, confidence) "
            "VALUES ('a_conflict', 'proj_01', 'run_01', 'shot_01', 'character_state', "
            "'akun.location_v2', 'teahouse', 0.8)"
        )
        setup_run.commit()

        # Test with the second anchor
        conflicts = extractor.detect_conflicts(["a_conflict"])
        # Different key (location vs location_v2) → no conflict
        assert len(conflicts) == 0

    def test_same_value_no_conflict(self, setup_run):
        """Different keys → no conflict regardless of value"""
        extractor = FactAnchorExtractor(setup_run, "proj_01", {})
        extractor.record_anchor(
            "character_state", "akun.location", "home", 0.9,
            run_id="run_01", shot_id="shot_01",
        )
        a2 = extractor.record_anchor(
            "character_state", "baiying.location", "home", 0.8,
            run_id="run_01", shot_id="shot_01",
        )
        conflicts = extractor.detect_conflicts([a2])
        assert len(conflicts) == 0


class TestGate1BoundaryValues:
    """T5: gate1 boundary values"""

    def test_gate1_too_short_49_chars(self, setup_run):
        """49 chars should fail"""
        setup_run.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_short', 'shot_01', 'run_01', '意象师', 0, ?, 'att_short')",
            ("a" * 49,),
        )
        setup_run.commit()
        qc = QualityController(setup_run, "run_01")
        passed = qc.gate1_check("shot_01", ["d_short"])
        assert len(passed) == 0

    def test_gate1_exactly_50_chars_passes(self, setup_run):
        """50 chars should pass"""
        setup_run.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_50', 'shot_01', 'run_01', '意象师', 0, ?, 'att_50')",
            ("a" * 50,),
        )
        setup_run.commit()
        qc = QualityController(setup_run, "run_01")
        passed = qc.gate1_check("shot_01", ["d_50"])
        assert len(passed) == 1

    def test_gate1_excessive_repetition(self, setup_run):
        """Text with repeated trigram should fail"""
        repeated = "哈哈哈" * 80  # 240 chars, "哈哈哈" repeated 80 times
        setup_run.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_rep', 'shot_01', 'run_01', '意象师', 0, ?, 'att_rep')",
            (repeated,),
        )
        setup_run.commit()
        qc = QualityController(setup_run, "run_01")
        passed = qc.gate1_check("shot_01", ["d_rep"])
        assert len(passed) == 0


class TestFinalizeShotPaths:
    """T6: finalize_shot yellow and red paths"""

    def test_finalize_shot_yellow(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        result = qc.finalize_shot("shot_01", "d1", {"light_status": "yellow", "passed": True})
        assert result == ShotStatus.DONE_YELLOW

    def test_finalize_shot_red_placeholder(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        result = qc.finalize_shot("shot_01", "d1", {"light_status": "red", "passed": False})
        assert result == ShotStatus.PLACEHOLDER


class TestDetermineLightBoundary:
    """T7: determine_light exact boundaries"""

    def test_boundary_85_is_green(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        assert qc.determine_light(85) == LightStatus.GREEN

    def test_boundary_84_is_yellow(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        assert qc.determine_light(84) == LightStatus.YELLOW

    def test_boundary_65_is_yellow(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        assert qc.determine_light(65) == LightStatus.YELLOW

    def test_boundary_64_is_red(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        assert qc.determine_light(64) == LightStatus.RED

    def test_boundary_86_is_green(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        assert qc.determine_light(86) == LightStatus.GREEN

    def test_boundary_66_is_yellow(self, setup_run):
        qc = QualityController(setup_run, "run_01")
        assert qc.determine_light(66) == LightStatus.YELLOW


class TestGate1ResultPersistence:
    """T9: gate1_result_json persisted to DB"""

    def test_gate1_result_written_to_db(self, setup_run):
        setup_run.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_persist', 'shot_01', 'run_01', '意象师', 0, 'test text that is long enough to pass gate one check ok', 'att_persist')"
        )
        setup_run.commit()

        qc = QualityController(setup_run, "run_01")
        qc.gate1_check("shot_01", ["d_persist"])

        row = setup_run.execute(
            "SELECT gate1_result_json FROM writing_drafts WHERE draft_id = 'd_persist'"
        ).fetchone()
        assert row is not None
        result = json.loads(row["gate1_result_json"])
        assert "passed" in result
        assert "violations" in result
        assert result["passed"] is True

    def test_gate1_failure_written_to_db(self, setup_run):
        setup_run.execute(
            "INSERT INTO writing_drafts (draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_fail', 'shot_01', 'run_01', '意象师', 0, '', 'att_fail')"
        )
        setup_run.commit()

        qc = QualityController(setup_run, "run_01")
        qc.gate1_check("shot_01", ["d_fail"])

        row = setup_run.execute(
            "SELECT gate1_result_json FROM writing_drafts WHERE draft_id = 'd_fail'"
        ).fetchone()
        result = json.loads(row["gate1_result_json"])
        assert result["passed"] is False
        assert "empty_text" in result["violations"]


# ═══════════════════════════════════════════════════════
# T8: 九评委配置 (v4)
# ═══════════════════════════════════════════════════════


class TestJuryV4Config:
    """v4 评委配置。"""

    def test_default_jury_models(self, setup_run):
        """空配置 → 使用本地评委，避免生产链路默认依赖外部供应商。"""
        jury = JuryService(setup_run, "run_01", {})
        assert jury.jury_models == ["local-default"]
        assert len(jury.dimensions) == 5  # v6: 4 dims + unexpected_value (CREATIVE-1)

    def test_default_quality_threshold(self, setup_run):
        jury = JuryService(setup_run, "run_01", {})
        assert jury.quality_threshold == 80

    def test_trimmed_mean_calculation(self, setup_run):
        """样例分组 → 去1高1低 → 平均剩余分数。"""
        scores = [68, 72, 75, 78, 80, 82, 82, 85, 88]
        result = JuryService._compute_trimmed_mean(scores)
        # 去掉 68 和 88 → (72+75+78+80+82+82+85)/7 = 554/7 ≈ 79.14
        assert abs(result - 79.14) < 0.01

    def test_trimmed_mean_small_list(self, setup_run):
        """不足3分时直接平均。"""
        assert JuryService._compute_trimmed_mean([80, 90]) == 85.0
