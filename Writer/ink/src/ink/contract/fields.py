"""层级契约字段标准投影。

对齐 ``docs/implementation-contract-v1.md`` §字段标准投影（2015-2018 行）：
BookContract / VolumeContract / PartContract / ChapterContract 各自的合法字段路径、
类型与是否必填。ShotContract 对齐 5 张结构化子表（must_land / anti_write /
scene_contract / persona / soft_constraints）。

字段路径采用点分形式（如 ``identity.title``），与 ``writing_source_coverage_matrix.
contract_field_path`` 列对齐——patch 应用时按此路径更新 coverage。

严格白名单语义：patch ���每个 op 的 path 必须在本表内，否则 ``ContractPatchError``。
"""
from __future__ import annotations

# 每个字段的元信息：type ∈ str/list/dict，required 是否必填（confirmed 时不可缺）
# 复合字段（identity、volume_id 等）本身是 dict，其叶子路径在 LEAF_FIELDS 里展开。
CONTRACT_FIELD_SCHEMAS: dict[str, dict[str, dict[str, object]]] = {
    "book": {
        "identity": {"type": "dict", "required": True, "children": {"title": {"type": "str", "required": True}}},
        "logline": {"type": "str", "required": True},
        "genre_positioning": {"type": "str", "required": False},
        "narrative_voice": {"type": "list", "required": False},
        "hard_boundaries": {"type": "list", "required": False},
        "world_knowledge": {"type": "list", "required": False},
        "character_bibles": {"type": "list", "required": False},
        "evidence_chain": {"type": "list", "required": False},
        "motif_system": {"type": "list", "required": False},
        "style_locks": {"type": "list", "required": False},
        "quality_profile": {"type": "dict", "required": False},
        "forbidden_directions": {"type": "list", "required": False},
        "source_refs": {"type": "list", "required": False},
    },
    "volume": {
        "volume_id": {"type": "dict", "required": True, "children": {"name": {"type": "str", "required": True}}},
        "function": {"type": "str", "required": False},
        "arc_goal": {"type": "str", "required": False},
        "main_conflict": {"type": "str", "required": False},
        "entry_state": {"type": "str", "required": False},
        "exit_state": {"type": "str", "required": False},
        "evidence_progression": {"type": "list", "required": False},
        "character_arc_delta": {"type": "list", "required": False},
        "motif_progression": {"type": "list", "required": False},
        "pacing_target": {"type": "str", "required": False},
        "required_turning_points": {"type": "list", "required": False},
        "forbidden_repetition": {"type": "list", "required": False},
        "source_refs": {"type": "list", "required": False},
    },
    "part": {
        "part_id": {"type": "dict", "required": True, "children": {"name": {"type": "str", "required": True}}},
        "local_goal": {"type": "str", "required": False},
        "transition_function": {"type": "str", "required": False},
        "required_reveals": {"type": "list", "required": False},
        "emotional_curve": {"type": "list", "required": False},
        "dependency_scopes": {"type": "list", "required": False},
        "risk_notes": {"type": "list", "required": False},
        "source_refs": {"type": "list", "required": False},
    },
    "chapter": {
        "chapter_id": {"type": "dict", "required": True, "children": {"title": {"type": "str", "required": True}}},
        "chapter_function": {"type": "str", "required": False},
        "scene_hook": {"type": "str", "required": False},
        "institution_action": {"type": "str", "required": False},
        "character_cost": {"type": "str", "required": False},
        "must_land": {"type": "list", "required": False},
        "evidence_plant_or_payoff": {"type": "list", "required": False},
        "sci_fi_or_world_anchor": {"type": "str", "required": False},
        "chapter_end_crack": {"type": "str", "required": False},
        "dialogue_anchor": {"type": "str", "required": False},
        "sensory_anchor": {"type": "str", "required": False},
        "pacing_shape": {"type": "str", "required": False},
        "continuity_refs": {"type": "list", "required": False},
        "anti_write": {"type": "list", "required": False},
        "dependencies": {"type": "list", "required": False},
        "source_refs": {"type": "list", "required": False},
        # --- 悬疑工程学契约字段（v3.3 对齐，由大纲解析器注入，patch_engine 落库） ---
        "pursuit_type": {"type": "str", "required": False},      # 追读类型：追查/压迫/围困
        "main_engine": {"type": "str", "required": False},        # 主引擎：预埋种植/预埋回收/数字有体温...
        "emotion_target": {"type": "str", "required": False},     # 情感刻度目标 1-5
        "silence_point": {"type": "str", "required": False},      # 沉默点：角色（写了什么但不告诉谁）
        "causal_anchor": {"type": "str", "required": False},      # 物理因果锚点（读者要明白的后果链）
        "hook_type": {"type": "str", "required": False},          # 章末钩子类型：证据/责任/倒计时/反转/道德
        "light_state": {"type": "str", "required": False},        # 灯态：绿/黄/红/封存/白
        "chapter_end_hook": {"type": "str", "required": False},   # 章末钩子原文
    },
    "shot": {
        # 对齐 5 张结构化子表：writing_shot_must_land / anti_write / scene_contract /
        # persona_assignment / soft_constraints
        "must_land": {
            "type": "dict",
            "required": False,
            "children": {
                "events": {"type": "list", "required": True},
                "beats": {"type": "list", "required": True},
                "information_releases": {"type": "list", "required": True},
            },
        },
        "anti_write": {
            "type": "dict",
            "required": False,
            "children": {
                "forbidden_facts": {"type": "list", "required": True},
                "forbidden_words": {"type": "list", "required": True},
                "pov_only": {"type": "list", "required": True},
            },
        },
        "scene_contract": {
            "type": "dict",
            "required": False,
            "children": {
                "location": {"type": "str", "required": True},
                "time_of_day": {"type": "str", "required": True},
                "characters_present": {"type": "list", "required": True},
                "character_positions": {"type": "dict", "required": True},
            },
        },
        "persona": {
            "type": "dict",
            "required": False,
            "children": {
                "persona": {"type": "str", "required": True},
                "intensity": {"type": "dict", "required": True},
                "is_creative_shot": {"type": "str", "required": False},
                "is_suspense_shot": {"type": "str", "required": False},
            },
        },
        "soft_constraints": {
            "type": "dict",
            "required": False,
            "children": {
                "relaxable_rules": {"type": "list", "required": True},
                "deviation_budget": {"type": "str", "required": True},
            },
        },
    },
}

# 叶子字段白名单：把复合 dict 展开成全部合法点分路径。
# 例：identity → {"identity", "identity.title"}；volume_id → {"volume_id", "volume_id.name"}
def _build_leaf_whitelist() -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for scope, fields in CONTRACT_FIELD_SCHEMAS.items():
        paths: set[str] = set()
        for name, meta in fields.items():
            paths.add(name)
            children = meta.get("children")
            if isinstance(children, dict):
                for child_name in children:
                    paths.add(f"{name}.{child_name}")
        out[scope] = paths
    return out

_LEAF_WHITELIST = _build_leaf_whitelist()


def validate_field_path(scope_type: str, path: str) -> bool:
    """严格白名单校验：path 是否属于该 scope 的合法字段路径。

    ``identity.title`` 合法；``identity.bad`` 不合法；``unknown_field`` 不合法。
    """
    if scope_type not in _LEAF_WHITELIST:
        return False
    return path in _LEAF_WHITELIST[scope_type]


def list_required_fields(scope_type: str) -> list[str]:
    """返回该 scope 的必填叶子字段路径（confirmed 时不可缺）。

    复合必填字段（如 ``identity``）返回其必填叶子（``identity.title``），
    外加复合字段自身路径（``identity``）——两者都必须在 payload 中存在。
    """
    if scope_type not in CONTRACT_FIELD_SCHEMAS:
        return []
    required: list[str] = []
    for name, meta in CONTRACT_FIELD_SCHEMAS[scope_type].items():
        if not meta.get("required"):
            continue
        required.append(name)
        children = meta.get("children")
        if isinstance(children, dict):
            for child_name, child_meta in children.items():
                if child_meta.get("required"):
                    required.append(f"{name}.{child_name}")
    return required


def validate_contract_payload(scope_type: str, payload: dict) -> list[str]:
    """校验 payload 是否符合 scope_type 的字段 schema，返回错误列表。

    检查：
    1. 所有字段路径是否在白名单内
    2. 必填字段是否都存在
    """
    errors: list[str] = []

    if scope_type not in CONTRACT_FIELD_SCHEMAS:
        errors.append(f"unknown scope_type: {scope_type}")
        return errors

    # 1. 检查所有字段路径是否在白名单内
    def _check_paths(obj: dict, prefix: str = "") -> None:
        for key, value in obj.items():
            path = f"{prefix}.{key}" if prefix else key
            if path not in _LEAF_WHITELIST.get(scope_type, set()):
                # 检查是否是复合字段的父节点
                is_parent = any(p.startswith(path + ".") for p in _LEAF_WHITELIST.get(scope_type, set()))
                if not is_parent:
                    errors.append(f"field path not in whitelist: {path}")
            if isinstance(value, dict):
                _check_paths(value, path)

    _check_paths(payload)

    # 2. 检查必填字段
    for required_path in list_required_fields(scope_type):
        parts = required_path.split(".")
        node = payload
        found = True
        for part in parts:
            if isinstance(node, dict) and part in node:
                node = node[part]
            else:
                found = False
                break
        if not found:
            errors.append(f"required field missing: {required_path}")

    return errors


def extract_field_paths_from_payload(scope_type: str, payload: dict) -> list[str]:
    """从 payload 提取所有已定义的字段路径（用于追踪）。"""
    if scope_type not in CONTRACT_FIELD_SCHEMAS:
        return []

    paths: set[str] = set()

    def _extract(obj: dict, prefix: str = "") -> None:
        for key, value in obj.items():
            path = f"{prefix}.{key}" if prefix else key
            if path in _LEAF_WHITELIST.get(scope_type, set()):
                paths.add(path)
            if isinstance(value, dict):
                _extract(value, path)

    _extract(payload)
    return sorted(paths)
