# DeepSpec State Machine

> Status: v1.2-draft

DeepSpec separates generation state from review state.

## Generation State

```text
pending -> generated
pending -> failed
failed  -> pending
generated -> pending    when source evidence changes or regeneration is requested
```

## Review State

```text
pending -> accepted
pending -> rejected
pending -> locked
accepted -> pending     when evidence becomes stale or content_hash changes
accepted -> locked
rejected -> pending     when regenerated with different content
locked -> unlocked/pending only by human decision
```

## Legacy Mapping

```text
candidate  -> generated + pending
uncertain  -> generated + pending
confirmed  -> generated + accepted
rejected   -> generated + rejected
superseded -> generated + rejected
```

## Execution State

Execution lifecycle state is intentionally excluded. Values such as `running`, `done`, `failed`, and `verified` belong to orchestration or ODD, not to CTF specification formation.
