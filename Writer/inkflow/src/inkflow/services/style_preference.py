"""Style Preference Learning — ARCH-10.

Records the winning persona/model/temperature/style_direction for each shot,
building a preference profile that feeds back into L0.5/L1 rhythm decisions.

Storage:
  - writing_style_preferences table (shot-level records)
  - Aggregated by persona/model/style_direction for runtime queries
"""

from __future__ import annotations

import json
import sqlite3
from collections import Counter

from inkflow.utils.ulid import generate as generate_ulid


class StylePreferenceService:
    """Records and retrieves style preferences from jury winners."""

    def __init__(self, db: sqlite3.Connection, project_id: str, run_id: str):
        self.db = db
        self.project_id = project_id
        self.run_id = run_id

    def record_winner_preference(
        self,
        shot_id: str,
        draft_id: str,
        persona: str,
        model_ref: str,
        temperature: float,
        style_direction: str,
        score: float,
    ) -> str:
        """Record the winning shot's style preference.

        Args:
            shot_id: The shot that was written.
            draft_id: The winning draft ID.
            persona: Writer persona (e.g., "意象师", "节奏师").
            model_ref: Model reference used (e.g., "ollama/llama3").
            temperature: Effective temperature used.
            style_direction: Style direction (e.g., "诗意", "克制", "生活化", "极简").
            score: Jury winner score (trimmed mean).

        Returns:
            preference_id
        """
        pref_id = f"sp_{shot_id}_{generate_ulid()[:8]}"

        self.db.execute(
            "INSERT OR REPLACE INTO writing_style_preferences "
            "(preference_id, shot_id, draft_id, project_id, run_id, "
            "persona, model_ref, temperature, style_direction, score, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))",
            (
                pref_id, shot_id, draft_id, self.project_id, self.run_id,
                persona, model_ref, temperature, style_direction, score,
            ),
        )
        self.db.commit()
        return pref_id

    def get_run_preferences(self) -> list[dict]:
        """Get all style preferences for this run."""
        rows = self.db.execute(
            "SELECT * FROM writing_style_preferences "
            "WHERE run_id = ? ORDER BY created_at",
            (self.run_id,),
        ).fetchall()
        return [dict(r) for r in rows]

    def get_persona_distribution(self) -> dict[str, int]:
        """Get persona win counts for this run."""
        rows = self.db.execute(
            "SELECT persona, COUNT(*) as cnt FROM writing_style_preferences "
            "WHERE run_id = ? GROUP BY persona",
            (self.run_id,),
        ).fetchall()
        return {r["persona"]: r["cnt"] for r in rows}

    def get_top_style_direction(self) -> str | None:
        """Get the most frequent style_direction for this run."""
        rows = self.db.execute(
            "SELECT style_direction, COUNT(*) as cnt FROM writing_style_preferences "
            "WHERE run_id = ? GROUP BY style_direction ORDER BY cnt DESC LIMIT 1",
            (self.run_id,),
        ).fetchone()
        return rows["style_direction"] if rows else None

    def get_project_profile(self) -> dict:
        """Aggregated style profile for the project (all runs)."""
        rows = self.db.execute(
            "SELECT persona, style_direction, model_ref, AVG(temperature) as avg_temp, "
            "COUNT(*) as win_count, AVG(score) as avg_score "
            "FROM writing_style_preferences "
            "WHERE project_id = ? "
            "GROUP BY persona, style_direction, model_ref "
            "ORDER BY win_count DESC",
            (self.project_id,),
        ).fetchall()
        return {
            "entries": [dict(r) for r in rows],
            "total_wins": sum(r["win_count"] for r in rows),
        }

    def get_effective_temperature(self, persona: str) -> float:
        """Get the average effective temperature for a persona in this run."""
        rows = self.db.execute(
            "SELECT AVG(temperature) as avg_temp FROM writing_style_preferences "
            "WHERE run_id = ? AND persona = ?",
            (self.run_id, persona),
        ).fetchone()
        return rows["avg_temp"] if rows and rows["avg_temp"] is not None else 0.8


def extract_style_direction_from_draft(draft: dict | None, persona: str) -> str:
    """Extract style_direction from draft metadata.

    Falls back to persona-based defaults if not explicitly stored.
    """
    if draft is None:
        return _default_style_direction(persona)

    style_direction = draft.get("style_direction", "")
    if style_direction:
        return style_direction

    return _default_style_direction(persona)


def _default_style_direction(persona: str) -> str:
    """Map persona to default style direction."""
    defaults = {
        "意象师": "诗意",
        "节奏师": "克制",
        "对话师": "生活化",
        "结构师": "极简",
    }
    return defaults.get(persona, "未定义")
