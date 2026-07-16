from __future__ import annotations

import pytest

from ink.cli import _parse_int_ranges


def test_parse_int_ranges_deduplicates_and_sorts() -> None:
    assert _parse_int_ranges("5,3-4,4,8") == [3, 4, 5, 8]


@pytest.mark.parametrize("raw", ["", "0", "4-2", "x", "2-x"])
def test_parse_int_ranges_rejects_invalid_input(raw: str) -> None:
    with pytest.raises(SystemExit):
        _parse_int_ranges(raw)
