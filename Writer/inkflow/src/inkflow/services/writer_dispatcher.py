"""双线/四线赛马写作调度器 (Writer Dispatcher)。

双线模式 (ARCH-8 前):
  赛道甲: 首用模型 (step-router-v1) → 草稿甲
  赛道乙: 备用模型 (qwen3.7-plus)   → 草稿乙
  共 2 份草稿，交由九评委评分选择。

四线模式 (ARCH-8+):
  4 个 persona × 风格方向 × 温度差异化
  - 意象师 (诗意, temp=0.95, deviation_multiplier=1.2)
  - 节奏师 (克制, temp=0.75, deviation_multiplier=0.8)
  - 对话师 (生活化, temp=0.85, deviation_multiplier=1.0)
  - 结构师 (极简, temp=0.60, deviation_multiplier=0.6)
  共 4 份草稿，交由九评委评分选择。

每线有链式兜底：首用失败 → 备用 → 兜底 → 本地兜底。
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
    resolve_model,
)
from inkflow.models.enums import ShotStatus
from inkflow.services.model_client import (
    ModelRequest,
    ModelClient,
    LocalDefaultGenerator,
    create_model_client,
    ModelCallError,
)
from inkflow.services.audit_recorder import AuditRecorder


# ARCH-8: 4-track persona style configuration
QUAD_TRACK_PERSONAS = {
    "意象师": {
        "style_direction": "诗意",
        "temperature_multiplier": 1.15,  # 0.8 * 1.15 ≈ 0.95
        "deviation_multiplier": 1.2,
        "style_injection": (
            "\n\n## 风格方向：诗意\n"
            "你是一个擅长感官细节、氛围、隐喻的作家。\n"
            "多用具体的感官意象。让每一个比喻都来自角色的日常经验。\n"
            "不要分析，让意象自己说话。"
        ),
    },
    "节奏师": {
        "style_direction": "克制",
        "temperature_multiplier": 0.94,  # 0.8 * 0.94 ≈ 0.75
        "deviation_multiplier": 0.8,
        "style_injection": (
            "\n\n## 风格方向：克制\n"
            "你是一个擅长控制句长、段落节奏和信息释放的作家。\n"
            "长短句交替。重要的信息放在短句中。\n"
            "不要堆砌形容词。让留白产生力量。"
        ),
    },
    "对话师": {
        "style_direction": "生活化",
        "temperature_multiplier": 1.0,  # 0.8 * 1.0 = 0.8
        "deviation_multiplier": 1.0,
        "style_injection": (
            "\n\n## 风格方向：生活化\n"
            "你是一个擅长对话、潜台词和声音差异的作家。\n"
            "用对话推进情节。每个角色说话的方式必须不同。\n"
            "潜台词比台词更重要。"
        ),
    },
    "结构师": {
        "style_direction": "极简",
        "temperature_multiplier": 0.75,  # 0.8 * 0.75 = 0.6
        "deviation_multiplier": 0.6,
        "style_injection": (
            "\n\n## 风格方向：极简\n"
            "你是一个擅长 POV 一致性、事实锚点和场景结构的作家。\n"
            "零废话。每个句子都必须推动场景。\n"
            "不要装饰，不要解释。用最少的字传递最多的信息。"
        ),
    },
}


class WriterDispatcher:
    """双线赛马写作调度器。

    Track A (赛道甲): primary model
    Track B (赛道乙): backup model
    每线生成 1 份草稿，共 2 份。
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

    def dispatch_dual_track(
        self,
        shot_id: str,
        compiled_prompt: str,
        *,
        attempt: int = 1,
    ) -> dict:
        """双线赛马：两个模型各写 1 份草稿。

        Args:
            shot_id: 目标 shot。
            compiled_prompt: 编译后的完整 prompt（两线共用）。
            attempt: 第几轮尝试（1=首次，2=重写）。

        Returns:
            {
                "shot_id": str,
                "drafts": [
                    {"draft_id": str, "track": "甲", "model_ref": str, "text": str, ...},
                    {"draft_id": str, "track": "乙", "model_ref": str, "text": str, ...},
                ],
                "attempt": int,
            }
        """
        self.db.execute(
            "UPDATE writing_shots SET shot_status = ?, updated_at = datetime('now') "
            "WHERE shot_id = ?",
            (ShotStatus.GENERATING, shot_id),
        )
        self.db.commit()

        chain = resolve_model_chain("writer", self.models_config)

        # 赛道甲 = 首用模型, 赛道乙 = 备用模型
        track_a_ref = chain[0] if len(chain) > 0 else "local-default"
        track_b_ref = chain[1] if len(chain) > 1 else chain[0] if chain else "local-default"

        drafts = []

        # 赛道甲
        draft_a = self._generate_track_draft(
            shot_id, "甲", track_a_ref, compiled_prompt, attempt,
        )
        drafts.append(draft_a)

        # 赛道乙
        draft_b = self._generate_track_draft(
            shot_id, "乙", track_b_ref, compiled_prompt, attempt,
        )
        drafts.append(draft_b)

        # 写入数据库
        result_drafts = []
        for idx, draft_data in enumerate(drafts):
            draft_id = generate_ulid()
            attempt_id = generate_ulid()

            self.db.execute(
                "INSERT INTO writing_drafts "
                "(draft_id, shot_id, run_id, writer_persona, writer_index, "
                "text, self_note, is_usable, attempt_id) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)",
                (
                    draft_id, shot_id, self.run_id,
                    f"赛道{draft_data['track']}",
                    idx,
                    draft_data["text"],
                    draft_data["self_note"],
                    attempt_id,
                ),
            )

            result_drafts.append({
                "draft_id": draft_id,
                "track": draft_data["track"],
                "model_ref": draft_data["model_ref"],
                "text": draft_data["text"],
                "self_note": draft_data["self_note"],
            })

        self.db.commit()
        self._record_draft_generated_events(shot_id, result_drafts, attempt=attempt)

        return {
            "shot_id": shot_id,
            "drafts": result_drafts,
            "attempt": attempt,
        }

    def _generate_track_draft(
        self,
        shot_id: str,
        track: str,
        model_ref: str,
        prompt: str,
        attempt: int,
    ) -> dict:
        """为单个赛道生成草稿。含链式兜底。"""
        chain = resolve_model_chain("writer", self.models_config)

        # 找到起始位置
        start_idx = 0
        for i, ref in enumerate(chain):
            if ref == model_ref:
                start_idx = i
                break

        # 链式尝试
        for ref in chain[start_idx:]:
            supplier, model_name = parse_model_ref(ref)
            providers_for_model = build_providers_for_model(ref, self.models_config)
            params = get_model_params(model_name, self.models_config)

            try:
                client = create_model_client(
                    model_name, db=self.db, providers=providers_for_model,
                )
                request = ModelRequest(
                    operation="write_generate",
                    persona=f"赛道{track}",
                    prompt=prompt,
                    model=model_name,
                    temperature=params.get("temperature", 0.8),
                    max_tokens=params.get("max_tokens", 16384),
                    shot_id=shot_id,
                    run_id=self.run_id,
                )
                response = client.generate(request)
                return {
                    "track": track,
                    "model_ref": ref,
                    "text": response.text,
                    "self_note": response.self_note or f"[{model_name}] 赛道{track}",
                }
            except (ModelCallError, ValueError):
                continue

        # 全部失败 → 本地兜底
        fallback = LocalDefaultGenerator(db=self.db)
        request = ModelRequest(
            operation="write_generate",
            persona=f"赛道{track}",
            prompt=prompt,
            shot_id=shot_id,
            run_id=self.run_id,
        )
        response = fallback.generate(request)
        return {
            "track": track,
            "model_ref": "local-default",
            "text": response.text,
            "self_note": f"[兜底:链式耗尽] 赛道{track}",
        }

    def mark_draft_usable(
        self, draft_id: str, gate1_result: dict | None = None,
    ) -> None:
        """标记草稿通过质量门1。"""
        if gate1_result is None:
            self.db.execute(
                "UPDATE writing_drafts SET is_usable = 1 WHERE draft_id = ?",
                (draft_id,),
            )
        else:
            self.db.execute(
                "UPDATE writing_drafts SET is_usable = 1, "
                "gate1_result_json = ? WHERE draft_id = ?",
                (
                    json.dumps(gate1_result, ensure_ascii=False),
                    draft_id,
                ),
            )
        self.db.commit()

    # ── ARCH-8: 四线赛马 ──

    def dispatch_quad_track(
        self,
        shot_id: str,
        base_prompt: str,
        *,
        persona_prompts: dict[str, str] | None = None,
        attempt: int = 1,
        deviation_budget: float | None = None,
        temperature_cap: float = 1.2,
        blank_shot: bool = False,
    ) -> dict:
        """四线赛马：4 个 persona × 风格方向 × 温度差异化。

        4 份草稿使用不同的 prompt 变体和温度，交给九评委择优。

        Args:
            shot_id: 目标 shot。
            base_prompt: 基础 prompt（所有 persona 共用）。
            attempt: 第几轮尝试。
            deviation_budget: 当前 shot 的 deviation_budget，用于调整各 persona 的有效温度。

        Returns:
            {
                "shot_id": str,
                "drafts": [
                    {"draft_id": str, "persona": "意象师", "style_direction": "诗意", ...},
                    ...
                ],
                "attempt": int,
            }
        """
        self.db.execute(
            "UPDATE writing_shots SET shot_status = ?, updated_at = datetime('now') "
            "WHERE shot_id = ?",
            (ShotStatus.GENERATING, shot_id),
        )
        self.db.commit()

        chain = resolve_model_chain("writer", self.models_config)
        primary_ref = chain[0] if chain else "local-default"

        drafts = []

        for persona_name, persona_config in QUAD_TRACK_PERSONAS.items():
            # Build persona-specific prompt
            persona_base_prompt = (persona_prompts or {}).get(persona_name) or base_prompt
            prompt_variant = persona_base_prompt + persona_config["style_injection"]

            # Calculate effective temperature
            base_params = get_model_params(
                parse_model_ref(primary_ref)[1], self.models_config
            )
            base_temp = base_params.get("temperature", 0.8)
            effective_temp = min(temperature_cap, base_temp * persona_config["temperature_multiplier"])

            # Adjust by deviation_budget if available
            if deviation_budget is not None:
                # Higher budget → slightly higher temp for more exploration
                budget_adjustment = (deviation_budget - 0.5) * 0.1
                effective_temp = min(temperature_cap, max(0.3, effective_temp + budget_adjustment))

            draft = self._generate_persona_draft(
                shot_id, persona_name, persona_config, primary_ref,
                prompt_variant, effective_temp, attempt,
            )
            drafts.append(draft)

        # Write to database
        result_drafts = []
        for idx, draft_data in enumerate(drafts):
            draft_id = generate_ulid()
            attempt_id = generate_ulid()

            self.db.execute(
                "INSERT INTO writing_drafts "
                "(draft_id, shot_id, run_id, writer_persona, writer_index, "
                "text, self_note, is_usable, attempt_id, model_ref, temperature, style_direction) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)",
                (
                    draft_id, shot_id, self.run_id,
                    draft_data["persona"],
                    idx,
                    draft_data["text"],
                    draft_data["self_note"],
                    attempt_id,
                    draft_data.get("model_ref", ""),
                    draft_data.get("temperature", 0.8),
                    draft_data.get("style_direction", ""),
                ),
            )

            result_drafts.append({
                "draft_id": draft_id,
                "persona": draft_data["persona"],
                "style_direction": draft_data["style_direction"],
                "temperature": draft_data["temperature"],
                "model_ref": draft_data["model_ref"],
                "text": draft_data["text"],
                "self_note": draft_data["self_note"],
            })

        self.db.commit()
        self._record_draft_generated_events(shot_id, result_drafts, attempt=attempt)

        # ARCH-11: Designate the first track (意象师, highest deviation_multiplier)
        # as the "deviant" track for soft-constraint deviation evaluation.
        deviant_track_idx = 0  # 意象师 is first in QUAD_TRACK_PERSONAS

        return {
            "shot_id": shot_id,
            "drafts": result_drafts,
            "attempt": attempt,
            "deviant_draft_id": result_drafts[deviant_track_idx]["draft_id"],
            "deviant_persona": result_drafts[deviant_track_idx]["persona"],
            "blank_shot": blank_shot,
        }

    def dispatch_single_persona_track(
        self,
        shot_id: str,
        base_prompt: str,
        persona_name: str,
        *,
        persona_prompts: dict[str, str] | None = None,
        attempt: int = 2,
        deviation_budget: float | None = None,
        temperature_cap: float = 1.2,
        blank_shot: bool = False,
    ) -> dict:
        """单线返写：只重写一个 persona，用于补足第 2 个过线稿。"""
        if persona_name not in QUAD_TRACK_PERSONAS:
            persona_name = "结构师"
        persona_config = QUAD_TRACK_PERSONAS[persona_name]
        chain = resolve_model_chain("writer", self.models_config)
        primary_ref = chain[0] if chain else "local-default"

        persona_base_prompt = (persona_prompts or {}).get(persona_name) or base_prompt
        prompt_variant = persona_base_prompt + persona_config["style_injection"]
        base_params = get_model_params(
            parse_model_ref(primary_ref)[1], self.models_config,
        )
        base_temp = base_params.get("temperature", 0.8)
        effective_temp = min(temperature_cap, base_temp * persona_config["temperature_multiplier"])
        if deviation_budget is not None:
            budget_adjustment = (deviation_budget - 0.5) * 0.1
            effective_temp = min(temperature_cap, max(0.3, effective_temp + budget_adjustment))

        draft_data = self._generate_persona_draft(
            shot_id, persona_name, persona_config, primary_ref,
            prompt_variant, effective_temp, attempt,
        )
        draft_id = generate_ulid()
        attempt_id = generate_ulid()
        self.db.execute(
            "INSERT INTO writing_drafts "
            "(draft_id, shot_id, run_id, writer_persona, writer_index, "
            "text, self_note, is_usable, attempt_id, model_ref, temperature, style_direction) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)",
            (
                draft_id, shot_id, self.run_id,
                draft_data["persona"],
                0,
                draft_data["text"],
                draft_data["self_note"],
                attempt_id,
                draft_data.get("model_ref", ""),
                draft_data.get("temperature", 0.8),
                draft_data.get("style_direction", ""),
            ),
        )
        self.db.commit()
        result = {
            "shot_id": shot_id,
            "drafts": [{
                "draft_id": draft_id,
                "persona": draft_data["persona"],
                "style_direction": draft_data["style_direction"],
                "temperature": draft_data["temperature"],
                "model_ref": draft_data["model_ref"],
                "text": draft_data["text"],
                "self_note": draft_data["self_note"],
            }],
            "attempt": attempt,
            "single_line_rewrite": True,
            "blank_shot": blank_shot,
        }
        self._record_draft_generated_events(shot_id, result["drafts"], attempt=attempt)
        return result

    def _generate_persona_draft(
        self,
        shot_id: str,
        persona_name: str,
        persona_config: dict,
        model_ref: str,
        prompt: str,
        temperature: float,
        attempt: int,
    ) -> dict:
        """Generate a draft for a specific persona with style direction."""
        chain = resolve_model_chain("writer", self.models_config)
        start_idx = 0
        for i, ref in enumerate(chain):
            if ref == model_ref:
                start_idx = i
                break

        for ref in chain[start_idx:]:
            supplier, model_name = parse_model_ref(ref)
            providers_for_model = build_providers_for_model(ref, self.models_config)
            params = get_model_params(model_name, self.models_config)

            try:
                client = create_model_client(
                    model_name, db=self.db, providers=providers_for_model,
                )
                request = ModelRequest(
                    operation="write_generate",
                    persona=persona_name,
                    prompt=prompt,
                    model=model_name,
                    temperature=temperature,
                    max_tokens=params.get("max_tokens", 16384),
                    shot_id=shot_id,
                    run_id=self.run_id,
                )
                response = client.generate(request)
                return {
                    "persona": persona_name,
                    "style_direction": persona_config["style_direction"],
                    "temperature": round(temperature, 3),
                    "model_ref": ref,
                    "text": response.text,
                    "self_note": response.self_note or f"[{model_name}] {persona_name}/{persona_config['style_direction']}",
                }
            except (ModelCallError, ValueError):
                continue

        fallback = LocalDefaultGenerator(db=self.db)
        request = ModelRequest(
            operation="write_generate",
            persona=persona_name,
            prompt=prompt,
            shot_id=shot_id,
            run_id=self.run_id,
        )
        response = fallback.generate(request)
        return {
            "persona": persona_name,
            "style_direction": persona_config["style_direction"],
            "temperature": round(temperature, 3),
            "model_ref": "local-default",
            "text": response.text,
            "self_note": f"[兜底:链式耗尽] {persona_name}/{persona_config['style_direction']}",
        }

    # ── 向后兼容 ──

    def _record_draft_generated_events(
        self,
        shot_id: str,
        drafts: list[dict],
        *,
        attempt: int,
    ) -> None:
        audit = AuditRecorder(self.db, run_id=self.run_id)
        for draft in drafts:
            audit.record_event(
                stage="writer",
                event_type="draft_generated",
                status="recorded",
                shot_id=shot_id,
                actor=draft.get("persona") or draft.get("track") or draft.get("writer_persona"),
                output_refs={
                    "draft_id": draft.get("draft_id"),
                    "model_ref": draft.get("model_ref"),
                },
                metrics={
                    "attempt": attempt,
                    "text_length": len(draft.get("text") or ""),
                    "temperature": draft.get("temperature"),
                },
                payload={
                    "style_direction": draft.get("style_direction"),
                    "self_note": draft.get("self_note"),
                },
                failure_category="model_failure"
                if draft.get("model_ref") == "local-default" else None,
                failure_detail="writer fallback to local-default"
                if draft.get("model_ref") == "local-default" else None,
            )

    def dispatch_race(
        self,
        shot_id: str,
        *,
        writer_count: int | None = None,
        tier: str = "light",
        compiled_prompts: dict[str, str] | None = None,
    ) -> dict:
        """[兼容] 旧接口。内部转发到 dispatch_dual_track()。"""
        # 取第一个可用的 prompt
        prompt = ""
        if compiled_prompts:
            for persona in ["意象师", "节奏师", "对话师"]:
                if persona in compiled_prompts:
                    prompt = compiled_prompts[persona]
                    break

        if not prompt:
            # 兜底：从合约构建简单 prompt
            contract_row = self.db.execute(
                "SELECT must_land_json FROM writing_shot_contracts "
                "WHERE shot_id = ? AND run_id = ?",
                (shot_id, self.run_id),
            ).fetchone()
            if contract_row:
                try:
                    must_land = json.loads(contract_row["must_land_json"] or "{}")
                    beats = must_land.get("beats", "")
                    if beats:
                        prompt = f"请直接写出以下场景的小说正文。\n\n{beats}"
                except Exception:
                    pass
            if not prompt:
                prompt = f"请为场景 {shot_id} 写一段小说正文。"

        return self.dispatch_dual_track(shot_id, prompt)

    def dispatch_race_with_escalation(
        self,
        shot_id: str,
        *,
        writer_count: int | None = None,
    ) -> dict:
        """[兼容] 旧接口。"""
        return self.dispatch_race(shot_id, writer_count=writer_count)

    def get_drafts(self, shot_id: str) -> list[dict]:
        """获取某个 shot 的所有草稿。"""
        rows = self.db.execute(
            "SELECT * FROM writing_drafts WHERE shot_id = ? ORDER BY writer_index",
            (shot_id,),
        ).fetchall()
        return [dict(r) for r in rows]
