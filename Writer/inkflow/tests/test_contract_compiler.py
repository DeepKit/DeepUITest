"""Test Contract Compiler (Service 1)."""

from __future__ import annotations

import json
import pytest
from inkflow.services.contract_compiler import ContractCompiler
from inkflow.models.enums import ContractStatus


SAMPLE_META_CONTRACT = {
    "identity": {"title": "分流", "genre": "文学小说"},
    "narrative_voice": {"pov": "多POV", "tone": "冷峻"},
    "hard_boundaries": {"no_deus_ex_machina": True},
    "anti_reveal": {"白英的秘密": "第三章前不揭示"},
    "world_knowledge": {"setting": "成都", "era": "当代"},
    "structure_rules": {"chapter_length": "4000-6000字"},
    "anti_patterns": {"academic_tone": True},
    "style_locks": {"sensory_density": "high"},
    "motif_system": {"膝盖": "反复出现的身体意象"},
    "creative_zones": {"对话": "自由发挥"},
}


@pytest.fixture
def compiler(db):
    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    db.commit()
    return ContractCompiler(db, "proj_01")


class TestMetaContract:
    def test_create_meta_contract(self, compiler):
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        assert len(mc_id) == 26

        contract = compiler.get_meta_contract()
        assert contract is not None
        assert contract["status"] == "draft"
        layers = contract["layers_json"]
        assert layers["identity"]["title"] == "分流"

    def test_structured_identity_accepts_legacy_genre(self, compiler):
        contract_data = json.loads(json.dumps(SAMPLE_META_CONTRACT, ensure_ascii=False))
        contract_data["identity"].update({
            "author": "测试作者",
            "era": "当代",
            "total_chapters": 10,
        })
        mc_id = compiler.create_meta_contract(contract_data)

        compiler.write_meta_contract_structured(mc_id, contract_data)

        row = compiler.db.execute(
            "SELECT genre_tags FROM writing_project_identity WHERE project_id = ?",
            ("proj_01",),
        ).fetchone()
        assert json.loads(row["genre_tags"]) == ["文学小说"]

    def test_structured_write_accepts_chapter_hooks_list(self, compiler):
        contract_data = json.loads(json.dumps(SAMPLE_META_CONTRACT, ensure_ascii=False))
        contract_data["identity"].update({
            "author": "测试作者",
            "era": "当代",
            "total_chapters": 10,
        })
        contract_data["suspense_blueprint"] = {
            "preset": "literary_tension",
            "global_question": "谁会承担下一次代价？",
        }
        contract_data["suspense_config"] = {
            "chapter_hooks": ["每章最后一句必须留下未完成动作。"],
        }
        contract_data["structure_rules"] = {
            "chapter_2_events": [{"pov": "角色A", "event": "事件一"}],
        }
        mc_id = compiler.create_meta_contract(contract_data)

        compiler.write_meta_contract_structured(mc_id, contract_data)

        row = compiler.db.execute(
            "SELECT COUNT(*) AS cnt FROM writing_chapter_tension_arc"
        ).fetchone()
        assert row["cnt"] == 1

    def test_schema_validation_allows_future_pov_in_partial_outline(self, compiler):
        contract_data = {
            "identity": {
                "title": "测试",
                "author": "测试作者",
                "era": "当代",
                "total_chapters": 66,
                "pov_characters": ["第一代A", "第一代B", "未来角色"],
            },
            "narrative_voice": {},
            "style_locks": {},
            "suspense_blueprint": {},
            "structure_rules": {
                "chapter_2_events": [
                    {"pov": "第一代A", "event": "事件一"},
                    {"pov": "第一代B", "event": "事件二"},
                ],
            },
        }

        assert compiler.validate_contract_schema(contract_data) == []

    def test_schema_validation_rejects_undeclared_shot_pov(self, compiler):
        contract_data = {
            "identity": {
                "title": "测试",
                "author": "测试作者",
                "era": "当代",
                "total_chapters": 3,
                "pov_characters": ["角色A"],
            },
            "narrative_voice": {},
            "style_locks": {},
            "suspense_blueprint": {},
            "structure_rules": {
                "chapter_2_events": [
                    {"pov": "未声明角色", "event": "事件一"},
                ],
            },
        }

        errors = compiler.validate_contract_schema(contract_data)
        assert any("未声明角色" in error for error in errors)

    def test_schema_validation_enforces_full_outline_pov_coverage(self, compiler):
        contract_data = {
            "identity": {
                "title": "测试",
                "author": "测试作者",
                "era": "当代",
                "total_chapters": 3,
                "pov_characters": ["角色A", "角色B", "缺席角色"],
            },
            "narrative_voice": {},
            "style_locks": {},
            "suspense_blueprint": {},
            "structure_rules": {
                "chapter_2_events": [
                    {"pov": "角色A", "event": "事件一"},
                ],
                "chapter_3_events": [
                    {"pov": "角色B", "event": "事件二"},
                ],
            },
        }

        errors = compiler.validate_contract_schema(contract_data)
        assert any("缺席角色" in error for error in errors)

    def test_update_status(self, compiler):
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        compiler.confirm_contract(mc_id)
        assert compiler.is_contract_confirmed()

    def test_lock_contract(self, compiler):
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        compiler.confirm_contract(mc_id)
        compiler.lock_contract(mc_id)

        contract = compiler.get_meta_contract()
        assert contract["status"] == "locked"

    def test_is_contract_confirmed_false(self, compiler):
        assert not compiler.is_contract_confirmed()
        compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        assert not compiler.is_contract_confirmed()

    def test_record_revision(self, compiler):
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        before = SAMPLE_META_CONTRACT.copy()
        after = SAMPLE_META_CONTRACT.copy()
        after["style_locks"] = {"sensory_density": "medium"}

        reason = "人类审核后调整感官密度，从high改为medium以适应第2章的城市场景描写，同时需要保持文学质感和叙事节奏"
        rev_id = compiler.record_revision(mc_id, "human", reason, before, after)
        assert len(rev_id) == 26

    def test_record_revision_reason_too_short(self, compiler):
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        with pytest.raises(Exception):  # CHECK constraint
            compiler.record_revision(mc_id, "human", "太短", {}, {})


class TestShotContracts:
    def _setup_session_and_shots(self, db):
        """Create session + shot records needed for shot contracts."""
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'proj_01', 'run_01', 'active')"
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('s1', 'proj_01', 'run_01', 'v01.c02', 1, 'pending')"
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('s2', 'proj_01', 'run_01', 'v01.c02', 2, 'pending')"
        )
        db.commit()

    def test_compile_shot_contracts(self, compiler):
        self._setup_session_and_shots(compiler.db)
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        contract = compiler.get_meta_contract()

        shots = [
            {"shot_id": "s1", "shot_index": 1, "layer_key": "v01.c02"},
            {"shot_id": "s2", "shot_index": 2, "layer_key": "v01.c02"},
        ]
        contract_ids = compiler.compile_shot_contracts("run_01", shots, contract["layers_json"])
        assert len(contract_ids) == 2

    def test_compile_shot_contracts_writes_scene_contract(self, compiler):
        self._setup_session_and_shots(compiler.db)
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        contract = compiler.get_meta_contract()

        shots = [{
            "shot_id": "s1",
            "shot_index": 1,
            "layer_key": "v01.c02",
            "must_land": {
                "title": "常规运输条件下的密封",
                "beats": "前线露天堆场出现微裂纹，批号无法确认。",
            },
            "scene_contract": {
                "scene_id": "v01.c02.scene.01",
                "location": "前线露天堆场",
                "time_position": "雨停后三天",
                "required_anchors": ["露天", "微裂纹", "批号"],
                "forbidden_overlap": ["转运站月台"],
                "information_delta": "密封件出现异常且批号追踪断裂",
                "min_utf8_bytes": 1200,
            },
        }]
        cids = compiler.compile_shot_contracts("run_01", shots, contract["layers_json"])

        row = compiler.db.execute(
            "SELECT location, required_anchors, forbidden_overlap "
            "FROM writing_shot_scene_contracts WHERE contract_id = ?",
            (cids[0],),
        ).fetchone()
        assert row["location"] == "前线露天堆场"
        assert "微裂纹" in row["required_anchors"]
        assert "转运站月台" in row["forbidden_overlap"]

    def test_compile_shot_contracts_writes_scene_fingerprint(self, compiler):
        """compile_shot_contracts 同时写 writing_shot_scene_fingerprints。"""
        self._setup_session_and_shots(compiler.db)
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        contract = compiler.get_meta_contract()

        shots = [{
            "shot_id": "s1",
            "shot_index": 1,
            "layer_key": "v01.c02",
            "must_land": {
                "title": "常规运输条件下的密封",
                "beats": "前线露天堆场出现微裂纹，批号无法确认。",
            },
            "scene_contract": {
                "scene_id": "v01.c02.scene.01",
                "location": "前线露天堆场",
                "time_position": "雨停后三天",
                "required_anchors": ["露天", "微裂纹", "批号"],
                "entry_object": "微裂纹",
                "forbidden_overlap": ["转运站月台"],
                "min_utf8_bytes": 1200,
                "fingerprint": {
                    "scene_bucket": "前线露天堆场",
                    "time_jump": "雨停后三天",
                    "key_objects": ["微裂纹", "露天", "批号"],
                    "event_anchors": ["露天", "微裂纹", "批号"],
                    "similarity_hash": "abc123def4",
                    "source": "explicit",
                },
            },
        }]
        cids = compiler.compile_shot_contracts("run_01", shots, contract["layers_json"])

        row = compiler.db.execute(
            "SELECT scene_bucket, event_anchors, source, time_jump, similarity_hash "
            "FROM writing_shot_scene_fingerprints WHERE contract_id = ?",
            (cids[0],),
        ).fetchone()
        assert row is not None
        assert row["scene_bucket"] == "前线露天堆场"
        assert json.loads(row["event_anchors"]) == ["露天", "微裂纹", "批号"]
        assert row["source"] == "explicit"
        assert row["time_jump"] == "雨停后三天"

    def test_compile_shot_contracts_writes_fingerprint_when_missing(self, compiler):
        """scene_contract 未带 fingerprint 时，_write_scene_fingerprint 现场计算。"""
        self._setup_session_and_shots(compiler.db)
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        contract = compiler.get_meta_contract()

        shots = [{
            "shot_id": "s1",
            "shot_index": 1,
            "layer_key": "v01.c02",
            "must_land": {"title": "t", "beats": "b"},
            "scene_contract": {
                "scene_id": "v01.c02.scene.01",
                "location": "转运站月台",
                "required_anchors": ["军列"],
                "entry_object": "军列",
                "min_utf8_bytes": 1200,
            },
        }]
        cids = compiler.compile_shot_contracts("run_01", shots, contract["layers_json"])

        row = compiler.db.execute(
            "SELECT scene_bucket, source FROM writing_shot_scene_fingerprints "
            "WHERE contract_id = ?",
            (cids[0],),
        ).fetchone()
        assert row is not None
        assert row["scene_bucket"] == "转运站月台"
        assert row["source"] == "explicit"

    def test_get_shot_contract(self, compiler):
        self._setup_session_and_shots(compiler.db)
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        contract = compiler.get_meta_contract()

        shots = [{"shot_id": "s1", "shot_index": 1, "layer_key": "v01.c02"}]
        cids = compiler.compile_shot_contracts("run_01", shots, contract["layers_json"])

        sc = compiler.get_shot_contract("s1", "run_01")
        assert sc is not None
        assert sc["contract_status"] == "draft"

    def test_lock_shot_contracts(self, compiler):
        self._setup_session_and_shots(compiler.db)
        mc_id = compiler.create_meta_contract(SAMPLE_META_CONTRACT)
        contract = compiler.get_meta_contract()

        shots = [{"shot_id": "s1", "shot_index": 1, "layer_key": "v01.c02"}]
        compiler.compile_shot_contracts("run_01", shots, contract["layers_json"])
        compiler.lock_shot_contracts("run_01")

        sc = compiler.get_shot_contract("s1", "run_01")
        assert sc["contract_status"] == "locked"
