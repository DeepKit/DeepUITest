"""Tests for ArchitectGate — 4-level cascading quality gate."""

from __future__ import annotations

import json
import pytest


GOOD_L4_TEXT = (
    "雨水从窗缝挤进来，沿着柜台边缘慢慢聚成一滴。"
    "韩教授把旧纸袋压在灯下，纸角还在发潮。"
    "阿坤没有问，他听见走廊尽头的门轴响了一下。"
    "灯管闪了两次，白光落在他膝盖上。"
    "他伸手去够那张票根，指尖还没碰到纸面，门外的铃突然响了"
)


class TestArchitectGateL4:
    """L4: Shot-level gate tests."""

    @pytest.fixture
    def setup_l4(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate

        db = setup_run
        run_id = "run_01"
        project_id = "proj_01"
        db.execute(
            "INSERT INTO writing_drafts "
            "(draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_01', 'shot_01', 'run_01', '结构师', 0, ?, 'att_l4')",
            (GOOD_L4_TEXT,),
        )
        db.commit()

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

    def test_l4_rejects_deprecated_character_alias(self, setup_l4):
        db, gate, run_id = setup_l4
        layers = {
            "identity": {"pov_characters": ["郑坤", "白英", "苏然", "韩教授"]},
            "hard_boundaries": {"characters_alive": ["郑坤", "白英", "苏然", "韩教授"]},
        }
        db.execute(
            "UPDATE writing_meta_contract SET layers_json = ? "
            "WHERE meta_contract_id = 'mc1'",
            (json.dumps(layers, ensure_ascii=False),),
        )
        db.execute(
            "UPDATE writing_drafts SET text = ? WHERE draft_id = 'd_01'",
            (
                "雨落在玻璃上，阿坤把手机扣在掌心。"
                "他听见订单提示音从袖口里闷闷地响起来，膝盖先停了一下。",
            ),
        )
        db.commit()

        result = gate.evaluate_l4(
            "shot_01", "d_01",
            {"passed": True, "score": 90, "light_status": "green"},
        )

        assert result["passed"] is False
        assert any("character_name" in issue for issue in result["hard_issues"])

    def test_l4_rejects_unanchored_medical_fact_expansion(self, setup_l4):
        db, gate, run_id = setup_l4
        text = (
            "雨声压在窗上，郑坤把诊断单折成四折塞进工牌后面。"
            "阿姨问他还跑不跑，他没有答，只把膝盖往桌腿后面收了收。"
            "他上周请了半天假去社区医院拍了片子，诊断意见写着髌骨软化。"
        )
        db.execute(
            "UPDATE writing_drafts SET text = ? WHERE draft_id = 'd_01'",
            (text,),
        )
        db.commit()

        result = gate.evaluate_l4(
            "shot_01", "d_01",
            {"passed": True, "score": 90, "light_status": "green"},
        )

        assert result["passed"] is False
        assert any("unanchored_fact" in issue for issue in result["hard_issues"])


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
        db.execute(
            "INSERT OR IGNORE INTO writing_drafts "
            "(draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_01', 'shot_l3_10', ?, '结构师', 0, ?, 'att_l3')",
            (run_id, GOOD_L4_TEXT),
        )
        db.commit()

    def _create_chapter_with_revisions(self, db, chapter_key, run_id, project_id, texts):
        """Create a clean chapter run with current revisions for hook tests."""
        db.execute(
            "INSERT OR IGNORE INTO writing_sessions "
            "(session_id, project_id, run_id, status) VALUES (?, ?, ?, 'active')",
            (f"s_{run_id}", project_id, run_id),
        )
        for i, text in enumerate(texts, start=1):
            shot_id = f"{run_id}_shot_{i}"
            contract_id = f"{run_id}_contract_{i}"
            revision_id = f"{run_id}_revision_{i}"
            db.execute(
                "INSERT INTO writing_shots "
                "(shot_id, project_id, run_id, layer_key, shot_index, "
                "shot_status, light_status) "
                "VALUES (?, ?, ?, ?, ?, 'done_green', 'green')",
                (shot_id, project_id, run_id, chapter_key, i),
            )
            db.execute(
                "INSERT INTO writing_shot_contracts "
                "(contract_id, project_id, run_id, shot_id, layer_key, "
                "contract_status, snapshot_hash, must_land_json, anti_write_json, "
                "pov_routing_json, contract_json) "
                "VALUES (?, ?, ?, ?, ?, 'locked', 'h', '{}', '{}', ?, '{}')",
                (
                    contract_id,
                    project_id,
                    run_id,
                    shot_id,
                    chapter_key,
                    json.dumps({"pov_character": ["阿坤", "韩教授", "苏然"][i % 3]}),
                ),
            )
            db.execute(
                "INSERT INTO shot_revisions "
                "(revision_id, shot_id, run_id, contract_id, revision_sequence, "
                "operation, text, text_hash_normalized, is_current, attempt_id) "
                "VALUES (?, ?, ?, ?, 1, 'write_generate', ?, ?, 1, ?)",
                (
                    revision_id,
                    shot_id,
                    run_id,
                    contract_id,
                    text,
                    f"hash_{i}",
                    f"attempt_{i}",
                ),
            )
            db.execute(
                "UPDATE writing_shots SET current_revision_id = ? WHERE shot_id = ?",
                (revision_id, shot_id),
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
        run_id = "run_l3_twice"
        gate = ArchitectGate(db, run_id, "proj_01")

        texts = [
            "阿坤把湿透的票根摊在柜台上，水沿着玻璃边缘慢慢往下走。韩教授没有解释，只让他把手按住。",
            "苏然翻过临时边界单，琉璃场三个字被红笔圈住，纸角还沾着雨水。",
            "阿坤收起那张纸，柜台里的灯一盏盏灭下去。外面雨声压住了排号屏的提示音，"
            "他听见自己袖口还在滴水。他正要把湿冷的塑料袋塞进柜台，门外的铃突然响了",
        ]
        self._create_chapter_with_revisions(db, chapter, run_id, "proj_01", texts)
        db.execute(
            "INSERT INTO writing_drafts "
            "(draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d_l3_twice', ?, ?, '结构师', 0, ?, 'att_l3_twice')",
            (f"{run_id}_shot_1", run_id, GOOD_L4_TEXT),
        )
        db.commit()
        for i in range(1, 4):
            gate.evaluate_l4(
                f"{run_id}_shot_{i}", "d_l3_twice",
                {"passed": True, "score": 88, "light_status": "green"},
            )

        result = gate.evaluate_l3(chapter)
        assert result["passed"] is True
        assert gate.should_trigger_l3(chapter) is False

    def test_failed_l3_can_be_retriggered_after_repair(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        chapter = "v01.c14"
        gate = ArchitectGate(db, "run_01", "proj_01")

        self._create_chapter_shots(db, chapter, "run_01", "proj_01", ["green"] * 4)
        for i in range(10, 14):
            gate.evaluate_l4(
                f"shot_l3_{i}", "d_01",
                {"passed": True, "score": 88, "light_status": "green"},
            )

        failed = gate.evaluate_l3(chapter)
        assert failed["passed"] is False
        assert gate.should_trigger_l3(chapter) is True

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

    def test_l3_passes_but_warns_when_chapter_hook_is_closed(self, setup_run):
        """B79: chapter_hook_weak is now a non-blocking warning, not a hard failure."""
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        chapter = "v01.c07"
        run_id = "run_hook_closed"
        gate = ArchitectGate(db, run_id, "proj_01")
        texts = [
            "阿坤把湿透的票根摊在柜台上，水沿着玻璃边缘慢慢往下走。韩教授没有解释，只让他把手按住。",
            "苏然翻过临时边界单，琉璃场三个字被红笔圈住，纸角还沾着雨水。",
            "阿坤收起那张纸，柜台里的灯一盏盏灭下去。所以这件事终于结束了。",
        ]
        self._create_chapter_with_revisions(db, chapter, run_id, "proj_01", texts)

        result = gate.evaluate_l3(chapter)

        # B79: chapter_hook_weak is now non-blocking warning
        assert result["passed"] is True
        assert result["chapter_hook"]["passed"] is False

    def test_l3_passes_when_chapter_hook_is_unfinished_action(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        chapter = "v01.c08"
        run_id = "run_hook_open"
        gate = ArchitectGate(db, run_id, "proj_01")
        texts = [
            "阿坤把湿透的票根摊在柜台上，水沿着玻璃边缘慢慢往下走。韩教授没有解释，只让他把手按住。",
            "苏然翻过临时边界单，琉璃场三个字被红笔圈住，纸角还沾着雨水。",
            "阿坤收起那张纸，柜台里的灯一盏盏灭下去。外面雨声压住了排号屏的提示音，"
            "他听见自己袖口还在滴水。他正要把湿冷的塑料袋塞进柜台，门外的铃突然响了",
        ]
        self._create_chapter_with_revisions(db, chapter, run_id, "proj_01", texts)

        result = gate.evaluate_l3(chapter)

        assert result["passed"] is True
        assert result["chapter_hook"]["passed"] is True
        assert result["chapter_hook"]["hook_quality"] == "excellent"

    def test_l3_fails_titled_hook_that_is_too_thin(self, setup_run):
        from inkflow.services.architect_gate import ArchitectGate
        db = setup_run
        chapter = "v01.c09"
        run_id = "run_thin_hook"
        gate = ArchitectGate(db, run_id, "proj_01")
        texts = [
            "郑坤把雨水甩在门外，湿气贴着裤腿往上爬。他没有立刻进去，只看着墙上的排班表。"
            "表格边角翘起，像一片被泡软的纸。门里有人喊他的名字，他正要回答，屏幕忽然亮了",
            "电话响了。韩教授看着骨片，给小林发了一句：明天再筛一遍。轮子从门外碾过去，吱呀响。",
        ]
        self._create_chapter_with_revisions(db, chapter, run_id, "proj_01", texts)
        db.execute(
            "UPDATE writing_shot_contracts SET must_land_json = ? "
            "WHERE run_id = ? AND shot_id = ?",
            (json.dumps({"title": "慢下来"}, ensure_ascii=False), run_id, f"{run_id}_shot_2"),
        )
        db.commit()

        result = gate.evaluate_l3(chapter)

        assert result["passed"] is False
        assert result["shot_density"]["passed"] is False
        assert any("shot_too_thin" in issue for issue in result["issues"])


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
