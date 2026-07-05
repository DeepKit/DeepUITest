from __future__ import annotations

import json
import sqlite3

from ink.errors import ConfigError


def load_writer_model_pool(conn: sqlite3.Connection, project_id: int) -> tuple[str, ...]:
    row = conn.execute(
        "SELECT writer_model_pool FROM writing_projects WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    if row is None:
        raise ConfigError(f"project not found: {project_id}")
    value = json.loads(row[0])
    if not isinstance(value, list) or not value:
        raise ConfigError("writer_model_pool must be a non-empty JSON array")
    models = tuple(str(item) for item in value)
    if any(not model.strip() for model in models):
        raise ConfigError("writer_model_pool contains an empty model name")
    return models


def select_writer_models(pool: tuple[str, ...], count: int) -> tuple[str, ...]:
    if count < 1:
        raise ConfigError("draft count must be positive")
    if not pool:
        raise ConfigError("writer_model_pool is empty")
    return tuple(pool[index % len(pool)] for index in range(count))
