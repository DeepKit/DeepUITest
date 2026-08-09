"""
Decision Critic Skill
=====================
批评者视角：挑战假设，识别盲点
"""

import structlog
import json
import re
from typing import Dict, Any
from ..base import BaseSkill, SkillCategory, SkillParameter, SkillResult
from .scenarios import get_scenario_focus

logger = structlog.get_logger(__name__)

CRITIC_SYSTEM_PROMPT = """你是一位决策批评者。你的角色是：
1. 挑战假设，识别盲点
2. 寻找决策中的风险
3. 提出魔鬼代言人式问题
4. 不提供建议，只挑战思维

输出 JSON 对象：
- assumptions_challenged: 被挑战的假设列表
- blind_spots: 盲点列表
- risks: 风险列表 (risk, severity)
- devil_advocate_questions: 魔鬼代言人问题

重要：只输出一个 JSON 对象，不要 Markdown，不要代码围栏，不要额外解释。
"""

class DecisionCriticSkill(BaseSkill):
    """决策批评者 Skill"""
    
    def __init__(self, llm_client=None):
        super().__init__(
            name="decision_critic",
            description="批评者视角：挑战假设，识别盲点和风险",
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
        """执行批评者视角分析"""
        problem = params.get("problem", "")
        input_context = params.get("context", {})
        
        logger.info("decision_critic.execute", problem_length=len(problem))
        
        try:
            # 构建提示词（T8: 按场景模板注入差异化聚焦）
            scene_focus = get_scenario_focus(input_context, "critic")
            prompt = f"""问题：{problem}

背景信息：{input_context.get('background', '无')}
{scene_focus}
请以批评者视角分析这个决策问题。"""
            
            # 调用 LLM (如果可用)，失败时降级到模板
            if self.llm_client:
                try:
                    response = await self.llm_client.chat(
                        system=CRITIC_SYSTEM_PROMPT,
                        user=prompt
                    )
                    result = self._parse_response(response.content)
                    if "raw_analysis" in result:
                        # LLM 输出无法解析为 JSON → 降级到模板（防假绿）
                        truncated = getattr(response, "truncated", False)
                        logger.warning("decision_critic.llm_not_json",
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
                    logger.warning("decision_critic.llm_fallback", error=str(e))
                    result = self._generate_template_result(problem)
                    result["degraded"] = True
                    result["degrade_reason"] = str(e)
            else:
                result = self._generate_template_result(problem)
                result["degraded"] = True
                result["degrade_reason"] = "llm_client_not_configured"
            
            return SkillResult.success(result)
        except Exception as e:
            logger.error("decision_critic.error", error=str(e))
            return SkillResult.failure(f"Skill/Critic/ExecutionError: {e}")
    
    def _parse_response(self, response: str) -> Dict[str, Any]:
        """解析 LLM 响应（支持 JSON 围栏提取与容错）"""
        # 通用提取：先找围栏，再找裸 JSON
        m = re.search(r"```json\s*\n?([\s\S]*?)\n?```", response)
        if m:
            try:
                parsed = json.loads(m.group(1))
                parsed.setdefault("role", "critic")
                return parsed
            except Exception:
                pass
        m = re.search(r"\{[\s\S]*\}", response)
        if m:
            try:
                parsed = json.loads(m.group(0))
                parsed.setdefault("role", "critic")
                return parsed
            except Exception:
                pass
        # 无法解析时返回原始分析（调用方据此判断降级）
        return {
            "role": "critic",
            "assumptions_challenged": [],
            "blind_spots": [],
            "risks": [],
            "devil_advocate_questions": [],
            "raw_analysis": response
        }
    
    def _generate_template_result(self, problem: str) -> Dict[str, Any]:
        """生成模板结果（降级模式）"""
        return {
            "role": "critic",
            "assumptions_challenged": [
                "假设1: 当前情况会持续不变",
                "假设2: 只有这两个选项"
            ],
            "blind_spots": [
                "可能忽略的第三种可能性",
                "未考虑的机会成本"
            ],
            "risks": [
                {"risk": "决策延迟风险", "severity": "medium"},
                {"risk": "信息不完整风险", "severity": "low"}
            ],
            "devil_advocate_questions": [
                "如果这个决定完全错误，最坏的结果是什么？",
                "有没有你故意不去想的选项？"
            ]
        }
