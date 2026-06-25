"""Chapter Rhythm Architect (L1).

Assigns narrative_phase and deviation_budget to each shot in a chapter.
Uses LLM for creative judgment + rule engine for structural validation.

Inputs:
  - chapter events (from contract)
  - volume rhythm constraints (from L0.5, if available)

Outputs:
  - chapter_rhythm_map: {shot_index: {phase, budget, paragraph_length, sensory_pressure}}
"""

from __future__ import annotations

import json
import sqlite3

from inkflow.services.model_client import ModelClient, ModelRequest, ModelCallError


# 6 narrative phases with their default parameter ranges
PHASE_PARAMETERS = {
    "pulse": {
        "paragraph_length": [200, 400],
        "sensory_pressure": "高",
        "description": "高能量场景。段落短，节奏快。句子像心跳。",
    },
    "ripple": {
        "paragraph_length": [400, 600],
        "sensory_pressure": "中",
        "description": "余波场景。事件刚发生，涟漪在扩散。节奏放缓。",
    },
    "sediment": {
        "paragraph_length": [500, 800],
        "sensory_pressure": "低",
        "description": "日常沉积。段落可以长。重点在日常质感。",
    },
    "chaos": {
        "paragraph_length": [300, 500],
        "sensory_pressure": "高",
        "description": "揭示/反转。节奏不规则。信息释放要讲究。",
    },
    "fold": {
        "paragraph_length": [400, 600],
        "sensory_pressure": "中",
        "description": "时间/视角交织。节奏有层次感。",
    },
    "sublime": {
        "paragraph_length": [300, 600],
        "sensory_pressure": "中偏高",
        "description": "认知断裂。每个字都有分量。不要解释顿悟。",
    },
}

# Valid phases
VALID_PHASES = list(PHASE_PARAMETERS.keys())


class ChapterRhythmArchitect:
    """L1: Assigns rhythm parameters to each shot in a chapter."""

    def __init__(self, db: sqlite3.Connection, model_client: ModelClient):
        self.db = db
        self.model = model_client

    def analyze_chapter(
        self,
        chapter_key: str,
        chapter_events: list[dict],
        *,
        volume_constraints: dict | None = None,
        previous_chapter_rhythm: dict | None = None,
    ) -> dict:
        """Analyze chapter and assign rhythm parameters to each shot.

        Args:
            chapter_key: e.g. 'v01.c03'
            chapter_events: List of shot event dicts from contract
            volume_constraints: Optional L0.5 constraints (deviation_range, chapter_role)
            previous_chapter_rhythm: Optional L1 output from previous chapter

        Returns:
            chapter_rhythm_map dict
        """
        num_shots = len(chapter_events)
        if num_shots == 0:
            return {"shots": [], "validation": {"error": "No shots in chapter"}}

        # Step 1: Use LLM to assign phase + budget to each shot
        llm_result = self._llm_assign(chapter_key, chapter_events, volume_constraints)

        # Step 2: Validate with rule engine
        validation = self._validate_rhythm(llm_result, volume_constraints)

        # Step 3: If validation fails, retry (max 3 rounds)
        max_retries = 3
        retry_count = 0
        while not validation["all_pass"] and retry_count < max_retries:
            retry_count += 1
            llm_result = self._llm_reassign(
                chapter_key, chapter_events, llm_result, validation, volume_constraints
            )
            validation = self._validate_rhythm(llm_result, volume_constraints)

        # Step 4: Derive parameter ranges from phases
        shots_with_params = []
        for shot_assign in llm_result["shots"]:
            phase = shot_assign["narrative_phase"]
            params = PHASE_PARAMETERS.get(phase, PHASE_PARAMETERS["sediment"])
            shots_with_params.append({
                "shot_index": shot_assign["shot_index"],
                "narrative_phase": phase,
                "deviation_budget": shot_assign["deviation_budget"],
                "paragraph_length": params["paragraph_length"],
                "sensory_pressure": params["sensory_pressure"],
                "phase_description": params["description"],
                "shot_role": shot_assign.get("shot_role", "unknown"),
            })

        # Step 5: Cross-chapter衔接 check
        transition_note = ""
        if previous_chapter_rhythm:
            prev_last = previous_chapter_rhythm.get("shots", [{}])[-1]
            first_shot = shots_with_params[0] if shots_with_params else {}
            transition_note = self._check_cross_chapter_transition(
                prev_last, first_shot
            )

        return {
            "chapter_key": chapter_key,
            "shots": shots_with_params,
            "validation": validation,
            "retry_count": retry_count,
            "transition_note": transition_note,
            "mean_deviation_budget": (
                sum(s["deviation_budget"] for s in shots_with_params) / len(shots_with_params)
                if shots_with_params else 0
            ),
        }

    def _llm_assign(
        self,
        chapter_key: str,
        chapter_events: list[dict],
        volume_constraints: dict | None,
    ) -> dict:
        """Use LLM to assign narrative_phase and deviation_budget to each shot."""
        # Build prompt for LLM
        events_summary = []
        for i, ev in enumerate(chapter_events):
            events_summary.append({
                "shot_index": i + 1,
                "title": ev.get("title", ""),
                "pov": ev.get("pov", ""),
                "event_summary": ev.get("event", "")[:200],
            })

        constraint_text = ""
        if volume_constraints:
            budget_range = volume_constraints.get("deviation_range", [0.3, 0.7])
            chapter_role = volume_constraints.get("chapter_role", "rising")
            constraint_text = f"""
本章约束（来自卷级架构师）：
- 章角色: {chapter_role}
- deviation_budget 范围: [{budget_range[0]}, {budget_range[1]}]
- 每个 shot 的 deviation_budget 必须在此范围内
"""

        prompt = f"""你是一个小说节奏架构师。请为以下章节的每个 shot 分配叙事相位和留白预算。

章节: {chapter_key}

Shot 列表:
{json.dumps(events_summary, ensure_ascii=False, indent=2)}
{constraint_text}

## 6 种叙事相位
- pulse: 高能量冲突场景（段落短，节奏快）
- ripple: 余波扩散（节奏放缓）
- sediment: 日常沉积（段落长，节奏慢）
- chaos: 揭示/反转（节奏不规则）
- fold: 时间/视角交织（层次感）
- sublime: 认知断裂/顿悟（重量感）

## Shot 角色分类
- anchor（锚点）: foreshadow recovery、章末钩子、角色转折点 → deviation_budget 0.2-0.35
- breathing（呼吸）: 过渡、日常、环境描写 → deviation_budget 0.6-0.8

## 输出格式（严格 JSON）
{{
  "shots": [
    {{
      "shot_index": 1,
      "narrative_phase": "pulse|ripple|sediment|chaos|fold|sublime",
      "deviation_budget": 0.0-1.0,
      "shot_role": "anchor|breathing"
    }}
  ],
  "reasoning": "简要说明每个 shot 的分配理由"
}}

请输出 JSON："""

        try:
            response = self.model.generate(ModelRequest(
                operation="architect_chapter_rhythm",
                persona="architect",
                prompt=prompt,
                temperature=0.6,
                max_tokens=4096,
            ))
            result = json.loads(response.text)
            # Normalize shot indices
            for shot in result.get("shots", []):
                if "shot_index" not in shot:
                    shot["shot_index"] = result["shots"].index(shot) + 1
            return result
        except (json.JSONDecodeError, ModelCallError, KeyError) as e:
            # Fallback: assign default values
            return self._fallback_assign(chapter_events, volume_constraints)

    def _llm_reassign(
        self,
        chapter_key: str,
        chapter_events: list[dict],
        prev_result: dict,
        validation: dict,
        volume_constraints: dict | None,
    ) -> dict:
        """Ask LLM to fix validation failures."""
        failed_rules = [r for r, passed in validation.items() if not passed and r != "all_pass"]

        prompt = f"""上一次节奏分配有以下问题需要修复：
{json.dumps(failed_rules, ensure_ascii=False)}

上一次的分配结果：
{json.dumps(prev_result, ensure_ascii=False)}

请修复以上问题，重新输出完整的 JSON 分配结果。
保持输出格式不变。"""

        try:
            response = self.model.generate(ModelRequest(
                operation="architect_chapter_rhythm_retry",
                persona="architect",
                prompt=prompt,
                temperature=0.5,
                max_tokens=4096,
            ))
            result = json.loads(response.text)
            for shot in result.get("shots", []):
                if "shot_index" not in shot:
                    shot["shot_index"] = result["shots"].index(shot) + 1
            return result
        except (json.JSONDecodeError, ModelCallError):
            return prev_result  # Keep previous result if retry fails

    def _fallback_assign(
        self,
        chapter_events: list[dict],
        volume_constraints: dict | None,
    ) -> dict:
        """Deterministic fallback when LLM fails."""
        budget_range = [0.3, 0.7]
        if volume_constraints:
            budget_range = volume_constraints.get("deviation_range", [0.3, 0.7])

        shots = []
        for i, ev in enumerate(chapter_events):
            # Simple heuristic: last shot = anchor, others alternate
            is_last = (i == len(chapter_events) - 1)
            if is_last:
                phase = "sublime" if "顿悟" in ev.get("event", "") or "发现" in ev.get("event", "") else "pulse"
                budget = budget_range[0]  # Low budget for anchor
                role = "anchor"
            elif i % 2 == 0:
                phase = "sediment"
                budget = (budget_range[0] + budget_range[1]) / 2
                role = "breathing"
            else:
                phase = "ripple"
                budget = budget_range[1]  # Higher budget for breathing
                role = "breathing"

            shots.append({
                "shot_index": i + 1,
                "narrative_phase": phase,
                "deviation_budget": round(budget, 2),
                "shot_role": role,
            })

        return {"shots": shots, "reasoning": "Fallback assignment (LLM unavailable)"}

    def _validate_rhythm(
        self,
        result: dict,
        volume_constraints: dict | None,
    ) -> dict:
        """Rule engine validation of rhythm assignment."""
        shots = result.get("shots", [])
        validation = {}

        if not shots:
            validation["all_pass"] = False
            validation["error"] = "No shots assigned"
            return validation

        budgets = [s.get("deviation_budget", 0.5) for s in shots]
        phases = [s.get("narrative_phase", "sediment") for s in shots]

        # Rule 1: No 3 consecutive identical budgets
        rule1 = True
        for i in range(len(budgets) - 2):
            if abs(budgets[i] - budgets[i+1]) < 0.05 and abs(budgets[i+1] - budgets[i+2]) < 0.05:
                rule1 = False
                break
        validation["rule_1_no_3_consecutive_budgets"] = rule1

        # Rule 2: No 3 consecutive identical phases
        rule2 = True
        for i in range(len(phases) - 2):
            if phases[i] == phases[i+1] == phases[i+2]:
                rule2 = False
                break
        validation["rule_2_no_3_consecutive_phases"] = rule2

        # Rule 3: At least 1 breathing shot (budget > 0.5)
        rule3 = any(b > 0.5 for b in budgets)
        validation["rule_3_has_breathing_shot"] = rule3

        # Rule 4: At least 1 anchor shot (budget < 0.4)
        rule4 = any(b < 0.4 for b in budgets)
        validation["rule_4_has_anchor_shot"] = rule4

        # Rule 5: Mean budget within volume constraints range
        mean_budget = sum(budgets) / len(budgets)
        if volume_constraints:
            budget_range = volume_constraints.get("deviation_range", [0.0, 1.0])
            rule5 = budget_range[0] - 0.1 <= mean_budget <= budget_range[1] + 0.1
        else:
            rule5 = 0.3 <= mean_budget <= 0.7  # Default range
        validation["rule_5_mean_budget_in_range"] = rule5

        # Rule 6: All phases are valid
        rule6 = all(p in VALID_PHASES for p in phases)
        validation["rule_6_valid_phases"] = rule6

        # Rule 7: All budgets in [0, 1]
        rule7 = all(0 <= b <= 1 for b in budgets)
        validation["rule_7_budgets_in_range"] = rule7

        validation["all_pass"] = all([rule1, rule2, rule3, rule4, rule5, rule6, rule7])
        return validation

    def _check_cross_chapter_transition(
        self,
        prev_last_shot: dict,
        first_shot: dict,
    ) -> str:
        """Check if transition between chapters is smooth."""
        if not prev_last_shot or not first_shot:
            return ""

        prev_phase = prev_last_shot.get("narrative_phase", "")
        first_phase = first_shot.get("narrative_phase", "")

        # Same phase consecutively across chapters is not ideal
        if prev_phase == first_phase:
            return (
                f"注意：前一章末尾是 {prev_phase} 相位，本章开头也是 {first_phase}。"
                f"考虑在本章第一个 shot 做一些节奏变化。"
            )
        return ""

    def store_rhythm_map(self, chapter_rhythm_map: dict, run_id: str) -> str:
        """Store chapter rhythm map in DB."""
        rhythm_id = f"rhythm_{chapter_rhythm_map['chapter_key']}_{run_id}"
        self.db.execute(
            "INSERT OR REPLACE INTO writing_chapter_rhythms "
            "(rhythm_id, chapter_key, run_id, rhythm_map_json, validation_json) "
            "VALUES (?, ?, ?, ?, ?)",
            (
                rhythm_id,
                chapter_rhythm_map["chapter_key"],
                run_id,
                json.dumps(chapter_rhythm_map, ensure_ascii=False),
                json.dumps(chapter_rhythm_map.get("validation", {}), ensure_ascii=False),
            ),
        )
        self.db.commit()
        return rhythm_id
