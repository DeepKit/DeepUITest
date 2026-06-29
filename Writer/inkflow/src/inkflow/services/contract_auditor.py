"""Deterministic contract auditor used before meta-contract confirmation."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ContractAuditIssue:
    code: str
    field: str
    severity: str
    message: str
    suggested_action: str

    def to_dict(self) -> dict[str, str]:
        return {
            "code": self.code,
            "field": self.field,
            "severity": self.severity,
            "message": self.message,
            "suggested_action": self.suggested_action,
        }


class ContractAuditor:
    """Two-pass local contract review.

    The confirmation gate must be deterministic: it decides whether a contract
    can enter the DB as confirmed, so it cannot depend on remote model
    availability or non-repeatable wording preferences.
    """

    REQUIRED_SECTIONS = (
        "identity",
        "narrative_voice",
        "hard_boundaries",
        "style_locks",
        "anti_patterns",
        "world_knowledge",
        "motif_system",
        "creative_zones",
        "suspense_config",
        "structure_rules",
    )

    PLACEHOLDER_MARKERS = (
        "<<请填写",
        "TODO",
        "TBD",
        "待填写",
        "__",
    )

    PROMPT_ARTIFACT_MARKERS = (
        "### 场景",
        "brilliance=",
        "badsmell=",
        "POV=",
        "green ·",
        "yellow ·",
        "red ·",
    )

    def review_twice(self, contract_data: dict[str, Any]) -> dict[str, Any]:
        """Run two required reviews and return a machine-readable verdict."""
        round1 = self._review_structure(contract_data)
        round2 = self._review_production_readiness(contract_data)
        reviews = [round1, round2]
        blocker_count = sum(
            1
            for review in reviews
            for issue in review["issues"]
            if issue["severity"] == "blocker"
        )
        warning_count = sum(len(review["warnings"]) for review in reviews)
        return {
            "schema": "inkflow.contract_audit.v1",
            "passed": blocker_count == 0,
            "required_reviews": 2,
            "passed_reviews": sum(1 for review in reviews if review["passed"]),
            "blocker_count": blocker_count,
            "warning_count": warning_count,
            "reviews": reviews,
        }

    def _review_structure(self, contract_data: dict[str, Any]) -> dict[str, Any]:
        issues: list[ContractAuditIssue] = []
        warnings: list[ContractAuditIssue] = []

        for section in self.REQUIRED_SECTIONS:
            value = contract_data.get(section)
            if not isinstance(value, dict) or not value:
                issues.append(_issue(
                    "missing_required_section",
                    section,
                    f"契约缺少必需段落 {section}，不能进入生产。",
                    "让架构师补齐该段落后重新提交契约复审。",
                ))

        identity = _as_dict(contract_data.get("identity"))
        if not _has_text(identity.get("character_arcs")):
            issues.append(_issue(
                "missing_character_arcs",
                "identity.character_arcs",
                "角色弧线为空，写手无法判断人物变化方向。",
                "和架构师讨论每个 POV 角色的起点、压力、变化和终点。",
            ))

        creative = _as_dict(contract_data.get("creative_zones"))
        if not _has_text(creative.get("chapter_2_interpretation")):
            warnings.append(_warning(
                "missing_chapter_2_interpretation",
                "creative_zones.chapter_2_interpretation",
                "第 2 章诠释为空；如果项目不是从第 2 章续写，可在后续 setup 中补足目标章意图。",
                "让架构师把目标章的编辑意图写入对应 chapter_N_events 或 setup。",
            ))

        chapter_fields = _chapter_event_fields(contract_data)
        if not chapter_fields:
            issues.append(_issue(
                "missing_chapter_events",
                "structure_rules.chapter_N_events",
                "契约没有任何 chapter_N_events，无法生成章节。",
                "让架构师至少补齐下一章的逐 shot 事件。",
            ))

        placeholder_hits = _find_markers(contract_data, self.PLACEHOLDER_MARKERS)
        for field, marker in placeholder_hits[:8]:
            issues.append(_issue(
                "unresolved_placeholder",
                field,
                f"契约仍含未解决占位符或待办标记: {marker}",
                "打回架构师和人类继续讨论，不能让占位符进入 confirmed 契约。",
            ))

        return _review_result(
            round_no=1,
            name="结构完整性复审",
            issues=issues,
            warnings=warnings,
        )

    def _review_production_readiness(
        self, contract_data: dict[str, Any],
    ) -> dict[str, Any]:
        issues: list[ContractAuditIssue] = []
        warnings: list[ContractAuditIssue] = []

        declared_povs = _declared_povs(contract_data)
        for field, events in _chapter_event_fields(contract_data).items():
            if not isinstance(events, list) or not events:
                issues.append(_issue(
                    "empty_chapter_events",
                    f"structure_rules.{field}",
                    f"{field} 不是非空列表，不能生产章节。",
                    "让架构师按 shot 拆出本章事件列表。",
                ))
                continue

            seen: set[int] = set()
            for idx, event in enumerate(events, start=1):
                path = f"structure_rules.{field}[{idx}]"
                if not isinstance(event, dict):
                    issues.append(_issue(
                        "invalid_chapter_event",
                        path,
                        "chapter event 必须是字典，包含 shot/pov/event。",
                        "让架构师重新生成结构化 chapter_N_events。",
                    ))
                    continue

                shot_no = event.get("shot", idx)
                if not isinstance(shot_no, int):
                    issues.append(_issue(
                        "invalid_shot_number",
                        f"{path}.shot",
                        "shot 编号必须是整数。",
                        "让架构师重新编号本章 shot。",
                    ))
                elif shot_no in seen:
                    issues.append(_issue(
                        "duplicate_shot_number",
                        f"{path}.shot",
                        f"shot 编号重复: {shot_no}",
                        "让架构师重新整理本章 shot 顺序。",
                    ))
                else:
                    seen.add(shot_no)

                pov = str(event.get("pov") or "").strip()
                if not pov or pov.lower() == "unknown":
                    issues.append(_issue(
                        "missing_pov",
                        f"{path}.pov",
                        "shot 缺少明确 POV，后续视角门禁无法工作。",
                        "让架构师为每个 shot 指定 POV。",
                    ))
                elif declared_povs and pov not in declared_povs:
                    issues.append(_issue(
                        "undeclared_pov",
                        f"{path}.pov",
                        f"POV '{pov}' 没有在 identity.pov_characters 中声明。",
                        "在人类确认后，把该 POV 加入角色列表，或修正本 shot POV。",
                    ))

                event_text = str(event.get("event") or "").strip()
                if len(event_text) < 4:
                    issues.append(_issue(
                        "empty_must_land",
                        f"{path}.event",
                        "shot event 太短，无法作为 must_land。",
                        "让架构师写成可落地的动作、信息变化或关系变化。",
                    ))

                artifact_hits = [
                    marker for marker in self.PROMPT_ARTIFACT_MARKERS
                    if marker in event_text
                ]
                for marker in artifact_hits:
                    issues.append(_issue(
                        "prompt_artifact_in_contract",
                        f"{path}.event",
                        f"契约事件含管线提示词残留: {marker}",
                        "让架构师清理编辑标记，只保留小说内事件。",
                    ))

            expected = list(range(1, len(events) + 1))
            if seen and sorted(seen) != expected:
                warnings.append(_warning(
                    "non_sequential_shots",
                    f"structure_rules.{field}",
                    f"{field} shot 编号不是连续 1..N。",
                    "建议架构师重排编号，避免审计和导出定位混乱。",
                ))

            final_event = events[-1] if events and isinstance(events[-1], dict) else {}
            final_roles = _normalize_roles(final_event.get("type_roles"))
            final_text = str(final_event.get("event") or "")
            if "hook" not in final_roles and "钩子" not in final_text:
                warnings.append(_warning(
                    "chapter_hook_not_explicit",
                    f"structure_rules.{field}[-1]",
                    "最后一个 shot 没有显式 hook 职责；setup 会补默认 hook，但契约层最好写清。",
                    "让架构师明确章末悬念、留白或未完成动作。",
                ))

        suspense = _as_dict(contract_data.get("suspense_config"))
        if not suspense.get("chapter_hooks"):
            warnings.append(_warning(
                "missing_chapter_hooks",
                "suspense_config.chapter_hooks",
                "契约没有显式章末钩子要求，后续 L3 只能用默认钩子规则。",
                "让架构师写出读者离开本章时应带走的问题。",
            ))

        return _review_result(
            round_no=2,
            name="生产就绪复审",
            issues=issues,
            warnings=warnings,
        )


def _review_result(
    *,
    round_no: int,
    name: str,
    issues: list[ContractAuditIssue],
    warnings: list[ContractAuditIssue],
) -> dict[str, Any]:
    return {
        "round": round_no,
        "auditor": f"契约审计师-{round_no}",
        "name": name,
        "passed": not issues,
        "issues": [issue.to_dict() for issue in issues],
        "warnings": [warning.to_dict() for warning in warnings],
    }


def _issue(
    code: str,
    field: str,
    message: str,
    suggested_action: str,
) -> ContractAuditIssue:
    return ContractAuditIssue(
        code=code,
        field=field,
        severity="blocker",
        message=message,
        suggested_action=suggested_action,
    )


def _warning(
    code: str,
    field: str,
    message: str,
    suggested_action: str,
) -> ContractAuditIssue:
    return ContractAuditIssue(
        code=code,
        field=field,
        severity="warning",
        message=message,
        suggested_action=suggested_action,
    )


def _as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _has_text(value: Any) -> bool:
    return bool(str(value or "").strip())


def _chapter_event_fields(contract_data: dict[str, Any]) -> dict[str, Any]:
    structure = _as_dict(contract_data.get("structure_rules"))
    return {
        key: value
        for key, value in structure.items()
        if key.startswith("chapter_") and key.endswith("_events")
    }


def _declared_povs(contract_data: dict[str, Any]) -> set[str]:
    identity = _as_dict(contract_data.get("identity"))
    raw = identity.get("pov_characters") or []
    if isinstance(raw, str):
        raw = [item.strip() for item in raw.replace("，", ",").split(",")]
    if not isinstance(raw, list):
        return set()
    return {str(item).strip() for item in raw if str(item).strip()}


def _normalize_roles(value: Any) -> set[str]:
    if value is None:
        return set()
    if isinstance(value, str):
        return {item.strip() for item in value.replace("，", ",").split(",") if item.strip()}
    if isinstance(value, list):
        return {str(item).strip() for item in value if str(item).strip()}
    return set()


def _find_markers(data: Any, markers: tuple[str, ...], path: str = "$") -> list[tuple[str, str]]:
    hits: list[tuple[str, str]] = []
    if isinstance(data, dict):
        for key, value in data.items():
            hits.extend(_find_markers(value, markers, f"{path}.{key}"))
    elif isinstance(data, list):
        for idx, value in enumerate(data):
            hits.extend(_find_markers(value, markers, f"{path}[{idx}]"))
    else:
        text = str(data)
        for marker in markers:
            if marker in text:
                hits.append((path, marker))
    return hits

