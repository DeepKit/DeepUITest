# DeepSpec Protocol Governance

## Principles

1. The protocol is independent of any single product or company.
2. Changes are driven by real-world usage, not theoretical completeness.
3. Backward compatibility is the default. Breaking changes require strong justification.

---

## Decision Making

### Minor Changes (no version bump)

- Adding optional fields
- Adding new `x_` extension kinds
- Clarifying documentation
- Adding examples

Process: Pull request → 1 maintainer approval → merge.

### Minor Version Bump (e.g., 1.0 → 1.1)

- Changing field optionality (optional → required)
- Removing deprecated fields (after 2 minor versions)
- Adding new required fields with defaults

Process: RFC issue → 7-day comment period → 2/3 maintainer vote → merge.

### Major Version Bump (e.g., 1.x → 2.0)

- Changing ID format
- Restructuring file layout
- Removing core concepts

Process: RFC issue → 30-day comment period → unanimous maintainer vote → migration guide required.

---

## Extension Registry

### Submitting a new `kind` value

Community members can propose promoting an `x_` extension to a built-in kind:

1. Open an issue with title: `[kind-proposal] {tree}: {kind_name}`
2. Provide: definition, use case, at least 2 real-world examples
3. 14-day comment period
4. 2/3 maintainer approval

### Submitting a new relation type

Same process as kind, with title: `[relation-proposal] {type_name}`

---

## Conformance

Tools claiming "DeepSpec v1 compatible" must:

1. Pass the conformance test suite at their declared level (0/1/2)
2. Not modify `.deepspec/` files without user consent
3. Handle unknown fields gracefully (ignore, don't error)

---

## Maintainers

Initial maintainers are the protocol creators. Additional maintainers are invited based on sustained contribution (code, documentation, or community support).

Maintainer responsibilities:
- Review RFCs and PRs within 7 days
- Participate in version bump votes
- Maintain at least one reference implementation or seed project

---

## Code of Conduct

Be respectful. Focus on technical merit. Welcome newcomers.
Detailed CoC to be adopted from Contributor Covenant when community grows.
