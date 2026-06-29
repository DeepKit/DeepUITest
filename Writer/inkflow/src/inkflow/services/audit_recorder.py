"""Unified audit recording for InkFlow production runs.

This layer is intentionally thin: business services keep their own domain
tables, while audit rows connect stage events, eligibility decisions, setup
snapshots, and failure attribution into a queryable chain.
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

from inkflow.utils.hashing import snapshot_hash
from inkflow.utils.ulid import generate as generate_ulid


FAILURE_CATEGORIES = {
    "contract_conflict",
    "outline_gap",
    "task_card_gap",
    "writer_drift",
    "gate_false_positive",
    "model_failure",
    "jury_failure",
    "unknown",
}


class AuditRecorder:
    """Append-only audit helper.

    Methods swallow sqlite errors only when the audit table is absent. That
    keeps older ad-hoc DBs usable during migration, while normal schema errors
    still surface in tests and fresh databases.
    """

    def __init__(
        self,
        db: sqlite3.Connection,
        *,
        project_id: str | None = None,
        run_id: str | None = None,
        session_id: str | None = None,
    ) -> None:
        self.db = db
        self.project_id = project_id
        self.run_id = run_id
        self.session_id = session_id

    def record_event(
        self,
        *,
        stage: str,
        event_type: str,
        status: str = "recorded",
        shot_id: str | None = None,
        actor: str | None = None,
        input_refs: dict[str, Any] | None = None,
        output_refs: dict[str, Any] | None = None,
        metrics: dict[str, Any] | None = None,
        payload: dict[str, Any] | None = None,
        failure_category: str | None = None,
        failure_detail: str | None = None,
    ) -> str | None:
        if failure_category and failure_category not in FAILURE_CATEGORIES:
            failure_category = "unknown"
        event_id = generate_ulid()
        try:
            self.db.execute(
                "INSERT INTO writing_audit_events "
                "(event_id, project_id, run_id, session_id, shot_id, stage, "
                "event_type, status, actor, input_refs_json, output_refs_json, "
                "metrics_json, payload_json, failure_category, failure_detail) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    event_id,
                    self.project_id,
                    self.run_id,
                    self.session_id,
                    shot_id,
                    stage,
                    event_type,
                    status,
                    actor,
                    _json(input_refs or {}),
                    _json(output_refs or {}),
                    _json(metrics or {}),
                    _json(payload or {}),
                    failure_category,
                    failure_detail,
                ),
            )
            self.db.commit()
            return event_id
        except sqlite3.OperationalError as exc:
            if "writing_audit_events" not in str(exc):
                raise
            return None

    def record_setup_snapshot(
        self,
        *,
        chapter_key: str,
        setup_data: dict[str, Any],
        source_path: str | Path | None = None,
        meta_contract_id: str | None = None,
        status: str | None = None,
    ) -> str | None:
        setup_id = generate_ulid()
        setup_hash = snapshot_hash(setup_data)
        source_path_text = str(source_path) if source_path else None
        setup_status = status or str(setup_data.get("status") or "ready")
        contract_id = (
            meta_contract_id
            or (setup_data.get("source_contract") or {}).get("meta_contract_id")
        )
        try:
            self.db.execute(
                "INSERT OR IGNORE INTO writing_setup_snapshots "
                "(setup_id, project_id, run_id, chapter_key, meta_contract_id, "
                "source_path, setup_hash, setup_json, status) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    setup_id,
                    self.project_id,
                    self.run_id,
                    chapter_key,
                    contract_id,
                    source_path_text,
                    setup_hash,
                    _json(setup_data),
                    setup_status,
                ),
            )
            row = self.db.execute(
                "SELECT setup_id FROM writing_setup_snapshots "
                "WHERE project_id = ? AND chapter_key = ? AND setup_hash = ?",
                (self.project_id, chapter_key, setup_hash),
            ).fetchone()
            self.db.commit()
            resolved_id = row["setup_id"] if row else setup_id
            self.record_event(
                stage="setup",
                event_type="setup_snapshot_recorded",
                status="recorded",
                input_refs={"source_path": source_path_text},
                output_refs={"setup_id": resolved_id, "setup_hash": setup_hash},
                payload={"chapter_key": chapter_key, "status": setup_status},
            )
            return resolved_id
        except sqlite3.OperationalError as exc:
            if "writing_setup_snapshots" not in str(exc):
                raise
            return None

    def record_draft_eligibility(
        self,
        *,
        draft_id: str,
        shot_id: str,
        gate_stage: str,
        passed: bool,
        attempt_id: str,
        score: float | None = None,
        threshold: float | None = None,
        reason: dict[str, Any] | None = None,
        result: dict[str, Any] | None = None,
    ) -> str | None:
        eligibility_id = generate_ulid()
        try:
            self.db.execute(
                "INSERT OR REPLACE INTO writing_draft_eligibility "
                "(eligibility_id, draft_id, shot_id, run_id, gate_stage, "
                "passed, score, threshold, reason_json, result_json, attempt_id) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    eligibility_id,
                    draft_id,
                    shot_id,
                    self.run_id,
                    gate_stage,
                    1 if passed else 0,
                    score,
                    threshold,
                    _json(reason or {}),
                    _json(result or {}),
                    attempt_id,
                ),
            )
            self.db.commit()
            self.record_event(
                stage=gate_stage,
                event_type="draft_eligibility",
                status="passed" if passed else "failed",
                shot_id=shot_id,
                input_refs={"draft_id": draft_id},
                metrics={"score": score, "threshold": threshold},
                payload={"reason": reason or {}, "result": result or {}},
                failure_category=None if passed else _infer_failure_category(gate_stage),
            )
            return eligibility_id
        except sqlite3.OperationalError as exc:
            if "writing_draft_eligibility" not in str(exc):
                raise
            return None

    def record_failure_attribution(
        self,
        *,
        stage: str,
        failure_category: str,
        shot_id: str | None = None,
        draft_id: str | None = None,
        root_cause: dict[str, Any] | None = None,
        evidence_refs: dict[str, Any] | None = None,
        suggested_action: str | None = None,
    ) -> str | None:
        if failure_category not in FAILURE_CATEGORIES:
            failure_category = "unknown"
        attribution_id = generate_ulid()
        try:
            self.db.execute(
                "INSERT INTO writing_failure_attributions "
                "(attribution_id, project_id, run_id, shot_id, draft_id, stage, "
                "failure_category, root_cause_json, evidence_refs_json, suggested_action) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    attribution_id,
                    self.project_id,
                    self.run_id,
                    shot_id,
                    draft_id,
                    stage,
                    failure_category,
                    _json(root_cause or {}),
                    _json(evidence_refs or {}),
                    suggested_action,
                ),
            )
            self.db.commit()
            self.record_event(
                stage=stage,
                event_type="failure_attributed",
                status="failed",
                shot_id=shot_id,
                input_refs={"draft_id": draft_id} if draft_id else {},
                output_refs={"attribution_id": attribution_id},
                payload={"root_cause": root_cause or {}, "evidence_refs": evidence_refs or {}},
                failure_category=failure_category,
                failure_detail=suggested_action,
            )
            return attribution_id
        except sqlite3.OperationalError as exc:
            if "writing_failure_attributions" not in str(exc):
                raise
            return None


def _json(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, sort_keys=True)


def _infer_failure_category(stage: str) -> str:
    if stage in {"outline", "outline_gate"}:
        return "outline_gap"
    if stage in {"gate1", "hard_rule", "type_gate", "literary_jury", "gate2", "l4", "l3"}:
        return "writer_drift"
    if stage == "jury_unavailable":
        return "jury_failure"
    return "unknown"


def failure_category_for_retry_type(failure_type: str) -> str:
    if failure_type in {"jury_unavailable"}:
        return "jury_failure"
    if failure_type in {"model_error", "json_parse_error"}:
        return "model_failure"
    if failure_type in {
        "l3_violation",
        "l4_violation",
        "chapter_hook_weak",
        "hard_rule_violation",
    }:
        return "writer_drift"
    if failure_type in {"empty_text", "too_short", "excessive_repetition", "below_threshold"}:
        return "writer_drift"
    return "unknown"
