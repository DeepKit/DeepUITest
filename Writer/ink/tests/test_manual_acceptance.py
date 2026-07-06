from __future__ import annotations

import json
from pathlib import Path

import pytest

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.database import connect
from ink.errors import LLMProviderError
from ink.manual_acceptance import append_jsonl_record, build_llm_acceptance_record
from ink.tools.record_llm_acceptance import main as record_llm_acceptance_main
from test_schema_contract import NOW, insert_minimal_draft, make_schema_db


def test_manual_acceptance_record_summarizes_llm_attempts_and_quality_samples() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    LLMGateway(conn).call(
        project_id=int(ids["project_id"]),
        shot_id=str(ids["shot_id"]),
        run_id=int(ids["run_id"]),
        call_type="draft",
        prompt_id=int(ids["prompt_id"]),
        prompt_text="write scene",
        model_name="mock-model",
        idempotency_key="manual-success-1",
    )
    with pytest.raises(LLMProviderError):
        LLMGateway(conn, provider=_FailingProvider(), provider_name="mock").call(
            project_id=int(ids["project_id"]),
            shot_id=str(ids["shot_id"]),
            run_id=int(ids["run_id"]),
            call_type="draft",
            prompt_id=int(ids["prompt_id"]),
            prompt_text="write failing scene",
            model_name="mock-model",
            idempotency_key="manual-failure-1",
        )
    conn.execute(
        """
        INSERT INTO writing_human_decisions
            (project_id, decision_type, actor, reason, preconditions_json,
             quality_report_json, hard_quality_override, created_at)
        VALUES (1, 'accept', 'author', 'quality passed', ?, ?, 0, ?)
        """,
        (
            json.dumps({"quality_gate_passed": True}),
            json.dumps({"evidence_class": "SEMI_ES", "defect_class": "neutral"}),
            NOW,
        ),
    )

    record = build_llm_acceptance_record(
        conn,
        project_id=1,
        price_input_per_1k=0.01,
        price_output_per_1k=0.02,
    )

    assert record["schema_version"] == "ink.llm_acceptance.v1"
    assert record["project_id"] == 1
    assert record["summary"] == {
        "attempt_count": 2,
        "success_count": 1,
        "failure_count": 1,
        "failure_rate": 0.5,
        "token_input": 2,
        "token_output": 1,
        "estimated_cost": 0.00004,
        "latency_ms_avg": record["summary"]["latency_ms_avg"],
        "latency_ms_p95": record["summary"]["latency_ms_p95"],
    }
    assert record["summary"]["latency_ms_avg"] is not None
    assert record["summary"]["latency_ms_p95"] is not None
    assert record["by_provider_model_call_type"] == [
        {
            "model_provider": "mock",
            "model_name": "mock-model",
            "call_type": "draft",
            "attempt_count": 2,
            "success_count": 1,
            "failure_count": 1,
            "token_input": 2,
            "token_output": 1,
        }
    ]
    assert record["quality_samples"] == [
        {
            "decision_id": 1,
            "project_id": 1,
            "actor": "author",
            "reason": "quality passed",
            "quality_gate_passed": True,
            "evidence_class": "SEMI_ES",
            "defect_class": "neutral",
            "created_at": NOW,
        }
    ]


def test_append_jsonl_record_creates_parent_and_appends_one_line(tmp_path: Path) -> None:
    output = tmp_path / "records" / "llm.jsonl"
    record = {"schema_version": "ink.llm_acceptance.v1", "summary": {"attempt_count": 0}}

    append_jsonl_record(output, record)

    lines = output.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 1
    assert json.loads(lines[0]) == record


def test_record_llm_acceptance_tool_writes_jsonl(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    output = tmp_path / "manual" / "records.jsonl"
    conn = connect(db_path, initialize=True)
    try:
        ids = insert_minimal_draft(conn)
        LLMGateway(conn).call(
            project_id=int(ids["project_id"]),
            shot_id=str(ids["shot_id"]),
            run_id=int(ids["run_id"]),
            call_type="draft",
            prompt_id=int(ids["prompt_id"]),
            prompt_text="write scene",
            model_name="mock-model",
            idempotency_key="manual-tool-success-1",
        )
        conn.commit()
    finally:
        conn.close()

    assert record_llm_acceptance_main(
        ["--db", str(db_path), "--output", str(output), "--project-id", "1"]
    ) == 0

    record = json.loads(output.read_text(encoding="utf-8").splitlines()[0])
    assert record["summary"]["attempt_count"] == 1
    assert record["summary"]["failure_rate"] == 0.0


class _FailingProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        raise RuntimeError("provider down")
