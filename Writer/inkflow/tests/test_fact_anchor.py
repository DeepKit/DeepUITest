"""Tests for Fact Anchor extraction and injection (P0-5/6 / B17)."""

from __future__ import annotations

import pytest

from inkflow.services.fact_anchor_extractor import FactAnchorExtractor


@pytest.fixture
def extractor(db):
    """FactAnchorExtractor with a project set up."""
    db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', '测试')")
    db.execute(
        "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
        "VALUES ('s1', 'p1', 'run_01', 'active')"
    )
    db.execute(
        "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
        "VALUES ('sh1', 'p1', 'run_01', 'v01.c02', 1, 'pending')"
    )
    db.execute(
        "INSERT INTO writing_shot_contracts "
        "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
        "snapshot_hash, must_land_json, anti_write_json, contract_json) "
        "VALUES ('c1', 'p1', 'run_01', 'sh1', 'v01.c02', 'draft', 'h1', '{}', '{}', '{}')"
    )
    db.execute(
        "INSERT INTO shot_revisions "
        "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, text, text_hash_normalized, attempt_id) "
        "VALUES ('rev1', 'sh1', 'run_01', 'c1', 1, 'write_generate', 'test', 'hash1', 'att1')"
    )
    db.commit()
    return FactAnchorExtractor(db, "p1", {})


class TestFactAnchorExtraction:
    """B17: extract() should produce non-empty anchors for text with keywords."""

    def test_extract_empty_text_returns_empty(self, extractor):
        assert extractor.extract("sh1", "run_01", "", "rev1") == []
        assert extractor.extract("sh1", "run_01", "   ", "rev1") == []

    def test_extract_no_keywords_returns_empty(self, extractor):
        # Text without keyword matches
        assert extractor.extract("sh1", "run_01", "abc def", "rev1") == []

    def test_extract_character_state(self, extractor):
        """Character state keywords should produce anchors."""
        text = "阿坤醒了。窗外的天还是灰的。他从枕头下面摸出保鲜膜。"
        ids = extractor.extract("sh1", "run_01", text, "rev1")
        assert len(ids) >= 1  # At least one character state anchor

    def test_extract_object_location(self, extractor):
        """Object location keywords should produce anchors."""
        text = "他把信放在桌子上。窗户旁边有一把旧椅子。"
        ids = extractor.extract("sh1", "run_01", text, "rev1")
        assert len(ids) >= 1

    def test_extract_event_occurred(self, extractor):
        """Event keywords should produce anchors."""
        text = "他拿起钥匙，走向门口，打开了门。"
        ids = extractor.extract("sh1", "run_01", text, "rev1")
        assert len(ids) >= 1

    def test_extract_returns_db_persisted_anchors(self, extractor):
        """Extracted anchors should be queryable from DB."""
        text = "阿坤醒了。他拿起钥匙，走向门口。"
        ids = extractor.extract("sh1", "run_01", text, "rev1")
        assert len(ids) >= 1

        anchors = extractor.get_anchors_for_shot("sh1")
        assert len(anchors) >= 1
        for a in anchors:
            assert a["shot_id"] == "sh1"
            assert a["run_id"] == "run_01"
            assert a["anchor_type"] in (
                "character_state", "object_location", "event_occurred"
            )

    def test_get_active_anchors_returns_recent(self, extractor):
        """get_active_anchors should return anchors from any shot."""
        text = "阿坤醒了。他拿起钥匙。"
        extractor.extract("sh1", "run_01", text, "rev1")
        active = extractor.get_active_anchors(limit=10, run_id="run_01")
        assert len(active) >= 1

    def test_get_active_anchors_excludes_unaccepted_old_runs(self, extractor):
        """Without current run, only accepted/baseline anchors are canonical."""
        db = extractor.db
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s2', 'p1', 'run_02', 'completed')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, current_revision_id) "
            "VALUES ('sh2', 'p1', 'run_02', 'v01.c03', 1, 'done_green', 'rev2')"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('c2', 'p1', 'run_02', 'sh2', 'v01.c03', 'locked', 'h2', '{}', '{}', '{}')"
        )
        db.execute(
            "INSERT INTO shot_revisions "
            "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
            "text, text_hash_normalized, attempt_id) "
            "VALUES ('rev2', 'sh2', 'run_02', 'c2', 1, 'write_generate', 'test2', 'hash2', 'att2')"
        )
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s3', 'p1', 'run_03', 'completed')"
        )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, current_revision_id) "
            "VALUES ('sh3', 'p1', 'run_03', 'v01.c04', 1, 'done_green', 'rev3')"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('c3', 'p1', 'run_03', 'sh3', 'v01.c04', 'locked', 'h3', '{}', '{}', '{}')"
        )
        db.execute(
            "INSERT INTO shot_revisions "
            "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, "
            "text, text_hash_normalized, attempt_id) "
            "VALUES ('rev3', 'sh3', 'run_03', 'c3', 1, 'write_generate', 'test3', 'hash3', 'att3')"
        )
        db.execute(
            "INSERT INTO writing_chapter_reviews "
            "(review_id, project_id, chapter_key, run_id, status) "
            "VALUES ('review3', 'p1', 'v01.c04', 'run_03', 'accepted')"
        )
        db.commit()

        extractor.record_anchor(
            "event_occurred", "event:unaccepted", "未接受事实", 0.8,
            run_id="run_02", shot_id="sh2", source_revision_id="rev2",
        )
        extractor.record_anchor(
            "event_occurred", "event:accepted", "已接受事实", 0.8,
            run_id="run_03", shot_id="sh3", source_revision_id="rev3",
        )

        active = extractor.get_active_anchors(limit=10)
        values = {anchor["anchor_value"] for anchor in active}
        assert "已接受事实" in values
        assert "未接受事实" not in values


class TestFactAnchorInjection:
    """P0-6: Anchors should be injectable into prompt_compiler."""

    def test_compile_shot_prompt_with_anchors(self, db):
        """compile_shot_prompt should include fact anchors in output."""
        from inkflow.services.prompt_compiler import PromptCompiler

        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', '测试')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        db.execute(
            "INSERT INTO writing_shots (shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
            "VALUES ('sh1', 'p1', 'run_01', 'v01.c02', 1, 'pending')"
        )
        db.execute(
            "INSERT INTO writing_shot_contracts "
            "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
            "snapshot_hash, must_land_json, anti_write_json, contract_json) "
            "VALUES ('c1', 'p1', 'run_01', 'sh1', 'v01.c02', 'draft', 'h1', '{}', '{}', '{}')"
        )
        db.execute(
            "INSERT INTO writing_fact_anchors "
            "(anchor_id, project_id, run_id, shot_id, anchor_type, anchor_key, "
            "anchor_value, confidence) "
            "VALUES ('a1', 'p1', 'run_01', 'sh1', 'character_state', "
            "'character_state:abc', 'test value', 0.8)"
        )
        db.commit()

        compiler = PromptCompiler(db)
        anchors = [{"anchor_key": "character_state:abc", "anchor_value": "阿坤醒了",
                    "anchor_type": "character_state", "confidence": 0.8}]
        static_prefix = {
            "prefix_text": "static prefix content",
            "prefix_length": 10,
            "prefix_hash": "h1",
        }
        prompt_id = compiler.compile_shot_prompt(
            "sh1", "run_01", "意象师",
            static_prefix,
            {"must_land": {}, "anti_write": {}},
            fact_anchors=anchors,
        )
        assert prompt_id is not None

        # Verify the compiled prompt contains the anchor
        row = db.execute(
            "SELECT assembled_prompt FROM writing_shot_prompts WHERE prompt_id = ?",
            (prompt_id,),
        ).fetchone()
        assert row is not None
        compiled = row["assembled_prompt"] or ""
        # dynamic_assembly_json should contain the anchor
        import json
        dyn_json = db.execute(
            "SELECT dynamic_assembly_json FROM writing_shot_prompts WHERE prompt_id = ?",
            (prompt_id,),
        ).fetchone()
        dyn_text = json.dumps(json.loads(dyn_json["dynamic_assembly_json"]), ensure_ascii=False)
        assert "阿坤醒了" in compiled or "阿坤醒了" in dyn_text
