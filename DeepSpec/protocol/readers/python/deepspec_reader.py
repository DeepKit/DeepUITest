"""
deepspec_reader - Minimal DeepSpec Protocol Reader (Level 1)

Zero dependencies beyond PyYAML. Reads .deepspec/ directories
and provides typed access to project facts, trees, and decisions.

Usage:
    from deepspec_reader import open_deepspec

    spec = open_deepspec("/path/to/project")
    if spec:
        for node in spec.tree("function").nodes:
            print(f"{node['id']}: {node['title']} [{node['status']}]")
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


# --- Defaults ---

NODE_DEFAULTS = {
    "status": "candidate",
    "confidence": "medium",
    "source_layer": "ai_inferred",
    "source_refs": [],
    "decision_refs": [],
    "issue_refs": [],
    "related_functions": [],
    "related_modules": [],
    "related_views": [],
    "children": [],
    "tags": [],
    "acceptance_criteria": [],
    "not_doing": [],
    "revision": 1,
    "slug_override": None,
}


# --- Data Classes ---

@dataclass
class TreeFile:
    version: str
    tree: str
    generated_at: str
    generator: str
    nodes: list[dict[str, Any]]


@dataclass
class ProjectSpec:
    version: str
    project: dict[str, Any]
    summary: dict[str, int]
    trees: dict[str, str]


# --- Reader ---

class DeepSpecReader:
    """Reads a .deepspec/ directory and provides access to protocol facts."""

    def __init__(self, project_root: str | Path):
        self._base = Path(project_root) / ".deepspec"
        self._project: ProjectSpec | None = None
        self._trees: dict[str, TreeFile] = {}

    @property
    def exists(self) -> bool:
        return (self._base / "project-spec.yaml").is_file()

    def project(self) -> ProjectSpec:
        if self._project is None:
            raw = self._read_yaml("project-spec.yaml")
            self._project = ProjectSpec(
                version=raw["version"],
                project=raw["project"],
                summary=raw["summary"],
                trees=raw["trees"],
            )
        return self._project

    def tree(self, tree_type: str) -> TreeFile:
        """Load a tree by type: 'function', 'module', or 'view'."""
        if tree_type not in self._trees:
            proj = self.project()
            path = proj.trees[f"{tree_type}_tree"]
            raw = self._read_yaml(path)
            nodes = [self._apply_defaults(n) for n in (raw.get("nodes") or [])]
            self._trees[tree_type] = TreeFile(
                version=raw["version"],
                tree=raw["tree"],
                generated_at=raw["generated_at"],
                generator=raw["generator"],
                nodes=nodes,
            )
        return self._trees[tree_type]

    def all_nodes(self) -> list[dict[str, Any]]:
        """Get all nodes across all three trees."""
        result = []
        for t in ("function", "module", "view"):
            result.extend(self.tree(t).nodes)
        return result

    def find_node(self, node_id: str) -> dict[str, Any] | None:
        """Find a node by ID across all trees."""
        for node in self.all_nodes():
            if node["id"] == node_id:
                return node
        return None

    def roots(self, tree_type: str) -> list[dict[str, Any]]:
        """Get root nodes (no parent) for a tree type."""
        return [n for n in self.tree(tree_type).nodes if not n.get("parent_id")]

    def children_of(self, parent_id: str) -> list[dict[str, Any]]:
        """Get direct children of a node."""
        return [n for n in self.all_nodes() if n.get("parent_id") == parent_id]

    def decisions(self) -> list[dict[str, Any]]:
        """Load all decisions."""
        try:
            raw = self._read_yaml("decisions/requirement-decisions.yaml")
            return raw.get("decisions", [])
        except FileNotFoundError:
            return []

    def accepted_decisions(self) -> list[dict[str, Any]]:
        """Get only accepted decisions."""
        return [d for d in self.decisions() if d.get("status") == "accepted"]

    def ai_instructions(self) -> list[str]:
        """Extract ai_instruction from all accepted decisions."""
        return [
            d["ai_instruction"]
            for d in self.accepted_decisions()
            if d.get("ai_instruction")
        ]

    def _read_yaml(self, relative_path: str) -> dict[str, Any]:
        full_path = self._base / relative_path
        if not full_path.is_file():
            raise FileNotFoundError(f"DeepSpec file not found: {relative_path}")
        with open(full_path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f)

    @staticmethod
    def _apply_defaults(node: dict[str, Any]) -> dict[str, Any]:
        result = dict(NODE_DEFAULTS)
        result.update(node)
        return result


# --- Convenience ---

def open_deepspec(project_root: str | Path) -> DeepSpecReader | None:
    """Open a DeepSpec reader for a project. Returns None if no .deepspec/ exists."""
    reader = DeepSpecReader(project_root)
    return reader if reader.exists else None
