"""Scene-first actor permission guard.

AI actors may draft contracts, create candidate revisions, generate review
opinions and submit amendments. They may NOT: activate a contract, freeze a
branch, accept a chapter, or update a Chapter Head. These are human-gated
terminal authority actions (implementation-contract.md §5).

This module is the single chokepoint consulted by the Scene-first repository
methods that perform those protected transitions. It raises ``PermissionError``
(labelled) so callers can seal the offending operation to ``failed`` without
mutating authority tables.
"""
from __future__ import annotations

# Actors prefixed with any of these are treated as non-human (AI / automated
# model / autonomous pipeline). Human actors have no such prefix.
AI_ACTOR_PREFIXES: tuple[str, ...] = ("ai:", "model:", "auto:")


class ActorPermissionError(PermissionError):
    """Raised when a non-human actor attempts a human-gated action."""


def is_ai_actor(actor: str) -> bool:
    if not actor:
        return False
    lowered = actor.lower()
    return any(lowered.startswith(prefix) for prefix in AI_ACTOR_PREFIXES)


def assert_human_actor(actor: str, *, action: str = "this action") -> None:
    """Raise if ``actor`` is AI-prefixed. AI may not perform human-gated actions."""
    if is_ai_actor(actor):
        raise ActorPermissionError(
            f"AI actor '{actor}' is not permitted to perform: {action}. "
            "This action requires a human actor."
        )


def assert_can_accept(actor: str) -> None:
    """AI cannot Accept a chapter (INV-AUTH-001)."""
    assert_human_actor(actor, action="accept chapter")


def assert_can_activate_contract(actor: str) -> None:
    """AI cannot activate a Scene Contract (INV-AUTH-002)."""
    assert_human_actor(actor, action="activate scene contract")


def assert_can_update_chapter_head(actor: str) -> None:
    """AI cannot update a Chapter Head (INV-AUTH-003)."""
    assert_human_actor(actor, action="update chapter head")


def assert_can_freeze_branch(actor: str) -> None:
    """AI cannot freeze a Branch version."""
    assert_human_actor(actor, action="freeze branch version")


def assert_can_confirm_fact(actor: str) -> None:
    """Fact attestation confirmation is human-gated (INV-FACT-004)."""
    assert_human_actor(actor, action="confirm fact proposal")
