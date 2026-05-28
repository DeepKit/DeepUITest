# Contributing to DeepSpec

DeepSpec is a specification construction and review system for human-AI software work.

## Contribution Priorities

1. Make project facts easier to inspect.
2. Make generated specifications more traceable.
3. Make human review more meaningful.
4. Make accepted specs safer to freeze, invalidate, and hand off to coding agents.
5. Keep protocol readers simple and backward-compatible.

## Before You Start

- Read `docs/DeepSpec-CTF方法论-v1.md` for the method.
- Read `protocol/README.md` for protocol expectations.
- Prefer small changes with clear verification.
- Do not mix broad theory rewrites with implementation changes.

## CTF Boundary

DeepSpec constructs, reviews, and freezes specifications. It does not replace ODD-style implementation verification.

A healthy contribution should make this chain clearer:

```text
Evidence -> Spec Node -> Review Decision -> Spec Snapshot -> Agent Task / ODD Contract Candidate
```

## Security and Privacy

Never commit API keys, cookies, private project data, database dumps, local credentials, or generated release packages.

If an example needs real-world flavor, anonymize it first.
