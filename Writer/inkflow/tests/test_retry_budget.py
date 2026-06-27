"""Tests for retry budget failure attribution."""

from __future__ import annotations

import json


def test_chapter_hook_failure_type_is_recorded(db):
    from inkflow.services.retry_budget import RetryBudgetService

    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    db.execute(
        "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
        "VALUES ('s1', 'proj_01', 'run_01', 'active')"
    )
    db.execute(
        "INSERT INTO writing_shots "
        "(shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
        "VALUES ('shot_01', 'proj_01', 'run_01', 'v01.c02', 1, 'pending')"
    )
    db.commit()

    budget = RetryBudgetService(db, "run_01")
    result = budget.record_failure(
        "shot_01",
        "chapter_hook_weak",
        detail="final shot closed",
    )

    row = db.execute(
        "SELECT failure_signature_json FROM writing_shots WHERE shot_id = 'shot_01'"
    ).fetchone()
    signature = json.loads(row["failure_signature_json"])
    assert result["failure_type"] == "chapter_hook_weak"
    assert signature["last_failure_type"] == "chapter_hook_weak"


def test_jury_unavailable_failure_type_is_recorded(db):
    from inkflow.services.retry_budget import RetryBudgetService

    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    db.execute(
        "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
        "VALUES ('s1', 'proj_01', 'run_01', 'active')"
    )
    db.execute(
        "INSERT INTO writing_shots "
        "(shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
        "VALUES ('shot_01', 'proj_01', 'run_01', 'v01.c02', 1, 'pending')"
    )
    db.commit()

    budget = RetryBudgetService(db, "run_01")
    result = budget.record_failure(
        "shot_01",
        "jury_unavailable",
        detail="missing_dimensions=reading_fluency",
    )

    row = db.execute(
        "SELECT failure_signature_json FROM writing_shots WHERE shot_id = 'shot_01'"
    ).fetchone()
    signature = json.loads(row["failure_signature_json"])
    assert result["failure_type"] == "jury_unavailable"
    assert signature["last_failure_type"] == "jury_unavailable"


def test_l3_chapter_hook_issue_classifies_specifically():
    from inkflow.services.retry_budget import classify_failure_type

    failure_type = classify_failure_type(
        gate1_violations=[],
        l3_issues=[
            "chapter_hook_weak: final shot must end on unfinished action",
        ],
    )

    assert failure_type == "chapter_hook_weak"


def test_circuit_breaker_triggers_on_threshold_failure(db):
    from inkflow.services.retry_budget import (
        CircuitBreakerTriggered,
        RetryBudgetService,
    )

    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    db.execute(
        "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
        "VALUES ('s1', 'proj_01', 'run_01', 'active')"
    )
    db.execute(
        "INSERT INTO writing_shots "
        "(shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
        "VALUES ('shot_01', 'proj_01', 'run_01', 'v01.c02', 1, 'pending')"
    )
    db.commit()

    budget = RetryBudgetService(db, "run_01", circuit_breaker_threshold=3)
    budget.record_failure("shot_01", "below_threshold")
    budget.record_failure("shot_01", "below_threshold")

    try:
        budget.record_failure("shot_01", "below_threshold")
        assert False, "expected circuit breaker"
    except CircuitBreakerTriggered:
        pass

    row = db.execute(
        "SELECT shot_status, failure_signature_json FROM writing_shots "
        "WHERE shot_id = 'shot_01'"
    ).fetchone()
    signature = json.loads(row["failure_signature_json"])
    assert row["shot_status"] == "done_red_permanent"
    assert signature["consecutive_count"] == 3


def test_circuit_breaker_resets_consecutive_count_on_type_switch(db):
    from inkflow.services.retry_budget import RetryBudgetService

    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    db.execute(
        "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
        "VALUES ('s1', 'proj_01', 'run_01', 'active')"
    )
    db.execute(
        "INSERT INTO writing_shots "
        "(shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
        "VALUES ('shot_01', 'proj_01', 'run_01', 'v01.c02', 1, 'pending')"
    )
    db.commit()

    budget = RetryBudgetService(db, "run_01", circuit_breaker_threshold=3)
    budget.record_failure("shot_01", "below_threshold")
    budget.record_failure("shot_01", "below_threshold")
    result = budget.record_failure("shot_01", "jury_unavailable")

    row = db.execute(
        "SELECT shot_status, failure_signature_json FROM writing_shots "
        "WHERE shot_id = 'shot_01'"
    ).fetchone()
    signature = json.loads(row["failure_signature_json"])
    assert result["consecutive_count"] == 1
    assert row["shot_status"] == "pending"
    assert signature["last_failure_type"] == "jury_unavailable"
    assert signature["consecutive_count"] == 1
