"""book 层上下文注入测试（阶段 E）。

覆盖：
- load_book_context：四类分组、confirmed 过滤、meta+atomic 合并去重、空数据降级
- _render_task_card：World/Character/Narrative/Motif 段注入、空段省略、不阻断 complete-tail 校验
- 端到端：make_winner_selected_shot 注入 book 数据后 compiled_instructions 含 book 段
"""
from __future__ import annotations

import json

import pytest

from factories import NOW, make_schema_db
from ink.contract.generated.dtos import BookContextDTO
from ink.contract.loader import load_book_context
from ink.contract.task_card import _render_book_section, _render_task_card


def _ensure_project(conn, project_id: int = 1) -> None:
    """确保 project 行存在（meta/atomic 的外键依赖）。make_schema_db 只建表不插数据。"""
    exists = conn.execute("SELECT 1 FROM writing_projects WHERE project_id = ?", (project_id,)).fetchone()
    if exists is None:
        conn.execute(
            """
            INSERT INTO writing_projects
                (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
            VALUES (?, 'demo', 'Demo', '["writer-a","writer-b","writer-c"]',
                    '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
            """,
            (project_id, NOW),
        )
    # atomic 的 source_document_id 外键：建一行占位 source document。
    sd = conn.execute(
        "SELECT 1 FROM writing_source_documents WHERE source_document_id = 1"
    ).fetchone()
    if sd is None:
        conn.execute(
            """
            INSERT INTO writing_source_documents
                (source_document_id, project_id, source_path, source_kind, priority,
                 content_hash, status, created_at, updated_at)
            VALUES (1, ?, 'guide.md', 'guide', 100, 'hash-1', 'active', ?, ?)
            """,
            (project_id, NOW, NOW),
        )


def _insert_meta(conn, project_id: int, *, status: str = "confirmed", world=None, narrative=None, motif=None) -> None:
    _ensure_project(conn, project_id)
    conn.execute(
        """
        INSERT INTO writing_meta_contracts
            (project_id, identity, narrative_voice, hard_boundaries, style_locks,
             world_knowledge, motif_system, creative_zones, style_quality_profile, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            project_id,
            json.dumps({"project_identity": "demo"}),
            json.dumps(narrative or {"person": "third", "distance": "close"}),
            json.dumps({"forbidden": ["deus ex machina"]}),
            json.dumps({"must_keep": ["sparse prose"]}),
            json.dumps(world or {"facts": ["魔法源自月光"]}),
            json.dumps(motif or {"motifs": ["破碎的镜子"]}),
            json.dumps({"allowed": []}),
            json.dumps({"target_reader": "adult"}),
            status,
        ),
    )


def _insert_atomic(conn, project_id: int, *, clause_type: str, text: str, status: str = "confirmed", scope_type: str = "book") -> None:
    _ensure_project(conn, project_id)
    conn.execute(
        """
        INSERT INTO writing_atomic_source_clauses
            (project_id, source_document_id, scope_type, scope_id, clause_type, severity,
             clause_text, source_refs_json, source_hashes_json, status, created_at, updated_at)
        VALUES (?, 1, ?, NULL, ?, 'hard', ?, '[]', '[]', ?, ?, ?)
        """,
        (project_id, scope_type, clause_type, text, status, NOW, NOW),
    )


class TestLoadBookContext:
    """load_book_context 查询与聚合。"""

    @staticmethod
    def _has(items: tuple[str, ...], substr: str) -> bool:
        return any(substr in line for line in items)

    def test_groups_meta_and_atomic_into_four_buckets(self) -> None:
        conn = make_schema_db()
        _insert_meta(conn, 1, world={"facts": ["月光魔法"]}, narrative={"person": "third"}, motif={"motifs": ["镜子"]})
        _insert_atomic(conn, 1, clause_type="world", text="世界规则：北境常年冰雪")
        _insert_atomic(conn, 1, clause_type="character", text="主角林微：冷静、寡言")
        _insert_atomic(conn, 1, clause_type="plot", text="主线：寻找破碎镜子的七块碎片")
        _insert_atomic(conn, 1, clause_type="style", text="风格：冷峻短句")

        ctx = load_book_context(conn, 1)
        assert isinstance(ctx, BookContextDTO)
        assert self._has(ctx.world, "月光魔法")
        assert self._has(ctx.world, "世界规则：北境常年冰雪")
        assert self._has(ctx.character, "主角林微：冷静、寡言")
        assert self._has(ctx.narrative, "主线：寻找破碎镜子的七块碎片")
        assert self._has(ctx.narrative, "person: third")
        assert self._has(ctx.motif, "风格：冷峻短句")
        assert self._has(ctx.motif, "镜子")

    def test_filters_non_confirmed_status(self) -> None:
        """proposed/draft/superseded 的数据不进 book 上下文。"""
        conn = make_schema_db()
        _insert_meta(conn, 1, status="draft")
        _insert_atomic(conn, 1, clause_type="character", text="confirmed 角色", status="confirmed")
        _insert_atomic(conn, 1, clause_type="character", text="proposed 角色", status="proposed")
        _insert_atomic(conn, 1, clause_type="character", text="superseded 角色", status="superseded")

        ctx = load_book_context(conn, 1)
        # meta 是 draft → world/narrative/motif 空；atomic 只留 confirmed。
        assert ctx.world == ()
        assert ctx.character == ("confirmed 角色",)
        assert ctx.narrative == ()
        assert ctx.motif == ()

    def test_filters_non_book_scope_atomic(self) -> None:
        """scope_type != 'book' 的 atomic 条款不进 book 上下文。"""
        conn = make_schema_db()
        _insert_meta(conn, 1, world={"facts": []}, narrative={"person": "third"}, motif={"motifs": []})
        _insert_atomic(conn, 1, clause_type="world", text="book 世界", scope_type="book")
        _insert_atomic(conn, 1, clause_type="world", text="chapter 世界", scope_type="chapter")

        ctx = load_book_context(conn, 1)
        assert ctx.world == ("book 世界",)

    def test_dedup_exact_duplicate_lines(self) -> None:
        """同一文本行（meta 内重复 / atomic 内重复）只保留一份，保序。"""
        conn = make_schema_db()
        # 两条 atomic 条款文本完全相同 → 去重留一。
        _insert_atomic(conn, 1, clause_type="character", text="主角林微")
        _insert_atomic(conn, 1, clause_type="character", text="主角林微")
        _insert_atomic(conn, 1, clause_type="character", text="配角周衡")

        ctx = load_book_context(conn, 1)
        assert ctx.character == ("主角林微", "配角周衡")

    def test_empty_when_no_book_data(self) -> None:
        """无 meta 无 atomic → 全空 tuple，不抛异常。"""
        conn = make_schema_db()
        ctx = load_book_context(conn, 1)
        assert ctx.world == ()
        assert ctx.character == ()
        assert ctx.narrative == ()
        assert ctx.motif == ()


class TestRenderBookSection:
    """_render_task_card 的 book 段渲染。"""

    def test_renders_four_sections(self) -> None:
        ctx = BookContextDTO(
            world=("月光魔法", "北境冰雪"),
            character=("林微：冷静",),
            narrative=("第三人称近距",),
            motif=("破碎镜子",),
        )
        text = _render_book_section(ctx)
        assert "World: 月光魔法；北境冰雪" in text
        assert "Character: 林微：冷静" in text
        assert "Narrative: 第三人称近距" in text
        assert "Motif: 破碎镜子" in text

    def test_omits_empty_buckets(self) -> None:
        ctx = BookContextDTO(world=("月光",), character=(), narrative=("第三人称",), motif=())
        text = _render_book_section(ctx)
        assert "World:" in text
        assert "Character:" not in text
        assert "Narrative:" in text
        assert "Motif:" not in text

    def test_none_context_yields_empty(self) -> None:
        assert _render_book_section(None) == ""

    def test_full_task_card_keeps_complete_tail_with_book(self) -> None:
        """注入 book 段后 task_card 仍以「。」结尾（通过 _has_complete_tail 校验）。"""
        ctx = BookContextDTO(world=("月光",), character=(), narrative=(), motif=())
        card = _render_task_card(
            {"events": ["a"], "beats": ["b"], "information_releases": []},
            {"forbidden_facts": [], "forbidden_words": [], "pov_only": []},
            {"persona": "p", "intensity": {}, "is_creative_shot": False, "is_suspense_shot": False},
            ctx,
        )
        assert card.endswith("请按以上约束完成本 shot。")
        assert "World: 月光" in card

    def test_full_task_card_without_book_data_unchanged_shape(self) -> None:
        """无 book 数据时 task_card 形态与改造前一致（无 World/Character 段）。"""
        card = _render_task_card(
            {"events": [], "beats": [], "information_releases": []},
            {"forbidden_facts": [], "forbidden_words": [], "pov_only": []},
            {"persona": "p", "intensity": {}, "is_creative_shot": False, "is_suspense_shot": False},
            None,
        )
        assert "World:" not in card
        assert "Character:" not in card
        assert card.endswith("请按以上约束完成本 shot。")


class TestBookContextReachesPrompt:
    """端到端：book 段经 task_card 进 writer prompt。"""

    def test_book_section_in_compiled_instructions(self) -> None:
        """make_winner_selected_shot 注入 book 数据后，重新编译的 task_card 含 book 段。"""
        from ink.contract.task_card import TaskCardCompiler
        from test_m4_review_pipeline import make_winner_selected_shot

        conn = make_winner_selected_shot()
        ids = conn.execute(
            "SELECT shot_id, run_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
        ).fetchone()
        shot_id, run_id = str(ids[0]), int(ids[1])
        _insert_meta(conn, 1, world={"facts": ["月光魔法"]}, motif={"motifs": ["破碎镜子"]})
        _insert_atomic(conn, 1, clause_type="character", text="主角林微：冷静")

        card = TaskCardCompiler(conn).compile_for_shot(shot_id, run_id)
        assert "World: facts: 月光魔法" in card.compiled_instructions
        assert "Character: 主角林微：冷静" in card.compiled_instructions
        assert "Motif: motifs: 破碎镜子" in card.compiled_instructions
