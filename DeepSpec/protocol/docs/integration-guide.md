# DeepSpec Protocol: 10-Minute Integration Guide

> For tool developers who want to read `.deepspec/` directories.

---

## What you'll build

A minimal reader that can:
1. Open a `.deepspec/` directory
2. Parse the project index
3. Load the three trees
4. Display nodes with their status and confidence

Time: ~10 minutes for a basic reader. ~1 hour for full validation.

---

## Step 1: Find the entry point (30 seconds)

```
{project_root}/.deepspec/project-spec.yaml
```

If this file exists, the project has DeepSpec facts.

---

## Step 2: Parse project-spec.yaml (2 minutes)

```yaml
version: "1.0"
project:
  name: "MyApp"
  type: "web_react"
trees:
  function_tree: "trees/function-tree.yaml"
  module_tree: "trees/module-tree.yaml"
  view_tree: "trees/view-tree.yaml"
```

You need: a YAML parser. That's it.

---

## Step 3: Load a tree file (3 minutes)

Each tree file has the same structure:

```yaml
version: "1.0"
tree: function          # or module, or view
nodes:
  - id: "func-login"
    tree: function
    title: "User Login"
    kind: feature
    status: confirmed   # candidate | confirmed | uncertain | rejected
    confidence: high    # low | medium | high
    source_layer: human_decision  # parsed_from_a | human_decision | ai_inferred
    parent_id: "func-root"
    children: [...]
```

Minimum fields you must handle: `id`, `tree`, `title`, `kind`.
Everything else has defaults (see schema).

---

## Step 4: Understand the node (2 minutes)

Every node answers one question depending on its tree:

| Tree | Question |
|------|----------|
| function | What does this software do? |
| module | How is it structured internally? |
| view | What does the user see? |

Nodes link to each other via:
- `parent_id` / `children` (tree hierarchy)
- `related_functions` / `related_modules` / `related_views` (cross-tree)
- Relations file (typed edges like `implements`, `presented_by`)

---

## Step 5: Show confidence (1 minute)

The killer feature for AI tools: every fact has a trust level.

```
confirmed + human_decision  → User verified this. Trust it.
candidate + ai_inferred     → AI guessed this. May be wrong.
uncertain + low confidence  → Needs human review.
```

Your tool should visually distinguish these levels.

---

## Step 6: Read decisions (2 minutes)

Decisions are first-class facts, not UI state:

```yaml
decisions:
  - id: "dec-001"
    type: confirm
    decision: "This app follows TodoMVC spec"
    ai_instruction: "All features must align with todomvc.com"
    status: accepted
```

`ai_instruction` is the gold: it tells your AI what the human decided.
**Accepted decisions override conflicting source material.**

---

## Reader Profile: Minimum Compliance

To claim "reads DeepSpec v1", your tool must:

| Requirement | Level |
|-------------|-------|
| Parse project-spec.yaml | Required |
| Load all three tree files | Required |
| Handle missing optional fields with defaults | Required |
| Display node id, title, kind, status | Required |
| Respect parent_id hierarchy | Required |
| Load decisions and expose ai_instruction | Recommended |
| Load evidence and show source_refs | Recommended |
| Load issues | Optional |
| Load relations | Optional |
| Validate against JSON Schema | Optional |

---

## Validation (optional, +30 minutes)

JSON Schema files are in `schemas/`. Validate with any JSON Schema library:

```javascript
// Node.js example
import Ajv from 'ajv';
import { load } from 'js-yaml';
import { readFileSync } from 'fs';

const ajv = new Ajv();
const schema = JSON.parse(readFileSync('schemas/tree.schema.json', 'utf8'));
const validate = ajv.compile(schema);

const tree = load(readFileSync('.deepspec/trees/function-tree.yaml', 'utf8'));
const valid = validate(tree);
if (!valid) console.error(validate.errors);
```

```python
# Python example
import yaml, jsonschema, json

schema = json.load(open('schemas/tree.schema.json'))
tree = yaml.safe_load(open('.deepspec/trees/function-tree.yaml'))
jsonschema.validate(tree, schema)
```

---

## What NOT to do

- Don't write to `.deepspec/` without user consent
- Don't treat `candidate` nodes as confirmed facts
- Don't ignore `ai_instruction` in decisions
- Don't assume all fields are present (use defaults)
- Don't parse HTML files as facts (they're generated views)

---

## Next steps

- Full protocol spec: `DeepSpec-三棵树通用协议-v1.md`
- JSON Schema definitions: `schemas/`
- Seed projects: `examples/`
- Questions: open an issue
