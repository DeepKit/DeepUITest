"""Prompt Compiler (Service 2).

4-stage prompt compilation:
1. Static prefix: pre-compiled at setup (meta-contract, voice profiles, style locks)
2. Dynamic assembly: at runtime (previous shots, fact anchors, motif tracker state)
3. Assembly: combine static + dynamic, respecting token budget
4. Versioning: content-addressed hash for audit trail

P0: static prefix is pre-compiled; dynamic part is assembled per-shot.
Anthropic Prompt Caching uses static prefix as the cacheable prefix (≤4096 tokens).
"""

from __future__ import annotations

import json
import sqlite3

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.utils.hashing import snapshot_hash
from inkflow.services.suspense_profile import get_preset, build_suspense_directive
from inkflow.services.audit_recorder import AuditRecorder


# Token budget for P0
MAX_PROMPT_TOKENS = 8000
CACHE_BREAKPOINT_LIMIT = 4096
# Reserved token budget for response overhead (stop sequences, formatting)
TOKEN_BUDGET_PADDING = 100

# B23-P1: Previous shots degradation limits
PREVIOUS_SHOT_FULL_TEXT_LIMIT = 2   # Last N shots get full text injection
PREVIOUS_SHOT_SUMMARY_LIMIT = 5     # Up to N shots get one-line summary
# (N-6 to N-10 get aggregated event summary; beyond 10 dropped)


class PromptCompiler:
    """Compiles prompts for the writer race."""

    def __init__(self, db: sqlite3.Connection):
        self.db = db

    def compile_static_prefix(
        self,
        meta_contract: dict,
        writer_persona: str,
        voice_samples: list[dict] | None = None,
        anti_samples: list[dict] | None = None,
        *,
        suspense_blueprint: dict | None = None,
    ) -> dict:
        """Compile the static (cacheable) prefix of the prompt.

        This is compiled once at setup and reused across all shots.

        Args:
            suspense_blueprint: Optional suspense blueprint from contract-draft.yaml
                (preset name + chapter configs). Injects suspense engine directives.

        Returns:
            Dict with {prefix_text, prefix_length, prefix_hash}
        """
        parts = []

        # Layer 1: Writer identity (shared across all writers)
        parts.append(_build_writer_identity(writer_persona, meta_contract))

        # Layer 1: Hard boundaries and anti_reveal
        parts.append(_build_hard_constraints(meta_contract))

        # Layer 1: Style locks (always injected)
        parts.append(_build_style_locks(meta_contract))

        # Layer 1: Exposition replacement rules
        parts.append(_build_exposition_replacement_rules())

        # Layer 1: World knowledge
        parts.append(_build_world_knowledge(meta_contract))

        # Layer 1: Suspense directives (读者必须心里有问号)
        parts.append(_build_suspense_directives(meta_contract))

        # D-25: Suspense engine directives from blueprint
        if suspense_blueprint:
            preset_name = suspense_blueprint.get("preset", "institutional_suspense")
            try:
                profile = get_preset(preset_name)
                parts.append(build_suspense_directive(profile, suspense_blueprint))
            except KeyError:
                pass  # Unknown preset — skip suspense directives

        prefix_text = "\n\n".join(parts)
        prefix_length = _estimate_tokens(prefix_text)

        # LLM-5: Warn if static prefix exceeds 4096 token caching limit
        if prefix_length > CACHE_BREAKPOINT_LIMIT:
            import warnings
            warnings.warn(
                f"Static prefix length {prefix_length} tokens exceeds 4096 "
                f"Prompt Caching limit. Caching degraded for {writer_persona}.",
                stacklevel=2,
            )

        return {
            "prefix_text": prefix_text,
            "prefix_length": prefix_length,
            "prefix_hash": snapshot_hash({"prefix": prefix_text}),
            "cacheable": prefix_length <= CACHE_BREAKPOINT_LIMIT,
        }

    def compile_shot_prompt(
        self,
        shot_id: str,
        run_id: str,
        writer_persona: str,
        static_prefix: dict,
        shot_context: dict,
        *,
        previous_shots: list[dict] | None = None,
        fact_anchors: list[dict] | None = None,
        motif_tasks: dict | None = None,
        anti_samples: list[dict] | None = None,
    ) -> str:
        """Compile the full prompt for a shot + writer.

        Stores the compiled prompt in writing_shot_prompts.

        Returns:
            prompt_id
        """
        prompt_id = generate_ulid()

        # Dynamic assembly: context-dependent parts
        dynamic_parts = []

        # Shot context (contract, must_land, anti_write)
        dynamic_parts.append(_build_shot_context(shot_context))

        # Previous shots (N-1, N-2 full text; N-3~N-5 summaries)
        if previous_shots:
            dynamic_parts.append(_build_previous_shots(previous_shots))

        # Fact anchors
        if fact_anchors:
            dynamic_parts.append(_build_fact_anchors_section(fact_anchors))

        # Motif tasks
        if motif_tasks:
            dynamic_parts.append(_build_motif_tasks(motif_tasks))

        # Anti-samples (max 5 pairs)
        if anti_samples:
            dynamic_parts.append(_build_anti_samples(anti_samples))

        dynamic_text = "\n\n".join(dynamic_parts)
        dynamic_assembly = {
            "shot_context": shot_context,
            "previous_shot_count": len(previous_shots) if previous_shots else 0,
            "fact_anchor_count": len(fact_anchors) if fact_anchors else 0,
            "has_motif_tasks": motif_tasks is not None,
            "anti_sample_count": len(anti_samples) if anti_samples else 0,
        }
        context_payload = {
            "previous_shots": previous_shots or [],
            "fact_anchors": fact_anchors or [],
            "motif_tasks": motif_tasks or {},
            "anti_samples": anti_samples or [],
        }
        context_hash_value = snapshot_hash(_jsonable(context_payload))

        # Full assembly respecting token budget
        full_prompt = _assemble_with_budget(
            static_prefix["prefix_text"],
            dynamic_text,
            max_tokens=MAX_PROMPT_TOKENS,
        )

        # Append final writing instruction
        full_prompt += (
            "\n\n---\n"
            "## 现在开始写\n\n"
            "写出这个场景的小说正文。不要分析，不要评论，不要解释。\n"
            "主题、系统、资源分配和人物处境只能通过动作、物件、身体反应、对话和环境后果显出来。\n"
            "直接写出故事。第一个字就是小说的正文。"
        )

        self.db.execute(
            "INSERT OR IGNORE INTO writing_shot_prompts "
            "(prompt_id, shot_id, run_id, writer_persona, prompt_hash, "
            "static_prefix, static_prefix_length, dynamic_assembly_json, "
            "assembled_prompt) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (prompt_id, shot_id, run_id, writer_persona,
             snapshot_hash({"full": full_prompt}),
             static_prefix["prefix_text"],
             static_prefix["prefix_length"],
             json.dumps(dynamic_assembly, ensure_ascii=False),
             full_prompt),
        )
        self.db.execute(
            "INSERT INTO writing_context_snaps "
            "(snap_id, shot_id, run_id, context_hash, previous_shots_json, "
            "fact_anchor_refs_json, motif_tracker_state_json, anti_samples_json, "
            "injected_with_warning) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)",
            (
                generate_ulid(), shot_id, run_id, context_hash_value,
                json.dumps(_jsonable(previous_shots or []), ensure_ascii=False),
                json.dumps(_jsonable(fact_anchors or []), ensure_ascii=False),
                json.dumps(_jsonable(motif_tasks or {}), ensure_ascii=False),
                json.dumps(_jsonable(anti_samples or []), ensure_ascii=False),
            ),
        )
        self.db.commit()
        AuditRecorder(self.db, run_id=run_id).record_event(
            stage="prompt",
            event_type="prompt_compiled",
            status="recorded",
            shot_id=shot_id,
            actor=writer_persona,
            output_refs={"prompt_id": prompt_id, "prompt_hash": snapshot_hash({"full": full_prompt})},
            metrics={
                "static_prefix_length": static_prefix["prefix_length"],
                "assembled_prompt_length": len(full_prompt),
                "previous_shot_count": dynamic_assembly["previous_shot_count"],
                "fact_anchor_count": dynamic_assembly["fact_anchor_count"],
            },
            payload={"dynamic_assembly": dynamic_assembly},
        )
        return prompt_id

    def get_shot_prompt(self, shot_id: str, run_id: str, writer_persona: str) -> dict | None:
        """Get the compiled prompt for a shot + writer."""
        row = self.db.execute(
            "SELECT * FROM writing_shot_prompts "
            "WHERE shot_id = ? AND run_id = ? AND writer_persona = ?",
            (shot_id, run_id, writer_persona),
        ).fetchone()
        if row is None:
            return None
        result = dict(row)
        result["dynamic_assembly_json"] = json.loads(result["dynamic_assembly_json"])
        return result


# ── Prompt section builders ──

def _build_writer_identity(persona: str, meta_contract: dict) -> str:
    """Build the writer identity section."""
    persona_descriptions = {
        "意象师": "你是一个小说作家，笔名意象师。你擅长感官细节、氛围、隐喻。\n"
                   "【重要】你的任务是直接写出小说正文。不要分析作品，不要评论叙事技巧，不要解释意象的含义。直接写。",
        "节奏师": "你是一个小说作家，笔名节奏师。你擅长控制句长、段落节奏和信息释放。\n"
                   "【重要】你的任务是直接写出小说正文。不要分析情节结构，不要评论叙事手法，不要总结。直接写。",
        "对话师": "你是一个小说作家，笔名对话师。你擅长对话、潜台词和声音差异。\n"
                   "【重要】你的任务是直接写出小说正文。不要分析人物动机，不要评论对话技巧，不要解释潜台词。直接写。",
        "结构师": "你是一个小说作家，笔名结构师。你擅长POV一致性、事实锚点和场景结构。\n"
                   "【重要】你的任务是直接写出小说正文。不要分析叙事结构，不要评论POV切换，不要总结。直接写。",
    }
    identity = meta_contract.get("identity", {})
    narrative_voice = meta_contract.get("narrative_voice", {})

    return f"""{persona_descriptions.get(persona, '')}

作品身份: {json.dumps(identity, ensure_ascii=False)}
叙事声音: {json.dumps(narrative_voice, ensure_ascii=False)}"""


def _jsonable(value):
    return json.loads(json.dumps(value, ensure_ascii=False, default=str))


def _build_hard_constraints(meta_contract: dict) -> str:
    """Build hard boundaries and anti_reveal section."""
    hard = meta_contract.get("hard_boundaries", {})
    anti = meta_contract.get("anti_reveal", {})

    lines = ["## 硬边界（不可违反）"]
    if hard:
        lines.append(json.dumps(hard, ensure_ascii=False, indent=2))
    if anti:
        lines.append("### 不得揭露的信息")
        lines.append(json.dumps(anti, ensure_ascii=False, indent=2))
    return "\n".join(lines)


def _build_style_locks(meta_contract: dict) -> str:
    """Build style iron rules section."""
    style = meta_contract.get("style_locks", {})
    base = f"## 风格铁律\n{json.dumps(style, ensure_ascii=False, indent=2)}"
    # OPT-5: Precision detail requirement
    precision_rule = (
        '\n\n### 精确细节（每个 shot 必须包含至少一个）\n'
        '精确细节不是感官堆叠——是观察力的精度。\n'
        '例子：\n'
        '- “他端杯子时水面多晃了一下”（暗示手在变弱，只有天天沏茶的人才看得出来）\n'
        '- “护膝放在柜子里没扔”（人和物件的关系，暗示不舍）\n'
        '- “杯沿抵在嘴唇上却没喝”（动作的不对称暗示内心状态）\n'
        '- “他说少放糖的次数从三次变成六次”（频率变化暗示健康在恶化）\n'
        '这种细节必须来自角色的日常观察，不是叙述者的分析。'
    )
    return base + precision_rule


def _build_exposition_replacement_rules() -> str:
    """Build concrete anti-exposition instructions for writer models."""
    return (
        "## 显影规则（硬要求）\n"
        "不要把主题、系统、资源分配、人物处境或阵营关系直接说出来。\n"
        "写作时如果想写“这意味着、系统并不恶意、它只是、本质上、逻辑结构、资源分配、低效率、直接回报、闭环”，必须删除。\n"
        "替代方式只能选以下五类：\n"
        "- 动作：角色被迫停下、改路、排队、按下、收回手。\n"
        "- 物件：屏幕通知、票根、胶带、临时单、杯沿、门禁灯发生变化。\n"
        "- 身体：膝盖疼、手抖、呼吸变短、汗浸湿胶带。\n"
        "- 对话：只让角色说当下要办的事，不解释制度原理。\n"
        "- 环境后果：窗口关闭、号码过期、地图改线、队伍被改道。\n"
        "系统只能作为环境出现：通知、屏幕、排队、拒绝、延迟、扣回、改派。不要解释系统为什么这样做。"
    )


def _build_world_knowledge(meta_contract: dict) -> str:
    """Build world knowledge section."""
    world = meta_contract.get("world_knowledge", {})
    if not world:
        return ""
    return f"## 世界观\n{json.dumps(world, ensure_ascii=False, indent=2)}"


def _build_suspense_directives(meta_contract: dict) -> str:
    """Build suspense engine directives from contract.

    Three core mandates:
    1. Per-shot: 章末必须是未完成动作，不是感官收束
    2. Per-shot: 至少一个数字+体温或物件的理解变化
    3. Cross-shot: 读者知道但角色不知道的信息差
    """
    sc = meta_contract.get("suspense_config", {})
    if not sc:
        return ""

    parts = ["## 悬疑引擎（必须遵守）"]

    # 1. Reader anchor — 读者替谁急
    anchor = sc.get("reader_anchor", "")
    if anchor:
        parts.append(f"\n读者此刻心里应该有这个问题：{anchor}")

    # 2. Information gap — 读者知道，角色不知道
    gaps = sc.get("information_gap", [])
    if gaps:
        parts.append("\n### 信息差（读者知道，角色不知道）")
        parts.append("你可以在本章中让读者知道以下信息，但角色不知道。")
        parts.append("使用错位共鸣：让读者带着信息去审视角色遇到的每一个人。")
        for gap in gaps:
            parts.append(f"- {gap}")

    # 3. Core objects with evolving meaning
    objects = sc.get("core_objects", {})
    if objects:
        parts.append("\n### 核心物件（每次出现理解不同）")
        parts.append("以下物件是悬疑锚点。它们每次出现时，读者对它的理解必须不同。")
        parts.append("第一次出现是背景，第二次是线索，第三次是证据。")
        for obj_name, obj_rule in objects.items():
            parts.append(f"- **{obj_name}**: {obj_rule}")

    # 4. Chapter hook rule
    hooks = sc.get("chapter_hooks", [])
    if hooks:
        parts.append("\n### 章末钩子（必须执行）")
        for hook in hooks:
            parts.append(f"- {hook}")

    # 5. Numbers with temperature
    numbers = sc.get("numbers_with_temperature", [])
    if numbers:
        parts.append("\n### 数字有体温")
        parts.append("任何倒计时或数字，必须在同一句或下一句紧跟一个具体的人或物。")
        parts.append("数字出现前，应已提前释放那个人的不可逆损伤画面。")
        for n in numbers:
            parts.append(f"- {n}")

    # 6. Foreshadowing rule
    parts.append("\n### 预埋种植")
    parts.append("每个关键物件首次出现时，先展示其后果或外观，延迟至少一句再给名字。")
    parts.append("抽象概念先展示它造成的后果，延迟至少三章再给名字。")

    return "\n".join(parts)


def _build_shot_context(shot_context: dict) -> str:
    """Build per-shot context section.

    Supports two formats:
    1. Three-layer deviation format (ARCH-1): hard_facts / soft_constraints / reference
    2. Legacy must_land format (backward compatible)

    Also injects deviation_budget (ARCH-2) and narrative_phase (ARCH-3) when present.
    """
    parts = []

    # ARCH-1: Three-layer deviation taxonomy (preferred) vs legacy must_land
    hard_facts = shot_context.get("hard_facts")
    soft_constraints = shot_context.get("soft_constraints")
    reference = shot_context.get("reference")

    if hard_facts is not None:
        # Three-layer format
        parts.extend(_build_three_layer_context(hard_facts, soft_constraints, reference))
    else:
        # Legacy must_land format (backward compatible)
        parts.extend(_build_must_land_context(shot_context))

    # POV isolation: the most important constraint
    anti_write = shot_context.get("anti_write", {})
    pov_only = anti_write.get("pov_only", "") if isinstance(anti_write, dict) else ""
    forbidden = anti_write.get("forbidden", "") if isinstance(anti_write, dict) else ""
    if pov_only or forbidden:
        parts.append("## 视角约束（严格遵守）")
        if pov_only:
            parts.append(f"⚠️ {pov_only}")
        if forbidden:
            parts.append(f"⚠️ {forbidden}")
    elif anti_write and not isinstance(anti_write, dict):
        parts.append(f"禁止书写: {json.dumps(anti_write, ensure_ascii=False)}")

    exit_to = shot_context.get("exit_to", {})
    if exit_to:
        parts.append(f"出口状态: {json.dumps(exit_to, ensure_ascii=False)}")

    # OPT-2: Per-shot sensory density directives
    sensory_pressure = shot_context.get("sensory_pressure")
    dominant_sense = shot_context.get("dominant_sense")
    if sensory_pressure or dominant_sense:
        parts.append("## 感官密度指令")
        if sensory_pressure == "高":
            parts.append(
                "本场景感官要密——气味、温度、湿度、声音、触觉交织在一起，"
                "让读者感到压迫。��段至少叠加两种感官。"
            )
        elif sensory_pressure == "中":
            parts.append(
                "本场景感官保持正常密度——每段一到两种感官，不要堆叠。"
            )
        elif sensory_pressure == "低":
            parts.append(
                "本场景感官要稀薄——空旷、安静、留白多。"
                "不要堆叠感官细节。让沉默和空白本身成为一种感官。"
            )
        if dominant_sense:
            parts.append(f"主打感官：{dominant_sense}。其他感官可以出现但不要抢。")

    # OPT-6: Emotional transition bridge
    entry_mood = shot_context.get("entry_mood")
    if entry_mood:
        parts.append(f"## 情绪入口\n{entry_mood}")

    # ARCH-2: deviation_budget — communicate creative freedom level
    deviation_budget = shot_context.get("deviation_budget")
    if deviation_budget is not None:
        parts.append(_build_deviation_directive(deviation_budget))

    # ARCH-3: narrative_phase — communicate rhythm role
    narrative_phase = shot_context.get("narrative_phase")
    if narrative_phase:
        parts.append(_build_phase_directive(narrative_phase))

    chapter_setup = shot_context.get("chapter_setup")
    if isinstance(chapter_setup, dict) and chapter_setup:
        parts.extend(_build_chapter_setup_context(chapter_setup))

    task_card = shot_context.get("task_card")
    if isinstance(task_card, dict) and task_card:
        parts.extend(_build_task_card_context(task_card))

    # ARCH-7: Non-interference declaration
    parts.append(_build_non_interference_declaration())

    return chr(10).join(parts)


def _build_chapter_setup_context(chapter_setup: dict) -> list[str]:
    """Build chapter preflight directives captured by `ink setup --chapter`."""
    parts = ["## 章前校准（必须执行）"]

    shot_setup = chapter_setup.get("shot") or {}
    if isinstance(shot_setup, dict):
        roles = shot_setup.get("type_roles") or []
        if roles:
            parts.append("本 shot 的类型职责: " + ", ".join(str(r) for r in roles))

        anti_patterns = shot_setup.get("anti_patterns") or []
        if anti_patterns:
            parts.append("本 shot 禁止写法:")
            for item in anti_patterns:
                parts.append(f"- {item}")

    exposition_gate = chapter_setup.get("exposition_gate") or {}
    if isinstance(exposition_gate, dict) and exposition_gate.get("enabled", True):
        rule = exposition_gate.get("rule")
        if rule:
            parts.append(f"概念显影规则: {rule}")

        forbidden = exposition_gate.get("forbidden_phrases") or []
        if forbidden:
            parts.append("禁止由叙述者直接说出的议论词/句:")
            for item in forbidden:
                parts.append(f"- {item}")

        repair_instruction = exposition_gate.get("repair_instruction")
        if repair_instruction:
            parts.append(f"替代写法: {repair_instruction}")
        parts.append(
            "执行方式: 看见抽象词时立刻转成可见后果。"
            "用屏幕通知、排队阻滞、物件变化、身体反应、沉默或短对话承载，不写制度解释。"
        )

    chapter_hook = chapter_setup.get("chapter_hook") or {}
    if isinstance(chapter_hook, dict) and chapter_hook.get("required"):
        requirements = chapter_hook.get("requirements") or []
        if requirements:
            parts.append("章末钩子要求:")
            for item in requirements:
                parts.append(f"- {item}")

    return parts


def _build_task_card_context(task_card: dict) -> list[str]:
    """Build the machine-checkable task card section."""
    parts = ["## Shot Task Card（必须执行）"]
    title = task_card.get("title")
    pov = task_card.get("pov")
    if title:
        parts.append(f"标题: {title}")
    if pov:
        parts.append(f"POV: {pov}")
    must_land = task_card.get("must_land")
    if must_land:
        parts.append("必须落地:")
        parts.append(str(must_land))
    hard_facts = task_card.get("hard_facts") or []
    if hard_facts:
        parts.append("硬事实:")
        for item in hard_facts:
            parts.append(f"- {item}")
    type_roles = task_card.get("type_roles") or []
    if type_roles:
        parts.append("类型职责: " + ", ".join(str(role) for role in type_roles))
    if task_card.get("hook_required"):
        parts.append("章末钩子: 最后一段必须留下未完成动作或未回答问题，不能解释性收束。")
    forbidden = task_card.get("forbidden_phrases") or []
    if forbidden:
        parts.append("硬门禁禁词/禁句:")
        for item in forbidden[:20]:
            parts.append(f"- {item}")
    outline = task_card.get("outline")
    if outline:
        parts.append("大纲裁定稿:")
        parts.append(str(outline))
    return parts


def _build_three_layer_context(
    hard_facts: list | None,
    soft_constraints: list | None,
    reference: dict | None,
) -> list[str]:
    """Build three-layer deviation context (ARCH-1).

    hard_facts: 不可偏离的硬事实
    soft_constraints: 建议遵守但允许偏离的软约束
    reference: 灵感参考（不检查，不约束）
    """
    parts = []

    parts.append(
        "## 写作任务" + chr(10) + chr(10) +
        "你是一个小说作家。请直接写出以下场景的正文。" + chr(10) +
        "不要分析，不要总结，不要评论。直接开始写小说。" + chr(10)
    )

    # Layer 1: Hard facts (不可偏离)
    if hard_facts:
        parts.append("## 硬事实（不可偏离）")
        parts.append("以下事件必须发生，顺序可以调整，但每个都必须落地：")
        for fact in hard_facts:
            parts.append(f"- {fact}")

    # Layer 2: Soft constraints (允许偏离)
    if soft_constraints:
        parts.append("")
        parts.append("## 软约束（建议遵守，允许表达偏离）")
        for sc in soft_constraints:
            parts.append(f"- {sc}")
        parts.append("")
        parts.append("以上约束你可以偏离——如果你的偏离产生了更好的文本。偏离不需要解释。")

    # Layer 3: Reference (灵感参考，不检查)
    if reference:
        parts.append("")
        parts.append("## 灵感参考（不检查，不约束）")
        style_dir = reference.get("style_direction", "")
        if style_dir:
            parts.append(f"- 风格方向：{style_dir}")
        example = reference.get("example_text", "")
        if example:
            parts.append(f'- 示例："{example}"')
        motif_conn = reference.get("motif_connection", "")
        if motif_conn:
            parts.append(f"- Motif 关联：{motif_conn}")

    parts.append("")
    parts.append("现在开始写。")
    return parts


def _build_must_land_context(shot_context: dict) -> list[str]:
    """Build legacy must_land context (backward compatible)."""
    parts = []
    must_land = shot_context.get("must_land", {})

    if must_land:
        title = must_land.get("title", "")
        beats = must_land.get("beats", "")
        if beats:
            beat_lines = [b.strip().lstrip('- ') for b in beats.split(chr(10)) if b.strip()]
            content_lines = [b for b in beat_lines if not b.startswith('#')]
            first_beat = content_lines[0] if content_lines else (beat_lines[0] if beat_lines else "")
            remaining_beats = chr(10).join(f'- {b}' for b in content_lines[1:]) if len(content_lines) > 1 else ""

            if title:
                parts.append(f"## {title}" + chr(10))

            parts.append(
                "## 写作任务" + chr(10) + chr(10) +
                "你是一个小说作家。请直接写出以下场景的正文。" + chr(10) +
                "不要分析，不要总结，不要评论。直接开始写小说。" + chr(10) + chr(10)
            )
            if first_beat:
                parts.append(f"第一句话以「{first_beat}」开头，然后继续写。" + chr(10))
            if remaining_beats:
                parts.append(f"场景要点：" + chr(10) + f"{remaining_beats}" + chr(10))
            parts.append("现在开始写。")
        else:
            event_text = must_land.get("event", "")
            if event_text:
                parts.append(f"必须落地: {json.dumps(must_land, ensure_ascii=False)}")

    return parts


def _build_deviation_directive(deviation_budget: float) -> str:
    """Build deviation budget directive (ARCH-2).

    deviation_budget: 0.0 = max constraint, 1.0 = max freedom
    """
    if deviation_budget <= 0.2:
        return (
            "## 留白预算：极低（精确模式）\n"
            "这个场景是锚点时刻。硬事实必须精确落地。\n"
            "表达方式可以微调，但不要偏离事件核心。"
        )
    elif deviation_budget <= 0.4:
        return (
            "## 留白预算：低（收敛模式）\n"
            "这个场景需要精确控制。硬事实不可偏离，软约束尽量遵守。\n"
            "你有少量表达空间——用来打磨句子的质感，不是改变事件走向。"
        )
    elif deviation_budget <= 0.6:
        return (
            "## 留白预算：中等（平衡模式）\n"
            "硬事实必须落地。软约束是建议，不是命令。\n"
            "你可以在表达方式上自由发挥，只要不违反硬事实。"
        )
    elif deviation_budget <= 0.8:
        return (
            "## 留白预算：高（呼吸模式）\n"
            "这是一个呼吸场景。硬事实很少，软约束是灵感，不是枷锁。\n"
            "你有大量自由空间——探索人物的日常、环境的细��、内心的微妙变化。\n"
            "不要急于推进情节。让场景自己生长。"
        )
    else:
        return (
            "## 留白预算：极高（探索模式）\n"
            "这个场景几乎完全开放。只有最基本的硬事实约束。\n"
            "你可以大胆探索——意外的意象、非常规的叙事角度、出人意料的细节。\n"
            "追求的不是安全，而是惊喜。"
        )


def _build_phase_directive(narrative_phase: str) -> str:
    """Build narrative phase directive (ARCH-3).

    6 phases: chaos / pulse / ripple / sediment / fold / sublime
    """
    phase_descriptions = {
        "pulse": (
            "## 叙事相位：Pulse（脉冲）\n"
            "这是高能量场景。段落要短（200-400 字），节奏要快。\n"
            "句子像心跳——一下一下，不给读者喘息空间。\n"
            "感官密度高，信息释放快。"
        ),
        "ripple": (
            "## 叙事相位：Ripple（涟漪）\n"
            "这是余波场景。一个事件刚刚发生，涟漪在扩散。\n"
            "段落中等长度（400-600 字）。节奏放缓但不静止。\n"
            "人物在消化刚才发生的事。读者也在消化。"
        ),
        "sediment": (
            "## 叙事相位：Sediment（沉积）\n"
            "这是日常沉积场景。没有大事件，但细节在积累。\n"
            "段落可以长一些（500-800 字）。节奏缓慢，像沉积物一层一层落下。\n"
            "重点在日常的质感——物件、习惯、微小的变化。"
        ),
        "chaos": (
            "## 叙事相位：Chaos（混沌）\n"
            "这是揭示/反转场景。读者的认知被打破。\n"
            "段落中等（300-500 字），节奏不规则——突然加速又突然停止。\n"
            "信息释放要讲究：先给碎片，再给全貌。"
        ),
        "fold": (
            "## 叙事相位：Fold（折叠）\n"
            "这是时间/视角交织场景。多条线在这一刻重叠。\n"
            "段落中等（400-600 字）。节奏有层次感——不同时间线的切换要自然。\n"
            "读者应该感到时间的厚度。"
        ),
        "sublime": (
            "## 叙事相位：Sublime（崇高/顿悟）\n"
            "这是认知断裂场景。人物（或读者）的世界观在这一刻裂开。\n"
            "段落灵活（300-600 字）。节奏要有重量感——每个字都有分量。\n"
            "不要解释顿悟。展示它发生的过程。让读者自己感受到裂开。"
        ),
    }
    return phase_descriptions.get(narrative_phase, f"## 叙事相位：{narrative_phase}")


def _build_non_interference_declaration() -> str:
    """Build non-interference declaration (ARCH-7).

    Explicitly tells the AI what the system will NOT check.
    """
    return (
        "## 不干预声明\n"
        "以下维度不在系统检查范围内，完全由你决定：\n"
        "- 读者的个人联想和情感反应\n"
        "- 具体的意象选择和隐喻构造\n"
        "- 句子的节奏和长度变化（只要在叙事相位范围内）\n"
        "- 审美偏好和文学风格\n"
        "- 场景的感官细节组合\n"
        "你不需要为这些维度的选择辩护。"
    )
def _build_previous_shots(previous_shots: list[dict]) -> str:
    """Build previous shots context section with summary degradation (B23-P1).

    Degradation levels:
    - Last N shots (PREVIOUS_SHOT_FULL_TEXT_LIMIT): full text injection
    - N-2 to N-5 (PREVIOUS_SHOT_SUMMARY_LIMIT): one-line summary (first 100 chars)
    - N-6 to N-10 (PREVIOUS_SHOT_AGGREGATE_LIMIT): aggregated bullet summary
    - Beyond 10: dropped entirely
    """
    if not previous_shots:
        return ""

    parts = ["## 前文上下文"]
    total = len(previous_shots)

    # Level 1: Full text for most recent shots
    full_text_start = max(0, total - PREVIOUS_SHOT_FULL_TEXT_LIMIT)
    full_text_shots = previous_shots[full_text_start:]
    if full_text_shots:
        parts.append("### 最近上下文（完整）")
        for shot in full_text_shots:
            text = shot.get("text", "").replace("\n", " ")
            parts.append(f"Shot {shot.get('shot_index', '?')}: {text}")

    # Level 2: One-line summary for earlier shots
    summary_start = max(0, total - PREVIOUS_SHOT_SUMMARY_LIMIT)
    summary_shots = previous_shots[summary_start:full_text_start]
    if summary_shots:
        parts.append("### 较早上下文（摘要）")
        for shot in summary_shots:
            text = shot.get("text", "")[:100].replace("\n", " ")
            parts.append(f"Shot {shot.get('shot_index', '?')}: {text}...")

    # Level 3: Aggregated summary for shots beyond summary limit
    aggregate_shots = previous_shots[:summary_start]
    if aggregate_shots and len(aggregate_shots) <= 5:
        parts.append("### 更早上下文（事件摘要）")
        for shot in aggregate_shots:
            # Extract first sentence as event summary
            text = shot.get("text", "")
            first_sentence = text.split("。")[0] if "。" in text else text[:60]
            if first_sentence:
                parts.append(f"- Shot {shot.get('shot_index', '?')}: {first_sentence}")

    return "\n".join(parts)


def _build_fact_anchors_section(fact_anchors: list[dict]) -> str:
    """Build fact anchors section."""
    if not fact_anchors:
        return ""

    parts = ["## 事实锚点"]
    for anchor in fact_anchors[:20]:  # Cap at 20 anchors
        parts.append(
            f"- [{anchor.get('anchor_type', '?')}] {anchor.get('anchor_key')}: "
            f"{anchor.get('anchor_value')}"
        )
    return "\n".join(parts)


def _build_motif_tasks(motif_tasks: dict) -> str:
    """Build motif tasks section."""
    required = motif_tasks.get("required", [])
    suggested = motif_tasks.get("suggested", [])
    forbidden = motif_tasks.get("forbidden", [])

    parts = ["## 意象任务"]
    if required:
        parts.append(f"必须出现: {', '.join(required)}")
    if suggested:
        parts.append(f"建议出现: {', '.join(suggested)}")
    if forbidden:
        parts.append(f"禁止出现: {', '.join(forbidden)}")
    return "\n".join(parts)


def _build_anti_samples(anti_samples: list[dict]) -> str:
    """Build anti-samples section (max 5 pairs)."""
    if not anti_samples:
        return ""

    parts = ["## 反例参考"]
    for i, sample in enumerate(anti_samples[:5]):
        parts.append(f"\n### 反例 {i + 1}")
        if sample.get("bad"):
            parts.append(f"❌ 避免: {sample['bad'][:200]}")
        if sample.get("good"):
            parts.append(f"✅ 参考: {sample['good'][:200]}")
    return "\n".join(parts)


def _assemble_with_budget(static_prefix: str, dynamic_text: str, max_tokens: int) -> str:
    """Assemble prompt respecting token budget with summary degradation (B23-P1).

    Compression priority (when over budget):
    1. Degrade previous shots: full text → one-line summary → aggregated bullets → drop
    2. Reduce anti-samples
    3. Truncate remaining dynamic text
    Never compress: hard boundaries, anti_reveal, current shot contract, fact anchors.
    """
    full = f"{static_prefix}\n\n{dynamic_text}"
    estimated = _estimate_tokens(full)

    if estimated <= max_tokens:
        return full

    # Step 1: Degrade previous shots section if present
    degraded_dynamic = _degrade_previous_shots(dynamic_text, max_tokens)

    degraded_full = f"{static_prefix}\n\n{degraded_dynamic}"
    degraded_estimate = _estimate_tokens(degraded_full)

    if degraded_estimate <= max_tokens:
        return degraded_full

    # Step 2: Still over budget — truncate dynamic section
    budget_for_dynamic = max_tokens - _estimate_tokens(static_prefix) - TOKEN_BUDGET_PADDING
    if budget_for_dynamic <= 0:
        return static_prefix  # Only static prefix fits

    # Split by sections and keep highest-priority sections
    sections = degraded_dynamic.split("\n## ")
    if len(sections) > 1:
        # First section is the shot context (highest priority)
        kept = [sections[0]] if sections[0].strip() else []
        current = _estimate_tokens(sections[0]) if sections[0] else 0

        # Priority order for sections
        priority_keywords = ["事实锚点", "硬事实", "写作任务", "视角约束", "留白预算", "叙事相位"]
        other_sections = sorted(sections[1:], key=lambda s: (
            0 if any(kw in s for kw in priority_keywords) else 1
        ))

        for section in other_sections:
            section_text = "## " + section
            section_tokens = _estimate_tokens(section_text)
            if current + section_tokens > budget_for_dynamic:
                break
            kept.append(section)
            current += section_tokens

        result_dynamic = "\n## ".join(kept)
    else:
        # Fallback: simple line-by-line truncation
        dynamic_lines = degraded_dynamic.split("\n")
        truncated = []
        current_tokens = 0
        for line in dynamic_lines:
            lt = _estimate_tokens(line)
            if current_tokens + lt > budget_for_dynamic:
                truncated.append("\n[省略剩余上下文...]")
                break
            truncated.append(line)
            current_tokens += lt
        result_dynamic = "\n".join(truncated)

    return f"{static_prefix}\n\n{result_dynamic}"


def _degrade_previous_shots(dynamic_text: str, max_tokens: int) -> str:
    """Degrade previous shots section to save tokens.

    Pass 1: Replace full text with one-line summaries.
    Pass 2: Replace summaries with aggregated event bullets.
    Pass 3: Remove previous shots section entirely.
    """
    if "## 前文上下文" not in dynamic_text:
        return dynamic_text

    # Check if we even have a previous shots section to degrade
    lines = dynamic_text.split("\n")
    prev_section_start = None
    prev_section_end = None

    for i, line in enumerate(lines):
        if line.startswith("## 前文上下文"):
            prev_section_start = i
        elif prev_section_start is not None and line.startswith("## ") and i > prev_section_start:
            prev_section_end = i
            break

    if prev_section_start is None:
        return dynamic_text

    prev_section = lines[prev_section_start:prev_section_end] if prev_section_end else lines[prev_section_start:]

    # Count full-text shots
    full_text_count = sum(1 for line in prev_section if line.startswith("Shot ") and "..." not in line)

    if full_text_count > 0:
        # Pass 1: Convert full text to one-line summaries
        new_prev_section = ["## 前文上下文（摘要）", ""]
        for line in prev_section:
            if line.startswith("Shot ") and "..." not in line and "Shot" in line.split(":")[0]:
                # Full text line — convert to summary
                text = line.split(":", 1)[1].strip() if ":" in line else line
                summary = text[:80].replace("\n", " ")
                shot_idx = line.split(":")[0].replace("Shot ", "").strip()
                new_prev_section.append(f"Shot {shot_idx}: {summary}...")
            elif not line.startswith("## 前文上下文") and line.strip():
                new_prev_section.append(line)

        new_lines = lines[:prev_section_start] + new_prev_section + (lines[prev_section_end:] if prev_section_end else [])
        result = "\n".join(new_lines)

        if _estimate_tokens(result) <= max_tokens:
            return result

    # Pass 2: Convert to aggregated bullets
    new_prev_section = ["## 前文上下文（事件）", ""]
    shot_count = 0
    for line in prev_section:
        if line.startswith("Shot "):
            shot_count += 1
            parts = line.split(":", 1)
            shot_idx = parts[0].replace("Shot ", "").strip()
            text = parts[1].strip() if len(parts) > 1 else ""
            first_sentence = text.split("。")[0] if "。" in text else text[:60]
            new_prev_section.append(f"- S{shot_idx}: {first_sentence}")

    if shot_count > 5:
        # Only keep last 5
        new_prev_section = new_prev_section[:2] + new_prev_section[-5:]

    new_lines = lines[:prev_section_start] + new_prev_section + (lines[prev_section_end:] if prev_section_end else [])
    result = "\n".join(new_lines)

    if _estimate_tokens(result) <= max_tokens:
        return result

    # Pass 3: Remove previous shots entirely
    if prev_section_end:
        return "\n".join(lines[:prev_section_start] + lines[prev_section_end:])
    else:
        return "\n".join(lines[:prev_section_start])


def _estimate_tokens(text: str) -> int:
    """Rough token estimation: ~1.2 chars per token for Chinese, ~3.5 for mixed."""
    chinese_chars = sum(1 for c in text if '一' <= c <= '鿿')
    other_chars = len(text) - chinese_chars
    return int(chinese_chars / 1.2 + other_chars / 3.5)
