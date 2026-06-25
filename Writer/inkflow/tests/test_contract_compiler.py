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