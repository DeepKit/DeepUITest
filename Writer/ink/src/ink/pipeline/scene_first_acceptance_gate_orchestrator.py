from __future__ import annotations

import hashlib
import json
import sqlite3

from ink.core.chapter_accept_gate_repository import ChapterAcceptGateRepository
from ink.core.chapter_snapshot_repository import ChapterHead, ChapterSnapshotRepository, _atomic
from ink.errors import DataIntegrityError


class SceneFirstAcceptanceGateOrchestrator:
    """Persist deterministic Scene/Book/Ethics evidence around literary review.

    Chapter literary evidence is written by the validation port from its raw
    multi-dimensional scores. This orchestrator deliberately refuses to invent
    that evidence from a branch status.
    """

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn
        self.repo = ChapterAcceptGateRepository(conn)

    def accept_chapter(
        self,
        *,
        branch_version_id: int,
        expected_head_version: int,
        actor: str,
        reason: str,
        preconditions_json: dict,
        selection_decision_type: str,
        selection_evidence_json: dict,
    ) -> ChapterHead:
        """Evaluate missing deterministic gates and consume them in one transaction."""

        with _atomic(self.conn):
            self.prepare_acceptance(branch_version_id=branch_version_id, actor=actor)
            return ChapterSnapshotRepository(self.conn).accept_chapter(
                branch_version_id=branch_version_id,
                expected_head_version=expected_head_version,
                actor=actor,
                reason=reason,
                preconditions_json=preconditions_json,
                selection_decision_type=selection_decision_type,
                selection_evidence_json=selection_evidence_json,
            )

    def prepare_acceptance(self, *, branch_version_id: int, actor: str) -> dict[str, int]:
        identity = self._identity(branch_version_id)
        evidence_ids: dict[str, int] = {}
        if not self._has_latest(branch_version_id, "scene_integrity"):
            scene_payload = self._scene_integrity(branch_version_id, identity[0], identity[1])
            evidence_ids["scene_integrity"] = self.repo.record_evidence(
                branch_version_id=branch_version_id,
                gate_type="scene_integrity",
                passed=True,
                evidence=scene_payload,
                producer_actor=actor,
            )
        if not self._has_latest(branch_version_id, "chapter_quality"):
            raise DataIntegrityError(
                "chapter literary evidence is missing; run Scene-first candidate validation"
            )
        if not self._has_latest(branch_version_id, "book_continuity"):
            predecessor_hash = self.repo.predecessor_heads_hash(
                project_id=identity[0], chapter_id=identity[1]
            )
            blocking = self._unresolved_book_blocking_issues(identity[0])
            evidence_ids["book_continuity"] = self.repo.record_evidence(
                branch_version_id=branch_version_id,
                gate_type="book_continuity",
                passed=not blocking,
                evidence={
                    "blocking_issues": blocking,
                    "chapter_range_end": identity[1],
                    "predecessor_heads_hash": predecessor_hash,
                },
                predecessor_heads_hash=predecessor_hash,
                producer_actor=actor,
            )
        if not self._has_latest(branch_version_id, "ethics"):
            required = int(self.conn.execute(
                "SELECT require_ethics_review FROM writing_projects WHERE project_id = ?",
                (identity[0],),
            ).fetchone()[0]) == 1
            if required:
                raise DataIntegrityError(
                    "required Scene-first ethics evidence is missing; run ethics review"
                )
            evidence_ids["ethics"] = self.repo.record_evidence(
                branch_version_id=branch_version_id,
                gate_type="ethics",
                passed=True,
                evidence={
                    "required": False,
                    "risk_level": "low",
                    "recommendation": "approve",
                    "reason": "project policy does not require chapter ethics review",
                },
                producer_actor=actor,
            )
        return evidence_ids

    def _scene_integrity(
        self, branch_version_id: int, project_id: int, chapter_id: int
    ) -> dict[str, object]:
        planned = self.conn.execute(
            "SELECT scene_id, scene_order FROM writing_scenes "
            "WHERE project_id = ? AND chapter_id = ? ORDER BY scene_order",
            (project_id, chapter_id),
        ).fetchall()
        bound = self.conn.execute(
            """
            SELECT bs.scene_id, bs.scene_order, r.text, r.text_hash,
                   c.status, r.scene_contract_id
            FROM writing_branch_scenes bs
            JOIN writing_scene_revisions r ON r.scene_revision_id = bs.scene_revision_id
            JOIN writing_scene_contracts c ON c.scene_contract_id = r.scene_contract_id
            WHERE bs.branch_version_id = ? ORDER BY bs.scene_order
            """,
            (branch_version_id,),
        ).fetchall()
        planned_pairs = [(int(row[0]), int(row[1])) for row in planned]
        bound_pairs = [(int(row[0]), int(row[1])) for row in bound]
        if not planned_pairs or planned_pairs != bound_pairs:
            raise DataIntegrityError("Branch Scene bindings do not match the planned chapter Scenes")
        expected_orders = list(range(planned_pairs[0][1], planned_pairs[0][1] + len(planned_pairs)))
        if [order for _, order in planned_pairs] != expected_orders:
            raise DataIntegrityError("chapter Scene orders must be contiguous")
        for row in bound:
            text = str(row[2])
            if not text.strip() or hashlib.sha256(text.encode("utf-8")).hexdigest() != str(row[3]):
                raise DataIntegrityError("Scene Revision text is empty or hash-mismatched")
            if str(row[4]) != "active":
                raise DataIntegrityError("Scene Revision does not reference an active Contract")
        return {
            "scene_count": len(bound),
            "scene_ids": [scene_id for scene_id, _ in bound_pairs],
            "scene_orders": [order for _, order in bound_pairs],
        }

    def _unresolved_book_blocking_issues(self, project_id: int) -> list[str]:
        row = self.conn.execute(
            """
            SELECT blocking_issue_count, issues
            FROM writing_book_check_results
            WHERE project_id = ? ORDER BY check_sequence DESC LIMIT 1
            """,
            (project_id,),
        ).fetchone()
        if row is None or int(row[0]) == 0:
            return []
        payload = json.loads(str(row[1]))
        return [str(item) for item in payload]

    def _has_latest(self, branch_version_id: int, gate_type: str) -> bool:
        return self.conn.execute(
            "SELECT 1 FROM writing_chapter_accept_gate_evidence "
            "WHERE branch_version_id = ? AND gate_type = ? LIMIT 1",
            (branch_version_id, gate_type),
        ).fetchone() is not None

    def _identity(self, branch_version_id: int) -> tuple[int, int]:
        row = self.conn.execute(
            """
            SELECT r.project_id, r.chapter_id
            FROM writing_chapter_candidate_branch_versions bv
            JOIN writing_chapter_candidate_branches b ON b.branch_id = bv.branch_id
            JOIN writing_chapter_generation_rounds r
              ON r.generation_round_id = b.generation_round_id
            WHERE bv.branch_version_id = ? AND bv.status = 'frozen'
            """,
            (branch_version_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError("Scene-first acceptance gates require a frozen Branch Version")
        return int(row[0]), int(row[1])
