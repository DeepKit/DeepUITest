"""Tests for JuryService scoring (P0-3 / B15)."""

from __future__ import annotations

import pytest

from inkflow.models.enums import LightStatus
from inkflow.services.jury_service import JuryService


@pytest.fixture
def setup_run_with_draft(setup_run):
    """setup_run + a draft so jury FK constraint passes."""
    setup_run.execute(
        "INSERT INTO writing_drafts "
        "(draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
        "VALUES ('d1', 'shot_01', 'run_01', '意象师', 0, "
        "'雾从地面往上冒，不是从天上掉下来的。她站在绕城高速上，手机信号掉了一格。"
        "绕城是成都的物理边界，出绕城信号断，进绕城才是成都。她看了一眼手机——"
        "内江同时有三十七单，系统给她的建议全是外江。她从包里拿出新的保鲜膜。"
        "旧的已经被汗水浸透了。撕下来的时候膏药化了，和血水一起粘在腿上的汗毛上。"
        "她咬着牙撕——那种粘连的声音像撕创可贴。她在石板滩老居民楼下遇到���一个人。"
        "一个年轻人，十八九岁，拖着一个行李箱站在楼道口。他看到她的电瓶车，"
        "问了一句。她没有回答。她指了指头盔上褪色的太阳神鸟。年轻人看了一眼，"
        "没看懂。她骑走了。年轻人还站在楼道口，手机屏幕上显示着系统推送。"
        "全是外江。她骑进雾里。成都冬天的雾，从地面往上冒，不是从天上掉下来的。', 'att1')"
    )
    setup_run.commit()
    return setup_run


class TestJuryScoreScale:
    """B15: Jury scores should be 0-100, thresholds green>=85 / yellow>=65."""

    def test_default_stub_score_is_70(self, setup_run_with_draft):
        """Default stub score = 70 → YELLOW (65 <= 70 < 85)."""
        jury = JuryService(setup_run_with_draft, "run_01", {})
        result = jury.score_candidates("shot_01", ["d1"])
        assert result["light_status"] == LightStatus.YELLOW

    def test_local_jury_uses_heuristic_even_with_providers(self, setup_run_with_draft):
        """local-default jury should not call remote providers when providers exist."""
        config = {
            "providers": {
                "stepfun": {
                    "api_key": "sk-test",
                    "base_url": "https://invalid.example.test",
                    "protocol": "openai",
                },
            },
            "jury_config": {"models": ["local-default"]},
        }
        jury = JuryService(setup_run_with_draft, "run_01", config)
        result = jury.score_candidates("shot_01", ["d1"])

        assert result["winner_score"] >= 65
        attempts = setup_run_with_draft.execute(
            "SELECT COUNT(*) AS cnt FROM model_attempts WHERE phase = 'jury_score'"
        ).fetchone()["cnt"]
        assert attempts == 0

    def test_score_override_green(self, setup_run_with_draft):
        """score_override=90 → GREEN verdict."""
        jury = JuryService(setup_run_with_draft, "run_01", {})
        result = jury.score_candidates("shot_01", ["d1"], score_override=90)
        assert result["light_status"] == LightStatus.GREEN
        assert result["winner_score"] == 90

    def test_score_override_yellow(self, setup_run_with_draft):
        """score_override=75 → YELLOW verdict."""
        jury = JuryService(setup_run_with_draft, "run_01", {})
        result = jury.score_candidates("shot_01", ["d1"], score_override=75)
        assert result["light_status"] == LightStatus.YELLOW
        assert result["winner_score"] == 75

    def test_score_override_red(self, setup_run_with_draft):
        """score_override=50 → RED verdict."""
        jury = JuryService(setup_run_with_draft, "run_01", {})
        result = jury.score_candidates("shot_01", ["d1"], score_override=50)
        assert result["light_status"] == LightStatus.RED
        assert result["winner_score"] == 50

    def test_green_boundary_at_85(self, setup_run_with_draft):
        """Score exactly 85 → GREEN (boundary inclusive)."""
        jury = JuryService(setup_run_with_draft, "run_01", {})
        result = jury.score_candidates("shot_01", ["d1"], score_override=85)
        assert result["light_status"] == LightStatus.GREEN

    def test_yellow_boundary_at_65(self, setup_run_with_draft):
        """Score exactly 65 → YELLOW (boundary inclusive)."""
        jury = JuryService(setup_run_with_draft, "run_01", {})
        result = jury.score_candidates("shot_01", ["d1"], score_override=65)
        assert result["light_status"] == LightStatus.YELLOW

    def test_red_boundary_at_64(self, setup_run_with_draft):
        """Score 64 → RED (just below yellow boundary)."""
        jury = JuryService(setup_run_with_draft, "run_01", {})
        result = jury.score_candidates("shot_01", ["d1"], score_override=64)
        assert result["light_status"] == LightStatus.RED

    def test_layered_literary_dimensions_are_persisted(self, setup_run_with_draft):
        """v5: default jury writes hard-rule + literary 9 dimensions."""
        jury = JuryService(setup_run_with_draft, "run_01", {})
        jury.score_candidates("shot_01", ["d1"], score_override=80)

        rows = setup_run_with_draft.execute(
            "SELECT DISTINCT dimension FROM writing_jury_scores WHERE shot_id = 'shot_01'"
        ).fetchall()
        dimensions = {row["dimension"] for row in rows}
        assert "hard_rule_compliance" in dimensions
        assert "language_texture" in dimensions
        assert "chapter_continuity" in dimensions
        assert "unexpected_value" not in dimensions

    def test_creative_review_can_choose_less_safe_high_value_draft(self, setup_run_with_draft):
        """CREATIVE-3: blank-shot review weights unexpected_value over safe compliance."""
        setup_run_with_draft.execute(
            "INSERT INTO writing_drafts "
            "(draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d2', 'shot_01', 'run_01', '对话师', 1, "
            "'她把杯子转了半圈，没有说系统两个字。水面停在杯沿下一毫米，像一个没有提交的决定。"
            "门外有人咳嗽，咳声短得不自然。阿坤看着那一毫米，突然明白她已经知道了通知的来源。', 'att2')"
        )
        setup_run_with_draft.commit()

        high_literary = {
            "hard_rule_compliance": 100,
            "language_texture": 92,
            "reading_fluency": 92,
            "scene_specificity": 90,
            "emotional_progression": 90,
            "character_believability": 90,
            "dialogue_subtext": 88,
            "pacing_control": 90,
            "motif_theme_fit": 88,
            "chapter_continuity": 90,
        }
        lower_literary = {
            "hard_rule_compliance": 100,
            "language_texture": 80,
            "reading_fluency": 80,
            "scene_specificity": 80,
            "emotional_progression": 80,
            "character_believability": 80,
            "dialogue_subtext": 80,
            "pacing_control": 80,
            "motif_theme_fit": 80,
            "chapter_continuity": 80,
        }
        scores = {
            "d1": {
                **high_literary,
                "unexpected_value": 50,
            },
            "d2": {
                **lower_literary,
                "unexpected_value": 98,
            },
        }

        jury = JuryService(setup_run_with_draft, "run_01", {})
        regular = jury.score_candidates("shot_01", ["d1", "d2"], score_overrides=scores)
        creative = jury.score_candidates(
            "shot_01", ["d1", "d2"], score_overrides=scores, creative_review=True,
        )

        assert regular["winner_draft_id"] == "d1"
        assert regular["review_mode"] == "typed_literary"
        assert creative["winner_draft_id"] == "d2"
        assert creative["review_mode"] == "creative_blank"
        assert creative["score_key"] == "creative_score"
        assert creative["draft_scores"]["d1"]["type_gate_passed"] is False
        summary = creative["draft_scores"]["d1"]["failure_summary"]
        assert summary["stage"] == "type_gate"
        assert summary["label"] == "类型职责未通过"
        assert any("意外价值" in reason for reason in summary["reasons"])

    def test_requires_two_passing_drafts_for_production_threshold(self, setup_run_with_draft):
        """v5: winner can exist, but production pass requires min_passing_drafts."""
        setup_run_with_draft.execute(
            "INSERT INTO writing_drafts "
            "(draft_id, shot_id, run_id, writer_persona, writer_index, text, attempt_id) "
            "VALUES ('d2', 'shot_01', 'run_01', '结构师', 1, "
            "'她把手机扣回掌心，屏幕上的外江通知还亮着。楼道里的风把塑料袋吹得一下一下响。"
            "郑坤没有立刻走，他看着那行字，膝盖里像有一枚钝掉的螺丝慢慢转。', 'att2')"
        )
        setup_run_with_draft.commit()

        high = {
            "hard_rule_compliance": 100,
            "language_texture": 90,
            "reading_fluency": 90,
            "scene_specificity": 90,
            "emotional_progression": 90,
            "character_believability": 90,
            "dialogue_subtext": 90,
            "pacing_control": 90,
            "motif_theme_fit": 90,
            "chapter_continuity": 90,
        }
        low = {
            "hard_rule_compliance": 100,
            "language_texture": 70,
            "reading_fluency": 70,
            "scene_specificity": 70,
            "emotional_progression": 70,
            "character_believability": 70,
            "dialogue_subtext": 70,
            "pacing_control": 70,
            "motif_theme_fit": 70,
            "chapter_continuity": 70,
        }
        jury = JuryService(setup_run_with_draft, "run_01", {})
        result = jury.score_candidates(
            "shot_01",
            ["d1", "d2"],
            score_overrides={"d1": high, "d2": low},
            quality_threshold=85,
        )

        assert result["winner_draft_id"] == "d1"
        assert result["passing_count"] == 1
        assert result["all_passed_threshold"] is False
        assert result["min_passing_drafts"] == 2

    def test_remote_hard_rule_style_complaint_does_not_zero_eligibility(
        self, setup_run_with_draft, monkeypatch,
    ):
        """Remote hard-rule style complaints are advisory, not fatal gates."""
        def fake_score_single(self, **kwargs):
            dimension = kwargs["dimension"]
            if dimension == "hard_rule_compliance":
                return {
                    "score": 50,
                    "comment": "段落长度远未达500-800字，缺少成都话点缀。",
                }
            return {"score": 90, "comment": "通过"}

        monkeypatch.setattr(JuryService, "_score_single", fake_score_single)
        config = {
            "providers": {"test": {"api_key": "sk-test", "base_url": "https://x.test/v1"}},
            "jury_config": {"models": ["test/fake-jury"], "min_passing_drafts": 1},
        }
        jury = JuryService(setup_run_with_draft, "run_01", config)

        result = jury.score_candidates("shot_01", ["d1"])

        assert result["winner_draft_id"] == "d1"
        assert result["draft_scores"]["d1"]["eligible"] is True
        assert result["draft_scores"]["d1"]["hard_rule"]["llm_advisory_ignored"] is True
        assert result["winner_score"] == 90

    def test_remote_hard_rule_fatal_complaint_still_rejects(
        self, setup_run_with_draft, monkeypatch,
    ):
        """Actual hard-rule failures still make the draft ineligible."""
        def fake_score_single(self, **kwargs):
            dimension = kwargs["dimension"]
            if dimension == "hard_rule_compliance":
                return {
                    "score": 50,
                    "comment": "提示词残留，且出现提前揭示。",
                }
            return {"score": 90, "comment": "通过"}

        monkeypatch.setattr(JuryService, "_score_single", fake_score_single)
        config = {
            "providers": {"test": {"api_key": "sk-test", "base_url": "https://x.test/v1"}},
            "jury_config": {"models": ["test/fake-jury"], "min_passing_drafts": 1},
        }
        jury = JuryService(setup_run_with_draft, "run_01", config)

        result = jury.score_candidates("shot_01", ["d1"])

        assert result["winner_draft_id"] is None
        assert result["draft_scores"]["d1"]["eligible"] is False
        assert result["draft_scores"]["d1"]["failure_stage"] == "hard_rule"

    def test_remote_hard_rule_timeout_does_not_zero_eligibility(
        self, setup_run_with_draft, monkeypatch,
    ):
        """A transient hard-rule model timeout should not reject a draft."""
        def fake_score_single(self, **kwargs):
            dimension = kwargs["dimension"]
            model_ref = kwargs["jury_model_ref"]
            if dimension == "hard_rule_compliance" and "timeout" in model_ref:
                return {
                    "score": 50,
                    "comment": "API调用失败 (attempt 1): OpenAI API error: The read operation timed out",
                }
            if dimension == "hard_rule_compliance":
                return {"score": 98, "comment": "硬规则完全通过"}
            return {"score": 90, "comment": "通过"}

        monkeypatch.setattr(JuryService, "_score_single", fake_score_single)
        config = {
            "providers": {"test": {"api_key": "sk-test", "base_url": "https://x.test/v1"}},
            "jury_config": {
                "models": ["test/pass-jury", "test/timeout-jury"],
                "min_passing_drafts": 1,
            },
        }
        jury = JuryService(setup_run_with_draft, "run_01", config)

        result = jury.score_candidates("shot_01", ["d1"])

        assert result["winner_draft_id"] == "d1"
        assert result["draft_scores"]["d1"]["eligible"] is True
        assert result["draft_scores"]["d1"]["hard_rule"]["llm_advisory_ignored"] is True

    def test_remote_literary_timeout_is_skipped_not_scored_as_50(
        self, setup_run_with_draft, monkeypatch,
    ):
        """Transient literary jury failures are infrastructure failures, not low scores."""
        def fake_score_single(self, **kwargs):
            dimension = kwargs["dimension"]
            model_ref = kwargs["jury_model_ref"]
            if dimension == "hard_rule_compliance":
                return {"score": 100, "comment": "硬规则通过"}
            if "timeout" in model_ref:
                return {
                    "score": 50,
                    "comment": "API调用失败 (attempt 1): OpenAI API error: The read operation timed out",
                    "failed": True,
                }
            return {"score": 90, "comment": "通过"}

        monkeypatch.setattr(JuryService, "_score_single", fake_score_single)
        config = {
            "providers": {"test": {"api_key": "sk-test", "base_url": "https://x.test/v1"}},
            "jury_config": {
                "models": ["test/pass-jury", "test/timeout-jury"],
                "min_passing_drafts": 1,
            },
        }
        jury = JuryService(setup_run_with_draft, "run_01", config)

        result = jury.score_candidates("shot_01", ["d1"])

        assert result["winner_draft_id"] == "d1"
        assert result["winner_score"] == 90
        assert 50 not in result["draft_scores"]["d1"]["raw_scores"]
        assert result["draft_scores"]["d1"]["jury_failures"]

    def test_all_remote_failures_for_literary_dimension_make_jury_unavailable(
        self, setup_run_with_draft, monkeypatch,
    ):
        """A required dimension with no valid jury score should not become fake quality 50."""
        def fake_score_single(self, **kwargs):
            dimension = kwargs["dimension"]
            if dimension == "hard_rule_compliance":
                return {"score": 100, "comment": "硬规则通过"}
            if dimension == "reading_fluency":
                return {
                    "score": 50,
                    "comment": "API调用失败 (attempt 1): OpenAI API error: The read operation timed out",
                    "failed": True,
                }
            return {"score": 90, "comment": "通过"}

        monkeypatch.setattr(JuryService, "_score_single", fake_score_single)
        config = {
            "providers": {"test": {"api_key": "sk-test", "base_url": "https://x.test/v1"}},
            "jury_config": {
                "models": ["test/jury-a", "test/jury-b"],
                "min_passing_drafts": 1,
            },
        }
        jury = JuryService(setup_run_with_draft, "run_01", config)

        result = jury.score_candidates("shot_01", ["d1"])
        draft_score = result["draft_scores"]["d1"]

        assert result["winner_draft_id"] is None
        assert draft_score["eligible"] is False
        assert draft_score["failure_stage"] == "jury_unavailable"
        assert "reading_fluency" in draft_score["missing_dimensions"]
        assert any("阅读流畅" in reason for reason in draft_score["failure_summary"]["reasons"])

    def test_explicit_remote_jury_without_provider_does_not_fallback_to_local(
        self, setup_run_with_draft,
    ):
        """Explicit remote jury config must fail as jury_unavailable, not silently local-score."""
        config = {
            "providers": {},
            "jury_config": {
                "models": ["deepseek/deepseek-v4-flash"],
                "min_passing_drafts": 1,
            },
        }
        jury = JuryService(setup_run_with_draft, "run_01", config)

        result = jury.score_candidates("shot_01", ["d1"])
        draft_score = result["draft_scores"]["d1"]

        assert result["winner_draft_id"] is None
        assert draft_score["eligible"] is False
        assert draft_score["failure_stage"] == "jury_unavailable"
        assert draft_score["missing_dimensions"]
        attempts = setup_run_with_draft.execute(
            "SELECT COUNT(*) AS cnt FROM writing_jury_scores "
            "WHERE run_id = 'run_01' AND jury_persona = 'deepseek-v4-flash'"
        ).fetchone()["cnt"]
        assert attempts > 0
