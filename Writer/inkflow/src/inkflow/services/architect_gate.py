"""Architect Gate — 4-level cascading quality gate.

级联规则：下级全部封版，才触发上级 Gate。

  Shot 1 → L4 → 封版
  Shot 2 → L4 → 封版
  ...
  Shot N → L4 → 封版
             ↓ (最后一个 Shot 封版后)
           L3 唤醒 → 检查整章 → 封版
             ↓ (最后一章封版后)
           L2 唤醒 → 检查全卷角色弧线 → 封版
             ↓ (最后一卷封版后)
           L1 唤醒 → 检查全书世界观 → 封版

P0: L4 + L3（单章运行）。L2/L1 is P1（多卷运行）。

L4 now includes:
- Dual-helix check (碎裂/重建): what did the character lose? what did they grab?
- Closing-sentence audit: is the last sentence an explanation or a concrete detail?
- Must-land event coverage
- D-25: Number temperature check (数字体温)
- D-25: Explanation sentence detection (解释句检测)
- D-25: Harm preview detection (伤害预演检测)
"""

from __future__ import annotations

import json
import re
import sqlite3

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.models.enums import ShotStatus
from inkflow.services.text_repository import TextRepository
from inkflow.utils.character_names import (
    deprecated_aliases_for_layers,
    find_deprecated_aliases,
)
from inkflow.services.audit_recorder import AuditRecorder


# ── Closing-sentence audit patterns ──

# Explanation markers that should NEVER appear in a closing sentence
_CLOSING_EXPLANATION_PATTERNS = [
    r'这意味着', r'这意味', r'本质上', r'说到底', r'总而言之',
    r'因此', r'所以', r'由此可见', r'综上所述',
    r'他意识到', r'她意识到', r'他明白', r'她明白',
    r'他终于', r'她终于', r'他知道了', r'她知道了',
    r'这就是', r'这才是', r'原来如此',
    r'结论', r'总结',
]

# General explanation patterns (not just in closing)
_EXPLANATION_PATTERNS = _CLOSING_EXPLANATION_PATTERNS + [
    r'也许', r'或许', r'大概', r'可能意味着',
    r'像是', r'仿佛在说', r'似乎在',
    r'说明', r'表明', r'证明',
]

# Narrator intrusion patterns — deeper over-explanation (OPT-3)
# These catch the narrator telling readers how to interpret character behavior
_NARRATOR_INTRUSION_PATTERNS = [
    r'她不是在.{2,20}她是在',
    r'他不是在.{2,20}他是在',
    r'这不是.{2,20}这是',
    r'问题不在于.{2,20}而在于',
    r'换句话说',
    r'也就是说',
    r'她的真正.{1,20}(原因|动机|意图|目的)',
    r'他的真正.{1,20}(原因|动机|意图|目的)',
    r'本质上是',
    r'从某种意义上说',
    r'可以说是',
    r'她其实是在',
    r'他其实是在',
    r'真正的.{1,10}不是.{2,20}而是',
]

# ── System voice patterns (OPT-7) ──

# Direct system presentation: notifications, popups, push messages (OK)
_SYSTEM_DIRECT_PATTERNS = [
    re.compile(r'["""][^""]{2,80}(推送|通知|弹窗|提示)[^""]{2,80}["""]'),
    re.compile(r'(弹窗|推送|通知|提示).{0,5}[跳显浮].{0,5}[出来示]'),
    re.compile(r'屏幕.{0,10}(跳|弹|亮).{0,20}(建议|通知|推送)'),
]

# Interpretive system presentation: character analyzing/explaining the system (BAD)
_SYSTEM_INTERPRETIVE_PATTERNS = [
    re.compile(r'系统.{0,10}(因为|之所以|的原因|的原理)'),
    re.compile(r'系统的.{0,10}(意[味图]|原[因理]|逻辑|机制)'),
    re.compile(r'(目标函数|算法).{0,10}(优化|倾斜|偏向|自动)'),
    re.compile(r'系统.{0,5}(其实|本质|实际上|根本)'),
    re.compile(r'它(只是|不过|其实).{0,20}(不是|没有)'),
]

# Concrete closing markers (good ending types)
_CLOSING_CONCRETE_PATTERNS = [
    r'。$', r'！$', r'？$', r'」$', r'"$', r'”$',
]

# Object/action/silence/sensory words that suggest a good closing
_CLOSING_SENSORY_KEYWORDS = [
    '雨', '雾', '手', '膝盖', '杯', '茶', '门', '窗', '光',
    '声音', '风', '水', '纸', '骨', '椅子', '镜子', '屏幕',
    '站', '走', '骑', '看', '放', '推', '拉', '关', '开',
    '停', '响', '亮', '暗', '热', '冷', '湿', '干', '重', '轻',
    '没有', '不再', '还在', '继续',
]

# ── Number temperature patterns (D-25) ──

# Match Chinese/Arabic numbers
_NUMBER_PATTERN = re.compile(
    r'(\d+(?:\.\d+)?%?|[零一二三四五六七八九十百千万亿两]+(?:\.\d+)?%?)'
)

# Abstract terms that should NOT follow a number
_ABSTRACT_TERMS = [
    '效率', '资源', '系统', '优化', '指标', '参数', '配置',
    '算法', '策略', '模型', '方案', '标准', '机制',
]

# Concrete terms that ARE acceptable after a number
_CONCRETE_TERMS = [
    '人', '个', '名', '位', '岁', '元', '块', '公里', '米',
    '单', '分', '份', '年', '月', '日', '天', '小时', '分钟',
    '茶', '路', '街', '楼', '层', '号', '室', '条',
    '腿', '手', '膝', '眼', '件', '张', '把', '辆', '台',
]

# Harm/preview sensory keywords (D-25)
_HARM_PREVIEW_KEYWORDS = [
    '疼', '痛', '麻', '拧', '撕', '裂', '碎', '破', '烂', '伤', '血',
    '冷', '冰', '硬', '湿', '黏', '腥', '臭', '腐',
    '喘', '咳', '抖', '颤', '僵', '肿', '红', '青', '紫',
    '针', '刀', '锤', '锯', '烧', '烫', '冻', '割',
]


class ArchitectGate:
    """4-level cascading architect gate.

    Each level gates the output of the level below.
    L4 gates individual shots. L3 gates chapter structure.
    L2 gates volume character arcs. L1 gates universe world rules.
    """

    def __init__(
        self,
        db: sqlite3.Connection,
        run_id: str,
        project_id: str,
        models_config: dict | None = None,
        providers: dict | None = None,
    ):
        self.db = db
        self.run_id = run_id
        self.project_id = project_id
        self.models_config = models_config or {}
        self.providers = providers or {}

    # ── L4: Shot-level gate ──

    def evaluate_l4(self, shot_id: str, draft_id: str, gate2_result: dict) -> dict:
        """L4 gate: Shot-level quality check.

        Checks:
        - Gate2 pass-through (jury score + light status)
        - Must-land event coverage
        - Dual-helix: what did the character lose? what did they grab?
        - Closing-sentence audit: is the ending concrete or explanatory?
        - D-25: Number temperature check
        - D-25: Explanation sentence detection
        - D-25: Harm preview detection

        Returns:
            {passed, score, light_status, issues, dual_helix, closing_audit,
             number_temperature, explanation_check, harm_preview, suspense_summary}
        """
        passed = gate2_result.get("passed", False)
        score = gate2_result.get("score", 0)
        light_status = gate2_result.get("light_status", "red")

        issues = []
        hard_issues = []

        # Check shot-level contract compliance
        contract = self.db.execute(
            "SELECT must_land_json, anti_write_json, contract_json FROM writing_shot_contracts "
            "WHERE shot_id = ? AND run_id = ?",
            (shot_id, self.run_id),
        ).fetchone()

        contract_text = ""
        if contract:
            must_land = json.loads(contract["must_land_json"] or "{}")
            contract_text = json.dumps(dict(contract), ensure_ascii=False)
            if must_land and not passed:
                issues.append("must_land events may not be fully covered")

        # Get the draft text for analysis
        draft = self.db.execute(
            "SELECT text FROM writing_drafts WHERE draft_id = ?", (draft_id,)
        ).fetchone()
        text = draft["text"] if draft else ""

        # Dual-helix check
        dual_helix = self._check_dual_helix(text)

        # Closing-sentence audit
        closing_audit = self._check_closing_sentence(text)

        if closing_audit.get("violation"):
            issue = f"closing: {closing_audit['violation']}"
            issues.append(issue)
            hard_issues.append(issue)

        # D-25: Number temperature check
        number_temp = self._check_number_temperature(text)
        if number_temp.get("violations"):
            issues.append(
                f"number_temperature: {len(number_temp['violations'])} violation(s)"
            )

        # D-25: Explanation sentence detection
        explanation_check = self._check_explanation_sentences(text)
        if explanation_check.get("violations"):
            issue = (
                f"explanation: {len(explanation_check['violations'])} violation(s)"
            )
            issues.append(issue)
            hard_issues.append(issue)

        # D-25: Harm preview detection
        harm_preview = self._check_harm_preview(text)
        if harm_preview.get("missing_preview"):
            issue = "harm_preview: sensory preview missing before impact info"
            issues.append(issue)
            hard_issues.append(issue)

        # OPT-1: Paragraph length check (phase-aware)
        # Look up narrative_phase to adjust max_chars threshold
        narrative_phase = None
        # Try contract_json first
        contract_json_row = self.db.execute(
            "SELECT contract_json FROM writing_shot_contracts "
            "WHERE shot_id = ? AND run_id = ?",
            (shot_id, self.run_id),
        ).fetchone()
        if contract_json_row:
            try:
                cj = json.loads(contract_json_row["contract_json"] or "{}")
                narrative_phase = cj.get("narrative_phase")
            except (json.JSONDecodeError, TypeError):
                pass
        # Try chapter_rhythms as fallback
        if not narrative_phase:
            rhythm_row = self.db.execute(
                "SELECT rhythm_map_json FROM writing_chapter_rhythms "
                "WHERE chapter_key = ? AND run_id = ?",
                (shot_id.rsplit(".s", 1)[0] if ".s" in shot_id else shot_id, self.run_id),
            ).fetchone()
            if rhythm_row:
                try:
                    rm = json.loads(rhythm_row["rhythm_map_json"] or "{}")
                    shot_idx = int(shot_id.rsplit(".s", 1)[1]) if ".s" in shot_id else 1
                    for s in rm.get("shots", []):
                        if s.get("shot_index") == shot_idx:
                            narrative_phase = s.get("narrative_phase")
                            break
                except (json.JSONDecodeError, TypeError, ValueError):
                    pass

        # Phase-specific paragraph length thresholds
        phase_max_chars = {
            "pulse": 500,      # High-energy → shorter paragraphs OK
            "chaos": 600,
            "sublime": 700,
            "ripple": 800,
            "fold": 800,
            "sediment": 1000,  # Slow scenes can have longer paragraphs
        }
        max_chars = phase_max_chars.get(narrative_phase, 800)

        para_length = self._check_paragraph_length(text, max_chars=max_chars)
        if para_length.get("violations"):
            issue = (
                f"paragraph_length: {len(para_length['violations'])} paragraph(s) "
                f"exceed {max_chars} chars"
                f" (phase={narrative_phase or 'default'})"
            )
            issues.append(issue)
            if (
                len(para_length.get("violations", [])) > 2
                or para_length.get("max_length", 0) > max_chars * 1.5
            ):
                hard_issues.append(issue)

        # OPT-3: Narrator intrusion detection
        narrator_intrusion = self._check_narrator_intrusion(text)
        if narrator_intrusion.get("violations"):
            issue = (
                f"narrator_intrusion: {len(narrator_intrusion['violations'])} narrator over-reach(es)"
            )
            issues.append(issue)
            hard_issues.append(issue)

        # OPT-7: System voice separation
        system_voice = self._check_system_voice(text)
        if system_voice.get("warning"):
            issue = (
                f"system_voice: interpretive({system_voice['interpretive']}) > "
                f"direct({system_voice['direct']}) — system is being explained, not shown"
            )
            issues.append(issue)
            hard_issues.append(issue)

        # Canonical character names: reject stale aliases after a rename.
        name_consistency = self._check_canonical_name_usage(text)
        if name_consistency.get("violations"):
            issue = (
                f"character_name: {len(name_consistency['violations'])} "
                "deprecated alias(es)"
            )
            issues.append(issue)
            hard_issues.append(issue)

        # Prevent concrete medical/institutional facts invented beyond contract.
        fact_expansion = self._check_unanchored_fact_expansion(text, contract_text)
        if fact_expansion.get("violations"):
            issue = (
                f"unanchored_fact: {len(fact_expansion['violations'])} "
                "unsupported concrete fact(s)"
            )
            issues.append(issue)
            hard_issues.append(issue)

        # D-25: Suspense summary
        suspense_summary = self._build_suspense_summary(
            closing_audit, number_temp, explanation_check, harm_preview,
            paragraph_length=para_length,
            narrator_intrusion=narrator_intrusion,
            system_voice=system_voice,
        )

        result = {
            "passed": bool(passed and not hard_issues),
            "score": score,
            "light_status": light_status,
            "issues": issues,
            "hard_issues": hard_issues,
            "dual_helix": dual_helix,
            "closing_audit": closing_audit,
            "number_temperature": number_temp,       # D-25
            "explanation_check": explanation_check,   # D-25
            "harm_preview": harm_preview,             # D-25
            "suspense_summary": suspense_summary,     # D-25
            "paragraph_length": para_length,          # OPT-1
            "narrator_intrusion": narrator_intrusion,  # OPT-3
            "system_voice": system_voice,             # OPT-7
            "name_consistency": name_consistency,
            "fact_expansion": fact_expansion,
        }

        self._record_gate("L4", shot_id, result)
        return result

    # ── Dual-helix check ──

    def _check_dual_helix(self, text: str) -> dict:
        """Check for dual-helix: cracking (碎裂) and rebuilding (重建).

        Heuristic: scans text for loss markers and grab markers.
        Returns a qualitative assessment, not a pass/fail.
        """
        if not text or len(text) < 100:
            return {"碎裂": "unknown", "重建": "unknown", "note": "text too short"}

        # Loss markers (碎裂): what the character lost
        loss_patterns = [
            (r'(失去|没了|丢了|不再|回不去|关[了门]|停了|断了|走了|离开|消失)', 'loss'),
            (r'(疼|痛|麻|拧|撕|裂|碎|破|烂|伤|血)', 'physical_pain'),
            (r'(被分[流送]|被划|被标记|被建议|被告知|被通知)', 'systemic_loss'),
        ]
        loss_found = []
        for pattern, label in loss_patterns:
            if re.search(pattern, text):
                loss_found.append(label)

        # Grab markers (重建): what the character grabbed onto
        grab_patterns = [
            (r'(指了|指了[一指]|指了指|握|抓住|抱住|拿起|接过|端起|压[在着])', 'physical_grab'),
            (r'(说了|问道|回答|骂了|叹|喊|叫)', 'verbal_grab'),
            (r'(看着|盯着|望[向着]|回头看|看了一眼)', 'visual_grab'),
            (r'(骑[走上进]|继续|再[来次]|重新|还[会在]|肯定)', 'forward_grab'),
        ]
        grab_found = []
        for pattern, label in grab_patterns:
            if re.search(pattern, text):
                grab_found.append(label)

        return {
            "碎裂": loss_found or ["no_loss_detected"],
            "重建": grab_found or ["no_grab_detected"],
            "note": "heuristic — P1 upgrade to AI audit",
        }

    # ── Closing-sentence audit ──

    def _check_closing_sentence(self, text: str) -> dict:
        """Audit the closing sentence of a shot.

        Checks:
        - Is the last sentence an explanation/summary? → violation
        - Is it a concrete object/action/silence? → good
        - Does it end with a sensory detail? → bonus
        - D-25: Is it an unfinished action? → hook quality

        Returns:
            {violation: str or None, type: str, last_sentence: str,
             hook_quality: str, is_unfinished: bool}
        """
        if not text or len(text) < 50:
            return {
                "violation": "text too short for closing audit",
                "type": "unknown",
                "last_sentence": "",
                "hook_quality": "unknown",
                "is_unfinished": False,
            }

        # Extract last sentence: split on Chinese/English sentence terminators
        sentences = re.split(r'[。！？!?\n](?:\s*)', text.strip())
        meaningful = [s.strip() for s in sentences if s.strip() and len(s.strip()) > 3]
        if not meaningful:
            return {
                "violation": "no meaningful closing sentence found",
                "type": "unknown",
                "last_sentence": "",
                "hook_quality": "unknown",
                "is_unfinished": False,
            }

        last = meaningful[-1]

        # Check for explanation markers
        for pattern in _CLOSING_EXPLANATION_PATTERNS:
            if re.search(pattern, last):
                return {
                    "violation": f"explanation marker: '{re.search(pattern, last).group()}'",
                    "type": "explanation",
                    "last_sentence": last[:120],
                    "suggestion": "replace with object, action, silence, or wrong conclusion",
                    "hook_quality": "poor",
                    "is_unfinished": False,
                }

        # Determine closing type
        closing_type = "action"
        if any(kw in last for kw in _CLOSING_SENSORY_KEYWORDS):
            closing_type = "sensory_detail"
        if any(kw in last for kw in ['没有', '不再', '还在', '继续']):
            closing_type = "silence_or_state_change"
        if any(kw in last for kw in ['看了', '看了一眼', '回头看', '盯着', '望着']):
            closing_type = "visual_grab"

        # D-25: Determine hook quality
        # Unfinished action markers: mid-action, physical interruption, decision suspended
        unfinished_markers = [
            '正要', '刚', '还没', '还没', '突然', '忽然',
            '门', '铃', '响', '电话', '手机', '屏幕',
            '抬头', '回头', '转身', '站起', '蹲下',
            '伸手', '握', '抓', '推', '拉', '放', '拿',
        ]
        is_unfinished = any(kw in last for kw in unfinished_markers)

        # Hook quality assessment
        if closing_type == "explanation":
            hook_quality = "poor"
        elif is_unfinished and closing_type in ("action", "sensory_detail", "silence_or_state_change"):
            hook_quality = "excellent"
        elif closing_type in ("sensory_detail", "silence_or_state_change"):
            hook_quality = "good"
        elif closing_type == "action":
            hook_quality = "acceptable"
        else:
            hook_quality = "fair"

        return {
            "violation": None,
            "type": closing_type,
            "last_sentence": last[:120],
            "hook_quality": hook_quality,
            "is_unfinished": is_unfinished,
        }

    # ── D-25: Number temperature check ──

    def _check_number_temperature(self, text: str) -> dict:
        """Check if numbers in the text are followed by concrete people/objects.

        Rule: 任何数字出现后，同一句或下一句必须紧跟一个具体的人或物。
        禁止数字后紧跟抽象概念。

        Returns:
            {violations: list, total_numbers: int, cold_numbers: int}
        """
        if not text or len(text) < 50:
            return {"violations": [], "total_numbers": 0, "cold_numbers": 0}

        # Find all numbers
        numbers = _NUMBER_PATTERN.findall(text)
        if not numbers:
            return {"violations": [], "total_numbers": 0, "cold_numbers": 0}

        violations = []
        total_numbers = len(numbers)
        cold_numbers = 0

        for num in numbers:
            # Find the position of this number
            pos = text.find(num)
            if pos == -1:
                continue

            # Check the next 50 characters after the number
            after = text[pos + len(num):pos + len(num) + 50]

            # Check if followed by abstract terms
            has_abstract = any(term in after for term in _ABSTRACT_TERMS)
            has_concrete = any(term in after for term in _CONCRETE_TERMS)

            if has_abstract and not has_concrete:
                cold_numbers += 1
                violations.append({
                    "number": num,
                    "position": pos,
                    "context": text[max(0, pos-10):pos+60],
                    "issue": "number followed by abstract term without concrete anchor",
                })
            elif has_abstract:
                # Has both abstract and concrete — warning
                cold_numbers += 1
                violations.append({
                    "number": num,
                    "position": pos,
                    "context": text[max(0, pos-10):pos+60],
                    "issue": "number has abstract term but also concrete anchor — warning",
                })

        return {
            "violations": violations,
            "total_numbers": total_numbers,
            "cold_numbers": cold_numbers,
        }

    # ── D-25: Explanation sentence detection ──

    def _check_explanation_sentences(self, text: str) -> dict:
        """Detect explanation sentences throughout the text.

        Returns:
            {violations: list, total_explanations: int}
        """
        if not text or len(text) < 50:
            return {"violations": [], "total_explanations": 0}

        violations = []
        for pattern in _EXPLANATION_PATTERNS:
            for match in re.finditer(pattern, text):
                # Get context around the match
                start = max(0, match.start() - 20)
                end = min(len(text), match.end() + 40)
                violations.append({
                    "pattern": pattern,
                    "match": match.group(),
                    "position": match.start(),
                    "context": text[start:end],
                })

        return {
            "violations": violations,
            "total_explanations": len(violations),
        }

    # ── D-25: Harm preview detection ──

    def _check_harm_preview(self, text: str) -> dict:
        """Check if harm/impact information is preceded by sensory preview.

        Rule: 在任何冲击力信息到达读者之前，先用感官细节建立情绪铺垫。

        Returns:
            {missing_preview: bool, preview_count: int, impact_count: int}
        """
        if not text or len(text) < 100:
            return {"missing_preview": False, "preview_count": 0, "impact_count": 0}

        # Count sensory preview keywords
        preview_count = sum(
            1 for kw in _HARM_PREVIEW_KEYWORDS if kw in text
        )

        # Count impact information (numbers, systemic terms)
        impact_terms = ['被分', '被划', '被标记', '被建议', '被告知', '被通知',
                       '失去', '没了', '丢了', '不再', '回不去']
        impact_count = sum(
            1 for term in impact_terms if term in text
        )

        # Simple heuristic: if there are impact terms but no sensory preview,
        # flag as missing preview
        missing_preview = impact_count > 0 and preview_count == 0

        return {
            "missing_preview": missing_preview,
            "preview_count": preview_count,
            "impact_count": impact_count,
            "note": "heuristic — P1 upgrade to AI audit" if missing_preview else "",
        }

    # ── OPT-1: Paragraph length check ──

    def _check_paragraph_length(self, text: str, max_chars: int = 800) -> dict:
        """Check if paragraphs exceed the contract-specified character limit.

        Rule: style_locks.paragraph_length = '500-800 字/段落'.
        Paragraphs exceeding 800 chars are violations.

        Returns:
            {violations: list, total_paragraphs: int, avg_length: float, max_length: int}
        """
        if not text or len(text) < 50:
            return {
                "violations": [],
                "total_paragraphs": 0,
                "avg_length": 0,
                "max_length": 0,
            }

        # Split into paragraphs by double newline or single newline
        paragraphs = [p.strip() for p in text.split('\n') if p.strip()]
        violations = []
        lengths = []

        for i, para in enumerate(paragraphs):
            char_count = len(para)
            lengths.append(char_count)
            if char_count > max_chars:
                violations.append({
                    "paragraph_index": i,
                    "char_count": char_count,
                    "limit": max_chars,
                    "overshoot": char_count - max_chars,
                    "preview": para[:80] + ("..." if len(para) > 80 else ""),
                })

        return {
            "violations": violations,
            "total_paragraphs": len(paragraphs),
            "avg_length": round(sum(lengths) / max(len(lengths), 1), 1),
            "max_length": max(lengths) if lengths else 0,
        }

    # ── OPT-3: Narrator intrusion detection ──

    def _check_narrator_intrusion(self, text: str) -> dict:
        """Detect narrator over-reach: narrator telling readers how to interpret.

        These are deeper than simple explanation markers. They catch patterns like:
        - "她不是在发现，她是在承认" (narrator re-defining character behavior)
        - "问题不在于勇气，而在于觉得自己不配" (narrator diagnosing character)

        Returns:
            {violations: list, total_intrusions: int}
        """
        if not text or len(text) < 50:
            return {"violations": [], "total_intrusions": 0}

        violations = []
        for pattern in _NARRATOR_INTRUSION_PATTERNS:
            for match in re.finditer(pattern, text):
                start = max(0, match.start() - 30)
                end = min(len(text), match.end() + 50)
                violations.append({
                    "pattern": pattern,
                    "match": match.group(),
                    "severity": "high",
                    "position": match.start(),
                    "context": text[start:end],
                    "suggestion": "让角色的行为自己说话，叙述者不要替读者下定义",
                })

        return {
            "violations": violations,
            "total_intrusions": len(violations),
        }

    # ── OPT-7: System voice separation ──

    def _check_system_voice(self, text: str) -> dict:
        """Check how 'the system' is presented: direct (notifications) vs interpretive.

        Rule: The system should be ENVIRONMENT, not an object being dissected.
        Direct presentation (push notifications, popups) is fine.
        Interpretive presentation (character analyzing system mechanics) means
        the system is being explained too much.

        Returns:
            {direct: int, interpretive: int, ratio: float, warning: bool,
             direct_matches: list, interpretive_matches: list}
        """
        if not text or len(text) < 100:
            return {
                "direct": 0, "interpretive": 0, "ratio": 0.0,
                "warning": False,
                "direct_matches": [], "interpretive_matches": [],
            }

        direct_matches = []
        for pattern in _SYSTEM_DIRECT_PATTERNS:
            for match in pattern.finditer(text):
                direct_matches.append({
                    "match": match.group()[:80],
                    "position": match.start(),
                })

        interpretive_matches = []
        for pattern in _SYSTEM_INTERPRETIVE_PATTERNS:
            for match in pattern.finditer(text):
                start = max(0, match.start() - 20)
                end = min(len(text), match.end() + 40)
                interpretive_matches.append({
                    "match": match.group()[:60],
                    "context": text[start:end],
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

    # ── Canonical names / factual expansion ──

    def _check_canonical_name_usage(self, text: str) -> dict:
        """Detect deprecated character aliases in generated prose."""
        if not text:
            return {"violations": [], "aliases": {}}
        row = self.db.execute(
            "SELECT layers_json FROM writing_meta_contract "
            "WHERE project_id = ? ORDER BY created_at DESC LIMIT 1",
            (self.project_id,),
        ).fetchone()
        layers = {}
        if row:
            try:
                layers = json.loads(row["layers_json"] or "{}")
            except (json.JSONDecodeError, TypeError):
                layers = {}
        aliases = deprecated_aliases_for_layers(layers)
        hits = find_deprecated_aliases(text, aliases)
        return {
            "violations": hits,
            "aliases": aliases,
        }

    def _check_unanchored_fact_expansion(self, text: str, contract_text: str) -> dict:
        """Catch high-impact concrete facts that are not present in the contract.

        This is deliberately narrow. It targets medical/institutional specifics
        that can change continuity if invented by a writer model.
        """
        if not text:
            return {"violations": []}

        patterns = [
            ("社区医院", "medical_visit"),
            ("拍了片", "medical_visit"),
            ("诊断意见", "medical_diagnosis"),
            ("髌骨软化", "medical_diagnosis"),
            ("关节积液", "medical_diagnosis"),
            ("建议休息", "medical_diagnosis"),
            ("请了半天假", "schedule_fact"),
            ("手术", "medical_procedure"),
            ("取出来", "medical_procedure"),
            ("派单量比上月增加", "metric_fact"),
        ]
        violations: list[dict] = []
        contract_text = contract_text or ""
        for marker, kind in patterns:
            if marker not in text or marker in contract_text:
                continue
            pos = text.find(marker)
            start = max(0, pos - 30)
            end = min(len(text), pos + len(marker) + 50)
            violations.append({
                "marker": marker,
                "kind": kind,
                "context": text[start:end].replace("\n", " "),
                "suggestion": "新增医疗/制度事实必须先进入 setup/contract，不得由正文模型自由发明。",
            })
        return {"violations": violations}

    # ── D-25: Suspense summary ──

    def _build_suspense_summary(
        self,
        closing_audit: dict,
        number_temp: dict,
        explanation_check: dict,
        harm_preview: dict,
        paragraph_length: dict | None = None,
        narrator_intrusion: dict | None = None,
        system_voice: dict | None = None,
    ) -> dict:
        """Build a summary of suspense-related checks.

        Returns:
            {overall_quality: str, scores: dict, issues: list}
        """
        scores = {}

        # Closing hook score (0-100)
        hook_quality = closing_audit.get("hook_quality", "unknown")
        hook_score_map = {
            "excellent": 95, "good": 80, "acceptable": 65, "fair": 50, "poor": 30, "unknown": 50,
        }
        scores["hook"] = hook_score_map.get(hook_quality, 50)

        # Number temperature score (0-100)
        total_nums = number_temp.get("total_numbers", 0)
        cold_nums = number_temp.get("cold_numbers", 0)
        if total_nums == 0:
            scores["number_temp"] = 100  # No numbers = no violation
        else:
            scores["number_temp"] = max(0, 100 - (cold_nums / total_nums) * 100)

        # Explanation score (0-100)
        explanations = explanation_check.get("total_explanations", 0)
        if explanations == 0:
            scores["explanation"] = 100
        elif explanations <= 2:
            scores["explanation"] = 70
        elif explanations <= 5:
            scores["explanation"] = 40
        else:
            scores["explanation"] = 10

        # Harm preview score (0-100)
        if harm_preview.get("missing_preview"):
            scores["harm_preview"] = 30
        else:
            scores["harm_preview"] = 100

        # OPT-1: Paragraph length score (0-100)
        if paragraph_length:
            para_violations = len(paragraph_length.get("violations", []))
            if para_violations == 0:
                scores["paragraph_length"] = 100
            elif para_violations <= 2:
                scores["paragraph_length"] = 60
            else:
                scores["paragraph_length"] = max(0, 100 - para_violations * 20)

        # OPT-3: Narrator intrusion score (0-100) — high severity
        if narrator_intrusion:
            intrusions = narrator_intrusion.get("total_intrusions", 0)
            if intrusions == 0:
                scores["narrator_intrusion"] = 100
            elif intrusions == 1:
                scores["narrator_intrusion"] = 50
            else:
                scores["narrator_intrusion"] = max(0, 100 - intrusions * 25)

        # OPT-7: System voice score (0-100)
        if system_voice:
            if system_voice.get("warning"):
                scores["system_voice"] = 30
            elif system_voice.get("interpretive", 0) > 0:
                scores["system_voice"] = 60
            else:
                scores["system_voice"] = 100

        # Overall suspense quality
        avg_score = sum(scores.values()) / len(scores) if scores else 50
        if avg_score >= 85:
            overall = "excellent"
        elif avg_score >= 70:
            overall = "good"
        elif avg_score >= 50:
            overall = "acceptable"
        else:
            overall = "needs_improvement"

        issues = []
        if scores.get("hook", 50) < 65:
            issues.append("closing_hook_weak")
        if scores.get("number_temp", 50) < 70:
            issues.append("number_temperature_low")
        if scores.get("explanation", 50) < 50:
            issues.append("too_many_explanations")
        if scores.get("harm_preview", 50) < 50:
            issues.append("missing_harm_preview")
        if scores.get("paragraph_length", 100) < 60:
            issues.append("paragraph_too_long")
        if scores.get("narrator_intrusion", 100) < 50:
            issues.append("narrator_overreach")
        if scores.get("system_voice", 100) < 50:
            issues.append("system_over_explained")

        return {
            "overall_quality": overall,
            "scores": scores,
            "average_score": round(avg_score, 1),
            "issues": issues,
        }

    # ── L3: Chapter-level gate ──

    def should_trigger_l3(self, chapter_key: str) -> bool:
        """Check if all shots in a chapter have passed L4."""
        total = self.db.execute(
            "SELECT COUNT(*) as cnt FROM writing_shots "
            "WHERE run_id = ? AND layer_key = ?",
            (self.run_id, chapter_key),
        ).fetchone()["cnt"]

        if total == 0:
            return False

        passed = self.db.execute(
            "SELECT COUNT(*) as cnt FROM writing_architect_gates "
            "WHERE run_id = ? AND level = 'L4' AND scope_key IN ("
            "  SELECT shot_id FROM writing_shots WHERE run_id = ? AND layer_key = ?"
            ") AND status = 'passed'",
            (self.run_id, self.run_id, chapter_key),
        ).fetchone()["cnt"]

        # Already triggered?
        existing = self.db.execute(
            "SELECT status FROM writing_architect_gates "
            "WHERE run_id = ? AND level = 'L3' AND scope_key = ?",
            (self.run_id, chapter_key),
        ).fetchone()

        if existing and existing["status"] == "passed":
            return False
        return passed >= total

    def evaluate_l3(self, chapter_key: str) -> dict:
        """L3 gate: Chapter-level structure check.

        Checks:
        - POV balance: are all required POVs covered?
        - Chapter arc: does the chapter have a clear emotional arc?
        - Hook quality: is the chapter-end hook effective?
        - Shot sequence: is the shot ordering coherent?

        For P0: uses deterministic checks + optional AI review.
        """
        shots = self.db.execute(
            "SELECT ws.shot_id, ws.shot_index, ws.shot_status, ws.light_status, "
            "wsc.must_land_json, wsc.pov_routing_json, wsc.contract_json "
            "FROM writing_shots ws "
            "LEFT JOIN writing_shot_contracts wsc ON ws.shot_id = wsc.shot_id "
            "AND wsc.run_id = ? "
            "WHERE ws.run_id = ? AND ws.layer_key = ? "
            "ORDER BY ws.shot_index",
            (self.run_id, self.run_id, chapter_key),
        ).fetchall()

        issues = []
        green_count = 0
        yellow_count = 0
        red_count = 0

        pov_counts: dict[str, int] = {}
        for shot in shots:
            status = shot["light_status"]
            if status == "green":
                green_count += 1
            elif status == "yellow":
                yellow_count += 1
            else:
                red_count += 1

            # Track POV coverage
            pov_routing = shot["pov_routing_json"]
            if pov_routing:
                try:
                    pov_data = json.loads(pov_routing) if isinstance(pov_routing, str) else pov_routing
                    pov_name = pov_data.get("pov_character", "unknown")
                    pov_counts[pov_name] = pov_counts.get(pov_name, 0) + 1
                except Exception:
                    pass

        # Check 1: POV balance
        if pov_counts:
            min_pov = min(pov_counts.values()) if pov_counts else 0
            max_pov = max(pov_counts.values()) if pov_counts else 0
            if max_pov > min_pov * 3 and max_pov > 2:
                issues.append(
                    f"POV imbalance: {pov_counts} (max={max_pov}, min={min_pov})"
                )

        # Check 2: Too many red/yellow shots
        if red_count > 0:
            issues.append(f"{red_count} shot(s) with red light status")
        if yellow_count > len(shots) // 2:
            issues.append(f"{yellow_count}/{len(shots)} shots yellow — may need chapter-level repair")

        # Check 3: Shot sequence completeness
        shot_indices = [s["shot_index"] for s in shots]
        expected = list(range(1, len(shots) + 1))
        if shot_indices != expected:
            issues.append(f"Shot sequence gap: got {shot_indices}, expected {expected}")

        # Check 4: Chapter-end hook must be an unfinished action/interruption.
        chapter_hook = self._check_chapter_end_hook(shots)
        if not chapter_hook["passed"]:
            issues.append(
                "chapter_hook_weak: final shot must end on unfinished action "
                "or interruption, not closure/explanation"
            )

        # Check 4b: Titled shots must be real scenes, not thin labeled stubs.
        shot_density = self._check_titled_shot_density(shots)
        for item in shot_density.get("violations", []):
            issues.append(
                "shot_too_thin: "
                f"s{item['shot_index']:02d} {item['title']} "
                f"{item['chars']}<{item['min_chars']} chars"
            )

        # Check 5 (OPT-4): Character presence — warn if a POV character has zero shots
        # Get POV characters from the meta-contract
        meta_contract_row = self.db.execute(
            "SELECT layers_json FROM writing_meta_contract "
            "WHERE project_id = ? ORDER BY created_at DESC LIMIT 1",
            (self.project_id,),
        ).fetchone()
        if meta_contract_row:
            try:
                layers = json.loads(meta_contract_row["layers_json"])
                pov_characters = layers.get("identity", {}).get("pov_characters", [])
            except (json.JSONDecodeError, KeyError):
                pov_characters = []

            if pov_characters:
                absent_in_chapter = [c for c in pov_characters if c not in pov_counts]
                if absent_in_chapter:
                    # Cross-chapter check: are they absent in recent chapters too?
                    cross_absent = self._check_cross_chapter_absence(
                        absent_in_chapter, chapter_key
                    )
                    if cross_absent:
                        issues.append(
                            f"character_absence: {cross_absent} absent in this AND "
                            f"previous chapter — risk of reader forgetting"
                        )
                    else:
                        issues.append(
                            f"character_absence: {absent_in_chapter} absent in this chapter"
                        )

        passed = len(issues) == 0

        result = {
            "passed": passed,
            "chapter_key": chapter_key,
            "shot_count": len(shots),
            "green_count": green_count,
            "yellow_count": yellow_count,
            "red_count": red_count,
            "pov_coverage": pov_counts,
            "chapter_hook": chapter_hook,
            "shot_density": shot_density,
            "issues": issues,
        }

        self._record_gate("L3", chapter_key, result)
        return result

    def _check_chapter_end_hook(self, shots) -> dict:
        """Hard L3 chapter-hook check on the final shot's current text."""
        if not shots:
            return {
                "passed": False,
                "shot_id": None,
                "shot_index": None,
                "violation": "chapter has no shots",
                "last_sentence": "",
                "hook_quality": "unknown",
                "is_unfinished": False,
            }

        last_shot = shots[-1]
        text = TextRepository(self.db).get_shot_text(last_shot["shot_id"])
        closing = self._check_closing_sentence(text)
        passed = (
            closing.get("violation") is None
            and closing.get("hook_quality") == "excellent"
            and closing.get("is_unfinished") is True
        )
        return {
            "passed": passed,
            "shot_id": last_shot["shot_id"],
            "shot_index": last_shot["shot_index"],
            "violation": closing.get("violation"),
            "type": closing.get("type"),
            "last_sentence": closing.get("last_sentence", ""),
            "hook_quality": closing.get("hook_quality", "unknown"),
            "is_unfinished": closing.get("is_unfinished", False),
        }

    def _check_titled_shot_density(self, shots) -> dict:
        """Require editor-facing titled shots to have enough scene weight."""
        violations: list[dict] = []
        repo = TextRepository(self.db)
        total = len(shots)
        for shot in shots:
            title = self._shot_title_from_row(shot)
            if not title:
                continue
            text = repo.get_shot_text(shot["shot_id"])
            chars = len(re.sub(r"\s+", "", text or ""))
            is_final = shot["shot_index"] == total
            min_chars = 500 if is_final else 450
            if chars < min_chars:
                violations.append({
                    "shot_id": shot["shot_id"],
                    "shot_index": shot["shot_index"],
                    "title": title,
                    "chars": chars,
                    "min_chars": min_chars,
                })
        return {
            "passed": not violations,
            "violations": violations,
        }

    @staticmethod
    def _shot_title_from_row(shot) -> str | None:
        for field in ("must_land_json", "contract_json"):
            raw = shot[field] if field in shot.keys() else None
            if not raw:
                continue
            try:
                data = json.loads(raw) if isinstance(raw, str) else raw
            except (json.JSONDecodeError, TypeError):
                continue
            if not isinstance(data, dict):
                continue
            title = data.get("title")
            if isinstance(title, str) and title.strip():
                return title.strip()
            must_land = data.get("must_land")
            if isinstance(must_land, dict):
                nested_title = must_land.get("title")
                if isinstance(nested_title, str) and nested_title.strip():
                    return nested_title.strip()
        return None

    def _check_cross_chapter_absence(
        self, absent_characters: list[str], current_chapter: str
    ) -> list[str]:
        """Check if characters are absent across consecutive chapters.

        Returns the subset of absent_characters that were ALSO absent
        in the immediately preceding chapter (same project, any run).
        """
        if not absent_characters:
            return []

        # Extract volume prefix (e.g. 'v01' from 'v01.c03')
        import re as _re
        m = _re.match(r'(v\d+)\.c(\d+)', current_chapter)
        if not m:
            return []
        volume = m.group(1)
        current_num = int(m.group(2))

        if current_num <= 1:
            return []  # First chapter — no previous to compare

        prev_chapter = f"{volume}.c{current_num - 1:02d}"

        # Find POV characters in the previous chapter
        prev_pov_row = self.db.execute(
            "SELECT wsc.pov_routing_json FROM writing_shots ws "
            "JOIN writing_shot_contracts wsc ON ws.shot_id = wsc.shot_id "
            "AND wsc.run_id = ws.run_id "
            "WHERE ws.layer_key = ? AND ws.shot_status IN ('done_green', 'done_yellow')",
            (prev_chapter,),
        ).fetchall()

        if not prev_pov_row:
            return []  # No data for previous chapter

        prev_pov_chars = set()
        for row in prev_pov_row:
            try:
                pov_data = json.loads(row["pov_routing_json"]) if row["pov_routing_json"] else {}
                c = pov_data.get("pov_character")
                if c:
                    prev_pov_chars.add(c)
            except (json.JSONDecodeError, KeyError):
                pass

        # Characters absent in BOTH chapters
        return [c for c in absent_characters if c not in prev_pov_chars]

    # ── L2: Volume-level gate (P1) ──

    def should_trigger_l2(self, volume_key: str) -> bool:
        """Check if all chapters in a volume have passed L3."""
        chapters = self.db.execute(
            "SELECT DISTINCT layer_key FROM writing_shots "
            "WHERE run_id = ? AND layer_key LIKE ?",
            (self.run_id, f"{volume_key}.c%"),
        ).fetchall()

        if not chapters:
            return False

        chapter_keys = [c["layer_key"] for c in chapters]
        passed = self.db.execute(
            "SELECT COUNT(*) as cnt FROM writing_architect_gates "
            "WHERE run_id = ? AND level = 'L3' AND scope_key IN ("
            + ",".join("?" * len(chapter_keys))
            + ") AND status = 'passed'",
            (self.run_id, *chapter_keys),
        ).fetchone()["cnt"]

        existing = self.db.execute(
            "SELECT 1 FROM writing_architect_gates "
            "WHERE run_id = ? AND level = 'L2' AND scope_key = ?",
            (self.run_id, volume_key),
        ).fetchone()

        return not existing and passed >= len(chapter_keys)

    def evaluate_l2(self, volume_key: str) -> dict:
        """L2 gate: Volume-level character arc check. (P1)"""
        result = {
            "passed": True,
            "volume_key": volume_key,
            "issues": [],
            "note": "L2 gate is P1 — full implementation requires multi-chapter context",
        }
        self._record_gate("L2", volume_key, result)
        return result

    # ── L1: Universe-level gate (P1) ──

    def should_trigger_l1(self) -> bool:
        """Check if all volumes have passed L2."""
        existing = self.db.execute(
            "SELECT 1 FROM writing_architect_gates "
            "WHERE run_id = ? AND level = 'L1' AND scope_key = 'global'",
            (self.run_id,),
        ).fetchone()
        return not existing  # P0: just record it once

    def evaluate_l1(self) -> dict:
        """L1 gate: Universe-level world rules consistency check. (P1)"""
        result = {
            "passed": True,
            "scope_key": "global",
            "issues": [],
            "note": "L1 gate is P1 — full implementation requires full-book context",
        }
        self._record_gate("L1", "global", result)
        return result

    # ── Internal ──

    def _record_gate(self, level: str, scope_key: str, result: dict) -> str:
        """Record gate result in writing_architect_gates."""
        gate_id = generate_ulid()
        status = "passed" if result.get("passed") else "failed"

        self.db.execute(
            "INSERT OR REPLACE INTO writing_architect_gates "
            "(gate_id, run_id, level, scope_key, status, check_result_json) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (gate_id, self.run_id, level, scope_key, status,
             json.dumps(result, ensure_ascii=False)),
        )
        self.db.commit()
        stage = level.lower()
        audit = AuditRecorder(self.db, project_id=self.project_id, run_id=self.run_id)
        audit.record_event(
            stage=stage,
            event_type="architect_gate",
            status=status,
            shot_id=scope_key if level == "L4" else None,
            actor="architect_gate",
            metrics={
                "score": result.get("score"),
                "level": level,
            },
            payload={
                "scope_key": scope_key,
                "issues": result.get("issues", []),
                "hard_issues": result.get("hard_issues", []),
            },
            failure_category=None if status == "passed" else "writer_drift",
            failure_detail="; ".join(str(i) for i in result.get("issues", [])[:3])
            if status == "failed" else None,
        )
        if status == "failed":
            audit.record_failure_attribution(
                stage=stage,
                failure_category="writer_drift",
                shot_id=scope_key if level == "L4" else None,
                root_cause={
                    "level": level,
                    "scope_key": scope_key,
                    "issues": result.get("issues", []),
                    "hard_issues": result.get("hard_issues", []),
                    "score": result.get("score"),
                },
                evidence_refs={"gate_id": gate_id},
                suggested_action="若同类 L4/L3 失败重复出现，回退优化大纲或章前 setup，而不是继续盲目返写。",
            )
        return gate_id

    def get_gate_result(self, level: str, scope_key: str) -> dict | None:
        """Get a specific gate result."""
        row = self.db.execute(
            "SELECT * FROM writing_architect_gates "
            "WHERE run_id = ? AND level = ? AND scope_key = ?",
            (self.run_id, level, scope_key),
        ).fetchone()
        if row is None:
            return None
        result = dict(row)
        result["check_result_json"] = json.loads(result["check_result_json"])
        return result

    def get_chapter_gates(self, chapter_key: str) -> list[dict]:
        """Get all gate results for a chapter (L4 + L3)."""
        rows = self.db.execute(
            "SELECT * FROM writing_architect_gates "
            "WHERE run_id = ? AND ("
            "  (level = 'L3' AND scope_key = ?) OR "
            "  (level = 'L4' AND scope_key IN ("
            "    SELECT shot_id FROM writing_shots "
            "    WHERE run_id = ? AND layer_key = ?"
            "  ))"
            ") ORDER BY level, created_at",
            (self.run_id, chapter_key, self.run_id, chapter_key),
        ).fetchall()
        results = []
        for row in rows:
            r = dict(row)
            r["check_result_json"] = json.loads(r["check_result_json"])
            results.append(r)
        return results
