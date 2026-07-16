"""LLMGateway 模型别名路由单元测试(离线,不依赖真实网关)。

验证生产别名机制(如 smart-polish → 真实模型):
- 构造时注入 model_aliases 与从 DB 懒加载两条路径都工作;
- provider 收到翻译后的真实模型名,但 DB 记录与返回的 ModelResult.model_name 保持原别名
  (满足 SoftSealOrchestrator 校验 winner.writer_model == "smart-polish" 的生产契约);
- 无别名命中时原样透传;
- finish_reason 在 ModelResult 还原后仍正确(顺便防回归:测试侧旧 _RemappingProvider 漏过该字段)。
"""
from __future__ import annotations

import pytest

from ink.core.llm_gateway import LLMGateway, ModelResult
from factories import NOW, make_schema_db


class _RecordingProvider:
    """记录 provider 收到的 model_name,返回可断言的 ModelResult。"""

    def __init__(self) -> None:
        self.seen: list[str] = []
        self._n = 0

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        self.seen.append(model_name)
        return ModelResult(
            text=f"output-for-{model_name}",
            model_name=model_name,
            token_input=10,
            token_output=20,
            finish_reason="stop",
        )


def _next_idem(label: str) -> str:
    """每次生成唯一 idempotency_key(避免 UNIQUE 约束)。"""
    _next_idem._n += 1  # type: ignore[attr-defined]
    return f"idem-{label}-{_next_idem._n}"  # type: ignore[attr-defined]


_next_idem._n = 0  # type: ignore[attr-defined]


# ModelProvider 是 Protocol,_RecordingProvider 鸭子满足,运行时无需显式声明。


def _seed_project(conn, *, model_aliases=None) -> int:
    """插入一个 writing_projects 行,返回 project_id。"""
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, model_aliases, created_at)
        VALUES (1, 'alias-demo', 'Alias Demo', '["w-a","w-b","w-c"]', '["j-a","j-b","j-c"]', ?, ?)
        """,
        (model_aliases, NOW),
    )
    conn.execute(
        "INSERT INTO writing_sessions (session_id, project_id, started_at) VALUES (10, 1, ?)",
        (NOW,),
    )
    conn.execute(
        "INSERT INTO writing_runs (run_id, project_id, session_id, run_attempt, started_at, status) "
        "VALUES (20, 1, 10, 1, ?, 'running')",
        (NOW,),
    )
    return 1


def _shot_id(conn) -> str:
    """插入最小 shot 契约 + shot,返回 shot_id。"""
    conn.execute(
        """
        INSERT INTO writing_shot_contracts
            (project_id, chapter_id, run_id, logical_shot_id, status, created_at, updated_at)
        VALUES (1, 1, 20, 'ch-01-shot-001', 'confirmed', ?, ?)
        """,
        (NOW, NOW),
    )
    conn.execute(
        """
        INSERT INTO writing_shots
            (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id,
             status, created_at, updated_at)
        VALUES ('ch-01-shot-001@20', 1, 1, 1, 20, 'ch-01-shot-001', 'pending', ?, ?)
        """,
        (NOW, NOW),
    )
    return "ch-01-shot-001@20"


def _invoke(gateway: LLMGateway, *, model_name: str, call_type: str = "polish") -> ModelResult:
    """封装 gateway.call 的固定参数,聚焦别名路由断言。"""
    return gateway.call(
        project_id=1,
        shot_id="ch-01-shot-001@20",
        run_id=20,
        call_type=call_type,
        prompt_id=None,
        prompt_text="t",
        model_name=model_name,
        idempotency_key=_next_idem(model_name),
    )


def test_alias_translated_to_real_model_and_restored_on_result() -> None:
    """别名经 gateway 翻译调 provider,返回结果还原成别名。"""
    conn = make_schema_db()
    _seed_project(conn, model_aliases='{"smart-polish":"xopglm51"}')
    _shot_id(conn)
    provider = _RecordingProvider()
    gateway = LLMGateway(conn, provider=provider, provider_name="test")

    result = _invoke(gateway, model_name="smart-polish")

    # provider 收到翻译后的真实模型名
    assert provider.seen == ["xopglm51"]
    # 返回的 ModelResult.model_name 还原成原别名(生产契约)
    assert result.model_name == "smart-polish"
    assert result.finish_reason == "stop"


def test_alias_loaded_from_db_on_first_call_then_cached() -> None:
    """未注入 model_aliases 时,gateway 从 writing_projects.model_aliases 懒加载并缓存。"""
    conn = make_schema_db()
    _seed_project(conn, model_aliases='{"smart-polish":"xopglm51"}')
    _shot_id(conn)
    provider = _RecordingProvider()
    gateway = LLMGateway(conn, provider=provider, provider_name="test")

    # 第一次 call:触发 DB 懒加载
    _invoke(gateway, model_name="smart-polish")
    assert provider.seen == ["xopglm51"]

    # 改 DB 中的别名映射,证明缓存生效(不重新读 DB)
    conn.execute(
        "UPDATE writing_projects SET model_aliases='{\"smart-polish\":\"xopglm52\"}' WHERE project_id=1"
    )
    _invoke(gateway, model_name="smart-polish")
    assert provider.seen == ["xopglm51", "xopglm51"]  # 仍用缓存里的 xopglm51


def test_injected_aliases_override_db() -> None:
    """构造时注入的 model_aliases 优先于 DB(不查 DB)。"""
    conn = make_schema_db()
    _seed_project(conn, model_aliases='{"smart-polish":"xopglm51"}')
    _shot_id(conn)
    provider = _RecordingProvider()
    gateway = LLMGateway(
        conn, provider=provider, provider_name="test",
        model_aliases={"smart-polish": "xopdeepseekv4pro"},
    )

    _invoke(gateway, model_name="smart-polish")
    assert provider.seen == ["xopdeepseekv4pro"]


def test_unmapped_model_name_passes_through() -> None:
    """无别名命中的模型名原样透传给 provider。"""
    conn = make_schema_db()
    _seed_project(conn, model_aliases='{"smart-polish":"xopglm51"}')
    _shot_id(conn)
    provider = _RecordingProvider()
    gateway = LLMGateway(conn, provider=provider, provider_name="test")

    _invoke(gateway, model_name="writer-a", call_type="draft")
    assert provider.seen == ["writer-a"]


def test_db_null_aliases_passes_through() -> None:
    """DB model_aliases 为 NULL 时,所有模型名透传。"""
    conn = make_schema_db()
    _seed_project(conn, model_aliases=None)
    _shot_id(conn)
    provider = _RecordingProvider()
    gateway = LLMGateway(conn, provider=provider, provider_name="test")

    _invoke(gateway, model_name="smart-polish")
    assert provider.seen == ["smart-polish"]


def test_non_string_alias_values_coerced_to_str() -> None:
    """DB model_aliases 是合法 JSON object 但值为非字符串(如 int)时,gateway 容错转为字符串别名。

    schema CHECK 只要求 json_type='object',不约束值的类型,故这种数据能入库;
    gateway 的 _load_project_aliases 用 str(v) 做防御性转换,避免 123 这样的值原样传给 provider。
    """
    conn = make_schema_db()
    _seed_project(conn, model_aliases='{"smart-polish": 123}')
    _shot_id(conn)
    provider = _RecordingProvider()
    gateway = LLMGateway(conn, provider=provider, provider_name="test")

    _invoke(gateway, model_name="smart-polish")
    # 非字符串值被转成 "123" 作为真实模型名(防御性,不至于崩)
    assert provider.seen == ["123"]


def test_db_records_alias_not_real_model() -> None:
    """writing_ai_call_attempts.model_name 记录的是原别名,便于审计追踪。"""
    conn = make_schema_db()
    _seed_project(conn, model_aliases='{"smart-polish":"xopglm51"}')
    _shot_id(conn)
    gateway = LLMGateway(conn, provider=_RecordingProvider(), provider_name="test")

    _invoke(gateway, model_name="smart-polish")

    row = conn.execute(
        "SELECT model_name FROM writing_ai_call_attempts WHERE shot_id = ?",
        ("ch-01-shot-001@20",),
    ).fetchone()
    assert row is not None
    assert row[0] == "smart-polish"
