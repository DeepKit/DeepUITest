"""Tests for Book Constitution Service (ARCH-4 L0)."""

from __future__ import annotations

import json
from unittest.mock import MagicMock, patch

import pytest

from inkflow.services.book_constitution import (
    BookConstitutionService,
    BookConstitutionError,
)


# ── Fixtures ──────────────────────────────────────────────────────────


@pytest.fixture
def service(db):
    """BookConstitutionService with a project already in DB."""
    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    # Add some motifs for lifecycle testing
    db.execute(
        "INSERT INTO writing_motif_definitions "
        "(motif_id, project_id, name, planned_density_json, variants_json) "
        "VALUES ('motif_knee', 'proj_01', '膝盖', '{}', '[]')"
    )
    db.execute(
        "INSERT INTO writing_motif_definitions "
        "(motif_id, project_id, name, planned_density_json, variants_json) "
        "VALUES ('motif_river', 'proj_01', '分流', '{}', '[]')"
    )
    db.commit()
    return BookConstitutionService(db, "proj_01")


def _valid_constitution_data() -> dict:
    """返回一个合法的宪法数据（通过所有验证）。"""
    return {
        "arc_shape": "slow_build → crisis → revelation",
        "tension_peak_chapter": "v03.c05",
        "tension_valley_chapters": ["v01.c03", "v02.c06"],
        "volume_map": {
            "v01": {"name": "四水流", "chapters": [f"v01.c0{i}" for i in range(1, 9)], "arc_summary": "建立四线"},
            "v02": {"name": "清浊分", "chapters": [f"v02.c0{i}" for i in range(1, 9)], "arc_summary": "清浊之分"},
            "v03": {"name": "回水", "chapters": [f"v03.c0{i}" for i in range(1, 8)], "arc_summary": "水往回流"},
            "v04": {"name": "不系舟", "chapters": [f"v04.c0{i}" for i in range(1, 10)], "arc_summary": "不系之舟"},
        },
        "chapter_roles": {
            **{f"v01.c0{i}": r for i, r in enumerate(["起", "承", "承", "转", "承", "转", "承", "合"], 1)},
            **{f"v02.c0{i}": r for i, r in enumerate(["起", "承", "承", "转", "承", "转", "承", "合"], 1)},
            **{f"v03.c0{i}": r for i, r in enumerate(["起", "承", "转", "转", "承", "转", "合"], 1)},
            **{f"v04.c0{i}": r for i, r in enumerate(["起", "承", "承", "转", "转", "承", "转", "承", "合"], 1)},
        },
        "motif_lifecycle": [
            {"motif_id": "motif_knee", "planted_at": "v01.c01", "developed_at": ["v01.c05", "v02.c03"], "resolved_at": "v04.c08"},
            {"motif_id": "motif_river", "planted_at": "v01.c01", "developed_at": ["v02.c01", "v03.c04"], "resolved_at": "v04.c09"},
        ],
        "global_deviation_mean": 0.4,
        "global_deviation_range": [0.2, 0.65],
    }


def _insert_constitution(db, constitution_id: str = "const_01", status: str = "draft") -> str:
    """Helper: 直接插入一条宪法记录。"""
    data = _valid_constitution_data()
    db.execute(
        "INSERT INTO writing_book_constitutions ("
        "constitution_id, project_id, version, arc_shape, "
        "tension_peak_chapter, tension_valley_chapters_json, "
        "volume_map_json, chapter_roles_json, motif_lifecycle_json, "
        "global_deviation_mean, global_deviation_range_json, status"
        ") VALUES (?, 'proj_01', 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            constitution_id,
            data["arc_shape"],
            data["tension_peak_chapter"],
            json.dumps(data["tension_valley_chapters"]),
            json.dumps(data["volume_map"]),
            json.dumps(data["chapter_roles"]),
            json.dumps(data["motif_lifecycle"]),
            data["global_deviation_mean"],
            json.dumps(data["global_deviation_range"]),
            status,
        ),
    )
    db.commit()
    return constitution_id


# ══════════════════════════════════════════════════════════════════════
# TestBookConstitutionValidation — 规则引擎单元测试
# ══════════════════════════════════════════════════════════════════════


class TestBookConstitutionValidation:
    """规则引擎验证（无 LLM 依赖）。"""

    def test_valid_constitution_passes(self, service):
        """合法数据 → 0 issues。"""
        data = _valid_constitution_data()
        issues = service.validate_constitution(data)
        assert issues == []

    def test_volume_count_too_few(self, service):
        """1 卷 → 报错。"""
        data = _valid_constitution_data()
        data["volume_map"] = {"v01": {"chapters": ["v01.c01"]}}
        issues = service.validate_constitution(data)
        assert any("卷数" in i for i in issues)

    def test_volume_count_too_many(self, service):
        """7 卷 → 报错。"""
        data = _valid_constitution_data()
        for i in range(5, 12):
            data["volume_map"][f"v{i:02d}"] = {"chapters": []}
        issues = service.validate_constitution(data)
        assert any("卷数" in i for i in issues)

    def test_missing_tension_peak(self, service):
        """无 tension_peak → 报错。"""
        data = _valid_constitution_data()
        data["tension_peak_chapter"] = ""
        issues = service.validate_constitution(data)
        assert any("tension_peak" in i for i in issues)

    def test_motif_missing_planted(self, service):
        """motif 无 planted_at → 报错。"""
        data = _valid_constitution_data()
        data["motif_lifecycle"][0]["planted_at"] = ""
        issues = service.validate_constitution(data)
        assert any("planted_at" in i for i in issues)

    def test_motif_missing_resolved(self, service):
        """motif 无 resolved_at → 报错。"""
        data = _valid_constitution_data()
        data["motif_lifecycle"][0]["resolved_at"] = ""
        issues = service.validate_constitution(data)
        assert any("resolved_at" in i for i in issues)

    def test_deviation_mean_out_of_range(self, service):
        """mean > 1.0 → 报错。"""
        data = _valid_constitution_data()
        data["global_deviation_mean"] = 1.5
        issues = service.validate_constitution(data)
        assert any("deviation_mean" in i for i in issues)

    def test_deviation_range_inverted(self, service):
        """range[0] > range[1] → 报错。"""
        data = _valid_constitution_data()
        data["global_deviation_range"] = [0.8, 0.2]
        issues = service.validate_constitution(data)
        assert any("range" in i for i in issues)

    def test_deviation_mean_outside_range(self, service):
        """mean 不在 range 内 → 报错。"""
        data = _valid_constitution_data()
        data["global_deviation_mean"] = 0.9
        data["global_deviation_range"] = [0.2, 0.65]
        issues = service.validate_constitution(data)
        assert any("不在 range" in i for i in issues)

    def test_chapter_missing_from_volume(self, service):
        """章节在 roles 中但不在任何卷中 → 报错。"""
        data = _valid_constitution_data()
        # 添加一个额外章节到 roles 但不在 volume 中
        data["chapter_roles"]["v01.c09"] = "承"
        issues = service.validate_constitution(data)
        assert any("不在任何卷中" in i for i in issues)

    def test_empty_data(self, service):
        """空数据 → 多个 issues。"""
        issues = service.validate_constitution({})
        assert len(issues) >= 2  # 至少卷数、peak 有问题


# ══════════════════════════════════════════════════════════════════════
# TestBookConstitutionStatus — 状态转换测试
# ══════════════════════════════════════════════════════════════════════


class TestBookConstitutionStatus:
    """状态转换。"""

    def test_draft_to_confirmed(self, service):
        """draft → confirmed。"""
        cid = _insert_constitution(service.db, status="draft")
        service.update_status(cid, "confirmed")
        c = service.get_latest_constitution()
        assert c["status"] == "confirmed"
        assert c["confirmed_at"] is not None

    def test_confirmed_to_locked(self, service):
        """confirmed → locked。"""
        cid = _insert_constitution(service.db, status="confirmed")
        service.update_status(cid, "locked")
        c = service.get_latest_constitution()
        assert c["status"] == "locked"
        assert c["locked_at"] is not None

    def test_invalid_transition_raises(self, service):
        """locked → draft → 报错。"""
        cid = _insert_constitution(service.db, status="locked")
        with pytest.raises(BookConstitutionError, match="非法状态转换"):
            service.update_status(cid, "draft")

    def test_draft_to_locked_direct_raises(self, service):
        """draft → locked → 报错（必须经过 confirmed）。"""
        cid = _insert_constitution(service.db, status="draft")
        with pytest.raises(BookConstitutionError, match="非法状态转换"):
            service.update_status(cid, "locked")

    def test_lock_constitution_from_confirmed(self, service):
        """lock_constitution 从 confirmed 直接锁定。"""
        cid = _insert_constitution(service.db, status="confirmed")
        service.lock_constitution(cid)
        c = service.get_latest_constitution()
        assert c["status"] == "locked"

    def test_lock_constitution_from_draft(self, service):
        """lock_constitution 从 draft → confirmed → locked。"""
        cid = _insert_constitution(service.db, status="draft")
        service.lock_constitution(cid)
        c = service.get_latest_constitution()
        assert c["status"] == "locked"

    def test_lock_already_locked_is_noop(self, service):
        """锁定已锁定的宪法 → 无操作。"""
        cid = _insert_constitution(service.db, status="locked")
        service.lock_constitution(cid)  # 不应报错
        c = service.get_latest_constitution()
        assert c["status"] == "locked"

    def test_nonexistent_constitution_raises(self, service):
        """操作不存在的宪法 → 报错。"""
        with pytest.raises(BookConstitutionError, match="不存在"):
            service.update_status("fake_id", "confirmed")


# ══════════════════════════════════════════════════════════════════════
# TestBookConstitutionQuery — 查询测试
# ══════════════════════════════════════════════════════════════════════


class TestBookConstitutionQuery:
    """查询。"""

    def test_get_latest_none(self, service):
        """无宪法 → None。"""
        assert service.get_latest_constitution() is None

    def test_get_latest_returns_newest(self, service):
        """返回最新版本。"""
        _insert_constitution(service.db, "const_01")
        # 插入 v2
        service.db.execute(
            "INSERT INTO writing_book_constitutions ("
            "constitution_id, project_id, version, arc_shape, status, "
            "tension_peak_chapter, tension_valley_chapters_json, "
            "volume_map_json, chapter_roles_json, motif_lifecycle_json, "
            "global_deviation_mean, global_deviation_range_json"
            ") VALUES ('const_02', 'proj_01', 2, 'v2_arc', 'draft', '', '[]', '{}', '{}', '[]', 0.3, '[0.1,0.5]')"
        )
        service.db.commit()
        c = service.get_latest_constitution()
        assert c["constitution_id"] == "const_02"
        assert c["version"] == 2

    def test_get_locked_none_when_no_locked(self, service):
        """无锁定宪法 → None。"""
        _insert_constitution(service.db, status="draft")
        assert service.get_locked_constitution() is None

    def test_get_locked_returns_locked(self, service):
        """返回锁定的宪法。"""
        _insert_constitution(service.db, "const_01", status="locked")
        c = service.get_locked_constitution()
        assert c is not None
        assert c["constitution_id"] == "const_01"
        assert c["status"] == "locked"


# ══════════════════════════════════════════════════════════════════════
# TestBookConstitutionGeneration — LLM 集成测试（mock）
# ══════════════════════════════════════════════════════════════════════


class TestBookConstitutionGeneration:
    """LLM 生成（mock ModelClient）。"""

    def test_generate_parses_llm_json(self, service, tmp_dir):
        """LLM 返回有效 JSON → 解析并存储。"""
        data = _valid_constitution_data()
        mock_response = MagicMock()
        mock_response.text = json.dumps(data, ensure_ascii=False)

        with patch("inkflow.services.book_constitution.create_model_client") as mock_create:
            mock_client = MagicMock()
            mock_client.generate.return_value = mock_response
            mock_create.return_value = mock_client

            # 创建源文件
            story_dir = tmp_dir / "story"
            story_dir.mkdir()
            (story_dir / "04_逐章大纲.md").write_text("# 大纲\n测试内容", encoding="utf-8")

            cid = service.generate_constitution(str(story_dir))
            assert cid is not None
            assert len(cid) > 0

            c = service.get_latest_constitution()
            assert c is not None
            assert c["status"] == "draft"
            assert c["arc_shape"] == data["arc_shape"]

    def test_generate_extracts_json_from_markdown(self, service, tmp_dir):
        """LLM 返回 ```json ... ``` 包裹 → 正确提取。"""
        data = _valid_constitution_data()
        mock_response = MagicMock()
        mock_response.text = f"这是分析结果：\n```json\n{json.dumps(data, ensure_ascii=False)}\n```\n希望有用！"

        with patch("inkflow.services.book_constitution.create_model_client") as mock_create:
            mock_client = MagicMock()
            mock_client.generate.return_value = mock_response
            mock_create.return_value = mock_client

            story_dir = tmp_dir / "story"
            story_dir.mkdir()

            cid = service.generate_constitution(str(story_dir))
            c = service.get_latest_constitution()
            assert c["arc_shape"] == data["arc_shape"]

    def test_generate_invalid_json_raises(self, service, tmp_dir):
        """LLM 返回无效 JSON → BookConstitutionError。"""
        mock_response = MagicMock()
        mock_response.text = "这不是 JSON"

        with patch("inkflow.services.book_constitution.create_model_client") as mock_create:
            mock_client = MagicMock()
            mock_client.generate.return_value = mock_response
            mock_create.return_value = mock_client

            story_dir = tmp_dir / "story"
            story_dir.mkdir()

            with pytest.raises(BookConstitutionError, match="不是有效 JSON"):
                service.generate_constitution(str(story_dir))

    def test_generate_records_model_ref(self, service, tmp_dir):
        """生成时记录使用的模型。"""
        data = _valid_constitution_data()
        mock_response = MagicMock()
        mock_response.text = json.dumps(data, ensure_ascii=False)

        with patch("inkflow.services.book_constitution.create_model_client") as mock_create:
            mock_client = MagicMock()
            mock_client.generate.return_value = mock_response
            mock_create.return_value = mock_client

            story_dir = tmp_dir / "story"
            story_dir.mkdir()

            service.generate_constitution(str(story_dir))
            c = service.get_latest_constitution()
            assert c["llm_model_ref"] is not None

    def test_generate_with_validation_issues_still_saves(self, service, tmp_dir):
        """即使验证有问题，仍保存为 draft（让人类审核）。"""
        bad_data = _valid_constitution_data()
        bad_data["global_deviation_mean"] = 999  # 非法值
        mock_response = MagicMock()
        mock_response.text = json.dumps(bad_data, ensure_ascii=False)

        with patch("inkflow.services.book_constitution.create_model_client") as mock_create:
            mock_client = MagicMock()
            mock_client.generate.return_value = mock_response
            mock_create.return_value = mock_client

            story_dir = tmp_dir / "story"
            story_dir.mkdir()

            cid = service.generate_constitution(str(story_dir))
            assert cid is not None
            c = service.get_latest_constitution()
            assert c["status"] == "draft"  # 仍然保存
