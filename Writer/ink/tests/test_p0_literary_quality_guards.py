from __future__ import annotations

import json

from factories import NOW, insert_minimal_draft, make_schema_db
from ink.core.chapter_continuity import load_continuity_context, render_continuity_section
from ink.pipeline.chapter_review_orchestrator import (
    CHAPTER_REVIEW_DIMENSIONS,
    _parse_chapter_scores,
    _parse_industrial_drift,
)
from ink.pipeline.outline_orchestrator import _outline_prompt


def test_continuity_context_prefers_previous_shot_and_uses_current_text_view() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    conn.execute(
        """
        INSERT INTO writing_shot_revisions
            (shot_id, run_id, revision_sequence, text, is_current, sealed_by, created_at)
        VALUES (?, 20, 1, ?, 0, 'shot_soft', ?)
        """,
        (ids["shot_id"], "上一场结尾：许怀山关掉白灯，门外脚步停住。", NOW),
    )
    cur = conn.execute(
        """
        INSERT INTO writing_shot_contracts
            (project_id, chapter_id, run_id, logical_shot_id, created_at, updated_at)
        VALUES (1, 1, 20, 'shot-002', ?, ?)
        """,
        (NOW, NOW),
    )
    current_contract_id = int(cur.lastrowid)
    conn.execute(
        """
        INSERT INTO writing_shots
            (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id,
             status, created_at, updated_at)
        VALUES ('shot-002@20', 1, 1, ?, 20, 'shot-002', 'pending', ?, ?)
        """,
        (current_contract_id, NOW, NOW),
    )

    context = load_continuity_context(conn, "shot-002@20", 20)

    assert context is not None
    assert context.source_kind == "previous_shot"
    assert context.source_shot_id == ids["shot_id"]
    assert "许怀山关掉白灯" in context.tail_text
    rendered = render_continuity_section(context)
    assert "同章上一 shot" in rendered
    assert "禁止在末段偷换 POV" in rendered


def test_outline_prompt_carries_hard_continuity_and_pov_lock() -> None:
    prompt = _outline_prompt(
        "许怀山检查第十七批密封件",
        2,
        continuity_section="【连续性硬约束】\n上一状态原文末尾：门外脚步停住。\n",
        pov_only=["许怀山"],
    )

    assert "POV 硬锁: 许怀山" in prompt
    assert "门外脚步停住" in prompt
    assert "先写“如何承接上一状态”" in prompt
    assert "禁止在末段偷换 POV" not in prompt  # 该措辞在连续性 section 中按实际上下文注入
    assert "不得新增契约外 POV" in prompt


def test_chapter_score_parser_exposes_pov_tail_and_continuity_hard_audits() -> None:
    payload = {name: 90 for name in CHAPTER_REVIEW_DIMENSIONS}
    payload.update(
        {
            "pov_consistency": 58,
            "chapter_continuity_hard": 55,
            "review_notes": "末段从许怀山切到林远征，开头也未承接上一章。",
            "pov_tail_audit": {
                "violation": True,
                "expected_pov": "许怀山",
                "observed_pov": "林远征",
                "transition_anchor": "",
                "evidence": "末段进入林远征的记忆与判断。",
            },
            "continuity_audit": {
                "violation": True,
                "transition_anchor": "",
                "evidence": "上一章门外脚步悬念被直接丢弃。",
            },
        }
    )

    scores, notes, audit = _parse_chapter_scores(json.dumps(payload, ensure_ascii=False))

    assert scores["pov_consistency"] == 58
    assert "林远征" in notes
    assert audit.pov_tail_violation is True
    assert "expected=许怀山" in audit.pov_tail_evidence
    assert audit.continuity_violation is True
    assert "直接丢弃" in audit.continuity_evidence


def test_industrial_observation_only_is_not_misclassified_as_vague_mechanism() -> None:
    response = {
        "drift": True,
        "drift_type": "failure_mechanism_vague",
        "claim_mode": "observation_only",
        "observable_anchors": ["裂纹像蛛网", "前线露天堆放数日"],
        "causal_chain": [],
        "missing_requirements": ["尚未解释根因"],
        "baseline_conflict": "",
        "confidence": 0.93,
        "evidence_sentence": "密封件表面的微裂纹像蛛网。",
    }

    assert _parse_industrial_drift(json.dumps(response, ensure_ascii=False)) == (None, "")


def test_industrial_causal_claim_without_observable_chain_is_blocked() -> None:
    response = {
        "drift": True,
        "drift_type": "failure_mechanism_vague",
        "claim_mode": "causal_claim",
        "observable_anchors": [],
        "causal_chain": [],
        "missing_requirements": ["缺少可观测工艺参数", "缺少条件到缺陷的因果链"],
        "baseline_conflict": "",
        "confidence": 0.94,
        "evidence_sentence": "这种异常是湿热导致的，却没有给出任何参数。",
    }

    drift_type, evidence = _parse_industrial_drift(json.dumps(response, ensure_ascii=False))

    assert drift_type == "failure_mechanism_vague"
    assert "湿热导致" in evidence


def test_industrial_background_condition_is_not_promoted_to_causal_claim() -> None:
    response = {
        "drift": True,
        "drift_type": "failure_mechanism_vague",
        "claim_mode": "causal_claim",
        "observable_anchors": ["露天堆放至少四天"],
        "causal_chain": [],
        "missing_requirements": ["未解释材料变化"],
        "baseline_conflict": "",
        "confidence": 0.91,
        "evidence_sentence": "前线卸货之后露天堆放，至少四天。",
    }

    assert _parse_industrial_drift(json.dumps(response, ensure_ascii=False)) == (None, "")
