"""
Decision Coach Skill
====================
教练视角：通过引导式提问帮助用户厘清想�?"""

import structlog
from typing import Dict, Any, List
from ..base import BaseSkill, SkillCategory, SkillParameter, SkillResult

logger = structlog.get_logger(__name__)

COACH_SYSTEM_PROMPT = """你是一位专业的决策教练。你的角色是�?1. 通过开放式问题帮助用户厘清想法
2. 不直接给出答案，而是引导用户自己发现
3. 关注用户的价值观和长期目�?4. 识别用户话语中的关键词和情绪

输出格式�?- key_DeepInsights: 用户表达中的关键洞察�?-5 条）
- guiding_questions: 引导性问题（3-5 个）
- values_detected: 检测到的价值观
- emotional_tone: 情绪基调
"""

class DecisionCoachSkill(BaseSkill):
    """决策教练 Skill"""
    
    def __init__(self, llm_client=None):
        super().__init__(
            name="decision_coach",
            description="教练视角：引导式提问，挖掘用户真实想�?,
            category=SkillCategory.LLM,
            version="1.0.0",
            parameters=[
                SkillParameter(
                    name="problem",
                    type="string",
                    description="用户的决策问�?,
                    required=True
                ),
                SkillParameter(
                    name="context",
                    type="object",
                    description="上下文信�?,
                    required=False
                )
            ]
        )
        self.llm_client = llm_client
    
    async def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> SkillResult:
        """执行教练视角分析"""
        problem = params.get("problem", "")
        input_context = params.get("context", {})
        
        logger.info("decision_coach.execute", problem_length=len(problem))
        
        try:
            # 构建提示�?            prompt = f"""问题：{problem}

背景信息：{input_context.get('background', '�?)}

请以教练视角分析这个决策问题�?""
            
            # 调用 LLM (如果可用)
            if self.llm_client:
                response = await self.llm_client.chat(
                    system=COACH_SYSTEM_PROMPT,
                    user=prompt
                )
                result = self._parse_response(response)
            else:
                # 降级模式：返回模板结�?                result = self._generate_template_result(problem)
            
            return SkillResult.success(result)
            
        except Exception as e:
            logger.error("decision_coach.error", error=str(e))
            return SkillResult.failure(
                f"Skill/Coach/ExecutionError: {e}"
            )
    
    def _parse_response(self, response: str) -> Dict[str, Any]:
        """解析 LLM 响应"""
        # TODO: 实现 JSON 解析逻辑
        return {
            "role": "coach",
            "key_DeepInsights": [],
            "guiding_questions": [],
            "values_detected": [],
            "emotional_tone": "neutral",
            "raw_analysis": response
        }
    
    def _generate_template_result(self, problem: str) -> Dict[str, Any]:
        """生成模板结果（降级模式）"""
        return {
            "role": "coach",
            "key_DeepInsights": [
                "用户正在面临一个重要的决策",
                "这个决策涉及到个人价值观和长期规�?
            ],
            "guiding_questions": [
                "如果没有任何限制，你最想做什么？",
                "这个决策对你来说，最重要的因素是什么？",
                "五年后回看这个决定，你希望自己做出了什么选择�?
            ],
            "values_detected": ["成长", "安全", "自由"],
            "emotional_tone": "thoughtful"
        }
