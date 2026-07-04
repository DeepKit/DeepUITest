from __future__ import annotations

import sqlite3


SELECT_SESSION_SHOTS_SQL = """
SELECT s.shot_id, s.run_id, s.status, s.updated_at
FROM writing_shots s
JOIN writing_runs r ON r.run_id = s.run_id
WHERE r.session_id = ?
ORDER BY s.updated_at, s.shot_id
"""


def load_session_shots(conn: sqlite3.Connection, session_id: int) -> list[sqlite3.Row | tuple]:
    return list(conn.execute(SELECT_SESSION_SHOTS_SQL, (session_id,)))
