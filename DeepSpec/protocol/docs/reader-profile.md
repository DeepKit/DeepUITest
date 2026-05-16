# DeepSpec Reader Profile v1

> Minimum specification for tools that consume `.deepspec/` directories.

---

## Purpose

A "DeepSpec Reader" is any tool that reads `.deepspec/` facts to provide value to users. This document defines the minimum compliance requirements.

---

## Compliance Levels

### Level 0: Scanner Reader

Can read scan results and file classification.

| Capability | Required |
|-----------|----------|
| Parse `project-spec.yaml` | Yes |
| Read `project.name`, `project.type`, `project.scan_time` | Yes |
| Read `summary.*` counters | Yes |
| Handle missing file gracefully | Yes |

### Level 1: Tree Reader

Can navigate the three requirement trees.

| Capability | Required |
|-----------|----------|
| All Level 0 capabilities | Yes |
| Parse `trees/function-tree.yaml` | Yes |
| Parse `trees/module-tree.yaml` | Yes |
| Parse `trees/view-tree.yaml` | Yes |
| Reconstruct parent-child hierarchy from `parent_id` | Yes |
| Handle empty `nodes: []` | Yes |
| Apply default values for missing optional fields | Yes |
| Distinguish `status` values visually | Recommended |
| Distinguish `source_layer` values | Recommended |
| Handle `x_` extension kinds without error | Yes |

### Level 2: Full Reader

Can consume all fact types including evidence, issues, and decisions.

| Capability | Required |
|-----------|----------|
| All Level 1 capabilities | Yes |
| Parse `relations/requirement-relations.yaml` | Yes |
| Parse `evidence/source-evidence.yaml` | Yes |
| Parse `issues/doc-issues.yaml` | Yes |
| Parse `decisions/requirement-decisions.yaml` | Yes |
| Resolve `source_refs[].ref_id` to evidence entries | Yes |
| Respect decision priority (accepted > candidate) | Yes |
| Expose `ai_instruction` from accepted decisions | Recommended |
| Validate against JSON Schema | Recommended |
| Detect `is_stale` evidence | Recommended |

---

## Default Values

When optional fields are missing, readers MUST apply these defaults:

```yaml
status: candidate
confidence: medium
source_layer: ai_inferred
revision: 1
source_refs: []
decision_refs: []
issue_refs: []
related_functions: []
related_modules: []
related_views: []
children: []
tags: []
acceptance_criteria: []
not_doing: []
slug_override: null
```

---

## Error Handling

| Situation | Required behavior |
|-----------|------------------|
| `project-spec.yaml` missing | Report "not a DeepSpec project" |
| Tree file referenced but missing | Warning, continue with empty tree |
| Unknown `kind` value (no `x_` prefix) | Warning, treat as unknown |
| Unknown `kind` value (with `x_` prefix) | Accept silently |
| Unknown fields in YAML | Ignore silently (forward compatibility) |
| `version` mismatch | Warning, attempt parse anyway |
| Malformed YAML | Error, report file and location |

---

## Testing Compliance

Use the seed projects in `examples/` to verify your reader:

1. `seed-react-web/` — Web project with all fact types populated
2. `seed-go-microservice/` — Backend with empty view tree

Your reader passes Level 1 if it can:
- Load both seed projects without error
- Display all nodes from all three trees
- Show correct parent-child relationships
- Not crash on empty `nodes: []`

---

## Non-Goals

A Reader Profile does NOT require:
- Writing to `.deepspec/`
- Generating HTML
- Running LLM tasks
- Validating content_hash
- Implementing incremental patch mode
- Supporting the full validation/merge pipeline

These are Writer capabilities, defined separately.
