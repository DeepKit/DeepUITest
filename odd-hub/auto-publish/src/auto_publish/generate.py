"""
内容生成�?�?支持多种 AI 提供商（OpenAI / DeepSeek / Anthropic�?"""
from __future__ import annotations
import os
from dataclasses import dataclass
from openai import OpenAI


@dataclass
class PublishContent:
    version: str
    title_en: str
    title_zh: str
    body_en: str       # Markdown, for Dev.to / Hashnode / Reddit
    body_zh: str       # Markdown, for 掘金 / 知乎
    short_en: str      # �?80 chars, for Telegram
    short_zh: str      # �?40 chars, for 即刻


_SYSTEM_EN = """You are a developer advocate writing release announcements for ODD (Output-Driven Development),
a CLI tool that makes AI-generated code verifiable via contracts.
Write concise, engaging content for developers. No hype, just facts."""

_SYSTEM_ZH = """你是 ODD (Output-Driven Development) 的开发者布道师�?ODD 是一个让 AI 生成代码可验证的 CLI 工具，通过契约机制降低工程风险�?用简洁、有价值的语言写发布公告，面向中文开发者社区。不要夸大，只讲事实�?""


def _make_client() -> tuple[OpenAI, str]:
    """根据环境变量选择 AI 提供商，返回 (client, model)�?""
    if os.environ.get("NIM_API_KEY"):
        return OpenAI(
            api_key=os.environ["NIM_API_KEY"],
            base_url="https://integrate.api.nvidia.com/v1",
        ), os.environ.get("NIM_MODEL", "deepseek-ai/deepseek-v3.2")
    if os.environ.get("DEEPSEEK_API_KEY"):
        return OpenAI(
            api_key=os.environ["DEEPSEEK_API_KEY"],
            base_url="https://api.deepseek.com",
        ), "deepseek-chat"
    if os.environ.get("OPENAI_API_KEY"):
        return OpenAI(api_key=os.environ["OPENAI_API_KEY"]), "gpt-4o-mini"
    raise RuntimeError(
        "未找�?AI 提供商密钥。请设置 NIM_API_KEY、DEEPSEEK_API_KEY �?OPENAI_API_KEY�?
    )


def generate(version: str, changelog: str, repo_url: str) -> PublishContent:
    client, model = _make_client()
    def ask(system: str, user: str) -> str:
        r = client.chat.completions.create(
            model=model,
            messages=[{"role": "system", "content": system},
                      {"role": "user", "content": user}],
            temperature=0.7,
        )
        return (r.choices[0].message.content or "").strip()

    # English long-form (title derived from body's first line)
    body_en = ask(_SYSTEM_EN, f"""Write a release announcement for odd-core {version}.
{changelog}

Repo: {repo_url}
Format: Markdown. Include:
- 1-sentence summary
- What's new (bullet list)
- Quick install: `pip install odd-core=={version}`
- Link to repo
Keep it under 400 words.""")
    # Short English (Telegram)
    short_en = ask(_SYSTEM_EN,
                   f"Write a Telegram announcement for odd-core {version} (max 280 chars). Include install command and repo link {repo_url}. Changelog: {changelog[:300]}")
    body_zh = ask(_SYSTEM_ZH, f"""�?odd-core {version} 写一篇发布公告�?更新日志�?{changelog}

仓库：{repo_url}
格式：Markdown。包含：
- 一句话总结
- 新增内容（列表）
- 快速安装：`pip install odd-core=={version}`
- 仓库链接

控制�?400 字以内�?"")
    # Short Chinese (即刻)
    short_zh = ask(_SYSTEM_ZH,
                   f"�?odd-core {version} 写一条即刻动态（最�?140 字）。包含安装命令和仓库链接 {repo_url}。更新日志：{changelog[:300]}")
    # Titles derived from first line of body (no extra API call)
    title_en = body_en.splitlines()[0].lstrip("# ").strip() if body_en else ""
    title_zh = body_zh.splitlines()[0].lstrip("# ").strip() if body_zh else ""
    return PublishContent(
        version=version,
        title_en=title_en,
        title_zh=title_zh,
        body_en=body_en,
        body_zh=body_zh,
        short_en=short_en,
        short_zh=short_zh,
    )
