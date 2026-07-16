"""BFX-079 契约层接线防再犯静态扫描（H4）。

两类违规模式：
1. 死线收口 / 临时跳过审查类注释 —— BFX-079 方案 C 撤除的"死线策略"docstring
   若死灰复燃（produce-chapter 跳双盲审查、activate 当 seal），此 linter 命中。
2. 大纲裸拼产稿模式 —— brief_builder.py（V1 死代码，已删）若以新名复活，或
   任何从 outline 文件直接拼 brief 而不读四层 clause 的模式，此 linter 命中。

正则 + AST 双管：注释类用正则（docstring/string literal），代码模式用 AST
（函数名 + import + 字面量）。
"""
from __future__ import annotations

import ast
import re
from dataclasses import dataclass

# 死线收口 / 跳审查类注释特征词。命中即报——这类注释是 BFX-079 根因的信号：
# "死线策略跳过双盲审查/activate 当 seal/不落四层 clause"。
_DEADLINE_POLICY_PATTERNS = [
    re.compile(r"死线.{0,4}(跳过|skip|不落|不审|降级)", re.IGNORECASE),
    re.compile(r"dead.?line.{0,8}(skip|bypass|seal|degrade)", re.IGNORECASE),
    re.compile(r"activate.{0,6}(is|as).{0,4}seal", re.IGNORECASE),
    re.compile(r"不落.{0,6}四层.{0,4}clause", re.IGNORECASE),
    re.compile(r"临时.{0,4}(跳过|skip|降级)", re.IGNORECASE),
]

# 大纲裸拼产稿模式特征：函数名含 build_brief / make_brief 且参数含 outline_file /
# chapter_outline，或 import outline_parser 后直接拼 brief 字面量。
_BRIEF_FROM_OUTLINE_FUNC = re.compile(r"^(build|make|gen|assemble)_(chapter_)?brief$", re.IGNORECASE)


@dataclass(frozen=True)
class ContractRewireViolation:
    code: str
    message: str
    line: int


def lint_deadline_policy_docstrings(source: str, filename: str = "<test>") -> list[ContractRewireViolation]:
    """扫源码所有 string literal（含 docstring），命中死线收口/跳审查类注释即报。

    BFX-079 方案 C 已撤除此类 docstring；此 linter 防再犯。误报风险低——
    "死线策略跳过双盲审查"这类表述在正常代码中不应出现。
    """
    violations: list[ContractRewireViolation] = []
    tree = ast.parse(source, filename=filename)
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            for pat in _DEADLINE_POLICY_PATTERNS:
                if pat.search(node.value):
                    violations.append(ContractRewireViolation(
                        code="DEADLINE_POLICY_DOCSTRING",
                        message=(
                            "BFX-079: 死线收口/跳审查类注释死灰复燃——"
                            "produce-chapter 不得跳双盲审查、不得 activate 当 seal、"
                            "不得不落四层 clause。见 docs/contract-layer-rewire-design.md 方案 C。"
                        ),
                        line=getattr(node, "lineno", 0),
                    ))
                    break  # 一个 string 命中一次即可
    return violations


def lint_task_card_outline_injection(
    source: str, filename: str = "<test>"
) -> list[ContractRewireViolation]:
    """扫 TaskCardCompiler.compile_for_shot 接收或读取裸 outline 的模式。"""
    violations: list[ContractRewireViolation] = []
    tree = ast.parse(source, filename=filename)
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if node.name != "compile_for_shot":
            continue
        outline_args = [
            arg.arg
            for arg in (*node.args.args, *node.args.kwonlyargs)
            if "outline" in arg.arg.lower()
        ]
        outline_names = {
            child.id
            for child in ast.walk(node)
            if isinstance(child, ast.Name) and "outline" in child.id.lower()
        }
        if outline_args or outline_names:
            violations.append(ContractRewireViolation(
                code="TASK_CARD_OUTLINE_INJECTION",
                message=(
                    "BFX-083: compile_for_shot 不得接收或读取裸 outline；"
                    "TaskCard 只能由已落库 contract/context 编译。"
                ),
                line=node.lineno,
            ))
    return violations


def lint_brief_from_outline_pattern(source: str, filename: str = "<test>") -> list[ContractRewireViolation]:
    """AST 扫大纲裸拼产稿模式：函数名 build/make/gen_brief 且参数含 outline_file。

    brief 必须从 compile_brief(scene_contract_id) 编译四层 clause，不得从 outline
    文件直接拼。brief_builder.py 已删，此 linter 防以新名复活。
    """
    violations: list[ContractRewireViolation] = []
    tree = ast.parse(source, filename=filename)
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if not _BRIEF_FROM_OUTLINE_FUNC.match(node.name):
            continue
        # 参数名含 outline_file / chapter_outline / outline_path → 大纲裸拼模式
        arg_names = {a.arg for a in node.args.args}
        outline_args = {a for a in arg_names if "outline" in a.lower() and ("file" in a.lower() or "path" in a.lower() or "outline" == a.lower())}
        if outline_args:
            violations.append(ContractRewireViolation(
                code="BRIEF_FROM_OUTLINE_PATTERN",
                message=(
                    f"BFX-079: 函数 {node.name} 参数含大纲文件 ({sorted(outline_args)}) ——"
                    "brief 不得从大纲文件裸拼，必须从 compile_brief(scene_contract_id) 编译四层 clause。"
                    "brief_builder.py 已删，防以新名复活。"
                ),
                line=node.lineno,
            ))
    return violations
