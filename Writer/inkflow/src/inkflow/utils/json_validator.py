"""JSON 字段验证工具 (DB-7)。

用途：在服务层统一校验 JSON 字段，防止非法 JSON 进入核心表。
"""

from __future__ import annotations

import json


def validate_json(value: str | None, field_name: str = "unknown") -> dict | list | None:
    """验证并解析 JSON 字符串。

    Args:
        value: JSON 字符串或 None。
        field_name: 字段名（用于错误消息）。

    Returns:
        解析后的 dict/list，或 None（如果输入为 None）。

    Raises:
        ValueError: 如果 value 不是合法 JSON。
    """
    if value is None:
        return None
    if isinstance(value, (dict, list)):
        return value
    try:
        return json.loads(value)
    except (json.JSONDecodeError, TypeError) as exc:
        raise ValueError(
            f"Invalid JSON in field '{field_name}': {exc}"
        ) from exc


def safe_json_dumps(obj: dict | list | None, field_name: str = "unknown") -> str | None:
    """安全序列化为 JSON 字符串。

    Args:
        obj: Python dict/list 或 None。
        field_name: 字段名（用于错误消息）。

    Returns:
        JSON 字符串，或 None（如果输入为 None）。

    Raises:
        ValueError: 如果序列化失败。
    """
    if obj is None:
        return None
    try:
        return json.dumps(obj, ensure_ascii=False)
    except (TypeError, ValueError) as exc:
        raise ValueError(
            f"Cannot serialize JSON for field '{field_name}': {exc}"
        ) from exc