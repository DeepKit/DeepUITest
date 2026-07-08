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
    VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
    VALUES (?, ?, ?, 1, 3, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
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
            raise DataIntegrityError(
                f"eligible jury candidates below threshold: {len(candidates)} < {context.min_eligible_candidates}"
            )

        aggregates: list[tuple[int, float]] = []
        llm_failed_count = 0
        for draft in candidates:
            try:
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
            dim_scores = _parse_jury_scores(result.text)  # 解析失败抛 LLMProviderError，交 gateway failover
            judge_count += 1
            self.conn.execute(
                RAW_SCORE_INSERT_SQL,
                (draft.draft_id, context.shot_contract_id, slot, judge_model, role, *dim_scores, now_utc_iso()),
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
        self.deviant_reference_draft_id = deviant_reference_draft_id
        self.intensity = intensity


def _load_jury_context(conn: sqlite3.Connection, shot_id: str, run_id: int) -> _JuryContext:
    row = conn.execute(
        """
        SELECT s.shot_contract_id, p.jury_model_pool, p.min_eligible_candidates, p.redo_candidate_count,
               p.auto_retry_on_hard_failure, p.max_retries_per_gate,
               p.shot_quality_floor, p.dimension_floor, p.judge_disagreement_max,
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
        project_id=int(row[11]),
        shot_contract_id=int(row[0]),
        jury_models=tuple(str(item) for item in json.loads(row[1])),
        min_eligible_candidates=int(row[2]),
        redo_candidate_count=int(row[3]),
        auto_retry_on_hard_failure=bool(row[4]),
        max_retries_per_gate=int(row[5]),
        shot_quality_floor=int(row[6]),
        dimension_floor=int(row[7]),
        judge_disagreement_max=int(row[8]),
        deviant_reference_draft_id=_load_deviant_reference(conn, shot_id) if int(row[10]) == 1 else None,
        intensity=json.loads(row[9]),
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


# 12 维评审维度定义：role → 该角色重点审视的维度（对齐 design-v2 §3.5）。
# text 画面/节奏/对话/悬疑；literary 语言/情感/人物/结构；cross_shot 可读/母题/章续/创意边界。
_DIMENSION_LABELS = {
    "scene_visual": "场景画面感",
    "rhythm_pacing": "节奏与步调",
    "dialogue_subtext": "对话潜台词",
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
    for col in SCORE_COLUMNS:
        if col not in obj:
            raise LLMProviderError(f"jury 评分缺维度：{col}")
        val = obj[col]
        if not isinstance(val, (int, float)) or isinstance(val, bool):
            raise LLMProviderError(f"jury 评分维度 {col} 非数值：{val!r}")
        iv = int(val)
        if iv < 0 or iv > 100:
            raise LLMProviderError(f"jury 评分维度 {col} 越界(0-100)：{iv}")
        scores.append(iv)
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
