"""复合 shot_id 生成与解析。

继承自 DeepStory 8层金字塔设计。
逻辑格式: {layer_key}.s{shot_index}
示例: v01.c02.s03

生产 run attempt 使用: {logical_shot_id}@{run_id}
示例: v01.c02.s03@01KW3Q5NCBPZWRG254EXAH2PK1

详见 docs/design-8layer-hierarchy.md
"""

from __future__ import annotations

import re
from typing import NamedTuple


class ShotIdParts(NamedTuple):
    """shot_id 解析结果。"""
    volume: str      # "v01"
    chapter: str     # "c02"
    section: str     # "s03"
    layer_key: str   # "v01.c02"


# v01.c02.s03
_SHOT_ID_RE = re.compile(r'^(v\d{2})\.(c\d{2})\.(s\d{2})$')

# v01.c02.s03@01KW3Q5NCBPZWRG254EXAH2PK1
_ATTEMPT_SHOT_ID_RE = re.compile(r'^(v\d{2}\.c\d{2}\.s\d{2})@([A-Za-z0-9_.:-]+)$')
_RUN_ID_SEGMENT_RE = re.compile(r'^[A-Za-z0-9_.:-]+$')

# v01.c02
_LAYER_KEY_RE = re.compile(r'^(v\d{2})\.(c\d{2})$')


def generate(layer_key: str, shot_index: int) -> str:
    """从 layer_key + shot_index 生成复合 shot_id。

    Args:
        layer_key: 卷.章格式，如 "v01.c02"
        shot_index: 节序号，从 1 开始

    Returns:
        复合 shot_id，如 "v01.c02.s03"

    Raises:
        ValueError: layer_key 格式不正确

    Examples:
        >>> generate("v01.c02", 3)
        'v01.c02.s03'
        >>> generate("v01.c01", 1)
        'v01.c01.s01'
    """
    if not _LAYER_KEY_RE.match(layer_key):
        raise ValueError(f"Invalid layer_key format: {layer_key!r}, expected 'vNN.cNN'")
    if shot_index < 1:
        raise ValueError(f"shot_index must be >= 1, got {shot_index}")
    return f"{layer_key}.s{shot_index:02d}"


def generate_attempt(layer_key: str, shot_index: int, run_id: str) -> str:
    """Generate a run-attempt-specific shot_id.

    The logical identity remains ``v01.c02.s03``. The primary key used by
    production runs includes run_id so a chapter rewrite creates fresh rows
    instead of reusing the previous run's shot records.
    """
    logical_id = generate(layer_key, shot_index)
    if not run_id or not _RUN_ID_SEGMENT_RE.match(run_id):
        raise ValueError(f"Invalid run_id for attempt shot_id: {run_id!r}")
    return f"{logical_id}@{run_id}"


def logical_id(shot_id: str) -> str:
    """Return the stable logical shot id for either logical or attempt ids."""
    if _SHOT_ID_RE.match(shot_id):
        return shot_id
    m = _ATTEMPT_SHOT_ID_RE.match(shot_id)
    if m:
        return m.group(1)
    raise ValueError(f"Invalid shot_id format: {shot_id!r}")


def parse(shot_id: str) -> ShotIdParts:
    """解析复合 shot_id。

    Args:
        shot_id: 复合 shot_id，如 "v01.c02.s03"

    Returns:
        ShotIdParts(volume, chapter, section, layer_key)

    Raises:
        ValueError: shot_id 格式不正确

    Examples:
        >>> parse("v01.c02.s03")
        ShotIdParts(volume='v01', chapter='c02', section='s03', layer_key='v01.c02')
    """
    shot_id = logical_id(shot_id)
    m = _SHOT_ID_RE.match(shot_id)
    if not m:
        raise ValueError(f"Invalid shot_id format: {shot_id!r}, expected 'vNN.cNN.sNN'")
    volume, chapter, section = m.groups()
    return ShotIdParts(volume, chapter, section, f"{volume}.{chapter}")


def is_valid(shot_id: str) -> bool:
    """检查是否为有效的复合 shot_id。

    Examples:
        >>> is_valid("v01.c02.s03")
        True
        >>> is_valid("v01.c02")
        False
        >>> is_valid("01KVJ1QVDRDGFX9J73459RE11H")  # legacy ULID
        False
    """
    return bool(_SHOT_ID_RE.match(shot_id) or _ATTEMPT_SHOT_ID_RE.match(shot_id))


def is_legacy_ulid(shot_id: str) -> bool:
    """检查是否为旧版 ULID 格式 (26字符)。

    用于数据迁移时识别旧格式。

    Examples:
        >>> is_legacy_ulid("01KVJ1QVDRDGFX9J73459RE11H")
        True
        >>> is_legacy_ulid("v01.c02.s03")
        False
    """
    return len(shot_id) == 26 and shot_id.isalnum()


def to_layer_key(shot_id: str) -> str:
    """从 shot_id 提取 layer_key。

    Examples:
        >>> to_layer_key("v01.c02.s03")
        'v01.c02'
    """
    return parse(shot_id).layer_key


def sort_key(shot_id: str) -> tuple[int, int, int]:
    """返回可排序的 (volume, chapter, section) 元组。

    Examples:
        >>> sort_key("v01.c02.s03")
        (1, 2, 3)
    """
    parts = parse(shot_id)
    return (
        int(parts.volume[1:]),
        int(parts.chapter[1:]),
        int(parts.section[1:]),
    )


def format_display(shot_id: str) -> str:
    """返回人类可读的显示格式。

    Examples:
        >>> format_display("v01.c02.s03")
        '第1卷 第2章 第3节'
    """
    parts = parse(shot_id)
    return f"第{int(parts.volume[1:])}卷 第{int(parts.chapter[1:])}章 第{int(parts.section[1:])}节"
