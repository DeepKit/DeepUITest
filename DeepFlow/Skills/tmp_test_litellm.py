"""直接测试 litellm 调用 WiseGateway，查看实际请求路径"""
import asyncio
import os
import logging

logging.basicConfig(level=logging.DEBUG)

async def main():
    import litellm
    litellm.set_verbose = True
    
    try:
        response = await litellm.acompletion(
            model="openai/claude-qoder-glm-5-2",
            messages=[{"role": "user", "content": "Reply with exactly: OK"}],
            api_key=os.environ.get("KIRO_API_KEY", "fuyi-kiro-17781158558"),
            api_base="http://127.0.0.1:8000/v1",
            timeout=40,
            num_retries=1,
            max_tokens=100,
        )
        print("SUCCESS:", response.choices[0].message.content)
    except Exception as exc:
        print("ERROR:", repr(exc))

asyncio.run(main())
