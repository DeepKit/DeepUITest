# iFLYTEK / WiseGateway 模型配置

> 状态：Scene-first 当前配置说明
> 安全规则：本文不得保存真实 API Key、App ID、Bearer Token 或组合凭据

## 1. 接入

**硬规则：Ink 调用任何模型一律经本机 WiseGateway，不得直连供应商。**
ink 代码已数据驱动：`base_url` 取自 DB `writing_model_role_configs.base_url`（一律填
`http://127.0.0.1:8000/v1`），凭据取 `INK_LLM_API_KEY` 环境变量。供应商直连仅允许在
WiseGateway 自身或受控诊断中发生，不在 ink 工程内出现。

```text
Base URL: http://127.0.0.1:8000/v1
API Key 环境变量: INK_LLM_API_KEY
真实 key: 仅从 WiseGateway .env 的 PROXY_API_KEY 取用，不进 ink 仓库
```

供应商直连仅用于故障诊断，凭据格式使用占位符：

```bash
export INK_LLM_PROVIDER=openai-compatible
export INK_LLM_BASE_URL=https://maas-coding-api.cn-huabei-1.xf-yun.com/v2
export INK_LLM_API_KEY="<appId:apiKey>"
```

> 2026-07-17 实测 `GET /v1/models`（带 `PROXY_API_KEY`）返回 35 个模型，与本地缓存
> `~/.claude/cache/gateway-models.json` 一致。ink 接入用 `claude-xunfei-*` 前缀。

真实凭据必须存储在环境变量或受控密钥管理器中，不进入：

- Markdown；
- `.env` 提交；
- 测试fixture；
- 日志；
- Prompt快照；
- 评审报告。

## 2. 模型家族

可用模型以 WiseGateway 当前模型路由表为准。文学生产要求一家族一票，不把同一家族变体当作独立多样性。

推荐家族：

- GPT-5.6；
- GLM-5.2；
- DeepSeek V4 Pro；
- Kimi K2.6；
- Qwen3.5；
- MiniMax；
- StepFun。

### 2.1 可用模型基线（2026-07-17 实测，35 个）

`GET http://127.0.0.1:8000/v1/models` 全量。`claude-xunfei-*` 前缀为 ink 接入用文本模型；
`claude-stepfun-step-router-v1` 为写作路由器（见 `stepfun-router-recipe.md`，契约进
system、纯正文进 user、多轮续写 + advisor 外壳重试）。asr/tts/audio/coder 专用模型不
入写作/评审池。

| 家族 | xunfei 文本模型（ink 可直接接入） |
|---|---|
| deepseek | v4-pro、v4-flash、v3-2 |
| glm | 5-2、5-2-1m（1M 上下文）、5-1、5、4-7-flash |
| kimi | k2-6、k2-5 |
| minimax | m2-5 |
| qwen3 | 5-35b-a3b、5-397b-a17b、6-35b-a3b |
| spark | x2、x2-flash |

完整 id 前缀 `claude-xunfei-`，如 `claude-xunfei-deepseek-v4-pro`。另有非 xunfei 前缀
的 agnes/deepseek/fccy/modelscope/nim/stepfun 共 17 个（含多模态/音频/router）。

## 3. 写作模型池

写作候选需要不同模型家族。模型池只决定模型来源，不替代：

- Scene Contract；
- Candidate Branch；
- 多样性门；
- 文学绝对门槛。

禁止同一模型评审自己生成的候选。

### 3.1 池配置方案（供对比切换）

doctor `_check_model_pool_separation` 要求 writer/jury 池不重叠且 jury ≥ max(jury_min, 5)。
legacy 项目配置 writer/jury 池相同 3 模型、jury<5，故 doctor 报 fail——属项目级配置待办，
非模型短缺（基线 35 模型绰绰有余）。进③重产前需选一个 pool 配入 DB，doctor 全绿后开工。
换池对比时新增一行 pool，不改旧行，保留历史对照。

| 方案 | writer 池（主写） | jury 池（评审） | 说明 |
|---|---|---|---|
| pool-A（草案，待老板定） | deepseek-v4-pro、glm-5-2-1m、kimi-k2-6 | glm-5-1、qwen3-5-397b-a17b、minimax-m2-5、spark-x2、deepseek-v3-2 | writer 长程强（3 个= draft_count）；jury 5 个不同家族、与 writer 零重叠 |
| pool-B | _待定_ | _待定_ | 预留对比位 |
| pool-C | _待定_ | _待定_ | 预留对比位 |

> 选池原则：writer 池取长程/文学能力强的，数量 = draft_count；jury 池取与 writer 零重叠
> 的不同家族，数量 ≥ 5；同家族变体（如 glm-5-2 与 glm-5-1）不算独立多样性，跨池时需标注
> 家族以备 doctor 家族去重。最终模型清单老板裁定。

## 4. 契约与文学评审模型池

同一门的专家目的相近，但模型家族不同。评审必须记录：

```text
model_alias
model_family
resolved_provider
prompt_hash
blind_context_hash
visible_prior_reviews
```

StepFun Router使用工具调用触发内部路由时，还应记录：

- Router别名；
- 工具调用是否发生；
- 预期resolved model；
- 响应是否返回可验证的resolved model；
- 是否发生降级。

## 5. 调用预算

预算从项目数据库读取，至少分为：

- Scene生成预算；
- Chapter Generation Round预算；
- 契约复审预算；
- 文学选优预算；
- 失败重试预算。

旧的per-Shot预算只能用于Internal Shot局部生成，不能作为完整章节候选预算。

## 6. 安全处置

若历史文档或Git历史中出现真实凭据：

1. 立即轮换；
2. 清理当前文档；
3. 检查Git历史、日志和备份；
4. 启用secret scanning；
5. 不在修复记录中复述原值。
