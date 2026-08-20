"""
DeepFlow MVP P0 优先级多模型会议 (2026-08-08)
=============================================
议题：DeepFlow MVP 端到端闭环——确定 P0 优先级任务清单与实现顺序
流程：阶段1 各家族独立生成 P0 清单；阶段2 各家族独立评审投票（一家族一票）
"""
import concurrent.futures
import json
import os
import re
import time
import urllib.request
from pathlib import Path

API = "http://127.0.0.1:8000/v1/messages"
KEY = os.environ.get("KIRO_API_KEY", "")
OUT = Path("D:/_Progs/02Business/DeepFlow/Skills/reports/deepflow-mvp-p0-deliberation-2026-08-08.json")

# 家族 -> 模型（qoder 本地路由实测可用，串行 ~18s）
MODELS = [
    ("GLM", "claude-qoder-glm-5-2"),
    ("Kimi", "claude-qoder-kimi-k3"),
    ("DeepSeek", "claude-qoder-deepseek-v4-pro"),
    ("Qwen", "claude-qoder-qwen3-8-max"),
    ("MiniMax", "claude-qoder-minimax-m3"),
    ("Cantus", "claude-qoder-cantus"),
]

CONTEXT = """背景：DeepFlow 是"智能应用的操作系统"，MVP 采用 Delphi(Core) + Python(Skills) 双栈。
已完成：
1. Skills 服务（FastAPI, 127.0.0.1:8001）已注册 7 个技能：code_executor + insight 金路径六角色
   （decision_coach 教练 / decision_critic 批评者 / decision_mirror 镜像 / decision_observer 观察者 /
    decision_aggregator 聚合器 / film_generator 胶片生成器），/skills /skills/execute 端点可用。
2. Delphi 引擎端已有 Workflow 定义/状态机/执行器等核心单元（Source/Workflow/*.pas 共 8 个单元，
   约 1.2 万行），且已创建 Delphi 调用 Skills 服务的端到端演示。
3. 示例 Workflow 定义已存在（Config/workflows/simple_qa.workflow.json、Workflows/insight_decision_gold.json、
   Templates/03-ai-chat.json 等）。

未完成/待验证：
- insight 六角色 Skill 的全链路真实调用验证（含 LLM 回退降级模板路径）
- Workflow 定义 → Delphi 引擎 → Skills 服务 → LLM → 聚合 → 胶片产出的完整闭环尚未端到端跑通验证
- 测试套件（Skills 服务侧 editor/tests 是前端测试，Python 侧无测试）
- FlowEngine 的 SQLite 持久化、错误恢复、并发一致性等核心机制
- 文档同步（06.13 FlowEngine 实现任务清单大部分未打勾）

约束：MVP 目标是"用最小成本验证架构可行性与端到端闭环"；金路径是 insight 决策推演
（多角色 → 聚合 → 胶片产出），对应产品文档 07.02 的"洞见-决策推演金路径"。"""

Q1_PROMPT = CONTEXT + """
决议点 Q1：DeepFlow MVP 端到端闭环的 P0 核心验收标准应聚焦哪一个？
候选：
A. 金路径闭环——跑通「Workflow 定义 → Delphi 引擎 → Skills 服务六角色 → LLM/降级 → 聚合 → 胶片」的完整演示，一个真实决策问题从请求到产出一气呵成。代价：暂缓引擎深层机制（持久化/并发）。
B. 引擎健壮性——先完成 FlowEngine 状态机、SQLite 持久化、错误恢复与并发一致性，引擎稳了再谈业务闭环。代价：业务侧闭环（六角色真实调用）后置，演示价值延迟。
C. 平台能力面——优先扩展 Skills 服务能力（MCP 外部集成、多技能注册、Skill 热加载），让平台"什么都能接"。代价：金路径闭环与引擎健壮性都后置，易陷入"为平台而平台"。
请作为独立技术评审给出选择和理由。只输出 JSON 对象，不要其它文字：
{"choice":"A","reason":"...","risk":"..."}"""

Q2_PROMPT = CONTEXT + """
决议点 Q2：假设采纳"先金路径闭环再加固"的总策略，P0 内部实现顺序应如何排？
候选：
A. 全链路冒烟先行——直接用现成 Workflow 定义（insight_decision_gold.json）跑通六角色真实调用（含 LLM 降级模板路径），先看到端到端产物，再补测试与文档。
B. 测试契约先行——先为 Skills 服务补 Python 测试（六角色单元测试 + /skills/execute 集成测试），测试绿了再跑全链路。
C. 文档清单先行——先把 06.13 任务清单按现状打勾/修正，形成精确的剩余工作量账本，再按账本执行。
请作为独立技术评审给出选择和理由。只输出 JSON 对象，不要其它文字：
{"choice":"A","reason":"...","risk":"..."}"""

Q3_PROMPT = CONTEXT + """
决议点 Q3：请给出你认为是 P0 的 Top 5 任务清单（按优先级从高到低排序），每项含任务名与一句验收标准。
只输出 JSON 数组，不要其它文字：
[{"task":"...","acceptance":"..."}]"""


def call(model: str, prompt: str, max_tokens: int = 1500, timeout: int = 180) -> str:
    payload = {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }

    def post(body):
        req = urllib.request.Request(
            API,
            data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
            headers={
                "x-api-key": KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))

    data = post(payload)
    return "".join(
        x.get("text", "") for x in data.get("content", []) if x.get("type") == "text"
    )


def extract_choice(text: str):
    m = re.search(r'"choice"\s*:\s*"([ABC])"', text)
    return m.group(1) if m else None


def extract_array(text: str):
    m = re.search(r"\[[\s\S]*\]", text)
    if not m:
        return []
    try:
        return json.loads(m.group(0))
    except Exception:
        return []


def main():
    result = {
        "deliberated_at": "2026-08-08",
        "task": "DeepFlow MVP P0 priority & execution order",
        "votes": {},
        "generations": {},
    }

    # 阶段 1：独立生成（Q1/Q2 投票 + Q3 清单）
    def generate(item):
        fam, model = item
        started = time.time()
        row = {"family": fam, "model": model, "status": "ok"}
        try:
            t1 = call(model, Q1_PROMPT)
            t2 = call(model, Q2_PROMPT)
            t3 = call(model, Q3_PROMPT, max_tokens=2500)
            row["q1_choice"] = extract_choice(t1)
            row["q2_choice"] = extract_choice(t2)
            row["q1_raw"] = t1[:900]
            row["q2_raw"] = t2[:900]
            row["q3_items"] = extract_array(t3)
            row["q3_raw"] = t3[:1500]
            row["latency_s"] = round(time.time() - started, 2)
        except Exception as exc:
            row["status"] = "error"
            row["latency_s"] = round(time.time() - started, 2)
            row["error"] = repr(exc)
        return row

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:  # qoder 并发受限，3 并发
        futures = [ex.submit(generate, item) for item in MODELS]
        for f in futures:
            row = f.result()
            result["votes"][row["family"]] = row
            result["generations"][row["family"]] = row

    # 计票：一家族一票
    def tally(key):
        votes = {"A": [], "B": [], "C": []}
        failed = []
        for fam, v in result["votes"].items():
            if v.get("status") != "ok" or not v.get(key):
                failed.append(fam)
                continue
            if v[key] in votes:
                votes[v[key]].append(fam)
        winner = max(votes, key=lambda k: len(votes[k])) if any(votes.values()) else None
        return {k: v for k, v in votes.items() if v}, failed, winner

    q1_votes, q1_failed, q1_winner = tally("q1_choice")
    q2_votes, q2_failed, q2_winner = tally("q2_choice")

    # Q3 清单聚合：任务名去重统计
    task_count = {}
    task_families = {}
    for fam, v in result["votes"].items():
        for item in v.get("q3_items", []):
            task = str(item.get("task", "")).strip()[:60]
            if not task:
                continue
            task_count[task] = task_count.get(task, 0) + 1
            task_families.setdefault(task, []).append(fam)

    result["summary"] = {
        "q1_votes": q1_votes,
        "q1_failed": q1_failed,
        "q1_winner": q1_winner,
        "q2_votes": q2_votes,
        "q2_failed": q2_failed,
        "q2_winner": q2_winner,
        "q3_aggregated": sorted(
            [
                {"task": t, "mentions": c, "families": sorted(set(fams))}
                for t, c in task_count.items()
                for fams in [task_families[t]]
            ],
            key=lambda x: -x["mentions"],
        ),
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result["summary"], ensure_ascii=False, indent=2))
    print(f"OUT={OUT}")


if __name__ == "__main__":
    main()
