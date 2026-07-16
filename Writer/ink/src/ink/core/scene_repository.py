from __future__ import annotations

import hashlib
import json
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from itertools import count
from typing import Iterator

from ink.errors import ConcurrentModificationError, DataIntegrityError
from ink.time import now_utc_iso


_SAVEPOINT_IDS = count(1)


@dataclass(frozen=True)
class SceneRevision:
    scene_revision_id: int
    scene_id: int
    parent_revision_id: int | None
    text_hash: str


class SceneRepository:
    """Controlled write path for Scene identity, contracts and immutable revisions."""

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def create_scene(
        self,
        *,
        project_id: int,
        chapter_id: int,
        logical_scene_key: str,
        scene_order: int,
    ) -> int:
        cursor = self.conn.execute(
            """
            INSERT INTO writing_scenes
                (project_id, chapter_id, logical_scene_key, scene_order, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (project_id, chapter_id, logical_scene_key, scene_order, now_utc_iso()),
        )
        return int(cursor.lastrowid)

    def create_contract(
        self,
        *,
        scene_id: int,
        version: int,
        contract_hash: str,
        source_bundle_hash: str,
        created_by: str,
        status: str = "draft",
        parent_contract_id: int | None = None,
    ) -> int:
        if status in {"active", "superseded"}:
            raise DataIntegrityError(
                "create_contract cannot activate or supersede a Scene Contract"
            )
        cursor = self.conn.execute(
            """
            INSERT INTO writing_scene_contracts
                (scene_id, version, status, contract_hash, parent_contract_id,
                 source_bundle_hash, created_by, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                scene_id,
                version,
                status,
                contract_hash,
                parent_contract_id,
                source_bundle_hash,
                created_by,
                now_utc_iso(),
            ),
        )
        return int(cursor.lastrowid)

    def activate_contract(self, scene_contract_id: int) -> None:
        row = self.conn.execute(
            "SELECT scene_id, status FROM writing_scene_contracts WHERE scene_contract_id = ?",
            (scene_contract_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"unknown scene contract: {scene_contract_id}")
        if str(row[1]) not in {"approved", "active"}:
            raise DataIntegrityError("only an approved contract may become active")
        if str(row[1]) != "active":
            reviews = self.conn.execute(
                """
                SELECT review_order, reviewer_family, visible_prior_reviews, verdict
                FROM writing_scene_contract_reviews
                WHERE scene_contract_id = ? AND review_order IN (1, 2, 3)
                ORDER BY review_order
                """,
                (scene_contract_id,),
            ).fetchall()
            if (
                len(reviews) != 3
                or any(str(review[3]) != "approve" for review in reviews)
                or any(int(review[2]) != 0 for review in reviews)
                or len({str(review[1]) for review in reviews}) != 3
            ):
                raise DataIntegrityError(
                    "active contract requires three blind approve reviews from distinct families"
                )
            layer_counts = {
                str(layer): int(count)
                for layer, count in self.conn.execute(
                    """
                    SELECT layer, count(*)
                    FROM writing_scene_contract_clauses
                    WHERE scene_contract_id = ?
                    GROUP BY layer
                    """,
                    (scene_contract_id,),
                ).fetchall()
            }
            if (
                layer_counts.get("hard_constraint", 0) < 1
                or layer_counts.get("source_dna", 0) < 1
                or layer_counts.get("soft_goal", 0) < 1
                or layer_counts.get("creative_opening", 0) < 2
            ):
                raise DataIntegrityError(
                    "active contract requires complete four-layer clauses"
                )
        now = now_utc_iso()
        with _atomic(self.conn):
            superseded_ids = tuple(
                int(item[0])
                for item in self.conn.execute(
                    """
                    SELECT scene_contract_id
                    FROM writing_scene_contracts
                    WHERE scene_id = ? AND status = 'active' AND scene_contract_id <> ?
                    ORDER BY scene_contract_id
                    """,
                    (int(row[0]), scene_contract_id),
                ).fetchall()
            )
            self.conn.execute(
                """
                UPDATE writing_scene_contracts
                SET status = 'superseded', superseded_at = ?
                WHERE scene_id = ? AND status = 'active' AND scene_contract_id <> ?
                """,
                (now, int(row[0]), scene_contract_id),
            )
            self.conn.execute(
                """
                UPDATE writing_scene_contracts
                SET status = 'active', activated_at = ?, superseded_at = NULL
                WHERE scene_contract_id = ?
                """,
                (now, scene_contract_id),
            )
            if superseded_ids:
                from ink.core.scene_stale_propagation import SceneStalePropagationManager

                scene = self.conn.execute(
                    "SELECT project_id FROM writing_scenes WHERE scene_id = ?",
                    (int(row[0]),),
                ).fetchone()
                stale_manager = SceneStalePropagationManager(self.conn)
                for superseded_id in superseded_ids:
                    result = stale_manager.mark_contract_superseded(
                        source_scene_contract_id=superseded_id,
                        replacement_scene_contract_id=scene_contract_id,
                        reason=f"Scene Contract {superseded_id} superseded by {scene_contract_id}",
                    )
                    self.conn.execute(
                        """
                        INSERT INTO writing_runtime_events
                            (project_id, session_id, run_id, shot_id, event_type,
                             event_payload, created_at)
                        VALUES (?, NULL, NULL, NULL, 'scene_contract_superseded', ?, ?)
                        """,
                        (
                            int(scene[0]),
                            json.dumps(
                                {
                                    "source_scene_contract_id": superseded_id,
                                    "replacement_scene_contract_id": scene_contract_id,
                                    "stale_revision_ids": result.revision_ids,
                                    "stale_branch_version_ids": result.branch_version_ids,
                                    "stale_snapshot_ids": result.snapshot_ids,
                                    "cancelled_repair_task_ids": result.cancelled_repair_task_ids,
                                },
                                ensure_ascii=False,
                                sort_keys=True,
                            ),
                            now,
                        ),
                    )

    def add_contract_clause(
        self,
        *,
        scene_contract_id: int,
        layer: str,
        clause_key: str,
        clause_text: str,
        severity: str,
        authority_rank: int = 0,
        confidence: float = 1.0,
        source_asset_id: int | None = None,
        source_anchor: str | None = None,
        risk_if_removed: str | None = None,
        supersedes_clause_id: int | None = None,
    ) -> int:
        cursor = self.conn.execute(
            """
            INSERT INTO writing_scene_contract_clauses
                (scene_contract_id, layer, clause_key, clause_text, severity,
                 source_asset_id, source_anchor, authority_rank, confidence,
                 risk_if_removed, supersedes_clause_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                scene_contract_id,
                layer,
                clause_key,
                clause_text,
                severity,
                source_asset_id,
                source_anchor,
                authority_rank,
                confidence,
                risk_if_removed,
                supersedes_clause_id,
                now_utc_iso(),
            ),
        )
        return int(cursor.lastrowid)

    def create_revision(
        self,
        *,
        scene_id: int,
        branch_version_id: int,
        scene_order: int,
        expected_parent_revision_id: int | None,
        scene_contract_id: int,
        text: str,
        actor_type: str,
        actor_id: str,
        change_reason: str,
        generation_task_id: int | None = None,
        repair_task_id: int | None = None,
        context_snapshot_id: int | None = None,
    ) -> SceneRevision:
        """Insert a revision and advance only the supplied branch-local Scene head."""

        branch = self.conn.execute(
            """
            SELECT bv.status, r.project_id, r.chapter_id
            FROM writing_chapter_candidate_branch_versions bv
            JOIN writing_chapter_candidate_branches b ON b.branch_id = bv.branch_id
            JOIN writing_chapter_generation_rounds r
              ON r.generation_round_id = b.generation_round_id
            WHERE bv.branch_version_id = ?
            """,
            (branch_version_id,),
        ).fetchone()
        if branch is None:
            raise DataIntegrityError(f"unknown branch version: {branch_version_id}")
        if str(branch[0]) != "building":
            raise DataIntegrityError("cannot write a revision into a frozen branch version")

        scene = self.conn.execute(
            "SELECT project_id, chapter_id FROM writing_scenes WHERE scene_id = ?",
            (scene_id,),
        ).fetchone()
        if scene is None:
            raise DataIntegrityError(f"unknown scene: {scene_id}")
        if (int(scene[0]), int(scene[1])) != (int(branch[1]), int(branch[2])):
            raise DataIntegrityError("scene and branch must belong to the same chapter")

        contract = self.conn.execute(
            """
            SELECT 1 FROM writing_scene_contracts
            WHERE scene_contract_id = ? AND scene_id = ? AND status = 'active'
            """,
            (scene_contract_id, scene_id),
        ).fetchone()
        if contract is None:
            raise DataIntegrityError("scene revision requires the active contract for that scene")

        binding = self.conn.execute(
            """
            SELECT scene_revision_id
            FROM writing_branch_scenes
            WHERE branch_version_id = ? AND scene_id = ?
            """,
            (branch_version_id, scene_id),
        ).fetchone()
        actual_parent = None if binding is None else int(binding[0])
        if actual_parent != expected_parent_revision_id:
            raise ConcurrentModificationError(
                "branch-local expected parent does not match the bound Scene revision"
            )

        if not text.strip():
            raise ValueError("scene revision text must not be empty")
        if actor_type == "ai":
            self._validate_ai_task(
                generation_task_id=generation_task_id,
                repair_task_id=repair_task_id,
                project_id=int(scene[0]),
                chapter_id=int(scene[1]),
                scene_id=scene_id,
                branch_version_id=branch_version_id,
                scene_contract_id=scene_contract_id,
                expected_parent_revision_id=expected_parent_revision_id,
            )
        text_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
        now = now_utc_iso()
        with _atomic(self.conn):
            cursor = self.conn.execute(
                """
                INSERT INTO writing_scene_revisions
                    (scene_id, parent_revision_id, scene_contract_id, generation_task_id,
                     repair_task_id, context_snapshot_id, text, text_hash, actor_type,
                     actor_id, change_reason, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    scene_id,
                    expected_parent_revision_id,
                    scene_contract_id,
                    generation_task_id,
                    repair_task_id,
                    context_snapshot_id,
                    text,
                    text_hash,
                    actor_type,
                    actor_id,
                    change_reason,
                    now,
                ),
            )
            revision_id = int(cursor.lastrowid)
            if binding is None:
                self.conn.execute(
                    """
                    INSERT INTO writing_branch_scenes
                        (branch_version_id, scene_order, scene_id, scene_revision_id)
                    VALUES (?, ?, ?, ?)
                    """,
                    (branch_version_id, scene_order, scene_id, revision_id),
                )
            else:
                updated = self.conn.execute(
                    """
                    UPDATE writing_branch_scenes
                    SET scene_order = ?, scene_revision_id = ?
                    WHERE branch_version_id = ? AND scene_id = ? AND scene_revision_id = ?
                    """,
                    (
                        scene_order,
                        revision_id,
                        branch_version_id,
                        scene_id,
                        expected_parent_revision_id,
                    ),
                )
                if updated.rowcount != 1:
                    raise ConcurrentModificationError(
                        "branch-local Scene head changed during revision"
                    )
        from ink.core.scene_stale_propagation import SceneStalePropagationManager

        SceneStalePropagationManager(self.conn).refresh_building_branch_stale(
            branch_version_id
        )
        return SceneRevision(
            scene_revision_id=revision_id,
            scene_id=scene_id,
            parent_revision_id=expected_parent_revision_id,
            text_hash=text_hash,
        )

    def bind_existing_revision(
        self,
        *,
        branch_version_id: int,
        scene_order: int,
        scene_id: int,
        scene_revision_id: int,
    ) -> None:
        """Seed a building branch from a canonical/parent revision before it diverges."""

        row = self.conn.execute(
            """
            SELECT bv.status, sr.scene_id
            FROM writing_chapter_candidate_branch_versions bv
            JOIN writing_scene_revisions sr ON sr.scene_revision_id = ?
            WHERE bv.branch_version_id = ?
            """,
            (scene_revision_id, branch_version_id),
        ).fetchone()
        if row is None:
            raise DataIntegrityError("unknown branch version or Scene revision")
        if str(row[0]) != "building":
            raise DataIntegrityError("cannot bind into a frozen branch version")
        if int(row[1]) != scene_id:
            raise DataIntegrityError("revision does not belong to the supplied Scene")
        self.conn.execute(
            """
            INSERT INTO writing_branch_scenes
                (branch_version_id, scene_order, scene_id, scene_revision_id)
            VALUES (?, ?, ?, ?)
            """,
            (branch_version_id, scene_order, scene_id, scene_revision_id),
        )

    # ── P0-3: four-layer assembly, dual-master review, amendment ──

    def assemble_four_layer_contract(
        self,
        *,
        scene_contract_id: int,
        hard_constraints: list[dict],
        source_dna: list[dict],
        soft_goals: list[dict],
        creative_openings: list[dict],
    ) -> None:
        """Bulk-insert clauses across all four layers in one transaction.

        Each clause dict may carry: clause_key, clause_text, severity,
        authority_rank, confidence, source_asset_id, source_anchor,
        risk_if_removed, supersedes_clause_id. layer is fixed by the bucket.
        """
        layers = (
            ("hard_constraint", hard_constraints),
            ("source_dna", source_dna),
            ("soft_goal", soft_goals),
            ("creative_opening", creative_openings),
        )
        # creative_opening requires at least two concrete openings (design.md §5.1.4).
        if len(creative_openings) < 2:
            raise DataIntegrityError(
                "a Scene Contract needs at least two creative_opening clauses"
            )
        with _atomic(self.conn):
            for layer, clauses in layers:
                for clause in clauses:
                    self.add_contract_clause(
                        scene_contract_id=scene_contract_id,
                        layer=layer,
                        clause_key=clause["clause_key"],
                        clause_text=clause["clause_text"],
                        severity=clause.get("severity", "hard" if layer == "hard_constraint" else "soft"),
                        authority_rank=clause.get("authority_rank", 0),
                        confidence=clause.get("confidence", 1.0),
                        source_asset_id=clause.get("source_asset_id"),
                        source_anchor=clause.get("source_anchor"),
                        risk_if_removed=clause.get("risk_if_removed"),
                        supersedes_clause_id=clause.get("supersedes_clause_id"),
                    )

    def _contract_status(self, scene_contract_id: int) -> str:
        row = self.conn.execute(
            "SELECT status FROM writing_scene_contracts WHERE scene_contract_id = ?",
            (scene_contract_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"unknown scene contract: {scene_contract_id}")
        return str(row[0])

    def _set_contract_status(self, scene_contract_id: int, status: str) -> None:
        self.conn.execute(
            "UPDATE writing_scene_contracts SET status = ? WHERE scene_contract_id = ?",
            (status, scene_contract_id),
        )

    def record_contract_review(
        self,
        *,
        scene_contract_id: int,
        reviewer_model: str,
        reviewer_family: str,
        prompt_hash: str,
        blind_context_hash: str,
        visible_prior_reviews: int,
        verdict: str,
        evidence_json: str,
        transition_to: str | None = None,
    ) -> int:
        """Insert a blind contract review row. ``review_order`` auto-increments per contract.

        The family-differ invariant (INV-CONTRACT-003) is enforced by
        :meth:`independent_review_contract`, not here — the architect's own
        self-check legitimately reuses the architect's family.
        """
        if verdict not in {"approve", "revise", "reject"}:
            raise DataIntegrityError(f"invalid verdict: {verdict}")
        existing = int(self.conn.execute(
            "SELECT COALESCE(MAX(review_order), 0) FROM writing_scene_contract_reviews WHERE scene_contract_id = ?",
            (scene_contract_id,),
        ).fetchone()[0])
        review_order = existing + 1
        cursor = self.conn.execute(
            """
            INSERT INTO writing_scene_contract_reviews
                (scene_contract_id, reviewer_model, reviewer_family, prompt_hash,
                 blind_context_hash, visible_prior_reviews, review_order, verdict,
                 evidence_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                scene_contract_id, reviewer_model, reviewer_family, prompt_hash,
                blind_context_hash, visible_prior_reviews, review_order, verdict,
                evidence_json, now_utc_iso(),
            ),
        )
        if transition_to is not None:
            self._set_contract_status(scene_contract_id, transition_to)
        return int(cursor.lastrowid)

    def self_check_contract(
        self, *, scene_contract_id: int, reviewer_model: str, reviewer_family: str,
        prompt_hash: str, blind_context_hash: str, verdict: str, evidence_json: str,
    ) -> int:
        """Architect's self-check is review_order=1 and moves draft → self_checked."""
        if self._contract_status(scene_contract_id) != "draft":
            raise DataIntegrityError("self_check expects a draft contract")
        return self.record_contract_review(
            scene_contract_id=scene_contract_id,
            reviewer_model=reviewer_model, reviewer_family=reviewer_family,
            prompt_hash=prompt_hash, blind_context_hash=blind_context_hash,
            visible_prior_reviews=0, verdict=verdict, evidence_json=evidence_json,
            transition_to="self_checked",
        )

    def independent_review_contract(
        self, *, scene_contract_id: int, reviewer_model: str, reviewer_family: str,
        prompt_hash: str, blind_context_hash: str, verdict: str, evidence_json: str,
    ) -> int:
        """Add an independent blind review from a previously unused model family.

        The first independent review moves self_checked → under_review; the second
        stays under_review. Blind context keeps every review isolated from prior
        verdicts (visible_prior_reviews=0).
        """
        status = self._contract_status(scene_contract_id)
        if status not in {"self_checked", "under_review"}:
            raise DataIntegrityError(
                "independent_review expects a self_checked or under_review contract"
            )
        architect = self.conn.execute(
            "SELECT created_by FROM writing_scene_contracts WHERE scene_contract_id = ?",
            (scene_contract_id,),
        ).fetchone()
        architect_family = str(architect[0]).split(":", 1)[-1] if str(architect[0]) else ""
        used_families = {
            str(row[0])
            for row in self.conn.execute(
                "SELECT reviewer_family FROM writing_scene_contract_reviews "
                "WHERE scene_contract_id = ?",
                (scene_contract_id,),
            ).fetchall()
        }
        if reviewer_family in used_families or (
            architect_family and reviewer_family == architect_family
        ):
            raise DataIntegrityError(
                "independent reviewer family must be unused and differ from the architect family"
            )
        return self.record_contract_review(
            scene_contract_id=scene_contract_id,
            reviewer_model=reviewer_model, reviewer_family=reviewer_family,
            prompt_hash=prompt_hash, blind_context_hash=blind_context_hash,
            visible_prior_reviews=0, verdict=verdict, evidence_json=evidence_json,
            transition_to="under_review",
        )

    def human_activate_contract(self, *, scene_contract_id: int, actor: str) -> None:
        """Human-only activation: under_review (or revision_required) → active.

        Emits a ``contract_activated`` runtime event in the same transaction.
        Supersedes any prior active contract on the same scene via the existing
        partial-unique-index swap performed by ``activate_contract``.
        """
        from ink.core.actor_guard import assert_can_activate_contract
        assert_can_activate_contract(actor)
        status = self._contract_status(scene_contract_id)
        if status not in {"under_review", "revision_required", "approved"}:
            raise DataIntegrityError(
                f"contract {scene_contract_id} status '{status}' cannot be activated"
            )
        with _atomic(self.conn):
            self._set_contract_status(scene_contract_id, "approved")
            self.activate_contract(scene_contract_id)
            row = self.conn.execute(
                "SELECT c.scene_id, s.project_id FROM writing_scene_contracts c "
                "JOIN writing_scenes s ON s.scene_id = c.scene_id "
                "WHERE c.scene_contract_id = ?",
                (scene_contract_id,),
            ).fetchone()
            project_id = int(row[1]) if row else None
            self.conn.execute(
                """
                INSERT INTO writing_runtime_events
                    (project_id, session_id, run_id, shot_id, event_type, event_payload, created_at)
                VALUES (?, NULL, NULL, NULL, 'contract_activated', ?, ?)
                """,
                (project_id, f'{{"scene_contract_id": {scene_contract_id}, "actor": "{actor}"}}', now_utc_iso()),
            )

    def submit_amendment(
        self, *, scene_contract_id: int, amending_actor: str,
        amendment_reason: str, clause_changes_json: str,
    ) -> int:
        """Record a human amendment request without mutating the active contract."""
        from ink.core.actor_guard import assert_human_actor

        assert_human_actor(amending_actor, action="amend scene contract")
        if not amendment_reason.strip():
            raise DataIntegrityError("amendment reason must not be empty")
        try:
            json.loads(clause_changes_json)
        except (TypeError, json.JSONDecodeError) as exc:
            raise DataIntegrityError("amendment clause changes must be valid JSON") from exc
        contract = self.conn.execute(
            """
            SELECT s.project_id, c.status
            FROM writing_scene_contracts c
            JOIN writing_scenes s ON s.scene_id = c.scene_id
            WHERE c.scene_contract_id = ?
            """,
            (scene_contract_id,),
        ).fetchone()
        if contract is None:
            raise DataIntegrityError(f"unknown Scene Contract: {scene_contract_id}")
        if str(contract[1]) != "active":
            raise DataIntegrityError("only an active Scene Contract may be amended")
        now = now_utc_iso()
        with _atomic(self.conn):
            cursor = self.conn.execute(
                """
                INSERT INTO writing_scene_contract_amendments
                    (scene_contract_id, amending_actor, amendment_reason,
                     clause_changes_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    scene_contract_id,
                    amending_actor,
                    amendment_reason,
                    clause_changes_json,
                    now,
                ),
            )
            amendment_id = int(cursor.lastrowid)
            self.conn.execute(
                """
                INSERT INTO writing_runtime_events
                    (project_id, session_id, run_id, shot_id, event_type,
                     event_payload, created_at)
                VALUES (?, NULL, NULL, NULL, 'scene_contract_amendment_submitted', ?, ?)
                """,
                (
                    int(contract[0]),
                    json.dumps(
                        {
                            "amendment_id": amendment_id,
                            "scene_contract_id": scene_contract_id,
                            "actor": amending_actor,
                            "reason": amendment_reason,
                        },
                        ensure_ascii=False,
                        sort_keys=True,
                    ),
                    now,
                ),
            )
        return amendment_id

    def create_repair_task(
        self,
        *,
        project_id: int,
        chapter_id: int,
        scene_id: int,
        branch_version_id: int,
        source_revision_id: int | None,
        scene_contract_id: int,
        issue: str,
        created_by: str,
    ) -> int:
        """Persist the auditable scope for one AI Scene repair."""
        if not issue.strip():
            raise DataIntegrityError("repair task issue must not be empty")
        scene = self.conn.execute(
            "SELECT project_id, chapter_id FROM writing_scenes WHERE scene_id = ?",
            (scene_id,),
        ).fetchone()
        if scene is None or (int(scene[0]), int(scene[1])) != (project_id, chapter_id):
            raise DataIntegrityError("repair task scope does not match its Scene")
        binding = self.conn.execute(
            """
            SELECT scene_revision_id
            FROM writing_branch_scenes
            WHERE branch_version_id = ? AND scene_id = ?
            """,
            (branch_version_id, scene_id),
        ).fetchone()
        current_revision_id = int(binding[0]) if binding is not None else None
        if current_revision_id != source_revision_id:
            raise DataIntegrityError("repair task source is not the branch-local Scene head")
        contract = self.conn.execute(
            """
            SELECT 1 FROM writing_scene_contracts
            WHERE scene_contract_id = ? AND scene_id = ? AND status = 'active'
            """,
            (scene_contract_id, scene_id),
        ).fetchone()
        if contract is None:
            raise DataIntegrityError("repair task requires the Scene's active contract")
        cursor = self.conn.execute(
            """
            INSERT INTO writing_scene_repair_tasks
                (project_id, chapter_id, scene_id, branch_version_id,
                 source_revision_id, scene_contract_id, issue, status,
                 created_by, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'planned', ?, ?)
            """,
            (
                project_id,
                chapter_id,
                scene_id,
                branch_version_id,
                source_revision_id,
                scene_contract_id,
                issue.strip(),
                created_by,
                now_utc_iso(),
            ),
        )
        return int(cursor.lastrowid)

    def _validate_ai_task(
        self, *, generation_task_id: int | None, repair_task_id: int | None,
        project_id: int, chapter_id: int, scene_id: int,
        branch_version_id: int, scene_contract_id: int,
        expected_parent_revision_id: int | None,
    ) -> None:
        """Require exactly one real, in-scope, eligible generation or repair task."""
        if (generation_task_id is None) == (repair_task_id is None):
            raise DataIntegrityError(
                "AI Scene revisions require exactly one generation or repair task"
            )
        parent_is_stale = (
            expected_parent_revision_id is not None
            and self.conn.execute(
                "SELECT 1 FROM writing_scene_revision_stale_marks "
                "WHERE scene_revision_id = ?",
                (expected_parent_revision_id,),
            ).fetchone()
            is not None
        )
        if generation_task_id is not None:
            if parent_is_stale:
                raise DataIntegrityError(
                    "generation task cannot extend a stale Scene revision; use a repair task"
                )
            row = self.conn.execute(
                """
                SELECT r.project_id, r.chapter_id, b.status
                FROM writing_chapter_candidate_branches b
                JOIN writing_chapter_generation_rounds r
                  ON r.generation_round_id = b.generation_round_id
                JOIN writing_chapter_candidate_branch_versions bv
                  ON bv.branch_id = b.branch_id
                WHERE b.branch_id = ? AND bv.branch_version_id = ?
                """,
                (generation_task_id, branch_version_id),
            ).fetchone()
            if row is None:
                raise DataIntegrityError(
                    f"generation_task_id {generation_task_id} does not reference the target branch"
                )
            if (int(row[0]), int(row[1])) != (project_id, chapter_id):
                raise DataIntegrityError(
                    "generation_task_id scope does not match the scene's project/chapter"
                )
            if str(row[2]) == "rejected":
                raise DataIntegrityError("generation_task_id is not eligible for AI revision")
            return

        row = self.conn.execute(
            """
            SELECT project_id, chapter_id, scene_id, branch_version_id,
                   source_revision_id, scene_contract_id, status
            FROM writing_scene_repair_tasks
            WHERE repair_task_id = ?
            """,
            (repair_task_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(
                f"repair_task_id {repair_task_id} does not reference a real repair task"
            )
        actual_scope = (int(row[0]), int(row[1]), int(row[2]), int(row[3]))
        expected_scope = (project_id, chapter_id, scene_id, branch_version_id)
        if actual_scope != expected_scope:
            raise DataIntegrityError("repair_task_id scope does not match the target Scene branch")
        if str(row[6]) not in {"planned", "running"}:
            raise DataIntegrityError("repair_task_id is not eligible for AI revision")
        if row[4] != expected_parent_revision_id or int(row[5]) != scene_contract_id:
            raise DataIntegrityError("repair_task_id lineage does not match the requested revision")

    # ── P0-5: guidance cards + fact proposals ──

    def create_guidance_card(
        self, *, project_id: int, chapter_id: int, scene_id: int | None,
        card_type: str, trigger_context: str, guidance_text: str,
        model_name: str, prompt_hash: str,
    ) -> int:
        cursor = self.conn.execute(
            """
            INSERT INTO writing_guidance_cards
                (project_id, chapter_id, scene_id, card_type, trigger_context,
                 guidance_text, model_name, prompt_hash, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?)
            """,
            (project_id, chapter_id, scene_id, card_type, trigger_context,
             guidance_text, model_name, prompt_hash, now_utc_iso()),
        )
        return int(cursor.lastrowid)

    def dismiss_guidance_card(self, *, guidance_card_id: int) -> None:
        updated = self.conn.execute(
            "UPDATE writing_guidance_cards SET status = 'dismissed' WHERE guidance_card_id = ?",
            (guidance_card_id,),
        ).rowcount
        if updated == 0:
            raise DataIntegrityError(f"unknown guidance card: {guidance_card_id}")

    def create_fact_proposal(
        self, *, project_id: int, chapter_id: int, scene_id: int | None,
        proposed_fact: str, fact_type: str, source_text: str,
        source_revision_id: int | None, confidence: float, model_name: str,
    ) -> int:
        cursor = self.conn.execute(
            """
            INSERT INTO writing_fact_proposals
                (project_id, chapter_id, scene_id, proposed_fact, fact_type,
                 source_text, source_revision_id, confidence, status, model_name, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'proposed', ?, ?)
            """,
            (project_id, chapter_id, scene_id, proposed_fact, fact_type,
             source_text, source_revision_id, confidence, model_name, now_utc_iso()),
        )
        return int(cursor.lastrowid)

    def confirm_fact_proposal(self, *, fact_proposal_id: int, actor: str) -> int:
        """Human-gated confirmation: proposed → confirmed, and writes a
        ``writing_fact_anchors`` row so the fact becomes enforceable by hard gates."""
        from ink.core.actor_guard import assert_can_confirm_fact
        assert_can_confirm_fact(actor)
        row = self.conn.execute(
            "SELECT project_id, chapter_id, scene_id, proposed_fact, fact_type, source_text, "
            "source_revision_id, confidence, status "
            "FROM writing_fact_proposals WHERE fact_proposal_id = ?",
            (fact_proposal_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"unknown fact proposal: {fact_proposal_id}")
        if str(row[8]) != "proposed":
            raise DataIntegrityError("only a proposed fact can be confirmed")
        with _atomic(self.conn):
            self.conn.execute(
                "UPDATE writing_fact_proposals SET status = 'confirmed' WHERE fact_proposal_id = ?",
                (fact_proposal_id,),
            )
            anchor_cursor = self.conn.execute(
                """
                INSERT OR IGNORE INTO writing_fact_anchors
                    (project_id, shot_id, revision_id, fact_text, source_span,
                     confidence, status, created_at)
                VALUES (?, NULL, ?, ?, ?, ?, 'confirmed', ?)
                """,
                (int(row[0]), row[6], str(row[3]), str(row[5])[:120],
                 float(row[7]), now_utc_iso()),
            )
            return int(anchor_cursor.lastrowid)

    def reject_fact_proposal(self, *, fact_proposal_id: int, actor: str) -> None:
        from ink.core.actor_guard import assert_human_actor
        assert_human_actor(actor, action="reject fact proposal")
        updated = self.conn.execute(
            "UPDATE writing_fact_proposals SET status = 'rejected' WHERE fact_proposal_id = ?",
            (fact_proposal_id,),
        ).rowcount
        if updated == 0:
            raise DataIntegrityError(f"unknown fact proposal: {fact_proposal_id}")


@contextmanager
def _atomic(conn: sqlite3.Connection) -> Iterator[None]:
    if conn.in_transaction:
        name = f"ink_scene_revision_{next(_SAVEPOINT_IDS)}"
        conn.execute(f"SAVEPOINT {name}")
        try:
            yield
        except Exception:
            conn.execute(f"ROLLBACK TO SAVEPOINT {name}")
            conn.execute(f"RELEASE SAVEPOINT {name}")
            raise
        else:
            conn.execute(f"RELEASE SAVEPOINT {name}")
        return

    conn.execute("BEGIN")
    try:
        yield
    except Exception:
        conn.rollback()
        raise
    else:
        conn.commit()
