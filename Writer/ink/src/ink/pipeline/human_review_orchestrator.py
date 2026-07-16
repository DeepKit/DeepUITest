from __future__ import annotations

import json
import sqlite3
from dataclasses import asdict, dataclass

from ink.core.state_machine import transition
from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError
from ink.pipeline.book_rolling_check_orchestrator import has_blocking_issues
from ink.quality_report import validate_quality_report
from ink.time import now_utc_iso


@dataclass(frozen=True)
class ChapterRevisionResult:
    decision_id: int
    run_id: int
    shot_ids: tuple[str, ...]


class HumanReviewOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def accept_chapter(self, project_id: int, chapter_id: int, run_id: int, *, actor: str, reason: str) -> int:
        review = _load_pending_review(self.conn, project_id, chapter_id, run_id)
        blocking_issues = tuple(json.loads(review["blocking_issues"]))
        if int(review["quality_gate_passed"]) != 1:
            raise DataIntegrityError("human accept cannot override chapter quality failure")
        if has_blocking_issues(self.conn, project_id):
            raise DataIntegrityError("unresolved book blocking issue prevents chapter accept")
        _require_ethics_approval(self.conn, project_id, chapter_id, run_id)

        shots = _load_accept_ready_shots(self.conn, project_id, chapter_id, run_id)
        if not shots:
            raise DataIntegrityError(f"chapter has no soft_sealed shots to accept: {project_id}/{chapter_id}/{run_id}")

        session_id = _lookup_session_id(self.conn, run_id)
        preconditions = {
            "review_id": int(review["review_id"]),
            "quality_gate_passed": True,
            "blocking_issues": list(blocking_issues),
            "soft_sealed_shot_count": len(shots),
        }
        quality_report = _accepted_quality_report(blocking_issues)

        try:
            self.conn.execute("SAVEPOINT human_accept_chapter")
            decision_id = _insert_human_decision(
                self.conn,
                project_id=project_id,
                session_id=session_id,
                run_id=run_id,
                chapter_id=chapter_id,
                decision_type="accept",
                actor=actor,
                reason=reason,
                preconditions=preconditions,
                quality_report=quality_report,
            )
            self.conn.execute(
                "UPDATE writing_chapter_reviews SET status = 'accepted' WHERE review_id = ?",
                (review["review_id"],),
            )
            repo = TextRepository(self.conn)
            for shot_id in shots:
                text = repo.read_current_text(shot_id, run_id)
                repo.write_revision(shot_id, run_id, text, seal="chapter_hard")
                transition(self.conn, shot_id, run_id, "soft_sealed", "hard_sealed")
        except Exception:
            self.conn.execute("ROLLBACK TO human_accept_chapter")
            self.conn.execute("RELEASE human_accept_chapter")
            raise
        else:
            self.conn.execute("RELEASE human_accept_chapter")
            return decision_id

    def reject_chapter(self, project_id: int, chapter_id: int, run_id: int, *, actor: str, reason: str) -> int:
        review = _load_pending_review(self.conn, project_id, chapter_id, run_id)
        session_id = _lookup_session_id(self.conn, run_id)
        preconditions = _review_preconditions(review, action="reject")

        try:
            self.conn.execute("SAVEPOINT human_reject_chapter")
            decision_id = _insert_human_decision(
                self.conn,
                project_id=project_id,
                session_id=session_id,
                run_id=run_id,
                chapter_id=chapter_id,
                decision_type="reject",
                actor=actor,
                reason=reason,
                preconditions=preconditions,
                quality_report={},
            )
            self.conn.execute(
                "UPDATE writing_chapter_reviews SET status = 'rejected' WHERE review_id = ?",
                (review["review_id"],),
            )
        except Exception:
            self.conn.execute("ROLLBACK TO human_reject_chapter")
            self.conn.execute("RELEASE human_reject_chapter")
            raise
        else:
            self.conn.execute("RELEASE human_reject_chapter")
            return decision_id

    def revise_chapter(
        self,
        project_id: int,
        chapter_id: int,
        run_id: int,
        *,
        actor: str,
        reason: str,
    ) -> ChapterRevisionResult:
        review = _load_revision_source_review(self.conn, project_id, chapter_id, run_id)
        old_shots = _load_chapter_shot_contracts(self.conn, project_id, chapter_id, run_id)
        if not old_shots:
            raise DataIntegrityError(f"chapter has no shots to revise: {project_id}/{chapter_id}/{run_id}")
        session_id = _lookup_session_id(self.conn, run_id)

        try:
            self.conn.execute("SAVEPOINT human_revise_chapter")
            new_run_id = _create_revision_run(self.conn, project_id, session_id)
            new_shot_ids = tuple(
                _clone_shot_for_new_run(self.conn, old_shot, project_id, chapter_id, new_run_id)
                for old_shot in old_shots
            )
            preconditions = _review_preconditions(
                review,
                action="revise",
                extra={
                    "source_run_id": run_id,
                    "new_run_id": new_run_id,
                    "new_shot_count": len(new_shot_ids),
                },
            )
            decision_id = _insert_human_decision(
                self.conn,
                project_id=project_id,
                session_id=session_id,
                run_id=run_id,
                chapter_id=chapter_id,
                decision_type="revise",
                actor=actor,
                reason=reason,
                preconditions=preconditions,
                quality_report={},
            )
            if str(review["status"]) == "pending":
                self.conn.execute(
                    "UPDATE writing_chapter_reviews SET status = 'revised' WHERE review_id = ?",
                    (review["review_id"],),
                )
        except Exception:
            self.conn.execute("ROLLBACK TO human_revise_chapter")
            self.conn.execute("RELEASE human_revise_chapter")
            raise
        else:
            self.conn.execute("RELEASE human_revise_chapter")
            return ChapterRevisionResult(decision_id=decision_id, run_id=new_run_id, shot_ids=new_shot_ids)


def _require_ethics_approval(
    conn: sqlite3.Connection,
    project_id: int,
    chapter_id: int,
    run_id: int,
) -> None:
    row = conn.execute(
        "SELECT require_ethics_review FROM writing_projects WHERE project_id=?",
        (project_id,),
    ).fetchone()
    if row is None or int(row[0]) == 0:
        return
    ethics = conn.execute(
        """
        SELECT risk_level, recommendation
        FROM writing_chapter_ethics_reviews
        WHERE project_id=? AND chapter_id=? AND run_id=?
        """,
        (project_id, chapter_id, run_id),
    ).fetchone()
    if ethics is None:
        raise DataIntegrityError("required chapter ethics review is missing")
    if str(ethics[1]) != "approve" or str(ethics[0]) == "blocking":
        raise DataIntegrityError(
            f"chapter ethics review prevents accept: risk={ethics[0]} recommendation={ethics[1]}"
        )


def _load_pending_review(conn: sqlite3.Connection, project_id: int, chapter_id: int, run_id: int) -> dict[str, object]:
    row = conn.execute(
        """
        SELECT review_id, quality_gate_passed, blocking_issues, status
        FROM writing_chapter_reviews
        WHERE project_id = ? AND chapter_id = ? AND run_id = ?
        """,
        (project_id, chapter_id, run_id),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"chapter review not found: {project_id}/{chapter_id}/{run_id}")
    if str(row[3]) != "pending":
        raise DataIntegrityError(f"chapter review must be pending before accept, got: {row[3]}")
    return {
        "review_id": int(row[0]),
        "quality_gate_passed": int(row[1]),
        "blocking_issues": str(row[2]),
        "status": str(row[3]),
    }


def _load_revision_source_review(
    conn: sqlite3.Connection,
    project_id: int,
    chapter_id: int,
    run_id: int,
) -> dict[str, object]:
    row = conn.execute(
        """
        SELECT review_id, quality_gate_passed, blocking_issues, status
        FROM writing_chapter_reviews
        WHERE project_id = ? AND chapter_id = ? AND run_id = ?
        """,
        (project_id, chapter_id, run_id),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"chapter review not found: {project_id}/{chapter_id}/{run_id}")
    if str(row[3]) not in {"pending", "rejected"}:
        raise DataIntegrityError(f"chapter review cannot start revision from status: {row[3]}")
    return {
        "review_id": int(row[0]),
        "quality_gate_passed": int(row[1]),
        "blocking_issues": str(row[2]),
        "status": str(row[3]),
    }


def _load_accept_ready_shots(conn: sqlite3.Connection, project_id: int, chapter_id: int, run_id: int) -> list[str]:
    rows = conn.execute(
        """
        SELECT shot_id, status
        FROM writing_shots
        WHERE project_id = ? AND chapter_id = ? AND run_id = ?
        ORDER BY shot_id
        """,
        (project_id, chapter_id, run_id),
    ).fetchall()
    not_soft_sealed = [str(row[0]) for row in rows if str(row[1]) != "soft_sealed"]
    if not_soft_sealed:
        raise DataIntegrityError(f"human accept requires all shots soft_sealed: {not_soft_sealed}")
    return [str(row[0]) for row in rows]


def _load_chapter_shot_contracts(
    conn: sqlite3.Connection,
    project_id: int,
    chapter_id: int,
    run_id: int,
) -> list[dict[str, object]]:
    rows = conn.execute(
        """
        SELECT s.shot_id, s.logical_shot_id, s.shot_contract_id, c.status
        FROM writing_shots s
        JOIN writing_shot_contracts c ON c.shot_contract_id = s.shot_contract_id
        WHERE s.project_id = ? AND s.chapter_id = ? AND s.run_id = ?
        ORDER BY s.logical_shot_id
        """,
        (project_id, chapter_id, run_id),
    ).fetchall()
    return [
        {
            "shot_id": str(row[0]),
            "logical_shot_id": str(row[1]),
            "shot_contract_id": int(row[2]),
            "contract_status": str(row[3]),
        }
        for row in rows
    ]


def _lookup_session_id(conn: sqlite3.Connection, run_id: int) -> int:
    row = conn.execute("SELECT session_id FROM writing_runs WHERE run_id = ?", (run_id,)).fetchone()
    if row is None:
        raise DataIntegrityError(f"run not found: {run_id}")
    return int(row[0])


def _review_preconditions(
    review: dict[str, object],
    *,
    action: str,
    extra: dict[str, object] | None = None,
) -> dict[str, object]:
    preconditions = {
        "action": action,
        "review_id": int(review["review_id"]),
        "source_review_status": str(review["status"]),
        "quality_gate_passed": int(review["quality_gate_passed"]) == 1,
        "blocking_issues": list(json.loads(str(review["blocking_issues"]))),
    }
    if extra:
        preconditions.update(extra)
    return preconditions


def _create_revision_run(conn: sqlite3.Connection, project_id: int, session_id: int) -> int:
    row = conn.execute(
        "SELECT COALESCE(MAX(run_attempt), 0) + 1 FROM writing_runs WHERE session_id = ?",
        (session_id,),
    ).fetchone()
    cursor = conn.execute(
        """
        INSERT INTO writing_runs
            (project_id, session_id, run_attempt, started_at, status)
        VALUES (?, ?, ?, ?, 'running')
        """,
        (project_id, session_id, int(row[0]), now_utc_iso()),
    )
    return int(cursor.lastrowid)


def _clone_shot_for_new_run(
    conn: sqlite3.Connection,
    old_shot: dict[str, object],
    project_id: int,
    chapter_id: int,
    new_run_id: int,
) -> str:
    old_contract_id = int(old_shot["shot_contract_id"])
    logical_shot_id = str(old_shot["logical_shot_id"])
    now = now_utc_iso()
    cursor = conn.execute(
        """
        INSERT INTO writing_shot_contracts
            (project_id, chapter_id, run_id, logical_shot_id, status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            project_id,
            chapter_id,
            new_run_id,
            logical_shot_id,
            str(old_shot["contract_status"]),
            now,
            now,
        ),
    )
    new_contract_id = int(cursor.lastrowid)
    _clone_contract_children(conn, old_contract_id, new_contract_id)

    new_shot_id = f"{logical_shot_id}@{new_run_id}"
    conn.execute(
        """
        INSERT INTO writing_shots
            (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id,
             status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)
        """,
        (new_shot_id, project_id, chapter_id, new_contract_id, new_run_id, logical_shot_id, now, now),
    )
    return new_shot_id


def _clone_contract_children(conn: sqlite3.Connection, old_contract_id: int, new_contract_id: int) -> None:
    conn.execute(
        """
        INSERT INTO writing_shot_must_land
            (shot_contract_id, events, beats, information_releases)
        SELECT ?, events, beats, information_releases
        FROM writing_shot_must_land
        WHERE shot_contract_id = ?
        """,
        (new_contract_id, old_contract_id),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_anti_write
            (shot_contract_id, forbidden_facts, forbidden_words, pov_only)
        SELECT ?, forbidden_facts, forbidden_words, pov_only
        FROM writing_shot_anti_write
        WHERE shot_contract_id = ?
        """,
        (new_contract_id, old_contract_id),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_scene_contract
            (shot_contract_id, location, time_of_day, characters_present, character_positions)
        SELECT ?, location, time_of_day, characters_present, character_positions
        FROM writing_shot_scene_contract
        WHERE shot_contract_id = ?
        """,
        (new_contract_id, old_contract_id),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_persona_assignment
            (shot_contract_id, persona, intensity, is_creative_shot, is_suspense_shot)
        SELECT ?, persona, intensity, is_creative_shot, is_suspense_shot
        FROM writing_shot_persona_assignment
        WHERE shot_contract_id = ?
        """,
        (new_contract_id, old_contract_id),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_soft_constraints
            (shot_contract_id, relaxable_rules, deviation_budget)
        SELECT ?, relaxable_rules, deviation_budget
        FROM writing_shot_soft_constraints
        WHERE shot_contract_id = ?
        """,
        (new_contract_id, old_contract_id),
    )


def _accepted_quality_report(blocking_issues: tuple[str, ...]) -> dict[str, object]:
    report = {
        "evidence_class": "SEMI_ES",
        "defect_class": "neutral",
        "blind_review_passed": True,
        "would_continue_reading_score": 82,
        "blocking_items": list(blocking_issues),
        "productive_deviations": [],
        "neutral_issues": [],
        "smart_model_required": True,
    }
    validated = validate_quality_report(report)
    return asdict(validated)


def _insert_human_decision(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    session_id: int,
    run_id: int,
    chapter_id: int,
    decision_type: str,
    actor: str,
    reason: str,
    preconditions: dict[str, object],
    quality_report: dict[str, object],
) -> int:
    cursor = conn.execute(
        """
        INSERT INTO writing_human_decisions
            (project_id, session_id, run_id, chapter_id, decision_type, actor, reason,
             preconditions_json, quality_report_json, hard_quality_override, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
        """,
        (
            project_id,
            session_id,
            run_id,
            chapter_id,
            decision_type,
            actor,
            reason,
            json.dumps(preconditions, ensure_ascii=False, sort_keys=True),
            json.dumps(quality_report, ensure_ascii=False, sort_keys=True),
            now_utc_iso(),
        ),
    )
    return int(cursor.lastrowid)
