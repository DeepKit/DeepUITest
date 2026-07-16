# iFLYTEK / WiseGateway 模型配置

> 状态：Scene-first 当前配置说明
> 安全规则：本文不得保存真实 API Key、App ID、Bearer Token 或组合凭据

## 1. 接入

推荐通过本机 WiseGateway 统一接入，避免在 Ink 项目中保存供应商凭据。

```text
Base URL: http://127.0.0.1:8000
API Key: 仅从环境变量读取
```

供应商直连仅用于故障诊断，凭据格式使用占位符：

```bash
export INK_LLM_PROVIDER=openai-compatible
export INK_LLM_BASE_URL=https://maas-coding-api.cn-huabei-1.xf-yun.com/v2
export INK_LLM_API_KEY="<appId:apiKey>"
```

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

## 3. 写作模型池

写作候选需要不同模型家族。模型池只决定模型来源，不替代：

- Scene Contract；
- Candidate Branch；
- 多样性门；
- 文学绝对门槛。

禁止同一模型评审自己生成的候选。

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
