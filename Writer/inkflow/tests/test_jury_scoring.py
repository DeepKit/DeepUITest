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

    def test_unexpected_value_dimension_is_persisted(self, setup_run_with_draft):
        """CREATIVE-1: default jury writes the unexpected_value dimension."""
        jury = JuryService(setup_run_with_draft, "run_01", {})
        jury.score_candidates("shot_01", ["d1"], score_override=80)

        rows = setup_run_with_draft.execute(
            "SELECT DISTINCT dimension FROM writing_jury_scores WHERE shot_id = 'shot_01'"
        ).fetchall()
        dimensions = {row["dimension"] for row in rows}
        assert "unexpected_value" in dimensions
