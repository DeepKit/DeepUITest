# Pull Request Checklist

## What changed?

Briefly describe the change and why it is needed.

## DeepSpec invariants

- [ ] Traceability is preserved: new or changed outputs can be linked to evidence or human decisions.
- [ ] Fallibility is preserved: generated or accepted content can be questioned, marked stale, rejected, or regenerated.
- [ ] State dimensions remain orthogonal: generation/review/evidence/execution state are not mixed.
- [ ] Partial success behavior is preserved: unrelated trees/files/results still work when one path fails.
- [ ] Least-privilege context is preserved for AI/LLM calls.

## Verification

- [ ] Relevant tests, parser checks, schema checks, or manual validation were run.
- [ ] Public docs or protocol docs were updated when behavior changed.
- [ ] No secrets, cookies, tokens, local private credentials, or generated release artifacts were added.

## Notes for reviewers

List risky areas, known limitations, or decisions that need human review.
