"""Shared exposition / explanation audit for prose candidates.

The production pipeline uses this before literary scoring and again in L4.
The goal is not to punish every abstract word. It blocks prose that explains
theme, system logic, resource allocation, or character condition instead of
making those facts visible through action, objects, bodies, dialogue, or scene
consequences.
"""

from __future__ import annotations

import re
from collections.abc import Iterable


CLOSING_EXPLANATION_PATTERNS = [
    r"这意味着", r"这意味", r"本质上", r"说到底", r"总而言之",
    r"因此", r"所以", r"由此可见", r"综上所述",
    r"他意识到", r"她意识到", r"他明白", r"她明白",
    r"他终于", r"她终于", r"他知道了", r"她知道了",
    r"这就是", r"这才是", r"原来如此",
    r"结论", r"总结",
]

GENERAL_EXPLANATION_PATTERNS = CLOSING_EXPLANATION_PATTERNS + [
    r"也许", r"或许", r"大概", r"可能意味着",
    r"仿佛在说", r"似乎在",
    r"说明(?!书)", r"表明", r"(?<!身份)证明(?!书|材料|文件)",
]

NARRATOR_INTRUSION_PATTERNS = [
    r"她不是在.{2,20}她是在",
    r"他不是在.{2,20}他是在",
    r"这不是.{2,20}这是",
    r"问题不在于.{2,20}而在于",
    r"换句话说",
    r"也就是说",
    r"她的真正.{1,20}(原因|动机|意图|目的)",
    r"他的真正.{1,20}(原因|动机|意图|目的)",
    r"本质上是",
    r"从某种意义上说",
    r"可以说是",
    r"她其实是在",
    r"他其实是在",
    r"真正的.{1,10}不是.{2,20}而是",
]

SYSTEM_DIRECT_PATTERNS = [
    re.compile(r'["""][^""]{2,80}(推送|通知|弹窗|提示)[^""]{2,80}["""]'),
    re.compile(r"(弹窗|推送|通知|提示).{0,5}[跳显浮].{0,5}[出来示]"),
    re.compile(r"屏幕.{0,10}(跳|弹|亮).{0,20}(建议|通知|推送)"),
]

SYSTEM_INTERPRETIVE_PATTERNS = [
    re.compile(r"系统.{0,10}(因为|之所以|的原因|的原理)"),
    re.compile(r"系统的.{0,10}(意[味图]|原[因理]|逻辑|机制)"),
    re.compile(r"(目标函数|算法).{0,10}(优化|倾斜|偏向|自动)"),
    re.compile(r"系统.{0,5}(其实|本质|实际上|根本)"),
    re.compile(r"它(只是|不过|其实).{0,20}(不是|没有|精确|计算|筛)"),
]

HARD_EXPOSITION_PATTERNS = [
    r"系统并不恶意",
    r"系统.{0,14}(只是|不过|其实|本质|根本|精确地|计算)",
    r"(资源分配|评估模型|分配算法|目标函数).{0,36}(逻辑|轨道|公平|效率|回报|计算|筛)",
    r"(系统|算法|模型).{0,24}(把|将).{0,24}(人|资源|区域|群体).{0,24}(分成|筛|排除)",
    r"(区域|边界|中心|边缘|群体).{0,24}(本质|象征|意味着|代表|逻辑|资源分配|侵蚀)",
    r"这(意味|说明|表明|证明|就是|才是).{0,36}(系统|资源|人物|处境|主题|逻辑|本质)",
    r"(人物|角色|读者|主题).{0,24}(处境|象征|体现|表达|指向)",
    r"(非核心|低效率|直接回报).{0,30}(人力|资源|计算|筛)",
    r"(逻辑结构|完整的逻辑|闭环)",
    r"什么都抓不到",
]

ABSTRACT_TERMS = [
    "主题", "系统", "资源", "分配", "算法", "模型", "逻辑", "结构",
    "机制", "公平", "效率", "回报", "核心", "非核心", "秩序",
    "意义", "象征", "处境", "社会", "轨道", "区域", "边界",
    "地盘", "侵蚀", "边界", "制度", "规则", "计算", "筛",
]

EXPLANATION_CONNECTORS = [
    "意味", "说明", "表明", "证明", "本质", "核心", "逻辑",
    "因此", "所以", "只是", "其实", "看似", "不是", "而是",
    "就像", "仿佛", "似乎", "换句话说", "也就是说",
]


def audit_exposition(
    text: str,
    *,
    forbidden_phrases: Iterable[str] | None = None,
    strict: bool = False,
) -> dict:
    """Audit whether prose explains instead of dramatizes.

    `strict=False` blocks high-confidence exposition dumps only. `strict=True`
    also treats softer explanation markers as hard failures; this is useful for
    final L4 checks, but too aggressive for early candidate filtering.
    """
    if not text or len(text.strip()) < 50:
        return _empty_result()

    violations: list[dict] = []

    _scan_patterns(
        text, violations, HARD_EXPOSITION_PATTERNS,
        code="hard_exposition", severity="high",
        suggestion="改成动作、物件、身体反应、对话或环境后果。",
    )
    _scan_patterns(
        text, violations, NARRATOR_INTRUSION_PATTERNS,
        code="narrator_intrusion", severity="high",
        suggestion="让角色行为自己说明，不要由叙述者下定义。",
    )

    system_voice = check_system_voice(text)
    for item in system_voice.get("interpretive_matches", []):
        _add_violation(
            violations,
            code="system_interpretive",
            severity="high",
            pattern="SYSTEM_INTERPRETIVE",
            match=item.get("match", ""),
            position=int(item.get("position", 0)),
            context=item.get("context", ""),
            suggestion="系统只能以通知、屏幕、排队、拒绝、环境后果出现。",
        )

    _scan_sentence_density(text, violations)

    if forbidden_phrases:
        for phrase in dict.fromkeys(str(p) for p in forbidden_phrases if p):
            for match in re.finditer(re.escape(phrase), text):
                _add_violation(
                    violations,
                    code="forbidden_exposition_phrase",
                    severity="high",
                    pattern=phrase,
                    match=match.group(),
                    position=match.start(),
                    context=_context(text, match.start(), match.end()),
                    suggestion="不要原样说出禁用概念，改写成可见后果。",
                )

    if strict:
        _scan_patterns(
            text, violations, GENERAL_EXPLANATION_PATTERNS,
            code="explanation_marker", severity="medium",
            suggestion="删掉解释连接词，用可见动作承接。",
            skip_dialogue=True,
        )

    violations = _dedupe(violations)
    hard_violations = [
        item for item in violations
        if item.get("severity") == "high" or strict
    ]
    medium_count = len(violations) - sum(1 for v in violations if v.get("severity") == "high")
    score = max(0, 100 - len(hard_violations) * 35 - medium_count * 10)

    return {
        "schema": "inkflow.exposition_audit.v1",
        "passed": not hard_violations,
        "score": score,
        "violations": violations,
        "hard_violations": hard_violations,
        "total_explanations": len(violations),
        "hard_explanations": len(hard_violations),
    }


def check_explanation_sentences(text: str) -> dict:
    """L4-compatible explanation sentence result."""
    result = audit_exposition(text, strict=True)
    return {
        "violations": result["violations"],
        "total_explanations": result["total_explanations"],
        "hard_explanations": result["hard_explanations"],
    }


def check_narrator_intrusion(text: str) -> dict:
    if not text or len(text) < 50:
        return {"violations": [], "total_intrusions": 0}
    violations: list[dict] = []
    _scan_patterns(
        text, violations, NARRATOR_INTRUSION_PATTERNS,
        code="narrator_intrusion", severity="high",
        suggestion="让角色的行为自己说话，叙述者不要替读者下定义。",
    )
    return {
        "violations": _dedupe(violations),
        "total_intrusions": len(violations),
    }


def check_system_voice(text: str) -> dict:
    if not text or len(text) < 100:
        return {
            "direct": 0, "interpretive": 0, "ratio": 0.0,
            "warning": False,
            "direct_matches": [], "interpretive_matches": [],
        }

    direct_matches = []
    for pattern in SYSTEM_DIRECT_PATTERNS:
        for match in pattern.finditer(text):
            direct_matches.append({
                "match": match.group()[:80],
                "position": match.start(),
            })

    interpretive_matches = []
    for pattern in SYSTEM_INTERPRETIVE_PATTERNS:
        for match in pattern.finditer(text):
            interpretive_matches.append({
                "match": match.group()[:60],
                "context": _context(text, match.start(), match.end(), before=20, after=40),
                "position": match.start(),
            })

    direct_count = len(direct_matches)
    interpretive_count = len(interpretive_matches)
    total = direct_count + interpretive_count
    ratio = interpretive_count / max(total, 1)
    return {
        "direct": direct_count,
        "interpretive": interpretive_count,
        "ratio": round(ratio, 2),
        "warning": interpretive_count > direct_count and interpretive_count >= 2,
        "direct_matches": direct_matches,
        "interpretive_matches": interpretive_matches,
    }


def _empty_result() -> dict:
    return {
        "schema": "inkflow.exposition_audit.v1",
        "passed": True,
        "score": 100,
        "violations": [],
        "hard_violations": [],
        "total_explanations": 0,
        "hard_explanations": 0,
    }


def _scan_patterns(
    text: str,
    violations: list[dict],
    patterns: Iterable[str],
    *,
    code: str,
    severity: str,
    suggestion: str,
    skip_dialogue: bool = False,
) -> None:
    for pattern in patterns:
        for match in re.finditer(pattern, text):
            if skip_dialogue and _is_inside_dialogue(text, match.start()):
                continue
            _add_violation(
                violations,
                code=code,
                severity=severity,
                pattern=pattern,
                match=match.group(),
                position=match.start(),
                context=_context(text, match.start(), match.end()),
                suggestion=suggestion,
            )


def _is_inside_dialogue(text: str, position: int) -> bool:
    prefix = text[:position]
    return (
        prefix.rfind("“") > prefix.rfind("”")
        or prefix.rfind("「") > prefix.rfind("」")
        or prefix.rfind("『") > prefix.rfind("』")
        or prefix.count('"') % 2 == 1
    )


def _scan_sentence_density(text: str, violations: list[dict]) -> None:
    for sentence, start in _iter_sentences(text):
        compact = sentence.strip()
        if len(compact) < 45:
            continue
        abstract_count = sum(1 for term in ABSTRACT_TERMS if term in compact)
        connector_count = sum(1 for term in EXPLANATION_CONNECTORS if term in compact)
        system_terms = sum(
            1 for term in ("系统", "算法", "模型", "资源", "分配", "效率", "回报")
            if term in compact
        )
        if abstract_count >= 5 and connector_count >= 1:
            _add_violation(
                violations,
                code="abstract_exposition_sentence",
                severity="high",
                pattern="abstract_density",
                match=compact[:80],
                position=start,
                context=compact[:160],
                suggestion="把抽象判断拆成角色遇到的具体阻力和物件变化。",
            )
        elif system_terms >= 4 and abstract_count >= 4:
            _add_violation(
                violations,
                code="system_exposition_sentence",
                severity="high",
                pattern="system_density",
                match=compact[:80],
                position=start,
                context=compact[:160],
                suggestion="系统逻辑不要由旁白解释，只让屏幕、排队、拒绝和后果出现。",
            )


def _iter_sentences(text: str) -> Iterable[tuple[str, int]]:
    pattern = re.compile(r"[^。！？!?；;\n]{1,180}[。！？!?；;]?")
    for match in pattern.finditer(text):
        sentence = match.group().strip()
        if sentence:
            yield sentence, match.start()


def _add_violation(
    violations: list[dict],
    *,
    code: str,
    severity: str,
    pattern: str,
    match: str,
    position: int,
    context: str,
    suggestion: str,
) -> None:
    violations.append({
        "code": code,
        "severity": severity,
        "pattern": pattern,
        "match": match,
        "position": position,
        "context": context,
        "suggestion": suggestion,
    })


def _context(
    text: str,
    start: int,
    end: int,
    *,
    before: int = 30,
    after: int = 60,
) -> str:
    return text[max(0, start - before):min(len(text), end + after)]


def _dedupe(violations: list[dict]) -> list[dict]:
    result: list[dict] = []
    seen: set[tuple[str, int, str]] = set()
    for item in sorted(violations, key=lambda v: (v.get("position", 0), v.get("code", ""))):
        key = (
            str(item.get("code")),
            int(item.get("position", 0)),
            str(item.get("match", ""))[:40],
        )
        if key in seen:
            continue
        seen.add(key)
        result.append(item)
    return result
