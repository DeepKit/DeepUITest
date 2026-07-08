"""按 call_type 的模型角色主/备/兜底配置。

每个 call_type（outline/draft/jury/polish/chapter_review/book_check/...）在
``writing_model_role_configs`` 表里存三行（primary/secondary/tertiary），尽量跨供应商。
``LLMGateway.call`` 按 (project_id, call_type) 取主备兜底，失败逐 tier 切，三都失败才判
该次逻辑调用失败并提示调供应商/api-key。

api_key 不落明文，只存环境变量名（``api_key_env``），运行时从 ``os.environ`` 取。
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass

from ink.errors import ConfigError
from ink.time import now_utc_iso

# tier 的尝试顺序：主 → 备 → 兜底。
TIER_ORDER: tuple[str, ...] = ("primary", "secondary", "tertiary")


@dataclass(frozen=True)
class ModelRoleConfig:
    """单个 tier 的模型角色配置。"""

    project_id: int
    call_type: str
    tier: str
    model_name: str
    provider: str
    base_url: str | None
    api_key_env: str
    max_tokens: int | None


def _row_to_config(row: sqlite3.Row | tuple) -> ModelRoleConfig:
    """SELECT 列序固定为：project_id, call_type, tier, model_name, provider, base_url, api_key_env, max_tokens。

    用索引取而非 row["name"]，不依赖 conn.row_factory=Row（兼容生产 Row 与测试裸 tuple）。
    """
    return ModelRoleConfig(
        project_id=int(row[0]),
        call_type=str(row[1]),
        tier=str(row[2]),
        model_name=str(row[3]),
        provider=str(row[4]),
        base_url=row[5],
        api_key_env=str(row[6]),
        max_tokens=row[7],
    )


def load_role_chain(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    call_type: str,
) -> list[ModelRoleConfig]:
    """按 tier 顺序返回某 call_type 的主/备/兜底配置链。

    返回 1-3 个配置，顺序为 primary → secondary → tertiary。缺档时**滚动补位**：
    secondary 缺则用 primary 顶替，tertiary 缺则用其前一个有效 tier 顶替——保证链非空，
    向后兼容「只配了 primary 单档」的旧项目（旧项目 init 未写 role_configs）。

    若该 call_type 在该项目下完全无配置，抛 ``ConfigError``，提示用 CLI 补齐。
    gateway 调用方据此决定是否 failover（链长 >1 才有切换意义）。
    """
    rows = conn.execute(
        """
        SELECT project_id, call_type, tier, model_name, provider, base_url, api_key_env, max_tokens
        FROM writing_model_role_configs
        WHERE project_id = ? AND call_type = ?
        ORDER BY CASE tier
            WHEN 'primary' THEN 0
            WHEN 'secondary' THEN 1
            WHEN 'tertiary' THEN 2
            ELSE 3
        END
        """,
        (project_id, call_type),
    ).fetchall()
    if not rows:
        raise ConfigError(
            f"call_type={call_type} 在 project_id={project_id} 下无模型角色配置；"
            f"请用 'ink role-config set' 或 init --role-config 补齐主/备/兜底三档"
        )
    chain: list[ModelRoleConfig] = [_row_to_config(r) for r in rows]
    # 滚动补位：保证三档都有值（缺档用前一有效档顶替），tier 字段反映链中位置而非原始档。
    # 例：只有 primary → 链 [primary, secondary(=primary 配置), tertiary(=primary 配置)]，
    # model/provider 可能重复，但 gateway 拿到的总是三 tier，可按顺序逐个试。
    from dataclasses import replace as _replace

    while len(chain) < len(TIER_ORDER):
        prev = chain[-1]
        chain.append(_replace(prev, tier=TIER_ORDER[len(chain)]))
    return chain[: len(TIER_ORDER)]


def upsert_role_config(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    call_type: str,
    tier: str,
    model_name: str,
    provider: str,
    api_key_env: str,
    base_url: str | None = None,
    max_tokens: int | None = None,
) -> int:
    """插入或更新单条 role config（按 (project_id, call_type, tier) UPSERT）。"""
    if tier not in TIER_ORDER:
        raise ConfigError(f"tier 必须是 {TIER_ORDER} 之一，得到 {tier!r}")
    if not model_name or not provider or not api_key_env:
        raise ConfigError("model_name / provider / api_key_env 均不可为空")
    now = now_utc_iso()
    conn.execute(
        """
        INSERT INTO writing_model_role_configs
            (project_id, call_type, tier, model_name, provider, base_url, api_key_env, max_tokens,
             created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (project_id, call_type, tier) DO UPDATE SET
            model_name = excluded.model_name,
            provider = excluded.provider,
            base_url = excluded.base_url,
            api_key_env = excluded.api_key_env,
            max_tokens = excluded.max_tokens,
            updated_at = excluded.updated_at
        """,
        (project_id, call_type, tier, model_name, provider, base_url, api_key_env, max_tokens, now, now),
    )
    row = conn.execute(
        "SELECT role_config_id FROM writing_model_role_configs WHERE project_id=? AND call_type=? AND tier=?",
        (project_id, call_type, tier),
    ).fetchone()
    return int(row[0])  # role_config_id（不依赖 row_factory=Row）


def list_role_configs(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    call_type: str | None = None,
) -> list[ModelRoleConfig]:
    """列出某项目（可限定 call_type）下的全部 role config。"""
    if call_type is None:
        rows = conn.execute(
            """
            SELECT project_id, call_type, tier, model_name, provider, base_url, api_key_env, max_tokens
            FROM writing_model_role_configs
            WHERE project_id = ?
            ORDER BY call_type, CASE tier WHEN 'primary' THEN 0 WHEN 'secondary' THEN 1 WHEN 'tertiary' THEN 2 ELSE 3 END
            """,
            (project_id,),
        ).fetchall()
    else:
        rows = conn.execute(
            """
            SELECT project_id, call_type, tier, model_name, provider, base_url, api_key_env, max_tokens
            FROM writing_model_role_configs
            WHERE project_id = ? AND call_type = ?
            ORDER BY CASE tier WHEN 'primary' THEN 0 WHEN 'secondary' THEN 1 WHEN 'tertiary' THEN 2 ELSE 3 END
            """,
            (project_id, call_type),
        ).fetchall()
    return [_row_to_config(r) for r in rows]


def validate_role_chain(chain: list[ModelRoleConfig]) -> list[str]:
    """校验一条 role chain 的配置完整性，返回错误信息列表（空表示通过）。

    检查：
    1. 链长度为 3（load_role_chain 已补位，此处复核）。
    2. api_key_env 对应的环境变量在 os.environ 中存在（不取值，只验存在性）。
    3. provider='openai-compatible' 时 base_url 非空。
    """
    import os

    errors: list[str] = []
    if len(chain) != len(TIER_ORDER):
        errors.append(f"role chain 长度应为 {len(TIER_ORDER)}，得到 {len(chain)}")
    seen_envs: set[str] = set()
    for cfg in chain:
        if cfg.api_key_env not in seen_envs:
            if cfg.api_key_env not in os.environ:
                errors.append(
                    f"tier={cfg.tier} api_key_env={cfg.api_key_env} 未在环境变量中设置"
                )
            seen_envs.add(cfg.api_key_env)
        if cfg.provider == "openai-compatible" and not cfg.base_url:
            errors.append(
                f"tier={cfg.tier} provider=openai-compatible 但 base_url 为空"
            )
    return errors
