"""多模型 LLM 评分服务 (Jury Service)。

默认配置为 3 个模型 × 5 个维度 = 15 分/草稿。
评分维度：契约履约 / 禁用表达 / 阅读流畅 / 悬疑效果 / 意外价值。
标准模式按 trimmed mean 选稿；留白 shot 可按 creative_score 加权选稿。
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
    JURY_V4_DIMENSIONS,
    JURY_V4_DIMENSION_DISPLAY,
)
from inkflow.services.model_client import (
    ModelRequest,
    create_model_client,
    ModelCallError,
)


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
}


CREATIVE_BLANK_WEIGHTS = {
    "contract_compliance": 0.10,
    "forbidden_expression": 0.10,
    "reading_fluency": 0.20,
    "suspense_effectiveness": 0.25,
    "unexpected_value": 0.35,
}


class JuryService:
    """多模型多维度 LLM 评分服务。

    默认 3 模型 × 5 维度 = 15 分/草稿。
    标准模式按 trimmed mean 选稿；CREATIVE-3 留白模式按创意权重选稿。
    """

    def __init__(self, db: sqlite3.Connection, run_id: str, models_config: dict):
        self.db = db
        self.run_id = run_id
        self.models_config = models_config

        jury_cfg = get_jury_config(models_config)
        self.jury_models: list[str] = jury_cfg["models"]
        self.dimensions: list[str] = jury_cfg["dimensions"]
        self.quality_threshold: int = get_quality_threshold(models_config)

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
    ) -> dict:
        """九评委评分 + 选择 winner。

        Args:
            score_override: 强制评分 (0-100)，仅用于测试/修复场景。跳过 LLM 调用。
            score_overrides: Per-draft/per-dimension score override for tests.
            creative_review: Use blank-shot creative weighting for winner selection.

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
        previous_ending = self._get_previous_ending(shot_id)
        attempt_id = generate_ulid()

        # 检测是否有可用的 API（空 providers → 用启发式评分）
        providers = self.models_config.get("providers", {})
        use_llm = bool(providers) and score_override is None and score_overrides is None

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

            if use_llm:
                # 真实 LLM 九评委评分
                for model_ref in self.jury_models:
                    supplier, model_name = parse_model_ref(model_ref)
                    for dimension in self.dimensions:
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
                        scores.append(score)
                        dimension_scores.setdefault(dimension, []).append(score)

                        # 用模型名作为评委标识
                        self.db.execute(
                            "INSERT INTO writing_jury_scores "
                            "(score_id, draft_id, shot_id, run_id, jury_persona, "
                            "phase, dimension, score, comment, attempt_id) "
                            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            (
                                generate_ulid(), draft_id, shot_id, self.run_id,
                                model_name,
                                JuryPhase.INDEPENDENT,
                                dimension,
                                score,
                                comment,
                                attempt_id,
                            ),
                        )
            else:
                # 启发式评分 / score_override 模式
                base_score = score_override if score_override is not None else _heuristic_score(draft_text)
                for model_ref in self.jury_models:
                    _, model_name = parse_model_ref(model_ref)
                    for dimension in self.dimensions:
                        override_for_draft = (score_overrides or {}).get(draft_id, {})
                        if dimension in override_for_draft:
                            score = override_for_draft[dimension]
                        elif "*" in override_for_draft:
                            score = override_for_draft["*"]
                        elif score_override is not None:
                            # 精确模式：不添加 variation
                            score = base_score
                        else:
                            import random, hashlib
                            seed = int(hashlib.md5(f"{draft_id}:{model_name}:{dimension}".encode()).hexdigest()[:8], 16)
                            rng = random.Random(seed)
                            variation = rng.randint(-3, 3)
                            score = max(0, min(100, base_score + variation))
                        comment = f"启发式评分: {model_name} {dimension} = {score}/100"

                        self.db.execute(
                            "INSERT INTO writing_jury_scores "
                            "(score_id, draft_id, shot_id, run_id, jury_persona, "
                            "phase, dimension, score, comment, attempt_id) "
                            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            (
                                generate_ulid(), draft_id, shot_id, self.run_id,
                                model_name,
                                JuryPhase.INDEPENDENT,
                                dimension,
                                score,
                                comment,
                                attempt_id,
                            ),
                        )
                        scores.append(score)
                        dimension_scores.setdefault(dimension, []).append(score)

            self.db.commit()

            trimmed_mean = self._compute_trimmed_mean(scores)
            dimension_means = {
                dim: round(sum(values) / len(values), 2)
                for dim, values in dimension_scores.items()
                if values
            }
            creative_score = self._compute_weighted_score(
                dimension_means, CREATIVE_BLANK_WEIGHTS,
            )
            draft_scores[draft_id] = {
                "trimmed_mean": trimmed_mean,
                "raw_scores": scores,
                "dimension_means": dimension_means,
                "creative_score": creative_score,
            }

        if creative_review:
            return self._select_winner(
                draft_scores,
                threshold,
                score_key="creative_score",
                review_mode="creative_blank",
            )
        return self._select_winner(draft_scores, threshold)

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
                    max_tokens=min(params.get("max_tokens", 1024), 1024),
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

            except ModelCallError as e:
                last_error = f"API调用失败 (attempt {attempt+1}): {e}"

        # 所有重试��失败
        return {"score": 50, "comment": last_error or f"模型 {model_name} 调用失败", "model_used": jury_model_ref}

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
            }

        ranked = sorted(
            draft_scores.items(),
            key=lambda x: x[1].get(score_key, x[1].get("trimmed_mean", 0)),
            reverse=True,
        )
        winner_id, winner_data = ranked[0]
        winner_score = winner_data.get(score_key, winner_data.get("trimmed_mean", 0))

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
            "all_passed_threshold": all(
                d.get(score_key, d.get("trimmed_mean", 0)) >= threshold
                for d in draft_scores.values()
            ),
            "review_mode": review_mode,
            "score_key": score_key,
        }

    # ── 辅助 ──

    @staticmethod
    def _build_meta_summary(meta_contract: dict) -> str:
        identity = meta_contract.get("identity", {})
        hard = meta_contract.get("hard_boundaries", {})
        style = meta_contract.get("style_locks", {})
        parts = []
        if identity:
            parts.append(f"作品：{identity.get('title', '未知')}")
        if hard:
            parts.append(f"硬边界：{json.dumps(hard, ensure_ascii=False)[:200]}")
        if style:
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
