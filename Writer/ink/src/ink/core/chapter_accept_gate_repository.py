from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass

from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


GATE_TYPES = (
    "scene_integrity",
    "chapter_quality",
    "book_continuity",
    "ethics",
)
CURRENT_POLICY_VERSION = "scene-first-accept-v1"


@dataclass(frozen=True)
class AcceptGateEvidence:
    evidence_id: int
    gate_type: str
    passed: bool
    evidence: dict[str, object]


class ChapterAcceptGateRepository:
    """Immutable quality evidence for one exact frozen Chapter Branch Version."""

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def record_evidence(
        self,
        *,
        branch_version_id: int,
        gate_type: str,
        passed: bool,
        evidence: dict[str, object],
        producer_actor: str,
        reviewer_models: tuple[str, ...] = (),
        predecessor_heads_hash: str | None = None,
        policy_version: str = CURRENT_POLICY_VERSION,
    ) -> int:
        if gate_type not in GATE_TYPES:
            raise ValueError(f"unknown Chapter Accept gate: {gate_type}")
        identity = self._branch_identity(branch_version_id)
        if identity[4] != "frozen" or not identity[3]:
            raise DataIntegrityError("accept gate evidence requires a hash-bound frozen branch version")
        self._assert_branch_fresh(branch_version_id)
        if gate_type == "book_continuity":
            expected = self.predecessor_heads_hash(
                project_id=identity[0], chapter_id=identity[1]
            )
            if predecessor_heads_hash != expected:
                raise DataIntegrityError("book continuity evidence predecessor Heads are stale")
        began = not self.conn.in_transaction
        if began:
            self.conn.execute("BEGIN IMMEDIATE")
        try:
            attempt_row = self.conn.execute(
                "SELECT coalesce(max(attempt), 0) + 1 "
                "FROM writing_chapter_accept_gate_evidence "
                "WHERE branch_version_id = ? AND gate_type = ?",
                (branch_version_id, gate_type),
            ).fetchone()
            cursor = self.conn.execute(
                """
                INSERT INTO writing_chapter_accept_gate_evidence
                    (project_id, chapter_id, generation_round_id, branch_version_id,
                     branch_content_hash, gate_type, attempt, policy_version, passed,
                     evidence_json, predecessor_heads_hash, producer_actor,
                     reviewer_models_json, evaluated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    identity[0], identity[1], identity[2], branch_version_id, identity[3],
                    gate_type, int(attempt_row[0]), policy_version, int(passed),
                    json.dumps(evidence, ensure_ascii=False, sort_keys=True),
                    predecessor_heads_hash, producer_actor,
                    json.dumps(list(reviewer_models), ensure_ascii=False), now_utc_iso(),
                ),
            )
            if began:
                self.conn.commit()
            return int(cursor.lastrowid)
        except Exception:
            if began:
                self.conn.rollback()
            raise

    def require_passing_bundle(
        self,
        *,
        branch_version_id: int,
        project_id: int,
        chapter_id: int,
        generation_round_id: int,
        content_hash: str,
    ) -> dict[str, AcceptGateEvidence]:
        require_ethics = self.conn.execute(
            "SELECT require_ethics_review FROM writing_projects WHERE project_id = ?",
            (project_id,),
        ).fetchone()
        if require_ethics is None:
            raise DataIntegrityError(f"unknown project: {project_id}")
        rows = self.conn.execute(
            """
            SELECT e.evidence_id, e.gate_type, e.passed, e.evidence_json,
                   e.project_id, e.chapter_id, e.generation_round_id,
                   e.branch_content_hash, e.policy_version, e.predecessor_heads_hash
            FROM writing_chapter_accept_gate_evidence e
            JOIN (
                SELECT gate_type, max(attempt) AS attempt
                FROM writing_chapter_accept_gate_evidence
                WHERE branch_version_id = ?
                GROUP BY gate_type
            ) latest ON latest.gate_type = e.gate_type AND latest.attempt = e.attempt
            WHERE e.branch_version_id = ?
            """,
            (branch_version_id, branch_version_id),
        ).fetchall()
        by_gate = {str(row[1]): row for row in rows}
        missing = [gate for gate in GATE_TYPES if gate not in by_gate]
        if missing:
            raise DataIntegrityError(
                "chapter accept gate evidence missing: " + ", ".join(missing)
            )
        predecessor_hash = self.predecessor_heads_hash(
            project_id=project_id, chapter_id=chapter_id
        )
        bundle: dict[str, AcceptGateEvidence] = {}
        for gate_type in GATE_TYPES:
            row = by_gate[gate_type]
            if (int(row[4]), int(row[5]), int(row[6])) != (
                project_id, chapter_id, generation_round_id
            ):
                raise DataIntegrityError(f"{gate_type} evidence identity does not match Branch")
            if str(row[7]) != content_hash:
                raise DataIntegrityError(f"{gate_type} evidence content hash is stale")
            if str(row[8]) != CURRENT_POLICY_VERSION:
                raise DataIntegrityError(f"{gate_type} evidence policy is stale")
            if gate_type == "book_continuity" and str(row[9] or "") != predecessor_hash:
                raise DataIntegrityError("book continuity evidence predecessor Heads are stale")
            if int(row[2]) != 1:
                raise DataIntegrityError(f"chapter accept hard gate failed: {gate_type}")
            payload = json.loads(str(row[3]))
            if gate_type == "ethics" and int(require_ethics[0]) == 1:
                if payload.get("recommendation") != "approve" or payload.get("risk_level") == "blocking":
                    raise DataIntegrityError("required chapter ethics review prevents accept")
            bundle[gate_type] = AcceptGateEvidence(
                evidence_id=int(row[0]), gate_type=gate_type,
                passed=True, evidence=payload,
            )
        return bundle

    def predecessor_heads_hash(self, *, project_id: int, chapter_id: int) -> str:
        rows = self.conn.execute(
            """
            SELECT h.chapter_id, h.active_snapshot_id, h.version, s.snapshot_hash
            FROM writing_chapter_heads h
            JOIN writing_chapter_snapshots s ON s.snapshot_id = h.active_snapshot_id
            LEFT JOIN writing_chapter_snapshot_stale_marks sm
              ON sm.snapshot_id = h.active_snapshot_id
            WHERE h.project_id = ? AND h.chapter_id < ?
              AND s.sealed_at IS NOT NULL AND sm.snapshot_id IS NULL
            ORDER BY h.chapter_id
            """,
            (project_id, chapter_id),
        ).fetchall()
        payload = "".join(
            f"{int(row[0])}:{int(row[1])}:{int(row[2])}:{str(row[3])}\n"
            for row in rows
        )
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def _branch_identity(self, branch_version_id: int) -> tuple[int, int, int, str, str]:
        row = self.conn.execute(
            """
            SELECT r.project_id, r.chapter_id, r.generation_round_id,
                   bv.content_hash, bv.status
            FROM writing_chapter_candidate_branch_versions bv
            JOIN writing_chapter_candidate_branches b ON b.branch_id = bv.branch_id
            JOIN writing_chapter_generation_rounds r
              ON r.generation_round_id = b.generation_round_id
            WHERE bv.branch_version_id = ?
            """,
            (branch_version_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"unknown branch version: {branch_version_id}")
        return int(row[0]), int(row[1]), int(row[2]), str(row[3] or ""), str(row[4])

    def _assert_branch_fresh(self, branch_version_id: int) -> None:
        row = self.conn.execute(
            "SELECT 1 FROM writing_branch_version_stale_marks WHERE branch_version_id = ? "
            "UNION ALL "
            "SELECT 1 FROM writing_branch_scenes bs "
            "JOIN writing_scene_revision_stale_marks sm "
            "ON sm.scene_revision_id = bs.scene_revision_id "
            "WHERE bs.branch_version_id = ? LIMIT 1",
            (branch_version_id, branch_version_id),
        ).fetchone()
        if row is not None:
            raise DataIntegrityError("accept gate evidence cannot be recorded for stale Scene lineage")
