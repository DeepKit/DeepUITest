"""模型角色主/备/兜底配置模块测试。

覆盖:
- ``load_role_chain`` 单档补位、三档、缺档抛 ConfigError;
- ``upsert`` UPSERT 幂等、tier 校验;
- ``validate_role_chain`` env/base_url 校验;
- CLI ``init --role-config`` 落库 + 向后兼容(无 role-config 时从旧池生成 primary 单档);
- CLI ``role-config set/get/validate`` 子命令。
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pytest

from ink.cli import main
from ink.core.model_role_config import (
    load_role_chain,
    list_role_configs,
    upsert_role_config,
    validate_role_chain,
)
from ink.errors import ConfigError


def _row(db_path: Path, sql: str):
    conn = sqlite3.connect(db_path)
    try:
        return conn.execute(sql).fetchone()
    finally:
        conn.close()


def _conn(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


# ---------- 模块 API ----------


def test_load_role_chain_single_tier_rolls_forward(tmp_path: Path) -> None:
    """只配 primary 单档时,补位成 [primary, primary, primary] —— 向后兼容旧项目。"""
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "c1", "--title", "T"]) == 0
    conn = _conn(db_path)
    try:
        upsert_role_config(
            conn,
            project_id=1,
            call_type="jury",
            tier="primary",
            model_name="glm52",
            provider="openai-compatible",
            api_key_env="IFLYTEK_KEY",
            base_url="https://x",
        )
        chain = load_role_chain(conn, project_id=1, call_type="jury")
        assert len(chain) == 3
        assert all(c.model_name == "glm52" for c in chain)
        assert [c.tier for c in chain] == ["primary", "secondary", "tertiary"]
    finally:
        conn.close()


def test_load_role_chain_three_tiers_cross_vendor(tmp_path: Path) -> None:
    """配齐三档跨供应商,链按 primary->secondary->tertiary 顺序返回。"""
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "c1", "--title", "T"]) == 0
    conn = _conn(db_path)
    try:
        for tier, model, env in [
            ("primary", "glm52", "IFLYTEK_KEY"),
            ("secondary", "deepseek-v4", "DEEPSEEK_KEY"),
            ("tertiary", "qwen", "QWEN_KEY"),
        ]:
            upsert_role_config(
                conn, project_id=1, call_type="draft", tier=tier,
                model_name=model, provider="openai-compatible",
                api_key_env=env, base_url=f"https://{tier}",
            )
        chain = load_role_chain(conn, project_id=1, call_type="draft")
        assert [c.model_name for c in chain] == ["glm52", "deepseek-v4", "qwen"]
        assert [c.api_key_env for c in chain] == ["IFLYTEK_KEY", "DEEPSEEK_KEY", "QWEN_KEY"]
    finally:
        conn.close()


def test_load_role_chain_missing_call_type_raises(tmp_path: Path) -> None:
    """完全无配置的 call_type 抛 ConfigError,提示用 CLI 补齐。"""
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "c1", "--title", "T"]) == 0
    conn = _conn(db_path)
    try:
        with pytest.raises(ConfigError, match="role-config"):
            load_role_chain(conn, project_id=1, call_type="notexist")
    finally:
        conn.close()


def test_upsert_is_idempotent_and_updates(tmp_path: Path) -> None:
    """同 (project_id, call_type, tier) 第二次 upsert 更新而非插入。"""
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "c1", "--title", "T"]) == 0
    conn = _conn(db_path)
    try:
        rid1 = upsert_role_config(
            conn, project_id=1, call_type="polish", tier="primary",
            model_name="old", provider="mock", api_key_env="K",
        )
        rid2 = upsert_role_config(
            conn, project_id=1, call_type="polish", tier="primary",
            model_name="new", provider="mock", api_key_env="K",
        )
        assert rid1 == rid2  # UPSERT 同一行
        chain = load_role_chain(conn, project_id=1, call_type="polish")
        assert chain[0].model_name == "new"
        # 只应有 1 行(primary 补位不落库,只读时补)
        rows = conn.execute(
            "SELECT COUNT(*) FROM writing_model_role_configs WHERE call_type='polish'"
        ).fetchone()[0]
        assert rows == 1
    finally:
        conn.close()


def test_upsert_rejects_bad_tier(tmp_path: Path) -> None:
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "c1", "--title", "T"]) == 0
    conn = _conn(db_path)
    try:
        with pytest.raises(ConfigError, match="tier"):
            upsert_role_config(
                conn, project_id=1, call_type="draft", tier="quaternary",
                model_name="m", provider="mock", api_key_env="K",
            )
    finally:
        conn.close()


def test_validate_role_chain_detects_missing_env(tmp_path: Path, monkeypatch) -> None:
    """validate 检出 env 未设 + openai-compatible 缺 base_url。"""
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "c1", "--title", "T"]) == 0
    conn = _conn(db_path)
    try:
        upsert_role_config(
            conn, project_id=1, call_type="draft", tier="primary",
            model_name="m", provider="openai-compatible",
            api_key_env="NEVER_SET_ENV", base_url=None,  # 缺 base_url
        )
        chain = load_role_chain(conn, project_id=1, call_type="draft")
        # 确保 env 确实不存在
        monkeypatch.delenv("NEVER_SET_ENV", raising=False)
        errors = validate_role_chain(chain)
        assert any("NEVER_SET_ENV" in e for e in errors)
        assert any("base_url" in e for e in errors)
    finally:
        conn.close()


# ---------- CLI ----------


def test_cli_init_with_role_config_json(tmp_path: Path) -> None:
    """init --role-config JSON 一次性配多 call_type 三档。"""
    db_path = tmp_path / "ink.sqlite"
    role_cfg = {
        "draft": {
            "primary": {"model_name": "glm52", "provider": "openai-compatible",
                        "base_url": "https://a", "api_key_env": "IFLYTEK_KEY", "max_tokens": 2000},
            "secondary": {"model_name": "deepseek-v4", "provider": "openai-compatible",
                          "base_url": "https://b", "api_key_env": "DEEPSEEK_KEY"},
            "tertiary": {"model_name": "qwen", "provider": "openai-compatible",
                         "base_url": "https://c", "api_key_env": "QWEN_KEY"},
        },
        "jury": {
            "primary": {"model_name": "glm52", "provider": "openai-compatible",
                        "base_url": "https://a", "api_key_env": "IFLYTEK_KEY"},
        },
    }
    assert main([
        "--db", str(db_path), "init", "--code", "rc1", "--title", "RC",
        "--role-config", json.dumps(role_cfg),
    ]) == 0
    conn = _conn(db_path)
    try:
        draft_chain = load_role_chain(conn, project_id=1, call_type="draft")
        assert [c.model_name for c in draft_chain] == ["glm52", "deepseek-v4", "qwen"]
        jury_chain = load_role_chain(conn, project_id=1, call_type="jury")
        assert jury_chain[0].model_name == "glm52"
        assert all(c.model_name == "glm52" for c in jury_chain)  # 单档补位
    finally:
        conn.close()


def test_cli_init_backward_compat_seeds_primary_from_pool(tmp_path: Path, monkeypatch) -> None:
    """无 --role-config 时,从 --writer-models/--jury-models 首个模型生成 primary 单档。"""
    db_path = tmp_path / "ink.sqlite"
    monkeypatch.setenv("INK_LLM_PROVIDER", "openai-compatible")
    monkeypatch.setenv("INK_LLM_BASE_URL", "https://default")
    monkeypatch.setenv("INK_LLM_API_KEY_ENV", "INK_LLM_API_KEY")
    assert main([
        "--db", str(db_path), "init", "--code", "bc1", "--title", "BC",
        "--writer-models", "w1,w2,w3", "--jury-models", "j1,j2,j3",
    ]) == 0
    conn = _conn(db_path)
    try:
        draft = load_role_chain(conn, project_id=1, call_type="draft")
        assert draft[0].model_name == "w1"
        assert draft[0].provider == "openai-compatible"
        jury = load_role_chain(conn, project_id=1, call_type="jury")
        assert jury[0].model_name == "j1"
    finally:
        conn.close()


def test_cli_role_config_set_get_validate(tmp_path: Path, monkeypatch, capsys) -> None:
    """role-config set/get/validate 子命令链路。"""
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "c1", "--title", "T"]) == 0
    capsys.readouterr()  # 清空 init 输出
    # set primary + secondary
    assert main([
        "--db", str(db_path), "role-config", "set",
        "--project-id", "1", "--call-type", "draft", "--tier", "primary",
        "--model-name", "glm52", "--provider", "openai-compatible",
        "--base-url", "https://a", "--api-key-env", "IFLYTEK_KEY", "--max-tokens", "2000",
    ]) == 0
    capsys.readouterr()
    assert main([
        "--db", str(db_path), "role-config", "set",
        "--project-id", "1", "--call-type", "draft", "--tier", "secondary",
        "--model-name", "deepseek-v4", "--provider", "openai-compatible",
        "--base-url", "https://b", "--api-key-env", "DEEPSEEK_KEY",
    ]) == 0
    capsys.readouterr()
    # get:列出该 call_type 配置
    assert main([
        "--db", str(db_path), "role-config", "get",
        "--project-id", "1", "--call-type", "draft",
    ]) == 0
    get_payload = json.loads(capsys.readouterr().out)
    configs = get_payload["data"]["configs"]
    assert len(configs) == 2  # primary + secondary(tertiary 未配)
    assert {c["tier"] for c in configs} == {"primary", "secondary"}
    # validate:secondary 已设,tertiary 补位用 secondary(deepseek-v4);env 都要存在
    monkeypatch.setenv("IFLYTEK_KEY", "fake")
    monkeypatch.setenv("DEEPSEEK_KEY", "fake")
    assert main([
        "--db", str(db_path), "role-config", "validate",
        "--project-id", "1", "--call-type", "draft",
    ]) == 0
    val_payload = json.loads(capsys.readouterr().out)
    assert val_payload["data"]["valid"] is True
    assert val_payload["data"]["errors"] == []
    # 链补位:tertiary 应等于 secondary
    chain = val_payload["data"]["chain"]
    assert chain[2]["model_name"] == "deepseek-v4"


def test_cli_role_config_validate_detects_missing_env(tmp_path: Path, monkeypatch, capsys) -> None:
    """validate 检出未设环境变量。"""
    db_path = tmp_path / "ink.sqlite"
    assert main(["--db", str(db_path), "init", "--code", "c1", "--title", "T"]) == 0
    capsys.readouterr()
    assert main([
        "--db", str(db_path), "role-config", "set",
        "--project-id", "1", "--call-type", "draft", "--tier", "primary",
        "--model-name", "m", "--provider", "openai-compatible",
        "--base-url", "https://a", "--api-key-env", "NEVER_SET_ENV_123",
    ]) == 0
    capsys.readouterr()
    monkeypatch.delenv("NEVER_SET_ENV_123", raising=False)
    assert main([
        "--db", str(db_path), "role-config", "validate",
        "--project-id", "1", "--call-type", "draft",
    ]) == 0
    val_payload = json.loads(capsys.readouterr().out)
    assert val_payload["data"]["valid"] is False
    assert any("NEVER_SET_ENV_123" in e for e in val_payload["data"]["errors"])
