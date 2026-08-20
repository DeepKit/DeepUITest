"""
Decision Mirror Skill
=====================
镜像视角：反映用户情绪和价值观
"""

import structlog
import json
import re
from typing import Dict, Any
from ..base import BaseSkill, SkillCategory, SkillParameter, SkillResult
from .scenarios import get_scenario_focus

logger = structlog.get_logger(__name__)

MIRROR_SYSTEM_PROMPT = """你是一位决策镜像分析师。你的角色是：
1. 反映用户的情绪状态和潜在感受
2. 识别用户内心的价值观冲突
3. 帮助用户看到自己决策中的身份认同因素
4. 使用镜像式语言温和地反馈

输出 JSON 对象：
- emotional_landscape: 情绪地图 (primary_emotion, secondary_emotions, intensity)
- value_conflicts: 价值观冲突列表
- identity_aspects: 身份认同方面
- reflection_prompts: 反思引导

重要：只输出一个 JSON 对象，不要 Markdown，不要代码围栏，不要额外解释。
"""

class DecisionMirrorSkill(BaseSkill):
    """决策镜像 Skill"""
    
    def __init__(self, llm_client=None):
        super().__init__(
            name="decision_mirror",
            description="镜像视角：反映用户的情绪、价值观和内在冲突",
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
        """执行镜像视角分析"""
        problem = params.get("problem", "")
        input_context = params.get("context", {})
        
        logger.info("decision_mirror.execute", problem_length=len(problem))
        
        try:
            # 构建提示词（T8: 按场景模板注入差异化聚焦）
            scene_focus = get_scenario_focus(input_context, "mirror")
            prompt = f"""问题：{problem}

背景信息：{input_context.get('background', '无')}
{scene_focus}
请以镜像视角分析这个决策问题。"""
            
            # 调用 LLM (如果可用)，失败时降级到模板
            if self.llm_client:
                try:
                    response = await self.llm_client.chat(
                        system=MIRROR_SYSTEM_PROMPT,
                        user=prompt
                    )
                    result = self._parse_response(response.content)
                    if "raw_analysis" in result:
                        # LLM 输出无法解析为 JSON → 降级到模板（防假绿）
                        truncated = getattr(response, "truncated", False)
                        logger.warning("decision_mirror.llm_not_json",
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
                    logger.warning("decision_mirror.llm_fallback", error=str(e))
                    result = self._generate_template_result(problem)
                    result["degraded"] = True
                    result["degrade_reason"] = str(e)
            else:
                result = self._generate_template_result(problem)
                result["degraded"] = True
                result["degrade_reason"] = "llm_client_not_configured"
            
            return SkillResult.success(result)
        except Exception as e:
            logger.error("decision_mirror.error", error=str(e))
            return SkillResult.failure(f"Skill/Mirror/ExecutionError: {e}")
    
    def _parse_response(self, response: str) -> Dict[str, Any]:
        """解析 LLM 响应（支持 JSON 围栏提取与容错）"""
        # 通用提取：先找围栏，再找裸 JSON
        m = re.search(r"```json\s*\n?([\s\S]*?)\n?```", response)
        if m:
            try:
                parsed = json.loads(m.group(1))
                parsed.setdefault("role", "mirror")
                return parsed
            except Exception:
                pass
        m = re.search(r"\{[\s\S]*\}", response)
        if m:
            try:
                parsed = json.loads(m.group(0))
                parsed.setdefault("role", "mirror")
                return parsed
            except Exception:
                pass
        # 无法解析时返回原始分析（调用方据此判断降级）
        return {
            "role": "mirror",
            "emotional_landscape": {},
            "value_conflicts": [],
            "identity_aspects": [],
            "reflection_prompts": [],
            "raw_analysis": response
        }
    
    def _generate_template_result(self, problem: str) -> Dict[str, Any]:
        """生成模板结果（降级模式）"""
        return {
            "role": "mirror",
            "emotional_landscape": {
                "primary_emotion": "uncertainty",
                "secondary_emotions": ["hope", "fear", "excitement"],
                "intensity": 0.7
            },
            "value_conflicts": [
                {"value_a": "安全稳定", "value_b": "追求成长", "tension": 0.8}
            ],
            "identity_aspects": [
                "你似乎很重视专业能力的认可",
                "家庭责任是你决策时的重要考量"
            ],
            "reflection_prompts": [
                "我注意到你用了'应该'这个词，这是谁的期望？",
                "当你想到这个选择时，身体有什么感觉？"
            ]
        }
