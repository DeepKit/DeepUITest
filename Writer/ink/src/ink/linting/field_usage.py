from __future__ import annotations

import ast
from dataclasses import dataclass


@dataclass(frozen=True)
class FieldUsageViolation:
    code: str
    message: str
    line: int


def requires_full_field_consumption(func):
    return func


def lint_field_usage(source: str, required_fields_by_type: dict[str, set[str]] | None = None) -> list[FieldUsageViolation]:
    tree = ast.parse(source)
    visitor = _FieldUsageVisitor(required_fields_by_type or {})
    visitor.visit(tree)
    return visitor.violations


class _FieldUsageVisitor(ast.NodeVisitor):
    def __init__(self, required_fields_by_type: dict[str, set[str]]) -> None:
        self.required_fields_by_type = required_fields_by_type
        self.violations: list[FieldUsageViolation] = []

    def visit_Call(self, node: ast.Call) -> None:
        name = _call_name(node.func)
        if name in {"getattr", "vars", "dataclasses.asdict", "asdict"}:
            self.violations.append(
                FieldUsageViolation(
                    "DYNAMIC_DATACLASS_ACCESS",
                    f"dynamic dataclass access is forbidden: {name}",
                    node.lineno,
                )
            )
        self.generic_visit(node)

    def visit_Attribute(self, node: ast.Attribute) -> None:
        if node.attr == "__dict__":
            self.violations.append(
                FieldUsageViolation(
                    "DYNAMIC_DATACLASS_ACCESS",
                    "dynamic dataclass access is forbidden: __dict__",
                    node.lineno,
                )
            )
        self.generic_visit(node)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        if _has_full_consumption_marker(node):
            self._check_full_field_consumption(node)
        self.generic_visit(node)

    def _check_full_field_consumption(self, node: ast.FunctionDef) -> None:
        if not node.args.args:
            return
        first_arg = node.args.args[0]
        type_name = _annotation_name(first_arg.annotation)
        if not type_name or type_name not in self.required_fields_by_type:
            return

        used_fields = {
            child.attr
            for child in ast.walk(node)
            if isinstance(child, ast.Attribute)
            and isinstance(child.value, ast.Name)
            and child.value.id == first_arg.arg
        }
        missing = sorted(self.required_fields_by_type[type_name] - used_fields)
        if missing:
            self.violations.append(
                FieldUsageViolation(
                    "MISSING_FIELD_CONSUMPTION",
                    f"{node.name} does not consume {type_name} fields: {', '.join(missing)}",
                    node.lineno,
                )
            )


def _has_full_consumption_marker(node: ast.FunctionDef) -> bool:
    return any(_call_name(decorator) == "requires_full_field_consumption" for decorator in node.decorator_list)


def _annotation_name(node: ast.AST | None) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return None


def _call_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = _call_name(node.value)
        return f"{parent}.{node.attr}" if parent else node.attr
    if isinstance(node, ast.Call):
        return _call_name(node.func)
    return ""
