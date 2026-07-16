"""compile_brief 跨章 context 注入单元测试（BFX-079 契约层接线）。

覆盖 _prev_chapter_context 不变量（原 brief_builder 迁移而来）：
- 第1章/序章不注入 context（无前章）。
- 前章封版正文 >600 字时取头300+末300拼接，字数约束保持最末。
- 前章正文 ≤600 字时整段返回（不分头尾）。
- 前章未封版（read_active_chapter_text raise DataIntegrityError）→ graceful skip。
- inject_prev_context=False 强制不注入。

契约层不变量（compile_brief 自身）：
- 非 approved/active 契约不得编译 brief（防绕过 H1）。
- 四层不全必崩（H3 反事实第 1 条）。
"""
from __future__ import annotations

import os
import sqlite3
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

from ink.contract.brief_compiler import compile_brief
from ink.core.scene_repository import SceneRepository
from ink.errors import DataIntegrityError

_SCHEMA = (Path(__file__).resolve().parents[1] / "sql" / "schema.sql").read_text(
    encoding="utf-8"
)


def _new_db() -> sqlite3.Connection:
    db = tempfile.mktemp(suffix=".db")
    conn = sqlite3.connect(db)
    conn.executescript(_SCHEMA)
    conn.execute(
        'INSERT INTO writing_projects(project_id,code,title,writer_model_pool,'
        'jury_model_pool,created_at) VALUES(1,"T","t",\'["a","b","c"]\','
        '\'["a","b","c"]\',"2026-01-01T00:00:00Z")'
    )
    conn.commit()
    return conn


def _seed_contract(conn: sqlite3.Connection, *, chapter_id: int, created_by: str = "a:deepseek") -> int:
    """落一个四层齐全的 draft 契约并置 approved（跳审查，仅测编译）。"""
    repo = SceneRepository(conn)
    sid = repo.create_scene(
        project_id=1, chapter_id=chapter_id,
        logical_scene_key=f"ch{chapter_id}", scene_order=chapter_id,
    )
    cid = repo.create_contract(
        scene_id=sid, version=1, contract_hash="h", source_bundle_hash="h",
        created_by=created_by, status="draft",
    )
    repo.assemble_four_layer_contract(
        scene_contract_id=cid,
        hard_constraints=[{"clause_key": "pa", "clause_text": "窗外雨停月出", "severity": "hard", "authority_rank": 10}],
        source_dna=[{"clause_key": "e", "clause_text": "谜题推进", "severity": "diagnostic", "authority_rank": 5}],
        soft_goals=[{"clause_key": "c", "clause_text": "撞破秘密", "severity": "soft", "authority_rank": 6}],
        creative_openings=[
            {"clause_key": "h", "clause_text": "门被推开", "severity": "soft", "authority_rank": 3},
            {"clause_key": "so", "clause_text": "书房夜可发挥", "severity": "soft", "authority_rank": 2},
        ],
    )
    conn.execute(
        "UPDATE writing_scene_contracts SET status='approved' WHERE scene_contract_id=?",
        (cid,),
    )
    conn.commit()
    return cid


def _long_prev_text(n: int = 1000) -> str:
    head = "头" * 300
    mid = "中" * (n - 600)
    tail = "尾" * 300
    return head + mid + tail


def test_chapter1_no_context() -> None:
    """第1章无前章 → 不注入 context，字数约束在末尾。"""
    conn = _new_db()
    cid = _seed_contract(conn, chapter_id=1)
    brief = compile_brief(conn, cid)
    assert "前章正文摘要" not in brief
    assert brief.endswith("1200-1800 字。")


def test_prev_context_head_tail_300() -> None:
    """前章封版正文 >600 字时取头300+末300，字数约束保持最末。"""
    conn = _new_db()
    cid = _seed_contract(conn, chapter_id=2)
    with patch(
        "ink.core.chapter_snapshot_repository.ChapterSnapshotRepository.read_active_chapter_text",
        return_value=_long_prev_text(1000),
    ):
        brief = compile_brief(conn, cid)
    assert "前章正文摘要" in brief
    assert "头" * 300 in brief
    assert "（中段略）" in brief
    assert "尾" * 300 in brief
    assert "中" * 100 not in brief  # 中段被省略
    assert brief.endswith("1200-1800 字。")


def test_prev_context_short_text_uses_all() -> None:
    """前章正文 ≤600 字时整段返回（不分头尾）。"""
    conn = _new_db()
    cid = _seed_contract(conn, chapter_id=2)
    short_text = "短正文仅百字。" * 10
    with patch(
        "ink.core.chapter_snapshot_repository.ChapterSnapshotRepository.read_active_chapter_text",
        return_value=short_text,
    ):
        brief = compile_brief(conn, cid)
    assert "前章正文摘要" in brief
    assert "（中段略）" not in brief
    assert short_text in brief


def test_prev_chapter_not_sealed_skips() -> None:
    """前章未封版（raise DataIntegrityError）→ graceful skip，不注入不报错。"""
    conn = _new_db()
    cid = _seed_contract(conn, chapter_id=2)
    with patch(
        "ink.core.chapter_snapshot_repository.ChapterSnapshotRepository.read_active_chapter_text",
        side_effect=DataIntegrityError("no active snapshot"),
    ):
        brief = compile_brief(conn, cid)
    assert "前章正文摘要" not in brief
    assert brief.endswith("1200-1800 字。")


def test_inject_prev_context_false() -> None:
    """inject_prev_context=False 强制不注入（即使有前章可取）。"""
    conn = _new_db()
    cid = _seed_contract(conn, chapter_id=2)
    with patch(
        "ink.core.chapter_snapshot_repository.ChapterSnapshotRepository.read_active_chapter_text",
        return_value=_long_prev_text(1000),
    ):
        brief = compile_brief(conn, cid, inject_prev_context=False)
    assert "前章正文摘要" not in brief
    assert brief.endswith("1200-1800 字。")


def test_draft_contract_refused() -> None:
    """draft 契约（未审查未激活）不得编译 brief——防绕过 H1。"""
    conn = _new_db()
    repo = SceneRepository(conn)
    sid = repo.create_scene(project_id=1, chapter_id=1, logical_scene_key="ch1", scene_order=1)
    cid = repo.create_contract(
        scene_id=sid, version=1, contract_hash="h", source_bundle_hash="h",
        created_by="a:deepseek", status="draft",
    )
    repo.assemble_four_layer_contract(
        scene_contract_id=cid,
        hard_constraints=[{"clause_key": "pa", "clause_text": "x", "severity": "hard", "authority_rank": 10}],
        source_dna=[{"clause_key": "e", "clause_text": "x", "severity": "diagnostic", "authority_rank": 5}],
        soft_goals=[{"clause_key": "c", "clause_text": "x", "severity": "soft", "authority_rank": 6}],
        creative_openings=[
            {"clause_key": "h", "clause_text": "x", "severity": "soft", "authority_rank": 3},
            {"clause_key": "so", "clause_text": "x", "severity": "soft", "authority_rank": 2},
        ],
    )
    with pytest.raises(ValueError, match="only approved/active"):
        compile_brief(conn, cid)


def test_incomplete_four_layer_refused() -> None:
    """四层不全必崩——H3 反事实第 1 条。

    assemble_four_layer_contract 自己强制 opening>=2，所以四层残缺只能靠绕过
    assemble 直接写 clause 表模拟（防有人不走 repo 层）。compile_brief 是第二道
    防线：即使 clause 表被残缺写入，编译 brief 时也必须崩。
    """
    conn = _new_db()
    repo = SceneRepository(conn)
    sid = repo.create_scene(project_id=1, chapter_id=1, logical_scene_key="ch1", scene_order=1)
    cid = repo.create_contract(
        scene_id=sid, version=1, contract_hash="h", source_bundle_hash="h",
        created_by="a:deepseek", status="draft",
    )
    # 绕过 assemble，直接写残缺四层：只硬约束 + 源稿DNA，缺软目标/留白。
    conn.execute(
        "INSERT INTO writing_scene_contract_clauses"
        "(scene_contract_id, layer, clause_key, clause_text, severity, authority_rank, created_at) "
        "VALUES (?,?,?,?,?,?,?)",
        (cid, "hard_constraint", "pa", "x", "hard", 10, "2026-01-01T00:00:00Z"),
    )
    conn.execute(
        "INSERT INTO writing_scene_contract_clauses"
        "(scene_contract_id, layer, clause_key, clause_text, severity, authority_rank, created_at) "
        "VALUES (?,?,?,?,?,?,?)",
        (cid, "source_dna", "e", "x", "diagnostic", 5, "2026-01-01T00:00:00Z"),
    )
    conn.execute(
        "UPDATE writing_scene_contracts SET status='approved' WHERE scene_contract_id=?",
        (cid,),
    )
    conn.commit()
    with pytest.raises(ValueError, match="missing layers"):
        compile_brief(conn, cid)


def test_mutation_changing_clause_changes_brief() -> None:
    """改 clause 文本 → brief 必变（mutation test，证明 compile_brief 真读 clause）。

    H3 反事实：若 compile_brief 不读四层 clause（缓存/固定输出），改 clause 文本
    后 brief 不应变。此测试守住"契约成唯一真相源"——brief 内容由 clause 决定。
    """
    conn = _new_db()
    cid = _seed_contract(conn, chapter_id=1)
    brief_before = compile_brief(conn, cid, inject_prev_context=False)

    # 改一条硬约束 clause 文本
    conn.execute(
        "UPDATE writing_scene_contract_clauses SET clause_text=? "
        "WHERE scene_contract_id=? AND layer='hard_constraint'",
        ("窗外雨停月出_被改写", cid),
    )
    conn.commit()
    brief_after = compile_brief(conn, cid, inject_prev_context=False)

    assert brief_before != brief_after, "改 clause 文本后 brief 未变——compile_brief 未真读 clause"
    assert "被改写" in brief_after
    assert "被改写" not in brief_before


def test_mutation_changing_clause_text_only_not_hash() -> None:
    """只读 clause_text 字段输出，不误用 clause_hash/其他列——改 text 必变，改无关列不变。

    H3 反事实：确认 compile_brief 的输出来源是 clause_text（人读的部分），而非
    hash/authority_rank 等元数据列。改 authority_rank 不应改变 brief 文本。
    """
    conn = _new_db()
    cid = _seed_contract(conn, chapter_id=1)
    brief_before = compile_brief(conn, cid, inject_prev_context=False)

    # 改 authority_rank（元数据，不应进 brief 文本）
    conn.execute(
        "UPDATE writing_scene_contract_clauses SET authority_rank=authority_rank+1 "
        "WHERE scene_contract_id=?",
        (cid,),
    )
    conn.commit()
    brief_after = compile_brief(conn, cid, inject_prev_context=False)

    assert brief_before == brief_after, "改 authority_rank 不应改变 brief 文本——brief 只读 clause_text"
