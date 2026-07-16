"""LLMGateway failover 编排单元测试（离线）。

验证按 call_type 的主/备/兜底 failover（BFX-035 修复点）:
- 主成功:不 failover,落一次 attempt,record success;
- 主失败备成功:切到备,主失败不落 attempt/不 record,tier 切换走 model_role_failover event,
  最终落一次 attempt 记命中的备 model + record success;
- 三 tier 全失败:只落一次 attempt(fail)+ record 一次 fail,抛「请检查供应商」错;
- tier 失败不污染 consecutive_count 熔断(不重复 record)。
- budget-blocked 不 failover(已是熔断态直接 raise)。
"""
from __future__ import annotations

import pytest

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.errors import LLMProviderError
from factories import make_schema_db, insert_minimal_draft, NOW
from ink.core.model_role_config import upsert_role_config


class _ControllableProvider:
    """按 model_name 决定成功/失败的 provider:在 fail_names 中的抛错。"""

    def __init__(self, *, fail_names: set[str] | None = None, label: str = "p") -> None:
        self.fail_names = fail_names or set()
        self.label = label
        self.calls: list[str] = []

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        self.calls.append(model_name)
        if model_name in self.fail_names:
            raise RuntimeError(f"{self.label}: simulated failure for {model_name}")
        return ModelResult(
            text=f"ok-{model_name}", model_name=model_name,
            token_input=5, token_output=8, finish_reason="stop",
        )


def _seed_three_tiers(conn, *, call_type="draft", api_key_env="MOCK_KEY"):
    """配主/备/兜底三档(同供应商 mock,不同模型名)。"""
    for tier, model in [("primary", "glm52"), ("secondary", "deepseek-v4"), ("tertiary", "qwen")]:
        upsert_role_config(
            conn, project_id=1, call_type=call_type, tier=tier,
            model_name=model, provider="mock", api_key_env=api_key_env,
        )


def _patch_providers(gateway, *, fail_names: set[str]):
    """把 _get_or_build_provider 替换为返回单一可控 provider(按 model_name 判成败)。"""
    prov = _ControllableProvider(fail_names=fail_names)
    gateway._get_or_build_provider = lambda cfg: prov  # type: ignore[method-assign]
    return prov


def test_failover_primary_succeeds_no_switch() -> None:
    """主成功:不 failover,落一次 attempt 记 primary model,record success。"""
    conn = make_schema_db()
    insert_minimal_draft(conn)
    _seed_three_tiers(conn)
    gateway = LLMGateway(conn)
    prov = _patch_providers(gateway, fail_names=set())

    result = gateway.call(
        project_id=1, shot_id="shot-001@20", run_id=20, call_type="draft",
        prompt_id=None, prompt_text="hi", model_name="ignored-in-failover",
        idempotency_key="idem-1",
    )
    assert result.text == "ok-glm52"
    assert prov.calls == ["glm52"]  # 只调了主
    # 落一次 attempt,记命中的 primary model
    row = conn.execute(
        "SELECT model_name, success FROM writing_ai_call_attempts WHERE call_type='draft'"
    ).fetchone()
    assert row[0] == "glm52"
    assert row[1] == 1
    # 无 failover event
    n_failover = conn.execute(
        "SELECT COUNT(*) FROM writing_runtime_events WHERE event_type='model_role_failover'"
    ).fetchone()[0]
    assert n_failover == 0


def test_failover_primary_fails_secondary_succeeds() -> None:
    """主失败→备成功:主不落 attempt,切备落 attempt 记 secondary,record 只记一次 success。"""
    conn = make_schema_db()
    insert_minimal_draft(conn)
    _seed_three_tiers(conn)
    gateway = LLMGateway(conn)
    prov = _patch_providers(gateway, fail_names={"glm52"})

    result = gateway.call(
        project_id=1, shot_id="shot-001@20", run_id=20, call_type="draft",
        prompt_id=None, prompt_text="hi", model_name="draft-model",
        idempotency_key="idem-2",
    )
    assert result.text == "ok-deepseek-v4"
    assert prov.calls == ["glm52", "deepseek-v4"]  # 主抛错,备成功
    # 只落一次 attempt(主失败不落),记命中的 secondary
    rows = conn.execute(
        "SELECT model_name, success FROM writing_ai_call_attempts WHERE call_type='draft'"
    ).fetchall()
    assert len(rows) == 1
    assert rows[0][0] == "deepseek-v4"
    assert rows[0][1] == 1
    # 有 failover event(主→备)
    failover = conn.execute(
        "SELECT event_payload FROM writing_runtime_events WHERE event_type='model_role_failover'"
    ).fetchall()
    assert len(failover) == 1
    assert "glm52" in failover[0][0]


def test_failover_all_tiers_fail_raises_and_records_once() -> None:
    """三 tier 全失败:只落一次 attempt(fail)+ record 一次,抛「请检查供应商」错。"""
    conn = make_schema_db()
    insert_minimal_draft(conn)
    _seed_three_tiers(conn)
    gateway = LLMGateway(conn)
    prov = _patch_providers(gateway, fail_names={"glm52", "deepseek-v4", "qwen"})

    with pytest.raises(LLMProviderError, match="请检查供应商"):
        gateway.call(
            project_id=1, shot_id="shot-001@20", run_id=20, call_type="draft",
            prompt_id=None, prompt_text="hi", model_name="draft-model",
            idempotency_key="idem-3",
        )
    assert len(prov.calls) == 3  # 三个 tier 都试了
    # 只落一次 attempt(fail)
    rows = conn.execute(
        "SELECT success, error_category FROM writing_ai_call_attempts WHERE call_type='draft'"
    ).fetchall()
    assert len(rows) == 1
    assert rows[0][0] == 0
    assert rows[0][1] == "RuntimeError"
    # 两个 failover event(主→备,备→兜底)
    n_failover = conn.execute(
        "SELECT COUNT(*) FROM writing_runtime_events WHERE event_type='model_role_failover'"
    ).fetchone()[0]
    assert n_failover == 2


def test_failover_tier_failure_does_not_pollute_circuit_breaker() -> None:
    """BFX-035:tier 失败不调 record_call,consecutive_count 不被三 tier 累加。

    验证:全失败后,该 shot 的 consecutive_count 只 +1(逻辑调用级),不是 +3。
    """
    conn = make_schema_db()
    insert_minimal_draft(conn)
    _seed_three_tiers(conn)
    gateway = LLMGateway(conn)
    _patch_providers(gateway, fail_names={"glm52", "deepseek-v4", "qwen"})

    with pytest.raises(LLMProviderError):
        gateway.call(
            project_id=1, shot_id="shot-001@20", run_id=20, call_type="draft",
            prompt_id=None, prompt_text="hi", model_name="draft-model",
            idempotency_key="idem-4",
        )
    row = conn.execute(
        """
        SELECT consecutive_count FROM writing_llm_failure_streaks
        WHERE shot_id='shot-001@20' AND call_type='draft' AND failure_type='LLMProviderError'
        """
    ).fetchone()
    # 只记一次(逻辑调用级),不是 3 次
    assert row is not None
    assert row[0] == 1


def test_failover_no_role_config_falls_back_to_injected_provider() -> None:
    """无 role_config 的 call_type 回退单 provider 老逻辑(注入式 provider 不破)。"""
    conn = make_schema_db()
    insert_minimal_draft(conn)
    # 不配 role_config,用注入式 provider
    gateway = LLMGateway(conn, provider=_ControllableProvider(fail_names=set(), label="inj"),
                         provider_name="test")

    result = gateway.call(
        project_id=1, shot_id="shot-001@20", run_id=20, call_type="jury",  # jury 无 role_config
        prompt_id=None, prompt_text="hi", model_name="judge-a",
        idempotency_key="idem-5",
    )
    assert result.text == "ok-judge-a"
