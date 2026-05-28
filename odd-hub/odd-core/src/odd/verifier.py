"""
契约验证�?- 检查代码是否符合契约要�?"""

import re
from typing import Optional


class ContractVerifier:
    """对代码进行静态模式检�?""

    def verify(self, code: str, verification_hints: dict) -> dict:
        checks = []
        all_passed = True
        critical_failed = False

        for rule in verification_hints.get("must_contain_any", []):
            patterns = rule.get("patterns", [])
            reason = rule.get("reason", "")
            severity = rule.get("severity", "medium")
            found: Optional[str] = None
            for pattern in patterns:
                if pattern.lower() in code.lower():
                    found = pattern
                    break
            passed = found is not None
            if not passed:
                all_passed = False
                if severity == "critical":
                    critical_failed = True
            checks.append({"type": "must_contain_any", "rule": reason, "severity": severity, "passed": passed, "found": found})

        for rule in verification_hints.get("must_not_contain", []):
            patterns = rule.get("patterns", [])
            reason = rule.get("reason", "")
            severity = rule.get("severity", "medium")
            found = None
            for pattern in patterns:
                if pattern in code:
                    found = pattern
                    break
            passed = found is None
            if not passed:
                all_passed = False
                if severity == "critical":
                    critical_failed = True
            checks.append({"type": "must_not_contain", "rule": reason, "severity": severity, "passed": passed, "found": found})

        for rule in verification_hints.get("should_contain", []):
            patterns = rule.get("patterns", [])
            reason = rule.get("reason", "")
            found = None
            for pattern in patterns:
                if pattern in code:
                    found = pattern
                    break
            checks.append({"type": "should_contain", "rule": reason, "severity": "low", "passed": found is not None, "found": found})

        return {
            "passed": all_passed and not critical_failed,
            "critical_failed": critical_failed,
            "checks": checks,
        }
