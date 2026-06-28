"""Test Session Manager (Service 8)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from inkflow.services.session_manager import SessionManager
from inkflow.models.enums import SessionStatus, ShotStatus


@pytest.fixture
def mgr(db):
    """SessionManager with a project already inserted."""
    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    db.commit()
    return SessionManager(db, "proj_01")


class TestSessionLifecycle:
    """Session CRUD"""

    def test_create_session(self, mgr):
        session_id = mgr.create_session()
        assert session_id
        assert len(session_id) == 26

        session = mgr.get_session(session_id)
        assert session is not None
        assert session["project_id"] == "proj_01"
        assert session["status"] == SessionStatus.ACTIVE
        assert session["run_id"] is not None

    def test_create_session_with_act(self, mgr):
        session_id = mgr.create_session(act_id="v01.c02", total_shots=8)
        session = mgr.get_session(session_id)
        assert session["act_id"] == "v01.c02"
        assert session["total_shots"] == 8

    def test_update_status(self, mgr):
        session_id = mgr.create_session()
        mgr.update_session_status(session_id, SessionStatus.COMPLETED)
        session = mgr.get_session(session_id)
        assert session["status"] == SessionStatus.COMPLETED

    def test_abort_session(self, mgr):
        session_id = mgr.create_session()
        mgr.abort_session(session_id)
        session = mgr.get_session(session_id)
        assert session["status"] == SessionStatus.ABORTED

    def test_list_incomplete(self, mgr):
        s1 = mgr.create_session()
        s2 = mgr.create_session()
        mgr.complete_session(s1)

        incomplete = mgr.list_incomplete_sessions()
        assert len(incomplete) == 1
        assert incomplete[0]["session_id"] == s2

    def test_update_current_shot(self, mgr):
        session_id = mgr.create_session()
        mgr.update_current_shot(session_id, "shot_01")
        session = mgr.get_session(session_id)
        assert session["current_shot_id"] == "shot_01"

    def test_increment_completed_shots(self, mgr):
        session_id = mgr.create_session()
        mgr.increment_completed_shots(session_id)
        mgr.increment_completed_shots(session_id)
        session = mgr.get_session(session_id)
        assert session["completed_shots"] == 2

    def test_mark_crashed(self, mgr):
        session_id = mgr.create_session()
        mgr.mark_crashed(session_id)
        session = mgr.get_session(session_id)
        assert session["status"] == SessionStatus.CRASHED

    def test_failure_summary_groups_signatures_and_failed_gates(self, mgr):
        session_id = mgr.create_session(act_id="v01.c02", total_shots=2)
        session = mgr.get_session(session_id)
        shot_ids = mgr.create_shots(
            session["run_id"],
            [
                {"layer_key": "v01.c02", "shot_index": 1},
                {"layer_key": "v01.c02", "shot_index": 2},
            ],
        )
        mgr.db.execute(
            "UPDATE writing_shots SET failure_signature_json = ? WHERE shot_id = ?",
            (
                json.dumps(
                    {
                        "last_failure_type": "chapter_hook_weak",
                        "consecutive_count": 1,
                        "detail": "final shot closed",
                    },
                    ensure_ascii=False,
                ),
                shot_ids[1],
            ),
        )
        mgr.db.execute(
            "INSERT INTO writing_architect_gates "
            "(gate_id, run_id, level, scope_key, status, check_result_json) "
            "VALUES ('gate_failed_l3', ?, 'L3', 'v01.c02', 'failed', '{}')",
            (session["run_id"],),
        )
        mgr.db.commit()

        summary = mgr.get_session_failure_summary(session_id)

        assert summary is not None
        assert summary["total_failures"] == 1
        assert summary["by_type"] == {"chapter_hook_weak": 1}
        assert summary["failed_gates"] == {"L3": 1}
        assert summary["details"][0]["shot_index"] == 2


class TestCheckpoints:
    """Checkpoint write/load/verify"""

    def test_write_and_load_checkpoint(self, mgr):
        session_id = mgr.create_session()
        checkpoint_data = {
            "shot_id": "shot_01",
            "drafts": [{"text": "test"}],
            "scores": {"literary_quality": 8},
        }

        self._ensure_shot(mgr.db, session_id, "shot_01")
        cp_id = mgr.write_checkpoint(session_id, "shot_01", checkpoint_data)
        loaded = mgr.load_latest_checkpoint(session_id)

        assert loaded is not None
        assert loaded["shot_id"] == "shot_01"
        assert loaded["checkpoint_json"]["drafts"][0]["text"] == "test"

    def test_load_latest_returns_most_recent(self, mgr):
        session_id = mgr.create_session()
        self._ensure_shot(mgr.db, session_id, "shot_01")
        self._ensure_shot(mgr.db, session_id, "shot_02", shot_index=2)
        cp1 = mgr.write_checkpoint(session_id, "shot_01", {"seq": 1})
        import time
        time.sleep(1.1)  # Ensure different created_at timestamps
        cp2 = mgr.write_checkpoint(session_id, "shot_02", {"seq": 2})

        loaded = mgr.load_latest_checkpoint(session_id)
        assert loaded is not None
        assert loaded["checkpoint_json"]["seq"] == 2  # Deterministic: cp2 is newer

    def test_no_checkpoint_returns_none(self, mgr):
        session_id = mgr.create_session()
        assert mgr.load_latest_checkpoint(session_id) is None

    def test_verify_checkpoint_integrity(self, mgr):
        session_id = mgr.create_session()
        self._ensure_shot(mgr.db, session_id, "shot_01")
        data = {"key": "value"}
        cp_id = mgr.write_checkpoint(session_id, "shot_01", data)

        assert mgr.verify_checkpoint_integrity(cp_id, data)
        assert not mgr.verify_checkpoint_integrity(cp_id, {"different": "data"})

    def test_get_checkpoint_by_id(self, mgr):
        session_id = mgr.create_session()
        self._ensure_shot(mgr.db, session_id, "shot_01")
        cp_id = mgr.write_checkpoint(session_id, "shot_01", {"a": 1})
        cp = mgr.get_checkpoint(cp_id)
        assert cp is not None
        assert cp["checkpoint_json"]["a"] == 1

    @staticmethod
    def _ensure_shot(db, session_id, shot_id, shot_index=1):
        """Insert a shot so the checkpoint FK constraint is satisfied."""
        row = db.execute(
            "SELECT run_id FROM writing_sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()
        if row is None:
            return
        run_id = row["run_id"]
        db.execute(
            "INSERT OR IGNORE INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES (?, 'proj_01', ?, 'v01.c01', ?, 'pending')",
            (shot_id, run_id, shot_index),
        )
        db.commit()


class TestProjectStructure:
    """Project structure layers"""

    def test_write_and_read_structure(self, mgr):
        layers = [
            {"layer_type": "project", "layer_key": "project", "parent_layer_key": None, "layer_index": 0},
            {"layer_type": "volume", "layer_key": "v01", "parent_layer_key": "project", "layer_index": 1},
            {"layer_type": "chapter", "layer_key": "v01.c01", "parent_layer_key": "v01", "layer_index": 2},
            {"layer_type": "scene", "layer_key": "v01.c01.s01", "parent_layer_key": "v01.c01", "layer_index": 3},
        ]
        mgr.write_project_structure(layers, human_confirm_layer=2)

        structure = mgr.get_project_structure()
        assert len(structure) == 4
        assert structure[0]["layer_type"] == "project"
        assert structure[2]["layer_key"] == "v01.c01"


class TestShots:
    """Shot CRUD"""

    def test_create_shots(self, mgr):
        session_id = mgr.create_session()
        session = mgr.get_session(session_id)
        run_id = session["run_id"]

        shots = [
            {"layer_key": "v01.c02", "shot_index": 1},
            {"layer_key": "v01.c02", "shot_index": 2},
            {"layer_key": "v01.c02", "shot_index": 3},
        ]
        shot_ids = mgr.create_shots(run_id, shots)
        assert len(shot_ids) == 3

        all_shots = mgr.get_shots_for_run(run_id)
        assert len(all_shots) == 3
        assert all_shots[0]["shot_status"] == "pending"
        assert all_shots[0]["shot_index"] == 1
        assert all_shots[0]["logical_shot_id"] == "v01.c02.s01"
        assert all_shots[0]["shot_id"].startswith("v01.c02.s01@")

    def test_create_shots_is_idempotent_only_within_same_run(self, mgr):
        """A chapter rewrite must create fresh shot rows for the new run."""
        session_a = mgr.get_session(mgr.create_session(act_id="v01.c02", total_shots=1))
        session_b = mgr.get_session(mgr.create_session(act_id="v01.c02", total_shots=1))

        shot_a = mgr.create_shots(
            session_a["run_id"], [{"layer_key": "v01.c02", "shot_index": 1}],
        )[0]
        shot_a_again = mgr.create_shots(
            session_a["run_id"], [{"layer_key": "v01.c02", "shot_index": 1}],
        )[0]
        shot_b = mgr.create_shots(
            session_b["run_id"], [{"layer_key": "v01.c02", "shot_index": 1}],
        )[0]

        assert shot_a == shot_a_again
        assert shot_b != shot_a

        rows = mgr.db.execute(
            "SELECT run_id, logical_shot_id, shot_id FROM writing_shots "
            "WHERE layer_key = 'v01.c02' ORDER BY run_id"
        ).fetchall()
        assert len(rows) == 2
        assert {row["logical_shot_id"] for row in rows} == {"v01.c02.s01"}
        assert {row["shot_id"] for row in rows} == {shot_a, shot_b}

    def test_update_shot_status(self, mgr):
        session_id = mgr.create_session()
        session = mgr.get_session(session_id)
        run_id = session["run_id"]

        shot_ids = mgr.create_shots(run_id, [{"layer_key": "v01.c02", "shot_index": 1}])
        shot_id = shot_ids[0]

        mgr.update_shot_status(shot_id, ShotStatus.DONE_GREEN, light_status="green", brilliance_level="A")
        shot = mgr.get_shot(shot_id)
        assert shot["shot_status"] == "done_green"
        assert shot["light_status"] == "green"
        assert shot["brilliance_level"] == "A"


class TestRevisions:
    """Revision chain"""

    def test_write_revision(self, mgr):
        session_id = mgr.create_session()
        session = mgr.get_session(session_id)
        run_id = session["run_id"]

        # Create shot
        shot_ids = mgr.create_shots(run_id, [{"layer_key": "v01.c02", "shot_index": 1}])
        shot_id = shot_ids[0]

        # Create contract record (minimal)
        from inkflow.utils.ulid import generate as gen
        contract_id = gen()
        mgr.db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES (?, ?, ?, ?, ?, 'draft', 'hash1', '{}', '{}', '{}')",
            (contract_id, "proj_01", run_id, shot_id, "v01.c02"),
        )
        mgr.db.commit()

        rev_id = mgr.write_revision(
            shot_id=shot_id,
            run_id=run_id,
            contract_id=contract_id,
            revision_sequence=1,
            operation="write_generate",
            text="测试正文内容",
            text_hash="abc123",
            writer_persona="意象师",
            jury_scores_json={"literary_quality": 8},
        )

        rev = mgr.get_current_revision(shot_id)
        assert rev is not None
        assert rev["text"] == "测试正文内容"
        assert rev["is_current"] == 1
        assert rev["writer_persona"] == "意象师"

        # Write second revision — should become current
        rev2_id = mgr.write_revision(
            shot_id=shot_id,
            run_id=run_id,
            contract_id=contract_id,
            revision_sequence=2,
            operation="write_generate",
            text="修改后的正文",
            text_hash="def456",
            writer_persona="节奏师",
        )

        rev2 = mgr.get_current_revision(shot_id)
        assert rev2["text"] == "修改后的正文"
        assert rev2["revision_id"] == rev2_id

        # First revision should no longer be current
        import sqlite3 as _sql
        mgr.db.row_factory = _sql.Row
        old_rev = mgr.db.execute(
            "SELECT is_current FROM shot_revisions WHERE revision_id = ?", (rev_id,)
        ).fetchone()
        assert old_rev["is_current"] == 0


class TestRunSnapshots:
    """Run snapshots"""

    def test_create_run_snapshot(self, mgr):
        session_id = mgr.create_session()
        session = mgr.get_session(session_id)
        run_id = session["run_id"]

        from inkflow.utils.ulid import generate as gen
        mc_id = gen()
        mgr.db.execute(
            "INSERT INTO writing_meta_contract "
            "(meta_contract_id, project_id, status, layers_json, human_confirm_layer) "
            "VALUES (?, ?, 'draft', '{}', 2)",
            (mc_id, "proj_01"),
        )
        mgr.db.commit()

        snap_id = mgr.create_run_snapshot(
            run_id=run_id,
            meta_contract_id=mc_id,
            config_hash_str="cfg_hash",
            contract_snapshot_hash="cs_hash",
            snapshot_data={"contracts": [1, 2, 3]},
        )

        row = mgr.db.execute(
            "SELECT * FROM writing_run_snapshots WHERE snapshot_id = ?", (snap_id,)
        ).fetchone()
        assert row is not None
        assert row["run_id"] == run_id


class TestProjectConfig:
    """Project config from .models"""

    def test_get_project_config_none_when_empty(self, mgr):
        assert mgr.get_project_config() is None

    def test_init_project_config(self, mgr, tmp_dir: Path):
        models_dir = tmp_dir / ".inkflow"
        models_dir.mkdir(parents=True, exist_ok=True)
        models_path = models_dir / ".models"
        models_path.write_text(
            "providers:\n"
            "  test:\n"
            "    api_key: sk-test\n"
            "    base_url: https://test.example.com/v1\n"
            "    protocol: openai\n"
            "architect:\n"
            "  primary: claude-opus-4-6\n"
            "  candidates:\n"
            "    - claude-sonnet-4-6\n"
            "  fallback: gpt-5\n"
            "writer:\n"
            "  primary: claude-sonnet-4-6\n"
            "  candidates:\n"
            "    - gpt-5\n"
            "  fallback: local-default\n",
            encoding="utf-8",
        )

        config_id = mgr.init_project_config(str(tmp_dir))
        config = mgr.get_project_config()
        assert config is not None
        assert config["project_id"] == "proj_01"
        layers = config["layers_json"]
        assert "function_models" in layers
        assert "architect" in layers["function_models"]
