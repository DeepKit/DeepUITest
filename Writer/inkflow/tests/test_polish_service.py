"""Tests for CREATIVE-2 polish stage."""

from __future__ import annotations

from inkflow.services.polish_service import PolishService, conservative_polish


def _setup_revision(db) -> None:
    db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
    db.execute(
        "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
        "VALUES ('s1', 'p1', 'run_01', 'active')"
    )
    db.execute(
        "INSERT INTO writing_shots "
        "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, current_revision_id) "
        "VALUES ('sh1', 'p1', 'run_01', 'v01.c02', 1, 'done_green', 'r1')"
    )
    db.execute(
        "INSERT INTO writing_shot_contracts "
        "(contract_id, project_id, run_id, shot_id, layer_key, contract_status, "
        "snapshot_hash, must_land_json, anti_write_json, contract_json) "
        "VALUES ('c1', 'p1', 'run_01', 'sh1', 'v01.c02', 'locked', 'h1', '{}', '{}', '{}')"
    )
    db.execute(
        "INSERT INTO shot_revisions "
        "(revision_id, shot_id, run_id, contract_id, revision_sequence, operation, text, "
        "text_hash_normalized, writer_persona, is_current, attempt_id) "
        "VALUES ('r1', 'sh1', 'run_01', 'c1', 1, 'write_generate', ?, 'h1', '意象师', 1, 'a1')",
        (_messy_text(),),
    )
    db.commit()


def _messy_text() -> str:
    sentence = (
        "阿坤 抬头 ，看见保鲜膜贴在窗上。"
        "茶杯里的水晃了一下，他没有解释，只把手收回袖子里。"
        "楼道里有人咳嗽，声音短得像被系统剪掉了一截。"
    )
    return sentence * 5


class TestConservativePolish:
    def test_polish_normalizes_spacing_and_splits_long_paragraphs(self):
        result = conservative_polish(_messy_text(), max_paragraph_chars=180)

        assert " ，" not in result
        assert "\n\n" in result
        assert "保鲜膜" in result
        assert "系统" in result


class TestPolishService:
    def test_polish_revision_writes_child_revision(self, db):
        _setup_revision(db)
        svc = PolishService(db, "p1", "run_01")

        result = svc.polish_revision(
            shot_id="sh1",
            source_revision_id="r1",
            contract_id="c1",
            gate_result={"light_status": "green"},
            jury_summary={"winner_score": 90},
        )

        assert result["applied"] is True
        assert result["parent_revision_id"] == "r1"
        assert result["revision_sequence"] == 2

        source = db.execute(
            "SELECT is_current FROM shot_revisions WHERE revision_id = 'r1'"
        ).fetchone()
        assert source["is_current"] == 0

        polished = db.execute(
            "SELECT * FROM shot_revisions WHERE revision_id = ?",
            (result["revision_id"],),
        ).fetchone()
        assert polished["operation"] == "write_polish"
        assert polished["parent_revision_id"] == "r1"
        assert polished["is_current"] == 1
        assert "保鲜膜" in polished["text"]

        shot = db.execute(
            "SELECT current_revision_id FROM writing_shots WHERE shot_id = 'sh1'"
        ).fetchone()
        assert shot["current_revision_id"] == result["revision_id"]

    def test_polish_revision_skips_noop(self, db):
        _setup_revision(db)
        db.execute(
            "UPDATE shot_revisions SET text = ? WHERE revision_id = 'r1'",
            ("阿坤抬头，看见保鲜膜贴在窗上。茶杯里的水晃了一下。" * 3,),
        )
        db.commit()

        svc = PolishService(db, "p1", "run_01")
        result = svc.polish_revision(
            shot_id="sh1",
            source_revision_id="r1",
            contract_id="c1",
        )

        assert result["applied"] is False
        assert result["reason"] == "no_changes"
        count = db.execute(
            "SELECT COUNT(*) FROM shot_revisions WHERE shot_id = 'sh1'"
        ).fetchone()[0]
        assert count == 1
