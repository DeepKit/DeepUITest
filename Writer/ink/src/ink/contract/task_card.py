from __future__ import annotations

import sqlite3

from ink.contract.generated.dtos import BookContextDTO, ChapterContractDTO, TaskCardDTO
from ink.contract.loader import load_book_context, load_chapter_contract, load_shot_contract
from ink.core.chapter_continuity import load_continuity_context, render_continuity_section
from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


COMPLETE_TAIL_CHARS = set("。！？.!?」”'")


class TaskCardCompiler:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def compile_for_shot(self, shot_id: str, run_id: int) -> TaskCardDTO:
        contract = load_shot_contract(self.conn, shot_id, run_id)
        shot_contract_id, project_id = _lookup_shot_contract_id(self.conn, shot_id, run_id)
        book_context = load_book_context(self.conn, project_id)
        # chapter 层悬疑契约（scope_id 由 shot_id 前缀解析：ch-01-shot-001 → ch-1）
        chapter_scope_id = _derive_chapter_scope_id(shot_id)
        chapter_contract = load_chapter_contract(self.conn, project_id, chapter_scope_id)
        continuity_section = render_continuity_section(
            load_continuity_context(self.conn, shot_id, run_id)
        )
        instructions = _render_task_card(
            contract.must_land,
            contract.anti_write,
            contract.persona_assignment,
            book_context,
            chapter_contract,
            continuity_section,
        )
        task_card_id = self.write_task_card(shot_contract_id, instructions)
        return load_latest_task_card(self.conn, shot_contract_id, task_card_id=task_card_id)

    def write_task_card(self, shot_contract_id: int, compiled_instructions: str) -> int:
        if not _has_complete_tail(compiled_instructions):
            raise DataIntegrityError("task card instructions end with an incomplete tail")

        now = now_utc_iso()
        self.conn.execute(
            """
            UPDATE writing_shot_task_cards
            SET superseded_at = ?
            WHERE shot_contract_id = ? AND superseded_at IS NULL
            """,
            (now, shot_contract_id),
        )
        cursor = self.conn.execute(
            """
            INSERT INTO writing_shot_task_cards
                (shot_contract_id, compiled_instructions, created_at)
            VALUES (?, ?, ?)
            """,
            (shot_contract_id, compiled_instructions, now),
        )
        return int(cursor.lastrowid)


def load_latest_task_card(
    conn: sqlite3.Connection,
    shot_contract_id: int,
    *,
    task_card_id: int | None = None,
) -> TaskCardDTO:
    if task_card_id is None:
        row = conn.execute(
            """
            SELECT task_card_id, shot_contract_id, compiled_instructions, superseded_at
            FROM writing_shot_task_cards
            WHERE shot_contract_id = ? AND superseded_at IS NULL
            ORDER BY task_card_id DESC
            LIMIT 1
            """,
            (shot_contract_id,),
        ).fetchone()
    else:
        row = conn.execute(
            """
            SELECT task_card_id, shot_contract_id, compiled_instructions, superseded_at
            FROM writing_shot_task_cards
            WHERE shot_contract_id = ? AND task_card_id = ?
            """,
            (shot_contract_id, task_card_id),
        ).fetchone()
    if row is None:
        raise DataIntegrityError(f"task card not found for shot_contract_id={shot_contract_id}")
    return TaskCardDTO(
        task_card_id=int(row[0]),
        shot_contract_id=int(row[1]),
        compiled_instructions=str(row[2]),
        superseded_at=None if row[3] is None else str(row[3]),
    )


def _has_complete_tail(text: str) -> bool:
    stripped = text.strip()
    return bool(stripped) and stripped[-1] in COMPLETE_TAIL_CHARS


def _lookup_shot_contract_id(conn: sqlite3.Connection, shot_id: str, run_id: int) -> tuple[int, int]:
    """返回 (shot_contract_id, project_id)。project_id 用于加载 book 层上下文。"""
    row = conn.execute(
        "SELECT shot_contract_id, project_id FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    if row is None or row[0] is None:
        raise DataIntegrityError(f"shot contract not found: {shot_id}/{run_id}")
    return int(row[0]), int(row[1])


def _render_task_card(
    must_land: dict[str, object],
    anti_write: dict[str, object],
    persona_assignment: dict[str, object],
    book_context: BookContextDTO | None = None,
    chapter_suspense: ChapterContractDTO | None = None,
    continuity_section: str = "",
) -> str:
    events = _join_items(must_land.get("events"))
    beats = _join_items(must_land.get("beats"))
    releases = _join_items(must_land.get("information_releases"))
    forbidden_facts = _join_items(anti_write.get("forbidden_facts"))
    forbidden_words = _join_items(anti_write.get("forbidden_words"))
    pov_only = _join_items(anti_write.get("pov_only"))
    persona = str(persona_assignment.get("persona", ""))
    intensity = persona_assignment.get("intensity", {})
    book_section = _render_book_section(book_context)
    suspense_section = _render_chapter_suspense(chapter_suspense)
    return (
        f"Persona: {persona}\n"
        f"Intensity: {intensity}\n"
        f"Must land events: {events}\n"
        f"Beats: {beats}\n"
        f"Information releases: {releases}\n"
        f"Forbidden facts: {forbidden_facts}\n"
        f"Forbidden words: {forbidden_words}\n"
        f"POV only: {pov_only}\n"
        f"{continuity_section}"
        f"{book_section}"
        f"{suspense_section}"
        "请按以上约束完成本 shot。"
    )


def _derive_chapter_scope_id(shot_id: str) -> str:
    """shot_id（ch-01-shot-001）→ chapter scope_id（ch-1）。

    shot_id 约定为 ``ch-<NN>-shot-<NNN>``；取前两段并把章号去前导零。
    无法解析时原样返回（loader 查不到会优雅降级返回 None）。
    """
    parts = str(shot_id).split("-")
    if len(parts) >= 2 and parts[0] == "ch":
        try:
            ch_num = int(parts[1])
            return f"ch-{ch_num}"
        except ValueError:
            pass
    return str(shot_id)


def _render_chapter_suspense(chapter: ChapterContractDTO | None) -> str:
    """渲染章节悬疑工程学 6 行约束。无 chapter contract 或全空时整段省略（不阻断编译）。"""
    if chapter is None:
        return ""
    lines: list[str] = []
    if chapter.pursuit_type:
        lines.append(f"追读类型: {chapter.pursuit_type}")
    if chapter.main_engine:
        lines.append(f"主引擎: {chapter.main_engine}")
    if chapter.silence_point:
        lines.append(f"沉默点: {chapter.silence_point}（角色知道但读者/对方不知道）")
    if chapter.causal_anchor:
        lines.append(f"物理因果锚点: {chapter.causal_anchor}（读者须能复盘的后果链）")
    if chapter.light_state:
        lines.append(f"灯态: {chapter.light_state}")
    if chapter.chapter_end_hook:
        lines.append(f"章末钩子: {chapter.chapter_end_hook}")
    if not lines:
        return ""
    return "【章节悬疑约束】\n" + "\n".join(lines) + "\n\n"


def _render_book_section(book_context: BookContextDTO | None) -> str:
    """渲染 book 层 World/Character/Narrative/Motif 四段。无 confirmed 数据时整段省略（不阻断编译）。"""
    if book_context is None:
        return ""
    parts: list[str] = []
    for label, items in (
        ("World", book_context.world),
        ("Character", book_context.character),
        ("Narrative", book_context.narrative),
        ("Motif", book_context.motif),
    ):
        if not items:
            continue
        joined = "；".join(items)
        parts.append(f"{label}: {joined}\n")
    return "".join(parts)


def _join_items(value: object) -> str:
    if isinstance(value, list):
        return "；".join(str(item) for item in value)
    return "" if value is None else str(value)
