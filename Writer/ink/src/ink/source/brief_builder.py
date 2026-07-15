"""章纲 → 产稿 brief 文本构造器。

把 `outline_parser` 解析出的 `ChapterOutline`（白灯 `24_分章大纲.md` 的章节卡片）
拼成 `RealGenerationPort` 产稿用的 `chapter_brief`——一段自然语言，包含
标题、场景、冲突、必须落地的关键点与字数约束，格式对齐
`tests/test_generation_round_real_models.py` 的 `CHAPTER_BRIEF`。

死线收口用：不落 chapter contract payload / scene contract 四层 clause，
只产 brief 文本喂给真实模型。章纲作者定稿，brief 即契约。
"""
from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from ink.source.outline_parser import ChapterOutline, get_chapter

if TYPE_CHECKING:  # 避免运行时循环 import，仅作类型注解
    import sqlite3

# 产稿字数约束，对齐 RealGenerationPort._generation_prompt 的 "1200-1800 字"。
_WORD_CONSTRAINT = "1200-1800 字"

# 跨章 context：前章封版正文头/尾各取 N 字拼接，让模型续接前章人设与伏笔。
# 作者 2026-07-15 裁定形式：头+末各 300 字（零额外 LLM 调用，token 可控）。
_PREV_CONTEXT_HEAD = 300
_PREV_CONTEXT_TAIL = 300


def _prev_chapter_context(
    conn: "sqlite3.Connection | None",
    project_id: int | None,
    chapter_num: int,
) -> str | None:
    """取第 chapter_num-1 章封版正文的头+末各 300 字，拼成 context 段。

    第 1 章（或序章 chapter_num<=1）无前章 → None。
    conn/project_id 未传（向后兼容）→ None。
    前章未封版（read_active_chapter_text 无记录 raise DataIntegrityError）→ None，
    不阻断产稿（graceful skip，caller 只拿纯章纲 brief）。
    """
    if chapter_num <= 1 or conn is None or project_id is None:
        return None
    # 延迟 import：brief_builder 被 cli 早期加载，避免顶层循环依赖。
    from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
    from ink.errors import DataIntegrityError

    repo = ChapterSnapshotRepository(conn)
    try:
        prev_text = repo.read_active_chapter_text(
            project_id=project_id, chapter_id=chapter_num - 1
        )
    except DataIntegrityError:
        return None
    if not prev_text:
        return None
    if len(prev_text) <= _PREV_CONTEXT_HEAD + _PREV_CONTEXT_TAIL:
        excerpt = prev_text
    else:
        excerpt = (
            prev_text[:_PREV_CONTEXT_HEAD]
            + "\n……（中段略）……\n"
            + prev_text[-_PREV_CONTEXT_TAIL:]
        )
    return "前章正文摘要（续接人设与伏笔）：\n" + excerpt


def build_chapter_brief(
    outline_path: str | Path,
    chapter_num: int,
    *,
    conn: "sqlite3.Connection | None" = None,
    project_id: int | None = None,
) -> str | None:
    """从大纲文件取第 N 章，拼成产稿 brief 文本。

    找不到该章返回 None（caller 决定报错或跳过）。
    若传 conn+project_id 且 chapter_num>1，把第 N-1 章封版正文头+末各 300 字
    拼成 context 段插入 brief（字数约束句之前），使模型续接前章人设/伏笔。
    前章未封版或缺参则 graceful skip（不注入、不报错）。
    """
    text = Path(outline_path).read_text(encoding="utf-8")
    outline = get_chapter(text, chapter_num)
    if outline is None:
        return None
    brief = build_brief_from_outline(outline)
    ctx = _prev_chapter_context(conn, project_id, chapter_num)
    if ctx:
        # 字数约束句在 brief 末尾；把 context 插到它前面，字数约束保持最末。
        tail = _WORD_CONSTRAINT + "。"
        if brief.endswith(tail):
            brief = brief[: -len(tail)] + ctx + "\n" + tail
        else:  # 兜底：未以字数约束结尾则直接追加
            brief = brief + "\n" + ctx
    return brief


def build_brief_from_outline(outline: ChapterOutline) -> str:
    """把 ChapterOutline 拼成产稿 brief 自然语言段落。"""
    g = outline.get
    parts: list[str] = [f"第{outline.chapter_num}章《{outline.title}》。"]

    scene = g("场景")
    if scene:
        parts.append(scene + "。")

    conflict = g("冲突")
    if conflict:
        parts.append("本章冲突：" + conflict + "。")

    # 必须落地的关键点：物理因果锚点 + 沉默点 + 章末钩子（有则各一条）。
    must_land: list[str] = []
    anchor = g("物理因果锚点")
    if anchor:
        must_land.append("物理因果：" + anchor)
    silence = g("沉默点")
    if silence:
        must_land.append("沉默点：" + silence)
    hook = g("章末钩子")
    if hook:
        must_land.append("章末钩子：" + hook)
    engine = g("主引擎")
    if engine:
        must_land.append("主引擎：" + engine)
    if must_land:
        parts.append("本章须落地：" + "；".join(must_land) + "。")

    parts.append(_WORD_CONSTRAINT + "。")
    return "".join(parts)
