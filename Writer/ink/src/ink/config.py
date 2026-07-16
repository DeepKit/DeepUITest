from __future__ import annotations

import json
import sqlite3
from collections.abc import Mapping
from dataclasses import dataclass

from ink.errors import ConfigError


@dataclass(frozen=True)
class ProjectConfig:
    project_id: int
    code: str
    title: str
    draft_count: int
    writer_model_pool: tuple[str, ...]
    jury_model_pool: tuple[str, ...]
    jury_model_pool_min: int
    shot_quality_floor: int
    dimension_floor: int
    chapter_quality_floor: int
    book_quality_floor: int
    judge_disagreement_max: int
    reader_pull_floor: int
    blind_review_min_passes: int
    max_calls_per_shot: int
    max_total_llm_calls: int
    consecutive_failure_circuit_break: int


class ProjectConfigValidator:
    def __init__(self, *, allow_model_overlap: bool = False) -> None:
        self.allow_model_overlap = allow_model_overlap

    def validate(self, row: Mapping[str, object] | sqlite3.Row) -> ProjectConfig:
        writer_pool = self._parse_model_pool(row["writer_model_pool"], "writer_model_pool")
        jury_pool = self._parse_model_pool(row["jury_model_pool"], "jury_model_pool")
        jury_min = int(row["jury_model_pool_min"])
        draft_count = int(row["draft_count"])

        if len(writer_pool) < draft_count:
            raise ConfigError("writer_model_pool must contain at least draft_count models")
        if len(jury_pool) < jury_min:
            raise ConfigError("jury_model_pool must contain at least jury_model_pool_min models")

        overlap = set(writer_pool) & set(jury_pool)
        if overlap and not self.allow_model_overlap:
            raise ConfigError(f"writer_model_pool and jury_model_pool overlap: {sorted(overlap)}")
        if self.allow_model_overlap:
            for writer_model in writer_pool:
                available = [model for model in jury_pool if model != writer_model]
                if len(available) < jury_min:
                    raise ConfigError(
                        "jury_model_pool must still have jury_model_pool_min models after excluding writer_model"
                    )

        self._validate_thresholds(row)

        return ProjectConfig(
            project_id=int(row["project_id"]),
            code=str(row["code"]),
            title=str(row["title"]),
            draft_count=draft_count,
            writer_model_pool=tuple(writer_pool),
            jury_model_pool=tuple(jury_pool),
            jury_model_pool_min=jury_min,
            shot_quality_floor=int(row["shot_quality_floor"]),
            dimension_floor=int(row["dimension_floor"]),
            chapter_quality_floor=int(row["chapter_quality_floor"]),
            book_quality_floor=int(row["book_quality_floor"]),
            judge_disagreement_max=int(row["judge_disagreement_max"]),
            reader_pull_floor=int(row["reader_pull_floor"]),
            blind_review_min_passes=int(row["blind_review_min_passes"]),
            max_calls_per_shot=int(row["max_calls_per_shot"]),
            max_total_llm_calls=int(row["max_total_llm_calls"]),
            consecutive_failure_circuit_break=int(row["consecutive_failure_circuit_break"]),
        )

    def _parse_model_pool(self, raw: str, field_name: str) -> list[str]:
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ConfigError(f"{field_name} must be valid JSON") from exc
        if not isinstance(value, list):
            raise ConfigError(f"{field_name} must be a JSON array")
        if not value or any(not isinstance(item, str) or not item.strip() for item in value):
            raise ConfigError(f"{field_name} must contain non-empty strings")
        if len(set(value)) != len(value):
            raise ConfigError(f"{field_name} must not contain duplicate models")
        return value

    def _validate_thresholds(self, row: sqlite3.Row) -> None:
        floors = {
            "shot_quality_floor": 75,
            "dimension_floor": 60,
            "chapter_quality_floor": 75,
            "book_quality_floor": 75,
        }
        for field_name, minimum in floors.items():
            if int(row[field_name]) < minimum:
                raise ConfigError(f"{field_name} must be >= {minimum}")
        if int(row["judge_disagreement_max"]) > 25:
            raise ConfigError("judge_disagreement_max must be <= 25")
        if int(row["blind_review_min_passes"]) not in {1, 2, 3}:
            raise ConfigError("blind_review_min_passes must be between 1 and 3")
        if int(row["max_calls_per_shot"]) < 1 or int(row["max_total_llm_calls"]) < 1:
            raise ConfigError("LLM call budgets must be positive")
        if int(row["consecutive_failure_circuit_break"]) < 1:
            raise ConfigError("consecutive_failure_circuit_break must be positive")


def load_project_config(
    conn: sqlite3.Connection,
    project_id: int,
    *,
    allow_model_overlap: bool = False,
) -> ProjectConfig:
    cursor = conn.execute("SELECT * FROM writing_projects WHERE project_id = ?", (project_id,))
    row = cursor.fetchone()
    if row is None:
        raise ConfigError(f"project not found: {project_id}")
    if not isinstance(row, sqlite3.Row):
        names = [column[0] for column in cursor.description]
        row = dict(zip(names, row, strict=True))
    return ProjectConfigValidator(allow_model_overlap=allow_model_overlap).validate(row)
