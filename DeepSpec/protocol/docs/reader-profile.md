# DeepSpec Reader Profile v1.2-draft

> Minimum specification for tools that consume `.deepspec/` directories.

## Level 0: Scanner Reader

| Capability | Required |
|---|---|
| Detect `.deepspec/project-spec.yaml` | Yes |
| Read `project.name`, `project.type`, `project.scan_time` | Yes |
| Read `summary.*` counters | Yes |
| Report missing project cleanly | Yes |

## Level 1: Tree Reader

| Capability | Required |
|---|---|
| All Level 0 capabilities | Yes |
| Parse `trees/function-tree.yaml` | Yes |
| Parse `trees/module-tree.yaml` | Yes |
| Parse `trees/view-tree.yaml` | Yes |
| Parse `trees/data-tree.yaml` when referenced or present | Yes |
| Reconstruct hierarchy from `parent_id` | Yes |
| Handle empty `nodes: []` | Yes |
| Apply defaults for optional fields | Yes |
| Handle `x_` extension kinds without error | Yes |
| Warn on unknown non-extension kinds | Yes |

## Level 2: Full Reader

| Capability | Required |
|---|---|
| All Level 1 capabilities | Yes |
| Parse relations, evidence, issues, and decisions | Yes |
| Resolve `source_refs[].ref_id` to evidence entries | Yes |
| Expose accepted `ai_instruction` values | Recommended |
| Detect stale evidence | Recommended |
| Parse semantic bundles when present | Recommended |

## Default Values

```yaml
gen_status: generated
review_status: pending
status: candidate          # legacy compatibility only
confidence: medium
source_layer: ai_inferred
revision: 1
source_refs: []
decision_refs: []
issue_refs: []
related_functions: []
related_modules: []
related_views: []
related_data: []
children: []
tags: []
acceptance_criteria: []
not_doing: []
slug_override: null
```

## Error Handling

| Situation | Required behavior |
|---|---|
| `project-spec.yaml` missing | Report "not a DeepSpec project" |
| Optional tree referenced but missing | Warning, continue with empty tree |
| Required v1.0 tree missing | Warning, continue with partial data if possible |
| Unknown `x_` field or kind | Ignore or preserve silently |
| Unknown core field | Warning, attempt parse anyway |
| Version mismatch | Warning, attempt parse anyway |
| Malformed YAML | Error with file and location |

## Non-Goals

A reader does not need to write `.deepspec/`, run LLM calls, render HTML, or enforce all invariants. Those are writer/gate capabilities.
