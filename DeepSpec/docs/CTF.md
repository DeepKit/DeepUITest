# CTF in DeepSpec

CTF means Constructive Traceable Fallibilist Method.

It is the method used by DeepSpec to turn project material and AI output into specifications that humans can inspect and repair.

## One Sentence

A requirement's form and granularity are constructed through human-AI dialogue, traceable to evidence, and always open to correction. Underlying constraints (compliance, safety, performance) may be objective.

## Boundary

CTF belongs before execution.

```text
CTF / DeepSpec: form a trustworthy specification
Symphony-style orchestration: keep agents working on tasks
ODD: verify, seal, and rework implementation outputs
```

Do not put execution lifecycle state inside CTF. Once an objective is ready for execution, orchestration or ODD owns it.

## Core Workflow

```text
messy project material
        -> four projections
        -> semantic bundles
        -> evidence links
        -> trust signals
        -> human review decision
        -> SpecSnapshot / ContractCandidate
```

## Four Projections

```text
function-tree: behavior and capability
module-tree: implementation ownership and structure
view-tree: user-visible workflow and UI
data-tree: schema, state, persistence, migrations, and boundaries
```

The fourth tree is `data-tree`, not `risk-tree`. Risk is derived from all projections, with data drift often being the highest-risk source.

## Trust Signals

A reviewer should be able to see:

- evidence source status
- confidence
- generation status
- review status
- semantic bundle completeness
- conflicts with previous decisions
- stale source evidence
- agent assumptions, blockers, alternatives, and coverage

## State Model

Preferred node states are orthogonal:

```yaml
gen_status: pending | generated | failed
review_status: pending | accepted | rejected | locked
```

Notable combination: `gen_status=failed + review_status=locked` means source files changed, AI must regenerate, but human has not yet unlocked. Display as "source changed, awaiting unlock".

Legacy `status` is only a compatibility field.

## Review Discipline

Accept should be deliberate. Reject should be easy.

`accept_level` records responsibility:

```text
low_risk      acceptable local inference
provisional   usable but must be revisited
release       suitable for release gating
accountable   reviewer accepts responsibility for high-impact use
```

## Three Health Signals

Monitor only three signals, each tied to a core axiom:

| Signal | Axiom | Trigger |
|--------|-------|---------|
| Review backlog | A3 Fallibilism | pending ratio > 30% |
| Confidence drift | A2 Traceability | new output confidence drops below reviewed average |
| Confirmation bias | A6 Problem-First | accept:reject ratio > 10:1 |

No composite "health index". Each signal speaks for itself.

## Review Ceremony (Three Tiers)

Not every review needs 20 minutes.

| Tier | When | Time | What |
|------|------|------|------|
| Light | single node, confidence > 0.85 | 3 min | problem-first + accept/reject |
| Standard | semantic bundle, 3+ nodes changed | 10 min | problem-first + selective deep-dive + generation instructions |
| Deep | cross-tree impact, architecture decision | 20 min | full four-phase ceremony |

System suggests tier based on change scope. Reviewer can always escalate.

## Decision Log (Exception-Driven)

Record only:

- Reject decisions (reason required)
- Accept with confidence < 0.7 (reason required)
- Deviations from standard review flow

Auto-collect (no human input needed):

- time spent per node
- accept/reject counts
- average confidence
- session length and node count

Remove manual `reasoning_type` selection. Infer automatically from evidence presence.

## Checklist Automation

Machine-checkable items (A2 traceable, A3 fallible, A5 minimal context, A7 partial success) belong in `deepspec_validate`, not in a human checklist.

Only A6 (problem-first) requires human judgment. Present as a non-blocking prompt, not a blocking dialog.

## Tool Protocol

```text
deepspec_read     -- read tree data or summary
deepspec_validate -- check invariants, schema, cross-tree consistency
deepspec_query    -- RAG over four projection trees
deepspec_update   -- write nodes and decisions with conflict detection
```

Day-one minimum: `deepspec_read` + `deepspec_validate`. The other two can follow.

All `.deepspec/` content is human-readable YAML. If every AI tool disappears, a reviewer can still open the files in a text editor.

## Why It Helps AI Engineering

AI engineering fails when generated work looks plausible but cannot be traced, reviewed, or corrected. CTF adds the missing quality gate between agent output and human acceptance.

It does not promise that the AI is correct. It makes incorrectness discoverable and recoverable.
