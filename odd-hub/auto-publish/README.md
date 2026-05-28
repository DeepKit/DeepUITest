# auto-publish

ODD 多平台自动发布工具。git tag 触发后自动生成中英文内容并发布到 8 个平台�?
## 支持平台

| 平台 | 认证方式 | 内容语言 |
|------|---------|---------|
| GitHub Release | API Token | 英文 |
| Dev.to | API Key | 英文 |
| Hashnode | Token + Publication ID | 英文 |
| Reddit | OAuth (client_id + secret + password) | 英文 |
| Telegram | Bot Token + Chat ID | 中文 |
| 掘金 | Cookie | 中文 |
| 即刻 | Cookie | 中文 |
| 知乎专栏 | Cookie | 中文 |

## 快速开�?
### 1. 配置 GitHub Secrets

在仓�?Settings �?Secrets and variables �?Actions 中添加：

```
OPENAI_API_KEY          # 必填，用�?AI 生成内容

GITHUB_TOKEN            # 自动提供，无需手动添加
DEVTO_API_KEY           # Dev.to Settings �?Extensions �?DEV API Keys
HASHNODE_TOKEN          # Hashnode Settings �?Developer �?Personal Access Token
HASHNODE_PUBLICATION_ID # Hashnode Dashboard URL 中的 ID
REDDIT_CLIENT_ID        # Reddit App �?create app �?client_id
REDDIT_CLIENT_SECRET    # Reddit App �?secret
REDDIT_USERNAME         # Reddit 用户�?REDDIT_PASSWORD         # Reddit 密码
REDDIT_SUBREDDIT        # 发布到哪�?subreddit，如 r/programming
TELEGRAM_BOT_TOKEN      # @BotFather 创建 Bot 后获�?TELEGRAM_CHAT_ID        # 频道 ID，如 @your_channel �?-100xxxxxxxxx

JUEJIN_COOKIE           # 见下�?Cookie 获取方法
JIKE_COOKIE             # 见下�?Cookie 获取方法
ZHIHU_COOKIE            # 见下�?Cookie 获取方法
```

**按需配置**：未设置的平台会自动跳过，不影响其他平台�?
### 2. 触发发布

**自动触发**（推荐）�?```bash
git tag v1.2.0
git push origin v1.2.0
```

**手动触发**�?GitHub Actions �?Auto Publish �?Run workflow �?输入 tag

### 3. 查看结果

Actions 运行完成后，Summary 页面会显示每个平台的发布状态和链接�?
---

## Cookie 获取方法

Cookie �?30 天过期。过期后 Actions 会失败，Telegram 会收到提醒通知�?
### 掘金
1. 浏览器打开 juejin.cn 并登�?2. F12 �?Network �?任意请求 �?Request Headers �?Cookie
3. 复制整个 Cookie 字符�?
### 即刻
1. 浏览器打开 web.okjike.com 并登�?2. F12 �?Application �?Cookies �?web.okjike.com
3. 复制 `x-jike-access-token` 的值（只需这一个）

### 知乎
1. 浏览器打开 zhihu.com 并登�?2. F12 �?Network �?任意请求 �?Request Headers �?Cookie
3. 复制整个 Cookie 字符�?
---

## 本地测试

```bash
pip install -e ".[dev]"

export OPENAI_API_KEY=sk-...
export RELEASE_TAG=v1.0.0
export RELEASE_CHANGELOG="- 新增功能 A\n- 修复 Bug B"
export GITHUB_TOKEN=ghp_...   # 只测�?GitHub 的话

python -m auto_publish.main
```

## 架构

```
auto-publish/
├── src/auto_publish/
�?  ├── generate.py          # OpenAI 生成中英文内�?�?  ├── main.py              # 主入口，协调所有平�?�?  └── publishers/
�?      ├── github.py        # GitHub Release API
�?      ├── devto.py         # Dev.to API
�?      ├── hashnode.py      # Hashnode GraphQL API
�?      ├── reddit.py        # Reddit OAuth API
�?      ├── telegram.py      # Telegram Bot API
�?      ├── juejin.py        # 掘金 Cookie
�?      ├── jike.py          # 即刻 Cookie
�?      └── zhihu.py         # 知乎 Cookie
└── .github/workflows/
    └── auto-publish.yml     # GitHub Actions 触发�?```
