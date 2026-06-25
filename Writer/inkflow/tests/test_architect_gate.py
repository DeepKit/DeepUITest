"""Tests for ArchitectGate — 4-level cascading quality gate."""

from __future__ import annotations

import json
import pytest


class TestArchitectGateL4:
    """L4: Shot-level gate tests."""

    @pytest.fixture
    def setup_l4(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate

        db = setup_run
        run_id = "run_01"
        project_id = "proj_01"

        gate = ArchitectGate(db, run_id, project_id)
        return db, gate, run_id

    def test_l4_green_passes(self, setup_l4):
        db, gate, run_id = setup_l4
        gate2 = {"passed": True, "score": 90, "light_status": "green"}
        result = gate.evaluate_l4("shot_01", "d_01", gate2)
        assert result["passed"] is True
        assert result["light_status"] == "green"

    def test_l4_red_fails(self, setup_l4):
        db, gate, run_id = setup_l4
        gate2 = {"passed": False, "score": 50, "light_status": "red"}
        result = gate.evaluate_l4("shot_01", "d_01", gate2)
        assert result["passed"] is False

    def test_l4_records_in_db(self, setup_l4):
        db, gate, run_id = setup_l4
        gate2 = {"passed": True, "score": 88, "light_status": "green"}
        gate.evaluate_l4("shot_01", "d_01", gate2)

        row = db.execute(
            "SELECT * FROM writing_architect_gates "
            "WHERE run_id = ? AND level = 'L4' AND scope_key = 'shot_01'",
            (run_id,),
        ).fetchone()
        assert row is not None
        assert row["status"] == "passed"

    def test_l4_idempotent(self, setup_l4):
        db, gate, run_id = setup_l4
        gate2 = {"passed": True, "score": 88, "light_status": "green"}
        gate.evaluate_l4("shot_01", "d_01", gate2)
        gate.evaluate_l4("shot_01", "d_01", gate2)  # overwrite

        count = db.execute(
            "SELECT COUNT(*) as cnt FROM writing_architect_gates "
            "WHERE run_id = ? AND level = 'L4' AND scope_key = 'shot_01'",
            (run_id,),
        ).fetchone()["cnt"]
        assert count == 1


class TestArchitectGateL3:
    """L3: Chapter-level gate tests."""

    def _create_chapter_shots(self, db, chapter_key, run_id, project_id, light_statuses):
        """Create shots for a chapter with given light_statuses."""
        for i, status in enumerate(light_statuses, start=10):
            shot_id = f"shot_l3_{i}"
            db.execute(
                "INSERT OR IGNORE INTO writing_shots "
                "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, light_status) "
                "VALUES (?, ?, ?, ?, ?, 'done_green', ?)",
                (shot_id, project_id, run_id, chapter_key, i, status),
            )
            contract_id = f"c_l3_{i}"
            pov_char = ["阿坤", "韩教授", "白英", "苏然"][i % 4]
            db.execute(
                "INSERT OR IGNORE INTO writing_shot_contracts "
                "(contract_id, project_id, run_id, shot_id, layer_key, "
                "contract_status, snapshot_hash, must_land_json, anti_write_json, "
                "pov_routing_json, contract_json) "
                "VALUES (?, ?, ?, ?, ?, 'locked', 'h', '{}', '{}', ?, '{}')",
                (contract_id, project_id, run_id, shot_id, chapter_key,
                 json.dumps({"pov_character": pov_char})),
            )
        db.commit()

    def test_l3_not_triggered_without_l4(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        gate = ArchitectGate(db, "run_01", "proj_01")
        assert gate.should_trigger_l3("v01.c99") is False

    def test_l3_triggers_when_all_l4_passed(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        chapter = "v01.c03"
        gate = ArchitectGate(db, "run_01", "proj_01")

        self._create_chapter_shots(db, chapter, "run_01", "proj_01", ["green"] * 4)
        for i in range(10, 14):
            gate.evaluate_l4(f"shot_l3_{i}", "d_01", {"passed": True, "score": 88, "light_status": "green"})

        assert gate.should_trigger_l3(chapter) is True

    def test_l3_not_triggered_twice(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        chapter = "v01.c04"
        gate = ArchitectGate(db, "run_01", "proj_01")

        self._create_chapter_shots(db, chapter, "run_01", "proj_01", ["green"] * 4)
        for i in range(10, 14):
            gate.evaluate_l4(f"shot_l3_{i}", "d_01", {"passed": True, "score": 88, "light_status": "green"})

        gate.evaluate_l3(chapter)
        assert gate.should_trigger_l3(chapter) is False

    def test_l3_evaluates_pov_balance(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        chapter = "v01.c05"
        gate = ArchitectGate(db, "run_01", "proj_01")

        self._create_chapter_shots(db, chapter, "run_01", "proj_01", ["green"] * 4)
        for i in range(10, 14):
            gate.evaluate_l4(f"shot_l3_{i}", "d_01", {"passed": True, "score": 88, "light_status": "green"})

        result = gate.evaluate_l3(chapter)
        assert result["shot_count"] == 4
        assert result["green_count"] == 4
        assert result["red_count"] == 0
        assert "阿坤" in result["pov_coverage"]

    def test_l3_detects_mixed_quality(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        chapter = "v01.c06"
        gate = ArchitectGate(db, "run_01", "proj_01")

        statuses = ["green", "green", "yellow", "red"]
        self._create_chapter_shots(db, chapter, "run_01", "proj_01", statuses)
        for i, status in enumerate(statuses, start=10):
            score = {"green": 88, "yellow": 75, "red": 50}[status]
            passed = status != "red"
            gate.evaluate_l4(f"shot_l3_{i}", "d_01", {"passed": passed, "score": score, "light_status": status})

        result = gate.evaluate_l3(chapter)
        assert result["red_count"] == 1
        assert result["yellow_count"] == 1
        assert result["green_count"] == 2
        assert result["passed"] is False
        assert len(result["issues"]) > 0


class TestArchitectGateL2L1:
    """L2/L1: Volume and universe-level gate tests (P1 skeleton)."""

    def test_l2_not_triggered_without_l3(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        gate = ArchitectGate(db, "run_01", "proj_01")
        assert gate.should_trigger_l2("v01") is False

    def test_l1_records_global(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        gate = ArchitectGate(db, "run_01", "proj_01")

        existing = db.execute(
            "SELECT 1 FROM writing_architect_gates "
            "WHERE run_id = 'run_01' AND level = 'L1'"
        ).fetchone()
        assert existing is None

        result = gate.evaluate_l1()
        assert result["passed"] is True
        assert result["scope_key"] == "global"