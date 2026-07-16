from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Iterable

from ink.event_log import EventLog, EventRecord


@dataclass
class ReplayedState:
    stream: str
    identity: dict[str, object]
    status: str = "unknown"
    state: dict[str, Any] = field(default_factory=dict)
    applied_event_ids: list[int] = field(default_factory=list)
    last_event_at: str | None = None

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


class EventReplay:
    """Deterministically reduce append-only events into an inspectable state."""

    def __init__(self, conn: Any) -> None:
        self.log = EventLog(conn)

    def session(
        self,
        decision_session_id: int,
        *,
        at_event_id: int | None = None,
        at_time: str | None = None,
    ) -> ReplayedState:
        events = self.log.replay_session(decision_session_id)
        return _reduce(
            "decision_session",
            {"decision_session_id": decision_session_id},
            _bounded(events, at_event_id=at_event_id, at_time=at_time),
        )

    def contract(
        self,
        project_id: int,
        scope_type: str,
        scope_id: str | None = None,
        *,
        at_event_id: int | None = None,
        at_time: str | None = None,
    ) -> ReplayedState:
        events = self.log.replay_version(project_id, scope_type, scope_id)
        return _reduce(
            "contract_version",
            {
                "project_id": project_id,
                "scope_type": scope_type,
                "scope_id": scope_id,
            },
            _bounded(events, at_event_id=at_event_id, at_time=at_time),
        )


def _bounded(
    events: Iterable[EventRecord],
    *,
    at_event_id: int | None,
    at_time: str | None,
) -> list[EventRecord]:
    if at_event_id is not None and at_event_id < 1:
        raise ValueError("at_event_id must be positive")
    return [
        event
        for event in events
        if (at_event_id is None or event.event_id <= at_event_id)
        and (at_time is None or event.created_at <= at_time)
    ]


def _reduce(
    stream: str,
    identity: dict[str, object],
    events: Iterable[EventRecord],
) -> ReplayedState:
    replayed = ReplayedState(stream=stream, identity=identity)
    for event in events:
        replayed.status = event.event_type
        replayed.state.update(event.payload)
        replayed.state["last_event_type"] = event.event_type
        replayed.applied_event_ids.append(event.event_id)
        replayed.last_event_at = event.created_at
    replayed.state["event_count"] = len(replayed.applied_event_ids)
    return replayed
