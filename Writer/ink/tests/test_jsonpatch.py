"""JSON-Patch 纯单元测试：apply_patch / patch_paths 的边界与语义。"""
from __future__ import annotations

import pytest

from ink.contract.jsonpatch import apply_patch, patch_paths
from ink.errors import ContractPatchError


class TestApplyPatch:
    def test_empty_patch_returns_doc_unchanged(self) -> None:
        doc = {"key": "value"}
        result = apply_patch(doc, [])
        assert result == doc
        assert result is not doc  # 深拷贝

    def test_add_top_level_field(self) -> None:
        result = apply_patch({"a": 1}, [{"op": "add", "path": "b", "value": 2}])
        assert result == {"a": 1, "b": 2}

    def test_replace_existing_field(self) -> None:
        result = apply_patch(
            {"title": "old"}, [{"op": "replace", "path": "title", "value": "new"}],
        )
        assert result == {"title": "new"}

    def test_replace_missing_field_raises(self) -> None:
        with pytest.raises(ContractPatchError, match="replace target not found"):
            apply_patch({"a": 1}, [{"op": "replace", "path": "b", "value": 2}])

    def test_remove_field(self) -> None:
        result = apply_patch({"a": 1, "b": 2}, [{"op": "remove", "path": "a"}])
        assert result == {"b": 2}

    def test_remove_missing_field_raises(self) -> None:
        with pytest.raises(ContractPatchError, match="remove target not found"):
            apply_patch({"a": 1}, [{"op": "remove", "path": "b"}])

    def test_move_field(self) -> None:
        result = apply_patch(
            {"a": {"x": 1}, "b": {}},
            [{"op": "move", "from": "a.x", "path": "b.y"}],
        )
        assert result == {"a": {}, "b": {"y": 1}}

    def test_move_missing_source_raises(self) -> None:
        with pytest.raises(ContractPatchError, match="move source not found"):
            apply_patch({"a": 1}, [{"op": "move", "from": "z", "path": "b"}])

    def test_nested_path_add(self) -> None:
        result = apply_patch(
            {"identity": {"title": "T"}},
            [{"op": "add", "path": "identity.sub", "value": "V"}],
        )
        assert result == {"identity": {"title": "T", "sub": "V"}}

    def test_nested_path_create_missing_intermediates(self) -> None:
        """add 模式自动创建中间 dict。"""
        result = apply_patch(
            {},
            [{"op": "add", "path": "a.b.c", "value": "deep"}],
        )
        assert result == {"a": {"b": {"c": "deep"}}}

    def test_multiple_ops(self) -> None:
        result = apply_patch(
            {"x": 1, "y": 2},
            [
                {"op": "remove", "path": "x"},
                {"op": "replace", "path": "y", "value": 99},
                {"op": "add", "path": "z", "value": 3},
            ],
        )
        assert result == {"y": 99, "z": 3}

    def test_invalid_op_raises(self) -> None:
        with pytest.raises(ContractPatchError, match="unsupported op"):
            apply_patch({"a": 1}, [{"op": "copy", "path": "a", "from": "b"}])

    def test_non_dict_doc_raises(self) -> None:
        with pytest.raises(ContractPatchError, match="target must be a dict"):
            apply_patch([], [])  # type: ignore[arg-type]


class TestPatchPaths:
    def test_extracts_unique_paths(self) -> None:
        paths = patch_paths([
            {"op": "replace", "path": "a"},
            {"op": "add", "path": "b"},
            {"op": "remove", "path": "a"},
        ])
        assert paths == ["a", "b"]

    def test_skips_invalid_ops(self) -> None:
        paths = patch_paths([
            {"op": "replace", "path": "x"},
            {"op": "replace"},  # missing path
            "not a dict",
        ])
        assert paths == ["x"]

    def test_empty_patch_returns_empty(self) -> None:
        assert patch_paths([]) == []
