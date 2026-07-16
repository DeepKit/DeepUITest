from __future__ import annotations

import sqlite3

import pytest

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.errors import DataIntegrityError
from ink.pipeline import generation_round_real_ports as real_ports
from factories import NOW, make_schema_db


def _round_fixture() -> tuple[sqlite3.Connection, ChapterSnapshotRepository, int, int]:
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'real-ports', 'Real Ports',
             '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c"]', ?)
        """,
        (NOW,),
    )
    repo = ChapterSnapshotRepository(conn)
    round_id = repo.create_generation_round(
        project_id=1, chapter_id=1, round_number=1
    )
    branch_id = repo.create_branch(
        generation_round_id=round_id,
        candidate_index=1,
        writer_model="writer-a",
        generation_strategy="real-llm",
    )
    return conn, repo, round_id, branch_id


def test_real_generation_write_fails_closed_without_active_scene_contract() -> None:
    conn, repo, _round_id, branch_id = _round_fixture()

    with pytest.raises(DataIntegrityError, match="requires an active Scene Contract"):
        real_ports._write_branch_text(
            repo, branch_id=branch_id, version=1, text="候选正文。"
        )

    assert conn.execute(
        "SELECT COUNT(*) FROM writing_chapter_candidate_branch_versions"
    ).fetchone()[0] == 0
    assert conn.execute(
        "SELECT COUNT(*) FROM writing_scene_revisions"
    ).fetchone()[0] == 0


def test_real_selection_port_is_decision_only(monkeypatch: pytest.MonkeyPatch) -> None:
    conn, repo, round_id, branch_id = _round_fixture()
    conn.execute(
        "UPDATE writing_chapter_candidate_branches SET status = 'literary_review' "
        "WHERE branch_id = ?",
        (branch_id,),
    )
    candidate = real_ports.CandidateText(
        branch_id=branch_id, candidate_index=1, text="正文"
    )
    monkeypatch.setattr(
        real_ports,
        "_eligible_candidates",
        lambda _repo, *, round_id: [candidate],
    )
    port = real_ports.RealSelectionPort(gateway=None, project_id=1)  # type: ignore[arg-type]
    monkeypatch.setattr(
        port,
        "_rank",
        lambda *, round_id, candidates: [
            real_ports._ScoredCandidate(
                branch_id=branch_id,
                candidate_index=1,
                scores={dimension: 90 for dimension in real_ports.RealValidationPort.DIMENSIONS},
            )
        ],
    )

    winner = port.select_winner(conn, repo, round_id=round_id)

    assert winner == branch_id
    assert conn.execute(
        "SELECT status FROM writing_chapter_candidate_branches WHERE branch_id = ?",
        (branch_id,),
    ).fetchone()[0] == "literary_review"
    assert repo.get_generation_round_state(round_id=round_id).status == "planned"


def test_round_idempotency_key_is_stable() -> None:
    assert real_ports._idem_key("generate", 7, 3) == "round-7-generate-3"
    assert real_ports._idem_key("generate", 7, 3) == real_ports._idem_key(
        "generate", 7, 3
    )


def test_jury_parsers_fail_closed_on_non_protocol_output() -> None:
    with pytest.raises(real_ports._SelectionError, match="not parseable"):
        real_ports._parse_bool("看起来差异很大")

    with pytest.raises(real_ports._SelectionError, match="omitted or malformed"):
        real_ports._parse_scores(
            '{"narrative_tension": 88}', real_ports.RealValidationPort.DIMENSIONS
        )
