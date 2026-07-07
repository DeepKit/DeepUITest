# iFLYTEK Coding Plan 模型配置（讯飞编程套餐）

> **状态**：连通性已验证（14/14 模型可达），InkFlow 集成测试通过（`tests/test_iflytek_integration.py`）。
> **更新**：2026-07-07

## 1. 套餐与凭据

- 订单：讯飞 Coding Plan（MaaS Coding API）
- 端点：`https://maas-coding-api.cn-huabei-1.xf-yun.com/v2/chat/completions`
- 鉴权：HTTP 头 `Authorization: Bearer <appId:apiKey>` —— **整串**作为 Bearer token，不是只用冒号后半段
- 协议：OpenAI 兼容 `/chat/completions`，可直接用 InkFlow 的 `OpenAICompatibleProvider`

配置模板见 `.env.iflytek.example`。

## 2. 16 个模型分类

| 模型 ID | 家族 | 类型 | 备注 |
|---|---|---|---|
| `xopglm52` | 智谱 GLM-5.2 | 标准 | 卡，不推荐写作用 |
| `xopglm51` | 智谱 GLM-5.1 | 标准 | **写作主模型** |
| `xopglm5` | 智谱 GLM-5 | 标准 | 默认选中 |
| `xopglmv47flash` | 智谱 GLM-4.7-Flash | 标准 | |
| `xopkimik26` | 月之暗面 Kimi-K2.6 | 标准 | 长上下文强 |
| `xopkimik25` | 月之暗面 Kimi-K2.5 | 标准 | |
| `xopdeepseekv4pro` | DeepSeek-V4-Pro | 标准 | **裁判/审阅**，推理强 |
| `xopdeepseekv4flash` | DeepSeek-V4-Flash | 标准 | 快 |
| `xopdeepseekv32` | DeepSeek-V3.2 | 标准 | |
| `xopqwen36v35b` | 阿里 Qwen-3.6-35B-A3B | 标准 | 最快（~0.5s） |
| `xopqwen35v35b` | 阿里 Qwen-3.5-35B-A3B | 标准 | |
| `xopqwen35397b` | 阿里 Qwen-3.5-397B-A17B | 标准 | **大模型，审阅用** |
| `xop3qwencodernext` | 阿里 Qwen3-Coder-Next | 标准 | 代码模型，写作弱 |
| `xminimaxm25` | MiniMax-M2.5 | **推理** | 消耗 reasoning_content |
| `xsparkx2` | 讯飞 Spark-X2 | **推理** | 慢（~6-14s） |
| `xsparkx2flash` | 讯飞 Spark-X2-Flash | **推理** | 慢，token 消耗大 |

> 套餐**没有 MiniMax-M3、没有 Qwen3.7**——最新是 MiniMax-M2.5、Qwen-3.6-35B。

**推理模型注意**：`max_tokens` 需 ≥ 500，否则 token 被 `reasoning_content` 吃光，`content` 为空。InkFlow 当前 `OpenAICompatibleProvider` 不传 `max_tokens`（依赖模型默认值），对推理模型可能返回空 content。小说写作**优先用标准模型**。

## 3. 推荐的模型池配置

写入 `writing_projects.writer_model_pool` / `jury_model_pool`（JSON 数组）：

### 写作模型池（writer_model_pool）—— 草稿生成

```json
["xopglm51", "xopdeepseekv4pro", "xopkimik26"]
```

- **3 个不同家族**（智谱 GLM-5.1 / DeepSeek-V4-Pro / Kimi-K2.6），保证多样性
- 都是标准模型，content 直接产出，GLM-5.1 比 5.2 快不卡
- DB CHECK 要求 `json_array_length >= draft_count`（默认 3）

### 裁判模型池（jury_model_pool）—— 章节审阅

```json
["xopglm51", "xopdeepseekv4pro", "xopqwen36v35b", "xopkimik26", "xopqwen35397b"]
```

- **5 个家族**，DB CHECK 要求 `>= jury_model_pool_min`（默认 3）
- `xopqwen35397b`（397B 大模型）做深度审阅，质量高
- 可用 `xopqwen36v35b` 做快速初筛（最便宜最快）
- 不含推理模型（MiniMax-M2.5 等），避免 `max_tokens` 适配问题（见 tasks.md 第 3 项）

### 配置方式

`init` 命令当前硬编码默认池，需通过 SQL 更新：

```sql
UPDATE writing_projects
SET writer_model_pool = '["xopglm51","xopdeepseekv4pro","xopkimik26"]',
    jury_model_pool = '["xopglm51","xopdeepseekv4pro","xopqwen36v35b","xopkimik26","xopqwen35397b"]'
WHERE code = '<your-project-code>';
```

## 4. 运行时调用

环境变量：

```bash
export INK_LLM_PROVIDER=openai-compatible
export INK_LLM_BASE_URL=https://maas-coding-api.cn-huabei-1.xf-yun.com/v2
export INK_LLM_API_KEY=83e14cca3d4042e045c62358f11ffdfa:ZmFkMzNhMWVkOTY0NzYyYmZjZWFmYjFl
```

或 CLI 参数：

```bash
ink --llm-provider openai-compatible \
    --llm-base-url https://maas-coding-api.cn-huabei-1.xf-yun.com/v2 \
    --llm-api-key-env INK_LLM_API_KEY \
    <command> ...
```

## 5. 已知限制

1. **API 限流**：连续高频调用返回 `503 code:10310 "The system is busy"`。批量测试需间隔 ≥ 2-3 秒。集成测试已内置 3 次重试 + skip。
2. **推理模型 content 为空**：`max_tokens` 不足时。当前 `OpenAICompatibleProvider` 不传 `max_tokens`，故池中推理模型需后续增强（见 tasks.md 待办）。
3. **Idempotency-Key**：重试时必须用新 key，否则 DB UNIQUE 约束冲突。
