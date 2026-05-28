"""
Decision Aggregator Skill
=========================
聚合器：综合多视角结�?"""

import structlog
from typing import Dict, Any, List
from ..base import BaseSkill, SkillCategory, SkillParameter, SkillResult

logger = structlog.get_logger(__name__)

class DecisionAggregatorSkill(BaseSkill):
    """决策聚合�?Skill"""
    
    def __init__(self, llm_client=None):
        super().__init__(
            name="decision_aggregator",
            description="综合多视角分析结果，生成结构化视角列�?,
            category=SkillCategory.LLM,
            version="1.0.0",
            parameters=[
                SkillParameter(name="coach_view", type="object", required=True),
                SkillParameter(name="critic_view", type="object", required=True),
                SkillParameter(name="mirror_view", type="object", required=True),
                SkillParameter(name="observer_view", type="object", required=True)
            ]
        )
        self.llm_client = llm_client
    
    async def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> SkillResult:
        """聚合多视角结�?""
        coach = params.get("coach_view", {})
        critic = params.get("critic_view", {})
        mirror = params.get("mirror_view", {})
        observer = params.get("observer_view", {})
        
        logger.info("decision_aggregator.execute")
        
        try:
            # 提取关键洞察
            all_DeepInsights = []
            all_DeepInsights.extend(coach.get("key_DeepInsights", []))
            all_DeepInsights.extend(critic.get("assumptions_challenged", []))
            all_DeepInsights.extend(mirror.get("identity_aspects", []))
            all_DeepInsights.extend(observer.get("decision_patterns", []))
            
            # 提取所有问�?            all_questions = []
            all_questions.extend(coach.get("guiding_questions", []))
            all_questions.extend(critic.get("devil_advocate_questions", []))
            all_questions.extend(mirror.get("reflection_prompts", []))
            
            # 计算共识和分�?            result = {
                "views": [
                    {"role": "coach", "summary": self._summarize_view(coach)},
                    {"role": "critic", "summary": self._summarize_view(critic)},
                    {"role": "mirror", "summary": self._summarize_view(mirror)},
                    {"role": "observer", "summary": self._summarize_view(observer)}
                ],
                "key_DeepInsights": all_DeepInsights[:5],  # Top 5
                "self_questions": all_questions[:5],  # Top 5
                "emotional_summary": mirror.get("emotional_landscape", {}),
                "risks": critic.get("risks", []),
                "consensus_points": [
                    "这是一个需要认真对待的决策",
                    "没有完美的选择，关键是找到最适合你的"
                ],
                "divergence_points": [
                    "关于风险的容忍度，不同视角有不同看法"
                ]
            }
            
            return SkillResult.success(result)
        except Exception as e:
            logger.error("decision_aggregator.error", error=str(e))
            return SkillResult.failure(f"Skill/Aggregator/ExecutionError: {e}")
    
    def _summarize_view(self, view: Dict[str, Any]) -> str:
        """生成视角摘要"""
        role = view.get("role", "unknown")
        summaries = {
            "coach": "教练视角关注你的内在动机和价值观",
            "critic": "批评者视角帮助你识别盲点和风�?,
            "mirror": "镜像视角反映你的情绪和内在冲�?,
            "observer": "观察者视角提供客观的模式分析"
        }
        return summaries.get(role, "未知视角")
