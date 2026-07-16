"""Contract DTOs and schemas.

SPW 防绕过 H1：brief 由 ``brief_compiler.compile_brief`` 从四层 clause 编译，
是契约唯一受控入口。详见 ``docs/contract-layer-rewire-design.md``。
"""
from ink.contract.brief_compiler import compile_brief

__all__ = ["compile_brief"]
