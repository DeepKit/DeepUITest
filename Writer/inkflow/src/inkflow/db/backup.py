"""数据库自动备份

在写操作前自动复制 inkflow.db 到 .inkflow/backups/ 目录。
使用 SQLite Online Backup API，对 WAL 模式数据库安全。
保留最近 N 个备份，滚动删除较旧的。

用法：
  from inkflow.db.backup import backup_project_db
  backup_path = backup_project_db(db_path, label="before_import")
"""

from __future__ import annotations

import sqlite3
from datetime import datetime
from pathlib import Path


DEFAULT_KEEP = 10


def backup_project_db(
    db_path: str | Path,
    *,
    label: str = "auto",
    keep: int = DEFAULT_KEEP,
) -> Path | None:
    """使用 SQLite Online Backup API 安全备份 inkflow.db。

    对 WAL 模式数据库安全：会正确读取 WAL 中未刷盘的已提交事务。

    Args:
        db_path: inkflow.db 的路径
        label: 备份标签（用于文件名）
        keep: 最大保留数量

    Returns:
        备份文件路径，失败返回 None
    """
    db_path = Path(db_path).resolve()
    if not db_path.exists():
        return None

    backup_dir = db_path.parent / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_name = f"inkflow_{timestamp}_{label}.db"
    backup_path = backup_dir / backup_name

    src = None
    dst = None
    try:
        src = sqlite3.connect(str(db_path))
        dst = sqlite3.connect(str(backup_path))
        src.backup(dst)
    except Exception:
        # 如果备份失败，清理可能产生的空文件
        if backup_path.exists():
            backup_path.unlink(missing_ok=True)
        return None
    finally:
        if dst:
            dst.close()
        if src:
            src.close()

    _rotate_backups(backup_dir, keep=keep)
    return backup_path


def _rotate_backups(backup_dir: Path, keep: int) -> None:
    """删除较旧的备份，仅保留最近的 keep 个"""
    backups = sorted(backup_dir.glob("inkflow_*.db"), key=lambda p: p.name)
    while len(backups) > keep:
        old = backups.pop(0)
        old.unlink(missing_ok=True)
