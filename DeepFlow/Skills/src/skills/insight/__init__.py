"""
DeepInsight Decision Skills
=======================
DeepInsight-002: 洞见多角色决策相�?Python Skills

Skills:
- decision_coach: 教练视角 - 引导式提问，挖掘用户真实想法
- decision_critic: 批评者视�?- 挑战假设，识别盲�?- decision_mirror: 镜像视角 - 反映用户情绪和价值观
- decision_observer: 观察者视�?- 客观分析，识别模�?- decision_aggregator: 聚合�?- 综合多视角结�?- film_generator: 胶片生成�?- 生成决策思维胶片
"""

from .coach import DecisionCoachSkill
from .critic import DecisionCriticSkill
from .mirror import DecisionMirrorSkill
from .observer import DecisionObserverSkill
from .aggregator import DecisionAggregatorSkill
from .film_generator import FilmGeneratorSkill

__all__ = [
    'DecisionCoachSkill',
    'DecisionCriticSkill',
    'DecisionMirrorSkill',
    'DecisionObserverSkill',
    'DecisionAggregatorSkill',
    'FilmGeneratorSkill',
]
