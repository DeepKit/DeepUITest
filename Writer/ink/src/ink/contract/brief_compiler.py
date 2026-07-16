"""Scene Contract → 产稿 brief 文本编译器（契约唯一真相源）。

从 `writing_scene_contract_clauses` 四层 clause 编译出产稿用的 brief 自然语言
段落。brief 是**契约的产物**，不是大纲/正文拼出来的——这是 SPW 防绕过 H1 唯一
受控入口：产稿只能拿到 `scene_contract_id`，内部从此处读契约编译，不给裸 brief
入参留路径。

四层（docs/design.md §3.1）：
- hard_constraint：事实/状态/知情边界/必要因果/红线（失败级）
- source_dna：原稿创作机制（评估传递质量）
- soft_goal：场景功能/人物关系变化/情绪信息策略（允许优秀偏离）
- creative_opening：留给正文发现的空间（不得预先锁死）

编译规则：每层按 authority_rank 降序、同 rank 按 clause_key 升序，逐条拼入 brief。
"""
from __future__ import annotations

import sqlite3
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    pass

# 跨章 context：前章封版正文头/尾各取 N 字拼接，让模型续接前章人设与伏笔。
# 作者 2026-07-15 裁定形式：头+末各 300 字（零额外 LLM 调用，token 可控）。
_PREV_CONTEXT_HEAD = 300
_PREV_CONTEXT_TAIL = 300

# 四层编译文案模板：(层中文名, 是否标层名, 前缀)
_LAYER_LABEL = {
    "hard_constraint": ("硬约束", "本章不可违背："),
    "source_dna": ("源稿DNA", "传承机制："),
    "soft_goal": ("软目标", "本章目标："),
    "creative_opening": ("创作留白", "可发挥处："),
}
_LAYER_ORDER = ("hard_constraint", "source_dna", "soft_goal", "creative_opening")


def compile_brief(
    conn: sqlite3.Connection,
    scene_contract_id: int,
    *,
    inject_prev_context: bool = True,
) -> str:
    """从四层 clause 编译产稿 brief。

    Args:
        conn: 库连接。
        scene_contract_id: 契约主键——唯一受控入参，不接受裸 brief 文本。
        inject_prev_context: 是否注入前章封版正文头尾各 300 字作跨章 context。
            第 1 章无前章时 graceful skip（不注入不报错）。

    Returns:
        编译后的 brief 自然语言段落。

    Raises:
        ValueError: 契约不存在或非 active/approved 态、四层不全——契约缺失必崩，
            不得降级继续（SPW 防绕过 H1 + H3 反事实第 1 条）。
    """
    # 契约存在性 + 状态校验：非生效契约不得编译 brief。
    row = conn.execute(
        "SELECT status FROM writing_scene_contracts WHERE scene_contract_id = ?",
        (scene_contract_id,),
    ).fetchone()
    if row is None:
        raise ValueError(f"contract not found: {scene_contract_id}")
    if str(row[0]) not in {"approved", "active"}:
        raise ValueError(
            f"contract {scene_contract_id} status={row[0]}: only approved/active "
            f"contracts may be compiled to brief"
        )

    clauses = conn.execute(
        """
        SELECT layer, clause_key, clause_text, severity, authority_rank
        FROM writing_scene_contract_clauses
        WHERE scene_contract_id = ?
        ORDER BY
            CASE layer
                WHEN 'hard_constraint' THEN 0
                WHEN 'source_dna' THEN 1
                WHEN 'soft_goal' THEN 2
                WHEN 'creative_opening' THEN 3
            END,
            authority_rank DESC, clause_key ASC
        """,
        (scene_contract_id,),
    ).fetchall()

    # 四层齐全校验（H2 DB 触发器已焊，此处为应用层防御 + 清晰报错）。
    seen_layers = {r[0] for r in clauses}
    missing = [ly for ly in _LAYER_ORDER if ly not in seen_layers]
    if missing:
        raise ValueError(
            f"contract {scene_contract_id} missing layers {missing}: "
            f"four-layer contract incomplete, refusing to compile brief"
        )

    parts: list[str] = []
    current_layer: str | None = None
    layer_prefix = ""
    for layer, clause_key, clause_text, severity, _rank in clauses:
        if layer != current_layer:
            label, layer_prefix = _LAYER_LABEL[layer]
            parts.append(f"【{label}】")
            current_layer = layer
        # 严重度只在硬约束层标注（soft/diagnostic 不污染 brief 可读性）。
        sev_tag = f"[{severity}]" if layer == "hard_constraint" and severity != "hard" else ""
        parts.append(f"{layer_prefix}{clause_key}：{clause_text}{sev_tag}。")
        # 同层后续条款不再重复前缀。
        layer_prefix = ""

    parts.append("1200-1800 字。")
    brief = "".join(parts)

    # 跨章 context：第 N 章自动取第 N-1 章封版正文头尾各 300 字续接人设/伏笔。
    # 字数约束句须保持最末，故 context 插到它前面。第 1 章/前章未封版 → skip。
    if inject_prev_context:
        ctx = _prev_chapter_context(conn, scene_contract_id)
        if ctx:
            word_constraint = "1200-1800 字。"
            if brief.endswith(word_constraint):
                brief = brief[: -len(word_constraint)] + ctx + word_constraint
            else:
                brief = brief + ctx
    return brief


def _prev_chapter_context(conn: sqlite3.Connection, scene_contract_id: int) -> str | None:
    """取本契约对应章节的前一章封版正文头尾各 300 字，拼成 context 段。

    从契约→scene→chapter_id 解析当前章号；第 1 章或前章未封版 → None（不阻断产稿）。
    """
    row = conn.execute(
        """
        SELECT s.chapter_id FROM writing_scene_contracts c
        JOIN writing_scenes s ON s.scene_id = c.scene_id
        WHERE c.scene_contract_id = ?
        """,
        (scene_contract_id,),
    ).fetchone()
    if row is None:
        return None
    chapter_num = int(row[0])
    if chapter_num <= 1:
        return None
    project_row = conn.execute(
        """SELECT s.project_id FROM writing_scene_contracts c
           JOIN writing_scenes s ON s.scene_id = c.scene_id
           WHERE c.scene_contract_id = ?""",
        (scene_contract_id,),
    ).fetchone()
    if project_row is None:
        return None
    project_id = int(project_row[0])
    try:
        from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
        from ink.errors import DataIntegrityError

        repo = ChapterSnapshotRepository(conn)
        prev_text = repo.read_active_chapter_text(
            project_id=project_id, chapter_id=chapter_num - 1
        )
    except DataIntegrityError:
        return None
    except Exception:
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
