"""探测 WiseGateway 各 route 代表模型 (2026-08-08)"""
import concurrent.futures
import json
import os
import urllib.request
import time

API = "http://127.0.0.1:8000/v1/messages"
KEY = os.environ.get("KIRO_API_KEY", "")

CANDIDATES = [
    ("qoder", "claude-qoder-glm-5-2"),
    ("qoder", "claude-qoder-kimi-k3"),
    ("qoder", "claude-qoder-deepseek-v4-pro"),
    ("qoder", "claude-qoder-minimax-m3"),
    ("qoder", "claude-qoder-qwen3-7-max"),
    ("cloudflare", "claude-cloudflare-kimi-k2-6"),
    ("huggingface", "claude-huggingface-deepseek-v4-flash"),
    ("ms", "claude-ms-deepseek-v4-flash"),
    ("ms", "claude-ms-minimax-m3"),
    ("nim", "claude-nim-glm-5-2"),
    ("nim", "claude-nim-deepseek-v4-pro"),
    ("gemini", "claude-gemini-3-5-flash"),
    ("duojie", "claude-duojie-claude-sonnet-4-6"),
    ("sensenova", "claude-sensenova-deepseek-v4-flash"),
]

def call(model: str, timeout: int = 40) -> str:
    payload = {
        "model": model,
        "max_tokens": 200,
        "messages": [{"role": "user", "content": "Reply with exactly: OK"}],
    }
    req = urllib.request.Request(
        API,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "x-api-key": KEY,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return "".join(
        x.get("text", "") for x in data.get("content", []) if x.get("type") == "text"
    )

def probe(item):
    route, model = item
    started = time.time()
    try:
        text = call(model)
        return {
            "route": route,
            "model": model,
            "status": "ok",
            "latency_s": round(time.time() - started, 2),
            "reply": text.strip()[:60],
        }
    except Exception as exc:
        return {
            "route": route,
            "model": model,
            "status": "error",
            "latency_s": round(time.time() - started, 2),
            "error": repr(exc)[:200],
        }

results = []
with concurrent.futures.ThreadPoolExecutor(max_workers=14) as ex:
    for r in ex.map(probe, CANDIDATES):
        results.append(r)

path = "D:/_Progs/02Business/DeepFlow/Skills/tmp_route_probe.json"
with open(path, "w", encoding="utf-8") as f:
    json.dump({"checked_at": "2026-08-08", "results": results}, f, ensure_ascii=False, indent=2)
for r in results:
    print(f"[{r['route']:12s}] {r['model']:45s} {r['status']:6s} {r.get('latency_s', '')}s {r.get('reply', r.get('error', ''))}")
