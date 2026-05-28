# UniFlow API Reference

> Version: 1.0  
> Last Updated: 2025-12-05

---

## Table of Contents

1. [Core Components](#core-components)
2. [Workflow Definition](#workflow-definition)
3. [Session Management](#session-management)
4. [Commander (Request Router)](#commander-request-router)
5. [AI Integration](#ai-integration)
6. [Validation & Security](#validation--security)

---

## Core Components

### TWorkflowContext

Workflow execution context that stores variables and step outputs.

```pascal
var Context := TWorkflowContext.Create;
try
  // Set variables
  Context.SetVariable('user_name', 'John');
  Context.SetVariable('count', '42');
  
  // Get variables
  var Name := Context.GetVariable('user_name');
  
  // Check existence
  if Context.HasVariable('user_name') then
    // ...
  
  // Store step output
  Context.SetStepOutput('step_1', TJSONObject.Create);
  
  // Serialize
  var Json := Context.ToJSON;
finally
  Context.Free;
end;
```

**Key Methods:**

| Method | Description |
|--------|-------------|
| `SetVariable(name, value)` | Set a string variable |
| `GetVariable(name): string` | Get variable value |
| `HasVariable(name): Boolean` | Check if variable exists |
| `SetStepOutput(stepId, output)` | Store step execution output |
| `GetStepOutput(stepId): TJSONValue` | Get step output |
| `ToJSON: TJSONObject` | Serialize context |
| `LoadFromJSON(json)` | Deserialize context |

---

### TWorkflowDefinition

Defines a workflow with metadata and steps.

```pascal
var Workflow := TWorkflowDefinition.Create;
try
  Workflow.Id := 'greeting_workflow';
  Workflow.Name := 'Greeting Workflow';
  Workflow.Version := '1.0';
  
  // Add steps
  var Step := TWorkflowStep.Create;
  Step.Id := 'greet';
  Step.Name := 'Greet User';
  Step.StepType := stAction;
  Workflow.Steps.Add(Step);
  
  // Validate
  if Workflow.Validate then
    WriteLn('Valid workflow');
    
  // Export to JSON
  var Json := Workflow.ToJSON;
finally
  Workflow.Free;
end;
```

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `Id` | string | Unique workflow identifier |
| `Name` | string | Human-readable name |
| `Version` | string | Semantic version |
| `Description` | string | Optional description |
| `Steps` | TObjectList<TWorkflowStep> | Workflow steps |
| `Variables` | TDictionary | Initial variables |
| `Tags` | TStringList | Metadata tags |

---

### TWorkflowStep

Individual step in a workflow.

**Step Types:**

| Type | Description |
|------|-------------|
| `stAction` | Execute an action |
| `stCondition` | Conditional branching |
| `stLoop` | Loop (forEach/while) |
| `stParallel` | Parallel execution |
| `stWait` | Wait for external input |
| `stSubWorkflow` | Execute sub-workflow |

---

### TWorkflowExecutor

Executes workflow definitions.

```pascal
var Executor := TWorkflowExecutor.Create(Workflow, Context);
try
  // Register action executors
  Executor.RegisterActionExecutor(TLLMActionExecutor.Create);
  
  // Execute
  var Result := Executor.Start;
  
  if Result.Success then
    WriteLn('Completed: ' + Result.Output.ToString)
  else
    WriteLn('Error: ' + Result.ErrorMessage);
    
  // Or step-by-step
  while Executor.Status = esRunning do
  begin
    var StepResult := Executor.StepOnce;
    // Process step result...
  end;
finally
  Executor.Free;
end;
```

**Execution Status:**

| Status | Description |
|--------|-------------|
| `esIdle` | Not started |
| `esRunning` | Executing |
| `esPaused` | Paused |
| `esWaiting` | Waiting for input |
| `esCompleted` | Finished successfully |
| `esFailed` | Failed with error |
| `esCancelled` | Cancelled |

---

## Session Management

### TSession

Represents a user session with conversation hiDeepDeepDeepDeepDeepStory.

```pascal
var Session := TSession.Create;
try
  Session.UserId := 'user_123';
  
  // Add messages
  Session.AddUserMessage('Hello');
  Session.AddAssistantMessage('Hi! How can I help?');
  
  // Access context
  Session.Context.SetValue('preference', 'dark_mode');
  
  // Check status
  if Session.Status = ssActive then
    // Session is active
    
  // Get hiDeepDeepDeepDeepDeepStory
  for var Msg in Session.Messages do
    WriteLn(Format('[%s]: %s', [Msg.Role, Msg.Content]));
finally
  Session.Free;
end;
```

---

### TSessionManager

Manages session lifecycle.

```pascal
var Manager := TSessionManager.Create;
try
  // Create session
  var Session := Manager.CreateSession('user_123');
  
  // Retrieve session
  Session := Manager.GetSession(Session.SessionId);
  
  // Or get/create
  Session := Manager.GetOrCreateSession(SessionId, 'user_123');
  
  // Save changes
  Manager.SaveSession(Session);
  
  // Cleanup expired
  var CleanedCount := Manager.CleanupExpiredSessions;
  
  // Get stats
  var Stats := Manager.GetStats;
finally
  Manager.Free;
end;
```

**Configuration:**

```pascal
var Config: TSessionConfig;
Config.MaxMessageHiDeepDeepDeepDeepDeepStory := 100;
Config.SessionTimeoutMinutes := 30;
Config.MaxSessionsPerUser := 5;
Config.EnablePersistence := True;

Manager.Config := Config;
```

---

## Commander (Request Router)

### TCommander

Entry point for processing user requests.

```pascal
var Commander := TCommander.Create(SessionManager, WorkflowRegistry);
try
  // Register intents
  Commander.RegisterIntent('greeting',
    ['hello|hi|hey'],           // Regex patterns
    ['hello', 'hi', 'greet']);  // Keywords
    
  Commander.RegisterIntent('help',
    ['help|assist'],
    ['help', 'support', 'how do I']);
    
  // Register routes (intent -> workflow)
  Commander.RegisterRoute('greeting', 'workflow_greeting');
  Commander.RegisterRoute('help', 'workflow_help');
  
  // Set default workflow
  Commander.DefaultWorkflowId := 'workflow_fallback';
  
  // Process request
  var Request := TUserRequest.Create;
  try
    Request.SessionId := 'session_123';
    Request.Message := 'Hello there!';
    
    var Response := Commander.ProcessRequest(Request);
    try
      WriteLn('Status: ' + IntToStr(Ord(Response.Status)));
      WriteLn('Message: ' + Response.Message);
    finally
      Response.Free;
    end;
  finally
    Request.Free;
  end;
finally
  Commander.Free;
end;
```

### TIntentRecognizer

Recognizes user intent from text.

```pascal
var Recognizer := TIntentRecognizer.Create;
try
  Recognizer.MinConfidence := 0.3;
  Recognizer.DefaultIntent := 'unknown';
  
  Recognizer.RegisterIntent('greeting',
    ['hello|hi|hey', 'good\s+(morning|afternoon|evening)'],
    ['hello', 'hi', 'greetings'],
    10);  // Priority
    
  var Intent := Recognizer.Recognize('Hello there!');
  try
    WriteLn('Intent: ' + Intent.Name);
    WriteLn('Confidence: ' + FloatToStr(Intent.Confidence));
  finally
    Intent.Free;
  end;
finally
  Recognizer.Free;
end;
```

---

## AI Integration

### TUniFlowLLMAdapter

Adapter for DeepBase LLM integration.

```pascal
var Adapter := TUniFlowLLMAdapter.Create;
try
  // Configure
  var Options: TLLMExecutionOptions;
  Options.Provider := 'openai';
  Options.Model := 'gpt-4';
  Options.MaxTokens := 1000;
  Options.Temperature := 0.7;
  Options.TimeoutMs := 30000;
  Options.SystemPrompt := 'You are a helpful assistant.';
  
  // Execute
  var Result := Adapter.Execute('Hello, how are you?', Options);
  try
    if Result.Success then
      WriteLn('Response: ' + Result.Content)
    else
      WriteLn('Error: ' + Result.ErrorMessage);
  finally
    Result.Free;
  end;
finally
  Adapter.Free;
end;
```

### TLLMActionExecutor

Action executor for LLM calls in workflows.

```pascal
// Register globally
RegisterLLMExecutor;

// Or manually
var Executor := TLLMActionExecutor.Create;
WorkflowExecutor.RegisterActionExecutor(Executor);
```

---

## Validation & Security

### TJSONSchema

JSON Schema validator.

```pascal
var Schema := TJSONSchema.Create;
try
  Schema.LoadFromJSON(TJSONObject.ParseJSONValue(
    '{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}'
  ) as TJSONObject);
  
  var Data := TJSONObject.Create;
  Data.AddPair('name', 'John');
  
  var Result := Schema.Validate(Data);
  try
    if Result.IsValid then
      WriteLn('Valid!')
    else
      for var Err in Result.Errors do
        WriteLn('Error: ' + Err.Message);
  finally
    Result.Free;
  end;
finally
  Schema.Free;
end;
```

### TSanitizer

Input sanitization.

```pascal
var Sanitizer := TSanitizer.Create;
try
  // Default sanitization (HTML + SQL + Path)
  var Clean := Sanitizer.Sanitize('<script>alert("xss")</script> SELECT * FROM users');
  
  // Specific sanitization
  Clean := Sanitizer.SanitizeHTML(UserInput);
  Clean := Sanitizer.SanitizeSQL(UserInput);
  Clean := Sanitizer.SanitizePath(UserInput);
finally
  Sanitizer.Free;
end;
```

### TPromptGuard

Prompt injection protection.

```pascal
var Guard := TPromptGuard.Create;
try
  var Result := Guard.Check(UserPrompt);
  try
    if Result.IsSafe then
      // Process prompt
    else
    begin
      WriteLn('Blocked - Risk: ' + FloatToStr(Result.RiskScore));
      for var Pattern in Result.MatchedPatterns do
        WriteLn('Matched: ' + Pattern);
    end;
  finally
    Result.Free;
  end;
finally
  Guard.Free;
end;
```

---

## Events

### Workflow Events

```pascal
Executor.OnStepStart := procedure(Sender: TWorkflowExecutor; Step: TWorkflowStep)
begin
  WriteLn('Starting step: ' + Step.Name);
end;

Executor.OnStepComplete := procedure(Sender: TWorkflowExecutor; 
  Step: TWorkflowStep; Result: TStepResult)
begin
  if Result.Success then
    WriteLn('Step completed: ' + Step.Name);
end;

Executor.OnWorkflowComplete := procedure(Sender: TWorkflowExecutor;
  Success: Boolean; Output: TJSONValue)
begin
  WriteLn('Workflow finished. Success: ' + BoolToStr(Success));
end;
```

### Session Events

```pascal
Manager.OnSessionEvent := procedure(const SessionId: string; Event: TSessionEvent)
begin
  case Event of
    seCreated: WriteLn('Session created: ' + SessionId);
    seExpired: WriteLn('Session expired: ' + SessionId);
    seClosed: WriteLn('Session closed: ' + SessionId);
  end;
end;
```

### Commander Events

```pascal
Commander.OnRequestReceived := procedure(Request: TUserRequest)
begin
  WriteLn('Request: ' + Request.Message);
end;

Commander.OnIntentRecognized := procedure(Intent: TIntent)
begin
  WriteLn(Format('Intent: %s (%.2f)', [Intent.Name, Intent.Confidence]));
end;

Commander.OnResponseSent := procedure(Response: TCommanderResponse)
begin
  WriteLn('Response: ' + Response.Message);
end;
```

---

## Error Handling

All components use consistent error handling:

```pascal
try
  Result := Executor.Start;
  if not Result.Success then
  begin
    // Check error details
    case Result.ErrorCode of
      'TIMEOUT': // Handle timeout
      'LLM_ERROR': // Handle LLM error
      'VALIDATION_ERROR': // Handle validation error
    else
      // Generic error handling
    end;
  end;
except
  on E: EWorkflowException do
    WriteLn('Workflow error: ' + E.Message);
  on E: ESessionException do
    WriteLn('Session error: ' + E.Message);
  on E: Exception do
    WriteLn('Unexpected error: ' + E.Message);
end;
```

---

## Thread Safety

All managers are thread-safe:

- `TSessionManager` - Safe for concurrent session operations
- `TSimpleWorkflowRegistry` - Safe for concurrent workflow access
- `TCommander` - Safe for concurrent request processing
- `TIntentRecognizer` - Safe for concurrent intent recognition

Individual objects (`TSession`, `TWorkflowContext`, etc.) are NOT thread-safe and should not be shared between threads.

---

## Performance Guidelines

Target performance metrics:

| Operation | Target |
|-----------|--------|
| Context variable access | < 0.1ms |
| Session lookup | < 0.1ms |
| Intent recognition | < 0.5ms |
| Workflow parsing (simple) | < 1ms |
| Workflow parsing (complex) | < 5ms |
| JSON schema validation | < 0.5ms |

Use `UniFlow.Test.Performance` to run benchmarks:

```pascal
RunPerformanceBenchmarks;
// or quick check
QuickPerformanceCheck;
```
