"""探测 WiseGateway 是否支持 OpenAI /v1/chat/completions 格式"""
import json
import urllib.request
import os

KEY = os.environ.get("KIRO_API_KEY", "fuyi-kiro-17781158558")

payload = {
    "model": "claude-qoder-glm-5-2",
    "max_tokens": 50,
    "messages": [{"role": "user", "content": "Reply with exactly: OK"}],
}

req = urllib.request.Request(
    "http://127.0.0.1:8000/v1/chat/completions",
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "x-api-key": KEY,
        "content-type": "application/json",
    },
    method="POST",
)

try:
    with urllib.request.urlopen(req, timeout=40) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    print("STATUS: OK")
    print("KEYS:", list(data.keys()))
    content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
    print("CONTENT:", content[:100])
except Exception as exc:
    print("ERROR:", repr(exc))
