"""Tests for shared exposition / explanation gate."""

from __future__ import annotations

from inkflow.services.exposition_gate import audit_exposition


def test_concrete_scene_passes_exposition_gate():
    text = (
        "林舟把手机扣回掌心，屏幕还亮着。排号灯从三十七跳到三十八，"
        "窗口里的人把章盖偏了一点。胶带贴在膝盖上，边缘被汗泡白。"
        "他没有问为什么，只把那张临时单重新折了一次，塞进票根后面。"
    )

    result = audit_exposition(text, strict=False)

    assert result["passed"] is True
    assert result["hard_violations"] == []


def test_system_resource_explanation_fails_exposition_gate():
    text = (
        "研究员低头看着手里的样本。他忽然想起调度系统的评估模型。"
        "那个看似公平的资源分配算法，把中心区和边缘区的人分成两套轨道。"
        "系统并不恶意，它只是精确地计算，把所有非核心、低效率、"
        "不产生直接回报的人力和资源筛出去。这个逻辑结构本质上是空的。"
    )

    result = audit_exposition(text, strict=False)

    assert result["passed"] is False
    codes = {item["code"] for item in result["hard_violations"]}
    assert "hard_exposition" in codes or "abstract_exposition_sentence" in codes


def test_strict_exposition_gate_allows_instruction_manual_object():
    text = (
        "许怀山把湿透的密封件放在木箱边上。常规运输条件。"
        "说明书上这么写的。雨水顺着纸角往下滴，他没有再说话。"
    )

    result = audit_exposition(text, strict=True)

    assert result["passed"] is True
    assert result["violations"] == []


def test_strict_exposition_gate_still_catches_explanation_connector():
    text = (
        "许怀山把湿透的密封件放在木箱边上。"
        "这说明系统的检查流程本质上已经失效。"
        "雨水顺着纸角往下滴，他没有再说话。"
    )

    result = audit_exposition(text, strict=True)

    assert result["passed"] is False
    assert any(
        item["code"] == "explanation_marker"
        for item in result["violations"]
    )


def test_strict_exposition_gate_ignores_soft_marker_inside_dialogue():
    text = (
        "高启明抹了一把脸上的雨水。"
        "“说明书上写的常规，跟咱们这儿的常规，大概不是一回事。”"
        "许怀山没有接话，只把密封件翻到裂纹那一面。"
    )

    result = audit_exposition(text, strict=True)

    assert result["passed"] is True
    assert result["violations"] == []
