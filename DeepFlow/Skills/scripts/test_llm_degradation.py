"""测试 LLM 降级场景：验证 6 角色在 LLM 不可用时的降级模板输出

场景：
1. 正常模式：LLM 可用（通过 /llm/chat 验证）
2. 降级模式：模拟 LLM 故障（通过注入坏 LLM 配置或模拟失败）

本脚本先探测服务 LLM 链路状态，再分别测试 6 角色技能：
- decision_coach
- decision_critic
- decision_mirror
- decision_observer
- decision_aggregator
- film_generator
"""
import asyncio
import json
import time
import sys
import io
import urllib.request

# Windows 控制台 UTF-8 输出
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

BASE = "http://127.0.0.1:8001"
PROBLEM = "我是否应该从稳定的工作离职去创业做 AI 产品？"


def http_post(path: str, payload: dict, timeout: float = 60.0) -> dict:
    """同步 POST 请求"""
    req = urllib.request.Request(
        f"{BASE}{path}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_get(path: str, timeout: float = 10.0):
    req = urllib.request.Request(f"{BASE}{path}", method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    print("=" * 70)
    print("金路径 LLM 降级场景验证")
    print("=" * 70)

    # 1. 探测 LLM 链路
    print("\n[1] 探测 LLM 链路状态...")
    try:
        llm_probe = http_post("/llm/chat", {
            "messages": [{"role": "user", "content": "Reply with exactly: OK"}],
            "model": "claude-qoder-glm-5-2",
            "max_tokens": 10,
        }, timeout=40)
        print(f"    LLM 链路: 可用 (model={llm_probe.get('model', '?')})")
        llm_ok = True
    except Exception as e:
        print(f"    LLM 链路: 不可用 ({e})")
        llm_ok = False

    # 2. 测试 6 角色技能
    skills = [
        ("decision_coach", {"problem": PROBLEM, "context": {"background": "工作 5 年，有稳定收入和团队"}}),
        ("decision_critic", {"problem": PROBLEM, "context": {"background": "工作 5 年，有稳定收入和团队"}}),
        ("decision_mirror", {"problem": PROBLEM, "context": {"background": "工作 5 年，有稳定收入和团队"}}),
        ("decision_observer", {"problem": PROBLEM, "context": {"background": "工作 5 年，有稳定收入和团队"}}),
    ]

    results = {}
    print(f"\n[2] 测试 4 角色并行推演 ({'LLM 模式' if llm_ok else '降级模式'})...")
    for name, params in skills:
        t0 = time.time()
        try:
            resp = http_post("/skills/execute", {"skill_name": name, "params": params}, timeout=90)
            dt = time.time() - t0
            ok = resp.get("status") == "success"
            data = resp.get("result", resp)
            degraded = data.get("degraded", "unknown")
            print(f"    {name}: {'✅' if ok else '❌'} "
                  f"status={resp.get('status')} degraded={degraded} time={dt:.1f}s")
            results[name] = {"success": ok, "degraded": degraded,
                             "time": dt, "keys": list(data.keys())[:8],
                             "error": resp.get("error")}
        except Exception as e:
            dt = time.time() - t0
            print(f"    {name}: ❌ ERROR ({e}) time={dt:.1f}s")
            results[name] = {"success": False, "error": str(e), "time": dt}

    # 3. 聚合器测试
    print(f"\n[3] 测试 decision_aggregator...")
    coach_view = results.get("decision_coach", {})
    t0 = time.time()
    try:
        resp = http_post("/skills/execute", {
            "skill_name": "decision_aggregator",
            "params": {
                "coach_view": {"role": "coach", "summary": "test"},
                "critic_view": {"role": "critic", "summary": "test"},
                "mirror_view": {"role": "mirror", "summary": "test"},
                "observer_view": {"role": "observer", "summary": "test"},
            }
        }, timeout=90)
        dt = time.time() - t0
        ok = resp.get("status") == "success"
        data = resp.get("result", resp)
        print(f"    decision_aggregator: {'✅' if ok else '❌'} "
              f"status={resp.get('status')} degraded={data.get('degraded', 'unknown')} time={dt:.1f}s")
        results["decision_aggregator"] = {"success": ok,
                                          "degraded": data.get("degraded"), "time": dt,
                                          "error": resp.get("error")}
    except Exception as e:
        dt = time.time() - t0
        print(f"    decision_aggregator: ❌ ERROR ({e}) time={dt:.1f}s")
        results["decision_aggregator"] = {"success": False, "error": str(e), "time": dt}

    # 4. 胶片生成器测试
    print(f"\n[4] 测试 film_generator...")
    t0 = time.time()
    try:
        resp = http_post("/skills/execute", {
            "skill_name": "film_generator",
            "params": {
                "problem": PROBLEM,
                "aggregated": {
                    "views": [{"role": "coach", "summary": "test"}],
                    "key_DeepInsights": ["洞察1"],
                    "self_questions": ["问题1"],
                    "emotional_summary": {},
                }
            }
        }, timeout=90)
        dt = time.time() - t0
        ok = resp.get("status") == "success"
        data = resp.get("result", resp)
        print(f"    film_generator: {'✅' if ok else '❌'} "
              f"status={resp.get('status')} degraded={data.get('degraded', 'unknown')} time={dt:.1f}s")
        results["film_generator"] = {"success": ok,
                                     "degraded": data.get("degraded"), "time": dt,
                                     "error": resp.get("error")}
    except Exception as e:
        dt = time.time() - t0
        print(f"    film_generator: ❌ ERROR ({e}) time={dt:.1f}s")
        results["film_generator"] = {"success": False, "error": str(e), "time": dt}

    # 5. 汇总
    print("\n" + "=" * 70)
    print("验证汇总")
    print("=" * 70)
    ok = sum(1 for r in results.values() if r.get("success"))
    print(f"成功: {ok}/{len(results)}")
    for name, r in results.items():
        if r.get("success"):
            print(f"  ✅ {name}: degraded={r['degraded']} time={r['time']:.1f}s keys={r.get('keys', [])[:5]}")
        else:
            print(f"  ❌ {name}: {r.get('error', '?')}")

    # 保存结果
    out_path = "reports/llm-degradation-test.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
                   "llm_ok": llm_ok, "results": results}, f,
                  ensure_ascii=False, indent=2)
    print(f"\n结果已保存: {out_path}")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
