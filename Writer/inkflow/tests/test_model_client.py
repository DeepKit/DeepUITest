"""Tests for ModelClient and LocalDefaultGenerator (P0-2 / B14)."""

from __future__ import annotations

import pytest

from inkflow.services.model_client import (
    LocalDefaultGenerator,
    ModelRequest,
    ModelResponse,
    _record_model_error,
    create_model_client,
)


class TestLocalDefaultGenerator:
    """B14: writer race should produce >=50 char output, not placeholder."""

    def test_generate_returns_model_response(self):
        gen = LocalDefaultGenerator()
        req = ModelRequest(
            operation="write_generate",
            persona="imagist",
            prompt="test prompt",
            shot_id="shot_01",
            run_id="run_01",
        )
        resp = gen.generate(req)
        assert isinstance(resp, ModelResponse)
        assert resp.model == "local-default"
        assert resp.finish_reason == "stop"

    def test_output_length_at_least_50_chars(self):
        """Gate1 requires >= 50 chars; local-default must satisfy."""
        gen = LocalDefaultGenerator()
        for persona in ["imagist", "pacer", "dialogist", "structuralist"]:
            req = ModelRequest(
                operation="write_generate",
                persona=persona,
                prompt="test",
                shot_id="shot_01",
            )
            resp = gen.generate(req)
            assert len(resp.text) >= 50, f"{persona} produced <50 chars: {resp.text!r}"

    def test_deterministic_same_seed_same_output(self):
        """Same shot + persona should produce identical text (idempotent)."""
        gen = LocalDefaultGenerator()
        req1 = ModelRequest(
            operation="write_generate", persona="pacer", prompt="", shot_id="s1"
        )
        req2 = ModelRequest(
            operation="write_generate", persona="pacer", prompt="", shot_id="s1"
        )
        assert gen.generate(req1).text == gen.generate(req2).text

    def test_different_personas_different_output(self):
        gen = LocalDefaultGenerator()
        texts = []
        for persona in ["imagist", "pacer", "dialogist", "structuralist"]:
            req = ModelRequest(
                operation="write_generate",
                persona=persona,
                prompt="",
                shot_id="s1",
            )
            texts.append(gen.generate(req).text)
        # All 4 personas should produce different text
        assert len(set(texts)) == 4

    def test_different_shots_different_output(self):
        gen = LocalDefaultGenerator()
        req1 = ModelRequest(
            operation="write_generate", persona="imagist", prompt="", shot_id="s1"
        )
        req2 = ModelRequest(
            operation="write_generate", persona="imagist", prompt="", shot_id="s2"
        )
        assert gen.generate(req1).text != gen.generate(req2).text

    def test_prompt_beats_are_used_in_output(self):
        gen = LocalDefaultGenerator()
        prompt = """第一句话以「雾还没有散」开头，然后继续写。

场景要点：
- 郑坤的第二单在石板滩，外江
- 内江同时有 37 单，系统给他的建议全是外江
- 他从包里拿出新的保鲜膜

现在开始写。
## 视角约束（严格遵守）
⚠️ 只写 郑坤 的视角。不要切换到其他角色的场景。
"""
        resp = gen.generate(ModelRequest(
            operation="write_generate",
            persona="意象师",
            prompt=prompt,
            shot_id="v01.c02.s01",
            run_id="run_01",
        ))

        assert resp.text.startswith("雾还没有散")
        assert "郑坤" in resp.text
        assert "37 单" in resp.text
        assert "保鲜膜" in resp.text

    def test_local_jury_score_returns_json(self):
        gen = LocalDefaultGenerator()
        prompt = "【待评文本】\n郑坤把保鲜膜压在膝盖上，手机屏幕跳出 37 单。\n\n请给出 0-100 分。"
        resp = gen.generate(ModelRequest(
            operation="jury_score",
            persona="评委_local",
            prompt=prompt,
            shot_id="shot_01",
            run_id="run_01",
        ))

        assert '"score"' in resp.text
        assert "local-default heuristic score" in resp.text


class TestCreateModelClient:
    """Factory tests."""

    def test_create_local_default(self):
        client = create_model_client("local-default")
        assert isinstance(client, LocalDefaultGenerator)

    def test_unknown_model_raises(self):
        with pytest.raises(ValueError, match="Unknown model"):
            create_model_client("gpt-nonexistent")


def test_record_model_error_writes_attempt(db):
    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    db.execute(
        "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
        "VALUES ('s1', 'proj_01', 'run_01', 'active')"
    )
    db.execute(
        "INSERT INTO writing_shots "
        "(shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
        "VALUES ('shot_01', 'proj_01', 'run_01', 'v01.c02', 1, 'pending')"
    )
    db.commit()

    req = ModelRequest(
        operation="jury_score",
        persona="评委_test",
        prompt="score this",
        model="remote-model",
        shot_id="shot_01",
        run_id="run_01",
    )

    _record_model_error(db, req, "remote-model", "timed out")

    row = db.execute(
        "SELECT phase, model_name, error_message FROM model_attempts "
        "WHERE shot_id = 'shot_01'"
    ).fetchone()
    assert row is not None
    assert row["phase"] == "jury_score"
    assert row["model_name"] == "remote-model"
    assert row["error_message"] == "timed out"


def test_model_attempt_idempotency_includes_prompt_hash(db):
    db.execute("INSERT INTO projects (project_id, name) VALUES ('proj_01', '分流')")
    db.execute(
        "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
        "VALUES ('s1', 'proj_01', 'run_01', 'active')"
    )
    db.execute(
        "INSERT INTO writing_shots "
        "(shot_id, project_id, run_id, layer_key, shot_index, shot_status) "
        "VALUES ('shot_01', 'proj_01', 'run_01', 'v01.c02', 1, 'pending')"
    )
    db.commit()

    gen = LocalDefaultGenerator(db)
    base = {
        "operation": "jury_score",
        "persona": "评委_local",
        "shot_id": "shot_01",
        "run_id": "run_01",
    }
    gen.generate(ModelRequest(prompt="【待评文本】\n文本一", **base))
    gen.generate(ModelRequest(prompt="【待评文本】\n文本二", **base))
    gen.generate(ModelRequest(prompt="【待评文本】\n文本二", **base))

    row = db.execute(
        "SELECT COUNT(*) AS cnt FROM model_attempts "
        "WHERE shot_id = 'shot_01' AND phase = 'jury_score'"
    ).fetchone()
    assert row["cnt"] == 2
