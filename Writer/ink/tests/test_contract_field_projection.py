"""契约字段投影集成测试。"""
from __future__ import annotations

import sqlite3

import pytest

from factories import NOW, make_schema_db
from ink.contract.fields import (
    extract_field_paths_from_payload,
    validate_contract_payload,
)


class TestValidateContractPayload:
    """validate_contract_payload 测试。"""

    def test_valid_book_payload(self) -> None:
        """合法的 book payload。"""
        payload = {
            "identity": {"title": "Demo"},
            "logline": "core promise",
        }
        errors = validate_contract_payload("book", payload)
        assert len(errors) == 0

    def test_missing_required_field(self) -> None:
        """缺少必填字段。"""
        payload = {
            "logline": "core promise",
            # missing identity.title
        }
        errors = validate_contract_payload("book", payload)
        assert len(errors) > 0
        assert any("required field missing" in e for e in errors)

    def test_unknown_field_path(self) -> None:
        """未知字段路径。"""
        payload = {
            "identity": {"title": "Demo"},
            "unknown_field": "value",
        }
        errors = validate_contract_payload("book", payload)
        assert len(errors) > 0
        assert any("not in whitelist" in e for e in errors)

    def test_unknown_scope_type(self) -> None:
        """未知 scope_type。"""
        payload = {"test": "value"}
        errors = validate_contract_payload("unknown", payload)
        assert len(errors) > 0
        assert any("unknown scope_type" in e for e in errors)

    def test_valid_chapter_payload(self) -> None:
        """合法的 chapter payload。"""
        payload = {
            "chapter_id": {"title": "Ch1"},
            "scene_hook": "opening scene",
        }
        errors = validate_contract_payload("chapter", payload)
        assert len(errors) == 0

    def test_missing_nested_required(self) -> None:
        """缺少嵌套必填字段。"""
        payload = {
            "chapter_id": {},  # missing chapter_id.title
        }
        errors = validate_contract_payload("chapter", payload)
        assert len(errors) > 0
        assert any("required field missing" in e and "chapter_id.title" in e for e in errors)


class TestExtractFieldPathsFromPayload:
    """extract_field_paths_from_payload 测试。"""

    def test_extract_book_paths(self) -> None:
        """提取 book payload 的字段路径。"""
        payload = {
            "identity": {"title": "Demo"},
            "logline": "core promise",
        }
        paths = extract_field_paths_from_payload("book", payload)
        assert "identity" in paths
        assert "identity.title" in paths
        assert "logline" in paths

    def test_extract_chapter_paths(self) -> None:
        """提取 chapter payload 的字段路径。"""
        payload = {
            "chapter_id": {"title": "Ch1"},
            "scene_hook": "opening",
        }
        paths = extract_field_paths_from_payload("chapter", payload)
        assert "chapter_id" in paths
        assert "chapter_id.title" in paths
        assert "scene_hook" in paths

    def test_extract_unknown_scope(self) -> None:
        """未知 scope_type 返回空列表。"""
        payload = {"test": "value"}
        paths = extract_field_paths_from_payload("unknown", payload)
        assert paths == []

    def test_extract_empty_payload(self) -> None:
        """空 payload 返回空列表。"""
        paths = extract_field_paths_from_payload("book", {})
        assert paths == []

    def test_extract_only_whitelisted(self) -> None:
        """只提取白名单内的路径。"""
        payload = {
            "identity": {"title": "Demo"},
            "unknown_field": "value",
        }
        paths = extract_field_paths_from_payload("book", payload)
        assert "identity" in paths
        assert "identity.title" in paths
        assert "unknown_field" not in paths


class TestIntegrationWithDecisionSession:
    """与 DecisionSession 的集成测试。"""

    @pytest.fixture
    def conn(self) -> sqlite3.Connection:
        c = make_schema_db()
        c.execute(
            """
            INSERT INTO writing_projects
                (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
            VALUES
                (1, 'demo', 'Demo', '["writer-a","writer-b","writer-c"]',
                 '["judge-a","judge-b","judge-c","judge-d","judge-e"]', ?)
            """,
            (NOW,),
        )
        return c

    def test_confirm_with_valid_payload(self, conn: sqlite3.Connection) -> None:
        """合法 payload 可以 confirm。"""
        from ink.decision_sessions import DecisionSessionStore

        store = DecisionSessionStore(conn)
        session_id = store.start(
            project_id=1,
            scope_type="book",
            scope_id=None,
            target_type="BookContract",
            target_id="book",
            human_text="封基线",
        )
        store.record_ai_parse(
            session_id,
            parsed_patch={"op": "add", "path": "logline", "value": "test"},
            readback_text="测试",
            source_hashes=[],
        )
        store.create_option_set(session_id, options=[{"label": "确认"}], recommended_option=1)
        store.select_option(session_id, 1)

        payload = {
            "identity": {"title": "Demo"},
            "logline": "core promise",
        }
        errors = validate_contract_payload("book", payload)
        assert len(errors) == 0

        # 可以 confirm
        result = store.confirm_and_apply(
            session_id,
            actor="author",
            reason="测试",
            contract_scope_type="book",
            contract_scope_id=None,
            contract_payload=payload,
        )
        assert result.contract_version_id > 0

    def test_extract_paths_for_tracking(self, conn: sqlite3.Connection) -> None:
        """提取字段路径用于追踪。"""
        payload = {
            "identity": {"title": "Demo"},
            "logline": "promise",
            "narrative_voice": ["voice1"],
        }
        paths = extract_field_paths_from_payload("book", payload)
        assert len(paths) > 0
        # 这些路径可以用于 coverage matrix 追踪


class TestShotScope:
    """ShotContract 字段投影测试：对齐 5 张结构化子表。"""

    def test_shot_scope_exists(self) -> None:
        from ink.contract.fields import CONTRACT_FIELD_SCHEMAS
        assert "shot" in CONTRACT_FIELD_SCHEMAS

    def test_shot_has_five_subtable_groups(self) -> None:
        from ink.contract.fields import CONTRACT_FIELD_SCHEMAS
        shot = CONTRACT_FIELD_SCHEMAS["shot"]
        assert set(shot.keys()) == {"must_land", "anti_write", "scene_contract", "persona", "soft_constraints"}

    def test_shot_must_land_paths_valid(self) -> None:
        from ink.contract.fields import validate_field_path
        assert validate_field_path("shot", "must_land")
        assert validate_field_path("shot", "must_land.events")
        assert validate_field_path("shot", "must_land.beats")
        assert validate_field_path("shot", "must_land.information_releases")
        assert not validate_field_path("shot", "must_land.bogus")

    def test_shot_anti_write_paths_valid(self) -> None:
        from ink.contract.fields import validate_field_path
        assert validate_field_path("shot", "anti_write.forbidden_facts")
        assert validate_field_path("shot", "anti_write.forbidden_words")
        assert validate_field_path("shot", "anti_write.pov_only")
        assert not validate_field_path("shot", "anti_write.unknown")

    def test_shot_scene_contract_paths_valid(self) -> None:
        from ink.contract.fields import validate_field_path
        assert validate_field_path("shot", "scene_contract.location")
        assert validate_field_path("shot", "scene_contract.time_of_day")
        assert validate_field_path("shot", "scene_contract.characters_present")
        assert validate_field_path("shot", "scene_contract.character_positions")

    def test_shot_persona_paths_valid(self) -> None:
        from ink.contract.fields import validate_field_path
        assert validate_field_path("shot", "persona.persona")
        assert validate_field_path("shot", "persona.intensity")
        assert validate_field_path("shot", "persona.is_creative_shot")
        assert not validate_field_path("shot", "persona.nonexistent")

    def test_shot_soft_constraints_paths_valid(self) -> None:
        from ink.contract.fields import validate_field_path
        assert validate_field_path("shot", "soft_constraints.relaxable_rules")
        assert validate_field_path("shot", "soft_constraints.deviation_budget")

    def test_shot_payload_validation(self) -> None:
        from ink.contract.fields import validate_contract_payload
        payload = {
            "must_land": {"events": ["e1"], "beats": ["b1"], "information_releases": ["r1"]},
        }
        errors = validate_contract_payload("shot", payload)
        assert errors == []

    def test_shot_payload_unknown_field_rejected(self) -> None:
        from ink.contract.fields import validate_contract_payload
        payload = {"must_land": {"events": ["e1"], "beats": ["b1"], "bogus_field": "x"}}
        errors = validate_contract_payload("shot", payload)
        assert any("bogus_field" in e for e in errors)
