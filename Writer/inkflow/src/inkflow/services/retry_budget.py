"""Retry Budget & Failure Signature — D-25 悬疑引擎可靠性闭环.

防止无限 redo 和局部策略打架：

1. 全局重试预算：每个 run 的总 redo 次数上限（默认 = shot 数 × 2）。
2. failure_signature：记录每次失败的类型（empty, too_short, repetition,
   below_threshold, l4_violation, l3_violation, chapter_hook_weak）。
3. 同类失败熔断：同一类型的失败达到 3 次 → 标记为 circuit_breaker，
   该 shot 跳过 redo，进入 placeholder。

设计：
  - 轻量级，不影响 P0 happy path。
  - 所有数据存 writing_shots（redo_attempt + placeholder_type）和
    writing_shots（failure_signature_json）中。
"""

from __future__ import annotations

import json
import sqlite3
from collections import Counter

from inkflow.models.enums import (
    ShotStatus,
    PlaceholderType,
    LightStatus,
    LightThreshold,
)


_FAILURE_TYPES = [
    "empty_text",
    "too_short",
    "excessive_repetition",
    "below_threshold",
    "l4_violation",
    "l3_violation",
    "chapter_hook_weak",
    "jury_unavailable",
    "model_error",
    "json_parse_error",
]


class RetryBudgetExhausted(Exception):
    """全局重试预算耗尽。"""


class CircuitBreakerTriggered(Exception):
    """同类失败熔断触发。"""


class RetryBudgetService:
    """全局重试预算管理器。

    用法：
        svc = RetryBudgetService(db, run_id, max_budget=shot_count * 2)
        result = svc.record_failure(shot_id, failure_type="below_threshold")
        # result: {"can_retry", "circuit_breaker", "budget_remaining", ...}
    """

    def __init__(
        self,
        db: sqlite3.Connection,
        run_id: str,
        max_budget: int | None = None,
        circuit_breaker_threshold: int = 3,
    ):
        self.db = db
        self.run_id = run_id
        self.max_budget = max_budget or self._infer_budget()
        self.circuit_breaker_threshold = circuit_breaker_threshold
        self._used_budget: int = 0
        self._failure_signatures: dict[str, str] = {}

    # ── 主流程 ──

    def record_failure(self, shot_id: str, failure_type: str, *, detail: str = "") -> dict:
        """记录一次失败。

        Args:
            shot_id: 失败的 shot。
            failure_type: 失败类型（见 _FAILURE_TYPES）。
            detail: 可选的补充信息。

        Returns:
            {"can_retry": bool, "circuit_breaker": bool, "budget_remaining": int}
        """
        if failure_type not in _FAILURE_TYPES:
            failure_type = "model_error"

        # 1. 更新全局预算
        self._used_budget += 1
        budget_remaining = self.max_budget - self._used_budget

        # 2. 检查全局预算
        if budget_remaining < 0:
            raise RetryBudgetExhausted(
                f"Run {self.run_id} retry budget exhausted "
                f"({self._used_budget}/{self.max_budget})"
            )

        # 3. 检查同类失败熔断
        sig = self._failure_signatures.get(shot_id, "")
        count = self._count_consecutive_failures(shot_id, failure_type)

        if count >= self.circuit_breaker_threshold:
            # 熔断：标记 shot 为 permanent_red
            self._mark_circuit_breaker(shot_id, failure_type, count)
            raise CircuitBreakerTriggered(
                f"Shot {shot_id}: {failure_type} failed {count} times "
                f"(threshold={self.circuit_breaker_threshold}). "
                f"Circuit breaker triggered."
            )

        # 4. 记录 failure_signature
        self._record_failure_signature(shot_id, failure_type, detail)

        # 5. 更新 shot 的 redo_attempt（委托给 quality_controller 的逻辑）
        #    这里只记录预算消耗，不触发 smart_redo（由调用方决定）
        return {
            "can_retry": budget_remaining > 0,
            "circuit_breaker": False,
            "budget_remaining": budget_remaining,
            "failure_type": failure_type,
            "consecutive_count": count + 1,
        }

    def record_success(self, shot_id: str) -> None:
        """记录一次成功，清除该 shot 的失败签名。"""
        self._failure_signatures.pop(shot_id, None)
        # 清除 DB 中的 signature
        self.db.execute(
            "UPDATE writing_shots SET failure_signature_json = NULL "
            "WHERE shot_id = ?",
            (shot_id,),
        )
        self.db.commit()

    def get_budget_status(self) -> dict:
        """获取当前预算状态。"""
        return {
            "run_id": self.run_id,
            "max_budget": self.max_budget,
            "used_budget": self._used_budget,
            "remaining": self.max_budget - self._used_budget,
        }

    def get_failure_summary(self) -> dict:
        """获取 run 内所有失败类型的汇总。"""
        rows = self.db.execute(
            "SELECT failure_signature_json FROM writing_shots "
            "WHERE run_id = ? AND failure_signature_json IS NOT NULL",
            (self.run_id,),
        ).fetchall()

        type_counter: Counter = Counter()
        shot_count = 0
        for row in rows:
            try:
                sig = json.loads(row["failure_signature_json"])
                ft = sig.get("last_failure_type", "unknown")
                type_counter[ft] += 1
                shot_count += 1
            except (json.JSONDecodeError, TypeError):
                pass

        return {
            "run_id": self.run_id,
            "total_failures": shot_count,
            "by_type": dict(type_counter),
        }

    # ── 内部 ──

    def _infer_budget(self) -> int:
        """根据 run 内的 shot 数推断预算。"""
        row = self.db.execute(
            "SELECT COUNT(*) as cnt FROM writing_shots WHERE run_id = ?",
            (self.run_id,),
        ).fetchone()
        shot_count = row["cnt"] if row else 0
        return max(10, shot_count * 2)  # 每个 shot 最多 2 次 redo

    def _count_consecutive_failures(self, shot_id: str, failure_type: str) -> int:
        """统计同一 shot 上同一类型的连续失败次数。"""
        rows = self.db.execute(
            "SELECT failure_signature_json FROM writing_shots "
            "WHERE shot_id = ? AND failure_signature_json IS NOT NULL",
            (shot_id,),
        ).fetchone()
        if not rows:
            return 0
        try:
            sig = json.loads(rows["failure_signature_json"])
            return sig.get("consecutive_count", 0)
        except (json.JSONDecodeError, TypeError):
            return 0

    def _record_failure_signature(self, shot_id: str, failure_type: str, detail: str) -> None:
        """记录 failure_signature 到 writing_shots。"""
        existing = self.db.execute(
            "SELECT failure_signature_json FROM writing_shots WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()

        consecutive = 0
        if existing and existing["failure_signature_json"]:
            try:
                prev = json.loads(existing["failure_signature_json"])
                if prev.get("last_failure_type") == failure_type:
                    consecutive = prev.get("consecutive_count", 0) + 1
                else:
                    consecutive = 1
            except (json.JSONDecodeError, TypeError):
                consecutive = 1
        else:
            consecutive = 1

        sig = {
            "last_failure_type": failure_type,
            "consecutive_count": consecutive,
            "total_failures": self._used_budget,
            "detail": detail,
        }

        self.db.execute(
            "UPDATE writing_shots SET failure_signature_json = ? WHERE shot_id = ?",
            (json.dumps(sig, ensure_ascii=False), shot_id),
        )
        self.db.commit()

    def _mark_circuit_breaker(
        self, shot_id: str, failure_type: str, count: int
    ) -> None:
        """熔断：标记 shot 为 permanent_red + placeholder。"""
        self.db.execute(
            "UPDATE writing_shots SET "
            "shot_status = ?, "
            "placeholder_type = ?, "
            "light_status = ?, "
            "updated_at = datetime('now') "
            "WHERE shot_id = ?",
            (
                ShotStatus.DONE_RED_PERMANENT,
                PlaceholderType.PERMANENT_RED,
                LightStatus.RED,
                shot_id,
            ),
        )
        self.db.commit()


def classify_failure_type(
    gate1_violations: list[str],
    jury_score: float | None = None,
    l4_issues: list[str] | None = None,
    l3_issues: list[str] | None = None,
) -> str:
    """从失败信号中分类失败类型。"""
    if gate1_violations:
        if "empty_text" in gate1_violations:
            return "empty_text"
        if "too_short" in gate1_violations:
            return "too_short"
        if "excessive_repetition" in gate1_violations:
            return "excessive_repetition"

    if jury_score is not None and jury_score < LightThreshold.YELLOW_MIN:
        return "below_threshold"

    if l4_issues:
        return "l4_violation"

    if l3_issues:
        if any("chapter_hook_weak" in issue for issue in l3_issues):
            return "chapter_hook_weak"
        return "l3_violation"

    return "model_error"
