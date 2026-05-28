# DeepSpec Protocol

> AI-native specification facts for software projects.  
> Current baseline: v1.2-draft.

## What Is This?

DeepSpec Protocol defines a structured `.deepspec/` workspace that humans and AI coding agents can both read.

```text
Human intent / project files / code evidence
        -> DeepSpec CTF
YAML facts in .deepspec/
        -> generated HTML / reader tools
Human review decisions
        -> SpecSnapshot / ContractCandidate
```

YAML files are the source of truth. HTML pages are generated review surfaces.

## Core Concepts

- Four projections: `function-tree`, `module-tree`, `view-tree`, `data-tree`
- Evidence: facts should trace back to source material or human decisions
- Decisions: human review decisions are first-class facts, not UI state
- Orthogonal states: `gen_status` and `review_status` replace overloaded status in new work
- Compatibility: legacy `status` remains readable for older examples and implementations

## Directory Structure

```text
.deepspec/
  project-spec.yaml
  trees/
    function-tree.yaml
    module-tree.yaml
    view-tree.yaml
    data-tree.yaml
  bundles/
    semantic-bundles.yaml
  relations/
    requirement-relations.yaml
  evidence/
    source-evidence.yaml
  issues/
    doc-issues.yaml
  decisions/
    requirement-decisions.yaml
    review-decisions.yaml
  agents/
    agent-results.yaml
```

Only the first three tree files are required for v1.0/v1.1 compatibility. `data-tree` is part of the v1.2-draft target model.

## Adoption Levels

| Level | Name | Requirement |
|---|---|---|
| 0 | Scanner Reader | read `project-spec.yaml` and scan metadata |
| 1 | Tree Reader | read function/module/view trees and read data-tree when present |
| 2 | Full Reader | read relations, evidence, issues, decisions, and semantic bundles |
| 3 | Writer / Gate | validate, update, snapshot, and enforce invariants |

## Schemas

JSON Schema files are in `schemas/`. They are expected to be valid JSON and parseable by standard JSON tooling.

Important schemas:

```text
project-spec.schema.json
tree.schema.json
data-tree.schema.json
bundle.schema.json
review-decision.schema.json
agent-result.schema.json
spec-snapshot.schema.json
```

## Examples

Seed projects are under `examples/`.

```text
examples/seed-react-web/
examples/seed-go-microservice/
examples/seed-python-fastapi/
examples/seed-docs-only/
```

## Conformance

Use the Python runner under `conformance/` to test a reader implementation:

```bash
python protocol/conformance/run.py --reader "your-reader" --level 1
```

The repository does not yet publish `npx deepspec-init` or `npx deepspec-validate`. Those commands are planned CLI work, not current protocol guarantees.

## License

Protocol: Apache-2.0
