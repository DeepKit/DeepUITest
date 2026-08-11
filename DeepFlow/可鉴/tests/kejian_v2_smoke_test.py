# -*- coding: utf-8 -*-
"""
可鉴 · 决策操作系统 — v2 能力冒烟测试 (T18 封版审计)
=====================================================
覆盖 T13/T14/T19/T20 新增能力（不调用 LLM 全文生成，快速验证）：

- /health 健康检查
- /skills 技能清单（含 mind_xray）
- /governance/history CRUD（列出/保存/删除/清空）— T14/T19a
- /llm/families 多家族映射 — T20
- /llm/chat/by-name 按名调用（1 次短回复验证，glm）— T20
- /llm/xray 结构验证（decision 模式，短 history_summary）— T19b
- /llm/xray/treehole 树洞 X 光片结构验证 — T19b

注意：by-name/xray 需 LLM 真实调用，timeout 设为 180s（避免偶发超时误判）
使用方法：
    python kejian_v2_smoke_test.py
    python kejian_v2_smoke_test.py --api http://127.0.0.1:8002
"""

import argparse
import asyncio
import json
import sys
import time
from typing import Any, Dict, List

import aiohttp

DEFAULT_API = "http://127.0.0.1:8002"


class V2SmokeTester:
    """v2 能力冒烟测试运行器"""

    def __init__(self, base: str):
        self.base = base
        self.results: List[Dict[str, Any]] = []

    def record(self, name: str, ok: bool, detail: str = "") -> None:
        self.results.append({"name": name, "ok": ok, "detail": detail})
        mark = "PASS" if ok else "FAIL"
        print(f"  [{mark}] {name}" + (f" — {detail}" if detail else ""))

    async def run(self) -> int:
        async with aiohttp.ClientSession() as session:
            await self.test_health(session)
            await self.test_skills(session)
            await self.test_history_crud(session)
            await self.test_families(session)
            await self.test_by_name(session)  # glm 短回复
            await self.test_xray_decision(session)  # decision xray
            await self.test_xray_treehole(session)  # treehole xray

        passed = sum(1 for r in self.results if r["ok"])
        total = len(self.results)
        print(f"\n{'=' * 50}")
        print(f"v2 冒烟测试：{passed}/{total} 通过")
        for r in self.results:
            if not r["ok"]:
                print(f"  FAIL: {r['name']} — {r['detail']}")
        return 0 if passed == total else 1

    async def get_json(self, session: aiohttp.ClientSession, path: str, timeout: int = 10):
        async with session.get(self.base + path, timeout=aiohttp.ClientTimeout(total=timeout)) as resp:
            return resp.status, await resp.json()

    async def post_json(self, session: aiohttp.ClientSession, path: str, body: Dict, timeout: int = 180):
        async with session.post(self.base + path, json=body, timeout=aiohttp.ClientTimeout(total=timeout)) as resp:
            text = await resp.text()
            try:
                return resp.status, json.loads(text)
            except Exception:
                return resp.status, {"_raw": text[:200]}

    async def delete_json(self, session: aiohttp.ClientSession, path: str, timeout: int = 10):
        async with session.delete(self.base + path, timeout=aiohttp.ClientTimeout(total=timeout)) as resp:
            return resp.status, await resp.text()

    # ---------------- 用例 ----------------

    async def test_health(self, session: aiohttp.ClientSession) -> None:
        """T0: 健康检查"""
        status, data = await self.get_json(session, "/health")
        self.record("health", status == 200 and data.get("status") == "healthy",
                    f"HTTP {status}, skills={data.get('skills_loaded')}")

    async def test_skills(self, session: aiohttp.ClientSession) -> None:
        """T19: 技能清单含 mind_xray"""
        status, data = await self.get_json(session, "/skills")
        names = [s.get("name") for s in data] if isinstance(data, list) else []
        expect = {"code_executor", "decision_coach", "decision_critic",
                  "decision_mirror", "decision_observer", "decision_aggregator",
                  "film_generator", "mind_xray"}
        missing = expect - set(names)
        self.record("skills 清单", status == 200 and not missing,
                    f"缺失：{missing or '无'}, 共 {len(names)} 个")

    async def test_history_crud(self, session: aiohttp.ClientSession) -> None:
        """T14/T19a: 历史持久化 CRUD"""
        ts = int(time.time() * 1000)
        rid = f"h{ts}"
        body = {
            "id": rid, "ts": ts, "problem": "封版审计冒烟测试",
            "template": "strategic",
            "payload": {"kind": "decision", "degraded": False, "totalSec": "0.1"},
        }
        status, _ = await self.post_json(session, "/governance/history", body, timeout=10)
        self.record("history 保存", status in (200, 201), f"HTTP {status}")

        status, data = await self.get_json(session, "/governance/history?limit=200")
        items = data.get("items", []) if isinstance(data, dict) else []
        found = any(i.get("id") == rid for i in items)
        self.record("history 列出", status == 200 and found,
                    f"共 {len(items)} 条，找到测试记录：{found}")

        status, _ = await self.delete_json(session, f"/governance/history/{rid}")
        self.record("history 删除单条", status in (200, 204), f"HTTP {status}")

        status, data = await self.get_json(session, "/governance/history?limit=200")
        items = data.get("items", []) if isinstance(data, dict) else []
        gone = all(i.get("id") != rid for i in items)
        self.record("history 删除生效", status == 200 and gone, f"残留：{not gone}")

    async def test_families(self, session: aiohttp.ClientSession) -> None:
        """T20: 多家族映射"""
        status, data = await self.get_json(session, "/llm/families")
        fams = data.get("families", {}) if isinstance(data, dict) else {}
        expect = {"gpt", "glm", "deepseek", "kimi", "qwen", "minimax", "stepfun", "spark"}
        missing = expect - set(fams.keys())
        self.record("llm/families", status == 200 and not missing,
                    f"缺失家族：{missing or '无'}, 共 {len(fams)} 个")

    async def test_by_name(self, session: aiohttp.ClientSession) -> None:
        """T20: 按名调用（glm 短回复）"""
        body = {
            "model": "glm",
            "messages": [{"role": "user", "content": "回复两个字：收到"}],
            "max_tokens": 10,
        }
        status, data = await self.post_json(session, "/llm/chat/by-name", body, timeout=120)
        content = (data.get("content") or "") if isinstance(data, dict) else ""
        self.record("by-name(glm)", status == 200 and len(content) > 0,
                    f"HTTP {status}, 回复：{content[:30]}")

    async def test_xray_decision(self, session: aiohttp.ClientSession) -> None:
        """T19b: X 光片（decision 模式）"""
        body = {
            "problem": "封版审计冒烟：是否发布 v1.0.0",
            "material": "胶片摘要：功能完整，测试通过，建议发布",
            "history_summary": "",
            "mode": "decision",
        }
        status, data = await self.post_json(session, "/llm/xray", body, timeout=180)
        ok = status == 200 and isinstance(data, dict)
        if ok:
            ok = "core_obsession" in data and "narrative" in data
        self.record("xray(decision)", ok,
                    f"HTTP {status}, 字段：{list(data.keys())[:5] if isinstance(data, dict) else data}")

    async def test_xray_treehole(self, session: aiohttp.ClientSession) -> None:
        """T19b: X 光片（treehole 模式）"""
        body = {
            "problem": "最近压力很大",
            "material": "树洞对话：我：最近压力很大。树洞：我在这里。",
            "history_summary": "",
            "mode": "treehole",
        }
        status, data = await self.post_json(session, "/llm/xray", body, timeout=180)
        ok = status == 200 and isinstance(data, dict) and data.get("mode") == "treehole"
        self.record("xray(treehole)", ok, f"HTTP {status}, mode={data.get('mode') if isinstance(data, dict) else '?'}")


def main() -> int:
    parser = argparse.ArgumentParser(description="可鉴 v2 能力冒烟测试")
    parser.add_argument("--api", default=DEFAULT_API, help="Skills API 地址")
    args = parser.parse_args()
    tester = V2SmokeTester(args.api.rstrip("/"))
    return asyncio.run(tester.run())


if __name__ == "__main__":
    sys.exit(main())
