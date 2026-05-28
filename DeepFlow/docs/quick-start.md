# UniFlow Quick Start Guide

Get started with UniFlow in 5 minutes!

---

## Prerequisites

- Delphi 10.4+ or RAD Studio
- DeepBase Core library (already included)
- OpenAI API key (or other LLM provider)

---

## Step 1: Basic Setup

Add UniFlow units to your project:

```pascal
uses
  UniFlow.Workflow.Definition,
  UniFlow.Workflow.Context,
  UniFlow.Workflow.Executor,
  UniFlow.Session.Manager,
  UniFlow.Roles.Commander,
  UniFlow.AI.Adapter;
```

---

## Step 2: Create a Simple Workflow (JSON)

Create a file `my_workflow.json`:

```json
{
  "id": "hello_world",
  "name": "Hello World Workflow",
  "version": "1.0",
  "steps": [
    {
      "id": "greet",
      "name": "Generate Greeting",
      "type": "action",
      "config": {
        "action_type": "llm",
        "provider": "openai",
        "model": "gpt-4",
        "system_prompt": "You are a friendly assistant.",
        "user_message": "${user_message}",
        "max_tokens": 100
      },
      "output": "response"
    }
  ]
}
```

---

## Step 3: Load and Execute

```pascal
program HelloUniFlow;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  UniFlow.Workflow.Definition,
  UniFlow.Workflow.Context,
  UniFlow.Workflow.Executor,
  UniFlow.AI.Adapter;

var
  Workflow: TWorkflowDefinition;
  Context: TWorkflowContext;
  Executor: TWorkflowExecutor;
  Result: TStepResult;
begin
  // Load workflow
  Workflow := TWorkflowDefinition.Create;
  Workflow.LoadFromFile('my_workflow.json');
  
  // Create context with user input
  Context := TWorkflowContext.Create;
  Context.SetVariable('user_message', 'Hello! How are you?');
  
  // Execute
  Executor := TWorkflowExecutor.Create(Workflow, Context);
  try
    // Register LLM executor
    RegisterLLMExecutor;
    
    Result := Executor.Start;
    if Result.Success then
      WriteLn('Response: ' + Result.Output.ToString)
    else
      WriteLn('Error: ' + Result.ErrorMessage);
  finally
    Executor.Free;
    Context.Free;
    Workflow.Free;
  end;
end.
```

---

## Step 4: Add Intent Recognition (Commander)

```pascal
var
  SessionManager: TSessionManager;
  Registry: TSimpleWorkflowRegistry;
  Commander: TCommander;
begin
  // Setup
  SessionManager := TSessionManager.Create;
  Registry := TSimpleWorkflowRegistry.Create;
  Registry.RegisterWorkflowFromFile('my_workflow.json');
  
  Commander := TCommander.Create(SessionManager, Registry);
  
  // Register intents
  Commander.RegisterIntent('greeting', 
    ['hello|hi|hey'], 
    ['hello', 'hi']);
  Commander.RegisterRoute('greeting', 'hello_world');
  
  // Process
  var Response := Commander.ProcessMessage('', 'Hello!');
  WriteLn(Response.Message);
  
  // Cleanup
  Commander.Free;
  Registry.Free;
  SessionManager.Free;
end;
```

---

## Step 5: Add Sessions

```pascal
var
  SessionManager: TSessionManager;
  Session: TSession;
begin
  SessionManager := TSessionManager.Create;
  
  // Create session
  Session := SessionManager.CreateSession('user_123');
  
  // Add messages
  Session.AddUserMessage('Hello');
  Session.AddAssistantMessage('Hi! How can I help?');
  
  // Store context
  Session.Context.SetValue('preference', 'dark_mode');
  
  // Later: retrieve session
  Session := SessionManager.GetSession(Session.SessionId);
  
  SessionManager.Free;
end;
```

---

## Common Patterns

### Pattern 1: Conditional Workflow

```json
{
  "steps": [
    {
      "id": "check_type",
      "type": "condition",
      "config": {
        "expression": "${request_type}"
      },
      "branches": [
        { "condition": "equals('question')", "goto": "answer_question" },
        { "condition": "equals('task')", "goto": "execute_task" },
        { "condition": "else", "goto": "fallback" }
      ]
    }
  ]
}
```

### Pattern 2: Input Validation

```pascal
var
  Sanitizer: TSanitizer;
  Guard: TPromptGuard;
  CheckResult: TPromptCheckResult;
begin
  Sanitizer := TSanitizer.Create;
  Guard := TPromptGuard.Create;
  
  // Sanitize input
  var CleanInput := Sanitizer.Sanitize(UserInput);
  
  // Check for injection
  CheckResult := Guard.Check(CleanInput);
  if not CheckResult.IsSafe then
  begin
    WriteLn('Blocked: Potential injection detected');
    Exit;
  end;
  
  // Process clean input...
end;
```

### Pattern 3: Error Handling

```pascal
Executor.OnWorkflowError := procedure(Sender: TWorkflowExecutor; 
  const ErrorCode, ErrorMessage: string)
begin
  case ErrorCode of
    'TIMEOUT': // Retry or fail gracefully
    'LLM_ERROR': // Log and notify
    else // Generic handling
  end;
end;
```

---

## Configuration

### LLM Provider Setup

Configure in DeepBase config:

```json
{
  "llm": {
    "default_provider": "openai",
    "providers": {
      "openai": {
        "api_key": "sk-...",
        "base_url": "https://api.openai.com/v1"
      }
    }
  }
}
```

### Session Configuration

```pascal
var Config: TSessionConfig;
Config.MaxMessageHiDeepDeepDeepDeepDeepStory := 100;
Config.SessionTimeoutMinutes := 30;
Config.MaxSessionsPerUser := 5;
Config.EnablePersistence := True;

SessionManager.Config := Config;
```

---

## Examples

Check out the `Examples/` folder for complete examples:

- **QAChatbot/** - Simple Q&A bot
- **CodeAssistant/** - Code review and generation
- **MultiTurnChat/** - Context-aware conversations

---

## Next Steps

1. Read the [API Reference](api-reference.md)
2. Explore [Example Workflows](../Examples/)
3. Run [Performance Tests](../Tests/UniFlow.Test.Performance.pas)
4. Review [DeepBase Reuse Strategy](DeepBase-reuse-strategy.md)

---

## Troubleshooting

### "Workflow not found"
- Check workflow ID matches route
- Verify JSON file path is correct

### "LLM error: 401"
- Check API key configuration
- Verify provider settings

### "Session expired"
- Increase `SessionTimeoutMinutes`
- Call `GetOrCreateSession` instead of `GetSession`

### Performance issues
- Run `QuickPerformanceCheck`
- Check `UniFlow.Test.Performance` for benchmarks
