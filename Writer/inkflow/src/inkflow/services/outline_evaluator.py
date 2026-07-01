"""大纲评估服务 (Outline Evaluator)。

在写作前评估 shot 大纲质量。若评分低于阈值，调用架构师模型重新生成大纲。
5 维度评估：事件完整性 / 冲突清晰度 / 前后连贯 / 创作可行性 / 契约对齐
"""

from __future__ import annotations

import json
import sqlite3

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.utils.config import (
    resolve_model_chain,
    parse_model_ref,
    build_providers_for_model,
    get_model_params,
    get_outline_threshold,
)
from inkflow.services.model_client import (
    ModelRequest,
    create_model_client,
    LocalDefaultGenerator,
    ModelCallError,
)
from inkflow.services.audit_recorder import AuditRecorder


_EVALUATE_PROMPT = """\
你是一位资深文学编辑。请评估以下场景大纲的质量。

【元契约摘要】
{meta_contract_summary}

【场景大纲】
{outline_text}

【前一场景结尾（参考连贯性）】
{previous_ending}

请从以下 5 个维度评分 (0-100) 并给出整体评分：
1. 事件完整性：大纲是否覆盖了所有必须落地的事件？
2. 冲突清晰度：核心冲突是否明确？
3. 前后连贯性：与前一场景的衔接是否自然？
4. 创作可行性：大纲是否给写手留有创作空间？
5. 契约对齐度：是否符合元契约的硬边界和风格要求？

输出 JSON（不要其他内容）：
{{"dimensions": {{"completeness": 分数, "conflict_clarity": 分数, "continuity": 分数, "creative_feasibility": 分数, "contract_alignment": 分数}}, "score": 整体分数, "issues": ["问题1"], "suggestions": ["建议1"]}}

禁止输出思考过程、任务复述、解释文字、Markdown 标题。只允许输出一个 JSON 对象。
"""

_REGENERATE_PROMPT = """\
你是一位资深文学架构师。以下大纲评估不合格，请基于评估反馈重新生成。

【原大纲】
{original_outline}

【评估反馈】
评分: {score}
问题: {issues}
建议: {suggestions}

【元契约摘要】
{meta_contract_summary}

请重新生成一个更好的场景大纲，直接输出大纲内容（不要解释）：
"""

_PROMPT_ANALYSIS_MARKERS = (
    "我们需要",
    "用户要求",
    "首先",
    "需要仔细",
    "评估反馈",
    "原大纲是",
    "任务是",
)


class OutlineEvaluator:
    """大纲质量评估服务。

    在写作前评估大纲质量。若评分低于阈值，触发大纲重新生成。
    """

    def __init__(
        self,
        db: sqlite3.Connection,
        run_id: str,
        models_config: dict,
        providers: dict | None = None,
    ):
        self.db = db
        self.run_id = run_id
        self.models_config = models_config
        self.providers = providers or {}
        self.threshold = get_outline_threshold(models_config)

    def evaluate_and_fix(
        self,
        shot_id: str,
        shot_contract: dict,
        meta_contract: dict,
        *,
        max_retries: int = 1,
    ) -> dict:
        """评估大纲 → 若不合格则重新生成 → 返回最终大纲。

        这是 cli.py 的主入口。

        Returns:
            {
                "final_outline": str,
                "initial_score": int,
                "final_score": int | None,
                "regenerated": bool,
                "evaluation_history": [dict],
            }
        """
        outline_text = self._build_outline_text(shot_contract)
        previous_ending = self._get_previous_ending(shot_id)
        meta_summary = self._build_meta_summary(meta_contract)

        history = []

        # 第一次评估
        evaluation = self.evaluate_outline(
            shot_id, outline_text, meta_summary, previous_ending,
        )
        history.append(evaluation)
        initial_score = evaluation["score"]

        if evaluation["passed"] or evaluation.get("parse_error"):
            self._save_evaluation(shot_id, outline_text, evaluation, attempt=1)
            return {
                "final_outline": outline_text,
                "initial_score": initial_score,
                "final_score": initial_score,
                "regenerated": False,
                "evaluation_history": history,
            }

        # 低于阈值，尝试重新生成
        if max_retries <= 0:
            self._save_evaluation(shot_id, outline_text, evaluation, attempt=1)
            return {
                "final_outline": outline_text,
                "initial_score": initial_score,
                "final_score": initial_score,
                "regenerated": False,
                "evaluation_history": history,
            }

        new_outline = self.regenerate_outline(
            shot_id, outline_text, evaluation, meta_summary,
        )
        new_outline_text = new_outline["new_outline_text"]
        if _looks_like_prompt_analysis(new_outline_text):
            self._save_evaluation(
                shot_id, outline_text, evaluation,
                attempt=1, regenerated=True,
                new_outline_text="",
            )
            return {
                "final_outline": outline_text,
                "initial_score": initial_score,
                "final_score": initial_score,
                "regenerated": True,
                "evaluation_history": history,
                "regeneration_rejected": True,
            }

        # 重新评估
        evaluation2 = self.evaluate_outline(
            shot_id, new_outline_text, meta_summary, previous_ending,
        )
        history.append(evaluation2)

        # 保存两次评估
        self._save_evaluation(
            shot_id, outline_text, evaluation,
            attempt=1, regenerated=True,
            new_outline_text=new_outline_text,
        )
        self._save_evaluation(
            shot_id, new_outline_text, evaluation2,
            attempt=2,
        )

        # 如果新大纲更好，更新合约
        if (
            evaluation2["score"] > evaluation["score"]
            and not evaluation2.get("parse_error")
            and not _looks_like_prompt_analysis(new_outline_text)
            and not _outline_drift_too_large(outline_text, new_outline_text)
        ):
            self._update_contract(shot_id, new_outline_text)
            final_outline = new_outline_text
        else:
            final_outline = outline_text

        return {
            "final_outline": final_outline,
            "initial_score": initial_score,
            "final_score": evaluation2["score"],
            "regenerated": True,
            "evaluation_history": history,
        }

    def evaluate_outline(
        self,
        shot_id: str,
        outline_text: str,
        meta_contract_summary: str,
        previous_ending: str,
    ) -> dict:
        """评估大纲质量。

        Returns:
            {
                "score": int,
                "passed": bool,
                "dimensions": {...},
                "issues": [str],
                "suggestions": [str],
                "model_used": str,
            }
        """
        prompt = _EVALUATE_PROMPT.format(
            meta_contract_summary=meta_contract_summary,
            outline_text=outline_text,
            previous_ending=previous_ending or "（这是第一个场景）",
        )

        model_ref, text = self._call_model(
            "outline_evaluator", prompt, shot_id,
        )

        # 解析响应
        result = self._parse_evaluation_response(text)
        result["model_used"] = model_ref
        result["passed"] = result["score"] >= self.threshold
        return result

    def regenerate_outline(
        self,
        shot_id: str,
        original_outline: str,
        evaluation: dict,
        meta_contract_summary: str,
    ) -> dict:
        """基于评估反馈重新生成大纲。"""
        prompt = _REGENERATE_PROMPT.format(
            original_outline=original_outline,
            score=evaluation["score"],
            issues=json.dumps(evaluation.get("issues", []), ensure_ascii=False),
            suggestions=json.dumps(evaluation.get("suggestions", []), ensure_ascii=False),
            meta_contract_summary=meta_contract_summary,
        )

        model_ref, text = self._call_model(
            "outline_evaluator", prompt, shot_id,
        )

        return {
            "new_outline_text": _sanitize_regenerated_outline(text),
            "regeneration_note": f"由 {model_ref} 重新生成",
            "model_used": model_ref,
        }

    # ── 内部方法 ──

    def _call_model(
        self, role: str, prompt: str, shot_id: str,
    ) -> tuple[str, str]:
        """调用模型，含链式兜底。返回 (model_ref, text)。"""
        chain = resolve_model_chain(role, self.models_config)

        for ref in chain:
            supplier, model_name = parse_model_ref(ref)
            providers_for_model = build_providers_for_model(ref, self.models_config)
            params = get_model_params(model_name, self.models_config)

            try:
                client = create_model_client(
                    model_name, db=self.db, providers=providers_for_model,
                )
                request = ModelRequest(
                    operation="outline_evaluate",
                    persona="outline_evaluator",
                    prompt=prompt,
                    model=model_name,
                    temperature=params.get("temperature", 0.3),
                    max_tokens=min(
                        params.get("outline_max_tokens", params.get("max_tokens", 4096)),
                        4096,
                    ),
                    shot_id=shot_id,
                    run_id=self.run_id,
                    extra={
                        "timeout_seconds": params.get(
                            "outline_timeout_seconds",
                            params.get("timeout_seconds", 60),
                        ),
                    },
                )
                response = client.generate(request)
                return ref, response.text
            except (ModelCallError, ValueError):
                continue

        # 全部失败 → 本地兜底
        fallback = LocalDefaultGenerator(db=self.db)
        request = ModelRequest(
            operation="outline_evaluate",
            persona="outline_evaluator",
            prompt=prompt,
            shot_id=shot_id,
            run_id=self.run_id,
        )
        response = fallback.generate(request)
        return "local-default", response.text

    def _build_outline_text(self, shot_contract: dict) -> str:
        """从合约构建大纲文本。"""
        must_land = shot_contract.get("must_land_json", "{}")
        if isinstance(must_land, str):
            must_land = json.loads(must_land) if must_land else {}

        parts = []
        beats = must_land.get("beats", "")
        if beats:
            parts.append(f"必须落地的事件：\n{beats}")

        event = must_land.get("event", "")
        if event:
            parts.append(f"核心事件：{event}")

        pov = shot_contract.get("pov_routing_json", "")
        if pov:
            if isinstance(pov, str):
                pov = json.loads(pov) if pov else {}
            parts.append(f"视角人物：{pov.get('pov_character', '未知')}")

        return "\n\n".join(parts) if parts else "（大纲为空）"

    def _get_previous_ending(self, shot_id: str) -> str:
        """获取前一场景的结尾文本。"""
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
            text = row["text"]
            # 取最后 200 字
            return text[-200:] if len(text) > 200 else text
        return ""

    def _build_meta_summary(self, meta_contract: dict) -> str:
        """构建元契约摘要。"""
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

    def _parse_evaluation_response(self, text: str) -> dict:
        """解析评估响应 JSON。"""
        data = _parse_json_object_from_text(text)
        if data is not None:
            score = int(data.get("score", 50))
            return {
                "score": max(0, min(100, score)),
                "dimensions": data.get("dimensions", {}),
                "issues": data.get("issues", []),
                "suggestions": data.get("suggestions", []),
            }

        return {
            "score": self.threshold,
            "dimensions": {"local_parse_fallback": self.threshold},
            "issues": ["远端大纲评估响应无法解析，已使用本地结构兜底评分"],
            "suggestions": ["保留原始契约大纲，不把不可解析响应写回 shot 合约"],
            "parse_error": True,
        }

    def _save_evaluation(
        self,
        shot_id: str,
        outline_text: str,
        evaluation: dict,
        *,
        attempt: int = 1,
        regenerated: bool = False,
        new_outline_text: str | None = None,
    ) -> str:
        """保存评估结果到数据库。"""
        evaluation_id = generate_ulid()
        self.db.execute(
            "INSERT INTO writing_outline_evaluations "
            "(evaluation_id, shot_id, run_id, attempt, outline_text, score, "
            "threshold, passed, dimensions_json, issues_json, suggestions_json, "
            "regenerated, new_outline_text, model_used) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                evaluation_id, shot_id, self.run_id, attempt,
                outline_text, evaluation["score"],
                self.threshold,
                1 if evaluation.get("passed") else 0,
                json.dumps(evaluation.get("dimensions", {}), ensure_ascii=False),
                json.dumps(evaluation.get("issues", []), ensure_ascii=False),
                json.dumps(evaluation.get("suggestions", []), ensure_ascii=False),
                1 if regenerated else 0,
                new_outline_text,
                evaluation.get("model_used", "unknown"),
            ),
        )
        self.db.commit()
        audit = AuditRecorder(self.db, run_id=self.run_id)
        audit.record_event(
            stage="outline_gate",
            event_type="outline_evaluated",
            status="passed" if evaluation.get("passed") else "failed",
            shot_id=shot_id,
            actor=evaluation.get("model_used", "unknown"),
            metrics={
                "score": evaluation["score"],
                "threshold": self.threshold,
                "attempt": attempt,
                "regenerated": regenerated,
            },
            payload={
                "issues": evaluation.get("issues", []),
                "suggestions": evaluation.get("suggestions", []),
                "new_outline_saved": bool(new_outline_text),
            },
            failure_category=None if evaluation.get("passed") else "outline_gap",
            failure_detail="; ".join(str(i) for i in evaluation.get("issues", [])[:3])
            if not evaluation.get("passed") else None,
        )
        if not evaluation.get("passed"):
            audit.record_failure_attribution(
                stage="outline_gate",
                failure_category="outline_gap",
                shot_id=shot_id,
                root_cause={
                    "score": evaluation["score"],
                    "threshold": self.threshold,
                    "issues": evaluation.get("issues", []),
                },
                evidence_refs={"evaluation_id": evaluation_id},
                suggested_action="重写或收紧 shot 大纲，再进入正文写作。",
            )
        return evaluation_id

    def _update_contract(self, shot_id: str, new_outline_text: str) -> None:
        """更新合约中的大纲。"""
        # 将新大纲写回 must_land_json，同时保留 title/event 等结构化字段。
        row = self.db.execute(
            "SELECT must_land_json FROM writing_shot_contracts "
            "WHERE shot_id = ? AND run_id = ?",
            (shot_id, self.run_id),
        ).fetchone()
        try:
            new_must_land = json.loads(row["must_land_json"] or "{}") if row else {}
        except (json.JSONDecodeError, TypeError):
            new_must_land = {}
        if not isinstance(new_must_land, dict):
            new_must_land = {}
        new_must_land["beats"] = new_outline_text
        self.db.execute(
            "UPDATE writing_shot_contracts SET must_land_json = ? "
            "WHERE shot_id = ? AND run_id = ?",
            (json.dumps(new_must_land, ensure_ascii=False), shot_id, self.run_id),
        )
        self.db.commit()


def _parse_json_object_from_text(text: str) -> dict | None:
    """Parse the first valid JSON object from model text.

    Some reasoning models prepend analysis before the requested JSON. The
    evaluator must not treat that as a bad outline or feed the analysis back
    into regeneration.
    """
    import re

    text = re.sub(r"<think>[\s\S]*?</think>", "", text or "", flags=re.IGNORECASE).strip()
    candidates: list[str] = []

    for match in re.finditer(r"```(?:json)?\s*([\s\S]*?)```", text, flags=re.IGNORECASE):
        candidates.append(match.group(1).strip())

    candidates.append(text)
    candidates.extend(_balanced_json_candidates(text))

    for candidate in candidates:
        candidate = candidate.strip()
        if not candidate:
            continue
        try:
            data = json.loads(candidate)
        except (json.JSONDecodeError, TypeError, ValueError):
            continue
        if isinstance(data, dict):
            return data
    return None


def _balanced_json_candidates(text: str) -> list[str]:
    candidates: list[str] = []
    starts = [idx for idx, char in enumerate(text or "") if char == "{"]
    for start in starts[:8]:
        depth = 0
        in_string = False
        escape = False
        for idx in range(start, len(text)):
            char = text[idx]
            if in_string:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == '"':
                    in_string = False
                continue
            if char == '"':
                in_string = True
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    candidates.append(text[start:idx + 1])
                    break
    return candidates


def _sanitize_regenerated_outline(text: str) -> str:
    text = (text or "").strip()
    if "```" in text:
        import re
        match = re.search(r"```(?:markdown|md|text)?\s*([\s\S]*?)```", text, flags=re.IGNORECASE)
        if match:
            text = match.group(1).strip()
    for marker in ("【大纲】", "大纲：", "## "):
        idx = text.find(marker)
        if idx > 0:
            text = text[idx:].strip()
            break
    return text


def _looks_like_prompt_analysis(text: str) -> bool:
    head = (text or "").strip()[:260]
    if not head:
        return True
    return any(marker in head for marker in _PROMPT_ANALYSIS_MARKERS)


def _outline_drift_too_large(original: str, regenerated: str, threshold: float = 0.20) -> bool:
    """Check if regenerated outline diverges too far from the original.

    A regenerated outline that shares almost no content with the original
    is likely a hallucination rather than a genuine improvement.
    Uses character bigram overlap for CJK-friendly comparison.
    Returns True when the overlap ratio is below *threshold*.
    """
    def _bigrams(text: str) -> set[str]:
        cleaned = (text or "").replace(" ", "").replace("\n", "")
        return {cleaned[i:i + 2] for i in range(len(cleaned) - 1)}

    orig_bg = _bigrams(original)
    regen_bg = _bigrams(regenerated)
    if not orig_bg or not regen_bg:
        return True
    overlap = orig_bg & regen_bg
    ratio = len(overlap) / min(len(orig_bg), len(regen_bg))
    return ratio < threshold
