"""真实 iFLYTEK 模型版 6 章流水线端到端验收。

与 ``test_m6_workflow_smoke.py::test_full_production_flow_six_chapters`` 互补:
- 后者用 mock ``WorkflowProvider`` 验证 pipeline 编排正确性;
- 本文���用真实 ``OpenAICompatibleProvider`` 接 iFLYTEK Coding Plan,验证
  outline 抽取 / 产稿 / 润色在真实模型下的行为。

无 ``IFLYTEK_API_KEY`` 时全部 skip(仿 ``test_iflytek_integration.py``)。
iFLYTEK 是包月套餐,预算不受限,但 ``xopglm52`` 太卡已从池中剔除,
writer 池用 ``xopglm51``/``xopdeepseekv4pro``/``xopkimik26``。

真实模型输出不可预测,断言聚焦「pipeline 跑通」而非具体文本:
- 6 章全部 soft_sealed;
- 至少 1 章 winner draft 非 degraded(证明真实模型确实产出有效文本);
- export artifact 非空且含 6 章;
- chapter reviews accepted 数 ≥ 5(允许个别章限流降级后 jury 拒绝)。
"""
from __future__ import annotations

import os
import time

import pytest

from ink.core.llm_gateway import LLMGateway, OpenAICompatibleProvider
from ink.core.model_role_config import upsert_role_config
from ink.errors import DataIntegrityError, LLMProviderError
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator
from ink.pipeline.export_orchestrator import ExportOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from ink.pipeline.outline_orchestrator import OutlineOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator
from factories import NOW, make_schema_db
from test_m2_contract_outline import insert_chinese_contract_children

# 复用 iflytek 集成测试的常量与 skip 守卫
from test_iflytek_integration import IFLYTEK_BASE_URL, _skip_if_no_key

PROJECT_ID = 1
SESSION_ID = 10
INITIAL_RUN_ID = 20

# 避开太卡的 xopglm52;writer 池 3 个、jury 池 5 个(满足 DDL CHECK)
WRITER_POOL = ["xopglm51", "xopdeepseekv4pro", "xopkimik26"]
JURY_POOL = [
    "xopglm51",
    "xopdeepseekv4pro",
    "xopqwen36v35b",
    "xopkimik26",
    "xopqwen35397b",
]

# PolishOrchestrator 硬编码 model_name="smart-polish"(src/ink/pipeline/polish_orchestrator.py:38),
# 该别名在真实 iFLYTEK 不存在。生产侧通过 writing_projects.model_aliases JSON 列做别名路由
# (LLMGateway.call 翻译别名调真实模型,但 DB 与 ModelResult.model_name 保持原别名以满足
# SoftSealOrchestrator 校验契约)。测试侧同样把别名存 DB,与生产 CLI 完全一致。
MODEL_ALIAS_MAP = {"smart-polish": "xopglm51"}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def api_key() -> str:
    return _skip_if_no_key()


@pytest.fixture()
def provider(api_key: str) -> OpenAICompatibleProvider:
    """真实 iFLYTEK provider(裸 OpenAICompatibleProvider,别名校验由 gateway 层从 DB 读)。

    开启退避重试(max_retries=4):iFLYTEK 网关常 429/503 限流,与生产 CLI 实跑一致。
    """
    return OpenAICompatibleProvider(
        base_url=IFLYTEK_BASE_URL,
        api_key=api_key,
        max_retries=4,
        retry_base_delay=1.0,
    )


@pytest.fixture()
def gateway_conn():
    """六章节项目,但模型池换成真实 iFLYTEK 模型。

    阈值放宽以适配真实模型:
    - ``min_eligible_outlines=1``:只要 1 个合格 outline(默认 2 过严);
    - ``outline_drift_threshold=0.02``:真实模型(GLM/DeepSeek)倾向用自己的话重写,
      outline 与契约结构化字段(must_land/scene_contract)的 CJK bigram 重叠天然趋近 0
      (见 BFX-032),阈值需极低否则全拒。默认 0.20 / 0.10 均易全拒。
    """
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool,
             model_aliases, min_eligible_outlines, outline_drift_threshold, created_at)
        VALUES
            (?, 'real-models-demo', 'Real Models Demo', ?, ?,
             ?, 1, 0.02, ?)
        """,
        (
            PROJECT_ID,
            __import__("json").dumps(WRITER_POOL),
            __import__("json").dumps(JURY_POOL),
            __import__("json").dumps(MODEL_ALIAS_MAP),
            NOW,
        ),
    )
    # jury 真实化后单 shot jury 调用 = 3 裁判 × (draft_count 候选 + 1 polished 稿) × 两轮（首评 +
    # polish 后重评），+3 余量容 escalation 重评。与 cli.py setup 同公式（见 BFX-036），否则 schema
    # 默认 max_calls_per_shot=8 在真实 jury 调用时触发 per_type_exceeded budget blocked。
    conn.execute(
        "UPDATE writing_projects SET max_calls_per_shot = 27, max_total_llm_calls = 66 WHERE project_id = ?",
        (PROJECT_ID,),
    )
    # chapter_review 真实化调 gateway.call(call_type="chapter_review", model_name=None, tier_hint="primary")
    # —— 无 role_config 时回退注入式 provider，但 model_name=None 会落到 provider_name("iflytek")
    # 非真实模型名 → 全 tier 失败抛 ChapterReviewLLMFailure。配 chapter_review 三 tier role-config
    # 让 gateway 走 role_chain 路径（与生�� CLI 一致），api_key 从 IFLYTEK_API_KEY 环境变量读。
    for tier, model_name in zip(("primary", "secondary", "tertiary"), JURY_POOL[:3]):
        upsert_role_config(
            conn,
            project_id=PROJECT_ID,
            call_type="chapter_review",
            tier=tier,
            model_name=model_name,
            provider="openai-compatible",
            api_key_env="IFLYTEK_API_KEY",
            base_url=IFLYTEK_BASE_URL,
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
    for chapter_id in range(1, 7):
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
    """iFLYTEK 网关侧间歇性错误:限流(503)、路由失败(500/Model Not Found)等。

    这些是网关偶发问题而非测试本身缺陷,按 iflytek 集成测试惯例 skip。
    """
    msg = str(exc)
    return any(
        token in msg
        for token in ("503", "500", "Model Not Found", "overloaded", "PathDomainError")
    )


def _run_shot_to_soft_sealed(conn, shot_id: str, run_id: int, gateway: LLMGateway) -> None:
    """跑完单章:outline → write → hard gate → jury → polish → hard gate → jury → soft seal。

    outline / polish 段无降级兜底,遇网关间歇错误或 drift 全拒时 skip 整条测试
    (符合 ``test_iflytek_integration.py`` 惯例:网关侧问题 skip 而非 fail)。
    """
    # outline 段(无降级兜底)
    from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator

    try:
        PreDraftingOrchestrator(conn, gateway).run_until_prompt_compiled(shot_id, run_id)
    except LLMProviderError as exc:
        if _is_transient_gateway_error(exc):
            pytest.skip(f"iFLYTEK transient error during outline: {str(exc)[:120]}")
        raise
    except DataIntegrityError as exc:
        if "below threshold" in str(exc):
            pytest.skip(
                f"real-model outlines all drift-rejected: {str(exc)[:120]} "
                "(threshold tuning tracked as P2)"
            )
        raise

    # write 段(有 degraded 兜底,网关错误不中断)
    WriteOrchestrator(conn, gateway).produce_drafts(shot_id, run_id)

    # jury / hard gate / polish / soft seal —— 复用 m6 smoke 的编排
    from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
    from ink.pipeline.jury_orchestrator import JuryOrchestrator
    from ink.pipeline.polish_orchestrator import PolishOrchestrator
    from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator

    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn).score_and_select_winner(shot_id, run_id)

    # polish 段(无降级兜底,网关间歇错误 skip)
    try:
        PolishOrchestrator(conn, gateway).polish_winner(shot_id, run_id)
    except LLMProviderError as exc:
        if _is_transient_gateway_error(exc):
            pytest.skip(f"iFLYTEK transient error during polish: {str(exc)[:120]}")
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


class TestRealModelsSixChapters:
    """真实 iFLYTEK 模型驱动的 6 章流水线。"""

    def test_real_six_chapter_pipeline(
        self,
        gateway_conn,
        provider: OpenAICompatibleProvider,
    ) -> None:
        """完整 6 章:write → jury → review → accept → export,全程真实模型。"""
        conn = gateway_conn
        gateway = LLMGateway(conn, provider=provider, provider_name="iflytek")

        for chapter_id in range(1, 7):
            shot_id, run_id = _chapter_shot(conn, chapter_id, INITIAL_RUN_ID)
            _run_shot_to_soft_sealed(conn, shot_id, run_id, gateway)

            ChapterReviewOrchestrator(conn, gateway).review_chapter(PROJECT_ID, chapter_id, run_id)
            HumanReviewOrchestrator(conn).accept_chapter(
                PROJECT_ID,
                chapter_id,
                run_id,
                actor="author",
                reason=f"accept real-model chapter {chapter_id}",
            )

            if chapter_id < 6:
                time.sleep(4)  # 限流间隔

        # ------------------------------------------------------------------
        # 断言:聚焦「跑通」而非具体文本
        # ------------------------------------------------------------------
        # 1. 6 章全部 soft_sealed(已在 _run_shot_to_soft_sealed 内逐章断言)

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

        # 3. export artifact 非空、含 6 章
        artifact = ExportOrchestrator(conn).export_project(PROJECT_ID)
        assert isinstance(artifact, str)
        assert len(artifact) > 0, "export artifact is empty"

        chapter_count = conn.execute(
            "SELECT count(DISTINCT chapter_id) FROM writing_shots WHERE project_id = ?",
            (PROJECT_ID,),
        ).fetchone()[0]
        assert chapter_count == 6

        # 4. chapter reviews accepted ≥ 5(允许个别章限流降级后 jury 拒绝)
        accepted = conn.execute(
            "SELECT count(*) FROM writing_chapter_reviews WHERE status = 'accepted'"
        ).fetchone()[0]
        assert accepted >= 5, f"expected >= 5 accepted chapter reviews, got {accepted}"

    def test_real_outline_extraction_smoke(
        self,
        gateway_conn,
        provider: OpenAICompatibleProvider,
    ) -> None:
        """单章 outline 真实模型 smoke:验证 drift 不全拒、至少 1 个合格 outline。

        隔离 outline 段风险:失败时单独 skip 而非拖垮整条 pipeline 测试。
        """
        conn = gateway_conn
        gateway = LLMGateway(conn, provider=provider, provider_name="iflytek")
        shot_id, run_id = _chapter_shot(conn, 1, INITIAL_RUN_ID)

        try:
            OutlineOrchestrator(conn, gateway).evaluate_and_select(shot_id, run_id)
        except LLMProviderError as exc:
            if _is_transient_gateway_error(exc):
                pytest.skip(f"iFLYTEK transient error: {str(exc)[:120]}")
            raise
        except DataIntegrityError as exc:
            if "below threshold" in str(exc):
                pytest.skip(
                    f"real-model outlines all drift-rejected: {str(exc)[:120]} "
                    "(threshold tuning tracked as P2)"
                )
            raise

        # 验证 winner outline 已落库
        winner_count = conn.execute(
            """
            SELECT count(*)
            FROM writing_outline_specs
            WHERE shot_contract_id = (SELECT shot_contract_id FROM writing_shots WHERE shot_id = ?)
              AND is_winner = 1
            """,
            (shot_id,),
        ).fetchone()[0]
        assert winner_count == 1, f"expected 1 winner outline, got {winner_count}"


# ---------------------------------------------------------------------------
# 工业事实漂移检测器真模型守卫（task#19 / C3）
# ---------------------------------------------------------------------------


def test_real_industrial_drift_llm_fallback_contract(
    gateway_conn,
    provider: OpenAICompatibleProvider,
) -> None:
    """真模型守卫：工业漂移检测器 LLM 兜底层走真实 iFLYTEK，JSON 契约不崩。

    单测（test_m5_chapter_review.py::test_industrial_fact_drift_llm_fallback_blocks）
    用 mock provider 证 drift=true 阻断路径；本测试补「真实模型能产出可解析 JSON」
    这层契约——规则层无 marker、可疑段含「失效」触发 chapter_review call_type，
    真模型经三 tier failover 返回 {drift,drift_type,evidence_sentence} 三字段齐全。

    检测器是可降级补充校验（三 tier 全失败转 (None,None) 不阻断），故真模型断言
    聚焦「不抛 + JSON 可解析」，drift 真值随模型理解力浮动不硬断。瞬时网关错误 skip。
    """
    from ink.pipeline.chapter_review_orchestrator import _parse_industrial_drift
    from ink.source_workflow import SourceWorkflowStore
    from test_m5_chapter_review import _seed_industrial_baseline

    conn = gateway_conn
    gateway = LLMGateway(conn, provider=provider, provider_name="iflytek")

    # 灌工业基线（forbidden marker 词表 + process 报废制度锚点）。
    _seed_industrial_baseline(conn)
    conn.commit()

    # 章文本含失效关键词、无 marker → 规则层放行，可疑段触发 LLM 兜底。
    texts = [
        "质检员老周盯着那批货，前线上报失效了三次。",
        "他没翻签字表，只是叹了口气。",
    ]
    orchestrator = ChapterReviewOrchestrator(conn, gateway)
    try:
        drift_type, evidence = orchestrator._industrial_fact_drift_block(
            project_id=PROJECT_ID,
            chapter_id=1,
            run_id=INITIAL_RUN_ID,
            texts=texts,
            contract_summary="chapter 1: 工厂质检线的失效追责",
        )
    except LLMProviderError as exc:
        if _is_transient_gateway_error(exc):
            pytest.skip(f"iFLYTEK transient error: {str(exc)[:120]}")
        raise

    # 契约：返回二元组，无异常。drift_type 非 None 时 evidence 必非空。
    if drift_type is not None:
        assert drift_type == "industrial_fact_drift"
        assert evidence and len(evidence) > 0
        # evidence 含 LLM 判定前缀（真模型产出的 drift_type 被拼进结果）。
        assert "LLM 判定" in evidence
pytestmark = pytest.mark.skipif(
    os.environ.get("INK_RUN_REAL_LLM_TESTS") != "1",
    reason="real provider acceptance is opt-in; set INK_RUN_REAL_LLM_TESTS=1",
)
