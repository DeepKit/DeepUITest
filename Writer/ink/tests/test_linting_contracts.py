from __future__ import annotations

from ink.linting.field_usage import lint_field_usage
from ink.linting.orchestrator_signature import lint_shot_orchestrator_source


def violation_codes(violations) -> set[str]:
    return {violation.code for violation in violations}


def test_shot_orchestrator_entrypoints_only_accept_shot_id_and_run_id() -> None:
    good = """
def score_and_select_winner(shot_id, run_id):
    return shot_id, run_id
"""
    bad = """
def score_and_select_winner(shot_id, run_id, session_id):
    return shot_id, run_id, session_id
"""

    assert lint_shot_orchestrator_source(good, "jury_orchestrator.py") == []
    violations = lint_shot_orchestrator_source(bad, "jury_orchestrator.py")
    assert violation_codes(violations) == {"SHOT_ORCHESTRATOR_SIGNATURE"}


def test_shot_orchestrator_entrypoints_reject_dataclass_parameters() -> None:
    source = """
def produce_drafts(contract: ShotContract, run_id: int):
    return contract, run_id
"""

    violations = lint_shot_orchestrator_source(source, "write_orchestrator.py")

    assert "SHOT_ORCHESTRATOR_SIGNATURE" in violation_codes(violations)
    assert "SHOT_ORCHESTRATOR_DATACLASS_PARAM" in violation_codes(violations)


def test_field_usage_lint_rejects_dynamic_dataclass_access_globally() -> None:
    source = """
def compile_prompt(contract):
    return getattr(contract, "must_land")

def dump(contract):
    return contract.__dict__
"""

    violations = lint_field_usage(source)

    assert violation_codes(violations) == {"DYNAMIC_DATACLASS_ACCESS"}
    assert len(violations) == 2


def test_full_field_consumption_only_applies_to_marked_boundary_functions() -> None:
    source = """
class ShotContract:
    pass

def helper(contract: ShotContract):
    return contract.must_land

@requires_full_field_consumption
def compile_prompt(contract: ShotContract):
    return contract.must_land + contract.scene_contract
"""

    violations = lint_field_usage(
        source,
        {"ShotContract": {"must_land", "scene_contract", "anti_write"}},
    )

    assert violation_codes(violations) == {"MISSING_FIELD_CONSUMPTION"}
    assert "anti_write" in violations[0].message
