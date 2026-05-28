"""
Decision Critic Skill
=====================
批评者视角：挑战假设，识别盲�?"""

import structlog
from typing import Dict, Any
from ..base import BaseSkill, SkillCategory, SkillParameter, SkillResult

logger = structlog.get_logger(__name__)

class DecisionCriticSkill(BaseSkill):
    """决策批评�?Skill"""
    
    def __init__(self, llm_client=None):
        super().__init__(
            name="decision_critic",
            description="批评者视角：挑战假设，识别盲点和风险",
            category=SkillCategory.LLM,
            version="1.0.0",
            parameters=[
                SkillParameter(name="problem", type="string", required=True),
                SkillParameter(name="context", type="object", required=False)
            ]
        )
        self.llm_client = llm_client
    
    async def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> SkillResult:
        """执行批评者视角分�?""
        problem = params.get("problem", "")
        
        logger.info("decision_critic.execute", problem_length=len(problem))
        
        try:
            result = {
                "role": "critic",
                "assumptions_challenged": [
                    "假设1: 当前情况会持续不�?,
                    "假设2: 只有这两个选项"
                ],
                "blind_spots": [
                    "可能忽略的第三种可能�?,
                    "未考虑的机会成�?
                ],
                "risks": [
                    {"risk": "决策延迟风险", "severity": "medium"},
                    {"risk": "信息不完整风�?, "severity": "low"}
                ],
                "devil_advocate_questions": [
                    "如果这个决定完全错误，最坏的结果是什么？",
                    "有没有你故意不去想的选项�?
                ]
            }
            return SkillResult.success(result)
        except Exception as e:
            logger.error("decision_critic.error", error=str(e))
            return SkillResult.failure(f"Skill/Critic/ExecutionError: {e}")
