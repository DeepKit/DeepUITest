from __future__ import annotations

import pytest

from factories import make_schema_db
from ink.decision_sessions import DecisionSessionStore
from ink.event_log import EventLog
from ink.event_replay import EventReplay


@pytest.fixture
def conn():
    connection = make_schema_db()
    connection.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'replay', 'Replay',
                '["writer-a","writer-b","writer-c"]',
                '["judge-a","judge-b","judge-c","judge-d","judge-e"]',
                '2026-07-11T00:00:00Z')
        """
    )
    session_id = DecisionSessionStore(connection).start(
        project_id=1,
        scope_type="book",
        scope_id=None,
        target_type="BookContract",
        target_id="book",
        human_text="start",
    )
    assert session_id == 1
    yield connection
    connection.close()


def test_session_replay_rebuilds_latest_and_historical_state(conn) -> None:
    log = EventLog(conn)
    created = conn.execute(
        "SELECT event_id FROM writing_decision_session_events WHERE decision_session_id = 1"
    ).fetchone()[0]
    parsed = log.log_session_event(1, "ai_parsed", {"phase": "parsed", "confidence": 0.8})
    log.log_session_event(1, "confirmed", {"contract_version_id": 7})

    latest = EventReplay(conn).session(1)
    historical = EventReplay(conn).session(1, at_event_id=parsed)

    assert latest.status == "confirmed"
    assert latest.state["phase"] == "parsed"
    assert latest.state["contract_version_id"] == 7
    assert latest.state["event_count"] == 3
    assert historical.status == "ai_parsed"
    assert historical.applied_event_ids == [created, parsed]
    assert "contract_version_id" not in historical.state


def test_contract_replay_supports_event_and_time_bounds(conn) -> None:
    log = EventLog(conn)
    first = log.log_version_event(1, "created", "book", {"version": 1})
    log.log_version_event(1, "confirmed", "book", {"confirmed_by": "author"})
    first_time = conn.execute(
        "SELECT created_at FROM writing_contract_version_events WHERE event_id = ?",
        (first,),
    ).fetchone()[0]

    by_event = EventReplay(conn).contract(1, "book", at_event_id=first)
    by_time = EventReplay(conn).contract(1, "book", at_time=str(first_time))

    assert by_event.status == "created"
    assert by_event.state["version"] == 1
    assert by_time.applied_event_ids


def test_replay_rejects_invalid_event_bound(conn) -> None:
    with pytest.raises(ValueError, match="positive"):
        EventReplay(conn).session(1, at_event_id=0)
