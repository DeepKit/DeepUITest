# 可鉴决策操作系统

<div align="center">
<strong>每个决策，可见，可鉴。</strong>
<br/>
<br/>
<img src="https://img.shields.io/badge/version-1.0.0-blue.svg" alt="Version 1.0.0"/>
<img src="https://img.shields.io/badge/python-3.8%2B-green.svg" alt="Python 3.8+"/>
<img src="https://img.shields.io/badge/license-MIT-yellow.svg" alt="MIT License"/>
</div>

---

## 🎯 产品定位

**可鉴（Audita）** 是一款决策操作系统，通过「OCGS 定框架 + DeepFlow 做执行 + DeepInsight 给良知」的三体架构，将黑盒决策转变为透明、可审计、可复盘的思维过程。

### 核心价值主张

| 双关语义 | 产品承诺 | 用户价值 |
|---------|---------|---------|
| **可见** | 六角色思考实时展开，事件溯源完整记录 | 不是黑盒，每一步都可追溯 |
| **可鉴** | OCGS 治理框架约束，审计级过程留痕 | 经得起鉴察，正当性承诺 |

### 核心能力

- ✅ **六角色并行推演**：教练 / 批判者 / 反思者 / 观察者 / 聚合者 / 胶片生成者
- ✅ **防假绿机制**：宁可降级也不显示假绿状态，确保输出质量
- ✅ **结构化胶片产出**：将决策显影为可视化思维胶片
- ✅ **病毒裂变设计**：分享卡片带品牌水印，邀请链接自动传播

---

## 🚀 快速开始

### 1. 启动 Skills 服务

```bash
cd Skills
export KIRO_API_KEY="your-api-key"
export OPENAI_API_KEY="your-api-key"

python -m uvicorn src.main:app --host 127.0.0.1 --port 8001
```

**验证服务健康：**
```bash
curl http://127.0.0.1:8001/health
```

预期响应：
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "skills_loaded": 7
}
```

### 2. 启动 Web 前端

```bash
cd 可鉴
python -m http.server 8090
```

在浏览器中访问 `http://127.0.0.1:8090`，输入您的决策问题并点击"开始治理"。

---

## 🧪 测试套件

### E2E 端到端测试

运行单次完整链路测试（四视角 → 聚合 → 胶片）：

```bash
python kejian/tests/kejian_e2e_test.py \
  --problem "直营门店要不要从 50 家扩到 80 家？预算 8000 万，周期两年。" \
  --template strategic
```

**参数说明：**
- `--problem`: 必填，决策问题文本
- `--template`: 可选，`strategic`/`investment`/`personnel`/`procurement`
- `--output`: 可选，自定义报告文件名

**示例输出报告：**
```json
{
  "timestamp": "2026-08-09T02:43:11.740242Z",
  "problem": "直营门店要不要从 50 家扩到 80 家？...",
  "stages": {
    "perspectives": 4,
    "aggregated": true,
    "film_generated": true
  },
  "statistics": {
    "total_calls": 6,
    "successful": 4,
    "degraded": 2,
    "errors": 0
  },
  "total_elapsed_seconds": 87.3
}
```

### 批量压力测试

评估并发性能与系统负载：

```bash
python kejian/tests/stress_test.py \
  --requests 10 \
  --concurrency 5
```

**指标说明：**
- `success_rate`: 成功请求占比
- `avg_time_ms`: 平均耗时（毫秒）
- `p95_time_ms`: 95 分位耗时
- `error_count`: 失败次数

### 场景样本生成器

自动生成 100+ 真实决策场景用于测试：

```bash
python kejian/tests/generate_samples.py \
  --count 100 \
  --output samples.jsonl
```

**输出格式：JSONL（每行一个决策对象）**

示例：
```json
{"id": "DEC-20260809024311-1234", "domain": "strategic", "scenario": "是否要从 X 个门店扩展到 Y 个门店？预算 Z 万元，周期 N 年。", "difficulty": "medium", "stakeholders": ["CEO", "CFO"], ...}
```

---

## 📋 API 参考

### Skills 服务接口

#### 基础 URL

- Health: `GET http://127.0.0.1:8001/health`
- List Skills: `GET http://127.0.0.1:8001/skills`
- Execute Skill: `POST http://127.0.0.1:8001/skills/execute`

#### 调用示例

```bash
curl -X POST http://127.0.0.1:8001/skills/execute \
  -H "Content-Type: application/json" \
  -d '{
    "skill_name": "decision_coach",
    "params": {
      "problem": "直营门店要不要从 50 家扩到 80 家？",
      "context": {"decision_type": "strategic"}
    },
    "context": {},
    "timeout_ms": 300000
  }'
```

#### 返回字段契约

**Skill 通用响应结构：**
```json
{
  "skill_name": "decision_coach",
  "status": "success",
  "result": {
    "role": "coach",
    "key_DeepInsights": [...],
    "guiding_questions": [...],
    "degraded": false,
    "degrade_reason": null
  },
  "execution_time_ms": 23231,
  "timestamp": "2026-08-09T02:43:11.740242Z"
}
```

#### 六角色字段摘要

| 角色 | 技能名称 | 关键字段 |
|-----|---------|---------|
| 决策教练 | `decision_coach` | `key_DeepInsights`, `guiding_questions`, `values_detected`, `emotional_tone` |
| 批判者 | `decision_critic` | `assumptions_challenged`, `blind_spots`, `risks`, `devil_advocate_questions` |
| 反思者 | `decision_mirror` | `emotional_landscape`, `value_conflicts`, `identity_aspects`, `reflection_prompts` |
| 观察者 | `decision_observer` | `decision_patterns`, `external_factors`, `similar_cases`, `objective_observations` |
| 聚合者 | `decision_aggregator` | `views`, `key_DeepInsights`, `self_questions`, `emotional_summary`, `consensus_points`, `divergence_points` |
| 胶片生成者 | `film_generator` | `title`, `subtitle`, `sections`, `self_questions`, `closing_note` |

---

## 🔍 关键特性

### 防假绿机制（DeepInsight-003）

系统采用三重大防护确保输出质量：

1. **System Prompt 强制 JSON**：要求 LLM 只输出纯 JSON，禁用 Markdown 围栏
2. **_parse_response() 围栏提取**：即使返回非标准格式，也能用正则提取 JSON 部分
3. **raw_analysis 检测降级**：解析失败时主动设置 `degraded=true`，避免假绿

**降级可见性承诺：**
- 所有降级明确标记为"⚠ 降级原因"
- 模板兜底仍能提供引导问题和洞察建议
- 宁可降级也不显示错误数据

### 病毒裂变三层机制

1. **输出即广告**：每份胶片带品牌水印 + 邀请链接
2. **协作邀请**：分享卡片支持同事协作治理
3. **模板共享**：`.governance` 文件格式跨行业流动

---

## 📁 目录结构

```
可鉴/
├── index.html                  # 单页应用入口
├── css/
│   └── kejian.css             # 品牌样式（深色主题 + 金色 accent）
├── js/
│   └── kejian.js              # 核心逻辑（六角色并行推演 + 契约修正）
├── tests/
│   ├── kejian_e2e_test.py     # Python E2E 测试套件
│   ├── stress_test.py         # 并发压力测试工具
│   └── generate_samples.py    # 决策场景样本库生成器
├── run_8001.log               # Skills 服务日志
└── kejian_server.log          # HTTP 前端服务日志
```

---

## 🐛 Troubleshooting

### Q1: Skills 服务启动失败

**症状：** `/health` 返回 404 或超时

**排查步骤：**
1. 检查环境变量：`echo $KIRO_API_KEY`
2. 查看日志：`tail -f run_8001.log`
3. 确认依赖：`pip install litellm structlog RestrictedPython packaging`

### Q2: LLM 输出被破坏成问号

**症状：** 中文变成 `?` 或乱码

**原因：** PowerShell `ConvertTo-Json` 编码问题或网络传输损坏

**解决方案：**
1. 使用 Python 客户端而非 curl（已内建 UTF-8 处理）
2. 确认 WiseGateway 不修改内容
3. 降级模式下使用内置模板兜底

### Q3: 前端页面空白

**症状：** 打开 `http://127.0.0.1:8090` 只显示空白

**排查步骤：**
1. 检查浏览器 Console 报错（F12）
2. 确认 HTTP 服务器正常：`netstat -ano | findstr :8090`
3. 验证 Skills 服务连通性：前端 JS 会尝试 POST 到 `http://127.0.0.1:8001`

---

## 📄 License

MIT License — 详见 [LICENSE](LICENSE) 文件。

---

## 🤝 Contributing

欢迎提交 PR 或创建 Issue。决策治理是重要命题，我们一起把它做好。

**优先贡献方向：**
1. 更多行业决策场景模板（医疗 / 教育 / 法律等）
2. 优化 LLM 调用稳定性（减少降级频率）
3. 增强胶片可视化效果（Mermaid 图 / 情绪谱线）
4. 集成外部 MCP 协议（实现更复杂的决策能力）

---

**黑盒决策的时代结束了。从今天起，每一个决定——可见、可鉴、可复盘。**
