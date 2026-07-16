"""jury 真实化单测：验证 3 裁判真实调 gateway → 12 维分落 raw_scores + aggregate + median +
quality_gate 判定；LLM 全失败分流（直接 fail + 抛「调供应商」而非触发重写）。

与 test_m4_review_pipeline 的区别：m4 用 JuryScoreProvider 驱动桩语义；本文件聚焦
「真实 LLM 调用路径」的落库结构 + 失败分流边界，用 recording provider 验证 gateway.call
被调 3 次、raw_scores 落 3 行、aggregate final_score = 12 维 median 均值，以及
JuryLLMFailure 分流不触发重写。
"""

from __future__ import annotations

import json

import pytest

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.errors import DataIntegrityError
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.jury_orchestrator import JuryLLMFailure, JuryOrchestrator
from ink.pipeline.write_orchestrator import WriteOrchestrator
from ink.jury.scores import SCORE_COLUMNS

from test_m3_writer_pipeline import make_prompt_compiled_shot, _ids


def _twelve(score: int) -> str:
    return json.dumps({col: score for col in SCORE_COLUMNS}, ensure_ascii=False)


class RecordingJuryProvider:
    """记录每次 complete 的 (model_name, idempotency_key)，统一返回 12 维评分 JSON（全 84）。"""

    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        self.calls.append((model_name, idempotency_key))
        return ModelResult(text=_twelve(84), model_name=model_name, token_input=1, token_output=1)


class AlwaysFailJuryProvider:
    """每次 complete 抛 RuntimeError → gateway 注入式路径转 LLMProviderError → 3 裁判全失败。"""

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        raise RuntimeError("provider down")


class _PlainDraftProvider:
    """造 draft 文本用：返回固定普通文本（无桩标记），供 jury 评分测试的前置 write。"""

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        return ModelResult(
            text=f"scene text {model_name} {idempotency_key}",
            model_name=model_name,
            token_input=1,
            token_output=1,
        )


def _prepare_shot_with_drafts(*, draft_count: int = 1) -> tuple:
    conn = make_prompt_compiled_shot()
    ids = _ids(conn)
    if draft_count != 1:
        conn.execute("UPDATE writing_projects SET draft_count = ? WHERE project_id = 1", (draft_count,))
        conn.commit()
    WriteOrchestrator(conn, LLMGateway(conn, provider=_PlainDraftProvider())).produce_drafts(
        str(ids["shot_id"]), int(ids["run_id"])
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))
    return conn, ids


def test_three_judges_called_and_raw_scores_persisted_with_median() -> None:
    """3 裁判各调一次 gateway.call → raw_scores 落 3 行 → aggregate final_score = 12 维 median 均值。"""
    conn, ids = _prepare_shot_with_drafts()
    provider = RecordingJuryProvider()
    gateway = LLMGateway(conn, provider=provider)

    winner = JuryOrchestrator(conn, gateway).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

    # 每 draft 最多 3 裁判各调一次（注入式无 role_config，tier_hint 被忽略；deviant draft 不评）
    jury_calls = [c for c in provider.calls if c[1].startswith("jury:")]
    assert len(jury_calls) >= 3  # 至少一个 draft 的 3 裁判都被调
    # idempotency_key 含 slot：jury:{draft_id}:r1:{1,2,3}
    slots = {int(c[1].rsplit(":r1:", 1)[1]) for c in jury_calls if ":r1:" in c[1]}
    assert slots == {1, 2, 3}

    # raw_scores 落库（jury_round=1，至少 3 行 = 一个 draft 的 3 裁判）
    raw_count = conn.execute(
        "SELECT count(*) FROM writing_jury_raw_scores WHERE jury_round = 1"
    ).fetchone()[0]
    assert raw_count >= 3
    agg_count = conn.execute(
        "SELECT count(*) FROM writing_jury_aggregates"
    ).fetchone()[0]
    assert agg_count >= 1

    # aggregate：final_score = 12 维 median 均值（全 84 → 84.0），且恰有 1 winner
    agg = conn.execute(
        "SELECT final_score, quality_gate_passed, is_winner FROM writing_jury_aggregates"
    ).fetchall()
    assert len(agg) == agg_count
    assert all(row[0] == pytest.approx(84.0, abs=0.01) for row in agg)
    assert all(row[1] == 1 for row in agg)  # 全过 quality_floor 80
    assert sum(row[2] for row in agg) == 1  # 恰 1 winner
    assert winner is not None


def test_jury_llm_all_failure_transitions_failed_without_retry() -> None:
    """硬伤2：3 裁判 LLM 全失败 → 直接 transition failed + 抛「供应商」错，不触发重写。"""
    conn, ids = _prepare_shot_with_drafts()
    gateway = LLMGateway(conn, provider=AlwaysFailJuryProvider())

    # auto_retry_on_hard_failure 默认 1，但 LLM 失败分流应在 retry 之前直接 fail
    conn.execute("UPDATE writing_projects SET auto_retry_on_hard_failure = 1 WHERE project_id = 1")
    conn.commit()

    with pytest.raises(DataIntegrityError, match="LLM 调用失败"):
        JuryOrchestrator(conn, gateway).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

    status = conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0]
    assert status == "failed"
    # 未生成 retry draft（重写未被触发）
    retry_count = conn.execute("SELECT count(*) FROM writing_drafts WHERE retry_count = 1").fetchone()[0]
    assert retry_count == 0


def test_partial_judge_failure_treated_as_llm_failure() -> None:
    """3 裁判仅部分成功（<3）→ schema CHECK(judge_count>=3) 不允许落库 → 抛 JuryLLMFailure → 分流 fail。"""
    conn, ids = _prepare_shot_with_drafts(draft_count=3)
    # 3 draft 都部分失败（slot 1 抛错）→ 每个 judge_count<3 → 全 draft JuryLLMFailure → 分流 fail

    # 部分失败 provider：按 idempotency_key 的 slot，slot 1 抛错，slot 2/3 成功 → judge_count=2 <3
    class PartialFailProvider:
        def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
            slot = int(idempotency_key.rsplit(":r1:", 1)[1]) if ":r1:" in idempotency_key else 1
            if slot == 1:
                raise RuntimeError("slot1 down")
            return ModelResult(text=_twelve(84), model_name=model_name, token_input=1, token_output=1)

    gateway = LLMGateway(conn, provider=PartialFailProvider())
    with pytest.raises(DataIntegrityError, match="LLM 调用失败"):
        JuryOrchestrator(conn, gateway).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))

    status = conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0]
    assert status == "failed"
