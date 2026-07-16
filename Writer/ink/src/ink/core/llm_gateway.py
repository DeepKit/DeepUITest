from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import time
import urllib.error
import urllib.request
from collections.abc import Callable, Mapping
from dataclasses import dataclass, replace
from typing import Protocol

from ink.core.retry_budget import LLMCallBudget
from ink.errors import ConfigError, LLMProviderError
from ink.time import now_utc_iso

# 按 call_type 的主/备/兜底模型角色配置；lazy import 避免循环依赖（model_role_config 不依赖 gateway）。
def _load_role_chain(conn, *, project_id, call_type):
    from ink.core.model_role_config import load_role_chain as _load

    return _load(conn, project_id=project_id, call_type=call_type)


def _reorder_chain_from_tier(chain, tier_hint: str):
    """按 tier_hint 起算 wrap 重排 failover 链。

    chain 是 [primary, secondary, tertiary] 顺序（load_role_chain 已补位保证三档）。
    tier_hint=secondary → [secondary, tertiary, primary]：从 secondary 起调，失败切 tertiary，
    再切 primary。jury 3 裁判各传 primary/secondary/tertiary 实现投票多样性 + 单 judge 容灾。
    tier_hint 不在 TIER_ORDER 时原序返回（保守）。
    """
    from ink.core.model_role_config import TIER_ORDER

    idx = {cfg.tier: i for i, cfg in enumerate(chain) if cfg.tier in TIER_ORDER}
    if tier_hint not in idx:
        return chain
    start = idx[tier_hint]
    # 按 TIER_ORDER 全集 wrap：从 start 起，循环到 start-1
    order = [TIER_ORDER[(start + i) % len(TIER_ORDER)] for i in range(len(TIER_ORDER))]
    by_tier = {cfg.tier: cfg for cfg in chain}
    reordered = [by_tier[t] for t in order if t in by_tier]
    return reordered or chain


@dataclass(frozen=True)
class ModelResult:
    text: str
    model_name: str
    token_input: int = 0
    token_output: int = 0
    finish_reason: str = "stop"


class ModelProvider(Protocol):
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        ...


@dataclass(frozen=True)
class LLMProviderConfig:
    provider: str
    base_url: str | None = None
    api_key: str | None = None
    timeout_seconds: float = 60.0
    max_tokens: int | None = None
    max_retries: int = 0


class MockProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        if idempotency_key.startswith("jury:"):
            # jury 真实化后 _score_draft 解析 12 维 JSON。polished draft 文本含 "polished text"，
            # 给更高分确保第二轮 jury 重评时 winner 仍是 polished draft（soft seal 契约要求
            # winner.writer_model == "smart-polish"）。未 polish draft 给 84（过 quality_floor 但低于 polished）。
            from ink.jury.scores import SCORE_COLUMNS

            score = 90 if "polished text" in prompt_text else 84
            text = json.dumps({col: score for col in SCORE_COLUMNS}, ensure_ascii=False)
        elif idempotency_key.startswith("chapter_review:"):
            # chapter_review 真实化后解析 7 维 JSON + review_notes。默认全过（92）。
            from ink.pipeline.chapter_review_orchestrator import CHAPTER_REVIEW_DIMENSIONS

            text = json.dumps(
                {col: 92 for col in CHAPTER_REVIEW_DIMENSIONS} | {"review_notes": "mock pass"},
                ensure_ascii=False,
            )
        elif idempotency_key.startswith("book_check:"):
            # book_check 真实化后解析 6 维 JSON + issues。默认全过 + 空 issues。
            from ink.pipeline.book_rolling_check_orchestrator import BOOK_CHECK_DIMENSIONS

            text = json.dumps(
                {col: 92 for col in BOOK_CHECK_DIMENSIONS} | {"issues": []}, ensure_ascii=False
            )
        elif idempotency_key.startswith("outline:") and "Contract source: " in prompt_text:
            source = prompt_text.split("Contract source: ", 1)[1].splitlines()[0]
            text = f"{source} outline"
        elif idempotency_key.startswith("polish:"):
            text = "polished text"
        else:
            # Keep offline orchestration tests readable.  Mock provenance remains
            # explicit in writing_ai_call_attempts.model_provider and must never be
            # accepted as real-model quality evidence.
            text = f"scene text {model_name} {idempotency_key}"
        return ModelResult(
            text=text,
            model_name=model_name,
            token_input=len(prompt_text.split()),
            token_output=1,
        )


# 推理模型：响应含 reasoning_content，token 预算要先满足思维链再产出 content。
# 命名空间内的推理模型子串匹配（如 "xsparkx2"、"xminimaxm25"）。
_REASONING_MODEL_HINTS: tuple[str, ...] = ("sparkx2", "minimaxm")
_REASONING_DEFAULT_MAX_TOKENS: int = 2000


def _is_reasoning_model(model_name: str) -> bool:
    lowered = model_name.lower()
    return any(hint in lowered for hint in _REASONING_MODEL_HINTS)


class OpenAICompatibleProvider:
    def __init__(
        self,
        *,
        base_url: str,
        api_key: str,
        timeout_seconds: float = 60.0,
        opener: Callable[..., object] | None = None,
        max_tokens: int | None = None,
        max_retries: int = 0,
        retry_base_delay: float = 1.0,
    ) -> None:
        if not base_url.strip():
            raise ConfigError("LLM provider base_url must be non-empty")
        if not api_key.strip():
            raise ConfigError("LLM provider api_key must be non-empty")
        if timeout_seconds <= 0:
            raise ConfigError("LLM provider timeout_seconds must be positive")
        if max_tokens is not None and max_tokens <= 0:
            raise ConfigError("LLM provider max_tokens must be positive")
        if max_retries < 0:
            raise ConfigError("LLM provider max_retries must be non-negative")
        self.endpoint = f"{base_url.rstrip('/')}/chat/completions"
        self.api_key = api_key
        self.timeout_seconds = timeout_seconds
        self.max_tokens = max_tokens
        self.max_retries = max_retries
        self.retry_base_delay = retry_base_delay
        self._opener = opener or urllib.request.urlopen

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        payload: dict[str, object] = {
            "model": model_name,
            "messages": [{"role": "user", "content": prompt_text}],
        }
        # 推理模型必须显式给足 max_tokens，否则 token 全花在 reasoning_content 上，
        # content 字段为空。显式 max_tokens 优先；否则推理模型注入默认值。
        effective_max_tokens = self.max_tokens
        if effective_max_tokens is None and _is_reasoning_model(model_name):
            effective_max_tokens = _REASONING_DEFAULT_MAX_TOKENS
        if effective_max_tokens is not None:
            payload["max_tokens"] = effective_max_tokens
        body_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        # 退避重试：仅对瞬时错误(429 限流 / 5xx 服务端繁忙 / 超时)重试。
        # Idempotency-Key 保证重试安全(服务端去重)，故同 key 重发不会产生重复副作用。
        # 认证/参数类错误(401/400/402/404)立即抛，不重试。
        max_attempts = self.max_retries + 1
        # 用 idempotency_key 哈希做确定性抖动种子，避免所有请求同时重试加剧限流(不引入 random)。
        jitter_seed = int(hashlib.sha256(idempotency_key.encode("utf-8")).hexdigest(), 16) % 1000 / 1000.0
        last_exc: Exception | None = None
        for attempt in range(max_attempts):
            request = urllib.request.Request(
                self.endpoint,
                data=body_bytes,
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                    "Idempotency-Key": idempotency_key,
                    # urllib 默认 UA 是 "Python-urllib/x.x"，被 Cloudflare 当机器人拦(403 code 1010)。
                    # 给一个普通浏览器/SDK UA 绕过 WAF 机器人规则。
                    "User-Agent": "ink-writer/1.1 (OpenAI-compatible client)",
                },
                method="POST",
            )
            try:
                with self._opener(request, timeout=self.timeout_seconds) as response:
                    response_payload = json.loads(response.read().decode("utf-8"))
                return _parse_chat_completion_response(response_payload, fallback_model=model_name)
            except urllib.error.HTTPError as exc:
                body = exc.read().decode("utf-8", errors="replace")
                last_exc = LLMProviderError(f"provider HTTP {exc.code}: {body[:200]}")
                if exc.code in (429, 500, 502, 503, 504) and attempt < self.max_retries:
                    self._backoff_sleep(attempt, jitter_seed)
                    continue
                raise last_exc from exc
            except urllib.error.URLError as exc:
                last_exc = LLMProviderError(f"provider request failed: {exc.reason}")
                # 超时/连接错误视为瞬时，可重试
                if attempt < self.max_retries:
                    self._backoff_sleep(attempt, jitter_seed)
                    continue
                raise last_exc from exc
            except json.JSONDecodeError as exc:
                last_exc = LLMProviderError("provider returned invalid JSON")
                if attempt < self.max_retries:
                    self._backoff_sleep(attempt, jitter_seed)
                    continue
                raise last_exc from exc
        assert last_exc is not None  # 循环走完必有过异常(成功已在循环内 return)
        raise last_exc

    def _backoff_sleep(self, attempt: int, jitter_seed: float) -> None:
        """指数退避 + 确定性抖动：base * 2^attempt * (1 + jitter)。"""
        delay = self.retry_base_delay * (2 ** attempt) * (1.0 + jitter_seed)
        time.sleep(delay)


class LLMGateway:
    def __init__(
        self,
        conn: sqlite3.Connection,
        provider: ModelProvider | None = None,
        *,
        provider_name: str | None = None,
        model_aliases: Mapping[str, str] | None = None,
    ) -> None:
        self.conn = conn
        self.provider = provider or MockProvider()
        self.provider_name = provider_name or ("mock" if provider is None else provider.__class__.__name__)
        # 模型别名路由：把生产别名（如 "smart-polish"）翻译成真实模型名调 provider，
        # 但 DB 记录与返回的 ModelResult.model_name 保持原别名（SoftSealOrchestrator 校验契约）。
        # 构造时可注入；未注入时 call 内按 project_id 从 writing_projects.model_aliases 懒加载。
        self._model_aliases: dict[str, str] | None = dict(model_aliases) if model_aliases else None
        self._aliases_cache: dict[int, dict[str, str]] = {}
        # 按 (provider, base_url, api_key_env) 缓存 ModelProvider 实例，避免每 tier 重复构造。
        # key 用 api_key_env 而非明文 key（不落明文 key 到内存 dict 的 key 里）。
        self._provider_cache: dict[tuple[str, str | None, str], ModelProvider] = {}

    def call(
        self,
        *,
        project_id: int,
        shot_id: str | None,
        run_id: int | None,
        call_type: str,
        prompt_id: int | None,
        prompt_text: str,
        model_name: str,
        idempotency_key: str,
        model_provider: str | None = None,
        tier_hint: str | None = None,
    ) -> ModelResult:
        """调一次 LLM。配了 role_config 的 call_type 走主→备→兜底 failover（跨供应商容灾）；
        未配走注入式单 provider 老逻辑（测试 / 旧项目）。

        ``tier_hint``（'primary'/'secondary'/'tertiary'）仅在有 role_config 时生效：指定
        failover 的起调 tier，链按该 tier 起算 wrap 排列（例 hint=secondary → secondary,tertiary,primary）。
        jury 3 裁判各传不同 tier_hint 实现投票多样性（3 个不同模型各评一次）+ 单 judge 失败切下一 tier 容灾。
        """
        budget = LLMCallBudget(self.conn, project_id) if shot_id is not None and run_id is not None else None
        if budget is not None:
            allowed, reason = budget.check_circuit(shot_id, run_id)
            if not allowed:
                self._write_event(project_id, shot_id, run_id, "LLM_BUDGET_BLOCKED", {"reason": reason})
                raise LLMProviderError(f"LLM budget blocked: {reason}")

        # 分派：配了 role_configs 的 call_type 走 failover（主→备→兜底，跨供应商）；
        # 未配（注入式 provider 的测试 / 旧项目）走单 provider 老逻辑。
        try:
            chain = _load_role_chain(self.conn, project_id=project_id, call_type=call_type)
        except ConfigError:
            chain = []
        if chain:
            ordered = _reorder_chain_from_tier(chain, tier_hint) if tier_hint else chain
            return self._call_with_role_chain(
                chain=ordered,
                budget=budget,
                project_id=project_id,
                shot_id=shot_id,
                run_id=run_id,
                call_type=call_type,
                prompt_id=prompt_id,
                prompt_text=prompt_text,
                idempotency_key=idempotency_key,
                original_model_name=model_name,
            )
        return self._call_with_injected_provider(
            budget=budget,
            project_id=project_id,
            shot_id=shot_id,
            run_id=run_id,
            call_type=call_type,
            prompt_id=prompt_id,
            prompt_text=prompt_text,
            model_name=model_name,
            model_provider=model_provider,
            idempotency_key=idempotency_key,
        )

    def _call_with_injected_provider(
        self,
        *,
        budget: LLMCallBudget | None,
        project_id: int,
        shot_id: str | None,
        run_id: int | None,
        call_type: str,
        prompt_id: int | None,
        prompt_text: str,
        model_name: str,
        model_provider: str | None,
        idempotency_key: str,
    ) -> ModelResult:
        """单 provider 老逻辑：无 role_config 时回退。落一次 attempt + 一次 record_call。"""
        now = now_utc_iso()
        prompt_hash = _sha256(prompt_text)
        # call_type 未配 role_config（测试注入式 provider / chapter_review·book_check 无 role chain）
        # 时 model_name 可能为 None；DB model_name NOT NULL，回退 provider_name 保证审计可写。
        effective_model_name = model_name or self.provider_name
        cursor = self.conn.execute(
            """
            INSERT INTO writing_ai_call_attempts
                (project_id, shot_id, run_id, call_type, model_provider, model_name, idempotency_key,
                 prompt_id, prompt_hash, success, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
            """,
            (
                project_id,
                shot_id,
                run_id,
                call_type,
                model_provider or self.provider_name,
                effective_model_name,
                idempotency_key,
                prompt_id,
                prompt_hash,
                now,
            ),
        )
        attempt_id = int(cursor.lastrowid)

        started = time.perf_counter()
        # 别名路由：把 model_name（可能是生产别名如 "smart-polish"）翻译成真实模型名调 provider。
        # DB 记录的 model_name（上方 INSERT）保持原别名，便于审计追踪；返回的 ModelResult 也还原成别名，
        # 以满足 SoftSealOrchestrator 校验 winner.writer_model == "smart-polish" 的生产契约。
        real_name = self._resolve_model_alias(project_id, effective_model_name)
        try:
            result = self.provider.complete(prompt_text, real_name, idempotency_key)
        except Exception as exc:
            self.conn.execute(
                """
                UPDATE writing_ai_call_attempts
                SET success = 0, error_category = ?, latency_ms = ?
                WHERE attempt_id = ?
                """,
                (type(exc).__name__, _elapsed_ms(started), attempt_id),
            )
            if budget is not None:
                budget.record_call(shot_id, call_type, success=False, failure_type=type(exc).__name__)
            self._write_event(project_id, shot_id, run_id, "LLM_CALL_FAILED", {"attempt_id": attempt_id})
            raise LLMProviderError(str(exc)) from exc

        # 还原别名：provider 返回的 model_name 可能是 real_name，统一改回原始 model_name 保持契约。
        if real_name != model_name:
            result = replace(result, model_name=model_name)

        response_hash = _sha256(result.text)
        if budget is not None:
            budget.record_call(shot_id, call_type, success=True)
            budget.check_circuit(shot_id, run_id)
        self.conn.execute(
            """
            UPDATE writing_ai_call_attempts
            SET success = 1, response_hash = ?, token_input = ?, token_output = ?, latency_ms = ?, finish_reason = ?
            WHERE attempt_id = ?
            """,
            (response_hash, result.token_input, result.token_output, _elapsed_ms(started), result.finish_reason, attempt_id),
        )
        self._write_event(project_id, shot_id, run_id, "LLM_CALL_SUCCEEDED", {"attempt_id": attempt_id})
        return result

    def _call_with_role_chain(
        self,
        *,
        chain: list,  # list[ModelRoleConfig]
        budget: LLMCallBudget | None,
        project_id: int,
        shot_id: str | None,
        run_id: int | None,
        call_type: str,
        prompt_id: int | None,
        prompt_text: str,
        idempotency_key: str,
        original_model_name: str,
    ) -> ModelResult:
        """failover 编排：按 role chain 逐 tier 试，主→备→兜底。

        关键（BFX-035）：tier 失败**不调 record_call、不落 attempt**——避免污染 consecutive_count
        熔断（retry_budget 按 shot_id 聚合，三 tier 同 LLMProviderError 会累加同一行致误熔断）。
        只在逻辑调用整体成功（落 attempt + record success）/ 整体失败（落 attempt + record fail）
        后调一次。tier 切换走 model_role_failover event，writing_ai_call_attempts 不加 tier 列
        （避免迁移 + 破 SoftSeal 契约）。
        """
        from ink.core.model_role_config import ModelRoleConfig

        tried: list[dict] = []
        last_exc: Exception | None = None
        for idx, cfg in enumerate(chain):  # ModelRoleConfig
            provider = self._get_or_build_provider(cfg)
            real_name = self._resolve_model_alias(project_id, cfg.model_name)
            started = time.perf_counter()
            try:
                result = provider.complete(prompt_text, real_name, idempotency_key)
            except Exception as exc:  # noqa: BLE001 —— 任何 provider 异常都触发 failover
                tried.append({
                    "tier": cfg.tier,
                    "model_name": cfg.model_name,
                    "provider": cfg.provider,
                    "error": f"{type(exc).__name__}: {exc}",
                    "latency_ms": _elapsed_ms(started),
                })
                # budget-blocked 不 failover（已是熔断态，直接 raise 让上层处理）
                if isinstance(exc, LLMProviderError) and "budget blocked" in str(exc).lower():
                    raise
                last_exc = exc
                # 只在前 N-1 个 tier 失败时写 failover event（切换到下一 tier）；
                # 最后一个 tier 失败不写——整体失败由下方 LLM_CALL_FAILED event 覆盖，避免重复。
                if idx < len(chain) - 1:
                    self._write_event(
                        project_id, shot_id, run_id, "model_role_failover",
                        {
                            "call_type": call_type, "from_tier": cfg.tier,
                            "model_name": cfg.model_name, "provider": cfg.provider,
                            "error": f"{type(exc).__name__}: {exc}",
                        },
                    )
                continue
            # 成功：落一次 attempt（记实际命中的 model/provider）+ record success（重置连续失败）。
            now = now_utc_iso()
            response_hash = _sha256(result.text)
            cursor = self.conn.execute(
                """
                INSERT INTO writing_ai_call_attempts
                    (project_id, shot_id, run_id, call_type, model_provider, model_name, idempotency_key,
                     prompt_id, prompt_hash, success, response_hash, token_input, token_output,
                     latency_ms, finish_reason, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?)
                """,
                (
                    project_id, shot_id, run_id, call_type, cfg.provider, cfg.model_name,
                    idempotency_key, prompt_id, _sha256(prompt_text), response_hash,
                    result.token_input, result.token_output, _elapsed_ms(started),
                    result.finish_reason, now,
                ),
            )
            attempt_id = int(cursor.lastrowid)
            if budget is not None:
                budget.record_call(shot_id, call_type, success=True)
                budget.check_circuit(shot_id, run_id)
            self._write_event(
                project_id, shot_id, run_id, "LLM_CALL_SUCCEEDED",
                {"attempt_id": attempt_id, "call_type": call_type, "tier": cfg.tier,
                 "model_name": cfg.model_name, "failover_tried": tried[:-1] if tried else []},
            )
            # 还原成 original_model_name（保持调用方期望的 model_name 契约，如 soft seal 别名）。
            if cfg.model_name != original_model_name:
                result = replace(result, model_name=original_model_name)
            return result

        # 三 tier 全失败：落一次 attempt（fail）+ record fail（只记一次，逻辑调用级）。
        now = now_utc_iso()
        cursor = self.conn.execute(
            """
            INSERT INTO writing_ai_call_attempts
                (project_id, shot_id, run_id, call_type, model_provider, model_name, idempotency_key,
                 prompt_id, prompt_hash, success, error_category, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
            """,
            (
                project_id, shot_id, run_id, call_type, chain[0].provider, chain[0].model_name,
                idempotency_key, prompt_id, _sha256(prompt_text),
                type(last_exc).__name__ if last_exc else "UnknownError", now,
            ),
        )
        attempt_id = int(cursor.lastrowid)
        if budget is not None:
            budget.record_call(shot_id, call_type, success=False, failure_type="LLMProviderError")
        self._write_event(
            project_id, shot_id, run_id, "LLM_CALL_FAILED",
            {"attempt_id": attempt_id, "call_type": call_type, "tried_tiers": tried},
        )
        names = ", ".join(f"{c.tier}={c.model_name}({c.provider})" for c in chain)
        key_envs = ", ".join(sorted({c.api_key_env for c in chain}))
        raise LLMProviderError(
            f"all tiers failed for call_type={call_type}; 已尝试主/备/兜底: {names}; "
            f"请检查供应商可用性与 api-key 配置（env: {key_envs}）"
        ) from last_exc

    def _get_or_build_provider(self, cfg) -> ModelProvider:  # cfg: ModelRoleConfig
        """按 (provider, base_url, api_key_env) 缓存构造 ModelProvider。"""
        cache_key = (cfg.provider, cfg.base_url, cfg.api_key_env)
        cached = self._provider_cache.get(cache_key)
        if cached is not None:
            return cached
        if cfg.provider == "mock":
            provider: ModelProvider = MockProvider()
        elif cfg.provider == "openai-compatible":
            api_key = os.environ.get(cfg.api_key_env)
            if not api_key:
                raise LLMProviderError(
                    f"api_key_env {cfg.api_key_env} 未在环境变量中设置（tier={cfg.tier}, "
                    f"model={cfg.model_name}）；请设置该环境变量或用 'ink role-config' 改配"
                )
            if not cfg.base_url:
                raise LLMProviderError(
                    f"provider=openai-compatible 但 base_url 为空（tier={cfg.tier}）"
                )
            config = LLMProviderConfig(
                provider="openai-compatible",
                base_url=cfg.base_url,
                api_key=api_key,
                max_tokens=cfg.max_tokens,
                max_retries=4,  # openai-compatible 默认退避重试扛限流
            )
            provider = build_model_provider(config)
        else:
            raise LLMProviderError(f"unsupported provider in role config: {cfg.provider}")
        self._provider_cache[cache_key] = provider
        return provider

    def _resolve_model_alias(self, project_id: int, model_name: str) -> str:
        """把生产别名（如 smart-polish）翻译成真实模型名。

        优先用构造时注入的 model_aliases；否则按 project_id 从
        writing_projects.model_aliases 懒加载（按 project 缓存，避免每次 call 查 DB）。
        未命中别名的模型名原样返回。
        """
        aliases = self._model_aliases
        if aliases is None:
            aliases = self._aliases_cache.get(project_id)
            if aliases is None:
                aliases = self._load_project_aliases(project_id)
                self._aliases_cache[project_id] = aliases
        return aliases.get(model_name, model_name)

    def _load_project_aliases(self, project_id: int) -> dict[str, str]:
        row = self.conn.execute(
            "SELECT model_aliases FROM writing_projects WHERE project_id = ?",
            (project_id,),
        ).fetchone()
        if row is None or not row[0]:
            return {}
        try:
            raw = json.loads(row[0])
        except (json.JSONDecodeError, TypeError) as exc:
            raise ConfigError(f"invalid model_aliases JSON for project {project_id}: {exc}") from exc
        if not isinstance(raw, dict):
            raise ConfigError(f"model_aliases for project {project_id} must be a JSON object")
        # 键值统一字符串化，防御 {"smart-polish": 123} 之类的坏数据。
        return {str(k): str(v) for k, v in raw.items() if v}

    def _write_event(
        self,
        project_id: int,
        shot_id: str | None,
        run_id: int | None,
        event_type: str,
        payload: dict,
    ) -> None:
        self.conn.execute(
            """
            INSERT INTO writing_runtime_events
                (project_id, run_id, shot_id, event_type, event_payload, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (project_id, run_id, shot_id, event_type, json.dumps(payload, sort_keys=True), now_utc_iso()),
        )


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _elapsed_ms(started: float) -> int:
    return max(0, int((time.perf_counter() - started) * 1000))


def load_llm_provider_config(
    *,
    env: Mapping[str, str] | None = None,
    provider: str | None = None,
    base_url: str | None = None,
    api_key: str | None = None,
    api_key_env: str | None = None,
    timeout_seconds: float | None = None,
    max_tokens: int | None = None,
    max_retries: int | None = None,
) -> LLMProviderConfig:
    source = os.environ if env is None else env
    provider_name = (provider or source.get("INK_LLM_PROVIDER") or "mock").strip().lower().replace("_", "-")
    if provider_name == "mock":
        return LLMProviderConfig(provider="mock")
    if provider_name != "openai-compatible":
        raise ConfigError(f"unsupported LLM provider: {provider_name}")

    resolved_base_url = base_url or source.get("INK_LLM_BASE_URL")
    key_env = api_key_env or source.get("INK_LLM_API_KEY_ENV") or "INK_LLM_API_KEY"
    resolved_api_key = api_key or source.get(key_env)
    timeout_raw: object = timeout_seconds if timeout_seconds is not None else source.get("INK_LLM_TIMEOUT_SECONDS", 60.0)
    try:
        resolved_timeout = float(timeout_raw)
    except (TypeError, ValueError) as exc:
        raise ConfigError("INK_LLM_TIMEOUT_SECONDS must be numeric") from exc
    if resolved_timeout <= 0:
        raise ConfigError("INK_LLM_TIMEOUT_SECONDS must be positive")

    # 可选 max_tokens：CLI 参数优先，否则读 INK_LLM_MAX_TOKENS 环境变量。
    # 对所有模型生效；推理模型未显式设置时也会自动注入默认值。
    resolved_max_tokens: int | None = max_tokens
    if resolved_max_tokens is None:
        max_tokens_raw: object = source.get("INK_LLM_MAX_TOKENS")
        if max_tokens_raw is not None and str(max_tokens_raw).strip():
            try:
                resolved_max_tokens = int(max_tokens_raw)
            except (TypeError, ValueError) as exc:
                raise ConfigError("INK_LLM_MAX_TOKENS must be an integer") from exc
            if resolved_max_tokens <= 0:
                raise ConfigError("INK_LLM_MAX_TOKENS must be positive")

    # 重试次数：CLI 参数优先，否则读 INK_LLM_MAX_RETRIES，openai-compatible 实跑默认 4 次
    # （iFLYTEK 等网关常 429/503 限流，退避重试是实跑链路必要基础设施）。
    resolved_max_retries: int | None = max_retries
    if resolved_max_retries is None:
        retries_raw: object = source.get("INK_LLM_MAX_RETRIES")
        if retries_raw is not None and str(retries_raw).strip():
            try:
                resolved_max_retries = int(retries_raw)
            except (TypeError, ValueError) as exc:
                raise ConfigError("INK_LLM_MAX_RETRIES must be an integer") from exc
            if resolved_max_retries < 0:
                raise ConfigError("INK_LLM_MAX_RETRIES must be non-negative")
    if resolved_max_retries is None:
        resolved_max_retries = 4

    if not resolved_base_url:
        raise ConfigError("openai-compatible provider requires INK_LLM_BASE_URL or --llm-base-url")
    if not resolved_api_key:
        raise ConfigError(f"openai-compatible provider requires API key in {key_env}")
    return LLMProviderConfig(
        provider="openai-compatible",
        base_url=resolved_base_url,
        api_key=resolved_api_key,
        timeout_seconds=resolved_timeout,
        max_tokens=resolved_max_tokens,
        max_retries=resolved_max_retries,
    )


def build_model_provider(config: LLMProviderConfig) -> ModelProvider:
    if config.provider == "mock":
        return MockProvider()
    if config.provider == "openai-compatible":
        if config.base_url is None or config.api_key is None:
            raise ConfigError("openai-compatible provider config is incomplete")
        return OpenAICompatibleProvider(
            base_url=config.base_url,
            api_key=config.api_key,
            timeout_seconds=config.timeout_seconds,
            max_tokens=config.max_tokens,
            max_retries=config.max_retries,
        )
    raise ConfigError(f"unsupported LLM provider: {config.provider}")


def _parse_chat_completion_response(payload: object, *, fallback_model: str) -> ModelResult:
    if not isinstance(payload, dict):
        raise LLMProviderError("provider response must be a JSON object")
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        raise LLMProviderError("provider response missing choices")
    choice = choices[0]
    if not isinstance(choice, dict):
        raise LLMProviderError("provider response choice must be an object")
    message = choice.get("message")
    text = message.get("content") if isinstance(message, dict) else choice.get("text")
    # 推理模型在 max_tokens 不足时 content 可能为空，但 reasoning_content 有值。
    # 回退到 reasoning_content，避免直接抛错丢失思维链输出。
    if (not isinstance(text, str) or not text) and isinstance(message, dict):
        reasoning = message.get("reasoning_content")
        if isinstance(reasoning, str) and reasoning:
            text = reasoning
    if not isinstance(text, str) or not text:
        raise LLMProviderError("provider response missing text content")
    usage = payload.get("usage")
    usage_data = usage if isinstance(usage, dict) else {}
    return ModelResult(
        text=text,
        model_name=str(payload.get("model") or fallback_model),
        token_input=int(usage_data.get("prompt_tokens") or 0),
        token_output=int(usage_data.get("completion_tokens") or 0),
        finish_reason=str(choice.get("finish_reason") or "stop"),
    )
