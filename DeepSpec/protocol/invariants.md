# DeepSpec Protocol Invariants

> Status: v1.2-draft

These invariants define what a valid `.deepspec/` workspace must preserve.

## Core Invariants

| ID | Invariant | Enforcement point |
|---|---|---|
| INV-1 | Node IDs are unique within one tree. | write / validate |
| INV-2 | `parent_id` is null or references an existing node in the same tree. | write / validate |
| INV-3 | Relation endpoints reference existing nodes. | write / validate |
| INV-4 | `gen_status` and `review_status` transitions follow `state-machine.md`. | state change |
| INV-5 | Accepted nodes have evidence or an explicit provisional/accountable review decision. | accept / validate |
| INV-6 | `content_hash` changes invalidate prior generated assumptions and require review reconsideration. | merge / scan |
| INV-7 | Locked nodes cannot be overwritten by AI output without a human override decision. | merge |
| INV-8 | Stale evidence is retained but must be visible to readers. | scan / render |
| INV-9 | `data-tree` nodes that describe migrations should state rollback and compatibility when known. | validate |
| INV-10 | Unknown `x_` fields are ignored by readers; unknown core fields produce warnings, not crashes. | read |

## Failure Behavior

Validation failure should not destroy readable facts. DeepSpec should mark affected nodes or files, preserve the last readable snapshot, and allow unrelated trees to remain usable.
