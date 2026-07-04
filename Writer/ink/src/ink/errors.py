from __future__ import annotations


class InkError(Exception):
    """Base error for InkFlow v2."""


class StateMachineError(InkError):
    """State-machine related error."""


class IllegalTransitionError(StateMachineError):
    """The requested state transition is not legal."""


class TerminalStateError(StateMachineError):
    """A terminal shot state cannot transition further."""


class ConcurrentModificationError(StateMachineError):
    """A compare-and-swap update did not affect exactly one row."""


class DataIntegrityError(InkError):
    """Database content violated an application-level invariant."""


class ConfigError(InkError):
    """Project configuration is invalid."""


class LLMError(InkError):
    """LLM gateway call failed."""


class LLMProviderError(LLMError):
    """Underlying provider failed."""
