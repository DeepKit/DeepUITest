#!/usr/bin/env python3
"""黄金生产闭环 ② — 从 legacy 参数 JSON 重建干净生产库。

legacy 正式库(baideng_prod.db)被 schema_authority 标 'legacy',不再升级;
新库用最新 schema.sql + 全量迁移干净构建,再回灌 legacy 导出的参数三表
(writing_projects / writing_model_role_configs / writing_schema_authority)。
失败残骸(ai_call_attempts/runtime_events/scenes 等非参数表)不迁移——
这正是黄金闭环第③步重产 ch01/02 需要的干净生产库。

安全:默认 dry-run(不写库);--apply 才真建;目标路径已存在须 --force。
--force 覆盖前自动备份原库为 db.bak.YYYYMMDD-HHMMSS,绝不静默无备份覆盖。
回灌后 schema_authority 标 'current'(不是 legacy)。
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from ink.schema import initialize_schema, mark_all_migrations_applied, applied_migrations  # noqa: E402
from ink.core.model_role_config import upsert_role_config  # noqa: E402
from ink.time import now_utc_iso  # noqa: E402


def _project_param_cols(conn: sqlite3.Connection) -> list[str]:
    """writing_projects 除 project_id/created_at 外的列(回灌时主键+时间戳由新库生成)。"""
    cols = [r[1] for r in conn.execute("PRAGMA table_info(writing_projects)").fetchall()]
    return [c for c in cols if c not in ("project_id", "created_at")]


def rebuild(params_path: Path, db_path: Path) -> dict:
    """构建新库并回灌参数。返回统计。调用方负责 dry-run/force 守卫。"""
    data = json.loads(params_path.read_text(encoding="utf-8"))
    projects = data["projects"]
    role_configs = data["role_configs"]
    if len(projects) != 1:
        raise ValueError(f"expected exactly 1 project in params, got {len(projects)}")

    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA busy_timeout=5000")
    try:
        initialize_schema(conn)
        # 全新库:base schema 已含全部迁移对象,标记全部迁移已应用,不重复执行。
        marked = mark_all_migrations_applied(conn)

        # 回灌 project:插入参数列(主键+时间戳由新库生成),取回 project_id
        proj = projects[0]
        param_cols = _project_param_cols(conn)
        placeholders = ", ".join("?" for _ in param_cols)
        col_list = ", ".join(param_cols)
        values = [proj.get(c) for c in param_cols]
        cur = conn.execute(
            f"INSERT INTO writing_projects ({col_list}, created_at) VALUES ({placeholders}, ?)",
            (*values, now_utc_iso()),
        )
        project_id = int(cur.lastrowid)

        # 回灌 role_configs(用 upsert 保持 ON CONFLICT 语义一致)
        for rc in role_configs:
            upsert_role_config(
                conn,
                project_id=project_id,
                call_type=rc["call_type"],
                tier=rc["tier"],
                model_name=rc["model_name"],
                provider=rc["provider"],
                api_key_env=rc["api_key_env"],
                base_url=rc.get("base_url"),
                max_tokens=rc.get("max_tokens"),
            )

        # schema_authority 表是 legacy 库的 ad-hoc 标记(未纳入 schema.sql/迁移)。
        # 新库 schema.sql 不建此表,不回灌——若第③步需 legacy 隔离机制,应正式工程化,
        # 而非沿用无定义的临时表。legacy 标记状态已保存在 params JSON 的 schema_authority 段备查。
        conn.commit()

        # 验证:新库含 stale_marks 三表 + schema_migrations 有记录
        tabs = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
        has_stale = all(t in tabs for t in (
            "writing_scene_revision_stale_marks",
            "writing_branch_version_stale_marks",
            "writing_chapter_snapshot_stale_marks",
        ))
        mig_count = conn.execute("SELECT count(*) FROM schema_migrations").fetchone()[0]
        rc_count = conn.execute(
            "SELECT count(*) FROM writing_model_role_configs WHERE project_id=?", (project_id,)
        ).fetchone()[0]
        return {
            "db_path": str(db_path),
            "project_id": project_id,
            "migrations_marked": len(marked),
            "migrations_total": len(applied_migrations(conn)),
            "has_stale_marks_tables": has_stale,
            "role_configs_imported": rc_count,
        }
    finally:
        conn.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("params", type=Path, help="export_legacy_params.py 导出的 JSON")
    parser.add_argument("db", type=Path, help="新库输出路径(须不存在,除非 --force)")
    parser.add_argument("--apply", action="store_true", help="真建库(默认 dry-run 不写)")
    parser.add_argument("--force", action="store_true", help="目标已存在时覆盖(仍需 --apply)")
    args = parser.parse_args(argv)
    if not args.params.exists():
        print(f"[ERR] params not found: {args.params}", file=sys.stderr)
        return 2
    if args.db.exists() and not args.force:
        print(f"[ERR] target exists: {args.db}(用 --force 覆盖,且必须 --apply)", file=sys.stderr)
        return 2
    if not args.apply:
        print(f"[DRY-RUN] would build {args.db} from {args.params}")
        print(f"[DRY-RUN] 用 --apply 真建。")
        return 0

    # 正式库替换是不可逆生产动作:--force 覆盖前强制备份原库,然后删除原文件让 rebuild 全新建。
    # 备份名 db.bak.YYYYMMDD-HHMMSS,带时间戳避免反复覆盖丢失更早备份。
    if args.db.exists() and args.force:
        import shutil
        from datetime import datetime
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = args.db.with_suffix(args.db.suffix + f".bak.{ts}")
        shutil.copy2(args.db, backup)
        print(f"[BACKUP] 原 {args.db} → {backup}(覆盖前自动备份)")
        args.db.unlink()
        print(f"[REMOVE] 原库文件已删除(备份已留),rebuild 将全新建库")

    stats = rebuild(args.params, args.db)
    print(f"[DONE] rebuilt {stats['db_path']}")
    print(f"  project_id={stats['project_id']}")
    print(f"  migrations marked={stats['migrations_marked']} total={stats['migrations_total']}")
    print(f"  stale_marks tables present={stats['has_stale_marks_tables']}")
    print(f"  role_configs imported={stats['role_configs_imported']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
