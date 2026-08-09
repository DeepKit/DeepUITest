# -*- coding: utf-8 -*-
"""
T10 胶片视觉字段单元测试（Skills/tests/test_film_visual.py）
====================================================================
验证 film_generator 视觉化字段契约：
- key_insights / tradeoffs / emotional_spectrum / decision_readiness
- LLM 输出含视觉字段 → 原样保留
- LLM 输出缺字段 → 从聚合结果兜底（不伪造）
- LLM 输出非法 → 模板降级仍含视觉字段
- intensity 规范化（非 0-100 数值 → None）

运行：cd Skills && python -X utf8 tests/test_film_visual.py
"""
import asyncio, sys
sys.path.insert(0, 'src')
from skills.insight.film_generator import FilmGeneratorSkill

AGGREGATED = {
    "key_DeepInsights": ["洞察A：现金储备可支撑一年", "洞察B：扩张速度超行业均值", "洞察C：团队复制能力待验证"],
    "self_questions": ["问1", "问2"],
    "emotional_summary": {
        "primary_emotion": "期待",
        "secondary_emotions": ["焦虑", "兴奋"],
        "intensity": "high",
    },
    "views": [{"role": "coach", "summary": "教练视角摘要"}],
}

# 1) LLM 输出含完整视觉字段 → 原样保留
class FullResp:
    content = (
        '{"title":"扩店胶片","key_insights":["洞察X","洞察Y"],'
        '"tradeoffs":[{"choice":"扩店","pros":["规模效应"],"cons":["管理半径"]}],'
        '"emotional_spectrum":[{"emotion":"期待","intensity":80},{"emotion":"焦虑","intensity":40}],'
        '"decision_readiness":62,"sections":[],"self_questions":["q"],"closing_note":"c"}'
    )
class FullLLM:
    async def chat(self, **kw): return FullResp()

async def t_full():
    res = await FilmGeneratorSkill(llm_client=FullLLM()).execute({"problem": "要不要扩店？", "aggregated": AGGREGATED}, {})
    f = res.data
    assert f["degraded"] is False
    assert f["key_insights"] == ["洞察X", "洞察Y"], f["key_insights"]
    assert f["tradeoffs"][0]["choice"] == "扩店" and f["tradeoffs"][0]["cons"] == ["管理半径"]
    assert f["emotional_spectrum"] == [{"emotion": "期待", "intensity": 80}, {"emotion": "焦虑", "intensity": 40}]
    assert f["decision_readiness"] == 62
    print("[PASS] LLM 完整视觉字段原样保留")

# 2) LLM 输出缺视觉字段 → 从聚合结果兜底
class NoVisualResp:
    content = '{"title":"T","subtitle":"S","sections":[{"name":"n","content":["c"]}],"self_questions":["q"],"closing_note":"c"}'
class NoVisualLLM:
    async def chat(self, **kw): return NoVisualResp()

async def t_fallback():
    res = await FilmGeneratorSkill(llm_client=NoVisualLLM()).execute({"problem": "要不要扩店？", "aggregated": AGGREGATED}, {})
    f = res.data
    assert f["degraded"] is False
    # key_insights 从聚合洞察兜底（前 4 条）
    assert f["key_insights"] == ["洞察A：现金储备可支撑一年", "洞察B：扩张速度超行业均值", "洞察C：团队复制能力待验证"]
    # tradeoffs 不伪造 → 空列表
    assert f["tradeoffs"] == []
    # 情绪谱从 emotional_summary 映射，强度未知 → None（不编造）
    assert f["emotional_spectrum"] == [
        {"emotion": "期待", "intensity": None},
        {"emotion": "焦虑", "intensity": None},
        {"emotion": "兴奋", "intensity": None},
    ]
    # 决策成熟度不伪造 → None
    assert f["decision_readiness"] is None
    print("[PASS] 缺字段从聚合兑底，强度/成熟度不编造")

# 3) LLM 输出非法 JSON → 模板降级仍含视觉字段
class BadResp:
    content = "这不是 JSON"
class BadLLM:
    async def chat(self, **kw): return BadResp()

async def t_degraded():
    res = await FilmGeneratorSkill(llm_client=BadLLM()).execute({"problem": "要不要扩店？", "aggregated": AGGREGATED}, {})
    f = res.data
    assert f["degraded"] is True and f["degrade_reason"] == "llm_response_not_json"
    assert isinstance(f["key_insights"], list) and len(f["key_insights"]) == 3
    assert f["tradeoffs"] == []
    assert f["decision_readiness"] is None
    assert isinstance(f["emotional_spectrum"], list)
    print("[PASS] 模板降级仍含视觉字段契约")

# 4) intensity 规范化：越界数值 → None
class BadIntensityResp:
    content = '{"key_insights":["a"],"emotional_spectrum":[{"emotion":"狂喜","intensity":150},{"emotion":"平静","intensity":"high"}],"self_questions":["q"],"closing_note":"c"}'
class BadIntensityLLM:
    async def chat(self, **kw): return BadIntensityResp()

async def t_normalize():
    res = await FilmGeneratorSkill(llm_client=BadIntensityLLM()).execute({"problem": "p", "aggregated": AGGREGATED}, {})
    f = res.data
    items = f["emotional_spectrum"]
    assert items[0]["intensity"] is None, items[0]  # 150 越界
    assert items[1]["intensity"] is None, items[1]  # 非数值
    print("[PASS] intensity 越界/非数值规范化为 None")

# 5) 哲学校验仍生效：禁用短语触发 disclaimer 修正
class ForbiddenResp:
    content = '{"key_insights":["你应该立刻扩店"],"self_questions":["q"],"closing_note":"c"}'
class ForbiddenLLM:
    async def chat(self, **kw): return ForbiddenResp()

async def t_philosophy():
    res = await FilmGeneratorSkill(llm_client=ForbiddenLLM()).execute({"problem": "p", "aggregated": AGGREGATED}, {})
    f = res.data
    assert "disclaimer" in f, "禁用短语应触发免责声明修正"
    print("[PASS] 哲学校验仍生效")

async def main():
    await t_full()
    await t_fallback()
    await t_degraded()
    await t_normalize()
    await t_philosophy()
    print("T10 FILM VISUAL UNIT CHECKS PASSED")

asyncio.run(main())
