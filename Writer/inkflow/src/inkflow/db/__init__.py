"""Database module."""

from .connection import open_db, init_project_db
from .backup import backup_project_db
from .migration import clear_migrations, register_migration, migrate_if_needed, SCHEMA_VERSION

__all__ = [
    "open_db",
    "init_project_db",
    "backup_project_db",
    "clear_migrations",
    "register_migration",
    "migrate_if_needed",
    "SCHEMA_VERSION",
]