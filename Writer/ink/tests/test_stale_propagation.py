"""StalePropagationManager 测试。"""
from __future__ import annotations

import json
import sqlite3

import pytest

from factories import NOW, insert_minimal_draft, make_schema_db
from ink.stale_propagation import StaleMarkResult, StalePropagationManager


def _insert_project(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'demo', 'Demo', '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
        """,
        (NOW,),
    )


def _scalar_int(conn: sqlite3.Connection, sql: str) -> int:
    return int(conn.execute(sql).fetchone()[0])


def _setup_full_project(conn: sqlite3.Connection) -> dict:
    """创建一个完整的测试项目，含 prompt/draft/review/book_check。"""
    ids = insert_minimal_draft(conn)

    # 添加 chapter review
    conn.execute(
        """
        INSERT INTO writing_chapter_reviews
            (review_id, project_id, chapter_id, run_id, status,
             blocking_issues, reviewed_at)
        VALUES (100, 1, 1, 20, 'pending', '[]', ?)
        """,
        (NOW,),
    )

    # 添加 book check
    conn.execute(
        """
        INSERT INTO writing_book_check_results
            (check_run_id, project_id, check_sequence,
             chapter_range_start, chapter_range_end,
             issues, blocking_issue_count, created_at)
        VALUES (200, 1, 1, 1, 1, '[]', 0, ?)
        """,
        (NOW,),
    )

    return ids


class TestStaleMarkResult:
    """StaleMarkResult dataclass 测试。"""

    def test_total_empty(self) -> None:
        r = StaleMarkResult(scope_type="book", scope_id=None)
        assert r.total() == 0

    def test_total_with_items(self) -> None:
        r = StaleMarkResult(
            scope_type="chapter",
            scope_id="1",
            affected_prompt_ids=[1, 2],
            affected_draft_ids=[3],
            affected_review_ids=[4],
            affected_check_ids=[5, 6],
        )
        assert r.total() == 6


class TestBookScopeStale:
    """book scope stale 测试：标记全部。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _setup_full_project(c)
        return c

    def test_book_scope_marks_all_stale(self, conn: sqlite3.Connection) -> None:
        mgr = StalePropagationManager(conn)
        result = mgr.mark_stale_after_contract_change(
            project_id=1,
            scope_type="book",
            scope_id=None,
        )

        assert len(result.affected_prompt_ids) >= 1
        assert len(result.affected_draft_ids) >= 1
        assert len(result.affected_review_ids) >= 1
        assert len(result.affected_check_ids) >= 1

        # 验证数据库已更新
        row = conn.execute(
            "SELECT is_stale FROM writing_prompt_snapshots WHERE prompt_id = ?",
            (result.affected_prompt_ids[0],),
        ).fetchone()
        assert int(row[0]) == 1

    def test_book_scope_idempotent(self, conn: sqlite3.Connection) -> None:
        """重复标记幂等：第二次调用不再返回已标记的行。"""
        mgr = StalePropagationManager(conn)

        result1 = mgr.mark_stale_after_contract_change(
            project_id=1, scope_type="book", scope_id=None
        )
        assert result1.total() > 0

        result2 = mgr.mark_stale_after_contract_change(
            project_id=1, scope_type="book", scope_id=None
        )
        assert result2.total() == 0


class TestChapterScopeStale:
    """chapter scope stale 测试：精确标记本章。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _setup_full_project(c)

        # 添加第 2 章的数据
        conn = c
        conn.execute(
            """
            INSERT INTO writing_sessions (session_id, project_id, started_at)
            VALUES (11, 1, ?)
            """,
            (NOW,),
        )
        conn.execute(
            """
            INSERT INTO writing_runs
                (run_id, project_id, session_id, run_attempt, started_at, status)
            VALUES (21, 1, 11, 1, ?, 'running')
            """,
            (NOW,),
        )
        cur = conn.execute(
            """
            INSERT INTO writing_shot_contracts
                (project_id, chapter_id, run_id, logical_shot_id, created_at, updated_at)
            VALUES (1, 2, 21, 'shot-002', ?, ?)
            """,
            (NOW, NOW),
        )
        sc2 = cur.lastrowid
        cur = conn.execute(
            """
            INSERT INTO writing_shot_task_cards
                (shot_contract_id, compiled_instructions, created_at)
            VALUES (?, 'write ch2', ?)
            """,
            (sc2, NOW),
        )
        tc2 = cur.lastrowid
        cur = conn.execute(
            """
            INSERT INTO writing_prompt_snapshots
                (task_card_id, persona, full_prompt_text, prompt_size_bytes, created_at)
            VALUES (?, 'text', 'prompt ch2', 9, ?)
            """,
            (tc2, NOW),
        )
        prompt2 = cur.lastrowid
        shot2_id = "shot-002@21"
        conn.execute(
            """
            INSERT INTO writing_shots
                (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id,
                 status, created_at, updated_at)
            VALUES (?, 1, 2, ?, 21, 'shot-002', 'pending', ?, ?)
            """,
            (shot2_id, sc2, NOW, NOW),
        )
        conn.execute(
            """
            INSERT INTO writing_drafts
                (shot_id, prompt_id, persona, writer_model, text, byte_count, created_at)
            VALUES (?, ?, 'text', 'writer-a', 'draft ch2', 9, ?)
            """,
            (shot2_id, prompt2, NOW),
        )
        conn.execute(
            """
            INSERT INTO writing_chapter_reviews
                (review_id, project_id, chapter_id, run_id, status,
                 blocking_issues, reviewed_at)
            VALUES (101, 1, 2, 21, 'pending', '[]', ?)
            """,
            (NOW,),
        )
        return c

    def test_chapter_scope_marks_only_that_chapter(
        self, conn: sqlite3.Connection
    ) -> None:
        mgr = StalePropagationManager(conn)
        result = mgr.mark_stale_after_contract_change(
            project_id=1,
            scope_type="chapter",
            scope_id="1",
        )

        # 第 1 章的 prompt/draft/review 应被标记
        assert len(result.affected_prompt_ids) >= 1
        assert len(result.affected_draft_ids) >= 1
        assert len(result.affected_review_ids) >= 1

        # 第 2 章的 prompt/draft/review 不应被标记
        row = conn.execute(
            """
            SELECT is_stale FROM writing_prompt_snapshots
            WHERE prompt_id != ?
            """,
            (result.affected_prompt_ids[0],),
        ).fetchone()
        assert int(row[0]) == 0

    def test_chapter_scope_requires_scope_id(
        self, conn: sqlite3.Connection
    ) -> None:
        mgr = StalePropagationManager(conn)
        with pytest.raises(ValueError, match="chapter scope requires scope_id"):
            mgr.mark_stale_after_contract_change(
                project_id=1,
                scope_type="chapter",
                scope_id=None,
            )

    def test_book_check_always_marked_for_chapter(
        self, conn: sqlite3.Connection
    ) -> None:
        """book check 是全书级的，章变化时也要标记。"""
        mgr = StalePropagationManager(conn)
        result = mgr.mark_stale_after_contract_change(
            project_id=1,
            scope_type="chapter",
            scope_id="1",
        )
        assert len(result.affected_check_ids) >= 1


class TestVolumePartScopeStale:
    """volume/part scope stale 测试：精确筛选 writing_shots.volume_id/part_id。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        ids = _setup_full_project(c)
        # 给 shot 设置 volume_id 和 part_id，精确筛选
        c.execute(
            "UPDATE writing_shots SET volume_id = 'vol-1', part_id = 'part-1' WHERE shot_id = ?",
            (ids["shot_id"],),
        )
        return c

    def test_volume_scope_marks_matching_chapters(
        self, conn: sqlite3.Connection
    ) -> None:
        mgr = StalePropagationManager(conn)
        result = mgr.mark_stale_after_contract_change(
            project_id=1,
            scope_type="volume",
            scope_id="vol-1",
        )
        # 精确筛选 volume_id='vol-1' 的章节
        assert len(result.affected_prompt_ids) >= 1
        assert len(result.affected_draft_ids) >= 1

    def test_volume_scope_no_match_returns_empty(
        self, conn: sqlite3.Connection
    ) -> None:
        mgr = StalePropagationManager(conn)
        result = mgr.mark_stale_after_contract_change(
            project_id=1,
            scope_type="volume",
            scope_id="vol-nonexistent",
        )
        # 没有匹配的章节，不应标记任何 prompt/draft
        assert len(result.affected_prompt_ids) == 0
        assert len(result.affected_draft_ids) == 0
        # book_check 是全书级的，仍会被标记
        assert len(result.affected_check_ids) >= 1

    def test_part_scope_marks_matching_chapters(
        self, conn: sqlite3.Connection
    ) -> None:
        mgr = StalePropagationManager(conn)
        result = mgr.mark_stale_after_contract_change(
            project_id=1,
            scope_type="part",
            scope_id="part-1",
        )
        assert len(result.affected_prompt_ids) >= 1

    def test_part_scope_no_match_returns_empty(
        self, conn: sqlite3.Connection
    ) -> None:
        mgr = StalePropagationManager(conn)
        result = mgr.mark_stale_after_contract_change(
            project_id=1,
            scope_type="part",
            scope_id="part-nonexistent",
        )
        assert len(result.affected_prompt_ids) == 0


class TestSourceChangeStale:
    """source 变化 stale 传播测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        ids = _setup_full_project(c)
        conn = c

        # 插入 source document
        conn.execute(
            """
            INSERT INTO writing_source_documents
                (source_document_id, project_id, source_path, source_kind,
                 content_hash, status, created_at, updated_at)
            VALUES (50, 1, '/guide.md', 'guide', 'abc123',
                    'active', ?, ?)
            """,
            (NOW, NOW),
        )

        # 插入 atomic clause
        conn.execute(
            """
            INSERT INTO writing_atomic_source_clauses
                (atomic_clause_id, project_id, source_document_id, scope_type, scope_id,
                 clause_type, clause_text, severity, source_refs_json, source_hashes_json,
                 status, created_at, updated_at)
            VALUES (60, 1, 50, 'book', NULL, 'quality', 'must have logline',
                    'hard', '[]', '[]', 'confirmed', ?, ?)
            """,
            (NOW, NOW),
        )

        # 插入 decision session
        conn.execute(
            """
            INSERT INTO writing_decision_sessions
                (decision_session_id, project_id, scope_type, scope_id,
                 target_type, target_id, human_text, status, created_at, updated_at)
            VALUES (70, 1, 'book', NULL, 'BookContract', 'book', 'test',
                    'confirmed', ?, ?)
            """,
            (NOW, NOW),
        )

        # 插入 contract version (需要 contract_hash)
        conn.execute(
            """
            INSERT INTO writing_contract_versions
                (contract_version_id, project_id, scope_type, scope_id, version,
                 status, contract_json, contract_hash, source_clause_ids_json,
                 created_at)
            VALUES (80, 1, 'book', NULL, 1, 'confirmed',
                    '{}', 'hash123', '[]', ?)
            """,
            (NOW,),
        )

        # 插入 contract patch（关联 source clause）
        conn.execute(
            """
            INSERT INTO writing_contract_patches
                (contract_patch_id, project_id, decision_session_id,
                 base_contract_version_id, target_contract_version_id,
                 change_type, patch_json, affected_scopes_json,
                 stale_downstream_json, source_clause_ids_json, status, created_at)
            VALUES (90, 1, 70, 80, 80,
                    'refine', '[]', '[]', '[]', '[60]', 'applied', ?)
            """,
            (NOW,),
        )

        return c

    def test_source_change_marks_book_scope(
        self, conn: sqlite3.Connection
    ) -> None:
        """source 变化通过 book scope patch 传播到全部。"""
        mgr = StalePropagationManager(conn)
        result = mgr.mark_stale_after_source_change(
            project_id=1,
            source_document_id=50,
        )
        assert len(result.affected_prompt_ids) >= 1

    def test_source_change_no_clauses(
        self, conn: sqlite3.Connection
    ) -> None:
        """无原子条款时返回空。"""
        mgr = StalePropagationManager(conn)
        result = mgr.mark_stale_after_source_change(
            project_id=1,
            source_document_id=999,
        )
        assert result.total() == 0


class TestCheckStale:
    """check_stale 查询测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        _setup_full_project(c)
        return c

    def test_check_stale_false_initially(
        self, conn: sqlite3.Connection
    ) -> None:
        mgr = StalePropagationManager(conn)
        assert mgr.check_stale(shot_id="shot-001@20") is False

    def test_check_stale_true_after_mark(
        self, conn: sqlite3.Connection
    ) -> None:
        mgr = StalePropagationManager(conn)
        # 先标记 book scope stale
        mgr.mark_stale_after_contract_change(
            project_id=1, scope_type="book", scope_id=None
        )
        assert mgr.check_stale(shot_id="shot-001@20") is True

    def test_check_stale_unknown_shot(
        self, conn: sqlite3.Connection
    ) -> None:
        mgr = StalePropagationManager(conn)
        assert mgr.check_stale(shot_id="nonexistent") is False


class TestConfirmAutoStalePropagation:
    """confirm_and_apply(stale_manager=...) 自动触发 stale 传播。"""

    def _prepare_awaiting_confirm_session(self, conn):
        from ink.decision_sessions import DecisionSessionStore

        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封全书基线",
        )
        store.record_ai_parse(
            session_id,
            parsed_patch={"scope_type": "book", "change_type": "refine"},
            readback_text="封基线。",
            source_hashes=["hash-guide"],
            before_hash="before-hash",
        )
        store.create_option_set(session_id, options=[{"label": "确认"}], recommended_option=1)
        store.select_option(session_id, 1)
        return session_id

    def test_auto_stale_marks_downstream_on_confirm(self):
        conn = make_schema_db()
        _setup_full_project(conn)
        session_id = self._prepare_awaiting_confirm_session(conn)

        from ink.decision_sessions import DecisionSessionStore

        result = DecisionSessionStore(conn).confirm_and_apply(
            session_id,
            actor="author",
            reason="封基线",
            contract_scope_type="book",
            contract_scope_id=None,
            contract_payload={"identity": {"title": "Demo"}, "logline": "core"},
            source_hashes=["hash-guide"],
            stale_manager=StalePropagationManager(conn),
        )
        conn.commit()

        # stale_mark 非空：至少标记了 prompt/draft/review/check 各一条
        assert result.stale_mark is not None
        assert result.stale_mark.total() >= 4
        # DB 实际写入
        assert _scalar_int(conn, "SELECT is_stale FROM writing_prompt_snapshots WHERE prompt_id = 1") == 1

    def test_no_stale_manager_leaves_downstream_unmarked(self):
        conn = make_schema_db()
        _setup_full_project(conn)
        session_id = self._prepare_awaiting_confirm_session(conn)

        from ink.decision_sessions import DecisionSessionStore

        result = DecisionSessionStore(conn).confirm_and_apply(
            session_id,
            actor="author",
            reason="封基线",
            contract_scope_type="book",
            contract_scope_id=None,
            contract_payload={"identity": {"title": "Demo"}, "logline": "core"},
            source_hashes=["hash-guide"],
            # 不传 stale_manager
        )
        conn.commit()

        assert result.stale_mark is None
        # 下游未被标记
        assert _scalar_int(conn, "SELECT is_stale FROM writing_prompt_snapshots WHERE prompt_id = 1") == 0
