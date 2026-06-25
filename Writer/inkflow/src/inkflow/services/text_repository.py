"""Text Repository — 统一正文读取入口 (TS-1).

隔离 shot_revisions.text 的读取逻辑，避免散落的 SQL。

规则：
  - 未封版 shot（shot_status 不是 done_green/done_yellow/done_red_permanent）：
    读 MAX(revision_sequence) 的修订。
  - 已封版 shot：
    读 is_current = 1 的修订（唯一现行修订）。

如果需要区分 "正在写的那版" vs "已定稿的那版"，后续可以在
未封版分支再加一个 revision_sequence 过滤参数。
"""

from __future__ import annotations

import sqlite3


class TextRepository:
    """统一正文读取。

    用法：
        repo = TextRepository(db)
        text = repo.get_shot_text(shot_id)
    """

    def __init__(self, db: sqlite3.Connection):
        self.db = db

    # ── 主入口 ──

    def get_shot_text(self, shot_id: str) -> str:
        """获取 shot 的当前正文。

        封版 shot → is_current = 1。
        未封版 shot → MAX(revision_sequence)。
        """
        row = self.db.execute(
            "SELECT shot_status FROM writing_shots WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()

        if row is None:
            return ""

        shot_status = row["shot_status"]
        if shot_status in ("done_green", "done_yellow", "done_red_permanent"):
            return self._get_current_text(shot_id)
        else:
            return self._get_latest_text(shot_id)

    def get_shot_revision_id(self, shot_id: str) -> str | None:
        """获取正文所属 revision_id（用于锚定来源）。"""
        row = self.db.execute(
            "SELECT shot_status FROM writing_shots WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()

        if row is None:
            return None

        if row["shot_status"] in ("done_green", "done_yellow", "done_red_permanent"):
            rev = self.db.execute(
                "SELECT revision_id FROM shot_revisions WHERE shot_id = ? AND is_current = 1",
                (shot_id,),
            ).fetchone()
        else:
            rev = self.db.execute(
                "SELECT revision_id FROM shot_revisions WHERE shot_id = ? "
                "ORDER BY revision_sequence DESC LIMIT 1",
                (shot_id,),
            ).fetchone()

        return rev["revision_id"] if rev else None

    def get_shot_current_revision(self, shot_id: str) -> dict | None:
        """获取 shot 的当前修订完整记录（用于需要元数据的场景）。"""
        row = self.db.execute(
            "SELECT shot_status FROM writing_shots WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()

        if row is None:
            return None

        if row["shot_status"] in ("done_green", "done_yellow", "done_red_permanent"):
            rev = self.db.execute(
                "SELECT * FROM shot_revisions WHERE shot_id = ? AND is_current = 1",
                (shot_id,),
            ).fetchone()
        else:
            # Uncommitted: latest revision_sequence
            rev = self.db.execute(
                "SELECT * FROM shot_revisions WHERE shot_id = ? "
                "ORDER BY revision_sequence DESC LIMIT 1",
                (shot_id,),
            ).fetchone()

        return dict(rev) if rev else None

    # ── 底层读取 ──

    def _get_current_text(self, shot_id: str) -> str:
        """封版 shot：读 is_current = 1。"""
        row = self.db.execute(
            "SELECT text FROM shot_revisions WHERE shot_id = ? AND is_current = 1",
            (shot_id,),
        ).fetchone()
        return row["text"] if row else ""

    def _get_latest_text(self, shot_id: str) -> str:
        """未封版 shot：读 MAX(revision_sequence)。"""
        row = self.db.execute(
            "SELECT text FROM shot_revisions WHERE shot_id = ? "
            "ORDER BY revision_sequence DESC LIMIT 1",
            (shot_id,),
        ).fetchone()
        return row["text"] if row else ""

    # ── 便捷方法 ──

    def get_text_by_revision_id(self, revision_id: str) -> str:
        """通过 revision_id 直接读取（跳过 shot 状态判断）。"""
        row = self.db.execute(
            "SELECT text FROM shot_revisions WHERE revision_id = ?",
            (revision_id,),
        ).fetchone()
        return row["text"] if row else ""

    def has_text(self, shot_id: str) -> bool:
        """shot 是否有正文。"""
        text = self.get_shot_text(shot_id)
        return bool(text and text.strip())
