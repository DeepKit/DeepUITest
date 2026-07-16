from __future__ import annotations

import sqlite3
from dataclasses import dataclass

from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError


@dataclass(frozen=True)
class ContinuityContext:
    """The nearest usable prose state that the current shot must continue from."""

    source_kind: str
    source_shot_id: str
    source_chapter_id: int
    tail_text: str

    @property
    def is_empty(self) -> bool:
        return not self.tail_text.strip()


def load_continuity_context(
    conn: sqlite3.Connection,
    shot_id: str,
    run_id: int,
    *,
    max_chars: int = 1200,
) -> ContinuityContext | None:
    """Load the nearest previous shot/chapter ending through ``TextRepository``.

    Priority is:

    1. the preceding shot in the same chapter and run;
    2. the last available shot in the nearest previous chapter.

    The function deliberately accepts soft-sealed prose as continuity input.  During
    sequential production the next shot/chapter must be able to continue from the
    latest reviewed production state before a human hard-seals the whole chapter.
    """
    current = conn.execute(
        """
        SELECT project_id, chapter_id
        FROM writing_shots
        WHERE shot_id = ? AND run_id = ?
        """,
        (shot_id, run_id),
    ).fetchone()
    if current is None:
        raise DataIntegrityError(f"shot not found for continuity context: {shot_id}/{run_id}")
    project_id, chapter_id = int(current[0]), int(current[1])

    same_chapter = conn.execute(
        """
        SELECT s.shot_id, s.chapter_id
        FROM writing_shots s
        WHERE s.project_id = ? AND s.chapter_id = ? AND s.run_id = ?
          AND s.shot_id < ?
          AND EXISTS (
              SELECT 1 FROM writing_shot_revisions r WHERE r.shot_id = s.shot_id
          )
        ORDER BY s.shot_id DESC
        LIMIT 1
        """,
        (project_id, chapter_id, run_id, shot_id),
    ).fetchone()
    if same_chapter is not None:
        return _build_context(
            conn,
            source_kind="previous_shot",
            source_shot_id=str(same_chapter[0]),
            source_chapter_id=int(same_chapter[1]),
            run_id=run_id,
            max_chars=max_chars,
        )

    previous_chapter = conn.execute(
        """
        SELECT s.shot_id, s.chapter_id, s.run_id
        FROM writing_shots s
        WHERE s.project_id = ? AND s.chapter_id < ?
          AND EXISTS (
              SELECT 1 FROM writing_shot_revisions r WHERE r.shot_id = s.shot_id
          )
        ORDER BY s.chapter_id DESC,
                 CASE s.status WHEN 'hard_sealed' THEN 2 WHEN 'soft_sealed' THEN 1 ELSE 0 END DESC,
                 s.shot_id DESC,
                 s.run_id DESC
        LIMIT 1
        """,
        (project_id, chapter_id),
    ).fetchone()
    if previous_chapter is None:
        return None
    return _build_context(
        conn,
        source_kind="previous_chapter",
        source_shot_id=str(previous_chapter[0]),
        source_chapter_id=int(previous_chapter[1]),
        run_id=int(previous_chapter[2]),
        max_chars=max_chars,
    )


def load_previous_chapter_tail(
    conn: sqlite3.Connection,
    project_id: int,
    chapter_id: int,
    *,
    max_chars: int = 1600,
) -> str:
    """Load the nearest previous chapter's final prose for chapter-level review."""
    row = conn.execute(
        """
        SELECT s.shot_id, s.run_id
        FROM writing_shots s
        WHERE s.project_id = ? AND s.chapter_id < ?
          AND EXISTS (
              SELECT 1 FROM writing_shot_revisions r WHERE r.shot_id = s.shot_id
          )
        ORDER BY s.chapter_id DESC,
                 CASE s.status WHEN 'hard_sealed' THEN 2 WHEN 'soft_sealed' THEN 1 ELSE 0 END DESC,
                 s.shot_id DESC,
                 s.run_id DESC
        LIMIT 1
        """,
        (project_id, chapter_id),
    ).fetchone()
    if row is None:
        return ""
    text = TextRepository(conn).read_current_text(str(row[0]), int(row[1]))
    return _tail(text, max_chars)


def render_continuity_section(context: ContinuityContext | None) -> str:
    if context is None or context.is_empty:
        return (
            "【连续性硬约束】\n"
            "这是当前可用正文中的起始场景；不得伪造“上一段已经发生”的事件。\n\n"
        )
    source_label = "同章上一 shot" if context.source_kind == "previous_shot" else "上一章末尾"
    return (
        "【连续性硬约束】\n"
        f"承接来源: {source_label}（chapter={context.source_chapter_id}, "
        f"shot={context.source_shot_id}）\n"
        f"上一状态原文末尾:\n{context.tail_text}\n"
        "续写要求:\n"
        "1. 开头必须明确承接上述人物位置、时间、未完成动作或悬念，不得无解释跳时空。\n"
        "2. 若确需切换时间、地点或 POV，必须先写出读者可识别的转场锚点；禁止在末段偷换 POV。\n"
        "3. 不得重演上一状态已经完成的动作，不得让已消失/离场人物无说明重新出现。\n\n"
    )


def _build_context(
    conn: sqlite3.Connection,
    *,
    source_kind: str,
    source_shot_id: str,
    source_chapter_id: int,
    run_id: int,
    max_chars: int,
) -> ContinuityContext:
    text = TextRepository(conn).read_current_text(source_shot_id, run_id)
    return ContinuityContext(
        source_kind=source_kind,
        source_shot_id=source_shot_id,
        source_chapter_id=source_chapter_id,
        tail_text=_tail(text, max_chars),
    )


def _tail(text: str, max_chars: int) -> str:
    cleaned = text.strip()
    if len(cleaned) <= max_chars:
        return cleaned
    return "…[前文截断]\n" + cleaned[-max_chars:]
