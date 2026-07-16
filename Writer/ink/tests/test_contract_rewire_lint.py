"""H4 契约层接线静态扫描测试（BFX-079 防再犯）。

两类 linter（见 src/ink/linting/contract_rewire.py）：
- DEADLINE_POLICY_DOCSTRING：死线收口/跳审查类注释。
- BRIEF_FROM_OUTLINE_PATTERN：大纲裸拼产稿函数。

含全源码回归守卫：扫整个 src/ink 确认当前无违规，未来死灰复燃即 CI 红。
"""
from __future__ import annotations

from pathlib import Path

import pytest

from ink.linting.contract_rewire import (
    lint_brief_from_outline_pattern,
    lint_deadline_policy_docstrings,
    lint_task_card_outline_injection,
)

SRC_ROOT = Path(__file__).resolve().parents[1] / "src" / "ink"

# linter 自身文件描述这些违规模式，命中自己的正则——排除自指。
_SELF_FILES = {"contract_rewire.py"}


def violation_codes(violations) -> set[str]:
    return {v.code for v in violations}


# ---------- DEADLINE_POLICY_DOCSTRING ----------

def test_deadline_docstring_clean() -> None:
    source = "def f():\n    \"正常 docstring，无死线策略。\"\n    pass\n"
    assert lint_deadline_policy_docstrings(source) == []


def test_deadline_docstring_chinese_hits() -> None:
    source = "def f():\n    \"死线策略跳过双盲审查\"\n    pass\n"
    violations = lint_deadline_policy_docstrings(source)
    assert "DEADLINE_POLICY_DOCSTRING" in violation_codes(violations)


def test_deadline_docstring_english_hits() -> None:
    source = "def f():\n    'Dead-line policy skips the dual-blind review; activation is the seal.'\n    pass\n"
    violations = lint_deadline_policy_docstrings(source)
    assert "DEADLINE_POLICY_DOCSTRING" in violation_codes(violations)


def test_deadline_docstring_no_four_layer_hits() -> None:
    source = "def f():\n    \"死线收口用：不落四层 clause\"\n    pass\n"
    violations = lint_deadline_policy_docstrings(source)
    assert "DEADLINE_POLICY_DOCSTRING" in violation_codes(violations)


def test_deadline_docstring_temporary_skip_hits() -> None:
    source = "def f():\n    \"临时跳过审查\"\n    pass\n"
    violations = lint_deadline_policy_docstrings(source)
    assert "DEADLINE_POLICY_DOCSTRING" in violation_codes(violations)


# ---------- BRIEF_FROM_OUTLINE_PATTERN ----------

def test_brief_from_outline_clean_compile_brief_ok() -> None:
    """compile_brief 从契约 cid 编译，参数无 outline_file → 不报。"""
    source = "def compile_brief(conn, scene_contract_id):\n    return ''\n"
    assert lint_brief_from_outline_pattern(source) == []


def test_brief_from_outline_pattern_hits() -> None:
    """build_chapter_brief(outline_file, chapter) → 命中。"""
    source = "def build_chapter_brief(outline_file, chapter):\n    return ''\n"
    violations = lint_brief_from_outline_pattern(source)
    assert "BRIEF_FROM_OUTLINE_PATTERN" in violation_codes(violations)


def test_brief_from_outline_make_brief_hits() -> None:
    source = "def make_brief(outline_path, chapter):\n    return ''\n"
    violations = lint_brief_from_outline_pattern(source)
    assert "BRIEF_FROM_OUTLINE_PATTERN" in violation_codes(violations)


def test_brief_from_outline_no_outline_arg_clean() -> None:
    """build_brief 但参数不含 outline_file → 不报（可能是合法 builder）。"""
    source = "def build_brief(clauses):\n    return ''\n"
    assert lint_brief_from_outline_pattern(source) == []


# ---------- 全源码回归守卫 ----------

def _all_py_sources() -> list[Path]:
    return sorted(p for p in SRC_ROOT.rglob("*.py") if p.name not in _SELF_FILES)


@pytest.mark.parametrize("path", _all_py_sources(), ids=lambda p: str(p.relative_to(SRC_ROOT)))
def test_no_deadline_policy_docstring_in_src(path: Path) -> None:
    """全源码不得含死线收口/跳审查类注释（BFX-079 方案 C 防再犯）。"""
    source = path.read_text(encoding="utf-8")
    violations = lint_deadline_policy_docstrings(source, str(path))
    assert violations == [], (
        f"{path.relative_to(SRC_ROOT)} 命中 DEADLINE_POLICY_DOCSTRING：{[v.line for v in violations]}"
    )


@pytest.mark.parametrize("path", _all_py_sources(), ids=lambda p: str(p.relative_to(SRC_ROOT)))
def test_no_brief_from_outline_in_src(path: Path) -> None:
    """全源码不得含大纲裸拼产稿函数（brief_builder 防死灰复燃）。"""
    source = path.read_text(encoding="utf-8")
    violations = lint_brief_from_outline_pattern(source, str(path))
    assert violations == [], (
        f"{path.relative_to(SRC_ROOT)} 命中 BRIEF_FROM_OUTLINE_PATTERN：{[v.line for v in violations]}"
    )


def test_task_card_outline_argument_hits() -> None:
    source = (
        "class TaskCardCompiler:\n"
        "    def compile_for_shot(self, shot_id, run_id, outline_text):\n"
        "        return outline_text\n"
    )
    violations = lint_task_card_outline_injection(source)
    assert violation_codes(violations) == {"TASK_CARD_OUTLINE_INJECTION"}


def test_task_card_outline_local_hits() -> None:
    source = (
        "class TaskCardCompiler:\n"
        "    def compile_for_shot(self, shot_id, run_id):\n"
        "        outline = load_winner()\n"
        "        return outline\n"
    )
    violations = lint_task_card_outline_injection(source)
    assert violation_codes(violations) == {"TASK_CARD_OUTLINE_INJECTION"}


@pytest.mark.parametrize("path", _all_py_sources(), ids=lambda p: str(p.relative_to(SRC_ROOT)))
def test_no_task_card_outline_injection_in_src(path: Path) -> None:
    """TaskCard 编译不得接收或读取裸 outline。"""
    source = path.read_text(encoding="utf-8")
    violations = lint_task_card_outline_injection(source, str(path))
    assert violations == [], (
        f"{path.relative_to(SRC_ROOT)} 命中 TASK_CARD_OUTLINE_INJECTION："
        f"{[v.line for v in violations]}"
    )
