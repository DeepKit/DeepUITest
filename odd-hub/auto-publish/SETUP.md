# SETUP �?GitHub Secrets 配置指南

## 必填 Secrets

�?GitHub 仓库 �?Settings �?Secrets and variables �?Actions 中添加：

### AI 内容生成（三选一，按优先级）
| Secret | 说明 | 获取方式 |
|--------|------|----------|
| `NIM_API_KEY` | NVIDIA NIM（推荐，免费额度大） | https://integrate.api.nvidia.com |
| `NIM_MODEL` | 可选，默认 `deepseek-ai/deepseek-v3.2` | 见下方模型列�?|
| `DEEPSEEK_API_KEY` | DeepSeek（备选） | https://platform.deepseek.com/api_keys |
| `OPENAI_API_KEY` | OpenAI（备选） | https://platform.openai.com/api-keys |

> 优先使用 `NIM_API_KEY`，未设置时依次回退�?`DEEPSEEK_API_KEY` �?`OPENAI_API_KEY`�?
**NIM 可用模型�?*
- `deepseek-ai/deepseek-v3.2`（默认）
- `nvidia/llama-3.3-nemotron-super-49b-v1.5`
- `qwen/qwen3.5-397b-a17b`
- `stepfun-ai/step-3.5-flash`

### 官方 API 平台
| Secret | 说明 | 获取方式 |
|--------|------|----------|
| `GITHUB_TOKEN` | 自动注入，无需配置 | �?|
| `DEVTO_API_KEY` | Dev.to API Key | https://dev.to/settings/extensions |
| `HASHNODE_TOKEN` | Hashnode Personal Access Token | https://hashnode.com/settings/developer |
| `HASHNODE_PUBLICATION_ID` | 你的 Publication ID | Hashnode dashboard URL 中的 ID |
| `REDDIT_CLIENT_ID` | Reddit App Client ID | https://www.reddit.com/prefs/apps |
| `REDDIT_CLIENT_SECRET` | Reddit App Secret | 同上 |
| `REDDIT_USERNAME` | Reddit 用户�?| �?|
| `REDDIT_PASSWORD` | Reddit 密码 | �?|
| `TELEGRAM_BOT_TOKEN` | Telegram Bot Token | @BotFather |
| `TELEGRAM_CHAT_ID` | 频道 ID，如 `@mychannel` �?`-100xxxxxxx` | �?|

### Cookie 平台（中文，�?30 天过期）
| Secret | 说明 | 刷新方式 |
|--------|------|----------|
| `JUEJIN_COOKIE` | 掘金登录 Cookie | 浏览�?DevTools �?Network �?复制 Cookie header |
| `JIKE_COOKIE` | 即刻登录 Cookie | 同上 |
| `ZHIHU_COOKIE` | 知乎登录 Cookie | 同上 |

## 可选环境变�?
| 变量 | 默认�?| 说明 |
|------|--------|------|
| `REPO_URL` | `https://github.com/odd-hub/odd` | 项目主页链接，嵌入发布内�?|
| `REDDIT_SUBREDDIT` | `Python` | 发布目标 subreddit |

## 手动触发（dry-run�?
```bash
# 本地测试，不真实发布
DRY_RUN=true RELEASE_TAG=v1.0.0 DEEPSEEK_API_KEY=sk-... python -m auto_publish.main
```

或在 GitHub Actions 页面 �?Run workflow �?填入 tag �?`dry_run: true`�?
## Cookie 过期处理

Cookie 平台失效时，Actions 会在对应平台输出 `FAIL`，但不影响其他平台�?Telegram 通知会同步发出（如已配置）。刷新步骤：

1. 浏览器登录对应平�?2. F12 �?Network �?任意请求 �?复制 `Cookie` header �?3. 更新对应 GitHub Secret
