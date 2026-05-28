# deepspec-reader (Python)

Minimal DeepSpec Protocol reader. Level 1 compliance with v1.2-draft data-tree awareness.

## Install

```bash
pip install pyyaml
```

No other dependencies.

## Usage

```python
from deepspec_reader import open_deepspec

spec = open_deepspec("/path/to/project")
if spec is None:
    print("Not a DeepSpec project")
    exit()

# Project info
proj = spec.project()
print(f"Project: {proj.project['name']} ({proj.project['type']})")

# Browse function tree
for node in spec.tree("function").nodes:
    indent = "  " if node.get("parent_id") else ""
    status = node["status"]
    print(f"{indent}{node['id']}: {node['title']} [{status}]")

# Get AI instructions from human decisions
for instruction in spec.ai_instructions():
    print(f"AI must: {instruction}")
```

## API

| Method | Returns | Description |
|--------|---------|-------------|
| `open_deepspec(path)` | `Reader \| None` | Open project, None if no .deepspec |
| `reader.project()` | `ProjectSpec` | Project metadata and summary |
| `reader.tree(type)` | `TreeFile` | Load tree: "function", "module", "view", "data" when present |
| `reader.all_nodes()` | `list[dict]` | All nodes across all trees |
| `reader.find_node(id)` | `dict \| None` | Find node by ID |
| `reader.roots(type)` | `list[dict]` | Root nodes of a tree |
| `reader.children_of(id)` | `list[dict]` | Direct children |
| `reader.decisions()` | `list[dict]` | All decisions |
| `reader.accepted_decisions()` | `list[dict]` | Accepted only |
| `reader.ai_instructions()` | `list[str]` | AI instructions from decisions |
