"""ChapterOutline → shot contract 字段 dict 转换。

把解析出来的章大纲映射成 ink 的 shot contract 5 子表结构
（must_land/anti_write/scene_contract/persona/soft_constraints），
供 baseline 脚本直接 INSERT writing_shot_* 表。

阶段0：只映射基础字段（产出物/场景/冲突/物理因果锚点/灯态/章末钩子）。
阶段1 起：追加 chapter contract payload（追读类型/主引擎/沉默点等悬疑契约字段）。
"""
from __future__ import annotations

from typing import Any

from ink.source.outline_parser import ChapterOutline


def _split_chars(text: str) -> list[str]:
    """从"场景"行抽出登场人物（启发式：取时间/地点后的人名段）。

    场景行形如 "1979年4月，地方军工配套厂硫化车间。许怀山在装车前做最后抽检，吕素琴在质检室跑湿热试验"
    → 抽出 ["许怀山", "吕素琴"]。简单按句号分句取含"在"的人名段；解析不准时返回空，由脚本兜底。
    """
    chars: list[str] = []
    for seg in text.replace("，", "。").split("。"):
        seg = seg.strip()
        if "在" in seg and len(seg) < 40:
            # 句首到"在"之间通常是人名
            name = seg.split("在")[0].strip()
            if 2 <= len(name) <= 4 and name not in chars:
                chars.append(name)
    return chars


# 解释性收束禁词（章节级），与 beats 末位"可拍画面"约束配合，破章末解释性总结。
_EXPLANATORY_CLOSURE_WORDS = (
    "也就是说", "换句话说", "这意味着",  # 解释性收束
    "他不知道", "她不知道", "他们不知道",  # 全知式越界收束
    "可能永远", "会等很久很久",  # 抒情式越界
)
_SUSPENSE_SOFT_FORBIDDEN = ("突然", "忽然")  # 悬疑通用软禁词


def _silence_point_forbidden_facts(silence_point: str, chars: list[str]) -> list[str]:
    """从大纲"沉默点"字段推导该 POV 的硬禁事实。

    沉默点形如 "吕素琴（她知道异常但不敢上报）"——括号内是她知道但不能说的事实。
    责任流向"传递→行动"约束：沉默点角色的内幕，在该角色 POV 段不得越界说破，
    须靠物件/动作传递（油纸包/铁柜/钥匙交接）而非台词直陈。

    返回该角色 POV 段的硬禁事实短语；解析不到时返回空列表。
    """
    if not silence_point:
        return []
    # 取括号内"知道但不说"的事实描述作为该 POV 的硬禁内幕
    for opener in ("（", "("):
        if opener in silence_point:
            inner = silence_point.split(opener, 1)[1].rstrip("）)")
            inner = inner.strip("。.")
            if inner:
                return [f"{inner}（沉默点 POV 硬禁：须靠物件传递，不得台词直陈）"]
            break
    return []


# 主引擎关键词 → 5 维 intensity 增量映射。
# 大纲"主引擎"字段已有多样性（预埋种植/数字有体温/收束句/沉默/伤害预演/时间流逝…），
# 但原实现 persona 固定一刀切 → 不同主引擎的章产稿用同一配方 → 风格同质化。
# 此映射把大纲已有的主引擎差异落地到 persona intensity，破同质化。
_MAIN_ENGINE_INTENSITY_DELTAS: dict[str, dict[str, int]] = {
    "数字有体温": {"对话": 2, "悬疑": 1},  # 数字让角色念出来/对账 → 对话加重
    "预埋种植": {"悬疑": 1, "画面": 1},  # 物件特写埋钩
    "预埋回收": {"悬疑": 2, "结构": 1},  # 回收旧钩 → 结构+悬疑加重
    "收束句": {"画面": 2, "结构": 2, "对话": -1},  # 末句定格，画面/结构加重，对话让位
    "沉默": {"对话": -2, "画面": 2},  # 少言靠动作/物件
    "伤害预演": {"节奏": 2, "悬疑": 1},  # 紧迫预演
    "时间流逝": {"节奏": -2, "结构": 2},  # 慢跨年，结构加重节奏放慢
    "上级质问": {"对话": 2, "节奏": 1},  # 质询场面对话驱动
    "错位共鸣": {"悬疑": 2, "结构": 1},  # 跨章回声
}

# persona 基线（与原固定值一致），主引擎增量在其上叠加，最后 clamp 到 [0, 10]。
_PERSONA_BASELINE = {"画面": 7, "节奏": 6, "对话": 4, "结构": 6, "悬疑": 8}


def _persona_intensity_from_engine(main_engine: str) -> dict[str, int]:
    """从大纲"主引擎"推导差异化 5 维 intensity。

    主引擎可为复合（如"预埋种植+数字有体温"），按 + 分隔逐项叠加增量；
    基线 _PERSONA_BASELINE + 增量，clamp 到 [0, 10]。解析不到时返回基线。
    """
    intensity = dict(_PERSONA_BASELINE)
    if not main_engine:
        return intensity
    for part in main_engine.replace("，", "+").split("+"):
        part = part.strip()
        deltas = _MAIN_ENGINE_INTENSITY_DELTAS.get(part)
        if not deltas:
            continue
        for dim, delta in deltas.items():
            intensity[dim] = max(0, min(10, intensity[dim] + delta))
    return intensity


def to_shot_contract_dict(co: ChapterOutline) -> dict[str, dict[str, Any]]:
    """ChapterOutline → shot contract 5 子表 dict。

    返回结构对齐 insert_chinese_contract_children 的字段：
    {
      "must_land": {"events": [...], "beats": [...], "information_releases": [...]},
      "anti_write": {"forbidden_facts": [...], "forbidden_words": [...], "pov_only": [...]},
      "scene_contract": {"location": str, "time_of_day": str, "characters_present": [...], "character_positions": {...}},
      "persona": {"persona": str, "intensity": {...}, "is_creative_shot": "0", "is_suspense_shot": "1"},
      "soft_constraints": {"relaxable_rules": [...], "deviation_budget": 0.2},
    }
    """
    scene = co.get("场景")
    chars = _split_chars(scene)
    if not chars:
        chars = ["许怀山"]  # 兜底：至少一个 POV

    # 工业化章节契约不能只压缩成“产出物/冲突/章末钩子”三项。
    # 压力、期限、并行动作和不可逆选择必须进入 shot contract，否则大纲生成器
    # 容易把整章退化为单一章末画面，并仍被内部 jury 误判为高分。
    events = [
        co.get("产出物"),
        co.get("不可逆选择"),
        co.get("责任轨迹"),
    ]
    # beats 末位须是"可拍画面"式收束（章末钩子），而非解释性总结。
    # 把章末钩子既作末 beat 又作 information_release：beat 序列尾 = 具象钩子画面，
    # 破"章末全封存/解释性收束"（卷一卷二 7/10 章末钩子为"油纸包/铁柜/暂存"同构病根）。
    conflict = co.get("冲突")
    hook = co.get("章末钩子")
    beats = [
        co.get("场景"),
        co.get("压力来源"),
        co.get("明确期限"),
        co.get("并行动作"),
        conflict,
        co.get("工业因果桥"),
        co.get("目标感受"),
        co.get("叙事速度"),
        hook,
    ]
    information_releases = [
        value for value in [co.get("信息延迟"), hook] if value
    ]
    contract_forbidden = [
        value for value in [co.get("未来义务"), co.get("去重硬门")] if value
    ]

    return {
        "must_land": {
            "events": [e for e in events if e],
            "beats": [b for b in beats if b],
            "information_releases": [r for r in information_releases if r],
        },
        "anti_write": {
            # 沉默点角色 = 知道但不能说的事实 → 该 POV 的硬禁事实（责任流向"传递→行动"约束）。
            "forbidden_facts": (
                _silence_point_forbidden_facts(co.get("沉默点"), chars)
                + contract_forbidden
            ),
            # 解释性收束禁词：第10章末句"他不知道…会等很久很久"病根——把画面总结成陈述。
            # 通用软禁词 + 收束性解释模式词。
            "forbidden_words": list(_SUSPENSE_SOFT_FORBIDDEN) + list(_EXPLANATORY_CLOSURE_WORDS),
            "pov_only": chars[:1],  # POV 锁到首个人物
        },
        "scene_contract": {
            "location": _extract_location(scene),
            "time_of_day": "白天" if "白天" in scene or "装车" in scene else "夜晚",
            "characters_present": chars,
            "character_positions": {c: "在场" for c in chars},
        },
        "persona": {
            "persona": "悬疑官",
            # 从"主引擎"推导差异化 intensity，破不同章节同配方导致的风格同质化。
            "intensity": _persona_intensity_from_engine(co.get("主引擎")),
            "is_creative_shot": "0",
            "is_suspense_shot": "1",
        },
        "soft_constraints": {
            "relaxable_rules": ["metaphor"],
            "deviation_budget": 0.2,
        },
    }


def _extract_location(scene: str) -> str:
    """从场景行抽地点。如 "...地方军工配套厂硫化车间..." → "地方军工配套厂硫化车间"。"""
    # 取第一个"在"或"某"附近的地点段
    for marker in ["厂", "室", "站", "库", "间", "车间", "会议室"]:
        idx = scene.find(marker)
        if idx >= 0:
            # 往前找 2-8 字
            start = max(0, idx - 6)
            return scene[start: idx + len(marker)]
    return "工厂"


def to_chapter_contract_payload(co: ChapterOutline) -> dict[str, Any]:
    """ChapterOutline → chapter contract payload（阶段1 起）。

    把悬疑契约字段打包成 chapter contract 的 JSON payload。
    阶段1 在 fields.py 加白名单字段后，此 payload 可经 patch_engine 落库。
    阶段0 不调用此函数。
    """
    return {
        "pursuit_type": co.get("追读类型"),
        "main_engine": co.get("主引擎"),
        "emotion_target": co.get("情感刻度目标"),
        "silence_point": co.get("沉默点"),
        "causal_anchor": co.get("物理因果锚点"),
        "pressure_source": co.get("压力来源"),
        "deadline": co.get("明确期限"),
        "parallel_actions": co.get("并行动作"),
        "irreversible_choice": co.get("不可逆选择"),
        "responsibility_trace": co.get("责任轨迹"),
        "information_delay": co.get("信息延迟"),
        "target_reader_feeling": co.get("目标感受"),
        "narrative_speed": co.get("叙事速度"),
        "future_obligation_status": co.get("未来义务"),
        "hook_type": "",  # 阶段3 由 jury 审计推断
        "light_state": co.get("灯态"),
        "chapter_end_hook": co.get("章末钩子"),
        "chapter_id": {"id": co.chapter_num, "title": f"第{co.chapter_num}章"},
        "raw_outline": co.raw_text,
    }


def outline_to_four_layer_clauses(co: ChapterOutline) -> dict[str, list[dict[str, Any]]]:
    """ChapterOutline → 四层 clause dict（给 ``assemble_four_layer_contract`` 用）。

    这是 H1 契约唯一真相源接线的入口：把章纲字段映射到 Scene Contract 四层
    （docs/design.md §3.1），而非从大纲裸拼 brief。brief 由 ``brief_compiler``
    从落库后的 clause 编译，此处只负责把章纲转成 clause dict 落库。

    四层映射：
    - hard_constraint：物理因果锚点 / 沉默点硬禁 / 未来义务 / 去重硬门（失败��）
    - source_dna：主引擎 + 叙事速度派生的原稿创作机制（评估传递质量）
    - soft_goal：冲突 / 目标感受 / 场景功能（允许优秀偏离）
    - creative_opening：章末钩子 + 场景留白（至少 2 条，design.md §5.1.4）

    缺字段则该层对应 clause 不插入，但 creative_opening 不足 2 条会触发
    ``assemble_four_layer_contract`` 的 DB 级拒绝。
    """
    scene = co.get("场景")
    chars = _split_chars(scene) or ["许怀山"]
    forbidden_facts = (
        _silence_point_forbidden_facts(co.get("沉默点"), chars)
        + [v for v in [co.get("未来义务"), co.get("去重硬门")] if v]
    )

    hard_constraints = [
        {"clause_key": "physical_cause_anchor",
         "clause_text": co.get("物理因果锚点"), "severity": "hard",
         "authority_rank": 10},
        *[{"clause_key": f"forbidden_fact_{i}", "clause_text": f,
           "severity": "hard", "authority_rank": 9 - i}
          for i, f in enumerate(forbidden_facts)],
    ]
    hard_constraints = [c for c in hard_constraints if c["clause_text"]]

    # 兜底：章纲缺物理因果锚点/沉默点/未来义务/去重硬门时 hard 层会空，
    # 真实模型契约审查一致判 revise（ch2/3/4 实测根因）。
    # design.md §3.1 要求 hard 层非空——从冲突派生因果硬约束补位。
    # 注意：不用章末钩子派生 hard（章末钩子属于 creative_opening 层留白，
    # 同时进 hard 层会被审查判"锁死 creative_opening"，ch02 independent-2 实测）。
    if not hard_constraints:
        conflict = co.get("冲突")
        if conflict:
            hard_constraints.append(
                {"clause_key": "causal_conflict_anchor",
                 "clause_text": f"本章核心因果冲突须落地（兜底派生）：{conflict}",
                 "severity": "hard", "authority_rank": 8})
        if not hard_constraints and scene:
            hard_constraints.append(
                {"clause_key": "scene_binding",
                 "clause_text": f"场景物理约束须落地（兜底派生）：{scene}",
                 "severity": "hard", "authority_rank": 6})

    source_dna = [
        {"clause_key": "main_engine", "clause_text": co.get("主引擎"),
         "severity": "diagnostic", "authority_rank": 5},
        {"clause_key": "narrative_pace", "clause_text": co.get("叙事速度"),
         "severity": "diagnostic", "authority_rank": 4},
    ]
    source_dna = [c for c in source_dna if c["clause_text"]]

    soft_goals = [
        {"clause_key": "conflict", "clause_text": co.get("冲突"),
         "severity": "soft", "authority_rank": 6},
        {"clause_key": "emotion_target", "clause_text": co.get("目标感受"),
         "severity": "soft", "authority_rank": 5},
        {"clause_key": "scene_function", "clause_text": scene,
         "severity": "soft", "authority_rank": 4},
    ]
    soft_goals = [c for c in soft_goals if c["clause_text"]]

    # creative_opening：章末钩子 + 场景留白 + 目标感受留白，至少 2 条（design.md §5.1.4）。
    hook = co.get("章末钩子")
    creative_openings = [
        {"clause_key": "chapter_end_hook", "clause_text": hook,
         "severity": "soft", "authority_rank": 3} if hook else None,
        {"clause_key": "scene_opening", "clause_text": f"场景可发挥处：{scene}",
         "severity": "soft", "authority_rank": 2} if scene else None,
        {"clause_key": "emotion_opening",
         "clause_text": f"情绪落点可发挥：{co.get('目标感受')}",
         "severity": "soft", "authority_rank": 1} if co.get("目标感受") else None,
    ]
    creative_openings = [c for c in creative_openings if c is not None]

    # 兜底：审查口径要求 creative_opening 有 ≥2 条"可发挥留白"，且不得与 hard ���内容重复
    # （qwen3 实测：chapter_end_hook 不算开场留白；conflict_opening 与 hard 派生冲突撞文本判锁死；
    #  场景派生又会与 scene_opening 撞）。故 hard 兜底用「冲突」时，creative 兜底改用登场人物留白，
    #  源文本彻底错开。chars 来自 _split_chars(scene)，与 hard 的「冲突」、scene_opening 的「场景」均不重。
    non_hook_openings = [c for c in creative_openings if c["clause_key"] != "chapter_end_hook"]
    if len(non_hook_openings) < 2 and chars:
        creative_openings.append(
            {"clause_key": "character_reaction_opening",
             "clause_text": f"登场人物（{'、'.join(chars)}）的反应与心理动机可发挥，不锁死具体表现",
             "severity": "soft", "authority_rank": 0})

    return {
        "hard_constraints": hard_constraints,
        "source_dna": source_dna,
        "soft_goals": soft_goals,
        "creative_openings": creative_openings,
    }
