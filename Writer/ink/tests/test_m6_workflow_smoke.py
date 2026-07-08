from __future__ import annotations

import json
from pathlib import Path

import pytest

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.core.resume import ResumeManager
from ink.errors import DataIntegrityError
from ink.pipeline.book_rolling_check_orchestrator import BookRollingCheckOrchestrator
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.pipeline.export_orchestrator import ExportOrchestrator
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from ink.pipeline.import_orchestrator import ImportOrchestrator
from ink.pipeline.jury_orchestrator import JuryOrchestrator
from ink.pipeline.polish_orchestrator import PolishOrchestrator
from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator
from ink.pipeline.resume_handlers import build_shot_resume_handlers
from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator
from test_m2_contract_outline import insert_chinese_contract_children
from factories import NOW, make_schema_db


PROJECT_ID = 1
SESSION_ID = 10
INITIAL_RUN_ID = 20


def test_full_production_flow_six_chapters(tmp_path: Path) -> None:
    conn = make_six_chapter_project()
    provider = WorkflowProvider()
    gateway = LLMGateway(conn, provider=provider)
    accepted_runs: dict[int, int] = {}

    for chapter_id in range(1, 7):
        shot_id, run_id = _chapter_shot(conn, chapter_id, INITIAL_RUN_ID)
        _run_shot_to_soft_sealed(conn, shot_id, run_id, gateway, use_resume=chapter_id == 3)
        ChapterReviewOrchestrator(conn).review_chapter(PROJECT_ID, chapter_id, run_id)

        if chapter_id == 2:
            HumanReviewOrchestrator(conn).reject_chapter(
                PROJECT_ID,
                chapter_id,
                run_id,
                actor="author",
                reason="reject first pass before revision",
            )
            revised = HumanReviewOrchestrator(conn).revise_chapter(
                PROJECT_ID,
                chapter_id,
                run_id,
                actor="author",
                reason="start revised run after rejection",
            )
            _run_shot_to_soft_sealed(conn, revised.shot_ids[0], revised.run_id, gateway)
            ChapterReviewOrchestrator(conn).review_chapter(PROJECT_ID, chapter_id, revised.run_id)
            HumanReviewOrchestrator(conn).accept_chapter(
                PROJECT_ID,
                chapter_id,
                revised.run_id,
                actor="author",
                reason="accept revised chapter",
            )
            accepted_runs[chapter_id] = revised.run_id
        else:
            HumanReviewOrchestrator(conn).accept_chapter(
                PROJECT_ID,
                chapter_id,
                run_id,
                actor="author",
                reason=f"accept chapter {chapter_id}",
            )
            accepted_runs[chapter_id] = run_id

        book_check = BookRollingCheckOrchestrator(conn).run_if_due(PROJECT_ID, chapter_id)
        if chapter_id == 5:
            assert book_check is not None
            assert book_check.chapter_range_start == 1
            assert book_check.chapter_range_end == 5
            assert book_check.quality_gate_passed is True
        else:
            assert book_check is None

    artifact = ExportOrchestrator(conn).export_project(PROJECT_ID)
    source_root = tmp_path / "legacy"
    source_root.mkdir()
    (source_root / "accepted.md").write_text(artifact, encoding="utf-8")
    dry_run = ImportOrchestrator(conn).dry_run(PROJECT_ID, str(source_root))
    ImportOrchestrator(conn).finalize(
        dry_run.import_run_id,
        actor="author",
        reason="finalize smoke import",
    )

    assert accepted_runs[2] != INITIAL_RUN_ID
    assert artifact.count("polished text") == 6
    assert conn.execute("SELECT count(*) FROM writing_chapter_reviews WHERE status = 'accepted'").fetchone()[0] == 6
    assert conn.execute("SELECT count(*) FROM writing_chapter_reviews WHERE status = 'rejected'").fetchone()[0] == 1
    assert conn.execute("SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'accept'").fetchone()[0] == 6
    assert conn.execute("SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'reject'").fetchone()[0] == 1
    assert conn.execute("SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'revise'").fetchone()[0] == 1
    assert conn.execute("SELECT count(*) FROM writing_human_decisions WHERE decision_type = 'import_finalize'").fetchone()[0] == 1
    assert conn.execute("SELECT count(*) FROM writing_book_check_results").fetchone()[0] == 1
    assert conn.execute(
        """
        SELECT count(*)
        FROM writing_jury_aggregates a
        JOIN writing_drafts d ON d.draft_id = a.draft_id
        WHERE a.is_winner = 1 AND d.degraded = 1
        """
    ).fetchone()[0] == 0
    assert conn.execute("SELECT count(*) FROM writing_runtime_events WHERE event_type = 'EXPORT_COMPLETED'").fetchone()[0] == 1


def test_rejected_chapter_cannot_be_accepted() -> None:
    conn = make_six_chapter_project()
    gateway = LLMGateway(conn, provider=WorkflowProvider())
    shot_id, run_id = _chapter_shot(conn, 1, INITIAL_RUN_ID)
    _run_shot_to_soft_sealed(conn, shot_id, run_id, gateway)
    ChapterReviewOrchestrator(conn).review_chapter(PROJECT_ID, 1, run_id)
    HumanReviewOrchestrator(conn).reject_chapter(
        PROJECT_ID,
        1,
        run_id,
        actor="author",
        reason="reject first pass",
    )

    with pytest.raises(DataIntegrityError, match="must be pending"):
        HumanReviewOrchestrator(conn).accept_chapter(
            PROJECT_ID,
            1,
            run_id,
            actor="author",
            reason="cannot accept rejected review",
        )


def make_six_chapter_project():
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES
            (1, 'workflow-demo', 'Workflow Demo', '["writer-a","writer-b","writer-c"]',
             '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
        """,
        (NOW,),
    )
    conn.execute(
        "INSERT INTO writing_sessions (session_id, project_id, started_at) VALUES (?, ?, ?)",
        (SESSION_ID, PROJECT_ID, NOW),
    )
    conn.execute(
        """
        INSERT INTO writing_runs
            (run_id, project_id, session_id, run_attempt, started_at, status)
        VALUES (?, ?, ?, 1, ?, 'running')
        """,
        (INITIAL_RUN_ID, PROJECT_ID, SESSION_ID, NOW),
    )
    for chapter_id in range(1, 7):
        logical_shot_id = f"ch-{chapter_id:02d}-shot-001"
        cursor = conn.execute(
            """
            INSERT INTO writing_shot_contracts
                (project_id, chapter_id, run_id, logical_shot_id, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, 'confirmed', ?, ?)
            """,
            (PROJECT_ID, chapter_id, INITIAL_RUN_ID, logical_shot_id, NOW, NOW),
        )
        shot_contract_id = int(cursor.lastrowid)
        insert_chinese_contract_children(conn, shot_contract_id)
        conn.execute(
            """
            INSERT INTO writing_shots
                (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id,
                 status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)
            """,
            (
                f"{logical_shot_id}@{INITIAL_RUN_ID}",
                PROJECT_ID,
                chapter_id,
                shot_contract_id,
                INITIAL_RUN_ID,
                logical_shot_id,
                NOW,
                NOW,
            ),
        )
    # jury 真实化后每个 judge 调一次 gateway.call（3 draft×3 judge=9 次 / 每轮，两轮重评=18 次），
    # 超 schema 默认 max_calls_per_shot=8 会触发 per_type_exceeded 熔断。测试放宽预算。
    conn.execute(
        "UPDATE writing_projects SET max_calls_per_shot = 50, max_total_llm_calls = 200, "
        "consecutive_failure_circuit_break = 100 WHERE project_id = ?",
        (PROJECT_ID,),
    )
    return conn


def _chapter_shot(conn, chapter_id: int, run_id: int) -> tuple[str, int]:
    row = conn.execute(
        """
        SELECT shot_id, run_id
        FROM writing_shots
        WHERE project_id = ? AND chapter_id = ? AND run_id = ?
        """,
        (PROJECT_ID, chapter_id, run_id),
    ).fetchone()
    return str(row[0]), int(row[1])


def _run_shot_to_soft_sealed(conn, shot_id: str, run_id: int, gateway: LLMGateway, *, use_resume: bool = False) -> None:
    PreDraftingOrchestrator(conn, gateway).run_until_prompt_compiled(shot_id, run_id)
    if use_resume:
        manager = ResumeManager(conn)
        action = manager.resume_shot(SESSION_ID, shot_id, run_id)
        assert action == "rerun_prompt"
        manager.execute_resume_action(shot_id, run_id, action, build_shot_resume_handlers(conn, gateway))
    WriteOrchestrator(conn, gateway).produce_drafts(shot_id, run_id)
    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn, gateway).score_and_select_winner(shot_id, run_id)
    PolishOrchestrator(conn, gateway).polish_winner(shot_id, run_id)
    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn, gateway).score_and_select_winner(shot_id, run_id)
    SoftSealOrchestrator(conn).soft_seal_if_polished(shot_id, run_id)
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (shot_id,)).fetchone()[0] == "soft_sealed"


class WorkflowProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        if idempotency_key.startswith("outline:"):
            source = prompt_text.split("Contract source: ", 1)[1].splitlines()[0]
            text = f"{source} 推进"
        elif idempotency_key.startswith("polish:"):
            text = f"polished text {idempotency_key}"
        elif idempotency_key.startswith("jury:"):
            # jury 真实化后评分返回 12 维 JSON（全 84，过 quality_floor 80 + dimension_floor 65）
            from test_m4_review_pipeline import _JURY_DIMS

            text = json.dumps({dim: 84 for dim in _JURY_DIMS}, ensure_ascii=False)
        else:
            text = f"scene text {model_name} {idempotency_key}"
        return ModelResult(
            text=text,
            model_name=model_name,
            token_input=len(prompt_text.split()),
            token_output=1,
        )

