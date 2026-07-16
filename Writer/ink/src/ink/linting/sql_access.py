from __future__ import annotations

import ast
from dataclasses import dataclass
from pathlib import Path


TEXT_REVISIONS_TABLE = "writing_shot_revisions"
SCENE_FIRST_TERMINAL_AUTHORITY_TABLES = frozenset(
    {
        "writing_scene_contracts",
        "writing_chapter_candidate_branch_versions",
        "writing_selection_decisions",
        "writing_chapter_snapshots",
        "writing_chapter_snapshot_scenes",
        "writing_chapter_heads",
    }
)
SQL_CALLS = {"execute", "executemany", "executescript"}
SQL_WHITELIST_PARTS = {
    "core/text_repository.py",
    "schema.py",
}
SCENE_FIRST_TERMINAL_AUTHORITY_WHITELIST_PARTS = {
    "core/chapter_snapshot_repository.py",
    "core/scene_repository.py",
    "core/scene_stale_propagation.py",
    "schema.py",
}
SCENE_FIRST_TERMINAL_AUTHORITY_WRITE_KEYWORDS = (
    "insert into",
    "update",
    "delete from",
    "replace into",
)


@dataclass(frozen=True)
class SqlAccessViolation:
    code: str
    message: str
    line: int


def lint_sql_access(source: str, filename: str) -> list[SqlAccessViolation]:
    tree = ast.parse(source)
    visitor = _SqlAccessVisitor(filename)
    visitor.visit(tree)
    return visitor.violations


class _SqlAccessVisitor(ast.NodeVisitor):
    def __init__(self, filename: str) -> None:
        self.filename = filename.replace("\\", "/")
        self.violations: list[SqlAccessViolation] = []

    def visit_Call(self, node: ast.Call) -> None:
        call_name = _call_name(node.func)
        if call_name.endswith(".query"):
            self._check_orm_query(node)
        if call_name.split(".")[-1] in SQL_CALLS and node.args:
            self._check_sql_arg(node.args[0], node.lineno)
        self.generic_visit(node)

    def _check_orm_query(self, node: ast.Call) -> None:
        for arg in node.args:
            name = _call_name(arg)
            if "ShotRevision" in name or TEXT_REVISIONS_TABLE in name:
                self.violations.append(
                    SqlAccessViolation("ORM_ACCESS", "ORM access to shot revisions is forbidden", node.lineno)
                )

    def _check_sql_arg(self, arg: ast.AST, line: int) -> None:
        if isinstance(arg, ast.JoinedStr):
            self.violations.append(
                SqlAccessViolation("STRING_CONCATENATED_SQL", "f-string SQL is forbidden", line)
            )
            return
        if isinstance(arg, ast.BinOp) and isinstance(arg.op, ast.Add):
            self.violations.append(
                SqlAccessViolation("DYNAMIC_TABLE_NAME", "string-concatenated SQL is forbidden", line)
            )
            return
        if not isinstance(arg, ast.Constant) or not isinstance(arg.value, str):
            return

        sql = arg.value.lower()
        if TEXT_REVISIONS_TABLE in sql and not self._is_whitelisted(SQL_WHITELIST_PARTS):
            self.violations.append(
                SqlAccessViolation(
                    "TEXT_REVISIONS_ACCESS",
                    f"{TEXT_REVISIONS_TABLE} may only be accessed through core/text_repository.py",
                    line,
                )
            )

        if self._is_whitelisted(SCENE_FIRST_TERMINAL_AUTHORITY_WHITELIST_PARTS):
            return

        protected_tables = sorted(
            table for table in SCENE_FIRST_TERMINAL_AUTHORITY_TABLES if table in sql
        )
        writes_authority = protected_tables and any(
            keyword in sql for keyword in SCENE_FIRST_TERMINAL_AUTHORITY_WRITE_KEYWORDS
        )
        if writes_authority and not self._is_whitelisted(
            SCENE_FIRST_TERMINAL_AUTHORITY_WHITELIST_PARTS
        ):
            tables = ", ".join(protected_tables)
            self.violations.append(
                SqlAccessViolation(
                    "SCENE_FIRST_AUTHORITY_WRITE",
                    f"Scene-first authority tables may only be written through "
                    f"designated repositories/schema: {tables}",
                    line,
                )
            )

    def _is_whitelisted(self, whitelist_parts: set[str]) -> bool:
        if "/tests/" in f"/{self.filename}" or self.filename.startswith("tests/"):
            return True
        return any(self.filename.endswith(part) for part in whitelist_parts)


def _call_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = _call_name(node.value)
        return f"{parent}.{node.attr}" if parent else node.attr
    return ""
