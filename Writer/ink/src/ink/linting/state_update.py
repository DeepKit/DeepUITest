from __future__ import annotations

import ast
from dataclasses import dataclass


@dataclass(frozen=True)
class StateUpdateViolation:
    code: str
    message: str
    line: int


def lint_state_updates(source: str, filename: str) -> list[StateUpdateViolation]:
    if filename.replace("\\", "/").endswith("core/state_machine.py"):
        return []
    tree = ast.parse(source)
    violations: list[StateUpdateViolation] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and _call_name(node.func).split(".")[-1] in {"execute", "executemany"}:
            if not node.args:
                continue
            sql = node.args[0]
            if isinstance(sql, ast.Constant) and isinstance(sql.value, str):
                normalized = " ".join(sql.value.lower().split())
                if "update writing_shots" in normalized and "status" in normalized:
                    violations.append(
                        StateUpdateViolation(
                            "DIRECT_SHOT_STATUS_UPDATE",
                            "writing_shots.status may only be updated by core/state_machine.py",
                            node.lineno,
                        )
                    )
    return violations


def _call_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = _call_name(node.value)
        return f"{parent}.{node.attr}" if parent else node.attr
    return ""
