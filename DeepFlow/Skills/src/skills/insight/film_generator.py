"""
Film Generator Skill
====================
胶片生成器：生成决策思维胶片

DeepInsight-003: 包含"产品哲学校验"规则
- 优先显影而非给结�?- 必须包含自我提问清单
- 语气温和，不强迫
"""

import structlog
from typing import Dict, Any, List
from ..base import BaseSkill, SkillCategory, SkillParameter, SkillResult

logger = structlog.get_logger(__name__)

# 产品哲学校验规则 (DeepInsight-003)
PHILOSOPHY_RULES = {
    "no_direct_conclusion": True,      # 不直接给�?你应�?.."的结�?    "require_self_questions": True,    # 必须包含自我提问清单
    "gentle_tone": True,               # 语气温和，使�?也许"�?可能"�?    "emphasize_process": True,         # 强调思考过程而非结果
}

FORBIDDEN_PHRASES = [
    "你应�?,
    "你必�?,
    "正确的选择�?,
    "最佳方案是",
    "我建议你",
]

class FilmGeneratorSkill(BaseSkill):
    """决策胶片生成�?Skill"""
    
    def __init__(self, llm_client=None):
        super().__init__(
            name="film_generator",
            description="生成决策思维胶片，强调显影而非结论",
            category=SkillCategory.LLM,
            version="1.0.0",
            parameters=[
                SkillParameter(name="problem", type="string", required=True),
                SkillParameter(name="aggregated", type="object", required=True)
            ]
        )
        self.llm_client = llm_client
    
    async def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> SkillResult:
        """生成决策胶片"""
        problem = params.get("problem", "")
        aggregated = params.get("aggregated", {})
        
        logger.info("film_generator.execute", problem_length=len(problem))
        
        try:
            # 生成胶片内容
            film = self._generate_film(problem, aggregated)
            
            # 产品哲学校验 (DeepInsight-003)
            validation = self._validate_philosophy(film)
            if not validation["passed"]:
                logger.warning("film_generator.philosophy_violation", 
                             violations=validation["violations"])
                # 修正违规内容
                film = self._fix_violations(film, validation["violations"])
            
            return SkillResult.success(film)
        except Exception as e:
            logger.error("film_generator.error", error=str(e))
            return SkillResult.failure(f"Skill/FilmGenerator/ExecutionError: {e}")
    
    def _generate_film(self, problem: str, aggregated: Dict) -> Dict[str, Any]:
        """生成胶片结构"""
        views = aggregated.get("views", [])
        DeepInsights = aggregated.get("key_DeepInsights", [])
        questions = aggregated.get("self_questions", [])
        emotional = aggregated.get("emotional_summary", {})
        
        return {
            "title": "你的决策思维胶片",
            "subtitle": f"关于：{problem[:50]}..." if len(problem) > 50 else f"关于：{problem}",
            "sections": [
                {
                    "name": "思维显影",
                    "description": "这是你思考过程的可视化呈�?,
                    "content": DeepInsights
                },
                {
                    "name": "多元视角",
                    "description": "从不同角度看这个问题",
                    "content": [v["summary"] for v in views]
                },
                {
                    "name": "情绪光谱",
                    "description": "你在这个问题上的情绪状�?,
                    "content": emotional
                }
            ],
            "self_questions": questions,
            "closing_note": self._generate_closing_note(),
            "metadata": {
                "generated_at": "2025-12-07",
                "version": "1.0",
                "philosophy_compliant": True
            }
        }
    
    def _validate_philosophy(self, film: Dict) -> Dict[str, Any]:
        """验证产品哲学合规�?""
        violations = []
        
        # 检查是否有禁用短语
        film_text = str(film)
        for phrase in FORBIDDEN_PHRASES:
            if phrase in film_text:
                violations.append(f"包含禁用短语: '{phrase}'")
        
        # 检查是否有自我提问
        if not film.get("self_questions"):
            violations.append("缺少自我提问清单")
        
        return {
            "passed": len(violations) == 0,
            "violations": violations
        }
    
    def _fix_violations(self, film: Dict, violations: List[str]) -> Dict[str, Any]:
        """修正违规内容"""
        # 简单实现：添加免责声明
        film["disclaimer"] = (
            "以上内容仅供参考，旨在帮助你厘清思路�?
            "而非给出确定性的答案。最终的决定权始终在你手中�?
        )
        return film
    
    def _generate_closing_note(self) -> str:
        """生成结束�?""
        return (
            "这张胶片记录了你此刻的思考�?
            "没有标准答案，只有属于你的答案�?
            "也许现在不需要做决定，只需要继续感受和思考�?
        )
