"""Test utility modules: ULID, hashing, config."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from inkflow.utils import (
    generate_ulid,
    is_valid_ulid,
    snapshot_hash,
    text_hash_normalized,
    context_hash,
    config_hash,
    compute_config_hash,
    load_models_config,
    load_env,
    resolve_model,
)
from inkflow.utils.config import get_jury_config, write_project_config_record


class TestULID:
    """ULID generation and validation"""

    def test_generates_26_char_string(self):
        ulid = generate_ulid()
        assert len(ulid) == 26

    def test_is_valid(self):
        ulid = generate_ulid()
        assert is_valid_ulid(ulid)

    def test_invalid_length(self):
        assert not is_valid_ulid("too_short")
        assert not is_valid_ulid("a" * 27)

    def test_invalid_characters(self):
        assert not is_valid_ulid("I" * 26)  # I is not in base32
        assert not is_valid_ulid("L" * 26)  # L is not in base32
        assert not is_valid_ulid("U" * 26)  # U is not in base32

    def test_monotonic(self):
        """Subsequent calls should produce different ULIDs."""
        ulids = [generate_ulid() for _ in range(100)]
        assert len(set(ulids)) == 100  # All unique

    def test_lexicographic_order(self):
        """Later ULIDs should sort after earlier ones."""
        u1 = generate_ulid()
        # Small delay to ensure different timestamp
        import time
        time.sleep(0.002)
        u2 = generate_ulid()
        assert u1 < u2


class TestHashing:
    """Hashing utilities"""

    def test_snapshot_hash_deterministic(self):
        """Same input → same hash"""
        data = {"key": "value", "items": [1, 2, 3]}
        h1 = snapshot_hash(data)
        h2 = snapshot_hash(data)
        assert h1 == h2
        assert len(h1) == 12

    def test_snapshot_hash_key_order_independent(self):
        """Key order doesn't affect hash"""
        h1 = snapshot_hash({"a": 1, "b": 2})
        h2 = snapshot_hash({"b": 2, "a": 1})
        assert h1 == h2

    def test_snapshot_hash_different_input(self):
        """Different input → different hash"""
        h1 = snapshot_hash({"a": 1})
        h2 = snapshot_hash({"b": 2})
        assert h1 != h2

    def test_text_hash_normalized_whitespace_insensitive(self):
        """Whitespace differences don't affect hash"""
        h1 = text_hash_normalized("hello world")
        h2 = text_hash_normalized("hello   world")
        h3 = text_hash_normalized("  hello world  \n")
        assert h1 == h2 == h3

    def test_text_hash_normalized_content_difference(self):
        """Content difference → different hash"""
        h1 = text_hash_normalized("hello world")
        h2 = text_hash_normalized("hello earth")
        assert h1 != h2

    def test_context_hash_deterministic(self):
        """Same context → same hash"""
        ctx = {"previous_shots": ["s1", "s2"], "fact_anchors": ["a1"]}
        h1 = context_hash(ctx)
        h2 = context_hash(ctx)
        assert h1 == h2
        assert len(h1) == 12

    def test_config_hash_deterministic(self):
        """Same config → same hash"""
        cfg = {"primary": "claude-sonnet-4-6", "candidates": ["gpt-5"]}
        h1 = config_hash(cfg)
        h2 = config_hash(cfg)
        assert h1 == h2


class TestConfig:
    """Configuration loading and resolution"""

    def test_load_models_config(self, tmp_dir: Path):
        """Load .models YAML file"""
        models_dir = tmp_dir / ".inkflow"
        models_dir.mkdir(parents=True)
        models_path = models_dir / ".models"
        models_path.write_text(
            "providers:\n"
            "  test:\n"
            "    api_key: sk-test\n"
            "    base_url: https://test.example.com/v1\n"
            "    protocol: openai\n"
            "architect:\n"
            "  primary: claude-opus-4-6\n"
            "  candidates:\n"
            "    - claude-sonnet-4-6\n"
            "  fallback: gpt-5\n"
            "writer:\n"
            "  primary: claude-sonnet-4-6\n"
            "  candidates:\n"
            "    - gpt-5\n"
            "  fallback: local-default\n",
            encoding="utf-8",
        )

        config = load_models_config(str(tmp_dir))
        assert config["architect"]["primary"] == "claude-opus-4-6"
        assert config["writer"]["primary"] == "claude-sonnet-4-6"
        assert "_meta" in config
        assert "file_hash" in config["_meta"]
        assert "loaded_at" in config["_meta"]

    def test_load_models_config_missing(self, tmp_dir: Path):
        """Missing .models file raises FileNotFoundError"""
        with pytest.raises(FileNotFoundError, match="模型配置"):
            load_models_config(str(tmp_dir))

    def test_resolve_model_primary_available(self, monkeypatch):
        """Resolve primary model by tier."""
        config = {
            "writer": {
                "primary": "claude-sonnet-4-6",
                "candidates": ["gpt-5"],
                "fallback": "local-default",
            }
        }
        model = resolve_model("writer", config, tier="primary")
        assert model == "claude-sonnet-4-6"

    def test_resolve_model_fallback_when_primary_unavailable(self, monkeypatch):
        """Resolve fallback model."""
        config = {
            "writer": {
                "primary": "claude-sonnet-4-6",
                "candidates": ["gpt-5"],
                "fallback": "local-default",
            }
        }
        model = resolve_model("writer", config, tier="fallback")
        assert model == "local-default"

    def test_resolve_model_missing_function(self):
        """Missing function config returns local-default."""
        model = resolve_model("nonexistent", {})
        assert model == "local-default"

    def test_compute_config_hash(self):
        """Config hash excludes _meta"""
        config = {
            "architect": {"primary": "claude-opus-4-6"},
            "_meta": {"file_hash": "abc123"},
        }
        h1 = compute_config_hash(config)
        del config["_meta"]
        h2 = config_hash(config)
        assert h1 == h2

    def test_write_project_config_record(self, db):
        """Write .models config record to DB"""
        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', 'test')")
        config = {
            "architect": {"primary": "claude-opus-4-6"},
            "_meta": {"file_hash": "abc123", "loaded_at": "2026-06-17T00:00:00", "file_path": "/test/.models"},
        }

        config_id = write_project_config_record(db, "p1", config)

        row = db.execute(
            "SELECT * FROM writing_project_config WHERE config_id = ?", (config_id,)
        ).fetchone()
        assert row is not None
        assert row["project_id"] == "p1"

        layers = json.loads(row["layers_json"])
        assert layers["models_file_hash"] == "abc123"
        assert "function_models" in layers

    def test_jury_config_appends_required_current_dimensions(self):
        """旧 .models 显式 dimensions 不再污染 v5 文学 9 维。"""
        config = {
            "jury_config": {
                "dimensions": [
                    "contract_compliance",
                    "forbidden_expression",
                    "reading_fluency",
                ],
            },
        }

        jury = get_jury_config(config)

        assert jury["dimensions"][0] == "hard_rule_compliance"
        assert len(jury["literary_dimensions"]) == 9
        assert "language_texture" in jury["literary_dimensions"]
        assert "chapter_continuity" in jury["literary_dimensions"]
        assert "contract_compliance" not in jury["literary_dimensions"]

    def test_jury_config_defaults_to_local_model(self):
        """未显式配置 jury_config.models 时，生产默认使用本地评委。"""
        jury = get_jury_config({})

        assert jury["models"] == ["local-default"]

    def test_jury_config_keeps_explicit_models(self):
        """显式配置远端评委时保留项目选择。"""
        jury = get_jury_config({
            "jury_config": {"models": ["deepseek-v4-pro", "qwen3.7-plus"]},
        })

        assert jury["models"] == ["deepseek-v4-pro", "qwen3.7-plus"]

    def test_jury_config_does_not_warn_for_same_provider_prefixed_model(self):
        """B81: provider prefix and bare model name should compare equal."""
        import warnings

        config = {
            "roles": {
                "jury": {"primary_model": "agnes-2.0-flash"},
            },
            "jury_config": {
                "models": ["agnes/agnes-2.0-flash"],
            },
        }

        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            jury = get_jury_config(config)

        assert jury["models"] == ["agnes/agnes-2.0-flash"]
        assert not [w for w in caught if "B81" in str(w.message)]

    def test_jury_config_warns_for_different_primary_model(self):
        """B81: conflicting jury model sources should still be visible."""
        config = {
            "roles": {
                "jury": {"primary_model": "agnes-2.0-flash"},
            },
            "jury_config": {
                "models": ["deepseek/deepseek-v4-pro"],
            },
        }

        with pytest.warns(UserWarning, match="B81"):
            jury = get_jury_config(config)

        assert jury["models"] == ["deepseek/deepseek-v4-pro"]

    def test_jury_config_deduplicates_dimensions(self):
        """literary_dimensions 中已有必需维度时不重复追加。"""
        config = {
            "jury_config": {
                "literary_dimensions": [
                    "reading_fluency",
                    "language_texture",
                    "reading_fluency",
                ],
            },
        }

        jury = get_jury_config(config)

        assert jury["literary_dimensions"].count("reading_fluency") == 1
        assert jury["literary_dimensions"][0] == "reading_fluency"

    def test_jury_config_accepts_ten_point_threshold(self):
        """用户配置 8.5 分制时内部换算为 85/100。"""
        jury = get_jury_config({
            "jury_config": {
                "quality_threshold": 8.5,
                "hard_rule_threshold": 8,
                "type_threshold": 9,
                "min_passing_drafts": 3,
            },
        })

        assert jury["quality_threshold"] == 85
        assert jury["hard_rule_threshold"] == 80
        assert jury["type_threshold"] == 90
        assert jury["min_passing_drafts"] == 3

    def test_infer_supplier_supports_agnes(self):
        """Agnes models should resolve to the agnes provider."""
        from inkflow.utils.config import _infer_supplier

        assert _infer_supplier("agnes-2.0-flash", {}) == "agnes"


class TestLoadEnv:
    """M12: load_env coverage."""

    def test_load_env_with_file(self, tmp_dir: Path, monkeypatch):
        """Load .env file and extract known provider keys."""
        from inkflow.utils.config import load_env

        env_file = tmp_dir / ".env"
        env_file.write_text(
            "ANTHROPIC_API_KEY=sk-ant-test123\n"
            "OPENAI_API_KEY=sk-oa-test456\n"
            "SOME_OTHER_KEY=ignored\n",
            encoding="utf-8",
        )

        # Clear any existing keys first
        monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
        monkeypatch.delenv("OPENAI_API_KEY", raising=False)

        result = load_env(env_file)
        assert result.get("ANTHROPIC_API_KEY") == "sk-ant-test123"
        assert result.get("OPENAI_API_KEY") == "sk-oa-test456"
        assert "SOME_OTHER_KEY" not in result

    def test_load_env_no_file_returns_empty(self, monkeypatch):
        """No .env file and no env vars → empty dict."""
        from inkflow.utils.config import load_env

        monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
        monkeypatch.delenv("OPENAI_API_KEY", raising=False)

        result = load_env()
        assert isinstance(result, dict)
