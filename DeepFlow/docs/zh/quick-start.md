# 快速入门指�?

5 分钟内在你的 Delphi 应用程序中运�?UniFlow�?

## 前置条件

- Delphi 10.4+ �?RAD Studio 11+
- DeepBase 框架（用�?LLM 集成�?
- Python 3.10+（用�?Python Skills，可选）
- Node.js 18+（用�?Node.js Skills，可选）

## 安装

### 1. 添加源文�?

�?UniFlow 源文件复制到你的项目中：

```
Source/
├── Workflow/
�?  ├── UniFlow.Workflow.Definition.pas
�?  ├── UniFlow.Workflow.Context.pas
�?  ├── UniFlow.Workflow.Executor.pas
�?  └── UniFlow.Workflow.State.pas
├── AI/
�?  └── UniFlow.AI.Adapter.pas
├── Session/
�?  ├── UniFlow.Session.Types.pas
�?  └── UniFlow.Session.Manager.pas
├── Skill/
�?  ├── UniFlow.Skill.Types.pas
�?  ├── UniFlow.Skill.Client.pas
�?  └── UniFlow.Skill.Executor.pas
└── Diagnostics/
    └── UniFlow.Diagnostics.pas
```

### 2. 添加�?Uses 子句

```pascal
uses
  UniFlow.Workflow.Definition,
  UniFlow.Workflow.Executor,
  UniFlow.Workflow.Context;
```

## 你的第一个工作流

### �?1 步：创建工作流定�?

创建文件 `my_workflow.json`�?

```json
{
  "id": "hello-workflow",
  "name": "Hello World 工作�?,
  "version": "1.0.0",
  "steps": [
    {
      "id": "start",
      "type": "action",
      "name": "开�?,
      "action": {
        "type": "log",
        "message": "工作流已启动"
      },
      "next_step": "greet"
    },
    {
      "id": "greet",
      "type": "action",
      "name": "问候用�?,
      "action": {
        "type": "assign",
        "assignments": [
          {
            "target": "greeting",
            "value": "你好, {{ vars.user_name }}!"
          }
        ]
      },
      "next_step": "end"
    },
    {
      "id": "end",
      "type": "end",
      "name": "结束"
    }
  ]
}
```

### �?2 步：执行工作�?

```pascal
procedure TForm1.RunWorkflow;
var
  Definition: TWorkflowDefinition;
  Executor: TWorkflowExecutor;
  Context: TWorkflowContext;
begin
  // 从文件加载定�?
  Definition := TWorkflowDefinition.FromFile('my_workflow.json');
  try
    // 创建执行�?
    Executor := TWorkflowExecutor.Create(Definition);
    try
      // 创建带有输入变量的上下文
      Context := TWorkflowContext.Create;
      try
        Context.SetVariable('user_name', 'Alice');
        
        // 执行
        Executor.Execute(Context);
        
        // 获取结果
        ShowMessage(Context.GetVariable('greeting').AsString);
        // 输出: "你好, Alice!"
        
      finally
        Context.Free;
      end;
    finally
      Executor.Free;
    end;
  finally
    Definition.Free;
  end;
end;
```

## 添加 LLM 集成

### �?1 步：更新工作�?

```json
{
  "id": "ai-workflow",
  "name": "AI 助手工作�?,
  "version": "1.0.0",
  "steps": [
    {
      "id": "validate",
      "type": "action",
      "name": "验证输入",
      "action": {
        "type": "guard",
        "rules": [
          { "field": "user_input", "required": true, "min_length": 1 }
        ]
      },
      "next_step": "call_llm"
    },
    {
      "id": "call_llm",
      "type": "action",
      "name": "调用 LLM",
      "action": {
        "type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "prompt": "{{ vars.user_input }}",
        "system_prompt": "你是一个有帮助的助手�?,
        "temperature": 0.7
      },
      "output": {
        "target": "ai_response"
      },
      "next_step": "end"
    },
    {
      "id": "end",
      "type": "end"
    }
  ]
}
```

### �?2 步：注册 LLM 执行�?

```pascal
uses
  UniFlow.AI.Adapter;

procedure TForm1.InitializeWorkflow;
begin
  // 注册 LLM 动作执行�?
  RegisterLLMExecutor(Executor, LLMClient);
end;
```

## 添加条件逻辑

```json
{
  "id": "check_sentiment",
  "type": "condition",
  "name": "检查情�?,
  "condition": {
    "expression": "{{ vars.sentiment }} == 'positive'"
  },
  "branches": [
    {
      "condition": "{{ vars.sentiment }} == 'positive'",
      "target": "positive_response"
    },
    {
      "condition": "{{ vars.sentiment }} == 'negative'",
      "target": "negative_response"
    }
  ],
  "default_branch": "neutral_response"
}
```

## 使用外部 Skills

### 启动 Python Skill 服务

```bash
cd Skills
pip install -r requirements.txt
uvicorn src.main:app --port 8000
```

### 从工作流调用

```json
{
  "id": "execute_code",
  "type": "action",
  "name": "执行 Python 代码",
  "action": {
    "type": "skill",
    "skill": "code_executor",
    "input": {
      "language": "python",
      "code": "{{ vars.code }}"
    }
  },
  "output": {
    "target": "execution_result"
  }
}
```

### �?Delphi 调用

```pascal
uses
  UniFlow.Skill.Client;

var
  Client: TSkillClient;
  Result: TSkillResult;
begin
  Client := TSkillClient.Create('http://localhost:8000');
  try
    Result := Client.Execute('code_executor', TJSONObject.Create
      .AddPair('language', 'python')
      .AddPair('code', 'result = 2 + 2')
    );
    
    if Result.Success then
      ShowMessage('结果: ' + Result.Output.GetValue<string>('result'));
  finally
    Client.Free;
  end;
end;
```

## 会话管理

用于多轮对话�?

```pascal
uses
  UniFlow.Session.Manager,
  UniFlow.Session.Types;

var
  Manager: TSessionManager;
  Session: TWorkflowSession;
begin
  Manager := TSessionManager.Create;
  try
    // 创建新会�?
    Session := Manager.CreateSession('user-123', 'chat-workflow');
    
    // 第一�?
    Session.AddMessage(TSessionMessage.CreateUser('什么是机器学习�?));
    Executor.ExecuteWithSession(Session);
    
    // 第二轮（保持上下文）
    Session.AddMessage(TSessionMessage.CreateUser('给我一个例子�?));
    Executor.ExecuteWithSession(Session);
    
    // 获取对话历史
    for var Msg in Session.Messages do
      Memo1.Lines.Add(Msg.Role + ': ' + Msg.Content);
      
  finally
    Manager.Free;
  end;
end;
```

## 错误处理

```pascal
uses
  UniFlow.Workflow.Executor;

try
  Executor.Execute(Context);
except
  on E: EWorkflowValidationError do
    ShowMessage('验证失败: ' + E.Message);
  on E: EWorkflowExecutionError do
    ShowMessage('执行失败于步�? ' + E.StepId);
  on E: ESkillExecutionError do
    ShowMessage('Skill 错误: ' + E.Message);
end;
```

## 日志和诊�?

```pascal
uses
  UniFlow.Diagnostics;

begin
  // 启用追踪
  Diagnostics.TraceEnabled := True;
  Diagnostics.TraceLevel := tlVerbose;
  
  // 设置关联 ID 用于请求追踪
  Diagnostics.CorrelationId := 'req-' + TGUID.NewGuid.ToString;
  
  // 执行并追�?
  Executor.Execute(Context);
  
  // 导出追踪用于调试
  Memo1.Text := Diagnostics.ExportTrace;
end;
```

## 下一�?

- [API 参考](api-reference.md) - 完整 API 文档
- [工作流定义](workflow-definition.md) - 完整 JSON Schema
- [Skill 开发](skills-development.md) - 创建自定�?Skills
- [部署指南](deployment.md) - 生产环境部署
