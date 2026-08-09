# -*- coding: utf-8 -*-
"""
T9 LLM 截断降级诊断单元测试（Skills/tests/test_llm_truncation_diag.py）
====================================================================
验证：
- ChatResult.truncated 默认 False（向后兼容）
- 截断响应（finish_reason=length）→ degrade_reason=llm_response_truncated
- 非截断解析失败 → degrade_reason=llm_response_not_json

运行：cd Skills && python -X utf8 tests/test_llm_truncation_diag.py
"""
import asyncio, sys
sys.path.insert(0, 'src')
from llm.client import ChatResult
from skills.insight.coach import DecisionCoachSkill

# ChatResult truncated 默认 False（向后兼容）
r = ChatResult(content='x', model='m')
assert r.truncated is False and r.finish_reason == 'stop'
print('[PASS] ChatResult 向后兼容')

class TruncResp:
    content = '{"key_DeepInsights": ["被截断的 JSON'
    truncated = True
class TruncLLM:
    async def chat(self, **kw): return TruncResp()

class BadResp:
    content = '这不是 JSON'
    truncated = False
class BadLLM:
    async def chat(self, **kw): return BadResp()

async def t():
    res = await DecisionCoachSkill(llm_client=TruncLLM()).execute({'problem': '测试'}, {})
    d = res.data
    assert d['degraded'] is True and d['degrade_reason'] == 'llm_response_truncated', d
    print('[PASS] 截断降级诊断: degrade_reason=llm_response_truncated')
    res2 = await DecisionCoachSkill(llm_client=BadLLM()).execute({'problem': '测试'}, {})
    assert res2.data['degrade_reason'] == 'llm_response_not_json'
    print('[PASS] 非截断降级诊断: degrade_reason=llm_response_not_json')

asyncio.run(t())
print('T9 UNIT CHECKS PASSED')
