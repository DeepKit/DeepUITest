"""Stale 传播矩阵实现。

对齐 docs/implementation-contract-v1.md:2002-2011 的传播规则：
BookContract → 全部卷/部/章/shot；VolumeContract → 本卷部/章/shot；
PartContract → 本部章/shot；ChapterContract → 本章 shot；
ShotContract → 本 shot 的 prompt/draft；
SourceDocument hash → atomic clauses / contract patches / decision sessions / prompt。

写入层：writing_prompt_snapshots.is_stale、writing_drafts.is_stale、
writing_chapter_reviews.is_stale、writing_book_check_results.is_stale。

Schema 约束：
- writing_prompt_snapshots PK = prompt_id，通过 task_card_id → shot_task_cards →
  shot_contracts → chapter_id 关联章节。
- writing_drafts 无 chapter_id 列，通过 shot_id → writing_shots.chapter_id 关联。
- writing_chapter_reviews 直接有 chapter_id 列。
- writing_book_check_results 直接有 project_id 列。
- 当前 schema 中 writing_shots/writing_chapter_specs 只有 chapter_id (INTEGER)，
  无 volume_id / part_id 列。卷/部级别的 stale 传播退化为「全部章节」，
  待 schema 增加章节分组列后可精确化。
"""
from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from typing import Literal


@dataclass
class StaleMarkResult:
    """标记结果。"""
    scope_type: str
    scope_id: str | None
    affected_prompt_ids: list[int] = field(default_factory=list)
    affected_draft_ids: list[int] = field(default_factory=list)
    affected_review_ids: list[int] = field(default_factory=list)
    affected_check_ids: list[int] = field(default_factory=list)

    def total(self) -> int:
        return (
            len(self.affected_prompt_ids)
            + len(self.affected_draft_ids)
            + len(self.affected_review_ids)
            + len(self.affected_check_ids)
        )


class StalePropagationManager:
    """契约或 source hash 变化后，按层级标记下游 stale。

    注意：标记是幂等的，重复调用不会重复计数。下游是否阻塞由调用方
    （gatekeeper/pipeline）自行判断。
    """

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    # ------------------------------------------------------------------
    # 契约层级 stale 传播
    # ------------------------------------------------------------------

    def mark_stale_after_contract_change(
        self,
        *,
        project_id: int,
        scope_type: Literal["book", "volume", "part", "chapter"],
        scope_id: str | None,
        contract_version_id: int | None = None,
    ) -> StaleMarkResult:
        """契约变更后，标记下游 prompt/draft/review/book check stale。

        scope_id 的语义：
        - book：None，影响全部
        - volume：volume_id 字符串（当前 schema 无卷分组，退化为全部）
        - part：part_id 字符串（当前 schema 无部分组，退化为全部）
        - chapter：chapter_id 字符串（整数转字符串，精确标记本章）
        """
        result = StaleMarkResult(scope_type=scope_type, scope_id=scope_id)

        if scope_type == "book":
            result.affected_prompt_ids = self._mark_all_prompts(project_id)
            result.affected_draft_ids = self._mark_all_drafts(project_id)
            result.affected_review_ids = self._mark_all_reviews(project_id)
            result.affected_check_ids = self._mark_all_checks(project_id)
        elif scope_type == "volume":
            chapter_ids = self._find_chapters_in_volume(project_id, scope_id)
            if chapter_ids:
                result.affected_prompt_ids = self._mark_prompts_for_chapters(project_id, chapter_ids)
                result.affected_draft_ids = self._mark_drafts_for_chapters(project_id, chapter_ids)
                result.affected_review_ids = self._mark_reviews_for_chapters(project_id, chapter_ids)
            result.affected_check_ids = self._mark_all_checks(project_id)
        elif scope_type == "part":
            chapter_ids = self._find_chapters_in_part(project_id, scope_id)
            if chapter_ids:
                result.affected_prompt_ids = self._mark_prompts_for_chapters(project_id, chapter_ids)
                result.affected_draft_ids = self._mark_drafts_for_chapters(project_id, chapter_ids)
                result.affected_review_ids = self._mark_reviews_for_chapters(project_id, chapter_ids)
            result.affected_check_ids = self._mark_all_checks(project_id)
        elif scope_type == "chapter":
            if scope_id is None:
                raise ValueError("chapter scope requires scope_id")
            chapter_id = int(scope_id)
            result.affected_prompt_ids = self._mark_prompts_for_chapter(project_id, chapter_id)
            result.affected_draft_ids = self._mark_drafts_for_chapter(project_id, chapter_id)
            result.affected_review_ids = self._mark_reviews_for_chapter(project_id, chapter_id)
            # book check 是全书级的，任一章变化都需要重新检测
            result.affected_check_ids = self._mark_all_checks(project_id)
        else:
            raise ValueError(f"unknown scope_type: {scope_type}")

        return result

    # ------------------------------------------------------------------
    # Source 变化 stale 传播
    # ------------------------------------------------------------------

    def mark_stale_after_source_change(
        self,
        *,
        project_id: int,
        source_document_id: int,
    ) -> StaleMarkResult:
        """SourceDocument hash 变化后，标记依赖该 source 的下游 stale。

        路径：
        1. writing_atomic_source_clauses WHERE source_document_id
        2. writing_contract_patches WHERE source_clause_ids_json 包含这些 clause
        3. 提取受影响的 decision_session_id（通过 patch 关联）
        4. 从 decision session 的 scope_type/scope_id 决定下游 prompt/draft
        """
        result = StaleMarkResult(scope_type="source", scope_id=str(source_document_id))

        # 1. 找该 source 的所有原子条款
        clause_rows = self.conn.execute(
            """
            SELECT atomic_clause_id FROM writing_atomic_source_clauses
            WHERE source_document_id = ?
            """,
            (source_document_id,),
        ).fetchall()
        if not clause_rows:
            return result

        clause_ids = {int(row[0]) for row in clause_rows}

        # 2. 找所有 patch 中 source_clause_ids_json 包含这些 clause 的
        #    scope_type/scope_id 从 writing_decision_sessions 获取
        patch_rows = self.conn.execute(
            """
            SELECT cp.contract_patch_id, cp.decision_session_id,
                   ds.scope_type, ds.scope_id
            FROM writing_contract_patches cp
            JOIN writing_decision_sessions ds
                ON ds.decision_session_id = cp.decision_session_id
            WHERE cp.project_id = ?
            """,
            (project_id,),
        ).fetchall()

        affected_chapter_ids: set[int] = set()
        mark_all = False
        for row in patch_rows:
            patch_id = int(row[0])
            s_type = str(row[2])
            s_id = str(row[3]) if row[3] is not None else None

            # 查该 patch 的 source_clause_ids_json
            patch_detail = self.conn.execute(
                """
                SELECT source_clause_ids_json FROM writing_contract_patches
                WHERE contract_patch_id = ?
                """,
                (patch_id,),
            ).fetchone()
            if patch_detail is None:
                continue
            clause_ids_json = str(patch_detail[0])
            try:
                patch_clause_ids = set(json.loads(clause_ids_json))
            except (json.JSONDecodeError, TypeError):
                patch_clause_ids = set()

            if patch_clause_ids & clause_ids:
                if s_type == "book":
                    mark_all = True
                    break
                elif s_type == "chapter" and s_id is not None:
                    affected_chapter_ids.add(int(s_id))

        if mark_all:
            result.affected_prompt_ids = self._mark_all_prompts(project_id)
            result.affected_draft_ids = self._mark_all_drafts(project_id)
            result.affected_review_ids = self._mark_all_reviews(project_id)
            result.affected_check_ids = self._mark_all_checks(project_id)
        elif affected_chapter_ids:
            for cid in affected_chapter_ids:
                result.affected_prompt_ids.extend(
                    self._mark_prompts_for_chapter(project_id, cid)
                )
                result.affected_draft_ids.extend(
                    self._mark_drafts_for_chapter(project_id, cid)
                )
                result.affected_review_ids.extend(
                    self._mark_reviews_for_chapter(project_id, cid)
                )
            result.affected_check_ids = self._mark_all_checks(project_id)

        return result

    # ------------------------------------------------------------------
    # 查询层
    # ------------------------------------------------------------------

    def check_stale(self, *, shot_id: str) -> bool:
        """检查某 shot 是否 stale（用于 gate 阻断）。

        查 writing_prompt_snapshots 中该 shot 最新 prompt 的 is_stale。
        路径：shot_id → writing_shots → writing_shot_contracts →
              writing_shot_task_cards → writing_prompt_snapshots
        """
        row = self.conn.execute(
            """
            SELECT ps.is_stale
            FROM writing_prompt_snapshots ps
            JOIN writing_shot_task_cards tc ON tc.task_card_id = ps.task_card_id
            JOIN writing_shot_contracts sc ON sc.shot_contract_id = tc.shot_contract_id
            JOIN writing_shots s ON s.shot_contract_id = sc.shot_contract_id
            WHERE s.shot_id = ?
            ORDER BY ps.created_at DESC LIMIT 1
            """,
            (shot_id,),
        ).fetchone()
        if row is None:
            return False
        return int(row[0]) == 1

    # ------------------------------------------------------------------
    # 内部：按章节标记
    # ------------------------------------------------------------------

    def _mark_prompts_for_chapter(self, project_id: int, chapter_id: int) -> list[int]:
        """标记本章关联的 prompt snapshots 为 stale。

        路径：chapter_id → writing_shot_contracts → writing_shot_task_cards →
              writing_prompt_snapshots
        """
        rows = self.conn.execute(
            """
            SELECT ps.prompt_id
            FROM writing_prompt_snapshots ps
            JOIN writing_shot_task_cards tc ON tc.task_card_id = ps.task_card_id
            JOIN writing_shot_contracts sc ON sc.shot_contract_id = tc.shot_contract_id
            WHERE sc.project_id = ? AND sc.chapter_id = ? AND ps.is_stale = 0
            """,
            (project_id, chapter_id),
        ).fetchall()
        ids = [int(row[0]) for row in rows]
        if ids:
            placeholders = ",".join("?" for _ in ids)
            self.conn.execute(
                f"""
                UPDATE writing_prompt_snapshots SET is_stale = 1
                WHERE prompt_id IN ({placeholders})
                """,
                ids,
            )
        return ids

    def _mark_drafts_for_chapter(self, project_id: int, chapter_id: int) -> list[int]:
        """标记本章关联的 drafts 为 stale。

        路径：chapter_id → writing_shots → writing_drafts
        """
        rows = self.conn.execute(
            """
            SELECT d.draft_id
            FROM writing_drafts d
            JOIN writing_shots s ON s.shot_id = d.shot_id
            WHERE s.project_id = ? AND s.chapter_id = ? AND d.is_stale = 0
            """,
            (project_id, chapter_id),
        ).fetchall()
        ids = [int(row[0]) for row in rows]
        if ids:
            placeholders = ",".join("?" for _ in ids)
            self.conn.execute(
                f"""
                UPDATE writing_drafts SET is_stale = 1
                WHERE draft_id IN ({placeholders})
                """,
                ids,
            )
        return ids

    def _mark_reviews_for_chapter(self, project_id: int, chapter_id: int) -> list[int]:
        """标记本章关联的 chapter reviews 为 stale。"""
        rows = self.conn.execute(
            """
            SELECT review_id FROM writing_chapter_reviews
            WHERE project_id = ? AND chapter_id = ? AND is_stale = 0
            """,
            (project_id, chapter_id),
        ).fetchall()
        ids = [int(row[0]) for row in rows]
        if ids:
            placeholders = ",".join("?" for _ in ids)
            self.conn.execute(
                f"""
                UPDATE writing_chapter_reviews SET is_stale = 1
                WHERE review_id IN ({placeholders})
                """,
                ids,
            )
        return ids

    def _mark_prompts_for_chapters(self, project_id: int, chapter_ids: list[str]) -> list[int]:
        """标记多章关联的 prompt snapshots 为 stale。"""
        result: list[int] = []
        for cid in chapter_ids:
            result.extend(self._mark_prompts_for_chapter(project_id, int(cid)))
        return result

    def _mark_drafts_for_chapters(self, project_id: int, chapter_ids: list[str]) -> list[int]:
        """标记多章关联的 drafts 为 stale。"""
        result: list[int] = []
        for cid in chapter_ids:
            result.extend(self._mark_drafts_for_chapter(project_id, int(cid)))
        return result

    def _mark_reviews_for_chapters(self, project_id: int, chapter_ids: list[str]) -> list[int]:
        """标记多章关联的 chapter reviews 为 stale。"""
        result: list[int] = []
        for cid in chapter_ids:
            result.extend(self._mark_reviews_for_chapter(project_id, int(cid)))
        return result

    def _mark_all_prompts(self, project_id: int) -> list[int]:
        rows = self.conn.execute(
            """
            SELECT ps.prompt_id
            FROM writing_prompt_snapshots ps
            JOIN writing_shot_task_cards tc ON tc.task_card_id = ps.task_card_id
            JOIN writing_shot_contracts sc ON sc.shot_contract_id = tc.shot_contract_id
            WHERE sc.project_id = ? AND ps.is_stale = 0
            """,
            (project_id,),
        ).fetchall()
        ids = [int(row[0]) for row in rows]
        if ids:
            placeholders = ",".join("?" for _ in ids)
            self.conn.execute(
                f"""
                UPDATE writing_prompt_snapshots SET is_stale = 1
                WHERE prompt_id IN ({placeholders})
                """,
                ids,
            )
        return ids

    def _mark_all_drafts(self, project_id: int) -> list[int]:
        rows = self.conn.execute(
            """
            SELECT d.draft_id
            FROM writing_drafts d
            JOIN writing_shots s ON s.shot_id = d.shot_id
            WHERE s.project_id = ? AND d.is_stale = 0
            """,
            (project_id,),
        ).fetchall()
        ids = [int(row[0]) for row in rows]
        if ids:
            placeholders = ",".join("?" for _ in ids)
            self.conn.execute(
                f"""
                UPDATE writing_drafts SET is_stale = 1
                WHERE draft_id IN ({placeholders})
                """,
                ids,
            )
        return ids

    def _mark_all_reviews(self, project_id: int) -> list[int]:
        rows = self.conn.execute(
            """
            SELECT review_id FROM writing_chapter_reviews
            WHERE project_id = ? AND is_stale = 0
            """,
            (project_id,),
        ).fetchall()
        ids = [int(row[0]) for row in rows]
        if ids:
            placeholders = ",".join("?" for _ in ids)
            self.conn.execute(
                f"""
                UPDATE writing_chapter_reviews SET is_stale = 1
                WHERE review_id IN ({placeholders})
                """,
                ids,
            )
        return ids

    def _mark_all_checks(self, project_id: int) -> list[int]:
        rows = self.conn.execute(
            """
            SELECT check_run_id FROM writing_book_check_results
            WHERE project_id = ? AND is_stale = 0
            """,
            (project_id,),
        ).fetchall()
        ids = [int(row[0]) for row in rows]
        if ids:
            placeholders = ",".join("?" for _ in ids)
            self.conn.execute(
                f"""
                UPDATE writing_book_check_results SET is_stale = 1
                WHERE check_run_id IN ({placeholders})
                """,
                ids,
            )
        return ids

    # ------------------------------------------------------------------
    # 内部：章节查找（精确筛选）
    # ------------------------------------------------------------------

    def _find_chapters_in_volume(self, project_id: int, volume_id: str | None) -> list[str]:
        """按 volume_id 精确查找章节。"""
        if volume_id is None:
            return []
        rows = self.conn.execute(
            """
            SELECT DISTINCT chapter_id FROM writing_shots
            WHERE project_id = ? AND volume_id = ?
            """,
            (project_id, volume_id),
        ).fetchall()
        return [str(row[0]) for row in rows]

    def _find_chapters_in_part(self, project_id: int, part_id: str | None) -> list[str]:
        """按 part_id 精确查找章节。"""
        if part_id is None:
            return []
        rows = self.conn.execute(
            """
            SELECT DISTINCT chapter_id FROM writing_shots
            WHERE project_id = ? AND part_id = ?
            """,
            (project_id, part_id),
        ).fetchall()
        return [str(row[0]) for row in rows]
