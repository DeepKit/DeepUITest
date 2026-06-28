"""Session Manager (Service 8).

Manages writing sessions, checkpoints, resume/recovery, and project config.

Responsibilities:
- Create and manage writing sessions
- Write per-shot checkpoints for crash recovery
- Load checkpoint state during resume
- List incomplete sessions
- Abort sessions
- Load .models config and write to project_config
"""

from __future__ import annotations

import json
import sqlite3
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.utils.shot_id import (
    generate as generate_shot_id,
    generate_attempt as generate_attempt_shot_id,
)
from inkflow.utils.hashing import context_hash
from inkflow.utils.config import (
    load_models_config,
    compute_config_hash,
    write_project_config_record,
)
from inkflow.models.enums import SessionStatus, ShotStatus


class SessionManager:
    """Manages writing sessions lifecycle."""

    def __init__(self, db: sqlite3.Connection, project_id: str):
        self.db = db
        self.project_id = project_id

    # ── Session lifecycle ──

    def create_session(
        self,
        *,
        act_id: str | None = None,
        total_shots: int | None = None,
    ) -> str:
        """Create a new writing session.

        Args:
            act_id: Optional act/chapter layer key.
            total_shots: Expected total shots (for progress tracking).

        Returns:
            session_id of the new session.
        """
        session_id = generate_ulid()
        run_id = generate_ulid()

        self.db.execute(
            "INSERT INTO writing_sessions "
            "(session_id, project_id, run_id, act_id, status, total_shots) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (session_id, self.project_id, run_id, act_id, SessionStatus.ACTIVE, total_shots),
        )
        self.db.commit()
        return session_id

    def get_session(self, session_id: str) -> dict | None:
        """Get session info by ID."""
        row = self.db.execute(
            "SELECT * FROM writing_sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()
        if row is None:
            return None
        return dict(row)

    def update_session_status(self, session_id: str, status: str | SessionStatus) -> None:
        """Update session status."""
        status_val = status.value if isinstance(status, SessionStatus) else status
        self.db.execute(
            "UPDATE writing_sessions SET status = ?, updated_at = datetime('now') "
            "WHERE session_id = ?",
            (status_val, session_id),
        )
        self.db.commit()

    def update_current_shot(self, session_id: str, shot_id: str) -> None:
        """Update the current shot being processed."""
        self.db.execute(
            "UPDATE writing_sessions SET current_shot_id = ?, updated_at = datetime('now') "
            "WHERE session_id = ?",
            (shot_id, session_id),
        )
        self.db.commit()

    def increment_completed_shots(self, session_id: str) -> None:
        """Increment completed shots counter."""
        self.db.execute(
            "UPDATE writing_sessions SET completed_shots = completed_shots + 1, "
            "updated_at = datetime('now') WHERE session_id = ?",
            (session_id,),
        )
        self.db.commit()

    def abort_session(self, session_id: str) -> None:
        """Abort a session. Generated text is preserved."""
        self.update_session_status(session_id, SessionStatus.ABORTED)

    def complete_session(self, session_id: str) -> None:
        """Mark session as completed."""
        self.update_session_status(session_id, SessionStatus.COMPLETED)

    def mark_crashed(self, session_id: str) -> None:
        """Mark session as crashed."""
        self.update_session_status(session_id, SessionStatus.CRASHED)

    def list_incomplete_sessions(self) -> list[dict]:
        """List recoverable sessions that are not completed or explicitly aborted."""
        rows = self.db.execute(
            "SELECT * FROM writing_sessions "
            "WHERE project_id = ? AND status IN ('active', 'paused', 'crashed') "
            "ORDER BY created_at DESC",
            (self.project_id,),
        ).fetchall()
        return [dict(r) for r in rows]

    def get_session_failure_summary(self, session_id: str) -> dict | None:
        """Summarize shot failure signatures and failed gates for a session."""
        session = self.get_session(session_id)
        if session is None:
            return None

        rows = self.db.execute(
            "SELECT shot_id, shot_index, failure_signature_json "
            "FROM writing_shots "
            "WHERE run_id = ? AND failure_signature_json IS NOT NULL "
            "ORDER BY shot_index",
            (session["run_id"],),
        ).fetchall()

        by_type: Counter = Counter()
        details = []
        for row in rows:
            try:
                sig = json.loads(row["failure_signature_json"])
            except (json.JSONDecodeError, TypeError):
                continue
            failure_type = sig.get("last_failure_type", "unknown")
            by_type[failure_type] += 1
            details.append({
                "shot_id": row["shot_id"],
                "shot_index": row["shot_index"],
                "failure_type": failure_type,
                "consecutive_count": sig.get("consecutive_count", 0),
                "detail": sig.get("detail", ""),
            })

        gate_rows = self.db.execute(
            "SELECT level, COUNT(*) AS cnt FROM writing_architect_gates "
            "WHERE run_id = ? AND status = 'failed' "
            "GROUP BY level ORDER BY level",
            (session["run_id"],),
        ).fetchall()
        failed_gates = {row["level"]: row["cnt"] for row in gate_rows}

        return {
            "session_id": session_id,
            "run_id": session["run_id"],
            "status": session["status"],
            "total_failures": len(details),
            "by_type": dict(by_type),
            "details": details,
            "failed_gates": failed_gates,
        }

    # ── Checkpoints ──

    def write_checkpoint(
        self,
        session_id: str,
        shot_id: str,
        checkpoint_data: dict,
        *,
        storage_path: str = ".checkpoints/",
    ) -> str:
        """Write a per-shot checkpoint.

        Args:
            session_id: Active session ID.
            shot_id: Shot that just completed.
            checkpoint_data: Full checkpoint state (drafts, scores, gate results, etc.)
            storage_path: Relative path for checkpoint storage.

        Returns:
            checkpoint_id.
        """
        checkpoint_id = generate_ulid()
        ctx_hash = context_hash(checkpoint_data)

        self.db.execute(
            "INSERT INTO writing_session_checkpoints "
            "(checkpoint_id, session_id, shot_id, checkpoint_json, "
            "checkpoint_storage_path, context_hash) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                checkpoint_id,
                session_id,
                shot_id,
                json.dumps(checkpoint_data, ensure_ascii=False),
                storage_path,
                ctx_hash,
            ),
        )
        self.db.commit()
        return checkpoint_id

    def load_latest_checkpoint(self, session_id: str) -> dict | None:
        """Load the most recent checkpoint for a session.

        Returns:
            Checkpoint data dict, or None if no checkpoints exist.
        """
        row = self.db.execute(
            "SELECT * FROM writing_session_checkpoints "
            "WHERE session_id = ? "
            "ORDER BY created_at DESC LIMIT 1",
            (session_id,),
        ).fetchone()
        if row is None:
            return None
        result = dict(row)
        result["checkpoint_json"] = json.loads(result["checkpoint_json"])
        return result

    def get_checkpoint(self, checkpoint_id: str) -> dict | None:
        """Get a specific checkpoint by ID."""
        row = self.db.execute(
            "SELECT * FROM writing_session_checkpoints WHERE checkpoint_id = ?",
            (checkpoint_id,),
        ).fetchone()
        if row is None:
            return None
        result = dict(row)
        result["checkpoint_json"] = json.loads(result["checkpoint_json"])
        return result

    def verify_checkpoint_integrity(self, checkpoint_id: str, current_state: dict) -> bool:
        """Verify checkpoint context hash matches current state."""
        row = self.db.execute(
            "SELECT context_hash FROM writing_session_checkpoints "
            "WHERE checkpoint_id = ?",
            (checkpoint_id,),
        ).fetchone()
        if row is None:
            return False
        return row["context_hash"] == context_hash(current_state)

    # ── Project config ──

    def init_project_config(self, project_root: str | Path) -> str:
        """Initialize project configuration from .models file.

        Args:
            project_root: Path to project root directory.

        Returns:
            config_id of the written record.
        """
        models_config = load_models_config(project_root)
        return write_project_config_record(self.db, self.project_id, models_config)

    def get_project_config(self) -> dict | None:
        """Get the latest project config."""
        row = self.db.execute(
            "SELECT * FROM writing_project_config "
            "WHERE project_id = ? "
            "ORDER BY updated_at DESC LIMIT 1",
            (self.project_id,),
        ).fetchone()
        if row is None:
            return None
        result = dict(row)
        result["layers_json"] = json.loads(result["layers_json"])
        return result

    # ── Project structure ──

    def write_project_structure(
        self,
        layers: list[dict],
        human_confirm_layer: int,
    ) -> None:
        """Write project structure layers.

        All inserts are wrapped in a single transaction so partial
        failure does not leave orphaned rows.

        Args:
            layers: List of layer definitions with layer_type, layer_key, parent_layer_key, layer_index.
            human_confirm_layer: The layer index where human confirmation is required.
        """
        try:
            self.db.execute("SAVEPOINT write_project_structure")
            for layer in layers:
                structure_id = generate_ulid()
                self.db.execute(
                    "INSERT INTO writing_project_structure "
                    "(structure_id, project_id, layer_type, layer_key, "
                    "parent_layer_key, layer_index, human_confirm_layer, metadata_json) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        structure_id,
                        self.project_id,
                        layer["layer_type"],
                        layer["layer_key"],
                        layer.get("parent_layer_key"),
                        layer["layer_index"],
                        human_confirm_layer,
                        json.dumps(layer.get("metadata", {}), ensure_ascii=False),
                    ),
                )
            self.db.execute("RELEASE SAVEPOINT write_project_structure")
        except Exception:
            self.db.execute("ROLLBACK TO SAVEPOINT write_project_structure")
            raise
        self.db.commit()

    def get_project_structure(self) -> list[dict]:
        """Get all project structure layers."""
        rows = self.db.execute(
            "SELECT * FROM writing_project_structure "
            "WHERE project_id = ? "
            "ORDER BY layer_index",
            (self.project_id,),
        ).fetchall()
        return [dict(r) for r in rows]

    # ── Shots ──

    def create_shots(
        self,
        run_id: str,
        shots: list[dict],
    ) -> list[str]:
        """Create shot attempt records for a run.

        Args:
            run_id: The run ID these shots belong to.
            shots: List of {layer_key, shot_index} dicts.

        Returns:
            List of shot_ids.
        """
        shot_ids = []
        for shot in shots:
            # logical_shot_id is stable across rewrites; shot_id is run-attempt-specific.
            logical_shot_id = generate_shot_id(shot["layer_key"], shot["shot_index"])
            shot_id = generate_attempt_shot_id(
                shot["layer_key"], shot["shot_index"], run_id,
            )

            # Idempotent only within the same run. A new run must create fresh
            # shot rows even for the same logical chapter/shot index.
            existing = self.db.execute(
                "SELECT shot_id FROM writing_shots "
                "WHERE run_id = ? AND logical_shot_id = ?",
                (run_id, logical_shot_id),
            ).fetchone()
            if existing:
                shot_ids.append(existing["shot_id"])
                continue
            self.db.execute(
                "INSERT INTO writing_shots "
                "(shot_id, logical_shot_id, project_id, run_id, layer_key, "
                "shot_index, shot_status) "
                "VALUES (?, ?, ?, ?, ?, ?, 'pending')",
                (
                    shot_id, logical_shot_id, self.project_id, run_id,
                    shot["layer_key"], shot["shot_index"],
                ),
            )
            shot_ids.append(shot_id)
        self.db.commit()
        return shot_ids

    def update_shot_status(self, shot_id: str, status: str | ShotStatus, **kwargs) -> None:
        """Update shot status and optional fields."""
        status_val = status.value if isinstance(status, ShotStatus) else status
        fields = ["shot_status = ?"]
        params = [status_val]

        if "light_status" in kwargs:
            fields.append("light_status = ?")
            params.append(kwargs["light_status"])
        if "brilliance_level" in kwargs:
            fields.append("brilliance_level = ?")
            params.append(kwargs["brilliance_level"])
        if "badsmell_level" in kwargs:
            fields.append("badsmell_level = ?")
            params.append(kwargs["badsmell_level"])
        if "placeholder_type" in kwargs:
            fields.append("placeholder_type = ?")
            params.append(kwargs["placeholder_type"])
        if "redo_attempt" in kwargs:
            fields.append("redo_attempt = ?")
            params.append(kwargs["redo_attempt"])
        if "current_revision_id" in kwargs:
            fields.append("current_revision_id = ?")
            params.append(kwargs["current_revision_id"])

        fields.append("updated_at = datetime('now')")
        params.append(shot_id)

        self.db.execute(
            f"UPDATE writing_shots SET {', '.join(fields)} WHERE shot_id = ?",
            params,
        )
        self.db.commit()

    def get_shot(self, shot_id: str) -> dict | None:
        """Get shot by ID."""
        row = self.db.execute(
            "SELECT * FROM writing_shots WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()
        return dict(row) if row else None

    def get_shots_for_run(self, run_id: str) -> list[dict]:
        """Get all shots for a run, ordered by shot_index."""
        rows = self.db.execute(
            "SELECT * FROM writing_shots WHERE run_id = ? ORDER BY shot_index",
            (run_id,),
        ).fetchall()
        return [dict(r) for r in rows]

    # ── Revisions ──

    def write_revision(
        self,
        shot_id: str,
        run_id: str,
        contract_id: str,
        revision_sequence: int,
        operation: str,
        text: str,
        text_hash: str,
        *,
        writer_persona: str | None = None,
        parent_revision_id: str | None = None,
        jury_scores_json: dict | None = None,
        gate_result_json: dict | None = None,
        attempt_id: str | None = None,
    ) -> str:
        """Write a new revision for a shot.

        Unsets is_current on previous revisions, sets it on the new one.
        All operations are wrapped in a single transaction to prevent
        the shot from having zero current revisions on partial failure.

        DB-1: Rejects writes to baseline shots (is_baseline=1) unless
        the operation is 'write_repair' with explicit allow_baseline bypass.
        """
        revision_id = generate_ulid()
        attempt_id = attempt_id or generate_ulid()

        # DB-1: Guard against overwriting baseline shots
        shot_row = self.db.execute(
            "SELECT is_baseline FROM writing_shots WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()
        if shot_row and shot_row["is_baseline"]:
            raise ValueError(
                f"Shot {shot_id} is a locked human_baseline. "
                f"Cannot write new revision via operation={operation}."
            )

        try:
            self.db.execute("SAVEPOINT write_revision")

            # Unset is_current on all previous revisions for this shot
            self.db.execute(
                "UPDATE shot_revisions SET is_current = 0 WHERE shot_id = ?",
                (shot_id,),
            )

            self.db.execute(
                "INSERT INTO shot_revisions "
                "(revision_id, shot_id, run_id, parent_revision_id, contract_id, "
                "revision_sequence, operation, text, text_hash_normalized, "
                "writer_persona, jury_scores_json, gate_result_json, is_current, attempt_id) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)",
                (
                    revision_id,
                    shot_id,
                    run_id,
                    parent_revision_id,
                    contract_id,
                    revision_sequence,
                    operation,
                    text,
                    text_hash,
                    writer_persona,
                    json.dumps(jury_scores_json, ensure_ascii=False) if jury_scores_json else None,
                    json.dumps(gate_result_json, ensure_ascii=False) if gate_result_json else None,
                    attempt_id,
                ),
            )

            # Update shot's current_revision_id
            self.db.execute(
                "UPDATE writing_shots SET current_revision_id = ?, updated_at = datetime('now') "
                "WHERE shot_id = ?",
                (revision_id, shot_id),
            )
            self.db.execute("RELEASE SAVEPOINT write_revision")
        except Exception:
            self.db.execute("ROLLBACK TO SAVEPOINT write_revision")
            raise

        self.db.commit()
        return revision_id

    def get_current_revision(self, shot_id: str) -> dict | None:
        """Get the current revision for a shot (locked=is_current, uncommitted=latest)."""
        from inkflow.services.text_repository import TextRepository
        repo = TextRepository(self.db)
        return repo.get_shot_current_revision(shot_id)

    # ── Run snapshots ──

    def create_run_snapshot(
        self,
        run_id: str,
        meta_contract_id: str,
        config_hash_str: str,
        contract_snapshot_hash: str,
        snapshot_data: dict,
    ) -> str:
        """Create a run snapshot (contract snapshot at run start)."""
        existing = self.db.execute(
            "SELECT snapshot_id FROM writing_run_snapshots WHERE run_id = ?",
            (run_id,),
        ).fetchone()
        if existing:
            return existing["snapshot_id"]

        snapshot_id = generate_ulid()
        self.db.execute(
            "INSERT INTO writing_run_snapshots "
            "(snapshot_id, run_id, project_id, meta_contract_id, "
            "config_hash, contract_snapshot_hash, snapshot_json) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                snapshot_id,
                run_id,
                self.project_id,
                meta_contract_id,
                config_hash_str,
                contract_snapshot_hash,
                json.dumps(snapshot_data, ensure_ascii=False),
            ),
        )
        self.db.commit()
        return snapshot_id
