"""Tests for DB-1/DB-2/DB-3/DB-6: baseline protection, revision constraints, audit."""

from __future__ import annotations

import sqlite3

import pytest


class TestBaselineProtection:
    """DB-1 / B18: Baseline shots should be protected from overwrite."""

    def test_write_revision_rejects_baseline(self, db):
        """write_revision should reject baseline shots."""
        from inkflow.services.session_manager import SessionManager

        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, is_baseline) "
            "VALUES ('sh1', 'p1', 'run_01', 'v01.c01', 1, 'done_green', 1)"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('c1', 'p1', 'run_01', 'sh1', 'v01.c01', 'locked', 'h1', '{}', '{}', '{}')"
        )
        db.commit()

        mgr = SessionManager(db, "p1")
        with pytest.raises(ValueError, match="baseline"):
            mgr.write_revision(
                shot_id="sh1", run_id="run_01", contract_id="c1",
                revision_sequence=2, operation="write_generate",
                text="overwrite", text_hash="h2",
            )

    def test_write_revision_allows_non_baseline(self, db):
        """Non-baseline shots can be written normally."""
        from inkflow.services.session_manager import SessionManager

        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, is_baseline) "
            "VALUES ('sh1', 'p1', 'run_01', 'v01.c02', 1, 'pending', 0)"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('c1', 'p1', 'run_01', 'sh1', 'v01.c02', 'locked', 'h1', '{}', '{}', '{}')"
        )
        db.commit()

        mgr = SessionManager(db, "p1")
        rev_id = mgr.write_revision(
            shot_id="sh1", run_id="run_01", contract_id="c1",
            revision_sequence=1, operation="write_generate",
            text="new text", text_hash="h2",
        )
        assert rev_id is not None

        # Verify is_current
        row = db.execute(
            "SELECT is_current FROM shot_revisions WHERE revision_id = ?", (rev_id,)
        ).fetchone()
        assert row["is_current"] == 1


class TestCurrentRevisionConstraint:
    """DB-2/DB-3: Only one current revision per shot."""

    def test_single_current_revision(self, db):
        """Partial unique index should prevent two is_current=1 revisions."""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', 'p1', 'run_01', 'v01.c02', 1, 'pending')"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('c1', 'p1', 'run_01', 'sh1', 'v01.c02', 'locked', 'h1', '{}', '{}', '{}')"
        )
        db.commit()

        # Insert two current revisions for same shot
        db.execute(
            "INSERT INTO shot_revisions "
            "(revision_id, shot_id, run_id, contract_id, revision_sequence, "
            "operation, text, text_hash_normalized, is_current, attempt_id) "
            "VALUES ('r1', 'sh1', 'run_01', 'c1', 1, 'write_generate', 't1', 'h1', 1, 'a1')"
        )
        db.commit()

        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO shot_revisions "
                "(revision_id, shot_id, run_id, contract_id, revision_sequence, "
                "operation, text, text_hash_normalized, is_current, attempt_id) "
                "VALUES ('r2', 'sh1', 'run_01', 'c1', 2, 'write_generate', 't2', 'h2', 1, 'a2')"
            )


class TestModelAttemptsAudit:
    """DB-6 / B22: Model call audit table."""

    def test_model_attempts_table_exists(self, db):
        """model_attempts table should be created."""
        row = db.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='model_attempts'"
        ).fetchone()
        assert row is not None

    def test_audit_record_inserted(self, db):
        """Model attempts should be recorded."""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', 'p1', 'run_01', 'v01.c02', 1, 'pending')"
        )
        db.commit()

        db.execute(
            "INSERT INTO model_attempts "
            "(attempt_id, run_id, shot_id, phase, model_name, idempotency_key, "
            "request_prompt_hash, response_text_hash, "
            "usage_prompt_tokens, usage_completion_tokens, usage_total_tokens) "
            "VALUES ('a1', 'run_01', 'sh1', 'write_generate', 'local-default', "
            "'ik1', 'ph1', 'rh1', 100, 200, 300)"
        )
        db.commit()

        row = db.execute("SELECT * FROM model_attempts WHERE attempt_id = 'a1'").fetchone()
        assert row is not None
        assert row["phase"] == "write_generate"
        assert row["model_name"] == "local-default"
        assert row["usage_total_tokens"] == 300

    def test_polish_phase_is_valid(self, db):
        """CREATIVE-2: model_attempts.phase accepts polish."""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        db.commit()

        db.execute(
            "INSERT INTO model_attempts "
            "(attempt_id, run_id, phase, model_name, idempotency_key, request_prompt_hash) "
            "VALUES ('a1', 'run_01', 'polish', 'local-default', 'polish_key', 'ph1')"
        )
        db.commit()

        row = db.execute("SELECT phase FROM model_attempts WHERE attempt_id = 'a1'").fetchone()
        assert row["phase"] == "polish"

    def test_idempotency_key_unique(self, db):
        """Duplicate idempotency_key should be rejected."""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        db.commit()

        db.execute(
            "INSERT INTO model_attempts "
            "(attempt_id, run_id, phase, model_name, idempotency_key, request_prompt_hash) "
            "VALUES ('a1', 'run_01', 'write_generate', 'local-default', 'dup_key', 'ph1')"
        )
        db.commit()

        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO model_attempts "
                "(attempt_id, run_id, phase, model_name, idempotency_key, request_prompt_hash) "
                "VALUES ('a2', 'run_01', 'write_generate', 'local-default', 'dup_key', 'ph2')"
            )
