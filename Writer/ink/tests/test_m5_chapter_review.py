from __future__ import annotations

import json

import pytest

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.core.text_repository import TextRepository
from ink.contract.loader import load_shot_contract
from ink.errors import DataIntegrityError
from ink.pipeline.chapter_review_orchestrator import CHAPTER_REVIEW_DIMENSIONS, ChapterReviewOrchestrator
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator
from ink.pipeline.jury_orchestrator import JuryOrchestrator
from ink.pipeline.polish_orchestrator import PolishOrchestrator
from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator
from test_m4_review_pipeline import PolishProvider, _jury_gateway, make_winner_selected_shot


# chapter_review 真实化后的评分 mock provider：按章文本里的���标记返回章级维度 JSON，
# 复现原桩语义（[chapter-fail]→rhythm_curve 低，[blind-fail]→chapter_continuity_hard 低，
# [reader-pull-fail]→chapter_hook_soft 低；无标记→全过）。
_CHAPTER_FAIL_DIM = {
    "chapter-fail": "rhythm_curve",
    "blind-fail": "chapter_continuity_hard",
    "reader-pull-fail": "chapter_hook_soft",
}


class ChapterReviewProvider:
    """注入式 chapter_review 评分 provider（测试用）。按章文本标记返回章级维度 JSON。

    标记映射见 ``_CHAPTER_FAIL_DIM``：命中标记的维度给 70（< 默认 floor 75 → blocking），
    其余给 92（过 floor）。无标记全 92。
    """

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        scores = {col: 92 for col in CHAPTER_REVIEW_DIMENSIONS}
        for marker, dim in _CHAPTER_FAIL_DIM.items():
            if marker in prompt_text:
                scores[dim] = 70
        text = json.dumps(scores | {"review_notes": "mock chapter review"}, ensure_ascii=False)
        return ModelResult(text=text, model_name=model_name, token_input=1, token_output=1)


def _chapter_review_gateway(conn) -> LLMGateway:
    return LLMGateway(conn, provider=ChapterReviewProvider())


def test_chapter_quality_gate_blocks_accept() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    conn.execute(
        "UPDATE writing_shot_revisions SET text = text || ' [chapter-fail]' WHERE sealed_by = 'shot_soft'"
    )

    review = ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))

    assert review.quality_gate_passed is False
    assert review.blocking_issues == ("rhythm_curve",)
    assert conn.execute(
        "SELECT quality_gate_passed, status, blocking_issues FROM writing_chapter_reviews"
    ).fetchone() == (0, "pending", '["rhythm_curve"]')
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "soft_sealed"
    assert conn.execute(
        "SELECT count(*) FROM writing_ai_call_attempts WHERE idempotency_key LIKE ?",
        (f"chapter_review:1:1:{ids['run_id']}:%",),
    ).fetchone()[0] == 3


def test_human_accept_cannot_override_quality_failure() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    conn.execute(
        "UPDATE writing_shot_revisions SET text = text || ' [chapter-fail]' WHERE sealed_by = 'shot_soft'"
    )
    ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))

    with pytest.raises(DataIntegrityError):
        HumanReviewOrchestrator(conn).accept_chapter(1, 1, int(ids["run_id"]), actor="author", reason="approve")

    assert conn.execute("SELECT count(*) FROM writing_human_decisions").fetchone()[0] == 0
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "soft_sealed"
    assert conn.execute("SELECT count(*) FROM writing_shot_revisions WHERE sealed_by = 'chapter_hard'").fetchone()[0] == 0


def test_blind_review_and_reader_pull_required() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    conn.execute(
        "UPDATE writing_shot_revisions SET text = text || ' [blind-fail] [reader-pull-fail]' WHERE sealed_by = 'shot_soft'"
    )

    review = ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))

    assert review.quality_gate_passed is False
    assert set(review.blocking_issues) == {"chapter_continuity_hard", "chapter_hook_soft"}
    with pytest.raises(DataIntegrityError):
        HumanReviewOrchestrator(conn).accept_chapter(1, 1, int(ids["run_id"]), actor="author", reason="approve")
    assert conn.execute("SELECT count(*) FROM writing_human_decisions").fetchone()[0] == 0


def test_human_accept_writes_decision_and_hard_seals_chapter() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    review = ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))

    decision_id = HumanReviewOrchestrator(conn).accept_chapter(
        1,
        1,
        int(ids["run_id"]),
        actor="author",
        reason="chapter quality passed",
    )

    assert review.quality_gate_passed is True
    assert conn.execute("SELECT status FROM writing_chapter_reviews WHERE review_id = ?", (review.review_id,)).fetchone()[0] == "accepted"
    decision = conn.execute(
        """
        SELECT decision_type, actor, reason, preconditions_json, quality_report_json, hard_quality_override
        FROM writing_human_decisions
        WHERE decision_id = ?
        """,
        (decision_id,),
    ).fetchone()
    assert decision[:3] == ("accept", "author", "chapter quality passed")
    assert json.loads(decision[3])["quality_gate_passed"] is True
    assert json.loads(decision[4])["evidence_class"] == "SEMI_ES"
    assert decision[5] == 0
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "hard_sealed"
    assert TextRepository(conn).is_hard_sealed(str(ids["shot_id"]), int(ids["run_id"])) is True
    assert conn.execute(
        "SELECT text, is_current FROM writing_shot_revisions WHERE sealed_by = 'chapter_hard'"
    ).fetchone() == ("polished text", 1)


def test_human_reject_writes_decision_without_hard_seal() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    review = ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))

    decision_id = HumanReviewOrchestrator(conn).reject_chapter(
        1,
        1,
        int(ids["run_id"]),
        actor="author",
        reason="reject this direction",
    )

    assert conn.execute("SELECT status FROM writing_chapter_reviews WHERE review_id = ?", (review.review_id,)).fetchone()[0] == "rejected"
    decision = conn.execute(
        """
        SELECT decision_type, actor, reason, preconditions_json
        FROM writing_human_decisions
        WHERE decision_id = ?
        """,
        (decision_id,),
    ).fetchone()
    assert decision[:3] == ("reject", "author", "reject this direction")
    assert json.loads(decision[3])["action"] == "reject"
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "soft_sealed"
    assert conn.execute("SELECT count(*) FROM writing_shot_revisions WHERE sealed_by = 'chapter_hard'").fetchone()[0] == 0


def test_human_revise_writes_decision_and_clones_chapter_run() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    review = ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))

    revised = HumanReviewOrchestrator(conn).revise_chapter(
        1,
        1,
        int(ids["run_id"]),
        actor="author",
        reason="revise chapter pacing",
    )

    assert conn.execute("SELECT status FROM writing_chapter_reviews WHERE review_id = ?", (review.review_id,)).fetchone()[0] == "revised"
    assert revised.run_id != ids["run_id"]
    assert revised.shot_ids == (f"shot-001@{revised.run_id}",)
    assert conn.execute(
        "SELECT project_id, session_id, run_attempt, status FROM writing_runs WHERE run_id = ?",
        (revised.run_id,),
    ).fetchone() == (1, 10, 2, "running")
    assert conn.execute(
        "SELECT logical_shot_id, status FROM writing_shots WHERE shot_id = ?",
        (revised.shot_ids[0],),
    ).fetchone() == ("shot-001", "pending")
    assert load_shot_contract(conn, revised.shot_ids[0], revised.run_id).must_land["events"] == ["她走进档案室"]
    decision = conn.execute(
        """
        SELECT decision_type, preconditions_json
        FROM writing_human_decisions
        WHERE decision_id = ?
        """,
        (revised.decision_id,),
    ).fetchone()
    preconditions = json.loads(decision[1])
    assert decision[0] == "revise"
    assert preconditions["new_run_id"] == revised.run_id
    assert preconditions["source_run_id"] == ids["run_id"]
    assert preconditions["new_shot_count"] == 1
    assert conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0] == "soft_sealed"
    assert conn.execute("SELECT count(*) FROM writing_shot_revisions WHERE sealed_by = 'chapter_hard'").fetchone()[0] == 0


def make_soft_sealed_chapter():
    conn = make_winner_selected_shot()
    ids = _ids(conn)
    PolishOrchestrator(conn, LLMGateway(conn, provider=PolishProvider())).polish_winner(
        str(ids["shot_id"]),
        int(ids["run_id"]),
    )
    HardGateOrchestrator(conn).run_both_gates(str(ids["shot_id"]), int(ids["run_id"]))
    JuryOrchestrator(conn, _jury_gateway(conn)).score_and_select_winner(str(ids["shot_id"]), int(ids["run_id"]))
    SoftSealOrchestrator(conn).soft_seal_if_polished(str(ids["shot_id"]), int(ids["run_id"]))
    return conn


def test_suspense_decay_below_floor_forces_reheat() -> None:
    """E13 悬疑张力衰减监控：章内 winner 行 suspense_tension_median 中位数低于回炉线（82）→ 强制回炉。

    不注入 chapter-fail 标记（章级 7 维全过），仅把 winner 行 suspense_tension_median
    改成 81 模拟 91→82 衰减后失张力的章节，断言唯一阻塞项为 suspense_decay。
    """
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    conn.execute(
        "UPDATE writing_jury_aggregates SET suspense_tension_median = 81.0 WHERE shot_id = ? AND is_winner = 1",
        (str(ids["shot_id"]),),
    )
    conn.commit()

    review = ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))

    assert review.quality_gate_passed is False
    assert review.blocking_issues == ("suspense_decay",)
    assert conn.execute(
        "SELECT blocking_issues FROM writing_chapter_reviews"
    ).fetchone()[0] == '["suspense_decay"]'


def test_suspense_decay_at_floor_passes() -> None:
    """悬疑张力恰等于回炉线（82）不触发回炉：严格 < 判定，边界值放行。"""
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    conn.execute(
        "UPDATE writing_jury_aggregates SET suspense_tension_median = 82.0 WHERE shot_id = ? AND is_winner = 1",
        (str(ids["shot_id"]),),
    )
    conn.commit()

    review = ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))

    assert "suspense_decay" not in review.blocking_issues


def _ids(conn):
    row = conn.execute(
        "SELECT shot_id, run_id FROM writing_shots WHERE logical_shot_id = 'shot-001'"
    ).fetchone()
    return {"shot_id": row[0], "run_id": row[1]}


# ---- 工业事实漂移硬校验（块C2 测试） -----------------------------------
from ink.source_workflow import SourceWorkflowStore  # noqa: E402


def _seed_industrial_baseline(conn) -> None:
    """灌最小工业事实基线到 fixture DB（task#19 工艺细节库的测试落点）。

    复用 seed_industrial_facts.py 的 CLAUSES 语义，但仅插够触发规则层 + LLM 兜底
    的两条：一条 forbidden [marker] 反向词表条目（供规则层硬匹配）、一条 process
    报废制度锚点（供 LLM 兜底对照）。文档级用唯一 source_path 避免与并发测试冲突。
    """
    store = SourceWorkflowStore(conn)
    doc_id = store.register_source_document(
        project_id=1,
        source_path="test://industrial_baseline",
        source_kind="guide",
        content_hash="test-industrial-baseline-v1",
        status="active",
    )
    store.record_atomic_clause(
        project_id=1, source_document_id=doc_id, scope_type="volume", scope_id="1",
        clause_type="forbidden", severity="soft",
        clause_text="[marker] 武侠化/仪式感压过工艺的表达：义薄云天、江湖、闻味即断、神探式一眼识破。",
        source_refs=["§测试"], source_hashes=["test-industrial-baseline-v1"], status="confirmed",
    )
    store.record_atomic_clause(
        project_id=1, source_document_id=doc_id, scope_type="volume", scope_id="1",
        clause_type="process", severity="hard",
        clause_text="签字表格无'最终后果'一栏——根本没有位置留给失效追责。",
        source_refs=["§测试"], source_hashes=["test-industrial-baseline-v1"], status="confirmed",
    )
    store.record_atomic_clause(
        project_id=1, source_document_id=doc_id, scope_type="volume", scope_id="1",
        clause_type="process", severity="hard",
        clause_text="[trigger] 工艺失效信号词：失效、报废、前线、押运、废品、退货、事故、信不过。",
        source_refs=["§测试"], source_hashes=["test-industrial-baseline-v1"], status="confirmed",
    )
    conn.commit()


def _set_chapter_text(conn, text: str) -> None:
    """改写本章 current 文本（v_current_text 视图取的那条 revision）为指定文本。

    v_current_text 取 is_current DESC、revision_sequence DESC 的 rn=1；polish 后 revision
    的 is_current=0，故 current 实为 revision_sequence 最大那条。改它即改检测器读到的文本。
    """
    conn.execute(
        """
        UPDATE writing_shot_revisions
        SET text = ?
        WHERE rowid = (
            SELECT rowid
            FROM writing_shot_revisions
            WHERE shot_id = (SELECT shot_id FROM writing_shots WHERE logical_shot_id = 'shot-001')
            ORDER BY is_current DESC, revision_sequence DESC
            LIMIT 1
        )
        """,
        (text,),
    )
    conn.commit()


class IndustrialDriftProvider:
    """注入式 provider：7 维评分 + 工业漂移判定双分支。

    按 prompt 开头分支：含「事实漂移审查员」→ 返回漂移判定 JSON；否则返回 7 维全过 JSON。
    复现 task#19 检测器的 LLM 兜底路径（规则层未命中后 gateway 实际调用的 prompt）。
    """

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        if "事实漂移审查员" in prompt_text:
            # 触发失效机理模糊判定（可疑段含"失效"但未说清制度事实）。
            payload = {
                "drift": True,
                "drift_type": "failure_mechanism_vague",
                "evidence_sentence": "他闻味即断，没看签字表。",
            }
        else:
            payload = {col: 92 for col in CHAPTER_REVIEW_DIMENSIONS}
            payload["review_notes"] = "mock chapter review"
        return ModelResult(text=json.dumps(payload, ensure_ascii=False), model_name=model_name, token_input=1, token_output=1)


def test_industrial_fact_drift_rule_marker_blocks() -> None:
    """规则层硬命中：章文本出现风格漂移 marker「义薄云天」→ 直接判漂移，不调漂移 LLM。

    7 维评分照常调 gateway（一次 chapter_review）；但 drift 检测器的 LLM 兜底必须短路
    ——marker 命中即阻断，不该再调一次「事实漂移审查员」prompt（省供应商调用）。
    用计数 provider 断言 drift prompt 零调用。
    """

    class _MarkerProvider(ChapterReviewProvider):
        drift_calls = 0

        def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
            if "事实漂移审查员" in prompt_text:
                _MarkerProvider.drift_calls += 1
                raise AssertionError("marker 命中应短路，不该调漂移 LLM")
            return super().complete(prompt_text, model_name, idempotency_key)

    conn = make_soft_sealed_chapter()
    _seed_industrial_baseline(conn)
    _set_chapter_text(conn, "他义薄云天地护着工友，把整批废品扛了下来。")
    ids = _ids(conn)

    review = ChapterReviewOrchestrator(conn, LLMGateway(conn, provider=_MarkerProvider())).review_chapter(
        1, 1, int(ids["run_id"])
    )

    assert review.quality_gate_passed is False
    assert "industrial_fact_drift" in review.blocking_issues
    assert _MarkerProvider.drift_calls == 0
    notes = conn.execute("SELECT review_notes FROM writing_chapter_reviews").fetchone()[0]
    assert "规则硬命中" in notes and "义薄云天" in notes


def test_industrial_fact_drift_llm_fallback_blocks() -> None:
    """LLM 兜底：可疑段含失效关键词但无 marker → 规则层放行，LLM 判 drift=true 阻断。

    验证 task#19 检测器的两层链路：规则层 forbidden marker 未命中 → 启发式筛可疑段
    （含"失效"）→ 调 chapter_review gateway → LLM 返回 failure_mechanism_vague → 阻断。
    """
    conn = make_soft_sealed_chapter()
    _seed_industrial_baseline(conn)
    # 无 marker，但含失效关键词且制度事实模糊（没提签字表）。
    _set_chapter_text(conn, "这批货在前线失效了。质检员老周叹口气，没多说。")
    ids = _ids(conn)

    review = ChapterReviewOrchestrator(conn, LLMGateway(conn, provider=IndustrialDriftProvider())).review_chapter(
        1, 1, int(ids["run_id"])
    )

    assert review.quality_gate_passed is False
    assert "industrial_fact_drift" in review.blocking_issues
    notes = conn.execute("SELECT review_notes FROM writing_chapter_reviews").fetchone()[0]
    assert "LLM 判定" in notes and "failure_mechanism_vague" in notes


def test_industrial_fact_drift_clean_passes() -> None:
    """无漂移：章文本无 marker 且无失效关键词 → 不触发可疑段，不调 LLM，不阻断。

    验证检测器在干净章节上的零误伤：无 forbidden marker、无失效关键词 → _suspicious_segments
    返回空 → 检测器返回 (None,None) 不阻断。7 维全过 → quality_gate_passed=True。
    """
    conn = make_soft_sealed_chapter()
    _seed_industrial_baseline(conn)
    _set_chapter_text(conn, "车间里酒精棉球的气味很淡。老周在签字，蓝黑墨水，三级都盖了章。")
    ids = _ids(conn)

    review = ChapterReviewOrchestrator(conn, _chapter_review_gateway(conn)).review_chapter(1, 1, int(ids["run_id"]))

    assert "industrial_fact_drift" not in review.blocking_issues
