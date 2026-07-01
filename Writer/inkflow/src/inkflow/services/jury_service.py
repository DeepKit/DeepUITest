"""多模型 LLM 评分服务 (Jury Service)。

v5 分层裁判：
1. 硬规则裁判：规则预检 + 可选 LLM hard-rule check，失败不进入文学评分。
2. 类型裁判：只有 shot_profile 启用悬疑/留白/章末钩子等职责时才打类型分。
3. 文学裁判：9 个文学维度各自打分，去掉最高/最低后取平均选稿。
"""

from __future__ import annotations

import json
import re
import sqlite3

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.utils.config import (
    parse_model_ref,
    build_providers_for_model,
    get_model_params,
    get_jury_config,
    get_quality_threshold,
)
from inkflow.models.enums import (
    JuryPhase,
    LightThreshold,
    JURY_HARD_RULE_DIMENSIONS,
    JURY_LITERARY_DIMENSIONS,
    JURY_TYPE_DIMENSIONS,
    JURY_V4_DIMENSION_DISPLAY,
)
from inkflow.services.model_client import (
    ModelRequest,
    create_model_client,
    ModelCallError,
)
from inkflow.services.audit_recorder import AuditRecorder
from inkflow.services.exposition_gate import audit_exposition


_SCORE_PROMPT = """\
你是一位严格的文学评审。请从「{dimension_display}」维度评价以下小说正文。

【评分维度：{dimension_display}】
{dimension_description}

【元契约摘要】
{meta_contract_summary}

【前一场景结尾（参考连贯性）】
{previous_ending}

【待评文本】
{draft_text}

请给出 0-100 分的评分，并简要说明理由（100字以内）。
输出 JSON（不要其他内容）：
{{"score": 分数, "comment": "理由"}}

评分参考：
- 90-100: 卓越，无明显问题
- 80-89: 良好，偶有瑕疵
- 70-79: 合格，有明显不足
- 60-69: 较差，需要重写
- 0-59: 不可接受
"""


DIMENSION_DESCRIPTIONS = {
    "hard_rule_compliance": (
        "硬规则是否通过？只判断能不能进入文学评审，不评价文采。"
        "重点检查：硬事实、must_land、POV、禁写项、提前揭示、前文冲突、"
        "空文/重复/提示词残留、议论性解释/系统机制说明。若有任一致命问题，应给 0-79 分。"
        "段落长度、方言点缀、感官密度、身体时刻开场属于风格/文学问题，"
        "不得作为硬规则清零依据。characters_alive 只表示角色存活状态，"
        "不是唯一允许出场名单。"
    ),
    "contract_compliance": (
        "文本是否遵守了元契约中的硬边界、必须落地事件、风格铁律？"
        "是否存在与契约冲突的内容？"
    ),
    "forbidden_expression": (
        '是否出现 AI 味道？包括但不限于：总结性语言、概念化表述、'
        '禁用词汇（如"以下是"、"根据"、"这段文字"）、分析性段落、'
        '过度解释、说教语气。分数越高表示 AI 味越少。'
    ),
    "reading_fluency": (
        '文学质感、感官密度、可读性、节奏是否达标？'
        '是否符合章回体文学的流畅度要求？'
        '段落衔接是否自然？对话是否生动？\n'
        '【精确细节加分】如果文本中有至少一个"只有长期观察者才能注意到的微小变化"，'
        '加 5 分。例如："他端杯子时水面多晃了一下"（暗示手在变弱）、'
        '"他说少放糖的次数从三次变成六次"（频率变化暗示健康恶化）。'
        '这种细节必须来自角色的日常观察，不是叙述者的分析。'
        '如果没有精确细节，reading_fluency 不能超过 80 分。'
    ),
    "language_texture": (
        "语言是否有小说质地，句子是否具体、克制、有声音。"
        "高分文本应避免模板化、概念化和通用抒情。"
    ),
    "scene_specificity": (
        "场景是否由动作、物件、身体感和空间关系构成，而不是抽象说明。"
        "高分文本应让读者能看见具体发生了什么。"
    ),
    "emotional_progression": (
        "情绪是否有递进和转折，而不是停在同一种情绪里反复描述。"
    ),
    "character_believability": (
        "人物反应是否符合其身份、处境和前文状态。"
        "不得为了推进情节让角色突然失真。"
    ),
    "dialogue_subtext": (
        "对话是否像真人说话，并具有潜台词。"
        "没有对话的场景可评估沉默、动作和未说出口的信息。"
    ),
    "pacing_control": (
        "信息释放、句长、段落、停顿是否服务场景节奏。"
        "高分文本应知道哪里该快、哪里该慢。"
    ),
    "motif_theme_fit": (
        "意象、母题和本书气质是否贴合，是否避免廉价装饰。"
    ),
    "chapter_continuity": (
        "文本是否接得上前后小节：角色状态、地点、物件、信息释放和情绪节奏是否连续。"
    ),
    "suspense_effectiveness": (
        "悬疑效果是否达标？从三个不对称维度评估：\n"
        "1. 信息不对称：读者是否比角色知道得更多？这种差距是否产生了紧张感？\n"
        "2. 时间不对称：是否有未完成的事件或未解答的问题让读者必须继续阅读？\n"
        "3. 后果不对称：读者是否感知到角色尚未感知到的危险或后果？\n"
        "分数越高表示悬疑张力越强。"
    ),
    "unexpected_value": (
        "文本是否产生了'意外价值'——即出人意料但仍然令人信服的表达？\n"
        "具体评估标准：\n"
        "1. 意象独创性：是否有读者想不到、但合情合理的比喻或意象？（例如：不是'心如刀绞'，而是'他的喉结卡在某个不存在的声音里'）\n"
        "2. 节奏打破：是否有意打破了常规叙事节奏（如突然缩短句子、插入感官断片），并且这种打破增强了效果而非造成混乱？\n"
        "3. 对话潜流：对话是否有未说出口的第三层含义？（字面意思 ≠ 实际意图 ≠ 深层动机）\n"
        "4. 情感精度：是否用了一个精准的微小动作替代了大段情感描述？（如'她把杯子转了半圈'代替'她很犹豫'）\n"
        "5. 留白张力：是否在关键 moment 选择不说，让读者的想象力填补空白？\n"
        "注意：意外不等于怪异。好的意外价值是'意料之外，情理之中'。"
        "纯破坏规则或不可读的高分不能超过 70 分。"
    ),
    "hook_transition": (
        "钩子/信息释放是否有效。该留的问题是否留住，该露出的线索是否足够具体，"
        "结尾是否产生继续阅读动力，而不是解释性收束。"
    ),
}


CREATIVE_BLANK_WEIGHTS = {
    "contract_compliance": 0.10,
    "forbidden_expression": 0.10,
    "reading_fluency": 0.20,
    "suspense_effectiveness": 0.25,
    "unexpected_value": 0.35,
}

JURY_TYPE_THRESHOLDS = {
    "suspense_effectiveness": 80,
    "unexpected_value": 80,
    "hook_transition": 80,
}


class JuryService:
    """分层多模型评分服务。

    默认 hard-rule + 文学 9 维；类型维度只在 shot_profile 启用时加入。
    """

    def __init__(self, db: sqlite3.Connection, run_id: str, models_config: dict):
        self.db = db
        self.run_id = run_id
        self.models_config = models_config

        jury_cfg = get_jury_config(models_config)
        self.jury_models: list[str] = jury_cfg["models"]
        self.hard_dimensions: list[str] = jury_cfg.get(
            "hard_dimensions", JURY_HARD_RULE_DIMENSIONS,
        )
        self.literary_dimensions: list[str] = jury_cfg.get(
            "literary_dimensions", JURY_LITERARY_DIMENSIONS,
        )
        self.dimensions: list[str] = jury_cfg["dimensions"]
        self.quality_threshold: int = get_quality_threshold(models_config)
        self.hard_rule_threshold: int = jury_cfg.get("hard_rule_threshold", 80)
        self.type_threshold: int = jury_cfg.get("type_threshold", 80)
        self.min_passing_drafts: int = max(1, int(jury_cfg.get("min_passing_drafts", 2)))

    def score_candidates(
        self,
        shot_id: str,
        draft_ids: list[str],
        *,
        meta_contract: dict | None = None,
        quality_threshold: int | None = None,
        score_override: int | None = None,
        score_overrides: dict[str, dict[str, int]] | None = None,
        creative_review: bool = False,
        shot_profile: dict | None = None,
    ) -> dict:
        """分层评分 + 选择 winner。

        Args:
            score_override: 强制评分 (0-100)，仅用于测试/修复场景。跳过 LLM 调用。
            score_overrides: Per-draft/per-dimension score override for tests.
            creative_review: Backward-compatible flag; maps to blank_space type role.
            shot_profile: Optional type roles, e.g. {"types": ["suspense", "hook"]}.

        Returns:
            {
                "winner_draft_id": str | None,
                "winner_score": float,
                "winner_track": "甲" | "乙" | None,
                "light_status": "green" | "yellow" | "red",
                "draft_scores": {
                    "<draft_id>": {"trimmed_mean": float, "raw_scores": [int x 9]},
                    ...
                },
                "all_passed_threshold": bool,
            }
        """
        threshold = quality_threshold or self.quality_threshold
        meta_summary = self._build_meta_summary(meta_contract) if meta_contract else "（无）"
        hard_meta_summary = (
            self._build_meta_summary(meta_contract, hard_rule_only=True)
            if meta_contract else "（无）"
        )
        previous_ending = self._get_previous_ending(shot_id)
        attempt_id = generate_ulid()
        bypass_gates = score_override is not None or score_overrides is not None
        type_dimensions = self._resolve_type_dimensions(
            shot_id, creative_review=creative_review, shot_profile=shot_profile,
        )

        # 检测是否有可用的 API（空 providers / 全本地评委 → 用启发式评分）
        providers = self.models_config.get("providers", {})
        remote_jury_requested = any(
            parse_model_ref(model_ref)[1] != "local-default"
            for model_ref in self.jury_models
        )
        use_llm = (
            remote_jury_requested
            and score_override is None
            and score_overrides is None
        )

        draft_scores: dict[str, dict] = {}

        for draft_id in draft_ids:
            draft = self.db.execute(
                "SELECT text FROM writing_drafts WHERE draft_id = ?", (draft_id,)
            ).fetchone()
            if not draft:
                continue

            draft_text = draft["text"]
            scores: list[int] = []
            dimension_scores: dict[str, list[int]] = {}
            hard_gate = self._run_hard_rule_gate(draft_text)

            hard_passed = bypass_gates or hard_gate["passed"]
            jury_failures: list[dict] = []

            hard_scores, hard_failures = self._score_dimension_group(
                shot_id=shot_id,
                draft_id=draft_id,
                draft_text=draft_text,
                dimensions=self.hard_dimensions,
                assignment_stage="hard_rule",
                meta_summary=hard_meta_summary,
                previous_ending=previous_ending,
                attempt_id=attempt_id,
                use_llm=use_llm and hard_gate["passed"],
                score_override=100 if bypass_gates else None,
                score_overrides=score_overrides,
                deterministic_gate=hard_gate,
            )
            jury_failures.extend(hard_failures)
            self._merge_scores(scores, dimension_scores, hard_scores)
            hard_means = self._compute_dimension_means(hard_scores)
            if (
                not bypass_gates
                and hard_means
                and min(hard_means.values()) < self.hard_rule_threshold
            ):
                hard_passed = self._low_hard_rule_scores_are_advisory(
                    draft_id, attempt_id,
                )
                if hard_passed:
                    hard_gate["llm_advisory_ignored"] = True

            if not hard_passed:
                self.db.commit()
                draft_scores[draft_id] = self._build_rejected_score(
                    scores, dimension_scores, hard_gate, "hard_rule",
                )
                continue

            type_passed = True
            type_means: dict[str, float] = {}
            if type_dimensions:
                type_scores, type_failures = self._score_dimension_group(
                    shot_id=shot_id,
                    draft_id=draft_id,
                    draft_text=draft_text,
                    dimensions=type_dimensions,
                    assignment_stage="type_gate",
                    meta_summary=meta_summary,
                    previous_ending=previous_ending,
                    attempt_id=attempt_id,
                    use_llm=use_llm,
                    score_override=score_override,
                    score_overrides=score_overrides,
                )
                jury_failures.extend(type_failures)
                self._merge_scores(scores, dimension_scores, type_scores)
                type_means = self._compute_dimension_means(type_scores)
                missing_type_dimensions = [
                    dim for dim in type_dimensions if dim not in type_scores
                ]
                if missing_type_dimensions:
                    self.db.commit()
                    draft_scores[draft_id] = self._build_rejected_score(
                        scores, dimension_scores, hard_gate, "jury_unavailable",
                        type_means=type_means,
                        jury_failures=jury_failures,
                        missing_dimensions=missing_type_dimensions,
                    )
                    continue
                for dim, mean in type_means.items():
                    dim_threshold = JURY_TYPE_THRESHOLDS.get(dim, self.type_threshold)
                    if mean < dim_threshold:
                        type_passed = False

            if not type_passed:
                self.db.commit()
                draft_scores[draft_id] = self._build_rejected_score(
                    scores, dimension_scores, hard_gate, "type_gate",
                    type_means=type_means,
                    jury_failures=jury_failures,
                )
                continue

            literary_scores, literary_failures = self._score_dimension_group(
                shot_id=shot_id,
                draft_id=draft_id,
                draft_text=draft_text,
                dimensions=self.literary_dimensions,
                assignment_stage="literary",
                meta_summary=meta_summary,
                previous_ending=previous_ending,
                attempt_id=attempt_id,
                use_llm=use_llm,
                score_override=score_override,
                score_overrides=score_overrides,
            )
            jury_failures.extend(literary_failures)
            self._merge_scores(scores, dimension_scores, literary_scores)

            missing_literary_dimensions = [
                dim for dim in self.literary_dimensions if dim not in literary_scores
            ]
            if missing_literary_dimensions:
                self.db.commit()
                draft_scores[draft_id] = self._build_rejected_score(
                    scores, dimension_scores, hard_gate, "jury_unavailable",
                    type_means=type_means,
                    jury_failures=jury_failures,
                    missing_dimensions=missing_literary_dimensions,
                )
                continue

            self.db.commit()

            literary_dimension_means = self._compute_dimension_means(literary_scores)
            literary_score = self._compute_trimmed_mean(
                list(literary_dimension_means.values()),
            )
            dimension_means = {
                dim: round(sum(values) / len(values), 2)
                for dim, values in dimension_scores.items()
                if values
            }
            creative_score = self._compute_weighted_score(
                dimension_means, CREATIVE_BLANK_WEIGHTS,
            )
            draft_scores[draft_id] = {
                "trimmed_mean": literary_score,
                "literary_score": literary_score,
                "raw_scores": scores,
                "dimension_means": dimension_means,
                "literary_dimension_means": literary_dimension_means,
                "hard_rule": hard_gate,
                "hard_rule_passed": True,
                "type_dimensions": type_dimensions,
                "type_gate_passed": True,
                "type_dimension_means": type_means,
                "creative_score": creative_score,
                "eligible": True,
                "jury_failures": jury_failures,
            }

        score_key = "creative_score" if creative_review else "literary_score"
        review_mode = "creative_blank" if creative_review else "typed_literary"
        self._record_draft_eligibility_audit(
            shot_id=shot_id,
            draft_scores=draft_scores,
            attempt_id=attempt_id,
            threshold=threshold,
            score_key=score_key,
        )
        verdict = self._select_winner(
            draft_scores,
            threshold,
            score_key=score_key,
            review_mode=review_mode,
        )
        AuditRecorder(self.db, run_id=self.run_id).record_event(
            stage="literary_jury",
            event_type="jury_verdict",
            status="selected" if verdict.get("winner_draft_id") else "failed",
            shot_id=shot_id,
            output_refs={"winner_draft_id": verdict.get("winner_draft_id")},
            metrics={
                "winner_score": verdict.get("winner_score", 0),
                "threshold": threshold,
                "passing_count": verdict.get("passing_count", 0),
                "min_passing_drafts": verdict.get("min_passing_drafts", self.min_passing_drafts),
            },
            payload={
                "review_mode": review_mode,
                "score_key": score_key,
            },
            failure_category=None if verdict.get("winner_draft_id") else "jury_failure",
            failure_detail=None if verdict.get("winner_draft_id") else "无 eligible winner",
        )
        return verdict

    # ── 分层评分辅助 ──

    def _record_draft_eligibility_audit(
        self,
        *,
        shot_id: str,
        draft_scores: dict[str, dict],
        attempt_id: str,
        threshold: int,
        score_key: str,
    ) -> None:
        audit = AuditRecorder(self.db, run_id=self.run_id)
        for draft_id, score_data in draft_scores.items():
            stage = score_data.get("failure_stage")
            eligible = bool(score_data.get("eligible", False))
            if eligible:
                gate_stage = "literary_jury"
                passed = score_data.get(score_key, score_data.get("literary_score", 0)) >= threshold
            elif stage == "hard_rule":
                gate_stage = "hard_rule"
                passed = False
            elif stage == "type_gate":
                gate_stage = "type_gate"
                passed = False
            elif stage == "jury_unavailable":
                gate_stage = "jury_unavailable"
                passed = False
            else:
                gate_stage = "literary_jury"
                passed = False

            score = score_data.get(score_key, score_data.get("literary_score"))
            audit.record_draft_eligibility(
                draft_id=draft_id,
                shot_id=shot_id,
                gate_stage=gate_stage,
                passed=passed,
                attempt_id=attempt_id,
                score=score,
                threshold=threshold,
                reason=score_data.get("failure_summary") or {
                    "eligible": eligible,
                    "jury_failures": score_data.get("jury_failures", []),
                },
                result=score_data,
            )
            if not passed:
                failure_category = "jury_failure" if gate_stage == "jury_unavailable" else "writer_drift"
                audit.record_failure_attribution(
                    stage=gate_stage,
                    failure_category=failure_category,
                    shot_id=shot_id,
                    draft_id=draft_id,
                    root_cause=score_data.get("failure_summary") or score_data,
                    evidence_refs={"attempt_id": attempt_id, "score_key": score_key},
                    suggested_action="按失败阶段返写；若多稿同类失败，回退优化大纲或 task card。",
                )

    def _score_dimension_group(
        self,
        *,
        shot_id: str,
        draft_id: str,
        draft_text: str,
        dimensions: list[str],
        assignment_stage: str,
        meta_summary: str,
        previous_ending: str,
        attempt_id: str,
        use_llm: bool,
        score_override: int | None,
        score_overrides: dict[str, dict[str, int]] | None,
        deterministic_gate: dict | None = None,
    ) -> tuple[dict[str, list[int]], list[dict]]:
        grouped: dict[str, list[int]] = {}
        failures: list[dict] = []
        for dimension, model_chain in self._dimension_model_chains(
            dimensions, assignment_stage,
        ):
            scored = False
            for model_ref in model_chain:
                _, model_name = parse_model_ref(model_ref)
                if (
                    deterministic_gate
                    and dimension == "hard_rule_compliance"
                    and not deterministic_gate["passed"]
                ):
                    score = min(60, deterministic_gate["score"])
                    comment = "; ".join(deterministic_gate["violations"])[:200]
                elif deterministic_gate and dimension == "hard_rule_compliance" and score_override is not None:
                    score = score_override
                    comment = f"硬规则测试覆盖: {score}/100"
                elif deterministic_gate and dimension == "hard_rule_compliance" and not use_llm:
                    score = deterministic_gate["score"]
                    comment = "规则硬检通过"
                elif use_llm:
                    result = self._score_single(
                        shot_id=shot_id,
                        draft_text=draft_text,
                        jury_model_ref=model_ref,
                        dimension=dimension,
                        meta_contract_summary=meta_summary,
                        previous_ending=previous_ending,
                    )
                    score = result["score"]
                    comment = result["comment"]
                    if result.get("failed"):
                        failures.append({
                            "model": model_name,
                            "model_ref": model_ref,
                            "dimension": dimension,
                            "comment": comment,
                        })
                        continue
                else:
                    score = self._local_dimension_score(
                        draft_id, model_name, dimension, draft_text,
                        score_override=score_override,
                        score_overrides=score_overrides,
                    )
                    comment = f"启发式评分: {model_name} {dimension} = {score}/100"

                self._record_score(
                    draft_id=draft_id,
                    shot_id=shot_id,
                    jury_persona=model_name,
                    dimension=dimension,
                    score=score,
                    comment=comment,
                    attempt_id=attempt_id,
                )
                grouped.setdefault(dimension, []).append(score)
                scored = True
                break
            if not scored:
                continue
        return grouped, failures

    def _dimension_model_chains(
        self,
        dimensions: list[str],
        assignment_stage: str,
    ) -> list[tuple[str, list[str]]]:
        """Assign each dimension to one primary judge, with failure fallback.

        Hard-rule/type gates use the first configured judge as the single gate
        judge. Literary scoring distributes the 9 dimensions across configured
        judges, so three judges naturally score three dimensions each. If the
        assigned judge has an infrastructure failure, later judges are tried for
        that dimension before the dimension is marked unavailable.
        """
        models = self.jury_models or ["local-default"]
        assignments: list[tuple[str, list[str]]] = []
        for idx, dimension in enumerate(dimensions):
            start_idx = idx % len(models) if assignment_stage == "literary" else 0
            chain = models[start_idx:] + models[:start_idx]
            assignments.append((dimension, chain))
        return assignments

    def _record_score(
        self,
        *,
        draft_id: str,
        shot_id: str,
        jury_persona: str,
        dimension: str,
        score: int,
        comment: str,
        attempt_id: str,
    ) -> None:
        self.db.execute(
            "INSERT INTO writing_jury_scores "
            "(score_id, draft_id, shot_id, run_id, jury_persona, "
            "phase, dimension, score, comment, attempt_id) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                generate_ulid(), draft_id, shot_id, self.run_id,
                jury_persona,
                JuryPhase.INDEPENDENT,
                dimension,
                max(0, min(100, int(score))),
                comment,
                attempt_id,
            ),
        )

    @staticmethod
    def _merge_scores(
        scores: list[int],
        dimension_scores: dict[str, list[int]],
        grouped: dict[str, list[int]],
    ) -> None:
        for dimension, values in grouped.items():
            scores.extend(values)
            dimension_scores.setdefault(dimension, []).extend(values)

    @staticmethod
    def _compute_dimension_means(grouped: dict[str, list[int]]) -> dict[str, float]:
        return {
            dim: round(sum(values) / len(values), 2)
            for dim, values in grouped.items()
            if values
        }

    def _local_dimension_score(
        self,
        draft_id: str,
        model_name: str,
        dimension: str,
        draft_text: str,
        *,
        score_override: int | None,
        score_overrides: dict[str, dict[str, int]] | None,
    ) -> int:
        override_for_draft = (score_overrides or {}).get(draft_id, {})
        if dimension in override_for_draft:
            return override_for_draft[dimension]
        if "*" in override_for_draft:
            return override_for_draft["*"]
        if score_override is not None:
            return score_override

        import hashlib
        import random

        base_score = _heuristic_score(draft_text) + _dimension_adjustment(dimension, draft_text)
        seed = int(
            hashlib.md5(f"{draft_id}:{model_name}:{dimension}".encode()).hexdigest()[:8],
            16,
        )
        rng = random.Random(seed)
        variation = rng.randint(-3, 3)
        return max(0, min(100, base_score + variation))

    def _resolve_type_dimensions(
        self,
        shot_id: str,
        *,
        creative_review: bool,
        shot_profile: dict | None,
    ) -> list[str]:
        roles: list[str] = []
        if shot_profile:
            raw_roles = shot_profile.get("types") or shot_profile.get("type_roles") or []
            if isinstance(raw_roles, str):
                raw_roles = [raw_roles]
            roles.extend(str(role) for role in raw_roles)
        if creative_review:
            roles.append("blank_space")
        if shot_id.endswith(".s04"):
            roles.append("hook")

        dimensions: list[str] = []
        for role in roles:
            for dimension in JURY_TYPE_DIMENSIONS.get(role, []):
                if dimension not in dimensions:
                    dimensions.append(dimension)
        return dimensions

    @staticmethod
    def _run_hard_rule_gate(text: str) -> dict:
        violations: list[str] = []
        if not text or not text.strip():
            violations.append("empty_text")
        if len(text.strip()) < 50:
            violations.append("too_short")
        bad_markers = ["以下是", "这段文字", "分析", "解读", "核心落点", "风格执行", "字数"]
        for marker in bad_markers:
            if marker in text[:500]:
                violations.append(f"prompt_artifact:{marker}")
        if _has_excessive_repetition(text):
            violations.append("excessive_repetition")
        exposition_audit = audit_exposition(text, strict=False)
        for item in exposition_audit.get("hard_violations", [])[:5]:
            violations.append(f"explanation:{item.get('code', 'unknown')}")

        score = 100 - min(80, len(violations) * 25)
        return {
            "passed": not violations,
            "score": score,
            "violations": violations,
            "exposition_audit": exposition_audit,
        }

    def _build_rejected_score(
        self,
        scores: list[int],
        dimension_scores: dict[str, list[int]],
        hard_gate: dict,
        stage: str,
        *,
        type_means: dict[str, float] | None = None,
        jury_failures: list[dict] | None = None,
        missing_dimensions: list[str] | None = None,
    ) -> dict:
        dimension_means = {
            dim: round(sum(values) / len(values), 2)
            for dim, values in dimension_scores.items()
            if values
        }
        return {
            "trimmed_mean": 0,
            "literary_score": 0,
            "raw_scores": scores,
            "dimension_means": dimension_means,
            "literary_dimension_means": {},
            "hard_rule": hard_gate,
            "hard_rule_passed": stage != "hard_rule",
            "type_gate_passed": stage != "type_gate",
            "type_dimension_means": type_means or {},
            "creative_score": 0,
            "eligible": False,
            "failure_stage": stage,
            "jury_failures": jury_failures or [],
            "missing_dimensions": missing_dimensions or [],
            "failure_summary": self._build_rejection_summary(
                stage, hard_gate, dimension_means, type_means or {},
                missing_dimensions or [],
            ),
        }

    def _build_rejection_summary(
        self,
        stage: str,
        hard_gate: dict,
        dimension_means: dict[str, float],
        type_means: dict[str, float],
        missing_dimensions: list[str],
    ) -> dict:
        """Return a human-readable reason for an ineligible draft."""
        if stage == "hard_rule":
            reasons: list[str] = []
            violations = hard_gate.get("violations") or []
            reasons.extend(str(v) for v in violations[:3])
            hard_score = dimension_means.get("hard_rule_compliance")
            if hard_score is not None and hard_score < self.hard_rule_threshold:
                label = JURY_V4_DIMENSION_DISPLAY.get(
                    "hard_rule_compliance", "hard_rule_compliance",
                )
                reasons.append(f"{label} {hard_score}<{self.hard_rule_threshold}")
            if not reasons:
                reasons.append("硬规则裁判判定不可进入文学评审")
            return {
                "stage": stage,
                "label": "硬规则未通过",
                "reasons": reasons,
            }

        if stage == "type_gate":
            reasons = []
            for dimension, mean in type_means.items():
                threshold = JURY_TYPE_THRESHOLDS.get(dimension, self.type_threshold)
                if mean < threshold:
                    label = JURY_V4_DIMENSION_DISPLAY.get(dimension, dimension)
                    reasons.append(f"{label} {mean}<{threshold}")
            if not reasons:
                reasons.append("类型职责未达标")
            return {
                "stage": stage,
                "label": "类型职责未通过",
                "reasons": reasons,
            }

        if stage == "jury_unavailable":
            reasons = []
            for dimension in missing_dimensions[:3]:
                label = JURY_V4_DIMENSION_DISPLAY.get(dimension, dimension)
                reasons.append(f"{label} 无有效远端评分")
            if not reasons:
                reasons.append("必需评分维度无有效远端评分")
            return {
                "stage": stage,
                "label": "评审不可用",
                "reasons": reasons,
            }

        return {
            "stage": stage,
            "label": "未入选",
            "reasons": [stage],
        }

    def _low_hard_rule_scores_are_advisory(
        self,
        draft_id: str,
        attempt_id: str,
    ) -> bool:
        """Return True when low remote hard-rule scores are non-fatal advice.

        Remote hard-rule jury can still reject drafts, but only for actual hard
        failures. Style-density complaints, transient model failures, and the
        common misread that characters_alive is an exclusive cast list are
        routed to later scoring instead of making the draft ineligible.
        """
        rows = self.db.execute(
            "SELECT score, comment FROM writing_jury_scores "
            "WHERE draft_id = ? AND run_id = ? AND attempt_id = ? "
            "AND dimension = 'hard_rule_compliance' AND score < ?",
            (draft_id, self.run_id, attempt_id, self.hard_rule_threshold),
        ).fetchall()
        if not rows:
            return False
        return all(
            _is_nonfatal_hard_rule_comment(row["comment"] or "")
            for row in rows
        )

    # ── 单次 LLM 调用 ──

    def _score_single(
        self,
        shot_id: str,
        draft_text: str,
        jury_model_ref: str,
        dimension: str,
        meta_contract_summary: str,
        previous_ending: str,
    ) -> dict:
        """调用一个评委模型评一个维度。解析失败时最多重试 2 次。"""
        dimension_display = JURY_V4_DIMENSION_DISPLAY.get(dimension, dimension)
        dimension_desc = DIMENSION_DESCRIPTIONS.get(dimension, "请评价此文本的质量。")

        prompt = _SCORE_PROMPT.format(
            dimension_display=dimension_display,
            dimension_description=dimension_desc,
            meta_contract_summary=meta_contract_summary,
            previous_ending=previous_ending or "（这是第一个场景）",
            draft_text=draft_text[:3000],
        )

        supplier, model_name = parse_model_ref(jury_model_ref)
        providers_for_model = build_providers_for_model(jury_model_ref, self.models_config)
        params = get_model_params(model_name, self.models_config)

        max_retries = int(params.get("jury_max_retries", params.get("max_retries", 0)))
        timeout_seconds = float(params.get("jury_timeout_seconds", params.get("timeout_seconds", 45)))
        last_error = None

        for attempt in range(max_retries + 1):
            try:
                client = create_model_client(
                    model_name, db=self.db, providers=providers_for_model,
                )
                request = ModelRequest(
                    operation="jury_score",
                    persona=f"评委_{model_name}",
                    prompt=prompt,
                    model=model_name,
                    temperature=params.get("temperature", 0.3),
                    max_tokens=min(
                        params.get("jury_max_tokens", params.get("max_tokens", 1024)),
                        1024,
                    ),
                    shot_id=shot_id,
                    run_id=self.run_id,
                    extra={"timeout_seconds": timeout_seconds},
                )
                response = client.generate(request)
                result = self._parse_score_response(response.text)

                # 解析成功
                if result.get("comment") != "评分响应无法解析":
                    return result

                # 解析失败，记录原始响应并重试
                last_error = f"解析失败 (attempt {attempt+1}): {response.text[:200]}"

            except (ModelCallError, ValueError) as e:
                last_error = f"API调用失败 (attempt {attempt+1}): {e}"

        # 所有重试失败。硬规则层会记录为 advisory 候选；类型/文学层会跳过该分数。
        return {
            "score": 50,
            "comment": last_error or f"模型 {model_name} 调用失败",
            "model_used": jury_model_ref,
            "failed": True,
        }

    @staticmethod
    def _parse_score_response(text: str) -> dict:
        """解析评分 JSON 响应。"""
        text = text.strip()

        # 1. 提取代码块中的 JSON
        if "```" in text:
            match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
            if match:
                text = match.group(1).strip()

        # 2. 尝试提取 JSON 对象（支持多行）
        json_match = re.search(r"\{[\s\S]*?\}", text)
        if json_match:
            json_str = json_match.group(0)
            try:
                data = json.loads(json_str)
                score = int(data.get("score", 50))
                return {"score": max(0, min(100, score)), "comment": str(data.get("comment", ""))[:200]}
            except (json.JSONDecodeError, ValueError):
                pass

        # 3. 尝试提取 "score": NNN 模式
        score_match = re.search(r'"score"\s*:\s*(\d{1,3})', text)
        if score_match:
            score = int(score_match.group(1))
            # 尝试提取 comment
            comment_match = re.search(r'"comment"\s*:\s*"([^"]*)"', text)
            comment = comment_match.group(1) if comment_match else text[:200]
            return {"score": max(0, min(100, score)), "comment": comment[:200]}

        # 4. 尝试提取文本中的数字（最后的 2-3 位数）
        nums = re.findall(r"\b(\d{2,3})\b", text)
        if nums:
            # 取最后一个可能是分数的数字
            score = min(100, max(0, int(nums[-1])))
            return {"score": score, "comment": text[:200]}

        return {"score": 50, "comment": "评分响应无法解析"}

    # ── 统计 ──

    @staticmethod
    def _compute_trimmed_mean(scores: list[int]) -> float:
        """去 1 个最高分和 1 个最低分，返回剩余分数均值。"""
        if len(scores) < 3:
            return sum(scores) / len(scores) if scores else 0.0
        sorted_scores = sorted(scores)
        trimmed = sorted_scores[1:-1]
        return round(sum(trimmed) / len(trimmed), 2)

    @staticmethod
    def _compute_weighted_score(scores: dict[str, float], weights: dict[str, float]) -> float:
        """Compute weighted score using only dimensions present in scores."""
        weighted_sum = 0.0
        total_weight = 0.0
        for dimension, score in scores.items():
            weight = weights.get(dimension, 0.0)
            if weight <= 0:
                continue
            weighted_sum += score * weight
            total_weight += weight
        if total_weight <= 0:
            return 0.0
        return round(weighted_sum / total_weight, 2)

    # ── 选择 ──

    def _select_winner(
        self,
        draft_scores: dict[str, dict],
        threshold: int,
        *,
        score_key: str = "trimmed_mean",
        review_mode: str = "standard",
    ) -> dict:
        """按指定 score_key 选择 winner，判定灯色。"""
        if not draft_scores:
            return {
                "winner_draft_id": None, "winner_score": 0,
                "winner_track": None, "light_status": "red",
                "draft_scores": {}, "all_passed_threshold": False,
                "review_mode": review_mode,
                "score_key": score_key,
                "passing_count": 0,
                "min_passing_drafts": self.min_passing_drafts,
            }

        eligible_scores = {
            draft_id: score_data
            for draft_id, score_data in draft_scores.items()
            if score_data.get("eligible", True)
        }
        if not eligible_scores:
            return {
                "winner_draft_id": None, "winner_score": 0,
                "winner_track": None, "light_status": "red",
                "draft_scores": draft_scores, "all_passed_threshold": False,
                "review_mode": review_mode,
                "score_key": score_key,
                "passing_count": 0,
                "min_passing_drafts": self.min_passing_drafts,
            }

        ranked = sorted(
            eligible_scores.items(),
            key=lambda x: x[1].get(score_key, x[1].get("trimmed_mean", 0)),
            reverse=True,
        )
        winner_id, winner_data = ranked[0]
        winner_score = winner_data.get(score_key, winner_data.get("trimmed_mean", 0))
        passing_count = sum(
            1
            for data in eligible_scores.values()
            if data.get(score_key, data.get("trimmed_mean", 0)) >= threshold
        )

        # 获取 winner 赛道
        winner_draft = self.db.execute(
            "SELECT writer_persona FROM writing_drafts WHERE draft_id = ?",
            (winner_id,),
        ).fetchone()
        winner_track = None
        if winner_draft:
            persona = winner_draft["writer_persona"] or ""
            if "甲" in persona:
                winner_track = "甲"
            elif "乙" in persona:
                winner_track = "乙"

        # 灯色判定
        if winner_score >= LightThreshold.GREEN_MIN:
            light_status = "green"
        elif winner_score >= LightThreshold.YELLOW_MIN:
            light_status = "yellow"
        else:
            light_status = "red"

        # 标记 winner 可用
        self.db.execute(
            "UPDATE writing_drafts SET is_usable = 1 WHERE draft_id = ?", (winner_id,)
        )
        self.db.commit()

        return {
            "winner_draft_id": winner_id,
            "winner_score": winner_score,
            "winner_track": winner_track,
            "light_status": light_status,
            "draft_scores": draft_scores,
            "all_passed_threshold": passing_count >= self.min_passing_drafts,
            "passing_count": passing_count,
            "min_passing_drafts": self.min_passing_drafts,
            "review_mode": review_mode,
            "score_key": score_key,
        }

    # ── 辅助 ──

    @staticmethod
    def _build_meta_summary(meta_contract: dict, *, hard_rule_only: bool = False) -> str:
        identity = meta_contract.get("identity", {})
        hard = meta_contract.get("hard_boundaries", {})
        style = meta_contract.get("style_locks", {})
        parts = []
        if identity:
            parts.append(f"作品：{identity.get('title', '未知')}")
        if hard:
            parts.append(f"硬边界：{json.dumps(hard, ensure_ascii=False)[:200]}")
        if hard_rule_only:
            parts.append(
                "硬规则裁判边界：只检查硬事实、must_land、POV、禁写项、"
                "提前揭示、前文冲突、空文、重复和提示词残留。"
                "段落长度、方言、感官密度、身体时刻开场不作清零依据；"
                "characters_alive 不是唯一允许出场名单。"
            )
        elif style:
            parts.append(f"风格要求：{json.dumps(style, ensure_ascii=False)[:200]}")
        return "\n".join(parts) if parts else "（无元契约信息）"

    def _get_previous_ending(self, shot_id: str) -> str:
        row = self.db.execute(
            "SELECT d.text FROM writing_drafts d "
            "JOIN writing_shots s ON d.shot_id = s.shot_id "
            "WHERE s.shot_index = ("
            "  SELECT s2.shot_index - 1 FROM writing_shots s2 WHERE s2.shot_id = ?"
            ") AND d.is_usable = 1 "
            "ORDER BY d.created_at DESC LIMIT 1",
            (shot_id,),
        ).fetchone()
        if row and row["text"]:
            t = row["text"]
            return t[-200:] if len(t) > 200 else t
        return ""

    # ── 向后兼容 ──

    def get_scores(self, shot_id: str) -> list[dict]:
        rows = self.db.execute(
            "SELECT * FROM writing_jury_scores WHERE shot_id = ? ORDER BY dimension",
            (shot_id,),
        ).fetchall()
        return [dict(r) for r in rows]


# ── 启发式评分（测试/无 API 时使用） ──

def _heuristic_score(text: str) -> int:
    """基于文本特征的启发式评分 (0-100)。仅在无 API 可用时使用。"""
    score = 70  # baseline

    exposition_audit = audit_exposition(text, strict=False)
    hard_explanations = len(exposition_audit.get("hard_violations", []))
    if hard_explanations >= 3:
        score -= 35
    elif hard_explanations >= 1:
        score -= 20

    # 惩罚：分析性语言
    analysis_keywords = ["以下是", "根据", "这段文字", "可以", "请告诉我", "如果",
                         "进一步", "讨论", "分析", "解读", "关键事件", "深层", "隐喻"]
    analysis_count = sum(1 for kw in analysis_keywords if kw in text[:500])
    if analysis_count >= 5:
        score -= 30
    elif analysis_count >= 3:
        score -= 20
    elif analysis_count >= 1:
        score -= 10

    # 惩罚：非中文内容
    chinese_chars = sum(1 for c in text if '一' <= c <= '鿿')
    if chinese_chars < 100:
        score -= 40
    elif chinese_chars < 200:
        score -= 20

    # 奖励：小说特征
    fiction_markers = ["她", "他", "道", "说", "雾", "雨", "茶", "膝盖", "手",
                       "「", "」", "“", "”"]
    fiction_count = sum(1 for kw in fiction_markers if kw in text[:500])
    if fiction_count >= 8:
        score += 15
    elif fiction_count >= 4:
        score += 8

    # 长度检查
    if len(text) < 200:
        score -= 30
    elif len(text) < 400:
        score -= 10
    elif 500 <= len(text) <= 1200:
        score += 5

    return max(0, min(100, score))


def _dimension_adjustment(dimension: str, text: str) -> int:
    """Small deterministic local bias per dimension for cheap jury mode."""
    if dimension == "hard_rule_compliance":
        exposition_audit = audit_exposition(text, strict=False)
        if exposition_audit.get("hard_violations"):
            return -35
        return 15 if not any(k in text[:500] for k in ["以下是", "分析", "解读"]) else -25
    if dimension in {"scene_specificity", "forbidden_expression"}:
        exposition_audit = audit_exposition(text, strict=False)
        if exposition_audit.get("hard_violations"):
            return -20
    if dimension == "scene_specificity":
        markers = ["手机", "屏幕", "膝盖", "保鲜膜", "门", "茶", "U盘", "楼道", "雾"]
        return min(10, sum(2 for marker in markers if marker in text))
    if dimension == "suspense_effectiveness":
        markers = ["突然", "正要", "还没", "不知道", "通知", "屏幕", "打断"]
        return min(12, sum(3 for marker in markers if marker in text))
    if dimension == "unexpected_value":
        markers = ["没有说", "半圈", "一毫米", "停在", "像一个"]
        return min(10, sum(2 for marker in markers if marker in text))
    if dimension == "hook_transition":
        markers = ["突然", "正要", "还没", "门外", "屏幕", "通知"]
        return min(10, sum(2 for marker in markers if marker in text))
    if dimension == "dialogue_subtext" and not any(q in text for q in ["“", "”", "「", "」"]):
        return -3
    return 0


def _is_nonfatal_hard_rule_comment(comment: str) -> bool:
    """Classify low hard-rule comments that should not zero eligibility."""
    if not comment:
        return False

    compact = comment.replace(" ", "")
    transient_markers = [
        "API调用失败", "调用失败", "readoperationtimedout", "timedout",
        "timeout", "评分响应无法解析", "解析失败",
    ]
    if any(marker.lower() in compact.lower() for marker in transient_markers):
        return True

    fatal_markers = [
        "空文", "过短", "重复", "提示词残留", "提前揭示", "前文冲突",
        "禁写", "POV切换", "视角切换", "必须落地", "must_land",
        "硬事实错误", "事实冲突",
    ]
    if any(marker in compact for marker in fatal_markers):
        return False

    nonfatal_markers = [
        "段落", "500-800", "500", "800", "3-4", "方言", "成都话",
        "感官", "气味", "声音", "温度", "湿度", "身体时刻", "开场",
        "characters_alive", "存活角色名单", "角色名单", "不在元契约",
        "未使用元契约规定的角色名",
    ]
    return any(marker in compact for marker in nonfatal_markers)


def _has_excessive_repetition(text: str) -> bool:
    compact = re.sub(r"\s+", "", text)
    if len(compact) < 80:
        return False
    for size in range(4, 9):
        seen: dict[str, int] = {}
        for idx in range(0, len(compact) - size + 1):
            token = compact[idx:idx + size]
            seen[token] = seen.get(token, 0) + 1
            if seen[token] >= 8:
                return True
    return False
