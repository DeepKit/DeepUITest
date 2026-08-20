"""
Decision Aggregator Skill
=========================
聚合器：综合多视角结果
"""

import structlog
import json
import re
from typing import Dict, Any, List
from ..base import BaseSkill, SkillCategory, SkillParameter, SkillResult

logger = structlog.get_logger(__name__)

AGGREGATOR_SYSTEM_PROMPT = """你是一位决策聚合分析师。你的角色是：
1. 综合教练、批评者、镜像、观察者四个视角的结果
2. 识别共识与分歧
3. 提炼最关键洞察与自我提问
4. 保持哲学中立，不替用户做决定

输出 JSON 对象：
- views: 各视角摘要列表 (role, summary)
- key_DeepInsights: 关键洞察 Top 5
- self_questions: 自我提问 Top 5
- emotional_summary: 情绪摘要
- risks: 风险列表
- consensus_points: 共识点
- divergence_points: 分歧点

重要：只输出一个 JSON 对象，不要 Markdown，不要代码围栏，不要额外解释。
"""

class DecisionAggregatorSkill(BaseSkill):
    """决策聚合器 Skill"""
    
    def __init__(self, llm_client=None):
        super().__init__(
            name="decision_aggregator",
            description="综合多视角分析结果，生成结构化视角列表",
            category=SkillCategory.LLM,
            version="1.0.0",
            parameters=[
                SkillParameter(
                    name="coach_view",
                    type="object",
                    description="教练视角分析结果",
                    required=True
                ),
                SkillParameter(
                    name="critic_view",
                    type="object",
                    description="批评者视角分析结果",
                    required=True
                ),
                SkillParameter(
                    name="mirror_view",
                    type="object",
                    description="镜像视角分析结果",
                    required=True
                ),
                SkillParameter(
                    name="observer_view",
                    type="object",
                    description="观察者视角分析结果",
                    required=True
                )
            ]
        )
        self.llm_client = llm_client
    
    async def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> SkillResult:
        """聚合多视角结果"""
        coach = params.get("coach_view", {})
        critic = params.get("critic_view", {})
        mirror = params.get("mirror_view", {})
        observer = params.get("observer_view", {})
        
        logger.info("decision_aggregator.execute")
        
        try:
            # 调用 LLM (如果可用) 进行综合，失败时降级到模板聚合
            if self.llm_client:
                try:
                    # 压缩四视角输入：只保留关键字段，避免截断
                    views_json = json.dumps(
                        {"coach": self._compact_view(coach),
                         "critic": self._compact_view(critic),
                         "mirror": self._compact_view(mirror),
                         "observer": self._compact_view(observer)},
                        ensure_ascii=False,
                    )
                    response = await self.llm_client.chat(
                        system=AGGREGATOR_SYSTEM_PROMPT,
                        user=f"请聚合以下四个视角的分析结果：\n{views_json[:8000]}",
                        max_tokens=8192
                    )
                    result = self._parse_response(response.content)
                    if "raw_analysis" in result:
                        # LLM 输出无法解析为 JSON → 降级到模板（防假绿）
                        truncated = getattr(response, "truncated", False)
                        logger.warning("decision_aggregator.llm_not_json",
                                      response_preview=response.content[:200],
                                      truncated=truncated)
                        result = self._aggregate_template(coach, critic, mirror, observer)
                        result["degraded"] = True
                        result["degrade_reason"] = (
                            "llm_response_truncated" if truncated else "llm_response_not_json"
                        )
                        return SkillResult.success(result)
                    result["degraded"] = False
                    return SkillResult.success(result)
                except Exception as e:
                    logger.warning("decision_aggregator.llm_fallback", error=str(e))
                    result = self._aggregate_template(coach, critic, mirror, observer)
                    result["degraded"] = True
                    result["degrade_reason"] = str(e)
                    return SkillResult.success(result)
            else:
                result = self._aggregate_template(coach, critic, mirror, observer)
                result["degraded"] = True
                result["degrade_reason"] = "llm_client_not_configured"
                return SkillResult.success(result)
        except Exception as e:
            logger.error("decision_aggregator.error", error=str(e))
            return SkillResult.failure(f"Skill/Aggregator/ExecutionError: {e}")

    def _compact_view(self, view: Dict[str, Any]) -> Dict[str, Any]:
        """压缩视角数据：提取关键字段，控制输入体积"""
        if not isinstance(view, dict):
            return {"role": "unknown", "summary": ""}
        # 优先用摘要字段，其次提取列表前几项
        compact: Dict[str, Any] = {"role": view.get("role", "unknown")}
        for key in ("summary", "key_DeepInsights", "guiding_questions",
                    "assumptions_challenged", "blind_spots", "risks",
                    "emotional_landscape", "value_conflicts", "identity_aspects",
                    "reflection_prompts", "decision_patterns", "external_factors",
                    "similar_cases", "objective_observations"):
            val = view.get(key)
            if val is None:
                continue
            if isinstance(val, list):
                compact[key] = val[:3]  # 每类最多 3 项
            elif isinstance(val, str):
                compact[key] = val[:200]  # 字符串截断 200 字
            else:
                compact[key] = val
        return compact

    def _parse_response(self, response: str) -> Dict[str, Any]:
        """解析 LLM 响应（支持 JSON 围栏提取与容错）"""
        # 通用提取：先找围栏，再找裸 JSON
        m = re.search(r"```json\s*\n?([\s\S]*?)\n?```", response)
        if m:
            try:
                parsed = json.loads(m.group(1))
                return parsed
            except Exception:
                pass
        m = re.search(r"\{[\s\S]*\}", response)
        if m:
            try:
                parsed = json.loads(m.group(0))
                return parsed
            except Exception:
                pass
        return {
            "views": [],
            "key_DeepInsights": [],
            "self_questions": [],
            "emotional_summary": {},
            "risks": [],
            "consensus_points": [],
            "divergence_points": [],
            "raw_analysis": response
        }

    def _aggregate_template(self, coach: Dict[str, Any], critic: Dict[str, Any],
                            mirror: Dict[str, Any], observer: Dict[str, Any]) -> Dict[str, Any]:
        """模板聚合（降级模式）"""
        # 提取关键洞察
        all_DeepInsights = []
        all_DeepInsights.extend(coach.get("key_DeepInsights", []))
        all_DeepInsights.extend(critic.get("assumptions_challenged", []))
        all_DeepInsights.extend(mirror.get("identity_aspects", []))
        all_DeepInsights.extend(observer.get("decision_patterns", []))
        
        # 提取所有问题
        all_questions = []
        all_questions.extend(coach.get("guiding_questions", []))
        all_questions.extend(critic.get("devil_advocate_questions", []))
        all_questions.extend(mirror.get("reflection_prompts", []))
        
        # 计算共识和分歧
        return {
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
    
    def _summarize_view(self, view: Dict[str, Any]) -> str:
        """生成视角摘要"""
        role = view.get("role", "unknown")
        summaries = {
            "coach": "教练视角关注你的内在动机和价值观",
            "critic": "批评者视角帮助你识别盲点和风险",
            "mirror": "镜像视角反映你的情绪和内在冲突",
            "observer": "观察者视角提供客观的模式分析"
        }
        return summaries.get(role, "未知视角")
