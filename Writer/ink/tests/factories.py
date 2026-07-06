from __future__ import annotations

import sqlite3

from ink.schema import connect_memory, initialize_schema


NOW = "2026-07-04T00:00:00.000Z"
SCORE_COLUMNS = (
    "scene_visual",
    "rhythm_pacing",
    "dialogue_subtext",
    "suspense_tension",
    "language_texture",
    "emotional_progression",
    "character_believability",
    "structure_landing",
    "reading_fluency",
    "motif_theme_fit",
    "chapter_continuity",
    "creative_boundary",
)


def make_schema_db() -> sqlite3.Connection:
    return initialize_schema(connect_memory())


def insert_minimal_draft(conn: sqlite3.Connection, writer_model: str = "writer-a") -> dict[str, int | str]:
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'demo', 'Demo', '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
        """,
        (NOW,),
    )
    conn.execute(
        "INSERT INTO writing_sessions (session_id, project_id, started_at) VALUES (10, 1, ?)",
        (NOW,),
    )
    conn.execute(
        """
        INSERT INTO writing_runs
            (run_id, project_id, session_id, run_attempt, started_at, status)
        VALUES (20, 1, 10, 1, ?, 'running')
        """,
        (NOW,),
    )
    cur = conn.execute(
        """
        INSERT INTO writing_shot_contracts
            (project_id, chapter_id, run_id, logical_shot_id, created_at, updated_at)
        VALUES (1, 1, 20, 'shot-001', ?, ?)
        """,
        (NOW, NOW),
    )
    shot_contract_id = cur.lastrowid
    cur = conn.execute(
        """
        INSERT INTO writing_shot_task_cards
            (shot_contract_id, compiled_instructions, created_at)
        VALUES (?, 'write the scene', ?)
        """,
        (shot_contract_id, NOW),
    )
    task_card_id = cur.lastrowid
    cur = conn.execute(
        """
        INSERT INTO writing_prompt_snapshots
            (task_card_id, persona, full_prompt_text, prompt_size_bytes, created_at)
        VALUES (?, 'text', 'prompt', 6, ?)
        """,
        (task_card_id, NOW),
    )
    prompt_id = cur.lastrowid
    shot_id = "shot-001@20"
    conn.execute(
        """
        INSERT INTO writing_shots
            (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id,
             status, created_at, updated_at)
        VALUES (?, 1, 1, ?, 20, 'shot-001', 'pending', ?, ?)
        """,
        (shot_id, shot_contract_id, NOW, NOW),
    )
    cur = conn.execute(
        """
        INSERT INTO writing_drafts
            (shot_id, prompt_id, persona, writer_model, text, byte_count, created_at)
        VALUES (?, ?, 'text', ?, 'draft text', 10, ?)
        """,
        (shot_id, prompt_id, writer_model, NOW),
    )
    return {
        "project_id": 1,
        "session_id": 10,
        "run_id": 20,
        "shot_contract_id": shot_contract_id,
        "task_card_id": task_card_id,
        "prompt_id": prompt_id,
        "shot_id": shot_id,
        "draft_id": cur.lastrowid,
    }


def insert_raw_score(
    conn: sqlite3.Connection,
    draft_id: int | str,
    shot_contract_id: int | str,
    jury_round: int,
    judge_slot: int,
    judge_model: str,
    judge_role: str,
) -> None:
    columns = ", ".join(SCORE_COLUMNS)
    placeholders = ", ".join(["?"] * len(SCORE_COLUMNS))
    scores = [80] * len(SCORE_COLUMNS)
    conn.execute(
        f"""
        INSERT INTO writing_jury_raw_scores
            (draft_id, shot_contract_id, jury_round, judge_slot, judge_model, judge_role,
             {columns}, evaluated_at)
        VALUES (?, ?, ?, ?, ?, ?, {placeholders}, ?)
        """,
        (draft_id, shot_contract_id, jury_round, judge_slot, judge_model, judge_role, *scores, NOW),
    )
