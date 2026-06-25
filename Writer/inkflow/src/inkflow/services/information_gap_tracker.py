"""Information Gap Tracker — 信息差生命周期追踪 (D-25).

追踪信息差的完整生命周期：
  pending → active → reinforced → revealed → resolved → new gap

信息差是悬疑的最强引擎。当读者知道某件事而角色不知道时，
读者会带着信息去审视角色的每一个行动，产生持续的紧张感。

每个 Shot 生成时，prompt 中注入当前活跃的信息差列表。
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field

from inkflow.utils.ulid import generate as generate_ulid


# ── 信息差状态 ──

class GapStatus:
    """信息差生命周期状态."""
    PENDING = "pending"         # 已声明，尚未创建
    ACTIVE = "active"           # 已创建，读者知道但角色不知道
    REINFORCED = "reinforced"   # 已被强化
    REVEALED = "revealed"       # 已被揭露，角色也知道了
    RESOLVED = "resolved"       # 已解决，不再产生悬疑


@dataclass
class InformationGap:
    """一个信息差实例."""

    gap_id: str
    project_id: str
    run_id: str
    description: str           # 信息差描述
    reader_knows: str          # 读者知道什么
    character_knows: str       # 角色知道什么（或不完整知道什么）
    status: str = GapStatus.PENDING

    created_shot_id: str | None = None
    reinforced_shot_ids: list[str] = field(default_factory=list)
    revealed_shot_id: str | None = None
    next_gap_id: str | None = None  # 揭露后可能产生的新信息差


class InformationGapTracker:
    """追踪信息差的完整生命周期.

    集成到 cli.py 的 run 循环中，在每次 Shot 完成后更新信息差状态。
    """

    def __init__(self, db: sqlite3.Connection, project_id: str, run_id: str):
        self.db = db
        self.project_id = project_id
        self.run_id = run_id

    # ── CRUD ──

    def create_gap(
        self,
        description: str,
        reader_knows: str,
        character_knows: str,
        created_shot_id: str | None = None,
    ) -> str:
        """创建一个新的信息差。

        Args:
            description: 信息差描述
            reader_knows: 读者知道什么
            character_knows: 角色知道什么
            created_shot_id: 在哪个 Shot 中被创建

        Returns:
            gap_id
        """
        gap_id = generate_ulid()

        self.db.execute(
            "INSERT INTO writing_information_gaps "
            "(gap_id, project_id, run_id, description, reader_knows, "
            "character_knows, status, created_shot_id, reinforced_shot_ids) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                gap_id, self.project_id, self.run_id,
                description, reader_knows, character_knows,
                GapStatus.ACTIVE if created_shot_id else GapStatus.PENDING,
                created_shot_id,
                json.dumps([], ensure_ascii=False),
            ),
        )
        self.db.commit()
        return gap_id

    def get_active_gaps(self) -> list[dict]:
        """获取当前所有活跃的信息差（active + reinforced）。"""
        rows = self.db.execute(
            "SELECT * FROM writing_information_gaps "
            "WHERE project_id = ? AND run_id = ? "
            "AND status IN ('active', 'reinforced') "
            "ORDER BY created_at",
            (self.project_id, self.run_id),
        ).fetchall()
        return [_gap_row_to_dict(row) for row in rows]

    def get_all_gaps(self) -> list[dict]:
        """获取所有信息差。"""
        rows = self.db.execute(
            "SELECT * FROM writing_information_gaps "
            "WHERE project_id = ? AND run_id = ? "
            "ORDER BY created_at",
            (self.project_id, self.run_id),
        ).fetchall()
        return [_gap_row_to_dict(row) for row in rows]

    def reinforce_gap(self, gap_id: str, shot_id: str) -> None:
        """强化一个信息差（在某个 Shot 中被再次提及）。

        读者被提醒：这个信息差还在，角色还不知道。
        """
        gap = self._get_gap(gap_id)
        if gap is None:
            return

        reinforced = json.loads(gap["reinforced_shot_ids"] or "[]")
        if shot_id not in reinforced:
            reinforced.append(shot_id)

        self.db.execute(
            "UPDATE writing_information_gaps "
            "SET status = ?, reinforced_shot_ids = ?, updated_at = datetime('now') "
            "WHERE gap_id = ?",
            (GapStatus.REINFORCED, json.dumps(reinforced, ensure_ascii=False), gap_id),
        )
        self.db.commit()

    def reveal_gap(self, gap_id: str, shot_id: str, new_gap_id: str | None = None) -> None:
        """揭露一个信息差（角色也知道了）。

        Args:
            gap_id: 要揭露的信息差 ID
            shot_id: 在哪个 Shot 中被揭露
            new_gap_id: 揭露后产生的新信息差 ID（如果有）
        """
        self.db.execute(
            "UPDATE writing_information_gaps "
            "SET status = ?, revealed_shot_id = ?, next_gap_id = ?, "
            "updated_at = datetime('now') "
            "WHERE gap_id = ?",
            (GapStatus.REVEALED, shot_id, new_gap_id, gap_id),
        )
        self.db.commit()

    def resolve_gap(self, gap_id: str) -> None:
        """解决一个信息差（不再产生悬疑）。"""
        self.db.execute(
            "UPDATE writing_information_gaps "
            "SET status = ?, updated_at = datetime('now') "
            "WHERE gap_id = ?",
            (GapStatus.RESOLVED, gap_id),
        )
        self.db.commit()

    # ── 初始化 ──

    def seed_from_blueprint(self, blueprint: dict) -> list[str]:
        """从悬疑蓝图初始化信息差。

        Args:
            blueprint: suspense_blueprint dict

        Returns:
            list of gap_ids created
        """
        gap_ids = []

        for chapter_key, chapter_config in blueprint.get("chapters", {}).items():
            gaps_to_create = chapter_config.get("info_gaps_to_create", [])
            for gap_desc in gaps_to_create:
                # Parse gap description into reader_knows and character_knows
                reader_knows, character_knows = _parse_gap_description(gap_desc)
                gap_id = self.create_gap(
                    description=gap_desc,
                    reader_knows=reader_knows,
                    character_knows=character_knows,
                )
                gap_ids.append(gap_id)

        return gap_ids

    # ── Prompt 注入 ──

    def build_active_gaps_prompt(self) -> str:
        """构建当前活跃信息差的 prompt 注入文本。

        Returns:
            注入到 prompt 中的信息差提醒文本
        """
        active = self.get_active_gaps()
        if not active:
            return ""

        parts = ["## 当前活跃的信息差（读者知道，角色不知道）", ""]
        parts.append("以下信息差正在产生悬疑张力。请确保：")
        parts.append("1. 不要在本章中让角色知道这些信息")
        parts.append("2. 利用戏剧反讽：让读者带着这些信息去审视角色的行动")
        parts.append("")

        for i, gap in enumerate(active, 1):
            parts.append(f"### 信息差 {i}")
            parts.append(f"读者知道：{gap['reader_knows']}")
            parts.append(f"角色不知道：{gap['character_knows']}")
            status_note = {
                GapStatus.ACTIVE: "（待强化）",
                GapStatus.REINFORCED: "（已强化，保持）",
            }.get(gap["status"], "")
            if status_note:
                parts.append(status_note)
            parts.append("")

        return "\n".join(parts)

    # ── 内部 ──

    def _get_gap(self, gap_id: str) -> dict | None:
        row = self.db.execute(
            "SELECT * FROM writing_information_gaps WHERE gap_id = ?",
            (gap_id,),
        ).fetchone()
        return _gap_row_to_dict(row) if row else None


# ── 辅助函数 ──

def _gap_row_to_dict(row: sqlite3.Row) -> dict:
    """将 DB 行转为 dict，解析 JSON 字段."""
    result = dict(row)
    if result.get("reinforced_shot_ids"):
        try:
            result["reinforced_shot_ids"] = json.loads(
                result["reinforced_shot_ids"]
            )
        except (json.JSONDecodeError, TypeError):
            result["reinforced_shot_ids"] = []
    else:
        result["reinforced_shot_ids"] = []
    return result


def _parse_gap_description(desc: str) -> tuple[str, str]:
    """从信息差描述中解析 reader_knows 和 character_knows。

    格式示例：
    "苏然发现了边界线每年外推6%，但阿坤、白英、韩教授都不知道——读者知道，角色不知道"

    Returns:
        (reader_knows, character_knows)
    """
    # Try to split on "——" or "——" or "，但"
    import re

    # Pattern: "X，但Y不知道" → reader knows X, character doesn't know Y
    match = re.search(r'(.+?)[，,]\s*但\s*(.+?)(?:不知道|不知道|不知|不知道)', desc)
    if match:
        reader_knows = match.group(1).strip()
        character_knows = match.group(2).strip()
        return reader_knows, character_knows

    # Pattern: "X——读者知道，角色不知道"
    match = re.search(r'(.+?)[—\-]{1,2}\s*读者知道', desc)
    if match:
        reader_knows = match.group(1).strip()
        character_knows = desc.replace(reader_knows, "").strip("— -，,。")
        return reader_knows, character_knows

    # Fallback: use the whole description as reader_knows
    return desc, "（待定义）"


def build_information_gap_schema() -> str:
    """Build the SQL schema for writing_information_gaps table.

    This is called from migration.py or schema.sql.
    """
    return """\
CREATE TABLE IF NOT EXISTS writing_information_gaps (
    gap_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    description TEXT NOT NULL,
    reader_knows TEXT NOT NULL,
    character_knows TEXT NOT NULL,
    created_shot_id TEXT REFERENCES writing_shots(shot_id),
    reinforced_shot_ids TEXT DEFAULT '[]',
    revealed_shot_id TEXT REFERENCES writing_shots(shot_id),
    next_gap_id TEXT REFERENCES writing_information_gaps(gap_id),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'active', 'reinforced', 'revealed', 'resolved')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_info_gaps_run ON writing_information_gaps(run_id);
CREATE INDEX IF NOT EXISTS idx_info_gaps_status ON writing_information_gaps(status);
"""