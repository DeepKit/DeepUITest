"""Suspense benchmark fixtures — D25-R2.

This module provides labeled samples for validating the `suspense_effectiveness`
jury dimension. Each sample is a short text segment with a human-annotated
suspense level (high / medium / low / pseudo).

The benchmark is used by tests/test_suspense_benchmark.py to verify that
the suspense_effectiveness scoring correlates with human judgment.
"""

from __future__ import annotations

# High suspense: strong information gap, time pressure, consequence asymmetry
HIGH_SUSPENSE = [
    {
        "id": "hs_001",
        "text": (
            "阿坤知道门外面有人在等他，但他不知道那是谁派来的。"
            "手机屏幕上显示着倒计时：17分钟。"
            "膝盖的伤口已经渗过了纱布，每一步都像在刀尖上走。"
            "他不知道的是——白英已经在楼下被拦住了，根本没人能来救他。"
        ),
        "label": "high",
        "rationale": "三层不对称：读者知道阿坤不知道门外是谁；读者知道白英被拦；"
                     "倒计时制造时间压力。后果严重（膝盖伤口+未知威胁）。",
    },
    {
        "id": "hs_002",
        "text": (
            "苏然盯着屏幕上的6%。每年外推6%，意味着五年后边界会再移30公里。"
            "她刚发现这个算法有个隐藏参数——不是线性增长，是指数。"
            "她看向窗外，韩教授的车还在老位置停着，但明天的这个时候，"
            "那辆车就会在边界外面了。"
        ),
        "label": "high",
        "rationale": "信息差：苏然知道指数增长，读者和韩教授还不知道。"
                     "物件（车）的意义在变化。后果不对称（韩教授即将失去居住权）。",
    },
]

# Medium suspense: some tension, but information gap is narrower
MEDIUM_SUSPENSE = [
    {
        "id": "ms_001",
        "text": (
            "白英整理抽屉时发现了一个去年没见过的通知。"
            "去年是'建议优化'，今年变成了'建议转型'。"
            "她想知道明年会是什么，但通知上只写了受理日期。"
        ),
        "label": "medium",
        "rationale": "信息差：读者和白英都不知道明年的通知内容。"
                     "有悬念但信息不对称较弱。物件（通知）有变化但不致命。",
    },
    {
        "id": "ms_002",
        "text": (
            "韩教授在三星堆的拓片上见过这个握空的手势。"
            "现在骨片上也有。"
            "他翻出三年前的笔记本，上面画着几乎一样的手势，"
            "但标注的出处是金沙遗址——不是三星堆。"
        ),
        "label": "medium",
        "rationale": "信息差：读者知道关联（三星堆+金沙），韩教授还没联系起来。"
                     "有悬疑钩子但后果不急迫。",
    },
]

# Low suspense: flat, no information gap, no consequence asymmetry
LOW_SUSPENSE = [
    {
        "id": "ls_001",
        "text": (
            "阿坤早上起来，膝盖还是疼。"
            "他吃了两片止痛药，喝了杯茶，然后出门上班。"
            "路上经过的早餐店开门了，他买了两个包子。"
        ),
        "label": "low",
        "rationale": "无信息差，无后果不对称，无未完成动作。"
                     "纯日常沉积场景，读者没有任何需要追踪的悬念。",
    },
    {
        "id": "ls_002",
        "text": (
            "白英坐在茶社里，看窗外的梧桐树叶。"
            "春天来了，叶子绿得很慢。"
            "她给杯子续了水，翻了一页书。"
        ),
        "label": "low",
        "rationale": "无悬念锚点，无信息差，无时间压力。"
                     "感官描写但没有悬疑张力。",
    },
]

# Pseudo suspense: emotional manipulation without real information gap
PSEUDO_SUSPENSE = [
    {
        "id": "ps_001",
        "text": (
            "他的心跳得好快！整个世界都安静了！"
            "难道这就是传说中的命运？"
            "那一刻，他感到前所未有的恐惧——不，是勇气！"
            "不，是恐惧！不，是爱！"
        ),
        "label": "pseudo",
        "rationale": "情绪堆砌但没有信息差，没有后果不对称。"
                     "用感叹号和反转制造表面紧张，但没有实质悬念。"
                     "读者不知道追什么，也不知道角色面临什么。",
    },
    {
        "id": "ps_002",
        "text": (
            "突然！一个黑影闪过！"
            "那是谁？难道是敌人？"
            "不，那是他自己影子。"
            "但等等——影子的形状不对！"
            "那是……那是另一个人的影子！"
        ),
        "label": "pseudo",
        "rationale": "廉价的惊吓手法（突然！黑影！），但没有信息差。"
                     "影子悬念是叙事把戏，不是真正的信息不对称。"
                     "读者不会产生真实的紧张感，因为没有真实后果。",
    },
]

# All benchmark samples
ALL_SAMPLES = HIGH_SUSPENSE + MEDIUM_SUSPENSE + LOW_SUSPENSE + PSEUDO_SUSPENSE


def get_samples_by_label(label: str) -> list[dict]:
    """Get all samples with a specific label."""
    return [s for s in ALL_SAMPLES if s["label"] == label]


def get_benchmark_summary() -> dict:
    """Return benchmark statistics."""
    from collections import Counter
    counts = Counter(s["label"] for s in ALL_SAMPLES)
    return {
        "total": len(ALL_SAMPLES),
        "by_label": dict(counts),
        "labels": sorted(counts.keys()),
    }
