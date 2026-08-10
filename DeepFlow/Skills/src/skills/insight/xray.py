"""
Mind X-Ray Skill (T19b/T19d)
=======================
脑内 X 光片：第三人称自我觉察 + 跨会话成长对比
- 照见本次决策/倾诉中"我"真正执着的是什么、在重复什么旧模式
- 结合历史会话摘要，指出与以往相比的新差异或成长
- 语气温和诚实：不羞辱、不讽刺、不道德审判（DeepInsight 基础版反宪法约束）
"""

import structlog
import json
import re
from typing import Dict, Any
from ..base import BaseSkill, SkillCategory, SkillParameter, SkillResult

logger = structlog.get_logger(__name__)

XRAY_SYSTEM_PROMPT = """你是一位温和而诚实的自我觉察分析师，为一位用户生成"脑内 X 光片"。

你的任务：
1. 用第三人称（"他"/"这个人"）描述这次决策或倾诉中，用户真正执着的是什么、在逃避什么
2. 识别他在重复的旧模式（如果有历史会话信息，与以往对比）
3. 指出哪怕一点点的新差异或成长（与历史相比）
4. 不求全面，突出 1~2 个关键观察点

语气铁律：温和、诚实。不羞辱、不讽刺、不道德审判、不居高临下。像一位懂他多年的老友。

输出 JSON 对象：
- core_obsession: 本次的核心执着/逃避点（一句话）
- old_patterns: 重复的旧模式列表（1~3 条，没有则空数组）
- growth: 新出现的差异或成长（1~2 条，没有则空数组）
- narrative: 一段完整的第三人称 X 光文字（80~200 字）

重要：只输出一个 JSON 对象，不要 Markdown，不要代码围栏，不要额外解释。
"""


class MindXraySkill(BaseSkill):
    """脑内 X 光片 Skill"""

    def __init__(self, llm_client=None):
        super().__init__(
            name="mind_xray",
            description="第三人称自我觉察 X 光片（含跨会话成长对比）",
            category=SkillCategory.LLM,
            version="1.0.0",
            parameters=[
                SkillParameter(
                    name="problem",
                    type="string",
                    description="本次的问题或倾诉主题",
                    required=True
                ),
                SkillParameter(
                    name="material",
                    type="string",
                    description="本次素材：胶片摘要（decision）或倾诉与对话内容（treehole）",
                    required=False
                ),
                SkillParameter(
                    name="history_summary",
                    type="string",
                    description="历史会话摘要（跨会话成长对比用），可空",
                    required=False
                ),
                SkillParameter(
                    name="mode",
                    type="string",
                    description="场景模式：decision（决策后照见）或 treehole（树洞倾诉后分析）",
                    required=False
                )
            ]
        )
        self.llm_client = llm_client

    async def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> SkillResult:
        """生成 X 光片"""
        problem = params.get("problem", "")
        material = params.get("material", "")
        history_summary = params.get("history_summary", "")
        mode = params.get("mode", "decision")

        logger.info("mind_xray.execute", mode=mode, problem_length=len(problem),
                    has_history=bool(history_summary))

        try:
            history_block = ""
            if history_summary.strip():
                history_block = f"""
以往会话记录（用于跨会话成长对比；若与本次无关可忽略）：
{history_summary}
"""
            prompt = f"""本次场景：{'决策型会话' if mode == 'decision' else '树洞倾诉'}
本次问题/主题：{problem}

本次素材：
{material or '（无额外素材，仅依据问题本身）'}
{history_block}
请为这个人写一张脑内 X 光片。"""

            if self.llm_client:
                try:
                    response = await self.llm_client.chat(
                        system=XRAY_SYSTEM_PROMPT,
                        user=prompt
                    )
                    result = self._parse_response(response.content)
                    if "raw_analysis" in result:
                        truncated = getattr(response, "truncated", False)
                        logger.warning("mind_xray.llm_not_json",
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
                    logger.warning("mind_xray.llm_fallback", error=str(e))
                    result = self._generate_template_result(problem)
                    result["degraded"] = True
                    result["degrade_reason"] = str(e)
            else:
                result = self._generate_template_result(problem)
                result["degraded"] = True
                result["degrade_reason"] = "llm_client_not_configured"

            result["mode"] = mode
            return SkillResult.success(result)
        except Exception as e:
            logger.error("mind_xray.error", error=str(e))
            return SkillResult.failure(f"Skill/Xray/ExecutionError: {e}")

    def _parse_response(self, response: str) -> Dict[str, Any]:
        """解析 LLM 响应（支持 JSON 围栏提取与容错）"""
        m = re.search(r"```json\s*\n?([\s\S]*?)\n?```", response)
        if m:
            try:
                parsed = json.loads(m.group(1))
                parsed.setdefault("role", "xray")
                return parsed
            except Exception:
                pass
        m = re.search(r"\{[\s\S]*\}", response)
        if m:
            try:
                parsed = json.loads(m.group(0))
                parsed.setdefault("role", "xray")
                return parsed
            except Exception:
                pass
        return {
            "role": "xray",
            "core_obsession": "",
            "old_patterns": [],
            "growth": [],
            "narrative": "",
            "raw_analysis": response
        }

    def _generate_template_result(self, problem: str) -> Dict[str, Any]:
        """生成模板结果（降级模式，语气遵循温和铁律）"""
        return {
            "role": "xray",
            "core_obsession": "他在意结果本身，也在意自己是否被看见",
            "old_patterns": [
                "倾向先把局面想完整，再真正迈出一步"
            ],
            "growth": [
                "这一次他愿意把问题摆出来被照见，这本身就是一种不同"
            ],
            "narrative": (
                "这个人这次认真地把问题摆了出来。他真正在意的，"
                "不只是结果好坏，还有自己是否坦诚地面对了它。"
                "和以往相比，他少了一点回避，多了一点愿意被看见的勇气。"
            )
        }
