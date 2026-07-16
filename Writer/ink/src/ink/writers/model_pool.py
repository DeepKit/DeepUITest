from __future__ import annotations

import json
import sqlite3
import hashlib

from ink.errors import ConfigError


def load_writer_model_pool(conn: sqlite3.Connection, project_id: int) -> tuple[str, ...]:
    row = conn.execute(
        "SELECT writer_model_pool FROM writing_projects WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    if row is None:
        raise ConfigError(f"project not found: {project_id}")
    value = json.loads(row[0])
    if not isinstance(value, list) or not value:
        raise ConfigError("writer_model_pool must be a non-empty JSON array")
    models = tuple(str(item) for item in value)
    if any(not model.strip() for model in models):
        raise ConfigError("writer_model_pool contains an empty model name")
    return models


def select_writer_models(pool: tuple[str, ...], count: int, shot_id: str = "") -> tuple[str, ...]:
    """按 shot_id 起点偏移轮选候选模型，破集中化导致的风格趋同。

    原实现固定从 pool[0] 开始取 count 个，多 shot 草稿时前段模型恒占候选位 →
    卷内同模型草稿过多，风格趋同（E11 诊断 writer 候选集中于 pool 前段）。
    改用 shot_id 哈希做起点偏移：同一 shot 跨次运行候选集一致（幂等），不同 shot
    分布到不同起点，使全卷各模型作为候选的频次均衡。

    shot_id 为空（兼容无 shot_id 调用）时回退原固定起点行为。
    """
    if count < 1:
        raise ConfigError("draft count must be positive")
    if not pool:
        raise ConfigError("writer_model_pool is empty")
    start = _stable_index(shot_id, len(pool)) if shot_id else 0
    return tuple(pool[(start + index) % len(pool)] for index in range(count))


def select_polish_model(pool: tuple[str, ...], shot_id: str, winner_model: str = "") -> str:
    """按 shot_id 稳定轮替选 polish 模型，破 smart-polish 集中化导致的风格趋同。

    polish 若固定单一模型（原硬编码 "smart-polish"），所有 shot 同一打磨配方 →
    卷内风格趋同（E10 诊断 6/10 章 polish 收束同构病根）。改用 writer_model_pool
    按 shot_id 哈希稳定轮替：同一 shot 跨次运行选同一模型（幂等），不同 shot 分布
    到不同模型；并尽量避开 winner_model（不自我打磨），避免赢家与打磨器同模型。

    pool 为空或单元素时回退 "smart-polish" 兼容旧基线。
    """
    if not pool:
        return "smart-polish"
    if len(pool) == 1:
        return pool[0] if pool[0] != winner_model else "smart-polish"
    # 稳定哈希：同一 shot_id 永远落到同一索引（幂等），跨 shot 均匀分布。
    idx = _stable_index(shot_id, len(pool))
    chosen = pool[idx]
    # 避开 winner_model：若命中赢家模型，取下一格。
    if chosen == winner_model and winner_model:
        chosen = pool[(idx + 1) % len(pool)]
    return chosen


def _stable_index(value: str, size: int) -> int:
    digest = hashlib.sha256(value.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") % size
