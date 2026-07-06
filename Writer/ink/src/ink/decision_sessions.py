from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from typing import Sequence

from ink.errors import DataIntegrityError
from ink.time import now_utc_iso


@dataclass(frozen=True)
class DecisionSessionRecord:
    decision_session_id: int
    project_id: int
    status: str
    target_type: str
    target_id: str | None


class DecisionSessionStore:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def start(
        self,
        *,
        project_id: int,
        scope_type: str,
        scope_id: str | None,
        target_type: str,
        target_id: str | None,
        human_text: str,
        parent_decision_session_id: int | None = None,
    ) -> int:
        now = now_utc_iso()
        cursor = self.conn.execute(
            """
            INSERT INTO writing_decision_sessions
                (project_id, scope_type, scope_id, target_type, target_id,
                 parent_decision_session_id, status, human_text, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 'collecting', ?, ?, ?)
            """,
            (
                project_id,
                scope_type,
                scope_id,
                target_type,
                target_id,
                parent_decision_session_id,
                human_text,
                now,
                now,
            ),
        )
        return int(cursor.lastrowid)

    def record_ai_parse(
        self,
        decision_session_id: int,
        *,
        parsed_patch: dict[str, object],
        readback_text: str,
        source_hashes: Sequence[str],
        before_hash: str | None = None,
    ) -> None:
        now = now_utc_iso()
        updated = self.conn.execute(
            """
            UPDATE writing_decision_sessions
            SET status = 'ai_parsed',
                parsed_patch_json = ?,
                readback_text = ?,
                source_hashes_json = ?,
                before_hash = COALESCE(?, before_hash),
                updated_at = ?
            WHERE decision_session_id = ?
              AND status IN ('collecting','retryable_failed','needs_human','stale')
            """,
            (
                _json(parsed_patch),
                readback_text,
                _json(list(source_hashes)),
                before_hash,
                now,
                decision_session_id,
            ),
        ).rowcount
        if updated != 1:
            raise DataIntegrityError(f"decision session is not parseable: {decision_session_id}")

    def create_option_set(
        self,
        decision_session_id: int,
        *,
        options: Sequence[dict[str, object]],
        recommended_option: int | None = None,
    ) -> int:
        _validate_options(options, recommended_option)
        now = now_utc_iso()
        try:
            self.conn.execute("SAVEPOINT decision_option_set")
            version = _next_option_version(self.conn, decision_session_id)
            cursor = self.conn.execute(
                """
                INSERT INTO writing_decision_option_sets
                    (decision_session_id, version, options_json, recommended_option, regenerate_count,
                     status, created_at)
                VALUES (?, ?, ?, ?, 0, 'active', ?)
                """,
                (decision_session_id, version, _json(list(options)), recommended_option, now),
            )
            updated = self.conn.execute(
                """
                UPDATE writing_decision_sessions
                SET status = 'awaiting_confirm', updated_at = ?
                WHERE decision_session_id = ? AND status = 'ai_parsed'
                """,
                (now, decision_session_id),
            ).rowcount
            if updated != 1:
                raise DataIntegrityError(f"decision session is not ready for options: {decision_session_id}")
        except Exception:
            self.conn.execute("ROLLBACK TO decision_option_set")
            self.conn.execute("RELEASE decision_option_set")
            raise
        else:
            self.conn.execute("RELEASE decision_option_set")
            return int(cursor.lastrowid)

    def regenerate_options(
        self,
        decision_session_id: int,
        *,
        options: Sequence[dict[str, object]],
        recommended_option: int | None = None,
    ) -> int:
        _validate_options(options, recommended_option)
        current = _load_active_option_set(self.conn, decision_session_id)
        now = now_utc_iso()
        try:
            self.conn.execute("SAVEPOINT decision_option_regenerate")
            self.conn.execute(
                """
                UPDATE writing_decision_option_sets
                SET status = 'superseded'
                WHERE option_set_id = ?
                """,
                (int(current["option_set_id"]),),
            )
            cursor = self.conn.execute(
                """
                INSERT INTO writing_decision_option_sets
                    (decision_session_id, version, options_json, recommended_option, regenerate_count,
                     status, created_at)
                VALUES (?, ?, ?, ?, ?, 'active', ?)
                """,
                (
                    decision_session_id,
                    int(current["version"]) + 1,
                    _json(list(options)),
                    recommended_option,
                    int(current["regenerate_count"]) + 1,
                    now,
                ),
            )
            self.conn.execute(
                """
                UPDATE writing_decision_sessions
                SET selected_option = NULL, updated_at = ?
                WHERE decision_session_id = ? AND status = 'awaiting_confirm'
                """,
                (now, decision_session_id),
            )
        except Exception:
            self.conn.execute("ROLLBACK TO decision_option_regenerate")
            self.conn.execute("RELEASE decision_option_regenerate")
            raise
        else:
            self.conn.execute("RELEASE decision_option_regenerate")
            return int(cursor.lastrowid)

    def select_option(self, decision_session_id: int, selected_option: int) -> None:
        if selected_option == 9:
            raise DataIntegrityError("option 9 requires regenerate_options() with a new option set")
        current = _load_active_option_set(self.conn, decision_session_id)
        if selected_option == 0:
            self._return_to_collecting(decision_session_id, int(current["option_set_id"]))
            return
        options = json.loads(str(current["options_json"]))
        if not isinstance(options, list) or selected_option < 1 or selected_option > len(options):
            raise DataIntegrityError(f"selected option is outside the active option set: {selected_option}")
        now = now_utc_iso()
        try:
            self.conn.execute("SAVEPOINT decision_option_select")
            self.conn.execute(
                "UPDATE writing_decision_option_sets SET status = 'selected' WHERE option_set_id = ?",
                (int(current["option_set_id"]),),
            )
            updated = self.conn.execute(
                """
                UPDATE writing_decision_sessions
                SET selected_option = ?, updated_at = ?
                WHERE decision_session_id = ? AND status = 'awaiting_confirm'
                """,
                (selected_option, now, decision_session_id),
            ).rowcount
            if updated != 1:
                raise DataIntegrityError(f"decision session is not awaiting confirmation: {decision_session_id}")
        except Exception:
            self.conn.execute("ROLLBACK TO decision_option_select")
            self.conn.execute("RELEASE decision_option_select")
            raise
        else:
            self.conn.execute("RELEASE decision_option_select")

    def confirm(self, decision_session_id: int, *, after_hash: str) -> None:
        row = self.conn.execute(
            """
            SELECT selected_option
            FROM writing_decision_sessions
            WHERE decision_session_id = ? AND status = 'awaiting_confirm'
            """,
            (decision_session_id,),
        ).fetchone()
        if row is None or row[0] is None:
            raise DataIntegrityError(f"decision session has no selected option: {decision_session_id}")
        updated = self.conn.execute(
            """
            UPDATE writing_decision_sessions
            SET status = 'confirmed', after_hash = ?, updated_at = ?
            WHERE decision_session_id = ? AND status = 'awaiting_confirm'
            """,
            (after_hash, now_utc_iso(), decision_session_id),
        ).rowcount
        if updated != 1:
            raise DataIntegrityError(f"decision session cannot be confirmed: {decision_session_id}")

    def _return_to_collecting(self, decision_session_id: int, option_set_id: int) -> None:
        now = now_utc_iso()
        try:
            self.conn.execute("SAVEPOINT decision_option_back")
            self.conn.execute(
                "UPDATE writing_decision_option_sets SET status = 'cancelled' WHERE option_set_id = ?",
                (option_set_id,),
            )
            updated = self.conn.execute(
                """
                UPDATE writing_decision_sessions
                SET status = 'collecting', selected_option = NULL, updated_at = ?
                WHERE decision_session_id = ? AND status = 'awaiting_confirm'
                """,
                (now, decision_session_id),
            ).rowcount
            if updated != 1:
                raise DataIntegrityError(f"decision session cannot return to collecting: {decision_session_id}")
        except Exception:
            self.conn.execute("ROLLBACK TO decision_option_back")
            self.conn.execute("RELEASE decision_option_back")
            raise
        else:
            self.conn.execute("RELEASE decision_option_back")


def _validate_options(options: Sequence[dict[str, object]], recommended_option: int | None) -> None:
    if not 1 <= len(options) <= 8:
        raise DataIntegrityError("option set must contain 1-8 options")
    if recommended_option is not None and not 1 <= recommended_option <= len(options):
        raise DataIntegrityError("recommended option must reference an existing option")


def _next_option_version(conn: sqlite3.Connection, decision_session_id: int) -> int:
    row = conn.execute(
        "SELECT COALESCE(MAX(version), 0) + 1 FROM writing_decision_option_sets WHERE decision_session_id = ?",
        (decision_session_id,),
    ).fetchone()
    return int(row[0])


def _load_active_option_set(conn: sqlite3.Connection, decision_session_id: int) -> dict[str, object]:
    row = conn.execute(
        """
        SELECT option_set_id, version, options_json, regenerate_count
        FROM writing_decision_option_sets
        WHERE decision_session_id = ? AND status = 'active'
        """,
        (decision_session_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"decision session has no active option set: {decision_session_id}")
    return {
        "option_set_id": int(row[0]),
        "version": int(row[1]),
        "options_json": str(row[2]),
        "regenerate_count": int(row[3]),
    }


def _json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)
