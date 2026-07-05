from __future__ import annotations

import ast
from dataclasses import dataclass
from pathlib import Path


SHOT_ORCHESTRATOR_FILES = {
    "outline_orchestrator.py",
    "write_orchestrator.py",
    "hard_gate_orchestrator.py",
    "jury_orchestrator.py",
    "gate_orchestrator.py",
    "polish_orchestrator.py",
    "soft_seal_orchestrator.py",
}


@dataclass(frozen=True)
class OrchestratorSignatureViolation:
    code: str
    message: str
    line: int


def lint_shot_orchestrator_source(source: str, filename: str) -> list[OrchestratorSignatureViolation]:
    if Path(filename).name not in SHOT_ORCHESTRATOR_FILES:
        return []

    tree = ast.parse(source)
    violations: list[OrchestratorSignatureViolation] = []
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and not node.name.startswith("_"):
            arg_names = [arg.arg for arg in node.args.args]
            if arg_names != ["shot_id", "run_id"] or node.args.vararg or node.args.kwarg:
                violations.append(
                    OrchestratorSignatureViolation(
                        "SHOT_ORCHESTRATOR_SIGNATURE",
                        f"{filename}:{node.name} must accept exactly (shot_id, run_id)",
                        node.lineno,
                    )
                )
            for arg in node.args.args:
                annotation = _annotation_name(arg.annotation)
                if annotation and annotation not in {"int", "str"}:
                    violations.append(
                        OrchestratorSignatureViolation(
                            "SHOT_ORCHESTRATOR_DATACLASS_PARAM",
                            f"{filename}:{node.name} must not accept upstream dataclass parameters",
                            node.lineno,
                        )
                    )
    return violations


def _annotation_name(node: ast.AST | None) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return None
