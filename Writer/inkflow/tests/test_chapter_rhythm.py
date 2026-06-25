"""Tests for ChapterRhythmArchitect (L1)."""

from __future__ import annotations

import sqlite3

import pytest

from inkflow.services.chapter_rhythm import (
    ChapterRhythmArchitect,
    PHASE_PARAMETERS,
    VALID_PHASES,
)
from inkflow.services.model_client import ModelClient, ModelRequest, ModelResponse


class FakeModelClient:
    """Fake model client that returns preset JSON responses."""

    def __init__(self, response_text: str | None = None):
        self._response_text = response_text
        self.call_count = 0

    def generate(self, request: ModelRequest) -> ModelResponse:
        self.call_count += 1
        if self._response_text:
            return ModelResponse(text=self._response_text, model="fake")
        # Default: return a valid JSON
        return ModelResponse(
            text=(
                '{"shots": ['
                '{"shot_index": 1, "narrative_phase": "sediment", "deviation_budget": 0.6, "shot_role": "breathing"},'
                '{"shot_index": 2, "narrative_phase": "pulse", "deviation_budget": 0.3, "shot_role": "anchor"},'
                '{"shot_index": 3, "narrative_phase": "ripple", "deviation_budget": 0.55, "shot_role": "breathing"},'
                '{"shot_index": 4, "narrative_phase": "sublime", "deviation_budget": 0.25, "shot_role": "anchor"},'
                '{"shot_index": 5, "narrative_phase": "sediment", "deviation_budget": 0.5, "shot_role": "breathing"}'
                '], "reasoning": "test"}'
            ),
            model="fake",
        )


@pytest.fixture
def fake_model():
    return FakeModelClient()


class TestChapterRhythmArchitect:
    """Test L1 chapter rhythm analysis."""

    def test_analyze_chapter_basic(self, db, fake_model):
        """Basic chapter analysis should return valid rhythm map."""
        arch = ChapterRhythmArchitect(db, fake_model)

        events = [
            {"title": "Shot 1", "pov": "苏然", "event": "苏然在办公室整理文件，发现异常"},
            {"title": "Shot 2", "pov": "苏然", "event": "苏然发现系统记录被篡改"},
            {"title": "Shot 3", "pov": "苏然", "event": "苏然思考这意味着什么"},
            {"title": "Shot 4", "pov": "苏然", "event": "苏然确认韩教授修改过参数"},
            {"title": "Shot 5", "pov": "苏然", "event": "苏然决定暂时不动声色"},
        ]

        result = arch.analyze_chapter("v01.c03", events)

        assert "shots" in result
        assert len(result["shots"]) == 5
        assert "validation" in result
        assert "mean_deviation_budget" in result

        # Each shot should have required fields
        for shot in result["shots"]:
            assert "narrative_phase" in shot
            assert "deviation_budget" in shot
            assert "paragraph_length" in shot
            assert "sensory_pressure" in shot
            assert shot["narrative_phase"] in VALID_PHASES
            assert 0 <= shot["deviation_budget"] <= 1

    def test_analyze_chapter_with_volume_constraints(self, db, fake_model):
        """Volume constraints should influence deviation_budget range."""
        # Use a fake model that returns the right number of shots
        class AdaptiveFakeModel:
            def __init__(self):
                self.call_count = 0
            def generate(self, request):
                self.call_count += 1
                return ModelResponse(
                    text=(
                        '{"shots": ['
                        '{"shot_index": 1, "narrative_phase": "pulse", "deviation_budget": 0.35, "shot_role": "anchor"},'
                        '{"shot_index": 2, "narrative_phase": "chaos", "deviation_budget": 0.25, "shot_role": "anchor"},'
                        '{"shot_index": 3, "narrative_phase": "pulse", "deviation_budget": 0.40, "shot_role": "anchor"}'
                        '], "reasoning": "climax chapter"}'
                    ),
                    model="fake",
                )

        arch = ChapterRhythmArchitect(db, AdaptiveFakeModel())

        events = [
            {"title": "Shot 1", "pov": "郑坤", "event": "郑坤送快递"},
            {"title": "Shot 2", "pov": "郑坤", "event": "郑坤发现异常"},
            {"title": "Shot 3", "pov": "郑坤", "event": "郑坤思考"},
        ]

        volume_constraints = {
            "chapter_role": "climax",
            "deviation_range": [0.15, 0.45],
        }

        result = arch.analyze_chapter(
            "v01.c04", events, volume_constraints=volume_constraints
        )

        assert "shots" in result
        assert len(result["shots"]) == 3

    def test_validate_rhythm_rules(self, db, fake_model):
        """Rule engine should validate rhythm correctly."""
        arch = ChapterRhythmArchitect(db, fake_model)

        # Good rhythm: varied budgets and phases
        good_result = {
            "shots": [
                {"shot_index": 1, "narrative_phase": "sediment", "deviation_budget": 0.6},
                {"shot_index": 2, "narrative_phase": "pulse", "deviation_budget": 0.3},
                {"shot_index": 3, "narrative_phase": "ripple", "deviation_budget": 0.55},
                {"shot_index": 4, "narrative_phase": "sublime", "deviation_budget": 0.25},
                {"shot_index": 5, "narrative_phase": "fold", "deviation_budget": 0.5},
            ]
        }

        validation = arch._validate_rhythm(good_result, None)
        assert validation["all_pass"] is True

    def test_validate_rhythm_fails_on_consecutive_same(self, db, fake_model):
        """Rule 1 & 2: 3 consecutive same budgets/phases should fail."""
        arch = ChapterRhythmArchitect(db, fake_model)

        bad_result = {
            "shots": [
                {"shot_index": 1, "narrative_phase": "sediment", "deviation_budget": 0.5},
                {"shot_index": 2, "narrative_phase": "sediment", "deviation_budget": 0.5},
                {"shot_index": 3, "narrative_phase": "sediment", "deviation_budget": 0.5},
                {"shot_index": 4, "narrative_phase": "pulse", "deviation_budget": 0.3},
            ]
        }

        validation = arch._validate_rhythm(bad_result, None)
        assert validation["rule_1_no_3_consecutive_budgets"] is False
        assert validation["rule_2_no_3_consecutive_phases"] is False

    def test_validate_rhythm_requires_anchor_and_breathing(self, db, fake_model):
        """Rules 3 & 4: Must have at least 1 anchor and 1 breathing shot."""
        arch = ChapterRhythmArchitect(db, fake_model)

        # All high budgets = no anchor
        no_anchor = {
            "shots": [
                {"shot_index": 1, "narrative_phase": "sediment", "deviation_budget": 0.7},
                {"shot_index": 2, "narrative_phase": "ripple", "deviation_budget": 0.6},
                {"shot_index": 3, "narrative_phase": "fold", "deviation_budget": 0.65},
            ]
        }

        validation = arch._validate_rhythm(no_anchor, None)
        assert validation["rule_3_has_breathing_shot"] is True
        assert validation["rule_4_has_anchor_shot"] is False

        # All low budgets = no breathing
        no_breathing = {
            "shots": [
                {"shot_index": 1, "narrative_phase": "pulse", "deviation_budget": 0.2},
                {"shot_index": 2, "narrative_phase": "chaos", "deviation_budget": 0.3},
                {"shot_index": 3, "narrative_phase": "sublime", "deviation_budget": 0.25},
            ]
        }

        validation = arch._validate_rhythm(no_breathing, None)
        assert validation["rule_3_has_breathing_shot"] is False
        assert validation["rule_4_has_anchor_shot"] is True

    def test_fallback_assign(self, db, fake_model):
        """Fallback assignment should produce valid results when LLM fails."""
        arch = ChapterRhythmArchitect(db, fake_model)

        events = [
            {"title": "Shot 1", "pov": "郑坤", "event": "郑坤送快递"},
            {"title": "Shot 2", "pov": "郑坤", "event": "郑坤发现异常"},
            {"title": "Shot 3", "pov": "郑坤", "event": "郑坤思考"},
            {"title": "Shot 4", "pov": "郑坤", "event": "郑坤做出决定"},
        ]

        result = arch._fallback_assign(events, None)

        assert "shots" in result
        assert len(result["shots"]) == 4

        # Last shot should be anchor
        last_shot = result["shots"][-1]
        assert last_shot["shot_role"] == "anchor"
        assert last_shot["deviation_budget"] < 0.4

    def test_phase_parameters_complete(self):
        """All 6 phases should have parameter definitions."""
        assert len(PHASE_PARAMETERS) == 6
        for phase in VALID_PHASES:
            assert phase in PHASE_PARAMETERS
            params = PHASE_PARAMETERS[phase]
            assert "paragraph_length" in params
            assert "sensory_pressure" in params
            assert "description" in params

    def test_store_rhythm_map(self, db, fake_model):
        """Should store rhythm map in DB."""
        # Create a session first (FK constraint)
        db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', 'test')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'proj_01', 'test_run_01', 'active')"
        )

        arch = ChapterRhythmArchitect(db, fake_model)

        rhythm_map = {
            "chapter_key": "v01.c03",
            "shots": [
                {"shot_index": 1, "narrative_phase": "sediment", "deviation_budget": 0.6}
            ],
            "validation": {"all_pass": True},
        }

        rhythm_id = arch.store_rhythm_map(rhythm_map, "test_run_01")

        row = db.execute(
            "SELECT * FROM writing_chapter_rhythms WHERE rhythm_id = ?",
            (rhythm_id,),
        ).fetchone()
        assert row is not None
        assert row["chapter_key"] == "v01.c03"
