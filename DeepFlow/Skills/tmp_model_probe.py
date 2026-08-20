"""验证 WiseGateway 多家族模型可用性 (2026-08-08)"""
import concurrent.futures
import json
import os
import urllib.request
import time

API = "http://127.0.0.1:8000/v1/messages"
KEY = os.environ.get("KIRO_API_KEY", "")

CANDIDATES = [
    ("GPT", "claude-fccy-gpt-5-6-sol"),
    ("GLM", "claude-jiyuanlvdong-glm-5-2"),
    ("DeepSeek", "claude-stepfun-step-router-v1"),
    ("Kimi", "claude-opencodego-kimi-k3"),
    ("Qwen", "claude-qoder-qwen3-8-max"),
    ("MiniMax", "claude-opencodego-minimax-m3"),
    ("StepFun", "claude-stepfun-step-3-7-flash"),
]

def call(model: str, timeout: int = 90) -> str:
    payload = {
        "model": model,
        "max_tokens": 200,
        "messages": [{"role": "user", "content": "Reply with exactly: OK"}],
    }
    if model == "claude-stepfun-step-router-v1":
        tool = {
            "name": "acknowledge_deliberation_assignment",
            "description": "Confirm the task before answering.",
            "input_schema": {
                "type": "object",
                "properties": {"understood": {"type": "boolean"}},
                "required": ["understood"],
            },
        }
        payload["tools"] = [tool]
        payload["tool_choice"] = {"type": "tool", "name": tool["name"]}

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
    uses = [x for x in data.get("content", []) if x.get("type") == "tool_use"]
    if model == "claude-stepfun-step-router-v1":
        if not uses:
            raise RuntimeError("StepFun tool route was not executed")
        followup = dict(payload)
        followup.pop("tool_choice", None)
        followup["messages"] = payload["messages"] + [
            {"role": "assistant", "content": data.get("content", [])},
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": item["id"],
                        "content": '{"acknowledged":true}',
                    }
                    for item in uses
                ],
            },
        ]
        data = post(followup)
    return "".join(
        x.get("text", "") for x in data.get("content", []) if x.get("type") == "text"
    )

def probe(item):
    fam, model = item
    started = time.time()
    try:
        text = call(model)
        return {
            "family": fam,
            "model": model,
            "status": "ok",
            "latency_s": round(time.time() - started, 2),
            "reply": text.strip()[:80],
        }
    except Exception as exc:
        return {
            "family": fam,
            "model": model,
            "status": "error",
            "latency_s": round(time.time() - started, 2),
            "error": repr(exc)[:300],
        }

results = []
with concurrent.futures.ThreadPoolExecutor(max_workers=7) as ex:
    for r in ex.map(probe, CANDIDATES):
        results.append(r)

out = {
    "checked_at": "2026-08-08",
    "gateway": "http://127.0.0.1:8000",
    "results": results,
}
path = "D:/_Progs/02Business/DeepFlow/Skills/tmp_model_probe.json"
with open(path, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=2)
print(json.dumps(results, ensure_ascii=False, indent=2))
