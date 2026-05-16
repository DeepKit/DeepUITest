# DeepSpec Protocol

> AI-native requirement specification format for software projects.

## What is this?

DeepSpec Protocol defines a structured format for representing software requirements as machine-readable facts that both AI and humans can work with.

```
Human intent (scattered docs/ideas/chats)
        ↓ AI generates
YAML facts (structured, AI-consumable)
        ↓ Tools render
HTML views (visual, human-reviewable)
        ↓ Human decides
Traceable specification (three trees + evidence + decisions)
```

## Core Concepts

- **Three Trees**: Function Tree (what), Module Tree (how), View Tree (UI)
- **Evidence**: Every fact traces back to source material
- **Decisions**: Human choices are first-class facts, not UI state
- **Dual Interface**: AI reads YAML, humans read HTML

## Quick Start

```bash
# Validate a .deepspec directory
npx deepspec-validate ./my-project/.deepspec

# Generate minimal .deepspec from project scan
npx deepspec-init ./my-project
```

## Directory Structure

```
.deepspec/
  project-spec.yaml          # Project index
  trees/
    function-tree.yaml       # What the software does
    module-tree.yaml         # How it's structured
    view-tree.yaml           # What users see
  relations/
    requirement-relations.yaml
  evidence/
    source-evidence.yaml
  issues/
    doc-issues.yaml
  decisions/
    requirement-decisions.yaml
```

## Adoption Levels

| Level | What you get | Integration cost |
|-------|-------------|-----------------|
| 0 - Scanner | File classification + project type | 1 day |
| 1 - Trees | Function/Module/View structure | 1 week |
| 2 - Full | + evidence + issues + decisions + validation | 1 month |

## Schema

JSON Schema definitions are in [`schemas/`](./schemas/). Use them to validate `.deepspec` YAML files.

## License

Protocol: Apache-2.0
