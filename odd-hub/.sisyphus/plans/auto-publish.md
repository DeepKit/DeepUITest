# auto-publish 工作计划

> 目标：ODD 多平台自动发布系�?> 触发：git tag + 手动触发
> 平台：GitHub Release / Dev.to / Reddit / Hashnode / Telegram / 掘金 / 即刻 / 知乎
> 内容：AI 自动生成中英文，全自动发布（无人工审核）

---

## 架构概览

```
git tag v1.x.x  OR  手动触发
        �?GitHub Actions: .github/workflows/auto-publish.yml
        �?tools/publisher/
  ├── generate.py        �?AI 生成中英文内�?  ├── platforms/
  �?  ├── github.py      �?GitHub Release（官�?API�?  �?  ├── devto.py       �?Dev.to（官�?API�?  �?  ├── reddit.py      �?Reddit（官�?API�?  �?  ├── hashnode.py    �?Hashnode（GraphQL API�?  �?  ├── telegram.py    �?Telegram Bot（官�?API�?  �?  ├── juejin.py      �?掘金（Cookie 模拟�?  �?  ├── jike.py        �?即刻（Cookie 模拟�?  �?  └── zhihu.py       �?知乎（Cookie 模拟�?  └── main.py            �?统一入口
```

---

## 任务清单

### 第一步：基础框架

- [x] 创建 `tools/publisher/` 目录结构�?`pyproject.toml`
- [x] 实现 `generate.py` �?调用 OpenAI/Claude API，从 CHANGELOG 生成中英文内�?- [x] 实现 `main.py` �?统一入口，读取环境变量，调度各平台发�?
### 第二步：免费官方 API 平台（无 Cookie�?
- [x] `github.py` �?创建/更新 GitHub Release，附�?release notes
- [x] `devto.py` �?发布英文技术文章（Dev.to API key�?- [x] `hashnode.py` �?发布英文文章（Hashnode GraphQL API�?- [x] `reddit.py` �?发布�?r/programming / r/Python（Reddit OAuth2�?- [x] `telegram.py` �?发送消息到 Telegram 频道（Bot Token�?
### 第三步：Cookie 模拟平台（中文）

- [x] `juejin.py` �?掘金发布文章（Cookie + 逆向 API�?- [x] `jike.py` �?即刻发布动态（Cookie + 逆向 API�?- [x] `zhihu.py` �?知乎发布文章（Cookie + 逆向 API�?
### 第四步：GitHub Actions 集成

- [x] `.github/workflows/auto-publish.yml` �?git tag 触发 + workflow_dispatch 手动触发
- [x] GitHub Secrets 配置文档 `tools/publisher/SETUP.md`

### 第五步：测试与验�?
- [x] 单元测试：`tools/publisher/tests/test_generate.py`
- [x] 集成测试：dry-run 模式（不真实发布，只打印内容�?- [ ] 端到端验证：手动触发一次，确认各平台收到内�?
---

## 环境变量清单

```
# AI 内容生成
OPENAI_API_KEY=

# 官方 API 平台
GITHUB_TOKEN=          # 自动注入，无需配置
DEVTO_API_KEY=
HASHNODE_API_KEY=
HASHNODE_PUBLICATION_ID=
REDDIT_CLIENT_ID=
REDDIT_CLIENT_SECRET=
REDDIT_USERNAME=
REDDIT_PASSWORD=
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHANNEL_ID=

# Cookie 平台（约 30 天过期，需手动刷新�?JUEJIN_COOKIE=
JIKE_COOKIE=
ZHIHU_COOKIE=
```

---

## 技术决�?
- Python 3.11+，依赖：`httpx`, `openai`, `praw`（Reddit SDK�?- 内容格式：Markdown（英文）/ Markdown（中文）
- 失败策略：单平台失败不影响其他平台，失败写入 GitHub Actions summary
- Cookie 刷新提醒：Actions 失败时自动发 Telegram 通知"Cookie 已过期，请刷�?
