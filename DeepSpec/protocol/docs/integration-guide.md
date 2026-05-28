# DeepSpec Protocol: 10-Minute Integration Guide

> For tool developers who want to read `.deepspec/` directories.

## What You Build

A minimal reader that can:

1. Find a `.deepspec/` directory
2. Parse `project-spec.yaml`
3. Load function/module/view trees
4. Load `data-tree` when present
5. Display nodes with trust state

## Step 1: Find the Entry Point

```text
{project_root}/.deepspec/project-spec.yaml
```

If this file exists, the project has DeepSpec facts.

## Step 2: Parse `project-spec.yaml`

```yaml
version: "1.2"
project:
  name: "MyApp"
  path: "/path/to/MyApp"
  type: "web_react"
  scan_time: "2026-05-20T10:00:00+08:00"
trees:
  function_tree: "trees/function-tree.yaml"
  module_tree: "trees/module-tree.yaml"
  view_tree: "trees/view-tree.yaml"
  data_tree: "trees/data-tree.yaml"
```

Use a YAML parser. Treat unknown fields as forward-compatible extensions.

## Step 3: Load a Tree File

Each tree file has the same top-level shape:

```yaml
version: "1.2"
tree: function
nodes:
  - id: "func-login"
    tree: function
    title: "User Login"
    kind: feature
    gen_status: generated
    review_status: pending
    confidence: high
    source_layer: ai_inferred
```

Minimum node fields: `id`, `tree`, `title`, `kind`.

## Step 4: Understand the Four Projections

| Tree | Question |
|---|---|
| function | What does this software do? |
| module | Where does the behavior live? |
| view | What does the user see? |
| data | What data exists, persists, moves, and migrates? |

Readers must not treat `data-tree` as a risk tree. Risk is a field or derived view.

## Step 5: Apply State Defaults

Preferred state fields:

```yaml
gen_status: generated
review_status: pending
confidence: medium
source_layer: ai_inferred
```

Legacy files may use:

```yaml
status: candidate
```

Map legacy status conservatively instead of failing.

## Step 6: Read Decisions

```yaml
decisions:
  - id: "dec-001"
    type: confirm
    decision: "This app follows TodoMVC spec"
    ai_instruction: "All features must align with todomvc.com"
    status: accepted
```

Accepted decisions are the highest-value context for coding agents, but they can still become stale when evidence changes.

## Validation

Schema files are in `protocol/schemas/`.

```python
import json
from pathlib import Path

for path in Path('protocol/schemas').glob('*.json'):
    json.loads(path.read_text(encoding='utf-8'))
```

## What Not To Do

- Do not write to `.deepspec/` without user consent.
- Do not treat generated pending nodes as confirmed facts.
- Do not ignore human `ai_instruction` fields.
- Do not parse generated HTML as facts.
- Do not require `data-tree` for old v1.0/v1.1 workspaces, but load it when present.
