from __future__ import annotations

import subprocess
import sys
import os
from pathlib import Path

import pytest

from ink.codegen.generate import render_dataclasses
from ink.contract.generated.dtos import (
    DraftSpecDTO,
    JuryInputDTO,
    OutlineSpecDTO,
    ProjectConfigDTO,
    PromptSpecDTO,
    QualityReportDTO,
    ShotContractDTO,
    TaskCardDTO,
)
from ink.errors import DataIntegrityError
from ink.quality_report import validate_quality_report
from ink.time import now_utc_iso


def test_generated_contract_dtos_are_frozen_and_unpack_all_fields() -> None:
    shot = ShotContractDTO(
        shot_id="shot-001@20",
        run_id=20,
        must_land={"events": ["a"]},
        anti_write={"forbidden": []},
        scene_contract={"location": "room"},
        persona_assignment={"persona": "text"},
        soft_constraints={"rules": []},
    )

    assert shot.unpack() == {
        "shot_id": "shot-001@20",
        "run_id": 20,
        "must_land": {"events": ["a"]},
        "anti_write": {"forbidden": []},
        "scene_contract": {"location": "room"},
        "persona_assignment": {"persona": "text"},
        "soft_constraints": {"rules": []},
    }
    with pytest.raises(Exception):
        shot.shot_id = "changed"

    project = ProjectConfigDTO(
        project_id=1,
        draft_count=3,
        writer_model_pool=("writer-a",),
        jury_model_pool=("judge-a", "judge-b", "judge-c"),
        shot_quality_floor=80,
        dimension_floor=65,
    )
    assert project.unpack()["draft_count"] == 3

    report = QualityReportDTO(
        evidence_class="ES",
        defect_class="destructive",
        blind_review_passed=True,
        would_continue_reading_score=80,
        blocking_items=(),
        productive_deviations=(),
        neutral_issues=(),
        smart_model_required=True,
    )
    assert report.unpack()["evidence_class"] == "ES"

    outline = OutlineSpecDTO(
        outline_id=1,
        shot_contract_id=2,
        evaluated_outline_text="她走进档案室。",
        drift_score=0.9,
        is_winner=True,
    )
    task_card = TaskCardDTO(
        task_card_id=3,
        shot_contract_id=2,
        compiled_instructions="写出档案室发现钥匙。",
        superseded_at=None,
    )
    prompt = PromptSpecDTO(
        prompt_id=4,
        task_card_id=3,
        persona="意象师",
        full_prompt_text="prompt",
        prompt_size_bytes=6,
        relaxed_soft=False,
        superseded_at=None,
    )
    draft = DraftSpecDTO(
        draft_id=5,
        shot_id="shot-001@20",
        prompt_id=4,
        persona="意象师",
        writer_model="writer-a",
        text="正文",
        byte_count=6,
        degraded=False,
    )
    jury_input = JuryInputDTO(
        draft_id=5,
        shot_contract_id=2,
        jury_round=1,
        judge_model_pool=("judge-a", "judge-b", "judge-c"),
    )
    assert outline.unpack()["is_winner"] is True
    assert task_card.unpack()["superseded_at"] is None
    assert prompt.unpack()["prompt_size_bytes"] == 6
    assert draft.unpack()["degraded"] is False
    assert jury_input.unpack()["jury_round"] == 1


def test_codegen_rendered_output_compiles() -> None:
    source = render_dataclasses()
    compile(source, "<generated dtos>", "exec")
    assert "class ShotContractDTO" in source
    assert "class OutlineSpecDTO" in source
    assert "class TaskCardDTO" in source
    assert "class PromptSpecDTO" in source
    assert "class DraftSpecDTO" in source
    assert "class JuryInputDTO" in source
    assert "class ProjectConfigDTO" in source
    assert "class QualityReportDTO" in source


def test_codegen_module_is_idempotent() -> None:
    root = Path(__file__).resolve().parents[1]
    env = os.environ.copy()
    env["PYTHONPATH"] = str(root / "src")
    result = subprocess.run(
        [sys.executable, "-m", "ink.codegen.generate"],
        cwd=root,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )

    assert "dtos.py" in result.stdout


def test_quality_report_schema_requires_evidence_and_defect_class() -> None:
    report = validate_quality_report(
        {
            "evidence_class": "ES",
            "defect_class": "productive",
            "blind_review_passed": True,
            "would_continue_reading_score": 82,
            "blocking_items": [],
            "productive_deviations": ["voice roughness"],
            "neutral_issues": [],
            "smart_model_required": True,
        }
    )
    assert report.evidence_class == "ES"
    assert report.productive_deviations == ("voice roughness",)

    with pytest.raises(DataIntegrityError):
        validate_quality_report({"defect_class": "productive"})
    with pytest.raises(DataIntegrityError):
        validate_quality_report(
            {
                "evidence_class": "BAD",
                "defect_class": "productive",
                "blind_review_passed": True,
                "would_continue_reading_score": 82,
                "blocking_items": [],
                "productive_deviations": [],
                "neutral_issues": [],
                "smart_model_required": True,
            }
        )


def test_now_utc_iso_format() -> None:
    value = now_utc_iso()

    assert value.endswith("Z")
    assert "T" in value
    assert len(value) == len("2026-07-04T00:00:00.000Z")
