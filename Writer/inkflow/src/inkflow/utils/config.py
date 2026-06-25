"""Configuration loading for InkFlow.

Handles:
- .inkflow/.models YAML: project-level model + providers configuration
- API key resolution for model providers
"""

from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

from inkflow.utils.hashing import config_hash


def load_models_config(project_root: str | Path) -> dict:
    """Load .inkflow/.models YAML file.

    Returns parsed dict including providers, function configs, and _meta.

    Raises:
        FileNotFoundError: If .models file doesn't exist.
    """
    project_root = Path(project_root)
    models_path = project_root / ".inkflow" / ".models"

    if not models_path.exists():
        raise FileNotFoundError(
            f"模型配置文件不存在: {models_path}\n"
            f"请创建 .inkflow/.models 文件。"
        )

    raw = models_path.read_text(encoding="utf-8")
    try:
        parsed = yaml.safe_load(raw)
    except yaml.YAMLError as e:
        raise ValueError(
            f"模型配置文件 YAML 语法错误: {models_path}\n"
            f"错误详情: {e}\n"
            f"请检查 .inkflow/.models 文件的缩进和语法。"
        ) from e
    if not isinstance(parsed, dict):
        raise ValueError(
            f"模型配置文件格式错误: {models_path}\n"
            f"期望 YAML 字典，实际为 {type(parsed).__name__}。"
        )

    if "providers" not in parsed:
        raise ValueError(
            f"模型配置文件缺少 providers 段: {models_path}"
        )

    parsed["_meta"] = {
        "file_hash": hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12],
        "loaded_at": datetime.now(timezone.utc).isoformat(),
        "file_path": str(models_path.resolve()),
    }

    return parsed


def load_env(env_path: str | Path | None = None) -> dict[str, str]:
    """Load .env file and return environment variables."""
    from dotenv import load_dotenv as _load_dotenv

    if env_path:
        _load_dotenv(env_path)
    else:
        import warnings
        warnings.warn(
            "load_env() called without explicit env_path. "
            "Searching from CWD may load unrelated .env files.",
            stacklevel=2,
        )
        _load_dotenv()

    result = {}
    for key in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY"):
        if os.getenv(key):
            result[key] = os.getenv(key)
    return result


def resolve_model(
    function: str,
    models_config: dict,
    *,
    tier: str = "primary",
) -> str:
    """解析角色的模型名（兼容 v3/v4 格式）。

    Args:
        function: 角色名 (writer, jury, architect, fact_anchor, repair, outline_evaluator)
        models_config: 解析后的 .models 配置
        tier: 'primary' / 'backup' / 'fallback'

    Returns:
        模型名字符串（不含供应商前缀）
    """
    # v4 格式: roles.writer.primary_model = "stepfun/step-router-v1"
    roles = models_config.get("roles", {})
    role_cfg = roles.get(function)
    if role_cfg:
        key_map = {
            "primary": "primary_model",
            "backup": "backup_model",
            "fallback": "fallback_model",
        }
        ref = role_cfg.get(key_map.get(tier, "primary_model"))
        if ref:
            _, model_name = parse_model_ref(ref)
            return model_name
        return "local-default"

    # v3 格式兼容
    func_config = models_config.get(function)
    if not func_config:
        return "local-default"

    if tier in ("primary", "backup"):
        return func_config.get("primary", "local-default")

    if tier in ("light", "heavy"):
        items = func_config.get(tier, [])
        return items[0] if items else func_config.get("primary", "local-default")

    if tier == "fallback":
        return func_config.get("fallback", "local-default")

    return "local-default"


def resolve_model_chain(role: str, models_config: dict) -> list[str]:
    """解析角色的模型链 [首用, 备用, 兜底]。

    Returns:
        ["stepfun/step-router-v1", "bailian/qwen3.7-plus", "deepseek/deepseek-v4-pro"]
    """
    # v4 格式
    roles = models_config.get("roles", {})
    role_cfg = roles.get(role)
    if role_cfg:
        chain = []
        for key in ("primary_model", "backup_model", "fallback_model"):
            ref = role_cfg.get(key)
            if ref:
                chain.append(ref)
        return chain or ["local-default"]

    # v3 格式兼容
    func_config = models_config.get(role)
    if not func_config:
        return ["local-default"]

    chain = []
    primary = func_config.get("primary")
    if primary:
        supplier = _infer_supplier(primary, models_config)
        chain.append(f"{supplier}/{primary}")
    for c in func_config.get("candidates", [])[:1]:
        supplier = _infer_supplier(c, models_config)
        chain.append(f"{supplier}/{c}")
    fallback = func_config.get("fallback")
    if fallback:
        supplier = _infer_supplier(fallback, models_config)
        chain.append(f"{supplier}/{fallback}")
    return chain or ["local-default"]


def parse_model_ref(ref: str) -> tuple[str, str]:
    """解析 '供应商/模型名' 格式。

    >>> parse_model_ref("stepfun/step-router-v1")
    ('stepfun', 'step-router-v1')
    >>> parse_model_ref("step-router-v1")
    ('stepfun', 'step-router-v1')
    """
    if "/" in ref:
        supplier, model = ref.split("/", 1)
        return supplier, model
    return _infer_supplier(ref, {}), ref


def get_model_params(model_name: str, models_config: dict) -> dict:
    """获取模型参数 (temperature, max_tokens)。"""
    params = models_config.get("model_params", {})
    return params.get(model_name, {"temperature": 0.8, "max_tokens": 16384})


def build_providers_for_model(model_ref: str, models_config: dict) -> dict:
    """为指定模型构建 providers 字典，传给 create_model_client()。"""
    supplier, _ = parse_model_ref(model_ref)
    provider_cfg = models_config.get("providers", {}).get(supplier, {})
    return {supplier: provider_cfg}


def get_jury_config(models_config: dict) -> dict:
    """获取评委配置 (默认 3 模型 + 5 维度 + 阈值)。"""
    from inkflow.models.enums import JURY_V4_MODELS_DEFAULT, JURY_V4_DIMENSIONS

    jury_cfg = models_config.get("jury_config", {})
    dimensions = _merge_required_dimensions(
        jury_cfg.get("dimensions"),
        JURY_V4_DIMENSIONS,
    )
    return {
        "models": jury_cfg.get("models", JURY_V4_MODELS_DEFAULT),
        "dimensions": dimensions,
        "quality_threshold": jury_cfg.get("quality_threshold", 80),
        "outline_threshold": jury_cfg.get("outline_threshold", 70),
    }


def _merge_required_dimensions(configured: object, required: list[str]) -> list[str]:
    """Preserve configured order while appending required current dimensions."""
    if not isinstance(configured, list) or not configured:
        return list(required)

    dimensions: list[str] = []
    for dimension in configured:
        if isinstance(dimension, str) and dimension not in dimensions:
            dimensions.append(dimension)
    for dimension in required:
        if dimension not in dimensions:
            dimensions.append(dimension)
    return dimensions


def get_quality_threshold(models_config: dict) -> int:
    """获取质量阈值（默认 80）。"""
    return get_jury_config(models_config)["quality_threshold"]


def get_outline_threshold(models_config: dict) -> int:
    """获取大纲阈值（默认 70）。"""
    return get_jury_config(models_config)["outline_threshold"]


def _infer_supplier(model_name: str, models_config: dict) -> str:
    """从模型名推断所属供应商（v3 兼容）。"""
    if model_name.startswith("step"):
        return "stepfun"
    elif model_name.startswith("qwen"):
        return "bailian"
    elif model_name.startswith("deepseek"):
        return "deepseek"
    return "stepfun"


def compute_config_hash(models_config: dict) -> str:
    """Compute a hash of the models config (excluding _meta)."""
    clean = {k: v for k, v in models_config.items() if k != "_meta"}
    return config_hash(clean)


def write_project_config_record(
    db_conn,
    project_id: str,
    models_config: dict,
) -> str:
    """Write the .models config record to writing_project_config."""
    from inkflow.utils.ulid import generate

    config_id = generate()
    meta = models_config.get("_meta", {})

    layers_json = {
        "models_file_hash": meta.get("file_hash", "unknown"),
        "models_loaded_at": meta.get("loaded_at", "unknown"),
        "models_file_path": meta.get("file_path", "unknown"),
        "function_models": {
            k: v for k, v in models_config.items() if k != "_meta"
        },
    }

    db_conn.execute(
        "INSERT OR REPLACE INTO writing_project_config "
        "(config_id, project_id, layers_json, updated_at) "
        "VALUES (?, ?, ?, datetime('now'))",
        (config_id, project_id, json.dumps(layers_json, ensure_ascii=False)),
    )
    return config_id
