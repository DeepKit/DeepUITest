# 工作流定义格�?

UniFlow 工作�?JSON 格式完整参考�?

## 基本结构

```json
{
  "id": "workflow-id",
  "name": "工作流名�?,
  "version": "1.0.0",
  "description": "可选描�?,
  "steps": [...],
  "triggers": [...],
  "hooks": {...}
}
```

## 顶层属�?

| 属�?| 类型 | 必填 | 描述 |
|------|------|------|------|
| `id` | string | �?| 工作流唯一标识�?|
| `name` | string | �?| 人类可读名称 |
| `version` | string | �?| 语义版本（如 "1.0.0"）|
| `description` | string | �?| 工作流描�?|
| `steps` | array | �?| 工作流步骤数�?|
| `triggers` | array | �?| 触发器配�?|
| `hooks` | object | �?| 生命周期钩子 |

---

## 步骤类型

### Action 步骤

执行特定动作�?

```json
{
  "id": "step-id",
  "type": "action",
  "name": "步骤名称",
  "action": {
    "type": "llm|skill|http|script|assign|log|guard",
    ...
  },
  "output": {
    "target": "result_variable"
  },
  "next_step": "next-step-id",
  "error_handler": {...},
  "retry_policy": {...},
  "timeout": 30000
}
```

### Condition 步骤

条件分支�?

```json
{
  "id": "check-condition",
  "type": "condition",
  "name": "检查�?,
  "condition": {
    "expression": "{{ vars.value }} > 10"
  },
  "branches": [
    {
      "condition": "{{ vars.value }} > 100",
      "target": "high-value-step"
    },
    {
      "condition": "{{ vars.value }} > 50",
      "target": "medium-value-step"
    }
  ],
  "default_branch": "low-value-step"
}
```

### Loop 步骤

集合或条件迭代�?

```json
{
  "id": "process-items",
  "type": "loop",
  "name": "处理每个项目",
  "loop": {
    "mode": "forEach",
    "collection": "{{ vars.items }}",
    "item_var": "current_item",
    "index_var": "index",
    "max_iterations": 100
  },
  "body_step": "process-single-item",
  "next_step": "after-loop"
}
```

循环模式�?
- `forEach` - 遍历集合
- `while` - 条件为真时循�?
- `repeat` - 固定次数迭代

### Parallel 步骤

并行执行分支�?

```json
{
  "id": "parallel-tasks",
  "type": "parallel",
  "name": "并行运行",
  "parallel": {
    "branches": ["task-a", "task-b", "task-c"],
    "wait_all": true,
    "fail_fast": false,
    "timeout": 60000
  },
  "next_step": "merge-results"
}
```

### Wait 步骤

等待事件或时间�?

```json
{
  "id": "wait-approval",
  "type": "wait",
  "name": "等待审批",
  "wait": {
    "strategy": "event",
    "event": "approval_received",
    "timeout": 86400000
  },
  "next_step": "process-approval"
}
```

等待策略�?
- `duration` - 等待固定时间
- `event` - 等待外部事件
- `approval` - 等待人工审批

### Subworkflow 步骤

调用另一个工作流�?

```json
{
  "id": "call-sub",
  "type": "subworkflow",
  "name": "调用子工作流",
  "workflow_id": "sub-workflow-id",
  "input": {
    "param1": "{{ vars.value1 }}",
    "param2": "{{ vars.value2 }}"
  },
  "output": {
    "target": "sub_result"
  },
  "next_step": "continue"
}
```

### End 步骤

工作流终止�?

```json
{
  "id": "end",
  "type": "end",
  "name": "工作流完�?,
  "output": {
    "result": "{{ vars.final_result }}",
    "status": "success"
  }
}
```

---

## 动作类型

### LLM 动作

调用语言模型�?

```json
{
  "type": "llm",
  "provider": "openai",
  "model": "gpt-4",
  "prompt": "{{ vars.user_input }}",
  "system_prompt": "你是一个有帮助的助手�?,
  "temperature": 0.7,
  "max_tokens": 1000,
  "json_output": false,
  "json_schema": null
}
```

| 属�?| 类型 | 描述 |
|------|------|------|
| `provider` | string | openai, anthropic, azure, ollama |
| `model` | string | 模型标识�?|
| `prompt` | string | 用户提示词（支持模板）|
| `system_prompt` | string | 系统/指令提示�?|
| `temperature` | number | 0.0 �?2.0 |
| `max_tokens` | integer | 最大响�?Token �?|
| `json_output` | boolean | 请求 JSON 输出 |
| `json_schema` | object | 用于验证�?JSON Schema |

### Skill 动作

调用外部 Skill 服务�?

```json
{
  "type": "skill",
  "skill": "code_executor",
  "input": {
    "language": "python",
    "code": "{{ vars.code }}"
  },
  "timeout": 30000
}
```

### HTTP 动作

发起 HTTP 请求�?

```json
{
  "type": "http",
  "method": "POST",
  "url": "https://api.example.com/data",
  "headers": {
    "Authorization": "Bearer {{ vars.api_key }}",
    "Content-Type": "application/json"
  },
  "body": {
    "query": "{{ vars.query }}"
  },
  "timeout": 10000
}
```

### Script 动作

执行内联代码�?

```json
{
  "type": "script",
  "language": "javascript",
  "code": "return input.value * 2;",
  "input": {
    "value": "{{ vars.number }}"
  }
}
```

### Assign 动作

设置变量值�?

```json
{
  "type": "assign",
  "assignments": [
    {
      "target": "greeting",
      "value": "你好, {{ vars.name }}!"
    },
    {
      "target": "count",
      "value": 0
    }
  ]
}
```

### Log 动作

输出日志消息�?

```json
{
  "type": "log",
  "level": "info",
  "message": "正在处理项目 {{ vars.item_id }}"
}
```

日志级别: `debug`, `info`, `warning`, `error`

### Guard 动作

输入验证�?

```json
{
  "type": "guard",
  "rules": [
    {
      "field": "email",
      "required": true,
      "type": "email"
    },
    {
      "field": "age",
      "type": "number",
      "min": 0,
      "max": 150
    },
    {
      "field": "name",
      "required": true,
      "min_length": 1,
      "max_length": 100
    }
  ],
  "on_fail": "reject"
}
```

---

## 输出映射

将步骤输出映射到变量�?

```json
{
  "output": {
    "target": "result",
    "json_path": "$.data.value",
    "transform": "trim"
  }
}
```

| 属�?| 描述 |
|------|------|
| `target` | 存储结果的变量名 |
| `json_path` | 用于提取�?JSONPath 表达�?|
| `transform` | 要应用的转换 |

---

## 错误处理

### 错误处理�?

```json
{
  "error_handler": {
    "strategy": "retry",
    "fallback_step": "error-recovery",
    "fallback_value": "default",
    "log_error": true,
    "rethrow": false
  }
}
```

策略�?
- `retry` - 按策略重�?
- `fallback` - 跳转到回退步骤
- `ignore` - 继续下一�?
- `abort` - 停止工作�?

### 重试策略

```json
{
  "retry_policy": {
    "max_retries": 3,
    "backoff_ms": 1000,
    "backoff_multiplier": 2.0,
    "max_backoff_ms": 30000,
    "retryable_errors": ["timeout", "rate_limit"]
  }
}
```

---

## 触发�?

### 定时触发�?

```json
{
  "triggers": [
    {
      "type": "schedule",
      "cron": "0 0 * * *",
      "timezone": "UTC"
    }
  ]
}
```

### 事件触发�?

```json
{
  "triggers": [
    {
      "type": "event",
      "event_name": "user.created",
      "filter": {
        "plan": "premium"
      }
    }
  ]
}
```

### Webhook 触发�?

```json
{
  "triggers": [
    {
      "type": "webhook",
      "path": "/api/workflow/start",
      "method": "POST",
      "auth": "api_key"
    }
  ]
}
```

---

## 钩子

生命周期回调�?

```json
{
  "hooks": {
    "on_start": "log-workflow-start",
    "on_complete": "notify-completion",
    "on_error": "send-alert",
    "on_timeout": "cleanup-resources"
  }
}
```

---

## 表达式语�?

UniFlow 使用类似 Jinja2 的模板语法�?

### 变量访问

```
{{ vars.name }}                    - 简单变�?
{{ vars.user.email }}              - 嵌套属�?
{{ vars.items[0] }}                - 数组索引
{{ vars.data['key'] }}             - 字典访问
```

### 过滤�?

```
{{ vars.name | default:'未知' }}     - 默认�?
{{ vars.text | upper }}              - 大写
{{ vars.text | lower }}              - 小写
{{ vars.text | trim }}               - 去除空白
{{ vars.obj | json }}                - JSON 字符�?
{{ vars.text | truncate:50 }}        - 截断
{{ vars.list | join:', ' }}          - 连接数组
{{ vars.text | split:', ' }}         - 分割字符�?
```

### 模板中的条件

```
{{ '�? if vars.active else '�? }}
```

### 内置变量

| 变量 | 描述 |
|------|------|
| `vars.*` | 用户定义变量 |
| `step.id` | 当前步骤 ID |
| `step.name` | 当前步骤名称 |
| `workflow.id` | 工作�?ID |
| `workflow.name` | 工作流名�?|
| `execution.id` | 执行实例 ID |
| `execution.start_time` | 开始时间戳 |

---

## 完整示例

```json
{
  "id": "customer-support",
  "name": "客户支持工作�?,
  "version": "1.0.0",
  "description": "�?AI 的自动化客户支持",
  "steps": [
    {
      "id": "validate-input",
      "type": "action",
      "name": "验证输入",
      "action": {
        "type": "guard",
        "rules": [
          { "field": "message", "required": true, "min_length": 1 }
        ]
      },
      "next_step": "classify-intent",
      "error_handler": {
        "strategy": "fallback",
        "fallback_step": "invalid-input"
      }
    },
    {
      "id": "classify-intent",
      "type": "action",
      "name": "分类意图",
      "action": {
        "type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "prompt": "对这条客户消息进行分�? {{ vars.message }}",
        "system_prompt": "将意图分类为: billing（账单）, technical（技术）, general（一般）, complaint（投诉）",
        "temperature": 0.3
      },
      "output": { "target": "intent" },
      "next_step": "route-by-intent"
    },
    {
      "id": "route-by-intent",
      "type": "condition",
      "name": "按意图路�?,
      "branches": [
        { "condition": "{{ vars.intent }} == 'billing'", "target": "billing-response" },
        { "condition": "{{ vars.intent }} == 'technical'", "target": "technical-response" },
        { "condition": "{{ vars.intent }} == 'complaint'", "target": "escalate-human" }
      ],
      "default_branch": "general-response"
    },
    {
      "id": "billing-response",
      "type": "action",
      "name": "账单回复",
      "action": {
        "type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "prompt": "{{ vars.message }}",
        "system_prompt": "你是账单支持专员..."
      },
      "output": { "target": "response" },
      "next_step": "end"
    },
    {
      "id": "technical-response",
      "type": "action",
      "name": "技术回�?,
      "action": {
        "type": "skill",
        "skill": "knowledge_search",
        "input": { "query": "{{ vars.message }}" }
      },
      "output": { "target": "knowledge" },
      "next_step": "generate-tech-response"
    },
    {
      "id": "generate-tech-response",
      "type": "action",
      "name": "生成技术回�?,
      "action": {
        "type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "prompt": "问题: {{ vars.message }}\n\n知识�? {{ vars.knowledge }}",
        "system_prompt": "你是技术支持专�?.."
      },
      "output": { "target": "response" },
      "next_step": "end"
    },
    {
      "id": "general-response",
      "type": "action",
      "name": "一般回�?,
      "action": {
        "type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "prompt": "{{ vars.message }}",
        "system_prompt": "你是一位友好的客服人员..."
      },
      "output": { "target": "response" },
      "next_step": "end"
    },
    {
      "id": "escalate-human",
      "type": "action",
      "name": "转人�?,
      "action": {
        "type": "assign",
        "assignments": [
          { "target": "response", "value": "您的请求已转交人工客服处理�? },
          { "target": "escalated", "value": true }
        ]
      },
      "next_step": "end"
    },
    {
      "id": "invalid-input",
      "type": "action",
      "name": "无效输入回复",
      "action": {
        "type": "assign",
        "assignments": [
          { "target": "response", "value": "请提供有效的消息�? }
        ]
      },
      "next_step": "end"
    },
    {
      "id": "end",
      "type": "end",
      "name": "完成",
      "output": {
        "response": "{{ vars.response }}",
        "intent": "{{ vars.intent }}",
        "escalated": "{{ vars.escalated | default:false }}"
      }
    }
  ]
}
```
