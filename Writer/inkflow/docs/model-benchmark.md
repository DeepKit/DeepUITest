# InkFlow 写手模型基准测试

> 2026-06-21 | 测试场景：郑坤 Shot 1（绕城·石板滩·遇到年轻人）
> 评估标准：分析率、正文字数、感官质量、beat 覆盖率、成本

## 测试 Prompt 格式（Prompt 3，已验证最佳）

```
你是一个小说作家。直接写出以下场景的正文，不要任何分析或评论。

第一句话必须是：XXX

然后继续写：
- beat 1
- beat 2
...

现在开始写。
```

## 关键发现

**root cause**：之前分析率高的根本原因是 `max_tokens=2048` 太小。放大到 16384+ 后，所有模型分析率降到 0%。

## 测试结果

| 模型 | provider | max_tokens | reasoning_effort | 推理字数 | 正文字数 | 分析率 | 成本估算 | 推荐 |
|------|----------|:---:|:---:|:---:|:---:|:---:|------|:---:|
| `deepseek-v4-pro` | deepseek | 16384 | N/A | 333 | **2215** | 0% | 高 | ⭐⭐⭐ 最佳质量 |
| `deepseek-v4-pro` | deepseek | 8192 | N/A | 549 | 1575 | 0% | 高 | |
| `deepseek-v4-flash` | deepseek | 16384 | N/A | 289 | 779 | 0% | 低 | ⭐⭐ 性价比 |
| `deepseek-v4-flash` | deepseek | 8192 | N/A | 85 | 893 | 0% | 低 | |
| `step-router-v1` | stepfun | 32768 | default | 0 | 758 | 0% | 中 | ⭐⭐ 零推理开销 |
| `step-router-v1` | stepfun | 16384 | default | 0 | 646 | 0% | 中 | |
| `step-3.7-flash` | stepfun | 32768 | disabled | 2474 | 724 | 0% | 低 | ❌ 推理吃 77% |
| `step-3.7-flash` | stepfun | 32768 | low | 953 | 547 | 0% | 低 | ❌ 推理吃 63% |
| `step-3.7-flash` | stepfun | 16384 | low | 824 | 478 | 0% | 低 | ❌ |
| `step-3.5-flash` | stepfun | 32768 | low | 1511 | 512 | 0% | 低 | ❌ 推理吃 75% |
| `step-3.5-flash` | stepfun | 16384 | low | 1745 | 551 | 0% | 低 | ❌ |

## 模型分类

### 写作模型（推荐）
- **`deepseek-v4-pro`**：质量最高，2215 字，感官密度最强，所有 beat 落地
- **`deepseek-v4-flash`**：性价比最高，893 字，质量好，推理开销极低
- **`step-router-v1`**：零推理开销，质量中等，实际路由到 v4-pro

### 推理模型（不推荐写作）
- `step-3.7-flash` / `step-3.5-flash`：推理吃掉 63-79% 的 token，正文输出效率低。即使关闭 reasoning (`reasoning_effort=disabled`)，仍产生大量内部推理。

### 不可用模型
- `qwen3.6-plus`：关闭 thinking 后输出全部是文学分析
- `qwen3.7-plus`：有 thinking 链，关闭后未独立测试写作

## 推荐配置

### 生产环境（高质量）
```yaml
writer:
  primary: deepseek-v4-pro
  light:
    - deepseek-v4-pro
  max_tokens: 16384
```

### 开发/测试环境（低成本）
```yaml
writer:
  primary: step-router-v1
  light:
    - step-router-v1
  max_tokens: 32768
```

### 默认 ModelRequest
```python
max_tokens: int = 16384  # 从 2048 改为 16384
```

## reasoning_effort 参数

StepFun 推理模型支持 `reasoning_effort` 参数：
- `disabled`：仍然产生推理链（step-3.7-flash 仍产生 2474 字推理）
- `low`：减少推理但不消除（step-3.7-flash 仍产生 953 字）
- 无法完全关闭推理模型的内部推理
- `step-router-v1` 不支持此参数，它是路由模型，无推理链

## 结论

1. **不要用推理模型写小说** — step-3.5/3.7-flash 的推理链无法关闭，浪费 60-80% token
2. **`step-router-v1` 是可行的低成本方案** — 零推理，质量中等，比 direct deepseek 便宜
3. **`deepseek-v4-pro` 是质量最优方案** — 2215 字零分析
4. **`max_tokens` 必须 >= 16384** — 2048 太小导致模型被迫输出分析

## 追加测试 (2026-06-21 第二轮)

### qwen3.7-plus (百炼 Anthropic 协议)
- thinking=disabled, max_tokens=4096
- 646 chars, 0% 分析率, 质量中等偏高
- 感官密度比 step-router-v1 稍弱，但全部 beat 落地
- 可用作 fallback

### step-router-v1 流水线实测
- 12 个 drafts, 1 个分析(8%)
- 3/4 shots 🟢 green, 1 🟡 yellow
- L3 章节 Gate 通过
- 平均得分 68.8, 平均正文字数 ~600-700 chars
- 零推理开销，成本最低

## 最终推荐

| 场景 | 模型 | max_tokens | 预期分析率 |
|------|------|:---:|:---:|
| 生产(高质量) | deepseek-v4-pro | 16384 | 0% |
| 生产(低成本) | step-router-v1 | 32768 | ~8% |
| 开发/测试 | step-router-v1 | 16384 | ~8% |
| Fallback | qwen3.7-plus (thinking=disabled) | 4096 | 0% |

---

## 百炼模型写作质量测试 (2026-06-18)

**测试端点**: `coding.dashscope.aliyuncs.com/v1` (OpenAI 兼容协议)  
**API Key**: `sk-sp-*` (百炼应用/空间 key)  
**Prompt**: 郑坤石板滩场景，强制首句 + beat 列表  
**max_tokens**: 16384, temperature: 0.8

### 可用模型 (百炼应用 key)

| 模型 | 耗时 | 字数 | 分析率 | 质量评估 | 推荐 |
|------|:---:|:---:|:---:|------|:---:|
| `qwen3.7-plus` | 20.1s | 502 | 0% | 感官密度高，节奏好，细节丰富 | ⭐⭐⭐ 最佳 |
| `qwen3.5-plus` | 31.8s | 433 | 0% | 意象最华丽，但略堆砌 | ⭐⭐ 文艺风 |
| `qwen3.6-plus` | 18.2s | 340 | 0% | 节奏紧凑，质量较高 | ⭐⭐ 性价比 |
| `qwen3-coder-plus` | 5.6s | 322 | 0% | 速度最快，但描写平实 | ⭐ 快速出稿 |

### 质量对比

**qwen3.7-plus** (最佳):
- 感官密度：浑浊微波、枯黄落叶、脚步声、皮鞋闷响
- 节奏控制："十步，五步，三步" 短句制造张力
- 氛围营造：风声停滞、落叶弧线、琴弦比喻
- 输出：502字，完整场景

**qwen3.5-plus** (最华丽):
- 意象丰富：磷光、晚霞余烬、古井般的眼、浓墨洇开
- 细节极致：睫毛水珠、樟��与雨水气味
- 风格偏文艺，略有堆砌感

**qwen3.6-plus** (性价比):
- 感官描写到位：水声潺潺、青苔斑驳
- 节奏紧凑，18s 完成
- 篇幅较短但完整

**qwen3-coder-plus** (最快):
- 5.6s 出稿，速度优势明显
- 描写偏平实，有陈词滥调（"时间凝固"、"微妙张力"）
- 适合快速原型

### 百炼模型推荐

| 场景 | 模型 | 备注 |
|------|------|------|
| 高质量写作 | `qwen3.7-plus` | 502字，感官密度最高 |
| 文艺风格 | `qwen3.5-plus` | 意象丰富，略华丽 |
| 快速出稿 | `qwen3-coder-plus` | 5.6s，适合原型验证 |
| 平衡选择 | `qwen3.6-plus` | 18s，质量与速度兼顾 |

### 与其他模型对比

| 模型 | 字数 | 分析率 | 质量 | 成本 | 备注 |
|------|:---:|:---:|:---:|:---:|------|
| deepseek-v4-pro | 2215 | 0% | ⭐⭐⭐⭐ | 高 | 最佳质量，成本高 |
| qwen3.7-plus | 502 | 0% | ⭐⭐⭐ | 中 | 百炼最佳 |
| step-router-v1 | 758 | 0% | ⭐⭐⭐ | 低 | 零推理开销 |
| qwen3.6-plus | 340 | 0% | ⭐⭐ | 中 | 百炼性价比 |
| deepseek-v4-flash | 779 | 0% | ⭐⭐ | 低 | DeepSeek 性价比 |
| qwen3-coder-plus | 322 | 0% | ⭐ | 中 | 最快 |
