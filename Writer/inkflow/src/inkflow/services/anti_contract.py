"""Anti-Contract Sandbox — ARCH-11.

Allows one track to intentionally deviate from soft constraints during the
quad-track race. The "unexpected value" of the deviation is evaluated;
if it produces significantly better text, a human judgment is triggered.

Flow:
  1. During quad-track dispatch, one track receives relaxed soft constraints
  2. After jury scoring, compare the "deviant" track's score against the
     "compliant" mean
  3. If deviant score > compliant mean + threshold → flag for human review
  4. Human decision feeds back into style preference learning (ARCH-10)
"""

from __future__ import annotations

import json
import sqlite3

from inkflow.utils.ulid import generate as generate_ulid


class AntiContractSandbox:
    """Evaluates soft-constraint deviations for unexpected value."""

    def __init__(self, db: sqlite3.Connection, run_id: str):
        self.db = db
        self.run_id = run_id

    def evaluate_deviation(
        self,
        shot_id: str,
        deviant_draft_id: str,
        compliant_draft_ids: list[str],
        jury_scores: dict[str, dict],
        deviation_threshold: float = 5.0,
    ) -> dict:
        """Evaluate whether a deviant draft's deviation produced unexpected value.

        Args:
            shot_id: The shot being evaluated.
            deviant_draft_id: The draft that intentionally deviated from soft constraints.
            compliant_draft_ids: Drafts that followed soft constraints.
            jury_scores: Dict of {draft_id: {"trimmed_mean": float}}
            deviation_threshold: Minimum score advantage to flag for human review.

        Returns:
            {
                "flagged": bool,
                "deviant_score": float,
                "compliant_mean": float,
                "advantage": float,
                "human_review_id": str | None,
                "soft_constraints": list[str],
            }
        """
        deviant_score = jury_scores.get(deviant_draft_id, {}).get("trimmed_mean", 0)
        compliant_scores = [
            jury_scores.get(did, {}).get("trimmed_mean", 0)
            for did in compliant_draft_ids
        ]
        compliant_mean = sum(compliant_scores) / len(compliant_scores) if compliant_scores else 0

        advantage = deviant_score - compliant_mean
        flagged = advantage >= deviation_threshold

        human_review_id = None
        if flagged:
            human_review_id = self._create_human_review(
                shot_id=shot_id,
                deviant_draft_id=deviant_draft_id,
                deviant_score=deviant_score,
                compliant_mean=compliant_mean,
                advantage=advantage,
            )

        return {
            "flagged": flagged,
            "deviant_score": deviant_score,
            "compliant_mean": compliant_mean,
            "advantage": advantage,
            "human_review_id": human_review_id,
        }

    def get_soft_constraints(self, shot_id: str) -> list[str]:
        """Get soft constraints for a shot from the contract."""
        row = self.db.execute(
            "SELECT contract_json FROM writing_shot_contracts "
            "WHERE shot_id = ? AND run_id = ?",
            (shot_id, self.run_id),
        ).fetchone()
        if not row:
            return []

        try:
            contract = json.loads(row["contract_json"])
            soft = contract.get("soft_constraints", [])
            if isinstance(soft, list):
                return soft
            return []
        except (json.JSONDecodeError, TypeError):
            return []

    def record_human_decision(
        self,
        human_review_id: str,
        decision: str,
        notes: str = "",
    ) -> None:
        """Record human decision on a flagged deviation.

        Args:
            human_review_id: The review ID from evaluate_deviation.
            decision: "accept", "reject", or "conditional".
            notes: Optional human notes.
        """
        self.db.execute(
            "UPDATE writing_anti_contract_reviews "
            "SET human_decision = ?, human_notes = ?, reviewed_at = datetime('now') "
            "WHERE review_id = ?",
            (decision, notes, human_review_id),
        )
        self.db.commit()

    def get_run_reviews(self) -> list[dict]:
        """Get all human reviews for this run."""
        rows = self.db.execute(
            "SELECT * FROM writing_anti_contract_reviews "
            "WHERE run_id = ? ORDER BY created_at",
            (self.run_id,),
        ).fetchall()
        return [dict(r) for r in rows]

    # ── Internal ──

    def _create_human_review(
        self,
        shot_id: str,
        deviant_draft_id: str,
        deviant_score: float,
        compliant_mean: float,
        advantage: float,
    ) -> str:
        """Create a human review record for a flagged deviation."""
        review_id = f"acr_{shot_id}_{generate_ulid()[:8]}"
        soft_constraints = self.get_soft_constraints(shot_id)

        self.db.execute(
            "INSERT INTO writing_anti_contract_reviews "
            "(review_id, shot_id, run_id, deviant_draft_id, "
            "deviant_score, compliant_mean, advantage, "
            "soft_constraints_json, human_decision, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'))",
            (
                review_id, shot_id, self.run_id, deviant_draft_id,
                deviant_score, compliant_mean, advantage,
                json.dumps(soft_constraints, ensure_ascii=False),
            ),
        )
        self.db.commit()
        return review_id
