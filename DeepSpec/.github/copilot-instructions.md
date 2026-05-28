# GitHub Copilot / Coding Agent Instructions for DeepSpec

DeepSpec turns messy human-AI requirement conversations into traceable, reviewable, fallible specifications for coding agents.

## Core Positioning

DeepSpec is not a generic code generator. It is a specification construction and review system.

Use this pipeline as the default mental model:

```text
Human intent / project facts / source code evidence
        -> CTF: Construct, Trace, Falsify, Review, Freeze
        -> SpecSnapshot / ContractCandidate
        -> Agent task orchestration
        -> ODD: Contract, Execute, Verify, Seal, Rework
```

## Non-Negotiable Principles

- Preserve traceability: every generated node, relation, decision, and issue must point back to source evidence or an explicit human decision.
- Preserve fallibility: no generated specification is permanently correct. Accepted nodes can become stale when evidence changes.
- Keep states orthogonal: generation state, review state, evidence state, and execution state must not be collapsed into one field.
- Prefer partial success: one failed tree, parser, LLM call, or validation pass must not block unrelated readable results.
- Keep AI context least-privilege: each AI call should receive the smallest context sufficient for the current task.
- Human judgment is not replaced: tooling should make human judgment more inspectable and consequential.
- Do not turn DeepSpec into ODD. DeepSpec constructs and freezes specifications; ODD verifies implementation outputs against contracts.

## Architecture Expectations

- `.deepspec/` is the project-local specification workspace.
- `protocol/` defines schemas, conformance rules, and reader expectations.
- `src/core/` should stay independent from UI concerns.
- `src/services/` coordinates parsing, storage, rendering, LLM calls, and decisions.
- `src/app/`, `src/providers/`, and `src/controllers/` are application/UI integration layers.

## Required Checks Before Claiming Completion

- Validate changed JSON schemas if any schema file changed.
- Run or describe relevant parser/store/validation checks for changed Delphi units.
- Confirm no tokens, cookies, API keys, local paths with secrets, or private credentials are added.
- Confirm changes do not weaken traceability, reviewability, or evidence requirements.

## Documentation Style

- README-level content should be short and practical.
- CTF, ODD, TAT, OCGS, and theory background belong in `docs/` unless directly required for implementation.
- Public-facing docs should explain the problem first, then the workflow, then the protocol.
- Chinese and English may coexist, but keep public repo entry points understandable to non-Chinese developers.
