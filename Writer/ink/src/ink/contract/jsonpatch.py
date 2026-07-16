"""RFC 6902 JSON-Patch 子集（点分路径版）。

支持 ``add`` / ``remove`` / ``replace`` / ``move`` 四个操作（不实现 ``copy``/``test``）。
路径采用点分形式（如 ``identity.title``），与 :mod:`ink.contract.fields` 和
``writing_source_coverage_matrix.contract_field_path`` 列对齐——不使用 RFC 6902 的
``/`` 前缀 JSON Pointer，以便与 coverage 矩阵一致。

纯标准库实现，不原地修改输入 doc；任一 op 失败抛 :class:`~ink.errors.ContractPatchError`。
"""
from __future__ import annotations

import copy
from typing import Any

from ink.errors import ContractPatchError

_SUPPORTED_OPS = {"add", "remove", "replace", "move"}


def apply_patch(doc: dict[str, Any], patch: list[dict[str, Any]]) -> dict[str, Any]:
    """把 patch 依次应用到 doc 的深拷贝上，返回新 dict。

    每个 op 形如 ``{"op": "add", "path": "identity.title", "value": "X"}``。
    ``move`` 需 ``from`` 字段。任一 op 失败整体抛 ``ContractPatchError``。
    """
    if not isinstance(doc, dict):
        raise ContractPatchError("patch target must be a dict")
    if not isinstance(patch, list):
        raise ContractPatchError("patch must be a list of ops")
    result = copy.deepcopy(doc)
    for i, op in enumerate(patch):
        if not isinstance(op, dict):
            raise ContractPatchError(f"op #{i} must be a dict")
        kind = op.get("op")
        if kind not in _SUPPORTED_OPS:
            raise ContractPatchError(f"op #{i} has unsupported op: {kind!r}")
        path = op.get("path")
        if not isinstance(path, str) or not path:
            raise ContractPatchError(f"op #{i} ({kind}) missing path")
        if kind == "add":
            _set_path(result, path, op.get("value"), create_missing=True)
        elif kind == "replace":
            _set_path(result, path, op.get("value"), create_missing=False)
        elif kind == "remove":
            _remove_path(result, path)
        elif kind == "move":
            src = op.get("from")
            if not isinstance(src, str) or not src:
                raise ContractPatchError(f"op #{i} (move) missing from")
            value = _pop_path(result, src)
            _set_path(result, path, value, create_missing=True)
    return result


def patch_paths(patch: list[dict[str, Any]]) -> list[str]:
    """提取 patch 中所有 op 的 ``path``（去重保序），用于 coverage 更新。"""
    seen: list[str] = []
    for op in patch:
        if isinstance(op, dict):
            p = op.get("path")
            if isinstance(p, str) and p and p not in seen:
                seen.append(p)
    return seen


def _split(path: str) -> list[str]:
    return [seg for seg in path.split(".") if seg]


def _navigate(doc: dict[str, Any], parts: list[str], *, create_missing: bool) -> dict[str, Any]:
    """沿 parts 导航到父节点，返回可写叶子父 dict。"""
    node: dict[str, Any] = doc
    for seg in parts[:-1]:
        if seg not in node:
            if create_missing:
                node[seg] = {}
            else:
                raise ContractPatchError(f"path segment not found: {seg}")
        child = node[seg]
        if not isinstance(child, dict):
            if create_missing:
                node[seg] = {}
            else:
                raise ContractPatchError(f"path segment is not a dict: {seg}")
        node = node[seg]
    return node


def _set_path(doc: dict[str, Any], path: str, value: Any, *, create_missing: bool) -> None:
    parts = _split(path)
    if not parts:
        raise ContractPatchError(f"empty path: {path}")
    parent = _navigate(doc, parts, create_missing=create_missing)
    leaf = parts[-1]
    if not create_missing and leaf not in parent:
        raise ContractPatchError(f"replace target not found: {path}")
    parent[leaf] = value


def _remove_path(doc: dict[str, Any], path: str) -> None:
    parts = _split(path)
    if not parts:
        raise ContractPatchError(f"empty path: {path}")
    parent = _navigate(doc, parts, create_missing=False)
    leaf = parts[-1]
    if leaf not in parent:
        raise ContractPatchError(f"remove target not found: {path}")
    del parent[leaf]


def _pop_path(doc: dict[str, Any], path: str) -> Any:
    parts = _split(path)
    if not parts:
        raise ContractPatchError(f"empty path: {path}")
    parent = _navigate(doc, parts, create_missing=False)
    leaf = parts[-1]
    if leaf not in parent:
        raise ContractPatchError(f"move source not found: {path}")
    return parent.pop(leaf)
