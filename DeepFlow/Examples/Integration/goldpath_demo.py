"""
DeepFlow MVP P0 - 金路径端到端演示 (Python 版)
===============================================

目标:
  1. 验证 insight 决策金路径完整闭环
  2. Workflow 定义 → Delphi 引擎 → Skills 服务六角色 → LLM → 聚合 → 胶片
  3. 记录响应时间，产出胶片文件

前置条件:
  - Skills 服务运行在 http://127.0.0.1:8001
  - 安装依赖：pip install requests

验收标准:
  ✓ 六个角色依次调用 (coach/critic/mirror/observer/aggregator/film_generator)
  ✓ 四视角并行推演 (parallel fork, 与 workflow fork_roles 一致)
  ✓ 最终产出胶片文件到 D:/_Progs/02Business/DeepFlow/outputs/film_{timestamp}.md
  ✓ 四视角并行阶段耗时 < 35 秒
"""

import os
import sys
import io
import json
import time
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

# Windows 控制台 UTF-8
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# 配置
SKILL_BASE_URL = "http://127.0.0.1:8001"
OUTPUT_DIR = Path("D:/_Progs/02Business/DeepFlow/outputs")
TIMEOUT_MS = 300000  # LLM 调用 ~20-30s，但并发会排队，预留 5 分钟余量


class GoldPathDemo:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({"Content-Type": "application/json"})
        self.start_time = None

    def log(self, message: str):
        elapsed = (datetime.now() - self.start_time).total_seconds()
        print(f"[{elapsed:6.3f}s] > {message}", flush=True)

    def call_skill(self, skill_name: str, params: dict) -> dict:
        """调用 Skills 服务"""
        url = f"{SKILL_BASE_URL}/skills/execute"
        payload = {
            "skill_name": skill_name,
            "timeout_ms": TIMEOUT_MS,
            "params": params
        }
        start = time.time()
        response = self.session.post(url, json=payload, timeout=150)
        elapsed = (time.time() - start) * 1000

        if not response.ok:
            raise Exception(f"技能调用失败 ({skill_name}): HTTP {response.status_code}")

        result = response.json()
        if result.get("status") != "success":
            raise Exception(f"技能调用失败 ({skill_name}): {result.get('error')}")

        self.log(f"OK {skill_name} done ({elapsed/1000:.3f}s)")
        return result.get("result", {})

    def run(self):
        """执行金路径完整流程"""
        print("\n" + "=" * 72)
        print("DeepFlow MVP P0 - Insight Gold Path Demo")
        print("=" * 72)
        print(f"启动时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Skills 服务：{SKILL_BASE_URL}")
        print("")

        self.start_time = datetime.now()

        # Step 1: 设定问题
        problem = "我在职业发展中面临选择：是继续在当前公司深耕技术路线成为专家，还是跳槽到创业公司担任技术负责人？请帮我进行系统性的决策分析。"

        print("【步骤 1】接收决策问题")
        print(f"问题：{problem[:80]}...")
        print("")

        # Step 2: 并行调用四视角 (与 workflow fork_roles 的 parallel 配置一致)
        print("【步骤 2】多视角并行推演（教练/批评者/镜像/观察者）")
        print("---")

        common_params = {"problem": problem, "context": {}}
        role_names = ["decision_coach", "decision_critic", "decision_mirror", "decision_observer"]

        views = {}
        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = {
                executor.submit(self.call_skill, name, common_params.copy()): name
                for name in role_names
            }
            for future in as_completed(futures):
                name = futures[future]
                views[name] = future.result()

        coach_view = views["decision_coach"]
        critic_view = views["decision_critic"]
        mirror_view = views["decision_mirror"]
        observer_view = views["decision_observer"]

        degraded_flags = {
            "coach": coach_view.get("degraded", False),
            "critic": critic_view.get("degraded", False),
            "mirror": mirror_view.get("degraded", False),
            "observer": observer_view.get("degraded", False),
        }
        print(f"degraded flags: {degraded_flags}")
        print("---")
        print("")

        # Step 3: 聚合
        print("【步骤 3】聚合多视角洞察")
        aggregated = self.call_skill("decision_aggregator", {
            "coach_view": coach_view,
            "critic_view": critic_view,
            "mirror_view": mirror_view,
            "observer_view": observer_view
        })
        print(f"aggregator degraded: {aggregated.get('degraded', False)}")
        print("")

        # Step 4: 生成胶片
        print("【步骤 4】生成决策胶片")
        film = self.call_skill("film_generator", {
            "problem": problem,
            "aggregated": aggregated
        })
        print(f"film degraded: {film.get('degraded', False)}")
        print("")

        # Step 5: 保存胶片
        film_path = self.save_film(problem, film)

        # 统计总耗时
        total_time = (datetime.now() - self.start_time).total_seconds() * 1000

        # 输出总结
        print("\n" + "=" * 72)
        print("Gold Path Demo Results Summary")
        print("=" * 72)
        print(f"总耗时：{total_time / 1000:.3f} 秒 ({total_time:.1f} ms)")
        degraded_any = any(degraded_flags.values()) or aggregated.get("degraded", False) or film.get("degraded", False)
        print(f"LLM 降级：{'是 (有角色走模板)' if degraded_any else '否 (全部真实 LLM)'}")
        print(f"Film Output: {film_path}")
        print("=" * 72)

        result = {
            "status": "success" if not degraded_any else "degraded",
            "total_time_ms": total_time,
            "film_saved": True,
            "degraded_roles": degraded_flags,
            "film_path": str(film_path),
        }

        # 保存运行摘要
        summary_path = OUTPUT_DIR / "goldpath_summary.json"
        summary_path.write_text(json.dumps({
            "timestamp": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
            **result
        }, ensure_ascii=False, indent=2), encoding="utf-8")

        return result

    def save_film(self, problem: str, film: dict) -> Path:
        """保存胶片到 Markdown 文件"""
        if "title" not in film:
            raise Exception("胶片输出中缺少 title 字段")

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        file_path = OUTPUT_DIR / f"film_{timestamp}.md"
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

        lines = [
            f"# {film['title']}",
            "",
            f"## 副标题：{film.get('subtitle', '决策推演')}",
            "",
            f"生成时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            f"问题：{problem}",
            "",
            "---",
            ""
        ]

        for section in film.get("sections", []):
            lines.append(f"### {section.get('name', '章节')}")
            lines.append("")
            desc = section.get('description', '')
            if desc:
                lines.append(desc)
            lines.append("")
            content = section.get('content', '')
            if content:
                lines.append(content)
                lines.append("")

        if film.get("closing_note"):
            lines.append("---")
            lines.append("")
            lines.append("## 结语")
            lines.append("")
            lines.append(film["closing_note"])
            lines.append("")

        if film.get("self_questions"):
            lines.append("## 自我提问")
            lines.append("")
            for q in film["self_questions"]:
                lines.append(f"- {q}")
            lines.append("")

        if film.get("disclaimer"):
            lines.append("---")
            lines.append("")
            lines.append("## 免责声明")
            lines.append("")
            lines.append(film["disclaimer"])
            lines.append("")

        content = "\n".join(lines)
        file_path.write_text(content, encoding="utf-8")

        self.log(f"SAVED film to: {file_path}")
        return file_path


if __name__ == "__main__":
    try:
        demo = GoldPathDemo()
        result = demo.run()
        print(f"\nRESULT: {json.dumps(result, ensure_ascii=False)}")
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
