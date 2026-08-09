"""
可鉴 · 批量压力测试工具
========================
并发调用六角色链路，评估系统负载性能

使用方法：
    python stress_test.py --requests 10 --concurrency 5
    python stress_test.py --help
"""

import argparse
import asyncio
import time
from datetime import datetime
from typing import List, Dict, Any
import aiohttp


# Configuration
SKILLS_API = "http://127.0.0.1:8001"


class StressTester:
    """压测工具"""
    
    def __init__(self):
        self.metrics = {
            "total_requests": 0,
            "successful": 0,
            "failed": 0,
            "times": [],
            "errors": []
        }
    
    async def run_single_request(self, session: aiohttp.ClientSession, problem: str) -> float:
        """单次完整请求（四视角 + 聚合 + 胶片）"""
        start_time = time.time()
        self.metrics["total_requests"] += 1
        
        try:
            # 并行调用四视角
            tasks = [
                "decision_coach",
                "decision_critic", 
                "decision_mirror",
                "decision_observer"
            ]
            
            for skill_name in tasks:
                payload = {
                    "skill_name": skill_name,
                    "params": {"problem": problem, "context": {}},
                    "context": {},
                    "timeout_ms": 120000
                }
                
                async with session.post(
                    f"{SKILLS_API}/skills/execute",
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=120)
                ) as resp:
                    if resp.status != 200:
                        raise Exception(f"HTTP {resp.status}")
            
            # 聚合
            async with session.post(
                f"{SKILLS_API}/skills/execute",
                json={
                    "skill_name": "decision_aggregator",
                    "params": {
                        "coach_view": {},
                        "critic_view": {},
                        "mirror_view": {},
                        "observer_view": {}
                    },
                    "context": {},
                    "timeout_ms": 60000
                },
                timeout=aiohttp.ClientTimeout(total=60)
            ) as resp:
                if resp.status != 200:
                    raise Exception(f"HTTP {resp.status}")
            
            elapsed = (time.time() - start_time) * 1000
            self.metrics["times"].append(elapsed)
            
            if elapsed < 10000:  # 10 秒内成功
                self.metrics["successful"] += 1
            else:
                self.metrics["failed"] += 1
            
            return elapsed
            
        except Exception as e:
            self.metrics["failed"] += 1
            self.metrics["errors"].append(str(e))
            return (time.time() - start_time) * 1000
    
    async def run_concurrent_burst(self, session: aiohttp.ClientSession, problems: List[str], concurrency: int):
        """并发压测"""
        semaphore = asyncio.Semaphore(concurrency)
        
        async def wrapped_request(problem):
            async with semaphore:
                return await self.run_single_request(session, problem)
        
        tasks = [wrapped_request(p) for p in problems]
        await asyncio.gather(*tasks)


async def main():
    parser = argparse.ArgumentParser(description="可鉴 · 批量压力测试")
    parser.add_argument("--requests", type=int, default=5, help="总请求数")
    parser.add_argument("--concurrency", type=int, default=3, help="并发度")
    parser.add_argument("--output", type=str, help="输出报告文件（可选）")
    
    args = parser.parse_args()
    
    # Generate test problems
    sample_problems = [
        "直营门店要不要从 50 家扩到 80 家？预算 8000 万，周期两年。",
        "是否应该接受一家风险投资机构的融资提议？估值 5000 万，出让 15% 股权。",
        "公司是否要转型做 SaaS 产品？现有业务稳定，但市场空间有限。",
        "是否应该在一线城市开设旗舰店？租金成本高，但能提升品牌形象。",
        "是否应该裁掉业绩最差的团队？影响士气，但能节省成本。",
    ] * 30  # 重复生成足够的问题池
    
    problems = [sample_problems[i % len(sample_problems)] for i in range(args.requests)]
    
    print(f"\n{'='*60}")
    print(f"可鉴 · 批量压力测试")
    print(f"请求数：{args.requests}")
    print(f"并发度：{args.concurrency}")
    print(f"{'='*60}\n")
    
    tester = StressTester()
    
    async with aiohttp.ClientSession() as session:
        # Health check first
        try:
            async with session.get(f"{SKILLS_API}/health", timeout=10) as resp:
                health = await resp.json()
                print(f"✓ Skills 服务健康检查通过\n")
        except Exception as e:
            print(f"✗ Skills 服务不可用：{e}")
            return
        
        start_total = time.time()
        await tester.run_concurrent_burst(session, problems, args.concurrency)
        total_elapsed = time.time() - start_total
    
    # Report
    times = tester.metrics["times"]
    if times:
        avg_time = sum(times) / len(times)
        min_time = min(times)
        max_time = max(times)
        p95 = sorted(times)[int(len(times) * 0.95)] if len(times) > 20 else max(times)
    else:
        avg_time = min_time = max_time = p95 = 0
    
    report = {
        "timestamp": datetime.utcnow().isoformat(),
        "configuration": {
            "requests": args.requests,
            "concurrency": args.concurrency
        },
        "results": {
            "success_rate": f"{tester.metrics['successful']}/{tester.metrics['total_requests']}",
            "avg_time_ms": f"{avg_time:.1f}",
            "min_time_ms": f"{min_time:.1f}",
            "max_time_ms": f"{max_time:.1f}",
            "p95_time_ms": f"{p95:.1f}"
        },
        "total_elapsed_seconds": total_elapsed,
        "error_count": len(tester.metrics["errors"])
    }
    
    print(f"\n{'='*60}")
    print("📊 压力测试结果")
    print(f"{'='*60}")
    print(f"总请求数：{tester.metrics['total_requests']}")
    print(f"成功数：{tester.metrics['successful']}")
    print(f"失败数：{tester.metrics['failed']}")
    print(f"平均耗时：{avg_time:.1f}ms")
    print(f"最小耗时：{min_time:.1f}ms")
    print(f"最大耗时：{max_time:.1f}ms")
    if times and len(times) > 20:
        print(f"P95 耗时：{p95:.1f}ms")
    print(f"总耗时：{total_elapsed:.1f}秒")
    print(f"错误数：{len(tester.metrics['errors'])}")
    print(f"{'='*60}\n")
    
    # Save report
    if args.output:
        import json
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        print(f"💾 报告已保存：{args.output}")


if __name__ == "__main__":
    asyncio.run(main())
