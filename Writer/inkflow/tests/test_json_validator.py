"""Tests for JSON validation utility (DB-7)."""

from __future__ import annotations

import pytest

from inkflow.utils.json_validator import validate_json, safe_json_dumps


class TestValidateJson:
    """DB-7: JSON validation for core table fields."""

    def test_valid_json_dict(self):
        assert validate_json('{"a": 1}', "test") == {"a": 1}

    def test_valid_json_list(self):
        assert validate_json("[1, 2, 3]", "test") == [1, 2, 3]

    def test_none_returns_none(self):
        assert validate_json(None, "test") is None

    def test_already_parsed(self):
        assert validate_json({"a": 1}, "test") == {"a": 1}

    def test_invalid_json_raises(self):
        with pytest.raises(ValueError, match="Invalid JSON"):
            validate_json("{not valid}", "test_field")

    def test_empty_string(self):
        with pytest.raises(ValueError, match="Invalid JSON"):
            validate_json("", "test")


class TestSafeJsonDumps:
    """DB-7: Safe JSON serialization."""

    def test_valid_dict(self):
        assert safe_json_dumps({"a": 1}, "test") == '{"a": 1}'

    def test_none_returns_none(self):
        assert safe_json_dumps(None, "test") is None

    def test_unserializable_raises(self):
        import sys
        # Functions are not serializable
        with pytest.raises(ValueError, match="Cannot serialize"):
            safe_json_dumps({"fn": sys.exit}, "test")