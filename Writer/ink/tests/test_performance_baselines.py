from __future__ import annotations

import time
from pathlib import Path

from ink.cli import main
from ink.core.llm_gateway import LLMGateway
from test_m6_workflow_smoke import (
    INITIAL_RUN_ID,
    WorkflowProvider,
    _chapter_shot,
    _run_shot_to_soft_sealed,
    make_six_chapter_project,
    test_full_production_flow_six_chapters as _full_production_flow_six_chapters,
)


SINGLE_SHOT_MAX_SECONDS = 5.0
SIX_CHAPTER_WORKFLOW_MAX_SECONDS = 15.0
CLI_ONE_CHAPTER_MAX_SECONDS = 10.0


def test_single_shot_mock_pipeline_performance_baseline() -> None:
    conn = make_six_chapter_project()
    shot_id, run_id = _chapter_shot(conn, 1, INITIAL_RUN_ID)
    gateway = LLMGateway(conn, provider=WorkflowProvider())

    elapsed = _measure(lambda: _run_shot_to_soft_sealed(conn, shot_id, run_id, gateway))

    assert elapsed < SINGLE_SHOT_MAX_SECONDS


def test_six_chapter_workflow_performance_baseline(tmp_path: Path) -> None:
    elapsed = _measure(lambda: _full_production_flow_six_chapters(tmp_path))

    assert elapsed < SIX_CHAPTER_WORKFLOW_MAX_SECONDS


def test_cli_one_chapter_performance_baseline(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    output_path = tmp_path / "export.md"

    def run_flow() -> None:
        assert main(["--db", str(db_path), "init", "--code", "perf-demo", "--title", "Perf Demo"]) == 0
        assert main(["--db", str(db_path), "setup", "--chapters", "1"]) == 0
        assert main(["--db", str(db_path), "write", "--chapter", "1"]) == 0
        assert main(["--db", str(db_path), "review", "--chapter", "1"]) == 0
        assert main(["--db", str(db_path), "accept", "--chapter", "1"]) == 0
        assert main(["--db", str(db_path), "export", "--output", str(output_path)]) == 0

    elapsed = _measure(run_flow)

    assert output_path.exists()
    assert elapsed < CLI_ONE_CHAPTER_MAX_SECONDS


def _measure(callback) -> float:
    started = time.perf_counter()
    callback()
    return time.perf_counter() - started
