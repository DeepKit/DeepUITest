"""
可鉴 · 决策操作系统 — 端到端测试套件
==========================================
验证六角色链路的完整功能（Python FastAPI 客户端）

使用方法：
    python kejian_e2e_test.py --problem "您的决策问题" --template strategic
    python kejian_e2e_test.py --help
"""

import argparse
import json
import sys
from datetime import datetime
from typing import Any, Dict, List
import aiohttp
import asyncio


# Configuration
SKILLS_API = "http://127.0.0.1:8002"  # 封版审计: 8001 为旧实例, 统一指向 8002 完整版
EXECUTE_URL = SKILLS_API + "/skills/execute"
TIMEOUT_SECONDS = 300  # 5 minutes for LLM calls


class DecisionGovernanceTestRunner:
    """决策治理端到端测试运行器"""
    
    def __init__(self):
        self.results: List[Dict[str, Any]] = []
        self.stats = {
            "total_calls": 0,
            "successful": 0,
            "degraded": 0,
            "errors": 0,
            "total_time_ms": 0
        }
    
    async def call_skill(self, session: aiohttp.ClientSession, skill_name: str, params: Dict[str, Any]) -> Dict[str, Any]:
        """调用 Skills API（带错误处理）"""
        self.stats["total_calls"] += 1
        start = datetime.utcnow()
        
        payload = {
            "skill_name": skill_name,
            "params": params,
            "context": {},
            "timeout_ms": TIMEOUT_SECONDS * 1000
        }
        
        try:
            async with session.post(
                EXECUTE_URL,
                json=payload,
                timeout=aiohttp.ClientTimeout(total=TIMEOUT_SECONDS)
            ) as resp:
                if resp.status == 200:
                    result = await resp.json()
                    elapsed = (datetime.utcnow() - start).total_seconds() * 1000
                    self.stats["total_time_ms"] += elapsed
                    
                    status = "success"
                    is_degraded = result.get("result", {}).get("degraded", False)
                    
                    if is_degraded:
                        self.stats["degraded"] += 1
                        print(f"  [DEGRADED] {skill_name}: {result['result'].get('degrade_reason', 'unknown')}")
                    else:
                        self.stats["successful"] += 1
                        print(f"  [OK] {skill_name} ({elapsed:.1f}ms)")
                    
                    return {
                        "status": status,
                        "execution_time_ms": elapsed,
                        "data": result
                    }
                else:
                    error_text = await resp.text()[:200]
                    raise Exception(f"HTTP {resp.status}: {error_text}")
                    
        except asyncio.TimeoutError:
            self.stats["errors"] += 1
            print(f"  [TIMEOUT] {skill_name}")
            return {"status": "timeout", "execution_time_ms": TIMEOUT_SECONDS * 1000, "error": "Request timed out"}
        except Exception as e:
            self.stats["errors"] += 1
            print(f"  [ERROR] {skill_name}: {str(e)[:100]}")
            return {"status": "error", "execution_time_ms": 0, "error": str(e)}
    
    async def run_coach_critic_mirror_observer(self, session: aiohttp.ClientSession, problem: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """阶段 1：四视角并行推演"""
        roles = [
            ("coach", "decision_coach", "决策教练"),
            ("critic", "decision_critic", "批判者"),
            ("mirror", "decision_mirror", "反思者"),
            ("observer", "decision_observer", "观察者"),
        ]
        
        results = {}
        tasks = []
        
        print(f"\n[STAGE 1] 四视角并行推演...")
        for role_key, skill_name, role_zh in roles:
            task = self.call_skill(session, skill_name, {"problem": problem, "context": context})
            tasks.append((role_key, role_zh, task))
        
        # 等待所有四角色完成
        for role_key, role_zh, task in tasks:
            result = await task
            if result["status"] in ["success", "degraded"]:
                results[role_key] = result.get("data", {}).get("result", {})
        
        return results
    
    async def run_aggregator(self, session: aiohttp.ClientSession, views: Dict[str, Any]) -> Dict[str, Any]:
        """阶段 2：聚合共识"""
        print(f"\n[STAGE 2] 聚合共识...")
        
        result = await self.call_skill(
            session,
            "decision_aggregator",
            {
                "coach_view": views.get("coach", {}),
                "critic_view": views.get("critic", {}),
                "mirror_view": views.get("mirror", {}),
                "observer_view": views.get("observer", {}),
            }
        )
        
        aggregated = result.get("data", {}).get("result", {})
        return aggregated
    
    async def run_film_generator(self, session: aiohttp.ClientSession, problem: str, aggregated: Dict[str, Any]) -> Dict[str, Any]:
        """阶段 3：胶片生成"""
        print(f"\n[STAGE 3] 胶片生成...")
        
        result = await self.call_skill(
            session,
            "film_generator",
            {
                "problem": problem,
                "aggregated": aggregated,
            }
        )
        
        film = result.get("data", {}).get("result", {})
        return film
    
    async def run_full_chain(self, problem: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """完整链路：四视角 → 聚合 → 胶片"""
        total_start = datetime.utcnow()
        
        print(f"\n{'='*60}")
        print(f"可鉴 · 决策治理测试")
        print(f"问题：{problem[:60]}...")
        print(f"{'='*60}\n")
        
        async with aiohttp.ClientSession() as session:
            # Health check
            try:
                async with session.get(f"{SKILLS_API}/health", timeout=10) as resp:
                    health = await resp.json()
                    print(f"[OK] Skills 服务健康检查：{health['status']}（技能数：{health['skills_loaded']}）\n")
            except Exception as e:
                print(f"[FAIL] Skills 服务不可用：{e}")
                return None
            
            # Stage 1: Four perspectives
            views = await self.run_coach_critic_mirror_observer(session, problem, context)
            
            # Stage 2: Aggregation
            aggregated = await self.run_aggregator(session, views)
            
            # Stage 3: Film generation
            film = await self.run_film_generator(session, problem, aggregated)
        
        elapsed = (datetime.utcnow() - total_start).total_seconds()
        
        # Generate report
        report = {
            "timestamp": datetime.utcnow().isoformat(),
            "problem": problem,
            "context": context,
            "stages": {
                "perspectives": len(views),
                "aggregated": bool(aggregated),
                "film_generated": bool(film)
            },
            "results": {
                "views": {k: self._extract_summary(v) for k, v in views.items()},
                "aggregated": self._extract_summary(aggregated),
                "film": self._extract_summary(film)
            },
            "statistics": self.stats,
            "total_elapsed_seconds": elapsed
        }
        
        return report
    
    def _extract_summary(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """提取关键字段摘要"""
        if not data:
            return {"empty": True}
        
        summary = {}
        
        # 提取 key_DeepInsights
        insights = data.get("key_DeepInsights", [])
        if isinstance(insights, list) and len(insights) > 0:
            summary["key_insights_count"] = len(insights)
        
        # 提取引导问题
        questions = data.get("guiding_questions", []) or data.get("self_questions", [])
        if isinstance(questions, list) and len(questions) > 0:
            summary["questions_count"] = len(questions)
        
        # 是否降级
        summary["degraded"] = data.get("degraded", False)
        if summary["degraded"]:
            summary["degrade_reason"] = data.get("degrade_reason", "unknown")
        
        # 情绪摘要
        emotional = data.get("emotional_summary", {})
        if emotional:
            summary["emotional_summary"] = emotional
        
        # Views 列表
        views = data.get("views", [])
        if isinstance(views, list) and len(views) > 0:
            summary["views_count"] = len(views)
        
        return summary
    
    def save_report(self, report: Dict[str, Any], filename: str = None):
        """保存测试报告"""
        if not filename:
            timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
            problem_hash = hash(report["problem"]) % 10000
            filename = f"kejian_test_{timestamp}_{problem_hash}.json"
        
        with open(filename, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        
        print(f"\n[SAVED] 报告已保存：{filename}")


async def main():
    parser = argparse.ArgumentParser(description="可鉴 · 决策治理 E2E 测试套件")
    parser.add_argument("--problem", type=str, required=True, help="决策问题")
    parser.add_argument("--template", type=str, choices=["strategic", "investment", "personnel", "procurement"], 
                       default="strategic", help="治理模板")
    parser.add_argument("--output", type=str, help="输出报告文件名（可选）")
    
    args = parser.parse_args()
    
    # Context mapping
    context_mapping = {
        "strategic": {"decision_type": "strategic", "scope": "expansion/new-market/product"},
        "investment": {"decision_type": "investment", "scope": "capital-allocation/risk"},
        "personnel": {"decision_type": "personnel", "scope": "promotion/hiring/restructure"},
        "procurement": {"decision_type": "procurement", "scope": "vendor-selection/budget"},
    }
    
    runner = DecisionGovernanceTestRunner()
    report = await runner.run_full_chain(args.problem, context_mapping[args.template])
    
    if report:
        runner.save_report(report, args.output)
        
        # Summary
        print(f"\n{'='*60}")
        print("[STATS] 测试结果统计")
        print(f"{'='*60}")
        print(f"总请求数：{runner.stats['total_calls']}")
        print(f"成功：{runner.stats['successful']}")
        print(f"降级：{runner.stats['degraded']}")
        print(f"错误：{runner.stats['errors']}")
        print(f"总耗时：{report['total_elapsed_seconds']:.1f}秒")
        print(f"{'='*60}")


if __name__ == "__main__":
    asyncio.run(main())
