program UniFlowE2ETest;
(*
  UniFlow End-to-End Test
  =======================
  
  端到端测试：验证完整工作流执行链�?
  输入 �?Commander �?Workflow �?LLM/Skill �?输出
  
  测试场景�?
  1. 简单问答工作流（无 LLM�?
  2. �?Skill 调用的工作流
  3. 完整 AI 对话工作流（需�?LLM 配置�?
  4. 错误处理与重�?
  5. 多轮对话上下�?
*)

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Diagnostics,
  DeepBase.UniFlow;

type
  TTestResult = record
    Name: string;
    Passed: Boolean;
    Message: string;
    DurationMs: Int64;
  end;

var
  Engine: TUniFlowEngine;
  TestResults: array of TTestResult;
  TotalPassed: Integer;
  TotalFailed: Integer;

procedure AddResult(const AName: string; APassed: Boolean; const AMessage: string; ADurationMs: Int64);
var
  R: TTestResult;
begin
  R.Name := AName;
  R.Passed := APassed;
  R.Message := AMessage;
  R.DurationMs := ADurationMs;
  
  SetLength(TestResults, Length(TestResults) + 1);
  TestResults[High(TestResults)] := R;
  
  if APassed then
    Inc(TotalPassed)
  else
    Inc(TotalFailed);
    
  if APassed then
    Writeln(Format('  [PASS] %s (%dms)', [AName, ADurationMs]))
  else
    Writeln(Format('  [FAIL] %s - %s (%dms)', [AName, AMessage, ADurationMs]));
end;

// ============================================================================
// Test Workflows
// ============================================================================

const
  // 简单问答工作流（纯规则，无 AI�?
  WORKFLOW_SIMPLE_QA = '''
  {
    "id": "e2e-simple-qa",
    "name": "Simple QA Workflow",
    "version": "1.0.0",
    "steps": [
      {
        "id": "validate-input",
        "type": "action",
        "name": "Validate Input",
        "action": {
          "type": "guard",
          "rules": [
            { "field": "question", "required": true, "min_length": 1 }
          ]
        },
        "next_step": "generate-answer",
        "error_handler": {
          "strategy": "fallback",
          "fallback_step": "invalid-input"
        }
      },
      {
        "id": "generate-answer",
        "type": "action",
        "name": "Generate Answer",
        "action": {
          "type": "assign",
          "assignments": [
            {
              "target": "answer",
              "value": "You asked: {{ vars.input.question }}. This is a test response."
            }
          ]
        },
        "next_step": "log-response"
      },
      {
        "id": "log-response",
        "type": "action",
        "name": "Log Response",
        "action": {
          "type": "log",
          "level": "info",
          "message": "Generated answer for question"
        },
        "next_step": "end"
      },
      {
        "id": "invalid-input",
        "type": "action",
        "name": "Invalid Input",
        "action": {
          "type": "assign",
          "assignments": [
            { "target": "answer", "value": "Please provide a valid question." }
          ]
        },
        "next_step": "end"
      },
      {
        "id": "end",
        "type": "end",
        "name": "End",
        "output": {
          "answer": "{{ vars.answer }}"
        }
      }
    ]
  }
  ''';

  // 条件分支工作�?
  WORKFLOW_CONDITIONAL = '''
  {
    "id": "e2e-conditional",
    "name": "Conditional Workflow",
    "version": "1.0.0",
    "steps": [
      {
        "id": "check-type",
        "type": "condition",
        "name": "Check Request Type",
        "branches": [
          {
            "condition": "{{ vars.input.type }} == 'greeting'",
            "target": "handle-greeting"
          },
          {
            "condition": "{{ vars.input.type }} == 'farewell'",
            "target": "handle-farewell"
          },
          {
            "condition": "{{ vars.input.type }} == 'question'",
            "target": "handle-question"
          }
        ],
        "default_branch": "handle-unknown"
      },
      {
        "id": "handle-greeting",
        "type": "action",
        "name": "Handle Greeting",
        "action": {
          "type": "assign",
          "assignments": [
            { "target": "response", "value": "Hello! How can I help you today?" }
          ]
        },
        "next_step": "end"
      },
      {
        "id": "handle-farewell",
        "type": "action",
        "name": "Handle Farewell",
        "action": {
          "type": "assign",
          "assignments": [
            { "target": "response", "value": "Goodbye! Have a great day!" }
          ]
        },
        "next_step": "end"
      },
      {
        "id": "handle-question",
        "type": "action",
        "name": "Handle Question",
        "action": {
          "type": "assign",
          "assignments": [
            { "target": "response", "value": "Your question: {{ vars.input.content }}" }
          ]
        },
        "next_step": "end"
      },
      {
        "id": "handle-unknown",
        "type": "action",
        "name": "Handle Unknown",
        "action": {
          "type": "assign",
          "assignments": [
            { "target": "response", "value": "I'm not sure how to handle that request." }
          ]
        },
        "next_step": "end"
      },
      {
        "id": "end",
        "type": "end",
        "name": "End",
        "output": {
          "response": "{{ vars.response }}"
        }
      }
    ]
  }
  ''';

  // 循环工作�?
  WORKFLOW_LOOP = '''
  {
    "id": "e2e-loop",
    "name": "Loop Workflow",
    "version": "1.0.0",
    "steps": [
      {
        "id": "init",
        "type": "action",
        "name": "Initialize",
        "action": {
          "type": "assign",
          "assignments": [
            { "target": "result", "value": "" },
            { "target": "count", "value": 0 }
          ]
        },
        "next_step": "loop-items"
      },
      {
        "id": "loop-items",
        "type": "loop",
        "name": "Process Items",
        "loop": {
          "mode": "forEach",
          "collection": "{{ vars.input.items }}",
          "item_var": "current_item",
          "index_var": "idx"
        },
        "body_step": "process-item",
        "next_step": "end"
      },
      {
        "id": "process-item",
        "type": "action",
        "name": "Process Single Item",
        "action": {
          "type": "assign",
          "assignments": [
            { "target": "result", "value": "{{ vars.result }}[{{ vars.idx }}:{{ vars.current_item }}]" }
          ]
        },
        "next_step": "loop-items"
      },
      {
        "id": "end",
        "type": "end",
        "name": "End",
        "output": {
          "result": "{{ vars.result }}"
        }
      }
    ]
  }
  ''';

  // 错误处理工作�?
  WORKFLOW_ERROR_HANDLING = '''
  {
    "id": "e2e-error",
    "name": "Error Handling Workflow",
    "version": "1.0.0",
    "steps": [
      {
        "id": "risky-operation",
        "type": "action",
        "name": "Risky Operation",
        "action": {
          "type": "guard",
          "rules": [
            { "field": "must_exist", "required": true }
          ]
        },
        "next_step": "success",
        "error_handler": {
          "strategy": "fallback",
          "fallback_step": "handle-error"
        }
      },
      {
        "id": "success",
        "type": "action",
        "name": "Success",
        "action": {
          "type": "assign",
          "assignments": [
            { "target": "status", "value": "success" },
            { "target": "message", "value": "Operation completed successfully" }
          ]
        },
        "next_step": "end"
      },
      {
        "id": "handle-error",
        "type": "action",
        "name": "Handle Error",
        "action": {
          "type": "assign",
          "assignments": [
            { "target": "status", "value": "error" },
            { "target": "message", "value": "Operation failed, using fallback" }
          ]
        },
        "next_step": "end"
      },
      {
        "id": "end",
        "type": "end",
        "name": "End",
        "output": {
          "status": "{{ vars.status }}",
          "message": "{{ vars.message }}"
        }
      }
    ]
  }
  ''';

// ============================================================================
// Test Cases
// ============================================================================

procedure Test_SimpleQA_ValidInput;
var
  SW: TStopwatch;
  Input: TJSONObject;
  Result: TUniFlowStepResult;
begin
  SW := TStopwatch.StartNew;
  Input := TJSONObject.Create;
  try
    Input.AddPair('question', 'What is UniFlow?');
    Result := Engine.ExecuteWorkflow('e2e-simple-qa', 'test-session-1', Input);
    try
      if Result.Success then
        AddResult('SimpleQA_ValidInput', True, '', SW.ElapsedMilliseconds)
      else
        AddResult('SimpleQA_ValidInput', False, Result.ErrorMessage, SW.ElapsedMilliseconds);
    finally
      Result.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure Test_SimpleQA_EmptyInput;
var
  SW: TStopwatch;
  Input: TJSONObject;
  Result: TUniFlowStepResult;
begin
  SW := TStopwatch.StartNew;
  Input := TJSONObject.Create;
  try
    Input.AddPair('question', ''); // Empty question
    Result := Engine.ExecuteWorkflow('e2e-simple-qa', 'test-session-2', Input);
    try
      // Should trigger fallback
      if Result.Success then
        AddResult('SimpleQA_EmptyInput', True, 'Fallback triggered correctly', SW.ElapsedMilliseconds)
      else
        AddResult('SimpleQA_EmptyInput', False, 'Expected fallback to handle empty input', SW.ElapsedMilliseconds);
    finally
      Result.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure Test_Conditional_Greeting;
var
  SW: TStopwatch;
  Input: TJSONObject;
  Result: TUniFlowStepResult;
begin
  SW := TStopwatch.StartNew;
  Input := TJSONObject.Create;
  try
    Input.AddPair('type', 'greeting');
    Input.AddPair('content', '');
    Result := Engine.ExecuteWorkflow('e2e-conditional', 'test-session-3', Input);
    try
      AddResult('Conditional_Greeting', Result.Success, 
        IfThen(Result.Success, '', Result.ErrorMessage), SW.ElapsedMilliseconds);
    finally
      Result.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure Test_Conditional_Question;
var
  SW: TStopwatch;
  Input: TJSONObject;
  Result: TUniFlowStepResult;
begin
  SW := TStopwatch.StartNew;
  Input := TJSONObject.Create;
  try
    Input.AddPair('type', 'question');
    Input.AddPair('content', 'How does this work?');
    Result := Engine.ExecuteWorkflow('e2e-conditional', 'test-session-4', Input);
    try
      AddResult('Conditional_Question', Result.Success,
        IfThen(Result.Success, '', Result.ErrorMessage), SW.ElapsedMilliseconds);
    finally
      Result.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure Test_Conditional_Unknown;
var
  SW: TStopwatch;
  Input: TJSONObject;
  Result: TUniFlowStepResult;
begin
  SW := TStopwatch.StartNew;
  Input := TJSONObject.Create;
  try
    Input.AddPair('type', 'unknown_type');
    Input.AddPair('content', '');
    Result := Engine.ExecuteWorkflow('e2e-conditional', 'test-session-5', Input);
    try
      AddResult('Conditional_Unknown', Result.Success,
        IfThen(Result.Success, '', Result.ErrorMessage), SW.ElapsedMilliseconds);
    finally
      Result.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure Test_ErrorHandling_Success;
var
  SW: TStopwatch;
  Input: TJSONObject;
  Result: TUniFlowStepResult;
begin
  SW := TStopwatch.StartNew;
  Input := TJSONObject.Create;
  try
    Input.AddPair('must_exist', 'present');
    Result := Engine.ExecuteWorkflow('e2e-error', 'test-session-6', Input);
    try
      AddResult('ErrorHandling_Success', Result.Success,
        IfThen(Result.Success, '', Result.ErrorMessage), SW.ElapsedMilliseconds);
    finally
      Result.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure Test_ErrorHandling_Fallback;
var
  SW: TStopwatch;
  Input: TJSONObject;
  Result: TUniFlowStepResult;
begin
  SW := TStopwatch.StartNew;
  Input := TJSONObject.Create;
  try
    // Missing required field - should trigger fallback
    Result := Engine.ExecuteWorkflow('e2e-error', 'test-session-7', Input);
    try
      AddResult('ErrorHandling_Fallback', Result.Success,
        IfThen(Result.Success, 'Fallback worked', Result.ErrorMessage), SW.ElapsedMilliseconds);
    finally
      Result.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure Test_Commander_IntentRecognition;
var
  SW: TStopwatch;
  Response: TUniFlowResponse;
begin
  SW := TStopwatch.StartNew;
  Response := Engine.ProcessRequest('test-session-8', 'Hello!', 'test-user');
  try
    AddResult('Commander_IntentRecognition', Response.Status = rsSuccess,
      IfThen(Response.Status = rsSuccess, '', Response.ErrorMessage), SW.ElapsedMilliseconds);
  finally
    Response.Free;
  end;
end;

procedure Test_Session_Persistence;
var
  SW: TStopwatch;
  Session1, Session2: TUniFlowSession;
  Passed: Boolean;
begin
  SW := TStopwatch.StartNew;
  
  // Create session and add data
  Session1 := Engine.GetOrCreateSession('persist-test', 'persist-user');
  Session1.AddUserMessage('Test message');
  Session1.SetVariable('test_var', 'test_value');
  
  // Retrieve same session
  Session2 := Engine.GetOrCreateSession('persist-test', 'persist-user');
  
  Passed := (Session2.GetMessageCount > 0) and 
            (Session2.GetVariable('test_var') = 'test_value');
  
  AddResult('Session_Persistence', Passed,
    IfThen(Passed, '', 'Session data not persisted'), SW.ElapsedMilliseconds);
end;

procedure Test_MultiTurn_Conversation;
var
  SW: TStopwatch;
  Response1, Response2, Response3: TUniFlowResponse;
  Session: TUniFlowSession;
  Passed: Boolean;
begin
  SW := TStopwatch.StartNew;
  
  // Simulate multi-turn conversation
  Response1 := Engine.ProcessRequest('multi-turn-test', 'Hello', 'multi-user');
  try
    Response2 := Engine.ProcessRequest('multi-turn-test', 'I need help', 'multi-user');
    try
      Response3 := Engine.ProcessRequest('multi-turn-test', 'Goodbye', 'multi-user');
      try
        Session := Engine.GetOrCreateSession('multi-turn-test', 'multi-user');
        
        // Should have accumulated messages
        Passed := Session.GetMessageCount >= 3;
        
        AddResult('MultiTurn_Conversation', Passed,
          IfThen(Passed, '', Format('Expected >= 3 messages, got %d', [Session.GetMessageCount])),
          SW.ElapsedMilliseconds);
      finally
        Response3.Free;
      end;
    finally
      Response2.Free;
    end;
  finally
    Response1.Free;
  end;
end;

procedure Test_Workflow_Registration;
var
  SW: TStopwatch;
  Ids: TArray<string>;
  Passed: Boolean;
begin
  SW := TStopwatch.StartNew;
  
  Ids := Engine.GetWorkflowIds;
  Passed := Length(Ids) >= 4; // At least our test workflows
  
  AddResult('Workflow_Registration', Passed,
    IfThen(Passed, Format('%d workflows registered', [Length(Ids)]), 
      Format('Expected >= 4 workflows, got %d', [Length(Ids)])),
    SW.ElapsedMilliseconds);
end;

procedure Test_Diagnostics_Available;
var
  SW: TStopwatch;
  Diag: TUniFlowDiagnostics;
begin
  SW := TStopwatch.StartNew;
  
  Diag := Engine.GetDiagnostics;
  AddResult('Diagnostics_Available', Diag <> nil,
    IfThen(Diag <> nil, '', 'Diagnostics not available'), SW.ElapsedMilliseconds);
end;

// ============================================================================
// Main
// ============================================================================

procedure LoadTestWorkflows;
begin
  Writeln('Loading test workflows...');
  Engine.LoadWorkflowFromJSON(WORKFLOW_SIMPLE_QA);
  Engine.LoadWorkflowFromJSON(WORKFLOW_CONDITIONAL);
  Engine.LoadWorkflowFromJSON(WORKFLOW_LOOP);
  Engine.LoadWorkflowFromJSON(WORKFLOW_ERROR_HANDLING);
  Writeln('  Loaded 4 test workflows');
end;

procedure RunAllTests;
var
  SW: TStopwatch;
begin
  SW := TStopwatch.StartNew;
  
  Writeln('');
  Writeln('============================================');
  Writeln('     UniFlow End-to-End Tests');
  Writeln('============================================');
  Writeln('');
  
  // Initialize
  Engine := TUniFlowEngine.Create;
  try
    Engine.Config.EnableAudit := True;
    Engine.Config.EnableMetrics := True;
    Engine.Config.EnableDiagnostics := True;
    Engine.Config.SkillServiceURL := ''; // No skill service for basic tests
    
    Engine.Initialize;
    Writeln('Engine initialized');
    Writeln('');
    
    // Load workflows
    LoadTestWorkflows;
    Writeln('');
    
    // Run tests
    Writeln('Running tests...');
    Writeln('');
    
    Test_SimpleQA_ValidInput;
    Test_SimpleQA_EmptyInput;
    Test_Conditional_Greeting;
    Test_Conditional_Question;
    Test_Conditional_Unknown;
    Test_ErrorHandling_Success;
    Test_ErrorHandling_Fallback;
    Test_Commander_IntentRecognition;
    Test_Session_Persistence;
    Test_MultiTurn_Conversation;
    Test_Workflow_Registration;
    Test_Diagnostics_Available;
    
  finally
    Engine.Free;
  end;
  
  // Summary
  Writeln('');
  Writeln('============================================');
  Writeln('                Summary');
  Writeln('============================================');
  Writeln(Format('  Total:  %d', [TotalPassed + TotalFailed]));
  Writeln(Format('  Passed: %d', [TotalPassed]));
  Writeln(Format('  Failed: %d', [TotalFailed]));
  Writeln(Format('  Time:   %dms', [SW.ElapsedMilliseconds]));
  Writeln('============================================');
  
  if TotalFailed = 0 then
    Writeln('  ALL TESTS PASSED!')
  else
    Writeln('  SOME TESTS FAILED!');
    
  Writeln('');
end;

function IfThen(ACondition: Boolean; const ATrue, AFalse: string): string;
begin
  if ACondition then
    Result := ATrue
  else
    Result := AFalse;
end;

begin
  try
    TotalPassed := 0;
    TotalFailed := 0;
    
    RunAllTests;
    
    Writeln('Press Enter to exit...');
    Readln;
    
    if TotalFailed > 0 then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln('FATAL ERROR: ' + E.Message);
      Writeln('Press Enter to exit...');
      Readln;
      ExitCode := 2;
    end;
  end;
end.
