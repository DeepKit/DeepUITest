# Workflow Definition Format

Complete reference for the UniFlow workflow JSON format.

## Basic Structure

```json
{
  "id": "workflow-id",
  "name": "Workflow Name",
  "version": "1.0.0",
  "description": "Optional description",
  "steps": [...],
  "triggers": [...],
  "hooks": {...}
}
```

## Top-Level Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `id` | string | Yes | Unique workflow identifier |
| `name` | string | Yes | Human-readable name |
| `version` | string | Yes | Semantic version (e.g., "1.0.0") |
| `description` | string | No | Workflow description |
| `steps` | array | Yes | Array of workflow steps |
| `triggers` | array | No | Trigger configurations |
| `hooks` | object | No | Lifecycle hooks |

---

## Step Types

### Action Step

Executes a specific action.

```json
{
  "id": "step-id",
  "type": "action",
  "name": "Step Name",
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

### Condition Step

Conditional branching.

```json
{
  "id": "check-condition",
  "type": "condition",
  "name": "Check Value",
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

### Loop Step

Iteration over collections or conditions.

```json
{
  "id": "process-items",
  "type": "loop",
  "name": "Process Each Item",
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

Loop modes:
- `forEach` - Iterate over collection
- `while` - Loop while condition is true
- `repeat` - Fixed number of iterations

### Parallel Step

Execute branches in parallel.

```json
{
  "id": "parallel-tasks",
  "type": "parallel",
  "name": "Run in Parallel",
  "parallel": {
    "branches": ["task-a", "task-b", "task-c"],
    "wait_all": true,
    "fail_fast": false,
    "timeout": 60000
  },
  "next_step": "merge-results"
}
```

### Wait Step

Wait for event or duration.

```json
{
  "id": "wait-approval",
  "type": "wait",
  "name": "Wait for Approval",
  "wait": {
    "strategy": "event",
    "event": "approval_received",
    "timeout": 86400000
  },
  "next_step": "process-approval"
}
```

Wait strategies:
- `duration` - Wait for fixed time
- `event` - Wait for external event
- `approval` - Wait for human approval

### Subworkflow Step

Call another workflow.

```json
{
  "id": "call-sub",
  "type": "subworkflow",
  "name": "Call Sub-workflow",
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

### End Step

Workflow termination.

```json
{
  "id": "end",
  "type": "end",
  "name": "Workflow Complete",
  "output": {
    "result": "{{ vars.final_result }}",
    "status": "success"
  }
}
```

---

## Action Types

### LLM Action

Call a language model.

```json
{
  "type": "llm",
  "provider": "openai",
  "model": "gpt-4",
  "prompt": "{{ vars.user_input }}",
  "system_prompt": "You are a helpful assistant.",
  "temperature": 0.7,
  "max_tokens": 1000,
  "json_output": false,
  "json_schema": null
}
```

| Property | Type | Description |
|----------|------|-------------|
| `provider` | string | openai, anthropic, azure, ollama |
| `model` | string | Model identifier |
| `prompt` | string | User prompt (supports templates) |
| `system_prompt` | string | System/instruction prompt |
| `temperature` | number | 0.0 to 2.0 |
| `max_tokens` | integer | Maximum response tokens |
| `json_output` | boolean | Request JSON output |
| `json_schema` | object | JSON schema for validation |

### Skill Action

Call an external skill service.

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

### HTTP Action

Make an HTTP request.

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

### Script Action

Execute inline code.

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

### Assign Action

Set variable values.

```json
{
  "type": "assign",
  "assignments": [
    {
      "target": "greeting",
      "value": "Hello, {{ vars.name }}!"
    },
    {
      "target": "count",
      "value": 0
    }
  ]
}
```

### Log Action

Output log messages.

```json
{
  "type": "log",
  "level": "info",
  "message": "Processing item {{ vars.item_id }}"
}
```

Log levels: `debug`, `info`, `warning`, `error`

### Guard Action

Input validation.

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

## Output Mapping

Map step output to variables.

```json
{
  "output": {
    "target": "result",
    "json_path": "$.data.value",
    "transform": "trim"
  }
}
```

| Property | Description |
|----------|-------------|
| `target` | Variable name to store result |
| `json_path` | JSONPath expression for extraction |
| `transform` | Transformation to apply |

---

## Error Handling

### Error Handler

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

Strategies:
- `retry` - Retry with policy
- `fallback` - Jump to fallback step
- `ignore` - Continue to next step
- `abort` - Stop workflow

### Retry Policy

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

## Triggers

### Schedule Trigger

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

### Event Trigger

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

### Webhook Trigger

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

## Hooks

Lifecycle callbacks.

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

## Expression Syntax

UniFlow uses a Jinja2-like template syntax.

### Variable Access

```
{{ vars.name }}                    - Simple variable
{{ vars.user.email }}              - Nested property
{{ vars.items[0] }}                - Array index
{{ vars.data['key'] }}             - Dictionary access
```

### Filters

```
{{ vars.name | default:'Unknown' }}  - Default value
{{ vars.text | upper }}              - Uppercase
{{ vars.text | lower }}              - Lowercase
{{ vars.text | trim }}               - Trim whitespace
{{ vars.obj | json }}                - JSON string
{{ vars.text | truncate:50 }}        - Truncate
{{ vars.list | join:', ' }}          - Join array
{{ vars.text | split:', ' }}         - Split string
```

### Conditionals in Templates

```
{{ 'Yes' if vars.active else 'No' }}
```

### Built-in Variables

| Variable | Description |
|----------|-------------|
| `vars.*` | User-defined variables |
| `step.id` | Current step ID |
| `step.name` | Current step name |
| `workflow.id` | Workflow ID |
| `workflow.name` | Workflow name |
| `execution.id` | Execution instance ID |
| `execution.start_time` | Start timestamp |

---

## Complete Example

```json
{
  "id": "customer-support",
  "name": "Customer Support Workflow",
  "version": "1.0.0",
  "description": "Automated customer support with AI",
  "steps": [
    {
      "id": "validate-input",
      "type": "action",
      "name": "Validate Input",
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
      "name": "Classify Intent",
      "action": {
        "type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "prompt": "Classify this customer message: {{ vars.message }}",
        "system_prompt": "Classify intent as: billing, technical, general, complaint",
        "temperature": 0.3
      },
      "output": { "target": "intent" },
      "next_step": "route-by-intent"
    },
    {
      "id": "route-by-intent",
      "type": "condition",
      "name": "Route by Intent",
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
      "name": "Billing Response",
      "action": {
        "type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "prompt": "{{ vars.message }}",
        "system_prompt": "You are a billing support specialist..."
      },
      "output": { "target": "response" },
      "next_step": "end"
    },
    {
      "id": "technical-response",
      "type": "action",
      "name": "Technical Response",
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
      "name": "Generate Technical Response",
      "action": {
        "type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "prompt": "Question: {{ vars.message }}\n\nKnowledge: {{ vars.knowledge }}",
        "system_prompt": "You are a technical support specialist..."
      },
      "output": { "target": "response" },
      "next_step": "end"
    },
    {
      "id": "general-response",
      "type": "action",
      "name": "General Response",
      "action": {
        "type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "prompt": "{{ vars.message }}",
        "system_prompt": "You are a friendly customer support agent..."
      },
      "output": { "target": "response" },
      "next_step": "end"
    },
    {
      "id": "escalate-human",
      "type": "action",
      "name": "Escalate to Human",
      "action": {
        "type": "assign",
        "assignments": [
          { "target": "response", "value": "Your request has been escalated to a human agent." },
          { "target": "escalated", "value": true }
        ]
      },
      "next_step": "end"
    },
    {
      "id": "invalid-input",
      "type": "action",
      "name": "Invalid Input Response",
      "action": {
        "type": "assign",
        "assignments": [
          { "target": "response", "value": "Please provide a valid message." }
        ]
      },
      "next_step": "end"
    },
    {
      "id": "end",
      "type": "end",
      "name": "Complete",
      "output": {
        "response": "{{ vars.response }}",
        "intent": "{{ vars.intent }}",
        "escalated": "{{ vars.escalated | default:false }}"
      }
    }
  ]
}
```
