"""测试 film_generator 的输出结构"""
import requests
import json

# 先模拟聚合器输出
aggregated_input = {
    "coach_view": {"role": "coach", "insights": ["..."]},
    "critic_view": {"role": "critic", "insights": ["..."]},
    "mirror_view": {"role": "mirror", "insights": ["..."]},
    "observer_view": {"role": "observer", "insights": ["..."]}
}

url = "http://127.0.0.1:8001/skills/execute"
payload = {
    "skill_name": "film_generator",
    "params": {
        "problem": "职业选择：专家路线 vs 创业负责人？",
        "aggregated": aggregated_input
    }
}

print("Testing film_generator output structure...")
response = requests.post(url, json=payload, timeout=30)

if response.ok:
    data = response.json()
    print("\n=== Full Response ===")
    print(json.dumps(data, indent=2, ensure_ascii=False))
    
    result = data.get("result", {})
    print("\n=== Result Keys ===")
    for key in result.keys():
        print(f"- {key}: {type(result[key]).__name__}")
else:
    print("FAILED:", response.text)
