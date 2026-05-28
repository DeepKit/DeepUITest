# Quick Start Guide

Get UniFlow running in your Delphi application in 5 minutes.

## Prerequisites

- Delphi 10.4+ or RAD Studio 11+
- DeepBase framework (for LLM integration)
- Python 3.10+ (for Python skills, optional)
- Node.js 18+ (for Node.js skills, optional)

## Installation

### 1. Add Source Files

Copy the UniFlow source files to your project:

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

### 2. Add to Uses Clause

```pascal
uses
  UniFlow.Workflow.Definition,
  UniFlow.Workflow.Executor,
  UniFlow.Workflow.Context;
```

## Your First Workflow

### Step 1: Create a Workflow Definition

Create a file `my_workflow.json`:

```json
{
  "id": "hello-workflow",
  "name": "Hello World Workflow",
  "version": "1.0.0",
  "steps": [
    {
      "id": "start",
      "type": "action",
      "name": "Start",
      "action": {
        "type": "log",
        "message": "Workflow started"
      },
      "next_step": "greet"
    },
    {
      "id": "greet",
      "type": "action",
      "name": "Greet User",
      "action": {
        "type": "assign",
        "assignments": [
          {
            "target": "greeting",
            "value": "Hello, {{ vars.user_name }}!"
          }
        ]
      },
      "next_step": "end"
    },
    {
      "id": "end",
      "type": "end",
      "name": "End"
    }
  ]
}
```

### Step 2: Execute the Workflow

```pascal
procedure TForm1.RunWorkflow;
var
  Definition: TWorkflowDefinition;
  Executor: TWorkflowExecutor;
  Context: TWorkflowContext;
begin
  // Load definition from file
  Definition := TWorkflowDefinition.FromFile('my_workflow.json');
  try
    // Create executor
    Executor := TWorkflowExecutor.Create(Definition);
    try
      // Create context with input variables
      Context := TWorkflowContext.Create;
      try
        Context.SetVariable('user_name', 'Alice');
        
        // Execute
        Executor.Execute(Context);
        
        // Get result
        ShowMessage(Context.GetVariable('greeting').AsString);
        // Output: "Hello, Alice!"
        
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

## Adding LLM Integration

### Step 1: Update Workflow

```json
{
  "id": "ai-workflow",
  "name": "AI Assistant Workflow",
  "version": "1.0.0",
  "steps": [
    {
      "id": "validate",
      "type": "action",
      "name": "Validate Input",
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
      "name": "Call LLM",
      "action": {
        "type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "prompt": "{{ vars.user_input }}",
        "system_prompt": "You are a helpful assistant.",
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

### Step 2: Register LLM Executor

```pascal
uses
  UniFlow.AI.Adapter;

procedure TForm1.InitializeWorkflow;
begin
  // Register LLM action executor
  RegisterLLMExecutor(Executor, LLMClient);
end;
```

## Adding Conditional Logic

```json
{
  "id": "check_sentiment",
  "type": "condition",
  "name": "Check Sentiment",
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

## Using External Skills

### Start Python Skill Service

```bash
cd Skills
pip install -r requirements.txt
uvicorn src.main:app --port 8000
```

### Call from Workflow

```json
{
  "id": "execute_code",
  "type": "action",
  "name": "Execute Python Code",
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

### Call from Delphi

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
      ShowMessage('Result: ' + Result.Output.GetValue<string>('result'));
  finally
    Client.Free;
  end;
end;
```

## Session Management

For multi-turn conversations:

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
    // Create new session
    Session := Manager.CreateSession('user-123', 'chat-workflow');
    
    // First turn
    Session.AddMessage(TSessionMessage.CreateUser('What is machine learning?'));
    Executor.ExecuteWithSession(Session);
    
    // Second turn (maintains context)
    Session.AddMessage(TSessionMessage.CreateUser('Give me an example.'));
    Executor.ExecuteWithSession(Session);
    
    // Get conversation hiDeepDeepDeepDeepDeepStory
    for var Msg in Session.Messages do
      Memo1.Lines.Add(Msg.Role + ': ' + Msg.Content);
      
  finally
    Manager.Free;
  end;
end;
```

## Error Handling

```pascal
uses
  UniFlow.Workflow.Executor;

try
  Executor.Execute(Context);
except
  on E: EWorkflowValidationError do
    ShowMessage('Validation failed: ' + E.Message);
  on E: EWorkflowExecutionError do
    ShowMessage('Execution failed at step: ' + E.StepId);
  on E: ESkillExecutionError do
    ShowMessage('Skill error: ' + E.Message);
end;
```

## Logging and Diagnostics

```pascal
uses
  UniFlow.Diagnostics;

begin
  // Enable tracing
  Diagnostics.TraceEnabled := True;
  Diagnostics.TraceLevel := tlVerbose;
  
  // Set correlation ID for request tracking
  Diagnostics.CorrelationId := 'req-' + TGUID.NewGuid.ToString;
  
  // Execute with tracing
  Executor.Execute(Context);
  
  // Export trace for debugging
  Memo1.Text := Diagnostics.ExportTrace;
end;
```

## Next Steps

- [API Reference](api-reference.md) - Complete API documentation
- [Workflow Definition](workflow-definition.md) - Full JSON schema
- [Skills Development](skills-development.md) - Create custom skills
- [Deployment](deployment.md) - Production deployment
