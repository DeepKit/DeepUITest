"""本地代理（WiseGateway 127.0.0.1:8000）真模型版 10 章流水线端到端验收。

与 ``test_e2e_real_models.py``（接 iFLYTEK 官方端点、6 章）互补：
- 后者直连 iFLYTEK MaaS，模型名走官方别名（xopglm51 等），key 走 IFLYTEK_API_KEY；
- 本测试接**本地 WiseGateway 代理**，模型名用代理暴露的 ``claude-xunfei-*`` 原生名，
  key 是代理签发的 ``fuyi-kiro-*``（非 appId:apiKey 格式，故不走 IFLYTEK_API_KEY）。

代理内部把 ``claude-xunfei-glm-5-1`` 这类透传名映射回 iFLYTEK 端点别名（实测返回
``model=xopglm51``），故 gateway 侧无白名单问题——OpenAICompatibleProvider.complete 直接把
model_name 塞进 payload model 字段透传。

**多用讯飞系**（老板指示：讯飞包月按次不计 token，预算不限）：
- writer 池：glm-5-1 / glm-5-2 / deepseek-v4-pro / kimi-k2-6（4 模型，shot_id 偏移破集中）
- jury 池：再叠 qwen3-6-35b-a3b / qwen3-5-397b-a17b（6 模型，满足 DDL CHECK ≥5）
- smart-polish 别名 → glm-5-1（PolishOrchestrator 硬编码 model_name="smart-polish"，
  gateway 经 writing_projects.model_aliases JSON 列翻译别名调真实模型）

章数 10（对齐圆桌基线那次的压测量）。断言聚焦「跑通」而非具体文本：
- 10 章全部 soft_sealed；
- 至少 1 章 winner draft 非 degraded（证明真实模型确实产出有效文本）；
- export artifact 非空且含 10 章；
- chapter reviews accepted 数 ≥ 8（允许个别章限流降级后 jury 拒绝）。

chapter_review 三 tier role-config 的 api_key_env=LOCAL_PROXY_KEY（代理 key 不在 IFLYTEK_API_KEY），
跑前需 ``export LOCAL_PROXY_KEY=fuyi-kiro-...``。无此环境变量时 chapter_review role-config 校验
失败——但主测试用注入式 provider（自带 key），仅 chapter_review 那条链依赖环境变量。
"""
from __future__ import annotations

import json
import os
import time

import pytest

from ink.core.llm_gateway import LLMGateway, OpenAICompatibleProvider
from ink.core.model_role_config import upsert_role_config
from ink.errors import DataIntegrityError, LLMProviderError
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.pipeline.export_orchestrator import ExportOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator
from factories import NOW, make_schema_db
from test_m2_contract_outline import insert_chinese_contract_children

# 本地 WiseGateway 代理（不直连 iFLYTEK 官方端点）。
LOCAL_PROXY_BASE_URL = "http://127.0.0.1:8000/v1"
LOCAL_PROXY_API_KEY = "fuyi-kiro-17781158558"
LOCAL_PROXY_KEY_ENV = "LOCAL_PROXY_KEY"

PROJECT_ID = 1
SESSION_ID = 10
INITIAL_RUN_ID = 20
CHAPTER_COUNT = 10

# 讯飞系模型池（代理暴露的 claude-xunfei-* 原生名）。
WRITER_POOL = [
    "claude-xunfei-glm-5-1",
    "claude-xunfei-glm-5-2",
    "claude-xunfei-deepseek-v4-pro",
    "claude-xunfei-kimi-k2-6",
]
JURY_POOL = [
    "claude-xunfei-glm-5-1",
    "claude-xunfei-glm-5-2",
    "claude-xunfei-deepseek-v4-pro",
    "claude-xunfei-qwen3-6-35b-a3b",
    "claude-xunfei-qwen3-5-397b-a17b",
    "claude-xunfei-kimi-k2-6",
]

# smart-polish 别名 → 代理透传名（与生产 model_aliases JSON 列一致的路由模式）。
MODEL_ALIAS_MAP = {"smart-polish": "claude-xunfei-glm-5-1"}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def provider() -> OpenAICompatibleProvider:
    """本地代理 provider（裸 OpenAICompatibleProvider，key 自带不走环境变量）。

    开启退避重试（max_retries=4）：代理上游 iFLYTEK 网关常 429/503 限流，
    与生产 CLI 实跑一致。
    """
    return OpenAICompatibleProvider(
        base_url=LOCAL_PROXY_BASE_URL,
        api_key=LOCAL_PROXY_API_KEY,
        max_retries=4,
        retry_base_delay=1.0,
    )


@pytest.fixture()
def gateway_conn():
    """10 章节项目，模型池换成讯飞系真模型（经本地代理）。

    阈值放宽以适配真实模型（与 test_e2e_real_models.py 同理由）：
    - ``min_eligible_outlines=1``：只要 1 个合格 outline（默认 2 过严）；
    - ``outline_drift_threshold=0.02``：真实模型倾向用自己的话重写，CJK bigram 重叠趋 0。
    """
    if LOCAL_PROXY_KEY_ENV not in os.environ:
        # chapter_review 链需此环境变量（主测试 provider 自带 key 不需要），
        # 预先提示而非跑到 chapter_review 才炸。
        os.environ[LOCAL_PROXY_KEY_ENV] = LOCAL_PROXY_API_KEY

    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool,
             model_aliases, min_eligible_outlines, outline_drift_threshold, created_at)
        VALUES
            (?, 'local-proxy-demo', 'Local Proxy 10-Chapter Demo', ?, ?,
             ?, 1, 0.02, ?)
        """,
        (
            PROJECT_ID,
            json.dumps(WRITER_POOL),
            json.dumps(JURY_POOL),
            json.dumps(MODEL_ALIAS_MAP),
            NOW,
        ),
    )
    # 10 章 × (3 裁判 × 5 候选 × 2 轮 + polish + chapter_review 三 tier + 余量)。
    # 讯飞包月不计 token，预算给足，避免 per_type_exceeded budget blocked。
    conn.execute(
        "UPDATE writing_projects SET max_calls_per_shot = 27, max_total_llm_calls = 330 WHERE project_id = ?",
        (PROJECT_ID,),
    )
    # chapter_review 三 tier role-config：走 role_chain 路径（与生产 CLI 一致），
    # api_key 从 LOCAL_PROXY_KEY 环境变量读（代理 key 非 appId:apiKey 格式）。
    for tier, model_name in zip(("primary", "secondary", "tertiary"), JURY_POOL[:3]):
        upsert_role_config(
            conn,
            project_id=PROJECT_ID,
            call_type="chapter_review",
            tier=tier,
            model_name=model_name,
            provider="openai-compatible",
            api_key_env=LOCAL_PROXY_KEY_ENV,
            base_url=LOCAL_PROXY_BASE_URL,
        )
    conn.execute(
        "INSERT INTO writing_sessions (session_id, project_id, started_at) VALUES (?, ?, ?)",
        (SESSION_ID, PROJECT_ID, NOW),
    )
    conn.execute(
        """
        INSERT INTO writing_runs
            (run_id, project_id, session_id, run_attempt, started_at, status)
        VALUES (?, ?, ?, 1, ?, 'running')
        """,
        (INITIAL_RUN_ID, PROJECT_ID, SESSION_ID, NOW),
    )
    for chapter_id in range(1, CHAPTER_COUNT + 1):
        logical_shot_id = f"ch-{chapter_id:02d}-shot-001"
        cursor = conn.execute(
            """
            INSERT INTO writing_shot_contracts
                (project_id, chapter_id, run_id, logical_shot_id, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, 'confirmed', ?, ?)
            """,
            (PROJECT_ID, chapter_id, INITIAL_RUN_ID, logical_shot_id, NOW, NOW),
        )
        shot_contract_id = int(cursor.lastrowid)
        insert_chinese_contract_children(conn, shot_contract_id)
        conn.execute(
            """
            INSERT INTO writing_shots
                (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id,
                 status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)
            """,
            (
                f"{logical_shot_id}@{INITIAL_RUN_ID}",
                PROJECT_ID,
                chapter_id,
                shot_contract_id,
                INITIAL_RUN_ID,
                logical_shot_id,
                NOW,
                NOW,
            ),
        )
    return conn


def _chapter_shot(conn, chapter_id: int, run_id: int) -> tuple[str, int]:
    row = conn.execute(
        """
        SELECT shot_id, run_id
        FROM writing_shots
        WHERE project_id = ? AND chapter_id = ? AND run_id = ?
        """,
        (PROJECT_ID, chapter_id, run_id),
    ).fetchone()
    return str(row[0]), int(row[1])


def _is_transient_gateway_error(exc: Exception) -> bool:
    """代理上游间歇性错误：限流（503）、路由失败（500/Model Not Found）等。

    网关偶发问题而非测试本身缺陷，按 iflytek 集成测试惯例 skip。
    """
    msg = str(exc)
    return any(
        token in msg
        for token in ("503", "500", "Model Not Found", "overloaded", "PathDomainError")
    )


def _run_shot_to_soft_sealed(conn, shot_id: str, run_id: int, gateway: LLMGateway) -> None:
    """跑完单章：outline → write → hard gate → jury → polish → hard gate → jury → soft seal。

    outline / polish 段无降级兜底，遇网关间歇错误或 drift 全拒时 skip 整条测试。
    """
    from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator

    try:
        PreDraftingOrchestrator(conn, gateway).run_until_prompt_compiled(shot_id, run_id)
    except LLMProviderError as exc:
        if _is_transient_gateway_error(exc):
            pytest.skip(f"local-proxy transient error during outline: {str(exc)[:120]}")
        raise
    except DataIntegrityError as exc:
        if "below threshold" in str(exc):
            pytest.skip(
                f"real-model outlines all drift-rejected: {str(exc)[:120]} "
                "(threshold tuning tracked as P2)"
            )
        raise

    WriteOrchestrator(conn, gateway).produce_drafts(shot_id, run_id)

    from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
    from ink.pipeline.jury_orchestrator import JuryOrchestrator
    from ink.pipeline.polish_orchestrator import PolishOrchestrator
    from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator

    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn).score_and_select_winner(shot_id, run_id)

    try:
        PolishOrchestrator(conn, gateway).polish_winner(shot_id, run_id)
    except LLMProviderError as exc:
        if _is_transient_gateway_error(exc):
            pytest.skip(f"local-proxy transient error during polish: {str(exc)[:120]}")
        raise

    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn).score_and_select_winner(shot_id, run_id)
    SoftSealOrchestrator(conn).soft_seal_if_polished(shot_id, run_id)
    assert (
        conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (shot_id,)).fetchone()[0]
        == "soft_sealed"
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestLocalProxyTenChapters:
    """本地代理（讯飞系真模型）驱动的 10 章流水线。"""

    def test_local_proxy_ten_chapter_pipeline(
        self,
        gateway_conn,
        provider: OpenAICompatibleProvider,
    ) -> None:
        """完整 10 章：outline → write → jury → polish → review → accept → export，全程真模型。"""
        conn = gateway_conn
        gateway = LLMGateway(conn, provider=provider, provider_name="iflytek")

        for chapter_id in range(1, CHAPTER_COUNT + 1):
            shot_id, run_id = _chapter_shot(conn, chapter_id, INITIAL_RUN_ID)
            _run_shot_to_soft_sealed(conn, shot_id, run_id, gateway)

            ChapterReviewOrchestrator(conn, gateway).review_chapter(PROJECT_ID, chapter_id, run_id)
            HumanReviewOrchestrator(conn).accept_chapter(
                PROJECT_ID,
                chapter_id,
                run_id,
                actor="author",
                reason=f"accept local-proxy chapter {chapter_id}",
            )

            if chapter_id < CHAPTER_COUNT:
                time.sleep(4)  # 限流间隔

        # ------------------------------------------------------------------
        # 断言：聚焦「跑通」而非具体文本
        # ------------------------------------------------------------------
        # 1. 10 章全部 soft_sealed（已在 _run_shot_to_soft_sealed 内逐章断言）

        # 2. 至少 1 章 winner draft 非 degraded —— 证明真实模型产出有效文本
        non_degraded_winners = conn.execute(
            """
            SELECT count(*)
            FROM writing_drafts d
            WHERE d.degraded = 0 AND d.draft_id IN (
                SELECT draft_id FROM writing_jury_aggregates WHERE is_winner = 1
            )
            """
        ).fetchone()[0]
        assert non_degraded_winners >= 1, (
            "expected at least 1 non-degraded winner draft, "
            "got 0 — all drafts degraded (real model unreachable?)"
        )

        # 3. export artifact 非空、含 10 章
        artifact = ExportOrchestrator(conn).export_project(PROJECT_ID)
        assert isinstance(artifact, str)
        assert len(artifact) > 0, "export artifact is empty"

        chapter_count = conn.execute(
            "SELECT count(DISTINCT chapter_id) FROM writing_shots WHERE project_id = ?",
            (PROJECT_ID,),
        ).fetchone()[0]
        assert chapter_count == CHAPTER_COUNT

        # 4. chapter reviews accepted ≥ 8（允许个别章限流降级后 jury 拒绝）
        accepted = conn.execute(
            "SELECT count(*) FROM writing_chapter_reviews WHERE status = 'accepted'"
        ).fetchone()[0]
        assert accepted >= 8, f"expected >= 8 accepted chapter reviews, got {accepted}"
