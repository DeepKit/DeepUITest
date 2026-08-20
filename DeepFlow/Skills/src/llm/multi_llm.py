"""
Multi-LLM Builder (T20)
=======================
通过 WiseGateway 8000 端口的 call_by_name 构建多家族 LLM 客户端池。
一家族一票原则：每个模型家族最多一个席位。

用法:
    from .multi_llm import build_llm_pool, call_by_name
    pool = build_llm_pool()          # 构建全池
    client = call_by_name("glm")     # 按名取单个客户端
"""

import os
import structlog
from typing import Dict, Optional
from .client import LLMClient, LLMConfig

logger = structlog.get_logger(__name__)

# ---------------------------------------------------------------------------
# WiseGateway 连接配置（环境变量可覆盖）
# ---------------------------------------------------------------------------
WISE_BASE_URL = os.getenv("WISE_BASE_URL", "http://127.0.0.1:8000/v1")
WISE_API_KEY = os.getenv("WISE_API_KEY", "fuyi-kiro-17781158558")

# ---------------------------------------------------------------------------
# 模型家族映射（短名 → WiseGateway model id）
# 一家族一票，覆盖 multi-llm-deliberation 规范中的 8 大家族
# ---------------------------------------------------------------------------
MODEL_FAMILIES: Dict[str, str] = {
    # GPT 家族（Sol/Luna/Terra 同族，取 Sol）
    "gpt":      "claude-fccy-gpt-5-6",
    # GLM 家族
    "glm":      "claude-qoder-glm-5-2",
    # DeepSeek 家族
    "deepseek": "claude-kevin-deepseek-v4-pro",
    # Kimi 家族
    "kimi":     "claude-cloudflare-kimi-k2-6",
    # Qwen 家族
    "qwen":     "claude-opencodego-qwen3-7-max",
    # MiniMax 家族
    "minimax":  "claude-duojie-minimax-m3",
    # StepFun 家族（路由模式，预期解析到 DeepSeek V4 Pro）
    "stepfun":  "claude-stepfun-step-router-v1",
    # Spark 家族（讯飞）
    "spark":    "claude-nim-glm-5-2",  # 暂用 GLM 替代，待 Spark 路由确认
}

# 完整别名映射（支持 skill 中使用的完整名称）
ALIASES: Dict[str, str] = {
    "claude-fccy-gpt-5-6-sol":    "gpt",
    "claude-xunfei-glm-5-2":      "glm",
    "claude-stepfun-step-router-v1": "stepfun",
    "claude-xunfei-kimi-k2-6":    "kimi",
    "claude-xunfei-qwen3-5-397b-a17b": "qwen",
    "claude-xunfei-minimax-m2-5": "minimax",
    "claude-xunfei-spark-x2":     "spark",
    "claude-qoder-glm-5-2":       "glm",
    "claude-kevin-deepseek-v4-pro": "deepseek",
    "claude-cloudflare-kimi-k2-6": "kimi",
    "claude-opencodego-qwen3-7-max": "qwen",
    "claude-duojie-minimax-m3":   "minimax",
}

# 已构建的客户端缓存（避免重复创建）
_client_cache: Dict[str, LLMClient] = {}


def _make_config(model_id: str) -> LLMConfig:
    """为指定 model_id 创建 LLMConfig。"""
    return LLMConfig(
        api_key=WISE_API_KEY,
        default_model=model_id,
        base_url=WISE_BASE_URL,
        timeout=120.0,
        max_retries=2,
    )


def call_by_name(name: str) -> LLMClient:
    """
    按名称构建/获取 LLM 客户端。

    支持三种名称格式：
    1. 家族短名: "gpt", "glm", "deepseek", "kimi", "qwen", "minimax", "stepfun", "spark"
    2. 完整别名: "claude-fccy-gpt-5-6-sol", "claude-xunfei-glm-5-2", ...
    3. WiseGateway model id: "claude-qoder-glm-5-2", ...

    Returns:
        LLMClient 实例（带缓存）

    Raises:
        KeyError: 名称无法映射到任何已知模型
    """
    # 1. 尝试家族短名
    if name in MODEL_FAMILIES:
        model_id = MODEL_FAMILIES[name]
    # 2. 尝试完整别名
    elif name in ALIASES:
        family = ALIASES[name]
        model_id = MODEL_FAMILIES.get(family, name)
    # 3. 直接当作 WiseGateway model id
    else:
        model_id = name

    if model_id in _client_cache:
        return _client_cache[model_id]

    logger.info("call_by_name.creating_client", name=name, model_id=model_id)
    client = LLMClient(_make_config(model_id))
    _client_cache[model_id] = client
    return client


def build_llm_pool(families: Optional[list] = None) -> Dict[str, LLMClient]:
    """
    构建多家族 LLM 客户端池。

    Args:
        families: 指定家族列表（默认全部 8 家族）

    Returns:
        {家族短名: LLMClient} 字典
    """
    target = families or list(MODEL_FAMILIES.keys())
    pool = {}
    for fam in target:
        try:
            pool[fam] = call_by_name(fam)
        except Exception as e:
            logger.warning("build_llm_pool.skip_family", family=fam, error=str(e))
    logger.info("build_llm_pool.done", families=list(pool.keys()), count=len(pool))
    return pool


def list_families() -> Dict[str, str]:
    """返回当前可用的家族 → model_id 映射。"""
    return dict(MODEL_FAMILIES)


async def close_all() -> None:
    """关闭所有缓存的客户端。"""
    for client in _client_cache.values():
        await client.close()
    _client_cache.clear()
    logger.info("multi_llm.all_clients_closed")
