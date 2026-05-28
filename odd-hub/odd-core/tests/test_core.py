"""
Tests for odd-core verifier and sealer
"""

import json
import tempfile
from pathlib import Path

import pytest

from odd.verifier import ContractVerifier
from odd.sealer import SealManager


# ── ContractVerifier ──────────────────────────────────────────────────────────

HINTS_BASIC = {
    "must_contain_any": [
        {"patterns": ["def ", "class "], "reason": "必须包含函数或类定义", "severity": "critical"},
    ],
    "must_not_contain": [
        {"patterns": ["eval(", "exec("], "reason": "禁止使用 eval/exec", "severity": "critical"},
    ],
    "should_contain": [
        {"patterns": ["\"\"\"", "'''"], "reason": "建议添加 docstring", "severity": "low"},
    ],
}

GOOD_CODE = '''
def add(a, b):
    """Add two numbers."""
    return a + b
'''

BAD_CODE = '''
result = eval("1 + 1")
'''


def test_verify_pass():
    result = ContractVerifier().verify(GOOD_CODE, HINTS_BASIC)
    assert result["passed"] is True
    assert result["critical_failed"] is False


def test_verify_fail_must_not_contain():
    result = ContractVerifier().verify(BAD_CODE, HINTS_BASIC)
    assert result["passed"] is False
    assert result["critical_failed"] is True


def test_verify_empty_hints():
    result = ContractVerifier().verify(GOOD_CODE, {})
    assert result["passed"] is True
    assert result["checks"] == []


def test_verify_checks_count():
    result = ContractVerifier().verify(GOOD_CODE, HINTS_BASIC)
    assert len(result["checks"]) == 3


# ── SealManager ───────────────────────────────────────────────────────────────

def test_seal_creates_file():
    contract = {"name": "test", "verification_hints": {}}
    code = "def foo(): pass"
    verification = {"passed": True, "critical_failed": False, "checks": []}

    with tempfile.TemporaryDirectory() as tmpdir:
        seal_dir = Path(tmpdir) / "seals"
        record = SealManager().seal(contract, code, verification, seal_dir)

        assert seal_dir.exists()
        assert Path(record["file"]).exists()
        assert len(record["seal_id"]) == 36  # UUID
        assert len(record["integrity"]) == 64  # SHA-256 hex


def test_seal_integrity_deterministic():
    contract = {"name": "test"}
    code = "def foo(): pass"
    verification = {"passed": True}

    with tempfile.TemporaryDirectory() as tmpdir:
        r1 = SealManager().seal(contract, code, verification, Path(tmpdir) / "s1")
        r2 = SealManager().seal(contract, code, verification, Path(tmpdir) / "s2")
        # 相同输入，哈希应相同（seal_id 不同，但 integrity 相同�?        assert r1["integrity"] == r2["integrity"]


def test_seal_record_structure():
    contract = {"name": "test"}
    code = "x = 1"
    verification = {"passed": True}

    with tempfile.TemporaryDirectory() as tmpdir:
        seal_dir = Path(tmpdir) / "seals"
        record = SealManager().seal(contract, code, verification, seal_dir)
        data = json.loads(Path(record["file"]).read_text(encoding="utf-8"))

        assert "seal_id" in data
        assert "timestamp" in data
        assert "hashes" in data
        assert "integrity" in data
        assert set(data["hashes"].keys()) == {"contract", "code", "verification"}
