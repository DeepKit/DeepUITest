"""InkFlow custom exception hierarchy.

Allows callers to catch specific error categories rather than
relying on built-in Exception types.
"""

from __future__ import annotations


class InkFlowError(Exception):
    """Base exception for all InkFlow errors."""
    pass


class ConfigError(InkFlowError):
    """Configuration errors (.models, .env, project config)."""
    pass


class ContractError(InkFlowError):
    """Meta-contract or shot-contract validation errors."""
    pass


class GenerationError(InkFlowError):
    """Writer race, jury, or pipeline failures."""
    pass


class DataIntegrityError(InkFlowError):
    """Schema violations, FK conflicts, orphan records."""
    pass


class SessionError(InkFlowError):
    """Session lifecycle errors (create, resume, abort)."""
    pass


class ImportError(InkFlowError):
    """Baseline import errors (duplicate, corrupt, missing)."""
    pass