from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass

from ink.contract.generated.dtos import DraftSpecDTO
from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.core.state_machine import load_status, transition
from ink.errors import DataIntegrityError, LLMProviderError
from ink.jury.scores import JUDGE_ROLES, SCORE_COLUMNS
from ink.time import now_utc_iso
from ink.writers.draft_repository import list_drafts, load_draft


_DEFAULT_ORCHESTRATOR: "JuryOrchestrator | None" = None

# DB 绝对底线 —— 对应 sql/schema.sql 的 writing_jury_aggregates CHECK 约束。
# 设计意图（见 schema.sql 注释）：DB 只兜绝对底线，应用层取 max(项目运营阈值, 绝对底线) 执行。
# 项目阈值（writing_projects.shot_quality_floor 等）不得低于此，由 _load_jury_context 取兜底后使用。
# 若改这些值，必须同步改 sql/schema.sql 的对应 CHECK，否则 passed=True 的稿写库会撞 CHECK 抛 IntegrityError。
ABSOLUTE_SHOT_QUALITY_FLOOR = 80      # final_score >= 80
ABSOLUTE_DIMENSION_FLOOR = 65        # 每维度 median >= 65
ABSOLUTE_JUDGE_DISAGREEMENT_MAX = 25  # judge_disagreement_max <= 25


class JuryLLMFailure(Exception):
    """单 draft 的 3 裁判 LLM 调用全部失败（failover 三 tier 都挂）。

    与「质量不过 gate」区分：LLM 失败是供应商故障，不应触发重写重跑，
    由 score_and_select_winner 捕获后跳过该 draft；全部 draft 都因 LLM 失败跳过时
    直接 transition failed 抛「调供应商」错（硬伤2修正）。
    """

    def __init__(self, draft_id: int, reason: str) -> None:
        super().__init__(f"jury LLM failure for draft {draft_id}: {reason}")
        self.draft_id = draft_id
        self.reason = reason


RAW_SCORE_INSERT_SQL = """
    INSERT INTO writing_jury_raw_scores
        (draft_id, shot_contract_id, jury_round, judge_slot, judge_model, judge_role,
         scene_visual, rhythm_pacing, dialogue_subtext, suspense_tension,
         language_texture, emotional_progression, character_believability,
         structure_landing, reading_fluency, motif_theme_fit,
         chapter_continuity, creative_boundary, evaluated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
"""
AGGREGATE_INSERT_SQL = """
    INSERT INTO writing_jury_aggregates
        (shot_id, draft_id, shot_contract_id, jury_round_used, judge_count,
         scene_visual_median, rhythm_pacing_median, dialogue_subtext_median,
         suspense_tension_median, language_texture_median, emotional_progression_median,
         character_believability_median, structure_landing_median, reading_fluency_median,
         motif_theme_fit_median, chapter_continuity_median, creative_boundary_median,
         weight_used, final_score, quality_gate_passed,
         quality_gate_reasons, judge_disagreement_max, is_winner, evaluated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
"""
ELIGIBLE_BASE_CANDIDATES_SQL = """
    SELECT d.draft_id
    FROM writing_drafts d
    JOIN writing_draft_eligibility e ON e.draft_id = d.draft_id
    WHERE d.shot_id = ?
      AND d.degraded = 0
      AND d.is_deviant = 0
      AND e.gate1_eligible = 1
      AND e.gate2_eligible = 1
    ORDER BY d.draft_id
"""
ELIGIBLE_RETRY_CANDIDATES_SQL = """
    SELECT d.draft_id
    FROM writing_drafts d
    JOIN writing_draft_eligibility e ON e.draft_id = d.draft_id
    WHERE d.shot_id = ?
      AND d.degraded = 0
      AND d.is_deviant = 0
      AND d.retry_count > 0
      AND e.gate1_eligible = 1
      AND e.gate2_eligible = 1
    ORDER BY d.draft_id
"""


def score_and_select_winner(shot_id: str, run_id: int) -> DraftSpecDTO:
    if _DEFAULT_ORCHESTRATOR is None:
        raise DataIntegrityError("jury orchestrator is not configured")
    return _DEFAULT_ORCHESTRATOR.score_and_select_winner(shot_id, run_id)


class JuryOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway: LLMGateway | None = None) -> None:
        self.conn = conn
        self.gateway = gateway or LLMGateway(conn)

    def score_and_select_winner(self, shot_id: str, run_id: int) -> DraftSpecDTO:
        status = load_status(self.conn, shot_id, run_id)
        if status == "winner_selected":
            if _redo_in_progress(self.conn, shot_id, run_id):
                return self._score_redo_and_maybe_flip(shot_id, run_id)
            return _load_current_winner(self.conn, shot_id)
        if status != "jury_scoring":
            raise DataIntegrityError(f"jury cannot run from status: {status}")

        context = _load_jury_context(self.conn, shot_id, run_id)
        candidates = _eligible_candidates(self.conn, shot_id)
        if len(candidates) < context.min_eligible_candidates:
            candidates = self._supplement_candidate_shortage(context, shot_id, run_id)
            if len(candidates) < context.min_eligible_candidates:
                raise DataIntegrityError(
                    f"eligible jury candidates below threshold after supplement: "
                    f"{len(candidates)} < {context.min_eligible_candidates}"
                )

        aggregates: list[tuple[int, float]] = []
        llm_failed_count = 0
        for draft in candidates:
            try:
                # Unchanged drafts keep their audited aggregate.  This matters most
                # after polish: only the new polished draft needs judging; rescoring
                # every original candidate doubled/tripled real-model calls and could
                # exhaust the per-type budget without adding information.
                result = _load_reusable_score_result(self.conn, context, draft)
                if result is None:
                    result = self._score_draft(context, draft)
            except JuryLLMFailure:
                # 该 draft 3 裁判全 LLM 失败——供应商故障，跳过不进 aggregates，不触发重写。
                llm_failed_count += 1
                continue
            if result.passed:
                aggregates.append((draft.draft_id, result.final_score))

        if not aggregates:
            # 硬伤2分流：全 LLM 失败 vs 评了但不过 gate。
            if llm_failed_count == len(candidates):
                transition(self.conn, shot_id, run_id, "jury_scoring", "failed")
                raise DataIntegrityError(
                    "jury 评分全部 LLM 调用失败，疑似供应商故障；"
                    "请检查 role-config 主/备/兜底三档 api-key 与 base_url（call_type=jury）"
                )
            return self._handle_quality_retry_or_fail(context, shot_id, run_id)

        winner_draft_id = max(aggregates, key=lambda item: (item[1], item[0]))[0]
        self.conn.execute("UPDATE writing_jury_aggregates SET is_winner = 0 WHERE shot_id = ?", (shot_id,))
        self.conn.execute(
            "UPDATE writing_jury_aggregates SET is_winner = 1 WHERE shot_id = ? AND draft_id = ?",
            (shot_id, winner_draft_id),
        )
        transition(self.conn, shot_id, run_id, "jury_scoring", "winner_selected")
        return load_draft(self.conn, winner_draft_id)

    def _supplement_candidate_shortage(
        self,
        context: "_JuryContext",
        shot_id: str,
        run_id: int,
    ) -> list[DraftSpecDTO]:
        """Generate and gate a supplemental wave before giving up on candidate count."""
        if not context.auto_retry_on_hard_failure:
            return _eligible_candidates(self.conn, shot_id)
        from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
        from ink.pipeline.write_orchestrator import WriteOrchestrator

        try:
            WriteOrchestrator(self.conn, self.gateway).produce_quality_retry_candidates(
                shot_id,
                run_id,
            )
            HardGateOrchestrator(self.conn).run_both_gates(shot_id, run_id)
        except DataIntegrityError:
            return _eligible_candidates(self.conn, shot_id)
        return _eligible_candidates(self.conn, shot_id)

    def _handle_quality_retry_or_fail(self, context: "_JuryContext", shot_id: str, run_id: int) -> DraftSpecDTO:
        if not context.auto_retry_on_hard_failure:
            transition(self.conn, shot_id, run_id, "jury_scoring", "failed")
            raise DataIntegrityError("no draft passed jury quality floor")

        from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
        from ink.pipeline.write_orchestrator import WriteOrchestrator

        try:
            WriteOrchestrator(self.conn, self.gateway).produce_quality_retry_candidates(shot_id, run_id)
            HardGateOrchestrator(self.conn).run_both_gates(shot_id, run_id)
        except DataIntegrityError:
            transition(self.conn, shot_id, run_id, "jury_scoring", "failed")
            raise

        retry_candidates = _eligible_candidates(self.conn, shot_id, retry_only=True)
        retry_aggregates: list[tuple[int, float]] = []
        retry_llm_failed = 0
        for draft in retry_candidates:
            try:
                result = self._score_draft(context, draft)
            except JuryLLMFailure:
                retry_llm_failed += 1
                continue
            if result.passed:
                retry_aggregates.append((draft.draft_id, result.final_score))

        if not retry_aggregates:
            if retry_llm_failed == len(retry_candidates) and retry_candidates:
                transition(self.conn, shot_id, run_id, "jury_scoring", "failed")
                raise DataIntegrityError(
                    "jury 重跑评分全部 LLM 调用失败，疑似供应商故障；"
                    "请检查 role-config 主/备/兜底三档 api-key 与 base_url（call_type=jury）"
                )
            if _shot_retry_count(self.conn, shot_id, run_id) >= context.max_retries_per_gate:
                transition(self.conn, shot_id, run_id, "jury_scoring", "failed")
            raise DataIntegrityError("no retry draft passed jury quality floor")

        winner_draft_id = max(retry_aggregates, key=lambda item: (item[1], item[0]))[0]
        self.conn.execute("UPDATE writing_jury_aggregates SET is_winner = 0 WHERE shot_id = ?", (shot_id,))
        self.conn.execute(
            "UPDATE writing_jury_aggregates SET is_winner = 1 WHERE shot_id = ? AND draft_id = ?",
            (shot_id, winner_draft_id),
        )
        transition(self.conn, shot_id, run_id, "jury_scoring", "winner_selected")
        return load_draft(self.conn, winner_draft_id)

    def _score_redo_and_maybe_flip(self, shot_id: str, run_id: int) -> DraftSpecDTO:
        from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator

        HardGateOrchestrator(self.conn).run_both_gates(shot_id, run_id)
        context = _load_jury_context(self.conn, shot_id, run_id)
        redo_candidates = _eligible_candidates(self.conn, shot_id, retry_only=True)
        if len(redo_candidates) < context.redo_candidate_count:
            raise DataIntegrityError(
                f"redo jury candidates below threshold: {len(redo_candidates)} < {context.redo_candidate_count}"
            )

        best_existing = _load_best_aggregate(self.conn, shot_id)
        if best_existing is None:
            raise DataIntegrityError(f"existing winner aggregate not found for redo: {shot_id}")

        redo_aggregates: list[tuple[int, float]] = []
        for draft in redo_candidates:
            try:
                result = self._score_draft(context, draft)
            except JuryLLMFailure:
                continue
            if result.passed:
                redo_aggregates.append((draft.draft_id, result.final_score))

        if redo_aggregates:
            best_redo = max(redo_aggregates, key=lambda item: (item[1], item[0]))
            if best_redo[1] > best_existing[1]:
                self.conn.execute("UPDATE writing_jury_aggregates SET is_winner = 0 WHERE shot_id = ?", (shot_id,))
                self.conn.execute(
                    "UPDATE writing_jury_aggregates SET is_winner = 1 WHERE shot_id = ? AND draft_id = ?",
                    (shot_id, best_redo[0]),
                )

        self.conn.execute(
            "UPDATE writing_shots SET redo_in_progress = 0 WHERE shot_id = ? AND run_id = ?",
            (shot_id, run_id),
        )
        return _load_current_winner(self.conn, shot_id)

    def resume_handlers(self) -> dict[str, object]:
        return {
            "rerun_jury": self.score_and_select_winner,
            "rerun_soft_gate_redo_jury": self.score_and_select_winner,
            "rerun_winner_select": self.score_and_select_winner,
        }

    def _score_draft(self, context: "_JuryContext", draft: DraftSpecDTO) -> _ScoreResult:
        """3 裁判真实调 gateway 评分 → 解析 12 维分 → 落 raw_scores + aggregate。

        每 judge 一次 `gateway.call(call_type="jury")`，gateway 内部已做主/备/兜底 failover
        （阶段 B）。单 judge 整体 LLM 失败（三 tier 都挂）跳过；3 judge 全失败抛
        ``JuryLLMFailure`` 交上层分流（直接 fail，不走重写）。部分成功则按实际 judge 数算中位数。
        解析容错：非 JSON / 越界 / 缺维 → 抛 LLMProviderError 交 gateway 换该 judge 备档重试。
        """
        self.conn.execute("DELETE FROM writing_jury_raw_scores WHERE draft_id = ? AND jury_round = 1", (draft.draft_id,))
        self.conn.execute("DELETE FROM writing_jury_aggregates WHERE draft_id = ?", (draft.draft_id,))
        # 重评（polish 后回到 jury_scoring 再评同一 draft）时清旧 jury attempt 行：
        # writing_ai_call_attempts.idempotency_key 全局 UNIQUE，重调用同 key（jury:{draft_id}:r1:{slot}）
        # 会撞 UNIQUE。raw_scores 已清（上一轮评分作废），attempt 行一并清保持语义一致。
        self.conn.execute(
            "DELETE FROM writing_ai_call_attempts WHERE call_type = 'jury' AND idempotency_key LIKE ?",
            (f"jury:{draft.draft_id}:r1:%",),
        )

        judges = _select_judges(context.jury_models, draft.writer_model, 3)
        contract_summary = _load_shot_contract_summary(self.conn, context.shot_contract_id)
        # 每维收集成功 judge 的分（按 slot 顺序），slot 从 1 起；失败的 slot 不落 raw_score。
        per_dim_scores: list[list[int]] = [[] for _ in SCORE_COLUMNS]
        judge_count = 0
        # slot → tier_hint：3 裁判对应 role_config 的 primary/secondary/tertiary，各从本 tier 起调
        # （failover 切下一 tier），实现 3 个不同模型投票 + 单 judge 容灾。配置时保证 jury
        # role_config 三 tier = jury_model_pool 三模型。
        slot_tiers = ("primary", "secondary", "tertiary")
        for slot, judge_model in enumerate(judges, start=1):
            role = JUDGE_ROLES[slot - 1]
            prompt_text = _jury_prompt(draft, contract_summary, role, context)
            idem = f"jury:{draft.draft_id}:r1:{slot}"
            try:
                result = self.gateway.call(
                    project_id=context.project_id,
                    shot_id=context.shot_id,
                    run_id=context.run_id,
                    call_type="jury",
                    prompt_id=None,
                    prompt_text=prompt_text,
                    model_name=judge_model,
                    idempotency_key=idem,
                    tier_hint=slot_tiers[slot - 1],
                )
            except LLMProviderError:
                # 该 judge 三 tier 全失败——跳过（不落 raw_score）。3 全失败在循环后判。
                continue
            try:
                dim_scores = _parse_jury_scores(result.text)  # 容错：缺单维已用中位填充；非 JSON/无有效维度仍抛
            except LLMProviderError:
                # gateway 返回了不可解析文本（非 JSON 或无有效维度）——当该 judge 失败，降级用其余 judge。
                continue
            judge_count += 1
            self.conn.execute(
                RAW_SCORE_INSERT_SQL,
                (draft.draft_id, context.shot_contract_id, 1, slot, judge_model, role, *dim_scores, now_utc_iso()),
            )
            for i, val in enumerate(dim_scores):
                per_dim_scores[i].append(val)

        if judge_count < 3:
            # schema CHECK(judge_count >= 3)：基础轮必须 3 裁判全成功才落 aggregate。
            # 部分 judge 失败（1-2 个）无法满足 CHECK，视为该 draft 评分不完整 → 抛 JuryLLMFailure
            # 交上层分流（不进 aggregates，全 draft 都因 LLM 失败时直接 fail 不走重写）。
            raise JuryLLMFailure(
                draft.draft_id,
                f"3 裁判仅 {judge_count} 个成功（{3 - judge_count} 个 LLM 调用失败），无法满足 jury 基础轮 3 裁判约束",
            )

        medians = [_median(vals) for vals in per_dim_scores]
        final_score = round(sum(medians) / len(medians), 6)
        judge_disagreement_max = max(
            (max(vals) - min(vals)) for vals in per_dim_scores if len(vals) >= 2
        ) if judge_count >= 2 else 0

        # 升级判定：基础轮分差超阈值 → 扩到 escalated_jury_count 裁判重评（jury_round=2）。
        # 升级轮成功时直接返回其结果（aggregate 已在升级方法里落库 jury_round_used=2），
        # 跳过基础轮 aggregate 落库；升级后仍分歧则升级轮 aggregate 标 escalation_exhausted。
        if (
            context.escalated_jury_count > 3
            and judge_disagreement_max > context.judge_disagreement_max
        ):
            escalation_result = self._run_escalation_round(
                context, draft, tuple(judges), per_dim_scores
            )
            if escalation_result is not None:
                return escalation_result
            # 升级失败（可用裁判不足 3）→ 落基础轮 aggregate 但标 escalation_exhausted + 不过 gate。
            weight_used = {column: round(1 / len(SCORE_COLUMNS), 6) for column in SCORE_COLUMNS}
            weight_used["_intensity_5d"] = context.intensity
            weight_used["_judge_count"] = judge_count
            if context.deviant_reference_draft_id is not None:
                weight_used["_deviant_reference_draft_id"] = context.deviant_reference_draft_id
            weight_used["_escalation"] = "failed_insufficient_judges"
            quality_gate_reasons = _quality_gate_reasons(
                context, final_score, medians, judge_disagreement_max
            ) + ["escalation_exhausted"]
            quality_gate_passed = 0
            self.conn.execute(
                AGGREGATE_INSERT_SQL,
                (
                    context.shot_id,
                    draft.draft_id,
                    context.shot_contract_id,
                    1,  # jury_round_used：基础轮（升级失败回退）
                    judge_count,  # judge_count：基础轮 = 3
                    *medians,
                    json.dumps(weight_used, ensure_ascii=False, sort_keys=True),
                    float(final_score),
                    quality_gate_passed,
                    json.dumps(quality_gate_reasons, sort_keys=True),
                    judge_disagreement_max,
                    now_utc_iso(),
                ),
            )
            return _ScoreResult(
                final_score=final_score,
                medians=medians,
                judge_disagreement_max=judge_disagreement_max,
                passed=False,
                reasons=quality_gate_reasons,
            )

        weight_used = {column: round(1 / len(SCORE_COLUMNS), 6) for column in SCORE_COLUMNS}
        weight_used["_intensity_5d"] = context.intensity
        weight_used["_judge_count"] = judge_count
        if context.deviant_reference_draft_id is not None:
            weight_used["_deviant_reference_draft_id"] = context.deviant_reference_draft_id
        quality_gate_passed = int(_quality_gate_passes(context, final_score, medians, judge_disagreement_max))
        quality_gate_reasons = _quality_gate_reasons(context, final_score, medians, judge_disagreement_max)
        self.conn.execute(
            AGGREGATE_INSERT_SQL,
            (
                context.shot_id,
                draft.draft_id,
                context.shot_contract_id,
                1,  # jury_round_used：基础轮
                judge_count,  # judge_count：基础轮 = 3
                *medians,
                json.dumps(weight_used, ensure_ascii=False, sort_keys=True),
                float(final_score),
                quality_gate_passed,
                json.dumps(quality_gate_reasons, sort_keys=True),
                judge_disagreement_max,
                now_utc_iso(),
            ),
        )
        return _ScoreResult(
            final_score=final_score,
            medians=medians,
            judge_disagreement_max=judge_disagreement_max,
            passed=bool(quality_gate_passed),
            reasons=quality_gate_reasons,
        )

    def _run_escalation_round(
        self,
        context: "_JuryContext",
        draft: DraftSpecDTO,
        base_judge_models: tuple[str, ...],
        base_per_dim_scores: list[list[int]],
    ) -> "_ScoreResult | None":
        """升级轮：扩到 ``escalated_jury_count`` 裁判重评（jury_round=2）。

        用升级轮全部分重算 medians/final_score/judge_disagreement_max 并覆盖 aggregate
        （先清旧 aggregate 行再插 jury_round_used=2）。基础轮 raw_score（round=1）保留，
        审计可见两轮。

        返回 ``None`` 表示升级失败（可用裁判 < 3 无法满足 schema judge_count >= 3），
        由调用方回退落基础轮 aggregate 并标 ``escalation_exhausted``。
        """
        escalation_judges = _select_judges_for_escalation(
            context.jury_models,
            draft.writer_model,
            context.escalated_jury_count,
            base_judge_models,
        )
        if len(escalation_judges) < 3:
            return None  # 可用裁判不足，无法满足 judge_count >= 3

        # 升级轮清旧：raw_scores round=2、aggregate 全清（升级覆盖基础轮 aggregate）。
        self.conn.execute(
            "DELETE FROM writing_jury_raw_scores WHERE draft_id = ? AND jury_round = 2",
            (draft.draft_id,),
        )
        self.conn.execute("DELETE FROM writing_jury_aggregates WHERE draft_id = ?", (draft.draft_id,))
        self.conn.execute(
            "DELETE FROM writing_ai_call_attempts WHERE call_type = 'jury' AND idempotency_key LIKE ?",
            (f"jury:{draft.draft_id}:r2:%",),
        )

        contract_summary = _load_shot_contract_summary(self.conn, context.shot_contract_id)
        per_dim_scores: list[list[int]] = [[] for _ in SCORE_COLUMNS]
        judge_count = 0
        slot_tiers = ("primary", "secondary", "tertiary")
        for slot, judge_model in enumerate(escalation_judges, start=1):
            role = JUDGE_ROLES[(slot - 1) % len(JUDGE_ROLES)]
            prompt_text = _jury_prompt(draft, contract_summary, role, context)
            idem = f"jury:{draft.draft_id}:r2:{slot}"
            try:
                result = self.gateway.call(
                    project_id=context.project_id,
                    shot_id=context.shot_id,
                    run_id=context.run_id,
                    call_type="jury",
                    prompt_id=None,
                    prompt_text=prompt_text,
                    model_name=judge_model,
                    idempotency_key=idem,
                    tier_hint=slot_tiers[(slot - 1) % len(slot_tiers)],
                )
            except LLMProviderError:
                continue
            dim_scores = _parse_jury_scores(result.text)
            judge_count += 1
            self.conn.execute(
                RAW_SCORE_INSERT_SQL,
                (draft.draft_id, context.shot_contract_id, 2, slot, judge_model, role, *dim_scores, now_utc_iso()),
            )
            for i, val in enumerate(dim_scores):
                per_dim_scores[i].append(val)

        if judge_count < 3:
            return None  # 升级轮成功裁判不足 3，无法满足 judge_count >= 3

        medians = [_median(vals) for vals in per_dim_scores]
        final_score = round(sum(medians) / len(medians), 6)
        judge_disagreement_max = max(
            (max(vals) - min(vals)) for vals in per_dim_scores if len(vals) >= 2
        ) if judge_count >= 2 else 0

        escalated_count = len(escalation_judges)
        weight_used = {column: round(1 / len(SCORE_COLUMNS), 6) for column in SCORE_COLUMNS}
        weight_used["_intensity_5d"] = context.intensity
        weight_used["_judge_count"] = judge_count
        weight_used["_jury_round"] = 2
        if len(escalation_judges) < context.escalated_jury_count:
            weight_used["_escalation_capped_to"] = escalated_count
        if context.deviant_reference_draft_id is not None:
            weight_used["_deviant_reference_draft_id"] = context.deviant_reference_draft_id
        quality_gate_passed = int(_quality_gate_passes(context, final_score, medians, judge_disagreement_max))
        quality_gate_reasons = _quality_gate_reasons(
            context, final_score, medians, judge_disagreement_max
        )
        # 升级后仍分歧 → 标 escalation_exhausted，走现有重写/fail 分流（人工裁决二期）。
        if judge_disagreement_max > context.judge_disagreement_max:
            quality_gate_reasons = quality_gate_reasons + ["escalation_exhausted"]
            quality_gate_passed = 0
        self.conn.execute(
            AGGREGATE_INSERT_SQL,
            (
                context.shot_id,
                draft.draft_id,
                context.shot_contract_id,
                2,  # jury_round_used：升级轮
                judge_count,  # judge_count：升级轮实际数
                *medians,
                json.dumps(weight_used, ensure_ascii=False, sort_keys=True),
                float(final_score),
                quality_gate_passed,
                json.dumps(quality_gate_reasons, sort_keys=True),
                judge_disagreement_max,
                now_utc_iso(),
            ),
        )
        return _ScoreResult(
            final_score=final_score,
            medians=medians,
            judge_disagreement_max=judge_disagreement_max,
            passed=bool(quality_gate_passed),
            reasons=quality_gate_reasons,
        )



class _JuryContext:
    def __init__(
        self,
        *,
        shot_id: str,
        run_id: int,
        project_id: int,
        shot_contract_id: int,
        jury_models: tuple[str, ...],
        min_eligible_candidates: int,
        redo_candidate_count: int,
        auto_retry_on_hard_failure: bool,
        max_retries_per_gate: int,
        shot_quality_floor: int,
        dimension_floor: int,
        judge_disagreement_max: int,
        escalated_jury_count: int,
        deviant_reference_draft_id: int | None,
        intensity: dict[str, object],
    ) -> None:
        self.shot_id = shot_id
        self.run_id = run_id
        self.project_id = project_id
        self.shot_contract_id = shot_contract_id
        self.jury_models = jury_models
        self.min_eligible_candidates = min_eligible_candidates
        self.redo_candidate_count = redo_candidate_count
        self.auto_retry_on_hard_failure = auto_retry_on_hard_failure
        self.max_retries_per_gate = max_retries_per_gate
        self.shot_quality_floor = shot_quality_floor
        self.dimension_floor = dimension_floor
        self.judge_disagreement_max = judge_disagreement_max
        self.escalated_jury_count = escalated_jury_count
        self.deviant_reference_draft_id = deviant_reference_draft_id
        self.intensity = intensity


def _load_jury_context(conn: sqlite3.Connection, shot_id: str, run_id: int) -> _JuryContext:
    row = conn.execute(
        """
        SELECT s.shot_contract_id, p.jury_model_pool, p.min_eligible_candidates, p.redo_candidate_count,
               p.auto_retry_on_hard_failure, p.max_retries_per_gate,
               p.shot_quality_floor, p.dimension_floor, p.judge_disagreement_max,
               p.escalated_jury_count,
               pa.intensity, pa.is_creative_shot, p.project_id
        FROM writing_shots s
        JOIN writing_projects p ON p.project_id = s.project_id
        JOIN writing_shot_persona_assignment pa ON pa.shot_contract_id = s.shot_contract_id
        WHERE s.shot_id = ? AND s.run_id = ?
        """,
        (shot_id, run_id),
    ).fetchone()
    if row is None or row[0] is None:
        raise DataIntegrityError(f"shot not found or missing jury context: {shot_id}/{run_id}")
    return _JuryContext(
        shot_id=shot_id,
        run_id=run_id,
        project_id=int(row[12]),
        shot_contract_id=int(row[0]),
        jury_models=tuple(str(item) for item in json.loads(row[1])),
        min_eligible_candidates=int(row[2]),
        redo_candidate_count=int(row[3]),
        auto_retry_on_hard_failure=bool(row[4]),
        max_retries_per_gate=int(row[5]),
        shot_quality_floor=max(int(row[6]), ABSOLUTE_SHOT_QUALITY_FLOOR),
        dimension_floor=max(int(row[7]), ABSOLUTE_DIMENSION_FLOOR),
        judge_disagreement_max=min(int(row[8]), ABSOLUTE_JUDGE_DISAGREEMENT_MAX),
        escalated_jury_count=int(row[9]),
        deviant_reference_draft_id=_load_deviant_reference(conn, shot_id) if int(row[11]) == 1 else None,
        intensity=json.loads(row[10]),
    )


def _eligible_candidates(conn: sqlite3.Connection, shot_id: str, *, retry_only: bool = False) -> list[DraftSpecDTO]:
    rows = conn.execute(
        ELIGIBLE_RETRY_CANDIDATES_SQL if retry_only else ELIGIBLE_BASE_CANDIDATES_SQL,
        (shot_id,),
    ).fetchall()
    return [load_draft(conn, int(row[0])) for row in rows]


def _select_judges(jury_models: tuple[str, ...], writer_model: str, count: int) -> tuple[str, ...]:
    judges = tuple(model for model in jury_models if model != writer_model)
    if len(judges) < count:
        raise DataIntegrityError("not enough jury models after excluding writer_model")
    return judges[:count]


def _select_judges_for_escalation(
    jury_models: tuple[str, ...],
    writer_model: str,
    count: int,
    base_used: tuple[str, ...],
) -> tuple[str, ...]:
    """升级轮裁判选取：排除 writer_model 后，优先用基础轮未参与模型增多样性，
    不足则复用基础轮模型；按 (draft_id, jury_round=2, judge_model) UNIQUE 去重（pool 本身
    无重复，天然满足）；取 ``min(count, 可用数)`` 个。pool 过小（如 5/writer 在内→4 可用）
    时降级到实际可取数，调用方据此记录 capped。
    """
    pool = [m for m in jury_models if m != writer_model]
    fresh = [m for m in pool if m not in base_used]
    reused = [m for m in pool if m in base_used]
    ordered = fresh + reused
    return tuple(ordered[: min(count, len(ordered))])



def _redo_in_progress(conn: sqlite3.Connection, shot_id: str, run_id: int) -> bool:
    row = conn.execute(
        "SELECT redo_in_progress FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    return row is not None and int(row[0]) == 1


def _shot_retry_count(conn: sqlite3.Connection, shot_id: str, run_id: int) -> int:
    row = conn.execute(
        "SELECT retry_count FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    return 0 if row is None else int(row[0])


def _load_best_aggregate(conn: sqlite3.Connection, shot_id: str) -> tuple[int, float] | None:
    row = conn.execute(
        """
        SELECT draft_id, final_score
        FROM writing_jury_aggregates
        WHERE shot_id = ? AND is_winner = 1 AND quality_gate_passed = 1
        ORDER BY final_score DESC, draft_id DESC
        LIMIT 1
        """,
        (shot_id,),
    ).fetchone()
    return None if row is None else (int(row[0]), float(row[1]))


def _load_deviant_reference(conn: sqlite3.Connection, shot_id: str) -> int | None:
    row = conn.execute(
        """
        SELECT draft_id
        FROM writing_drafts
        WHERE shot_id = ? AND is_deviant = 1 AND degraded = 0
        ORDER BY draft_id DESC
        LIMIT 1
        """,
        (shot_id,),
    ).fetchone()
    return None if row is None else int(row[0])


@dataclass
class _ScoreResult:
    """单 draft 评分结果：3 裁判 12 维分聚合后的 final_score / medians / 分歧 / gate 判定。"""

    final_score: float
    medians: list[float]
    judge_disagreement_max: float
    passed: bool
    reasons: list[str]


def _load_reusable_score_result(
    conn: sqlite3.Connection,
    context: "_JuryContext",
    draft: DraftSpecDTO,
) -> _ScoreResult | None:
    """Reuse scores for unchanged text, recomputing only the current gate decision."""
    row = conn.execute(
        """
        SELECT a.final_score,
               a.scene_visual_median, a.rhythm_pacing_median, a.dialogue_subtext_median,
               a.suspense_tension_median, a.language_texture_median,
               a.emotional_progression_median, a.character_believability_median,
               a.structure_landing_median, a.reading_fluency_median,
               a.motif_theme_fit_median, a.chapter_continuity_median,
               a.creative_boundary_median,
               a.judge_disagreement_max,
               d.is_stale
        FROM writing_jury_aggregates a
        JOIN writing_drafts d ON d.draft_id=a.draft_id
        WHERE a.draft_id=? AND a.shot_contract_id=?
        """,
        (draft.draft_id, context.shot_contract_id),
    ).fetchone()
    if row is None or int(row[14]) == 1:
        return None
    final_score = float(row[0])
    medians = [float(value) for value in row[1:13]]
    disagreement = float(row[13])
    passed = _quality_gate_passes(context, final_score, medians, disagreement)
    reasons = _quality_gate_reasons(context, final_score, medians, disagreement)
    # Keep the stored gate result aligned if project thresholds changed since the
    # original scoring.  No LLM call is needed because all raw medians are present.
    conn.execute(
        """
        UPDATE writing_jury_aggregates
        SET quality_gate_passed=?, quality_gate_reasons=?
        WHERE draft_id=?
        """,
        (int(passed), json.dumps(reasons, sort_keys=True), draft.draft_id),
    )
    return _ScoreResult(
        final_score=final_score,
        medians=medians,
        judge_disagreement_max=disagreement,
        passed=passed,
        reasons=reasons,
    )


# 12 维评审维度定义：role → 该角色重点审视的维度（对齐 design-v2 §3.5）。
# text 画面/节奏/对话/悬疑；literary 语言/情感/人物/结构；cross_shot 可读/母题/章续/创意边界。
_DIMENSION_LABELS = {
    "scene_visual": "场景画面感",
    "rhythm_pacing": "节奏与步调",
    "dialogue_subtext": "对话潜台词（无对白场景见下方准则）",
    "suspense_tension": "悬疑张力",
    "language_texture": "语言质感",
    "emotional_progression": "情感推进",
    "character_believability": "人物可信度",
    "structure_landing": "结构落点",
    "reading_fluency": "阅读流畅度",
    "motif_theme_fit": "母题与主题契合",
    "chapter_continuity": "章续衔接",
    "creative_boundary": "创意边界",
}


def _median(values: list[int]) -> float:
    """3 值取中位（排序后第 2 个）；2 值取均值。"""
    s = sorted(values)
    n = len(s)
    mid = n // 2
    if n % 2 == 1:
        return float(s[mid])
    return (s[mid - 1] + s[mid]) / 2.0


def _parse_jury_scores(text: str) -> list[int]:
    """解析裁判返回的 12 维分（0-100）。要求严格 JSON，键为 SCORE_COLUMNS，值为 int。

    容错：非 JSON / 缺维 / 越界 → 抛 LLMProviderError（交 gateway failover 换该 judge 备档重试）。
    """
    raw = text.strip()
    # 兼容模型把 JSON 包在 ```json fence 或前后赘述里的情况：提取首个 { 到末个 }。
    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise LLMProviderError(f"jury 评分非 JSON：未找到 JSON 对象边界")
    try:
        obj = json.loads(raw[start : end + 1])
    except json.JSONDecodeError as exc:
        raise LLMProviderError(f"jury 评分 JSON 解析失败：{exc}") from exc
    scores: list[int] = []
    parsed: list[int | None] = []
    for col in SCORE_COLUMNS:
        if col not in obj:
            # 真实模型偶尔漏返个别维度（实测 character_believability 偶发缺失）。
            # 整体丢该 judge 会让 judge_count<3 触发 JuryLLMFailure、中断该 draft 评分。
            # 容错：先记 None，下方用该 judge 其余维度中位填充，保 judge_count=3 链路不崩。
            parsed.append(None)
            continue
        val = obj[col]
        if not isinstance(val, (int, float)) or isinstance(val, bool):
            raise LLMProviderError(f"jury 评分维度 {col} 非数值：{val!r}")
        iv = int(val)
        if iv < 0 or iv > 100:
            raise LLMProviderError(f"jury 评分维度 {col} 越界(0-100)：{iv}")
        parsed.append(iv)
    present = [v for v in parsed if v is not None]
    if not present:
        # 该 judge 一个有效维度都没返——真废，交调用方当单 judge 失败处理。
        raise LLMProviderError("jury 评分无任何有效维度")
    fill = int(_median(present))
    scores = [(v if v is not None else fill) for v in parsed]
    return scores


def _load_shot_contract_summary(conn: sqlite3.Connection, shot_contract_id: int) -> str:
    """取 shot task_card 的 compiled_instructions 作为评审参考摘要（人物/场景/母题/章续约束）。

    task_card 是 writer 生成 draft 时用的同一份契约指令，评审复用保证裁判与 writer 看同一约束。
    取 superseded_at IS NULL 的当前版（B88 supersede 语义）。
    """
    row = conn.execute(
        """
        SELECT compiled_instructions FROM writing_shot_task_cards
        WHERE shot_contract_id = ? AND superseded_at IS NULL
        ORDER BY task_card_id DESC LIMIT 1
        """,
        (shot_contract_id,),
    ).fetchone()
    if row is None or row[0] is None:
        return ""
    text = str(row[0])
    # 截断避免 prompt 过长（评审只需约束要点，非全文）。
    return text[:2000] + ("…[截断]" if len(text) > 2000 else "")


def _jury_prompt(draft: DraftSpecDTO, contract_summary: str, role: str, context: "_JuryContext") -> str:
    """构造裁判 prompt：注入 draft.text + 契约摘要 + 12 维定义 + 角色主视角 + 严格 JSON 输出要求。"""
    role_focus = {
        "text": "重点审视：场景画面感、节奏步调、对话潜台词、悬疑张力（叙事落地层）",
        "literary": "重点审视：语言质感、情感推进、人物可信度、结构落点（文学品质层）",
        "cross_shot": "重点审视：阅读流畅度、母题主题契合、章续衔接、创意边界（跨章整体层）",
    }.get(role, "")
    dims_block = "\n".join(f'  "{col}": <0-100 整数>  // {label}' for col, label in _DIMENSION_LABELS.items())
    deviant_hint = ""
    if context.deviant_reference_draft_id is not None:
        deviant_hint = f"\n（本 shot 存在 deviant 参考草案 #{context.deviant_reference_draft_id}，评审时留意创意发散与约束的平衡。）"
    return (
        f"你是小说写作评审裁判（角色：{role}）。{role_focus}{deviant_hint}\n\n"
        f"## shot 契约要点\n{contract_summary or '（无契约摘要）'}\n\n"
        f"## 待评草案（writer_model={draft.writer_model}）\n{draft.text}\n\n"
        f"## 评分维度（共 12 维，每维 0-100 整数）\n{dims_block}\n\n"
        "## 评分准则\n"
        "1. 每维独立评 0-100，仅依据该维度本身的质量，不要因别的维度好坏连带扣分。\n"
        "2. 维度适用性——某些场景天生不含某类元素，此时该维按“中性偏高”给分，**不得因元素缺失而低分**：\n"
        "   - dialogue_subtext：若本段无对白或对白极少（独处、追逐、纯环境叙事等场景），"
        "给 75-82，视为“该场景无需对白，不构成缺陷”。仅在确有对白但潜台词单薄/直白时才扣分。\n"
        "   - 其他维度同理：场景不涉及某元素时给中性分，而非 0-40。\n"
        "3. 分歧控制：你的打分应落在该稿该维的合理区间内。若你与同伴的判断可能相差很大，"
        "取你心中区间的中位值，避免极端高/低分拉高整体分歧。\n"
        "4. **悬疑张力（suspense_tension）专审**：若上方“shot 契约要点”含【章节悬疑约束】，"
        "据此对照——追读类型是否达成（追查型看线索推进、倒计时型看时间压力是否落地）、"
        "沉默点是否真正对读者隐藏而非直说、物理因果锚点是否让读者可复盘后果链、"
        "章末钩子是否制造翻页欲。约束缺失或落实不到位时 suspense_tension 应明显扣分（<65）；"
        "无章节悬疑约束（纯铺垫章）则按中性偏高给分。\n\n"
        "5. **末段 POV 与连续性硬审计**：单独检查草案最后 25%（至少最后两个自然段）。"
        "若末段进入 POV only 之外角色的感知、记忆、判断或内心，且此前没有章节标题、空行分隔、"
        "明确时间地点变化等可见转场锚点，pov/人物相关的 character_believability 与 "
        "chapter_continuity 必须至少一项低于 60；仅仅提到、看见或对话中出现其他角色不算切 POV。"
        "若【连续性硬约束】给出上一状态，而开头没有承接人物位置、时间、未完成动作/悬念，"
        "chapter_continuity 必须低于 60。不得因语言漂亮而豁免。\n\n"
        "## 输出要求\n"
        "严格输出一个 JSON 对象，**仅**含上述 12 个维度键，值为 0-100 整数，不要任何额外文本、"
        "不要 markdown 代码围栏、不要 evidence 字段。示例：\n"
        '{"scene_visual": 85, "rhythm_pacing": 82, ...}\n'
    )


def _quality_gate_passes(
    context: _JuryContext,
    final_score: float,
    medians: list[float],
    judge_disagreement_max: float,
) -> bool:
    return (
        final_score >= context.shot_quality_floor
        and min(medians) >= context.dimension_floor
        and judge_disagreement_max <= context.judge_disagreement_max
    )


def _quality_gate_reasons(
    context: _JuryContext,
    final_score: float,
    medians: list[float],
    judge_disagreement_max: float,
) -> list[str]:
    reasons = []
    if final_score < context.shot_quality_floor:
        reasons.append("final_score_below_shot_quality_floor")
    if min(medians) < context.dimension_floor:
        reasons.append("dimension_below_floor")
    if judge_disagreement_max > context.judge_disagreement_max:
        reasons.append("judge_disagreement_exceeded")
    return reasons


def _load_current_winner(conn: sqlite3.Connection, shot_id: str) -> DraftSpecDTO:
    row = conn.execute(
        "SELECT draft_id FROM writing_jury_aggregates WHERE shot_id = ? AND is_winner = 1",
        (shot_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"winner not found for shot: {shot_id}")
    return load_draft(conn, int(row[0]))
