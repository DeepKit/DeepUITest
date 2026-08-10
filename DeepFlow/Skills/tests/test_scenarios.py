# -*- coding: utf-8 -*-
"""
T8 场景模板单元测试（Skills/tests/test_scenarios.py）
=====================================================
验证场景知识库与角色 prompt 注入：
- get_scenario_focus：模板匹配 / 空 context / 未知模板
- 四角色（coach/critic/mirror/observer）按 decision_type 注入差异化聚焦
- 无 context 时向后兼容（prompt 不含场景段）

运行：cd Skills && python -X utf8 tests/test_scenarios.py
"""
import asyncio
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from skills.insight.scenarios import get_scenario_focus, list_scenarios
from skills.insight.coach import DecisionCoachSkill
from skills.insight.critic import DecisionCriticSkill
from skills.insight.mirror import DecisionMirrorSkill
from skills.insight.observer import DecisionObserverSkill

captured = {}


class MockResp:
    content = '{"key_DeepInsights": ["a"], "guiding_questions": ["q"], "values_detected": [], "emotional_tone": "x"}'


class MockLLM:
    async def chat(self, system, user, **kw):
        captured['user'] = user
        return MockResp()


def test_focus_basics():
    assert list_scenarios() == {
        'strategic': '战略决策', 'investment': '投资决策',
        'personnel': '人事决策', 'procurement': '采购决策',
        'medical': '医疗健康', 'legal': '法律纠纷',
        'education': '教育升学', 'family': '家庭重大',
    }
    f1 = get_scenario_focus({'decision_type': 'investment', 'scope': 'capital-allocation'}, 'coach')
    assert '投资决策' in f1 and '回本周期' in f1
    assert get_scenario_focus({}, 'coach') == ''
    assert get_scenario_focus({'decision_type': 'unknown'}, 'critic') == ''
    assert get_scenario_focus({'decision_type': 'strategic'}, 'film') == ''  # 非四角色
    assert get_scenario_focus(None, 'coach') == ''  # 非法输入
    print('[PASS] get_scenario_focus 基础验证')


def test_new_templates_focus():
    # T12: 新增 4 模板（医疗/法律/教育/家庭）× 四角色聚焦均应非空且含模板名
    for dtype, cname in [('medical', '医疗健康'), ('legal', '法律纠纷'), ('education', '教育升学'), ('family', '家庭重大')]:
        for role in ('coach', 'critic', 'mirror', 'observer'):
            f = get_scenario_focus({'decision_type': dtype}, role)
            assert f and cname in f, f'{dtype}/{role} 聚焦缺失'
    # 抽验具体内容（哲学中立：只提供焦点）
    assert '第二诊疗意见' in get_scenario_focus({'decision_type': 'medical'}, 'coach')
    assert '证据链' in get_scenario_focus({'decision_type': 'legal'}, 'critic')
    assert '焦虑贩卖' in get_scenario_focus({'decision_type': 'education'}, 'critic')
    assert '收入中断' in get_scenario_focus({'decision_type': 'family'}, 'critic')
    print('[PASS] T12 新增 4 模板四角色聚焦验证')


async def test_role_injection():
    # coach + investment
    r = await DecisionCoachSkill(llm_client=MockLLM()).execute(
        {'problem': '测试问题', 'context': {'decision_type': 'investment'}}, {})
    assert r.status.value == 'success'
    assert '场景模板：投资决策' in captured['user']
    assert '最大可承受损失' in captured['user']
    print('[PASS] coach 注入 (investment 聚焦)')

    # critic + strategic
    await DecisionCriticSkill(llm_client=MockLLM()).execute(
        {'problem': '测试问题', 'context': {'decision_type': 'strategic'}}, {})
    assert '高估自身执行力' in captured['user']
    print('[PASS] critic 注入 (strategic 聚焦)')

    # mirror + personnel
    await DecisionMirrorSkill(llm_client=MockLLM()).execute(
        {'problem': '测试问题', 'context': {'decision_type': 'personnel'}}, {})
    assert '内疚与决断' in captured['user']
    print('[PASS] mirror 注入 (personnel 聚焦)')

    # observer + procurement
    await DecisionObserverSkill(llm_client=MockLLM()).execute(
        {'problem': '测试问题', 'context': {'decision_type': 'procurement'}}, {})
    assert '各候选报价' in captured['user']
    print('[PASS] observer 注入 (procurement 聚焦)')

    # 无 context 向后兼容
    await DecisionCoachSkill(llm_client=MockLLM()).execute({'problem': '测试问题'}, {})
    assert '场景模板' not in captured['user']
    print('[PASS] 无模板向后兼容')

    # T12: 新模板真实注入验证（observer + medical，coach + family）
    await DecisionObserverSkill(llm_client=MockLLM()).execute(
        {'problem': '测试问题', 'context': {'decision_type': 'medical'}}, {})
    assert '诊断报告' in captured['user']
    print('[PASS] observer 注入 (medical 聚焦)')
    await DecisionCoachSkill(llm_client=MockLLM()).execute(
        {'problem': '测试问题', 'context': {'decision_type': 'family'}}, {})
    assert '财务上是否可持续' in captured['user']
    print('[PASS] coach 注入 (family 聚焦)')


if __name__ == '__main__':
    test_focus_basics()
    test_new_templates_focus()
    asyncio.run(test_role_injection())
    print('ALL SCENARIO TESTS PASSED')
