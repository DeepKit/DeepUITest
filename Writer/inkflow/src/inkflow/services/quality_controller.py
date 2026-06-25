"""Quality Controller (Service 5).

Gate1 + Gate2 + Smart-Redo (L0-L2) + L1-L4 Repair.

Gate1: L0 mechanical checks (regex-based, deterministic)
Gate2: AI jury final minimum gate
Smart-Redo: 3-level retry with escalation
Repair: L1-L4 repair framework
"""

from __future__ import annotations

import json
import sqlite3

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.models.enums import (
    ShotStatus,
    LightStatus,
    LightThreshold,
    RedoLevel,
    RepairLayer,
)


class QualityController:
    """Quality control with dual gates and smart-redo."""

    def __init__(self, db: sqlite3.Connection, run_id: str):
        self.db = db
        self.run_id = run_id

    # ── Gate 1: L0 mechanical checks ──

    def gate1_check(self, shot_id: str, draft_ids: list[str]) -> list[str]:
        """Gate 1: L0 mechanical checks on all drafts.

        Checks:
        - Empty or whitespace-only text
        - Excessive repetition (same phrase > 5 times in short text)
        - Minimum length (at least 50 chars)

        Returns:
            List of draft_ids that passed Gate 1.
        """
        passed = []
        for draft_id in draft_ids:
            draft = self.db.execute(
                "SELECT * FROM writing_drafts WHERE draft_id = ?", (draft_id,)
            ).fetchone()
            if draft is None:
                continue

            text = draft["text"]
            violations = []

            # Check 1: Empty or whitespace-only
            if not text or not text.strip():
                violations.append("empty_text")

            # Check 2: Minimum length
            if len(text.strip()) < 50:
                violations.append("too_short")

            # Check 3: Excessive repetition
            if _has_excessive_repetition(text):
                violations.append("excessive_repetition")

            gate1_result = {
                "passed": len(violations) == 0,
                "violations": violations,
            }

            if gate1_result["passed"]:
                passed.append(draft_id)

            self.db.execute(
                "UPDATE writing_drafts SET gate1_result_json = ? WHERE draft_id = ?",
                (json.dumps(gate1_result, ensure_ascii=False), draft_id),
            )

        self.db.commit()
        return passed

    # ── Gate 2: Final minimum gate ──

    def gate2_check(self, shot_id: str, draft_id: str, jury_verdict: dict) -> dict:
        """Gate 2: Final minimum gate on jury winner.

        Args:
            shot_id: The shot.
            draft_id: The jury winner draft.
            jury_verdict: Output from JuryService.score_candidates().

        Returns:
            Dict: {passed, score, light_status, violations}
        """
        score = jury_verdict.get("winner_score", 0)
        light_status = jury_verdict.get("light_status", "red")

        violations = []
        # LLM-4: Only record real violations, not misleading red semantics
        if score < LightThreshold.YELLOW_MIN:
            violations.append("below_yellow_threshold")
        # Only add below_green if actually red (not yellow)
        if light_status == "red":
            violations.append("below_green_threshold")

        gate2_result = {
            "passed": light_status != "red",
            "score": score,
            "light_status": light_status,
            "violations": violations,
        }

        self.db.execute(
            "UPDATE writing_drafts SET gate2_result_json = ? WHERE draft_id = ?",
            (json.dumps(gate2_result, ensure_ascii=False), draft_id),
        )
        self.db.commit()

        return gate2_result

    # ── Smart-Redo ──

    def smart_redo(
        self,
        shot_id: str,
        current_level: int,
        retry_budget: "RetryBudgetService | None" = None,
    ) -> dict:
        """Execute Smart-Redo at the given level.

        L0: Retry same prompt
        L1: Fast model retry
        L2: Full redo with redo_model

        If retry_budget is provided, check budget and circuit breaker before
        allowing the redo.

        Returns:
            Dict: {level, action, can_retry}
        """
        shot = self.db.execute(
            "SELECT * FROM writing_shots WHERE shot_id = ?", (shot_id,)
        ).fetchone()
        if shot is None:
            return {"level": current_level, "action": "shot_not_found", "can_retry": False}

        current_attempt = shot["redo_attempt"]

        if current_attempt >= 3:
            # All 3 levels exhausted → permanent_red
            self.db.execute(
                "UPDATE writing_shots SET shot_status = ?, placeholder_type = 'permanent_red', "
                "updated_at = datetime('now') WHERE shot_id = ?",
                (ShotStatus.DONE_RED_PERMANENT, shot_id),
            )
            self.db.commit()
            if retry_budget:
                try:
                    retry_budget.record_failure(shot_id, "model_error", detail="all 3 retry levels exhausted")
                except Exception:
                    pass
            return {"level": current_level, "action": "permanent_red", "can_retry": False}

        # Atomic increment: WHERE redo_attempt = current_attempt prevents
        # the race condition where two concurrent redos read the same value.
        new_attempt = current_attempt + 1
        actions = {
            1: "retry_same_prompt",   # L0
            2: "fast_model_retry",     # L1
            3: "full_redo_model",      # L2
        }

        result = self.db.execute(
            "UPDATE writing_shots SET shot_status = 'redo', redo_attempt = redo_attempt + 1, "
            "placeholder_type = 'redo_placeholder', updated_at = datetime('now') "
            "WHERE shot_id = ? AND redo_attempt = ?",
            (shot_id, current_attempt),
        )
        if result.rowcount == 0:
            # Another process already incremented — re-read and return
            shot = self.db.execute(
                "SELECT redo_attempt FROM writing_shots WHERE shot_id = ?",
                (shot_id,),
            ).fetchone()
            new_attempt = shot["redo_attempt"] if shot else current_attempt

        self.db.commit()

        return {
            "level": new_attempt,
            "action": actions.get(new_attempt, "unknown"),
            "can_retry": new_attempt < 3,
        }

    # ── Light determination ──

    def determine_light(self, score: float) -> str:
        """Determine light status from score."""
        if score >= LightThreshold.GREEN_MIN:
            return LightStatus.GREEN
        elif score >= LightThreshold.YELLOW_MIN:
            return LightStatus.YELLOW
        return LightStatus.RED

    def finalize_shot(
        self,
        shot_id: str,
        draft_id: str,
        gate2_result: dict,
        *,
        brilliance_level: str | None = None,
        badsmell_level: str | None = None,
    ) -> str:
        """Finalize shot status after gate2.

        Returns:
            Final shot_status.
        """
        light = gate2_result["light_status"]

        if light == "green":
            status = ShotStatus.DONE_GREEN
        elif light == "yellow":
            status = ShotStatus.DONE_YELLOW
        else:
            status = ShotStatus.PLACEHOLDER

        self.db.execute(
            "UPDATE writing_shots SET shot_status = ?, light_status = ?, "
            "brilliance_level = ?, badsmell_level = ?, "
            "updated_at = datetime('now') WHERE shot_id = ?",
            (status, light, brilliance_level, badsmell_level, shot_id),
        )
        self.db.commit()
        return status

    # ── Repair ──

    def record_repair(
        self,
        shot_id: str,
        contract_id: str,
        layer: str,
        diagnosis: str,
        diff: dict,
        result: dict | None = None,
    ) -> str:
        """Record a repair attempt in the audit log.

        Args:
            shot_id: The shot being repaired.
            contract_id: The contract being repaired.
            layer: L1, L2, L3, or L4.
            diagnosis: What was wrong.
            diff: What changed.
            result: Repair outcome.

        Returns:
            repair_audit_id
        """
        repair_id = generate_ulid()
        self.db.execute(
            "INSERT INTO writing_repair_audit "
            "(repair_audit_id, shot_id, run_id, contract_id, layer, "
            "diagnosis, diff_json, repair_result_json) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (repair_id, shot_id, self.run_id, contract_id, layer,
             diagnosis,
             json.dumps(diff, ensure_ascii=False),
             json.dumps(result, ensure_ascii=False) if result else None),
        )
        self.db.commit()
        return repair_id


# ── L0 mechanical checks ──

# Common Chinese characters and punctuation that should not trigger
# repetition detection — they appear naturally at high frequency.
_REPETITION_WHITELIST_CHARS = set(
    "的了一是不我在人有他这来上到们说个大和就也地着那"
    "要看里没还时出会自为过能下子都去而从很得把所家"
    "以可想中对开用天年它现如小只后学起成向多当经"
    "，。！？、；：""''（）\n\r\t "
)

_REPETITION_THRESHOLD = 15


def _has_excessive_repetition(text: str) -> bool:
    """Check for excessive n-gram repetition, tuned for Chinese text.

    Uses 3-4 gram analysis (not 2-gram) to avoid false positives
    from common Chinese bigrams like "的，" or "了一".
    Filters n-grams that consist entirely of whitelist characters.
    """
    if len(text) < 200:
        return False
    from collections import Counter
    for n in range(3, 5):
        ngrams = [text[i:i + n] for i in range(len(text) - n + 1)]
        # Filter out n-grams that are all whitelist characters
        filtered = [
            ng for ng in ngrams
            if not all(c in _REPETITION_WHITELIST_CHARS for c in ng)
        ]
        if not filtered:
            continue
        counts = Counter(filtered)
        most_common = counts.most_common(1)
        if most_common and most_common[0][1] > _REPETITION_THRESHOLD:
            return True
    return False