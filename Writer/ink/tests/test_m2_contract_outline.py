from __future__ import annotations

import json

import pytest

from ink.contract.loader import load_shot_contract
from ink.contract.task_card import TaskCardCompiler
from ink.errors import DataIntegrityError
from ink.outline.drift import cjk_bigram_overlap, is_drift_rejected
from ink.outline.repository import OutlineRepository
from test_schema_contract import NOW, insert_minimal_draft, make_schema_db


def test_contract_loader_reloads_full_projection_from_db() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    insert_contract_children(conn, int(ids["shot_contract_id"]))

    contract = load_shot_contract(conn, str(ids["shot_id"]), int(ids["run_id"]))

    assert contract.shot_id == ids["shot_id"]
    assert contract.must_land["events"] == ["enter room"]
    assert contract.anti_write["pov_only"] == ["A"]
    assert contract.scene_contract["location"] == "archive"
    assert contract.persona_assignment["persona"] == "意象师"
    assert contract.soft_constraints["deviation_budget"] == 0.2


def test_task_card_compiler_rejects_incomplete_tail_and_supersedes_old_cards() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    compiler = TaskCardCompiler(conn)

    with pytest.raises(DataIntegrityError):
        compiler.write_task_card(int(ids["shot_contract_id"]), "把角色推到门边，然后")

    conn.commit()
    new_id = compiler.write_task_card(int(ids["shot_contract_id"]), "把角色推到门边。")

    rows = conn.execute(
        """
        SELECT task_card_id, superseded_at
        FROM writing_shot_task_cards
        WHERE shot_contract_id = ?
        ORDER BY task_card_id
        """,
        (ids["shot_contract_id"],),
    ).fetchall()
    assert rows[0][1] is not None
    assert rows[-1] == (new_id, None)


def test_outline_drift_threshold_and_winner_uniqueness() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    conn.commit()
    repo = OutlineRepository(conn)

    high = cjk_bigram_overlap("她走进档案室发现钥匙", "她走进档案室发现钥匙")
    low = cjk_bigram_overlap("她走进档案室发现钥匙", "城市雨夜无人回头")
    assert high == 1.0
    assert low < 0.2
    assert is_drift_rejected(low, 0.2) is True

    outline_a = repo.add_outline(int(ids["shot_contract_id"]), "outline a", high)
    outline_b = repo.add_outline(int(ids["shot_contract_id"]), "outline b", high)
    repo.select_winner(int(ids["shot_contract_id"]), outline_a)
    repo.select_winner(int(ids["shot_contract_id"]), outline_b)

    rows = conn.execute(
        "SELECT outline_id FROM writing_outline_specs WHERE shot_contract_id = ? AND is_winner = 1",
        (ids["shot_contract_id"],),
    ).fetchall()
    assert rows == [(outline_b,)]


def insert_contract_children(conn, shot_contract_id: int) -> None:
    conn.execute(
        """
        INSERT INTO writing_shot_must_land
            (shot_contract_id, events, beats, information_releases)
        VALUES (?, ?, ?, ?)
        """,
        (
            shot_contract_id,
            json.dumps(["enter room"]),
            json.dumps(["beat one"]),
            json.dumps(["key reveal"]),
        ),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_anti_write
            (shot_contract_id, forbidden_facts, forbidden_words, pov_only)
        VALUES (?, ?, ?, ?)
        """,
        (shot_contract_id, json.dumps([]), json.dumps(["突然"]), json.dumps(["A"])),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_scene_contract
            (shot_contract_id, location, time_of_day, characters_present, character_positions)
        VALUES (?, 'archive', 'night', ?, ?)
        """,
        (shot_contract_id, json.dumps(["A"]), json.dumps({"A": "door"})),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_persona_assignment
            (shot_contract_id, persona, intensity, is_creative_shot, is_suspense_shot)
        VALUES (?, '意象师', ?, 0, 1)
        """,
        (
            shot_contract_id,
            json.dumps({"画面": 8, "节奏": 5, "对话": 3, "结构": 6, "悬疑": 6}, ensure_ascii=False),
        ),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_soft_constraints
            (shot_contract_id, relaxable_rules, deviation_budget)
        VALUES (?, ?, 0.2)
        """,
        (shot_contract_id, json.dumps(["metaphor"])),
    )
