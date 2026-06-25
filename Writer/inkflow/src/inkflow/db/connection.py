"""数据库连接管理。单 SQLite DB 每项目。"""

from __future__ import annotations

import sqlite3
from pathlib import Path


def _find_schema() -> str:
    """查找 schema.sql 文件（包内）"""
    candidates = [
        (Path(__file__).parent / "schema.sql").resolve(),
    ]
    for c in candidates:
        if c.exists():
            return c.read_text(encoding="utf-8")
    raise FileNotFoundError("找不到 schema.sql。请确保 inkflow/db/schema.sql 存在。")


def open_db(path: str | Path, *, wal: bool = True, full_sync: bool = False) -> sqlite3.Connection:
    """打开一个 SQLite 数据库，应用标准 pragma"""
    conn = sqlite3.connect(str(path))
    conn.execute("PRAGMA encoding = 'UTF-8'")
    conn.text_factory = str
    if wal:
        conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(f"PRAGMA synchronous={'FULL' if full_sync else 'NORMAL'}")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA cache_size=-64000")
    conn.execute("PRAGMA temp_store=MEMORY")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.row_factory = sqlite3.Row
    return conn


def init_project_db(path: str | Path) -> sqlite3.Connection:
    """初始化项目 inkflow.db。创建（若不存在）或打开并迁移（若已存在）。

    Args:
        path: inkflow.db 的完整路径，如 D:\\_Progs\\.Story\\《分流》\\.inkflow\\inkflow.db

    Returns:
        sqlite3.Connection with row_factory = sqlite3.Row
    """
    from inkflow.db.migration import migrate_if_needed, init_version

    path = Path(path).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)

    # Check if the DB already exists by trying to open it and query _schema_meta.
    # Using try/except avoids the TOCTOU race between path.exists() and open_db().
    conn = open_db(path)
    try:
        conn.execute("SELECT 1 FROM _schema_meta LIMIT 1")
        migrate_if_needed(conn)
        conn.row_factory = sqlite3.Row
        return conn
    except sqlite3.OperationalError:
        # _schema_meta doesn't exist → fresh DB, initialize with same connection
        pass

    schema = _find_schema()
    _execute_schema(conn, schema)
    init_version(conn)
    conn.commit()
    conn.row_factory = sqlite3.Row
    return conn


def _execute_schema(conn: sqlite3.Connection, sql: str) -> None:
    """执行 schema SQL，跳过注释和空行，逐条执行。
    处理行内注释 (-- 在代码行后面的情况)。
    """
    lines = []
    for line in sql.splitlines():
        stripped = line.strip()
        # 跳过纯注释行
        if stripped.startswith("--"):
            continue
        # 跳过 PRAGMA（由 open_db 处理）
        if stripped.upper().startswith("PRAGMA"):
            continue
        if stripped == "":
            continue
        # 剥离行内注释：找不在字符串引号内的 --
        cleaned = _strip_inline_comment(line)
        lines.append(cleaned)

    text = "\n".join(lines)
    statements = _split_statements(text)

    for stmt in statements:
        stmt = stmt.strip()
        if not stmt:
            continue
        try:
            conn.execute(stmt)
        except sqlite3.OperationalError as e:
            # Only skip "already exists" errors for tables/indexes
            msg = str(e)
            if "already exists" in msg and ("table" in msg.lower() or "index" in msg.lower()):
                continue
            raise


def _strip_inline_comment(line: str) -> str:
    """Strip trailing -- comments, preserving string-internal --.
    Handles single-quoted strings, double-quoted identifiers, and '' escapes."""
    in_single = False
    in_double = False
    i = 0
    while i < len(line):
        c = line[i]
        if in_single:
            if c == "'":
                if i + 1 < len(line) and line[i + 1] == "'":
                    i += 2
                    continue
                in_single = False
        elif in_double:
            if c == '"':
                in_double = False
        else:
            if c == "'":
                in_single = True
            elif c == '"':
                in_double = True
            elif c == '-' and i + 1 < len(line) and line[i + 1] == '-':
                return line[:i]
        i += 1
    return line


def _split_statements(sql: str) -> list[str]:
    """Split SQL text into individual statements on semicolons,
    respecting string literals, block comments, and parenthesized expressions."""
    statements = []
    current = []
    depth = 0
    in_string = False
    in_block_comment = False
    i = 0
    while i < len(sql):
        c = sql[i]

        if in_block_comment:
            current.append(c)
            if c == '*' and i + 1 < len(sql) and sql[i + 1] == '/':
                current.append(sql[i + 1])
                i += 2
                in_block_comment = False
                continue
            i += 1
            continue

        if in_string:
            current.append(c)
            if c == "'":
                if i + 1 < len(sql) and sql[i + 1] == "'":
                    current.append(sql[i + 1])
                    i += 2
                    continue
                in_string = False
            i += 1
            continue

        if c == '/' and i + 1 < len(sql) and sql[i + 1] == '*':
            current.append(c)
            current.append(sql[i + 1])
            i += 2
            in_block_comment = True
            continue

        current.append(c)
        if c == "'":
            in_string = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif c == ";" and depth == 0:
            statements.append("".join(current))
            current = []
        i += 1
    remainder = "".join(current).strip()
    if remainder:
        statements.append(remainder)
    return statements