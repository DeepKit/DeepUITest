"""
Decision Observer Skill
=======================
观察者视角：客观分析，识别模式
"""

import structlog
import json
import re
from typing import Dict, Any
from ..base import BaseSkill, SkillCategory, SkillParameter, SkillResult
from .scenarios import get_scenario_focus

logger = structlog.get_logger(__name__)

OBSERVER_SYSTEM_PROMPT = """你是一位决策观察者分析师。你的角色是：
1. 客观分析决策模式和外部因素
2. 识别决策类型与时间窗口
3. 提供客观观察而不是主观建议
4. 引用类似的成功转型案例模式

输出 JSON 对象：
- decision_patterns: 决策模式列表
- external_factors: 外部因素列表 (factor, impact, weight)
- similar_cases: 类似案例
- objective_observations: 客观观察

重要：只输出一个 JSON 对象，不要 Markdown，不要代码围栏，不要额外解释。
"""

class DecisionObserverSkill(BaseSkill):
    """决策观察者 Skill"""
    
    def __init__(self, llm_client=None):
        super().__init__(
            name="decision_observer",
            description="观察者视角：客观分析决策模式和外部因素",
            category=SkillCategory.LLM,
            version="1.0.0",
            parameters=[
                SkillParameter(
                    name="problem",
                    type="string",
                    description="用户的决策问题",
                    required=True
                ),
                SkillParameter(
                    name="context",
                    type="object",
                    description="上下文信息",
                    required=False
                )
            ]
        )
        self.llm_client = llm_client
    
    async def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> SkillResult:
        """执行观察者视角分析"""
        problem = params.get("problem", "")
        input_context = params.get("context", {})
        
        logger.info("decision_observer.execute", problem_length=len(problem))
        
        try:
            # 构建提示词（T8: 按场景模板注入差异化聚焦）
            scene_focus = get_scenario_focus(input_context, "observer")
            prompt = f"""问题：{problem}

背景信息：{input_context.get('background', '无')}
{scene_focus}
请以观察者视角分析这个决策问题。"""
            
            # 调用 LLM (如果可用)，失败时降级到模板
            if self.llm_client:
                try:
                    response = await self.llm_client.chat(
                        system=OBSERVER_SYSTEM_PROMPT,
                        user=prompt
                    )
                    result = self._parse_response(response.content)
                    if "raw_analysis" in result:
                        # LLM 输出无法解析为 JSON → 降级到模板（防假绿）
                        truncated = getattr(response, "truncated", False)
                        logger.warning("decision_observer.llm_not_json",
                                      response_preview=response.content[:200],
                                      truncated=truncated)
                        result = self._generate_template_result(problem)
                        result["degraded"] = True
                        result["degrade_reason"] = (
                            "llm_response_truncated" if truncated else "llm_response_not_json"
                        )
                    else:
                        result["degraded"] = False
                except Exception as e:
                    logger.warning("decision_observer.llm_fallback", error=str(e))
                    result = self._generate_template_result(problem)
                    result["degraded"] = True
                    result["degrade_reason"] = str(e)
            else:
                result = self._generate_template_result(problem)
                result["degraded"] = True
                result["degrade_reason"] = "llm_client_not_configured"
            
            return SkillResult.success(result)
        except Exception as e:
            logger.error("decision_observer.error", error=str(e))
            return SkillResult.failure(f"Skill/Observer/ExecutionError: {e}")
    
    def _parse_response(self, response: str) -> Dict[str, Any]:
        """解析 LLM 响应（支持 JSON 围栏提取与容错）"""
        # 通用提取：先找围栏，再找裸 JSON
        m = re.search(r"```json\s*\n?([\s\S]*?)\n?```", response)
        if m:
            try:
                parsed = json.loads(m.group(1))
                parsed.setdefault("role", "observer")
                return parsed
            except Exception:
                pass
        m = re.search(r"\{[\s\S]*\}", response)
        if m:
            try:
                parsed = json.loads(m.group(0))
                parsed.setdefault("role", "observer")
                return parsed
            except Exception:
                pass
        # 无法解析时返回原始分析（调用方据此判断降级）
        return {
            "role": "observer",
            "decision_patterns": [],
            "external_factors": [],
            "similar_cases": [],
            "objective_observations": [],
            "raw_analysis": response
        }
    
    def _generate_template_result(self, problem: str) -> Dict[str, Any]:
        """生成模板结果（降级模式）"""
        return {
            "role": "observer",
            "decision_patterns": [
                "这是一个典型的'安全 vs 成长'类型的决策",
                "决策时间窗口：中期（3-6个月内需要决定）"
            ],
            "external_factors": [
                {"factor": "行业趋势", "impact": "positive", "weight": 0.6},
                {"factor": "经济环境", "impact": "neutral", "weight": 0.3},
                {"factor": "个人财务状况", "impact": "constraining", "weight": 0.7}
            ],
            "similar_cases": [
                "很多人在职业中期会面临类似的选择",
                "成功转型的关键因素通常是准备时间和财务缓冲"
            ],
            "objective_observations": [
                "你已经在这个问题上思考了较长时间",
                "你收集了一定的信息但可能还不够完整"
            ]
        }
