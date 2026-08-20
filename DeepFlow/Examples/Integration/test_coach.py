"""快速测试 decision_coach 技能"""
import requests
import json

url = "http://127.0.0.1:8001/skills/execute"
payload = {
    "skill_name": "decision_coach",
    "params": {
        "problem": "职业选择：专家路线 vs 创业负责人？"
    }
}

print("Sending request to:", url)
print("Payload:", json.dumps(payload, indent=2, ensure_ascii=False))
print("")

response = requests.post(url, json=payload, timeout=30)

print(f"Status: {response.status_code}")
print("")
print("Response:")
if response.ok:
    data = response.json()
    print(json.dumps(data, indent=2, ensure_ascii=False))
else:
    print("FAILED:", response.text)
