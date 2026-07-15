"""brief_builder 跨章 context 注入单元测试。

覆盖：
- 第1章/序章不注入 context（无前章）。
- 前章封版正文 >600 字时取头300+末300拼接，字数约束保持最末。
- 前章未封版（read_active_chapter_text raise DataIntegrityError）→ graceful skip。
- 不传 conn（向后兼容）→ 不注入、不报错。
"""
from __future__ import annotations

import sqlite3
from pathlib import Path
from unittest.mock import patch

import pytest

from ink.errors import DataIntegrityError
from ink.source import brief_builder as bb
from ink.source.outline_parser import ChapterOutline

OUTLINE = """\
### 第1章 硫化
场景：硫化车间。
冲突：返潮的密封件要不要装车。
物理因果锚点：硫化返潮。
章末钩子：吕素琴翻开记录本。
主引擎：预埋种植。

### 第2章 装车
场景：装车台。
冲突：第1章已看见的1978封存样件要不要复检。
物理因果锚点：油纸包。
章末钩子：许怀山沉默。
主引擎：预埋种植。
"""


@pytest.fixture()
def outline_file(tmp_path: Path) -> Path:
    p = tmp_path / "outline.md"
    p.write_text(OUTLINE, encoding="utf-8")
    return p


def _long_prev_text(n: int = 1000) -> str:
    """造一段 n 字正文，头尾可辨识。"""
    head = "头" * 300
    mid = "中" * (n - 600)
    tail = "尾" * 300
    return head + mid + tail


def test_chapter1_no_context(outline_file: Path) -> None:
    """第1章即使传 conn+project_id 也不注入（无前章）。"""
    conn = sqlite3.connect(":memory:")
    brief = bb.build_chapter_brief(str(outline_file), 1, conn=conn, project_id=1)
    assert brief is not None
    assert "前章正文摘要" not in brief
    assert brief.endswith(bb._WORD_CONSTRAINT + "。")


def test_prev_context_head_tail_300(outline_file: Path) -> None:
    """前章封版正文 >600 字时取头300+末300，字数约束保持最末。"""
    prev_text = _long_prev_text(1000)
    with patch(
        "ink.core.chapter_snapshot_repository.ChapterSnapshotRepository.read_active_chapter_text",
        return_value=prev_text,
    ):
        brief = bb.build_chapter_brief(
            str(outline_file), 2, conn=sqlite3.connect(":memory:"), project_id=1
        )
    assert brief is not None
    assert "前章正文摘要" in brief
    # 头300字 + 中段略标记 + 末300字都在
    assert "头" * 300 in brief
    assert "（中段略）" in brief
    assert "尾" * 300 in brief
    # 中段被省略
    assert "中" * 100 not in brief
    # 字数约束仍最末
    assert brief.endswith(bb._WORD_CONSTRAINT + "。")


def test_prev_context_short_text_uses_all(outline_file: Path) -> None:
    """前章正文 ≤600 字时整段返回（不分头尾）。"""
    short_text = "短正文仅百字。" * 10  # ~80字
    with patch(
        "ink.core.chapter_snapshot_repository.ChapterSnapshotRepository.read_active_chapter_text",
        return_value=short_text,
    ):
        brief = bb.build_chapter_brief(
            str(outline_file), 2, conn=sqlite3.connect(":memory:"), project_id=1
        )
    assert brief is not None
    assert "前章正文摘要" in brief
    assert "（中段略）" not in brief
    assert short_text in brief


def test_prev_chapter_not_sealed_skips(outline_file: Path) -> None:
    """前章未封版（raise DataIntegrityError）→ graceful skip，不注入不报错。"""
    with patch(
        "ink.core.chapter_snapshot_repository.ChapterSnapshotRepository.read_active_chapter_text",
        side_effect=DataIntegrityError("no active snapshot"),
    ):
        brief = bb.build_chapter_brief(
            str(outline_file), 2, conn=sqlite3.connect(":memory:"), project_id=1
        )
    assert brief is not None
    assert "前章正文摘要" not in brief
    assert brief.endswith(bb._WORD_CONSTRAINT + "。")


def test_backward_compat_no_conn(outline_file: Path) -> None:
    """不传 conn（旧调用方）→ 返回纯章纲 brief，不注入不报错。"""
    brief = bb.build_chapter_brief(str(outline_file), 2)
    assert brief is not None
    assert "前章正文摘要" not in brief
    assert brief.endswith(bb._WORD_CONSTRAINT + "。")
