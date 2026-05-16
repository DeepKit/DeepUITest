#!/usr/bin/env python3
"""
DeepSpec Conformance Test Runner

Usage:
    python run.py --reader "python deepspec_reader_cli.py" --level 1
    python run.py --reader "npx deepspec-reader-cli" --level 2

The reader CLI must support these commands:
    <reader> exists <path>         → {"exists": true/false}
    <reader> project <path>        → {"name": "...", "type": "...", ...}
    <reader> tree <path> <type>    → {"nodes": [...]}
    <reader> find <path> <id>      → {"node": {...}} or {"node": null}
    <reader> decisions <path>      → {"decisions": [...]}
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

FIXTURES = Path(__file__).parent / "fixtures"


def run_reader(reader_cmd: str, *args: str) -> dict:
    """Run the reader CLI and parse JSON output."""
    cmd = f"{reader_cmd} {' '.join(args)}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        return {"error": result.stderr.strip()}
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"error": f"Invalid JSON: {result.stdout[:200]}"}


class ConformanceRunner:
    def __init__(self, reader_cmd: str):
        self.reader = reader_cmd
        self.passed = 0
        self.failed = 0
        self.skipped = 0

    def test(self, name: str, condition: bool, detail: str = ""):
        if condition:
            self.passed += 1
            print(f"  ✓ {name}")
        else:
            self.failed += 1
            msg = f"  ✗ {name}"
            if detail:
                msg += f" — {detail}"
            print(msg)

    def skip(self, name: str, reason: str):
        self.skipped += 1
        print(f"  ○ {name} (skipped: {reason})")

    # --- Level 0 Tests ---

    def level_0(self):
        print("\n=== Level 0: Scanner Reader ===")
        fixture = FIXTURES / "valid-minimal"

        # t001
        result = run_reader(self.reader, "exists", str(fixture))
        self.test("t001_project_exists", result.get("exists") is True)

        # t002
        result = run_reader(self.reader, "project", str(fixture))
        self.test("t002_project_name", result.get("name") == "Minimal Test")
        self.test("t002_project_type", result.get("type") == "unknown")

        # t003
        self.test("t003_summary_nodes", result.get("total_nodes") == 1)

        # t004
        missing = FIXTURES / "nonexistent"
        result = run_reader(self.reader, "exists", str(missing))
        self.test("t004_missing_graceful", "error" not in result and result.get("exists") is False)

    # --- Level 1 Tests ---

    def level_1(self):
        print("\n=== Level 1: Tree Reader ===")
        fixture = FIXTURES / "valid-minimal"

        # t101
        result = run_reader(self.reader, "tree", str(fixture), "function")
        nodes = result.get("nodes", [])
        self.test("t101_function_tree", len(nodes) == 1)
        if nodes:
            self.test("t101_node_id", nodes[0].get("id") == "func-root")
            self.test("t101_node_title", nodes[0].get("title") == "Root")
            self.test("t101_node_kind", nodes[0].get("kind") == "capability")

        # t102
        result = run_reader(self.reader, "tree", str(fixture), "module")
        self.test("t102_module_tree_empty", result.get("nodes") == [])

        # t103
        result = run_reader(self.reader, "tree", str(fixture), "view")
        self.test("t103_view_tree_empty", result.get("nodes") == [])

        # t105 defaults
        result = run_reader(self.reader, "tree", str(fixture), "function")
        nodes = result.get("nodes", [])
        if nodes:
            node = nodes[0]
            self.test("t105_default_status", node.get("status") == "candidate")
            self.test("t105_default_confidence", node.get("confidence") == "medium")
            self.test("t105_default_source_layer", node.get("source_layer") == "ai_inferred")

        # t106 extension kinds
        ext_fixture = FIXTURES / "valid-extension-kinds"
        result = run_reader(self.reader, "tree", str(ext_fixture), "function")
        nodes = result.get("nodes", [])
        self.test("t106_extension_kind_no_error", "error" not in result)
        if nodes:
            self.test("t106_x_kind_preserved", nodes[0].get("kind") == "x_workflow")

        # t108 find by id
        result = run_reader(self.reader, "find", str(fixture), "func-root")
        node = result.get("node")
        self.test("t108_find_by_id", node is not None and node.get("id") == "func-root")

    # --- Level 2 Tests ---

    def level_2(self):
        print("\n=== Level 2: Full Reader ===")
        # Use seed-react-web which has all fact types
        fixture = Path(__file__).parent.parent / "examples" / "seed-react-web"

        result = run_reader(self.reader, "decisions", str(fixture))
        decisions = result.get("decisions", [])
        self.test("t204_decisions_loaded", len(decisions) >= 1)
        if decisions:
            self.test("t205_accepted_status", decisions[0].get("status") == "accepted")
            self.test("t206_ai_instruction", decisions[0].get("ai_instruction") is not None)

    def run(self, level: int):
        print(f"DeepSpec Conformance Test — Level {level}")
        print(f"Reader: {self.reader}")

        self.level_0()
        if level >= 1:
            self.level_1()
        if level >= 2:
            self.level_2()

        print(f"\n{'='*40}")
        print(f"Passed: {self.passed}  Failed: {self.failed}  Skipped: {self.skipped}")
        total = self.passed + self.failed
        if total > 0 and self.failed == 0:
            print(f"✓ CONFORMANT at Level {level}")
        else:
            print(f"✗ NOT CONFORMANT")
        return self.failed == 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="DeepSpec Conformance Test Runner")
    parser.add_argument("--reader", required=True, help="Reader CLI command")
    parser.add_argument("--level", type=int, default=1, choices=[0, 1, 2])
    args = parser.parse_args()

    runner = ConformanceRunner(args.reader)
    success = runner.run(args.level)
    sys.exit(0 if success else 1)
