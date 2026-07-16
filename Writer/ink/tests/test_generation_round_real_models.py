"""真实 iFLYTEK 模型版 Generation Round 状态机端到端验收。

与 ``test_generation_round_driver.py``（全 stub）互补：后者验证调度路径正确性；
本测试用真实 ``LLMGateway`` 接 iFLYTEK Coding Plan，验证三个真实 port
（``RealGenerationPort`` / ``RealValidationPort`` / ``RealSelectionPort``）
接线后 ``GenerationRoundDriver.drive()`` 能跑完一轮真模型 generation →
validation → substantive-difference gate → winner selection。

真实模型输出不可预测，断言聚焦「调度路径跑了真模型并抵达合法终态」，
而非任何具体文本或分数（与 ``test_e2e_real_models.py`` 一致）：

- final_status 是合法终态之一（selected / candidate_shortage /
  diversity_shortage / failed）；
- call_count > 0（证明 driver 确实推进了 LLM 调用）；
- model_events 表有真实模型名（非注入式 provider 的 "iflytek" 占位）的调用记录。

双守卫（仿 ``test_e2e_real_models.py``）：缺 ``IFLYTEK_API_KEY`` 或
``INK_RUN_REAL_LLM_TESTS≠1`` 时 skip。iFLYTEK 是包月套餐，预算不受限。
"""
from __future__ import annotations

import os

import pytest

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.llm_gateway import LLMGateway, OpenAICompatibleProvider
from ink.core.model_role_config import upsert_role_config
from ink.core.scene_repository import SceneRepository
from ink.pipeline.generation_round_driver import GenerationRoundDriver
from ink.pipeline.generation_round_real_ports import (
    RealGenerationPort,
    RealSelectionPort,
    RealValidationPort,
)
from factories import NOW, insert_contract_approve_reviews, make_schema_db

from test_iflytek_integration import IFLYTEK_BASE_URL, _skip_if_no_key

PROJECT_ID = 1

# 复用 test_e2e_real_models 的模型池（避开太卡的 xopglm52）。
WRITER_POOL = ["xopglm51", "xopdeepseekv4pro", "xopkimik26"]
JURY_POOL = [
    "xopglm51",
    "xopdeepseekv4pro",
    "xopqwen36v35b",
    "xopkimik26",
    "xopqwen35397b",
]

CHAPTER_BRIEF = (
    "第1章《雨夜来客》。深夜暴雨，独居山屋的老木匠听见敲门声。来客是"
    "一个浑身湿透的年轻人，自称迷路求宿。老木匠注意到客人手腕上有一道"
    "旧伤疤，形似某种符文。本章须落地：雨势渲染、老木匠的警觉心理、"
    "符文伤疤的悬念钩子、章末留客与拒客的未决张力。1200-1800 字。"
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def api_key() -> str:
    return _skip_if_no_key()


@pytest.fixture()
def provider(api_key: str) -> OpenAICompatibleProvider:
    return OpenAICompatibleProvider(
        base_url=IFLYTEK_BASE_URL,
        api_key=api_key,
        max_retries=4,
        retry_base_delay=1.0,
    )


@pytest.fixture()
def gateway_conn(provider: OpenAICompatibleProvider):
    """一个 project + chapter_review/write 三 tier role-config + 一个 planned round。

    initial_target_count=3（绕过补稿，3 候选直接进 validation），
    supplement_target_count=0。
    """
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (?, 'round-real', 'Round Real', ?, ?, ?)
        """,
        (
            PROJECT_ID,
            __import__("json").dumps(WRITER_POOL),
            __import__("json").dumps(JURY_POOL),
            NOW,
        ),
    )
    # writer 三 tier（generation 用 call_type="draft"，与 WriteOrchestrator 一致）
    for tier, model_name in zip(("primary", "secondary", "tertiary"), WRITER_POOL):
        upsert_role_config(
            conn,
            project_id=PROJECT_ID,
            call_type="draft",
            tier=tier,
            model_name=model_name,
            provider="openai-compatible",
            api_key_env="IFLYTEK_API_KEY",
            base_url=IFLYTEK_BASE_URL,
        )
    # jury 三 tier（validation/diff/selection 复用 chapter_review 池）
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
    # 真实门槛来自 schema：shot_quality_floor(默认 75, CHECK>=75) 与 dimension_floor
    # (默认 60, CHECK>=60)。iFLYTEK jury 稳定 77-83，75 门槛可自然过门，不放宽。
    # jury 预算陷阱（见 ink-real-model-testing 记忆）：真实 jury 调用会触发
    # per_type_exceeded budget blocked。按 cli.py 公式 max(8, 6×(draft+1)+3) 放宽，
    # 3 候选场景下 27/66 足够覆盖评分+差异+选优多轮调用。
    conn.execute(
        """
        UPDATE writing_projects
        SET max_calls_per_shot = 27, max_total_llm_calls = 66
        WHERE project_id = ?
        """,
        (PROJECT_ID,),
    )
    # P0-1 状态机只消费上游 active Scene Contract；契约四层与双师生成属于 P0-3。
    # 夹具显式准备最小合法前置，确保真实 port 不旁路 Scene-first 不变量。
    scenes = SceneRepository(conn)
    scene_id = scenes.create_scene(
        project_id=PROJECT_ID,
        chapter_id=1,
        logical_scene_key="chapter-01-main",
        scene_order=1,
    )
    contract_id = scenes.create_contract(
        scene_id=scene_id,
        version=1,
        contract_hash="round-real-contract-v1",
        source_bundle_hash="round-real-source-v1",
        created_by="test-architect",
        status="approved",
    )
    scenes.assemble_four_layer_contract(
        scene_contract_id=contract_id,
        hard_constraints=[{"clause_key": "hard-1", "clause_text": "hard"}],
        source_dna=[{"clause_key": "source-1", "clause_text": "source"}],
        soft_goals=[{"clause_key": "soft-1", "clause_text": "soft"}],
        creative_openings=[
            {"clause_key": "opening-1", "clause_text": "opening one"},
            {"clause_key": "opening-2", "clause_text": "opening two"},
        ],
    )
    insert_contract_approve_reviews(conn, contract_id)
    scenes.activate_contract(contract_id)

    repo = ChapterSnapshotRepository(conn)
    round_id = repo.create_generation_round(
        project_id=PROJECT_ID, chapter_id=1, round_number=1
    )
    # 3 候选直接进 validation，不触发补稿分支。
    conn.execute(
        """
        UPDATE writing_chapter_generation_rounds
        SET initial_target_count = 3, supplement_target_count = 0
        WHERE generation_round_id = ?
        """,
        (round_id,),
    )
    conn.commit()
    return conn, repo, round_id


# ---------------------------------------------------------------------------
# Acceptance
# ---------------------------------------------------------------------------


@pytest.mark.skipif(
    os.environ.get("INK_RUN_REAL_LLM_TESTS") != "1",
    reason="real Generation Round acceptance is opt-in; set INK_RUN_REAL_LLM_TESTS=1",
)
def test_real_generation_round_drives_to_legal_terminal(gateway_conn, provider):
    """Drive a full real-model round; assert it reaches a legal terminal state
    and that real LLM calls were recorded."""
    conn, repo, round_id = gateway_conn
    gateway = LLMGateway(conn, provider=provider, provider_name="iflytek")

    driver = GenerationRoundDriver(
        conn,
        repo,
        generation_port=RealGenerationPort(
            gateway, project_id=PROJECT_ID, chapter_brief=CHAPTER_BRIEF
        ),
        validation_port=RealValidationPort(gateway, project_id=PROJECT_ID),
        selection_port=RealSelectionPort(gateway, project_id=PROJECT_ID),
    )

    outcome = driver.drive(round_id=round_id)

    legal = {"selected", "candidate_shortage", "diversity_shortage", "failed"}
    assert outcome.final_status in legal, (
        f"real round reached non-legal status {outcome.final_status!r}; "
        f"failure_reason={outcome.failure_reason!r}"
    )
    # 真实模型确实被调用：至少初始 3 候选 generation 调用。
    assert outcome.call_count > 0, "real round recorded zero LLM calls"

    # writing_ai_call_attempts 表有真实模型名（role-chain tier 的 model_name）的成功调用记录。
    real_model_calls = conn.execute(
        """
        SELECT COUNT(*) FROM writing_ai_call_attempts
        WHERE project_id = ? AND success = 1
          AND model_name IN (?, ?, ?, ?, ?, ?)
        """,
        (PROJECT_ID, *WRITER_POOL, *JURY_POOL[:3]),
    ).fetchone()[0]
    assert real_model_calls > 0, (
        "no successful writing_ai_call_attempts row recorded a real iFLYTEK model call"
    )

    # 若抵达 selected，断言恰好一个 winner 被选中。
    if outcome.final_status == "selected":
        winners = conn.execute(
            """
            SELECT COUNT(*) FROM writing_chapter_candidate_branches
            WHERE generation_round_id = ? AND status = 'selected'
            """,
            (round_id,),
        ).fetchone()[0]
        assert winners == 1, f"selected round has {winners} winners, expected 1"
