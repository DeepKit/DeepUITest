from __future__ import annotations

import sqlite3
from dataclasses import dataclass

from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


@dataclass(frozen=True)
class SceneStaleMarkResult:
    revision_ids: tuple[int, ...]
    branch_version_ids: tuple[int, ...]
    snapshot_ids: tuple[int, ...]
    cancelled_repair_task_ids: tuple[int, ...]


class SceneStalePropagationManager:
    """Derive Scene-first stale state without mutating immutable artifacts."""

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def mark_contract_superseded(
        self,
        *,
        source_scene_contract_id: int,
        replacement_scene_contract_id: int,
        reason: str,
    ) -> SceneStaleMarkResult:
        if not reason.strip():
            raise DataIntegrityError("stale reason must not be empty")
        source = self.conn.execute(
            "SELECT scene_id FROM writing_scene_contracts WHERE scene_contract_id = ?",
            (source_scene_contract_id,),
        ).fetchone()
        replacement = self.conn.execute(
            "SELECT scene_id, status FROM writing_scene_contracts WHERE scene_contract_id = ?",
            (replacement_scene_contract_id,),
        ).fetchone()
        if source is None or replacement is None:
            raise DataIntegrityError("stale propagation requires real Scene Contracts")
        if int(source[0]) != int(replacement[0]):
            raise DataIntegrityError("replacement contract must belong to the same Scene")
        if str(replacement[1]) != "active":
            raise DataIntegrityError("replacement contract must be active")
        return self._propagate_from_contracts(
            source_contract_ids=(source_scene_contract_id,),
            replacement_contract_id=replacement_scene_contract_id,
            reason=reason,
        )

    def mark_fact_changed(
        self,
        *,
        fact_anchor_id: int,
        reason: str,
    ) -> SceneStaleMarkResult:
        """Mark every Scene Contract that bound the changed fact version stale.

        Unlike Contract supersede, a Fact change does **not** create a new
        Contract nor mark any Contract ``superseded`` — the Contract itself
        remains ``active``; only its derivations (Revisions/Branch Versions/
        Snapshots derived from the now-stale fact version) become stale with a
        NULL ``replacement_scene_contract_id``. Consumers branch on stale
        row existence, not on replacement non-nullness.
        """
        if not reason.strip():
            raise DataIntegrityError("stale reason must not be empty")
        anchor = self.conn.execute(
            "SELECT anchor_id FROM writing_fact_anchors WHERE anchor_id = ?",
            (fact_anchor_id,),
        ).fetchone()
        if anchor is None:
            raise DataIntegrityError(f"unknown fact anchor: {fact_anchor_id}")
        contract_rows = self.conn.execute(
            "SELECT DISTINCT scene_contract_id FROM writing_contract_fact_bindings "
            "WHERE fact_anchor_id = ? ORDER BY scene_contract_id",
            (fact_anchor_id,),
        ).fetchall()
        contract_ids = tuple(int(r[0]) for r in contract_rows)
        if not contract_ids:
            # No Contract ever bound this fact → nothing to propagate.
            return SceneStaleMarkResult((), (), (), ())
        return self._propagate_from_contracts(
            source_contract_ids=contract_ids,
            replacement_contract_id=None,
            reason=reason,
        )

    def _propagate_from_contracts(
        self,
        *,
        source_contract_ids: tuple[int, ...],
        replacement_contract_id: int | None,
        reason: str,
    ) -> SceneStaleMarkResult:
        """Shared downstream propagation for both Contract- and Fact-supersede.

        Finds Revisions derived from the given source Contracts, expands to
        Branch Versions and Snapshots, writes the three stale_marks rows
        (replacement NULL for Fact-supersede), and cancels running repair
        tasks bound to those Contracts.
        """
        placeholders = ",".join("?" for _ in source_contract_ids)
        revision_ids = tuple(
            int(row[0])
            for row in self.conn.execute(
                f"SELECT scene_revision_id FROM writing_scene_revisions "
                f"WHERE scene_contract_id IN ({placeholders}) ORDER BY scene_revision_id",
                source_contract_ids,
            ).fetchall()
        )
        branch_version_ids = self._branch_versions_for_revisions(revision_ids)
        snapshot_ids = self._snapshots_for_revisions(revision_ids)
        now = now_utc_iso()

        # revision → (the single source Contract that derived it) for per-row
        # source_scene_contract_id accuracy when multiple Contracts are involved.
        rev_to_contract = {}
        if revision_ids:
            rev_placeholders = ",".join("?" for _ in revision_ids)
            rev_to_contract = dict(
                self.conn.execute(
                    f"SELECT scene_revision_id, scene_contract_id "
                    f"FROM writing_scene_revisions "
                    f"WHERE scene_revision_id IN ({rev_placeholders})",
                    revision_ids,
                ).fetchall()
            )

        self.conn.executemany(
            """
            INSERT INTO writing_scene_revision_stale_marks
                (scene_revision_id, source_scene_contract_id,
                 replacement_scene_contract_id, stale_reason, marked_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(scene_revision_id) DO UPDATE SET
                source_scene_contract_id = excluded.source_scene_contract_id,
                replacement_scene_contract_id = excluded.replacement_scene_contract_id,
                stale_reason = excluded.stale_reason,
                marked_at = excluded.marked_at
            """,
            [
                (
                    revision_id,
                    rev_to_contract.get(revision_id, source_contract_ids[0]),
                    replacement_contract_id,
                    reason,
                    now,
                )
                for revision_id in revision_ids
            ],
        )
        self.conn.executemany(
            """
            INSERT INTO writing_branch_version_stale_marks
                (branch_version_id, source_scene_contract_id,
                 replacement_scene_contract_id, stale_reason, marked_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(branch_version_id) DO UPDATE SET
                source_scene_contract_id = excluded.source_scene_contract_id,
                replacement_scene_contract_id = excluded.replacement_scene_contract_id,
                stale_reason = excluded.stale_reason,
                marked_at = excluded.marked_at
            """,
            [
                (
                    branch_version_id,
                    source_contract_ids[0],
                    replacement_contract_id,
                    reason,
                    now,
                )
                for branch_version_id in branch_version_ids
            ],
        )
        self.conn.executemany(
            """
            INSERT INTO writing_chapter_snapshot_stale_marks
                (snapshot_id, source_scene_contract_id,
                 replacement_scene_contract_id, stale_reason, marked_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(snapshot_id) DO UPDATE SET
                source_scene_contract_id = excluded.source_scene_contract_id,
                replacement_scene_contract_id = excluded.replacement_scene_contract_id,
                stale_reason = excluded.stale_reason,
                marked_at = excluded.marked_at
            """,
            [
                (
                    snapshot_id,
                    source_contract_ids[0],
                    replacement_contract_id,
                    reason,
                    now,
                )
                for snapshot_id in snapshot_ids
            ],
        )

        cancelled_rows = self.conn.execute(
            f"""
            SELECT repair_task_id
            FROM writing_scene_repair_tasks
            WHERE scene_contract_id IN ({placeholders}) AND status IN ('planned', 'running')
            ORDER BY repair_task_id
            """,
            source_contract_ids,
        ).fetchall()
        cancelled_repair_task_ids = tuple(int(row[0]) for row in cancelled_rows)
        if cancelled_repair_task_ids:
            self.conn.execute(
                f"""
                UPDATE writing_scene_repair_tasks
                SET status = 'cancelled', completed_at = ?
                WHERE scene_contract_id IN ({placeholders})
                  AND status IN ('planned', 'running')
                """,
                (now, *source_contract_ids),
            )

        return SceneStaleMarkResult(
            revision_ids=revision_ids,
            branch_version_ids=branch_version_ids,
            snapshot_ids=snapshot_ids,
            cancelled_repair_task_ids=cancelled_repair_task_ids,
        )

    def refresh_building_branch_stale(self, branch_version_id: int) -> bool:
        row = self.conn.execute(
            "SELECT status FROM writing_chapter_candidate_branch_versions "
            "WHERE branch_version_id = ?",
            (branch_version_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"unknown branch version: {branch_version_id}")
        has_stale = self.branch_contains_stale_revision(branch_version_id)
        if str(row[0]) == "building" and not has_stale:
            self.conn.execute(
                "DELETE FROM writing_branch_version_stale_marks WHERE branch_version_id = ?",
                (branch_version_id,),
            )
        return has_stale

    def branch_contains_stale_revision(self, branch_version_id: int) -> bool:
        return self.conn.execute(
            """
            SELECT 1
            FROM writing_branch_scenes bs
            JOIN writing_scene_revision_stale_marks sm
              ON sm.scene_revision_id = bs.scene_revision_id
            WHERE bs.branch_version_id = ?
            LIMIT 1
            """,
            (branch_version_id,),
        ).fetchone() is not None

    def _branch_versions_for_revisions(
        self, revision_ids: tuple[int, ...]
    ) -> tuple[int, ...]:
        if not revision_ids:
            return ()
        placeholders = ",".join("?" for _ in revision_ids)
        return tuple(
            int(row[0])
            for row in self.conn.execute(
                f"SELECT DISTINCT branch_version_id FROM writing_branch_scenes "
                f"WHERE scene_revision_id IN ({placeholders}) ORDER BY branch_version_id",
                revision_ids,
            ).fetchall()
        )

    def _snapshots_for_revisions(
        self, revision_ids: tuple[int, ...]
    ) -> tuple[int, ...]:
        if not revision_ids:
            return ()
        placeholders = ",".join("?" for _ in revision_ids)
        return tuple(
            int(row[0])
            for row in self.conn.execute(
                f"SELECT DISTINCT snapshot_id FROM writing_chapter_snapshot_scenes "
                f"WHERE scene_revision_id IN ({placeholders}) ORDER BY snapshot_id",
                revision_ids,
            ).fetchall()
        )
