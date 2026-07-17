#!/usr/bin/env python3
"""黄金生产闭环 ② — 导出 legacy 库的参数三表为 JSON,供新库重建后回灌。

legacy 正式库(baideng_prod.db)被 schema_authority 标为 'legacy',不再升级;
新生产走全新库(最新 schema.sql + 全量迁移)。本脚本只读 legacy 库,把:
  - writing_projects(按 code 锚定,排除 project_id 自增主键)
  - writing_model_role_configs(按 project_code+call_type+tier 锚定)
  - writing_schema_authority(记录 legacy 标记,新库回灌时改 'current')
导出为可移植 JSON,不含 api_key 明文(只导 api_key_env 环境变量名)。

幂等:可重复跑,覆盖输出。不碰源库。
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

# 参数三表;排除自增主键与时间戳(回灌时由新库重生成)。
# writing_projects 排 project_id/created_at,留 code 作业务主键锚。
# role_configs 排 role_config_id/project_id/created_at/updated_at,留 call_type+tier 作锚。
# schema_authority 整表只 1 行,记录 legacy 状态备查(回灌时新库标 'current' 而非 'legacy')。
_PARAM_TABLES = {
    "projects": "writing_projects",
    "role_configs": "writing_model_role_configs",
    "schema_authority": "writing_schema_authority",
}


def _columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [r[1] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()]


def export_params(db_path: Path) -> dict:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        out: dict[str, object] = {}

        # writing_projects:导全部列,排除 project_id 与 created_at(主键+时间戳由新库生成)
        proj_cols = [c for c in _columns(conn, "writing_projects") if c not in ("project_id", "created_at")]
        proj_rows = [dict(zip(proj_cols, row)) for row in conn.execute(
            f"SELECT {', '.join(proj_cols)} FROM writing_projects"
        ).fetchall()]
        out["projects"] = proj_rows

        # role_configs:排除主键 role_config_id/project_id/created_at/updated_at
        role_cols = [c for c in _columns(conn, "writing_model_role_configs")
                     if c not in ("role_config_id", "project_id", "created_at", "updated_at")]
        role_rows = [dict(zip(role_cols, row)) for row in conn.execute(
            f"SELECT {', '.join(role_cols)} FROM writing_model_role_configs"
        ).fetchall()]
        out["role_configs"] = role_rows

        # schema_authority:整表,新库回灌时改 authority='current'
        auth_cols = _columns(conn, "writing_schema_authority")
        auth_rows = [dict(zip(auth_cols, row)) for row in conn.execute(
            f"SELECT {', '.join(auth_cols)} FROM writing_schema_authority"
        ).fetchall()]
        out["schema_authority"] = auth_rows
        return out
    finally:
        conn.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("db", type=Path, help="legacy Ink SQLite 库路径")
    parser.add_argument("-o", "--output", type=Path, default=None,
                        help="输出 JSON 路径(默认 <db>.params.json)")
    args = parser.parse_args(argv)
    if not args.db.exists():
        print(f"[ERR] database not found: {args.db}", file=sys.stderr)
        return 2
    out_path = args.output or args.db.with_suffix(".params.json")

    # 先单独统计非空表(上面 placeholder 被占位,这里真查)
    conn = sqlite3.connect(str(args.db))
    nonempty: dict[str, int] = {}
    for (name,) in conn.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").fetchall():
        try:
            n = conn.execute(f'SELECT count(*) FROM "{name}"').fetchone()[0]
            if n > 0:
                nonempty[name] = n
        except sqlite3.Error:
            pass
    conn.close()

    data = export_params(args.db)
    data["_source_nonempty_tables"] = nonempty
    data["_exported_from"] = str(args.db)

    out_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[DONE] exported {len(data['projects'])} projects, "
          f"{len(data['role_configs'])} role_configs, "
          f"{len(data['schema_authority'])} schema_authority rows → {out_path}")
    print(f"[INFO] legacy non-empty tables (will be dropped on rebuild): "
          f"{len(nonempty)} tables")
    return 0


if __name__ == "__main__":
    sys.exit(main())
