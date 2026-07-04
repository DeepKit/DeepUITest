from __future__ import annotations

import ast
from dataclasses import dataclass


FORBIDDEN_IMPORT_ROOTS = {
    "openai",
    "anthropic",
    "google.generativeai",
    "dashscope",
}


@dataclass(frozen=True)
class LLMAccessViolation:
    code: str
    message: str
    line: int


def lint_llm_access(source: str, filename: str) -> list[LLMAccessViolation]:
    normalized = filename.replace("\\", "/")
    if normalized.endswith("core/llm_gateway.py") or normalized.startswith("tests/") or "/tests/" in normalized:
        return []

    tree = ast.parse(source)
    violations: list[LLMAccessViolation] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                root = _forbidden_root(alias.name)
                if root:
                    violations.append(
                        LLMAccessViolation("DIRECT_LLM_SDK_IMPORT", f"direct provider import is forbidden: {root}", node.lineno)
                    )
        elif isinstance(node, ast.ImportFrom) and node.module:
            root = _forbidden_root(node.module)
            if root:
                violations.append(
                    LLMAccessViolation("DIRECT_LLM_SDK_IMPORT", f"direct provider import is forbidden: {root}", node.lineno)
                )
    return violations


def _forbidden_root(module_name: str) -> str | None:
    for root in FORBIDDEN_IMPORT_ROOTS:
        if module_name == root or module_name.startswith(f"{root}."):
            return root
    return None
