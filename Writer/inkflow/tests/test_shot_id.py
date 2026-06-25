"""Tests for composite shot_id module."""

from __future__ import annotations

import pytest

from inkflow.utils.shot_id import (
    generate,
    parse,
    is_valid,
    is_legacy_ulid,
    to_layer_key,
    sort_key,
    format_display,
    ShotIdParts,
)


class TestGenerate:
    def test_basic(self):
        assert generate("v01.c02", 3) == "v01.c02.s03"

    def test_single_digit(self):
        assert generate("v01.c01", 1) == "v01.c01.s01"

    def test_double_digit(self):
        assert generate("v02.c10", 15) == "v02.c10.s15"

    def test_invalid_layer_key_no_dot(self):
        with pytest.raises(ValueError, match="Invalid layer_key"):
            generate("v01c02", 1)

    def test_invalid_layer_key_wrong_prefix(self):
        with pytest.raises(ValueError, match="Invalid layer_key"):
            generate("x01.c02", 1)

    def test_invalid_layer_key_single_digit(self):
        with pytest.raises(ValueError, match="Invalid layer_key"):
            generate("v1.c2", 1)

    def test_invalid_shot_index_zero(self):
        with pytest.raises(ValueError, match="shot_index must be >= 1"):
            generate("v01.c01", 0)

    def test_invalid_shot_index_negative(self):
        with pytest.raises(ValueError, match="shot_index must be >= 1"):
            generate("v01.c01", -1)


class TestParse:
    def test_basic(self):
        result = parse("v01.c02.s03")
        assert result == ShotIdParts("v01", "c02", "s03", "v01.c02")

    def test_first_shot(self):
        result = parse("v01.c01.s01")
        assert result.volume == "v01"
        assert result.chapter == "c01"
        assert result.section == "s01"
        assert result.layer_key == "v01.c01"

    def test_large_numbers(self):
        result = parse("v99.c99.s99")
        assert result.volume == "v99"

    def test_invalid_format(self):
        with pytest.raises(ValueError, match="Invalid shot_id"):
            parse("v01.c02")

    def test_invalid_format_ulid(self):
        with pytest.raises(ValueError, match="Invalid shot_id"):
            parse("01KVJ1QVDRDGFX9J73459RE11H")

    def test_invalid_format_single_digit(self):
        with pytest.raises(ValueError, match="Invalid shot_id"):
            parse("v1.c2.s3")


class TestIsValid:
    def test_valid(self):
        assert is_valid("v01.c02.s03") is True

    def test_valid_first(self):
        assert is_valid("v01.c01.s01") is True

    def test_invalid_layer_key_only(self):
        assert is_valid("v01.c02") is False

    def test_invalid_ulid(self):
        assert is_valid("01KVJ1QVDRDGFX9J73459RE11H") is False

    def test_invalid_empty(self):
        assert is_valid("") is False

    def test_invalid_extra(self):
        assert is_valid("v01.c02.s03.x") is False


class TestIsLegacyUlid:
    def test_legacy_ulid(self):
        assert is_legacy_ulid("01KVJ1QVDRDGFX9J73459RE11H") is True

    def test_not_legacy(self):
        assert is_legacy_ulid("v01.c02.s03") is False

    def test_wrong_length(self):
        assert is_legacy_ulid("01KVJ1QVDRDGFX9J73459RE11") is False  # 25 chars

    def test_non_alnum(self):
        assert is_legacy_ulid("v01.c02.s03") is False


class TestToLayerKey:
    def test_basic(self):
        assert to_layer_key("v01.c02.s03") == "v01.c02"

    def test_first(self):
        assert to_layer_key("v01.c01.s01") == "v01.c01"


class TestSortKey:
    def test_basic(self):
        assert sort_key("v01.c02.s03") == (1, 2, 3)

    def test_first(self):
        assert sort_key("v01.c01.s01") == (1, 1, 1)

    def test_sorting_order(self):
        ids = ["v01.c02.s01", "v01.c01.s02", "v01.c01.s01", "v02.c01.s01"]
        sorted_ids = sorted(ids, key=sort_key)
        assert sorted_ids == [
            "v01.c01.s01",
            "v01.c01.s02",
            "v01.c02.s01",
            "v02.c01.s01",
        ]

    def test_dictionary_order_matches_sort_key(self):
        """字典序和 sort_key 排序结果一致（零填充保证）。"""
        ids = ["v01.c02.s01", "v01.c01.s10", "v01.c01.s02", "v01.c01.s01"]
        assert sorted(ids) == sorted(ids, key=sort_key)


class TestFormatDisplay:
    def test_basic(self):
        assert format_display("v01.c02.s03") == "第1卷 第2章 第3节"

    def test_first(self):
        assert format_display("v01.c01.s01") == "第1卷 第1章 第1节"

    def test_large(self):
        assert format_display("v12.c05.s20") == "第12卷 第5章 第20节"
