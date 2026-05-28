program UniFlowIntegrationDemo;
(*
  UniFlow Integration Demo
  ========================
  
  演示如何�?DeepBase 应用中集�?UniFlow 工作流引擎�?
  
  运行方式:
    1. 确保 Python Skill 服务已启�?(cd Skills && python -m uvicorn main:app)
    2. 编译并运行此程序
    
  功能演示:
    1. 基础请求处理
    2. 工作流加载与执行
    3. 会话管理
    4. 意图识别
    5. 诊断与调�?
*)

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  System.JSON,
  System.Classes,
  DeepBase.UniFlow;

var
  Engine: TUniFlowEngine;

// ============================================================================
// 事件处理
// ============================================================================

procedure OnWorkflowStart(Sender: TObject; const WorkflowId, SessionId: string);
begin
  Writeln(Format('[EVENT] Workflow started: %s (session: %s)', [WorkflowId, SessionId]));
end;

procedure OnWorkflowComplete(Sender: TObject; const WorkflowId: string; Success: Boolean);
begin
  if Success then
    Writeln(Format('[EVENT] Workflow completed: %s (success)', [WorkflowId]))
  else
    Writeln(Format('[EVENT] Workflow completed: %s (failed)', [WorkflowId]));
end;

procedure OnError(Sender: TObject; const ErrorCode, ErrorMessage: string);
begin
  Writeln(Format('[ERROR] %s: %s', [ErrorCode, ErrorMessage]));
end;

// ============================================================================
// Demo 1: 基础请求处理
// ============================================================================

procedure Demo1_BasicRequest;
var
  Response: TUniFlowResponse;
begin
  Writeln('');
  Writeln('=== Demo 1: Basic Request Processing ===');
  Writeln('');
  
  // 处理打招�?
  Response := Engine.ProcessRequest('session-1', 'Hello!', 'user-1');
  try
    Writeln('Input: Hello!');
    Writeln('Response: ' + Response.Message);
    Writeln('Status: ' + IntToStr(Ord(Response.Status)));
  finally
    Response.Free;
  end;
  
  Writeln('');
  
  // 处理帮助请求
  Response := Engine.ProcessRequest('session-1', 'How can you help me?', 'user-1');
  try
    Writeln('Input: How can you help me?');
    Writeln('Response: ' + Response.Message);
  finally
    Response.Free;
  end;
  
  Writeln('');
  
  // 处理再见
  Response := Engine.ProcessRequest('session-1', 'Goodbye!', 'user-1');
  try
    Writeln('Input: Goodbye!');
    Writeln('Response: ' + Response.Message);
  finally
    Response.Free;
  end;
end;

// ============================================================================
// Demo 2: 工作流加载与执行
// ============================================================================

const
  SIMPLE_WORKFLOW_JSON = '''
  {
    "id": "demo-greeting",
    "name": "Demo Greeting Workflow",
    "version": "1.0.0",
    "description": "A simple greeting workflow for demo",
    "steps": [
      {
        "id": "log-start",
        "type": "action",
        "name": "Log Start",
        "action": {
          "type": "log",
          "level": "info",
          "message": "Workflow started for user: {{ vars.user_name }}"
        },
        "next_step": "greet"
      },
      {
        "id": "greet",
        "type": "action",
        "name": "Generate Greeting",
        "action": {
          "type": "assign",
          "assignments": [
            {
              "target": "greeting",
              "value": "Hello, {{ vars.user_name }}! Welcome to UniFlow."
            }
          ]
        },
        "next_step": "check-vip"
      },
      {
        "id": "check-vip",
        "type": "condition",
        "name": "Check VIP Status",
        "branches": [
          {
            "condition": "{{ vars.is_vip }} == true",
            "target": "vip-greeting"
          }
        ],
        "default_branch": "end"
      },
      {
        "id": "vip-greeting",
        "type": "action",
        "name": "VIP Greeting",
        "action": {
          "type": "assign",
          "assignments": [
            {
              "target": "greeting",
              "value": "{{ vars.greeting }} You are a VIP member!"
            }
          ]
        },
        "next_step": "end"
      },
      {
        "id": "end",
        "type": "end",
        "name": "End",
        "output": {
          "greeting": "{{ vars.greeting }}"
        }
      }
    ]
  }
  ''';

procedure Demo2_WorkflowExecution;
var
  WorkflowId: string;
  Result: TUniFlowStepResult;
  Input: TJSONObject;
begin
  Writeln('');
  Writeln('=== Demo 2: Workflow Loading and Execution ===');
  Writeln('');
  
  // 加载工作�?
  WorkflowId := Engine.LoadWorkflowFromJSON(SIMPLE_WORKFLOW_JSON);
  Writeln('Loaded workflow: ' + WorkflowId);
  
  // 注册路由
  Engine.RegisterRoute('greeting', WorkflowId);
  Writeln('Registered route: greeting -> ' + WorkflowId);
  
  Writeln('');
  
  // 执行工作流（普通用户）
  Writeln('Executing workflow for normal user...');
  Input := TJSONObject.Create;
  try
    Input.AddPair('user_name', 'Alice');
    Input.AddPair('is_vip', TJSONBool.Create(False));
    
    Result := Engine.ExecuteWorkflow(WorkflowId, 'session-2', Input);
    try
      Writeln('Success: ' + BoolToStr(Result.Success, True));
      if Result.Output <> nil then
        Writeln('Output: ' + Result.Output.ToJSON);
    finally
      Result.Free;
    end;
  finally
    Input.Free;
  end;
  
  Writeln('');
  
  // 执行工作流（VIP 用户�?
  Writeln('Executing workflow for VIP user...');
  Input := TJSONObject.Create;
  try
    Input.AddPair('user_name', 'Bob');
    Input.AddPair('is_vip', TJSONBool.Create(True));
    
    Result := Engine.ExecuteWorkflow(WorkflowId, 'session-3', Input);
    try
      Writeln('Success: ' + BoolToStr(Result.Success, True));
      if Result.Output <> nil then
        Writeln('Output: ' + Result.Output.ToJSON);
    finally
      Result.Free;
    end;
  finally
    Input.Free;
  end;
end;

// ============================================================================
// Demo 3: 会话管理
// ============================================================================

procedure Demo3_SessionManagement;
var
  Session: TUniFlowSession;
  Response: TUniFlowResponse;
begin
  Writeln('');
  Writeln('=== Demo 3: Session Management ===');
  Writeln('');
  
  // 创建会话
  Session := Engine.GetOrCreateSession('demo-session', 'demo-user');
  Writeln('Created session: ' + Session.SessionId);
  Writeln('User ID: ' + Session.UserId);
  
  // 添加消息到会�?
  Session.AddUserMessage('First message');
  Session.AddAssistantMessage('Response to first message');
  Session.AddUserMessage('Second message');
  
  Writeln('Message count: ' + IntToStr(Session.GetMessageCount));
  
  // 设置会话变量
  Session.SetVariable('user_preference', 'dark_mode');
  Session.SetVariable('language', 'en');
  
  Writeln('');
  
  // 多轮对话
  Writeln('Multi-turn conversation:');
  
  Response := Engine.ProcessRequest('demo-session', 'Hello', 'demo-user');
  try
    Writeln('  User: Hello');
    Writeln('  Bot: ' + Response.Message);
  finally
    Response.Free;
  end;
  
  Response := Engine.ProcessRequest('demo-session', 'What can you do?', 'demo-user');
  try
    Writeln('  User: What can you do?');
    Writeln('  Bot: ' + Response.Message);
  finally
    Response.Free;
  end;
  
  // 获取会话统计
  Writeln('');
  Writeln('Final message count: ' + IntToStr(Session.GetMessageCount));
end;

// ============================================================================
// Demo 4: 意图识别
// ============================================================================

procedure Demo4_IntentRecognition;
var
  Response: TUniFlowResponse;
begin
  Writeln('');
  Writeln('=== Demo 4: Intent Recognition ===');
  Writeln('');
  
  // 注册自定义意�?
  Engine.RegisterIntent('weather',
    ['weather', 'forecast', '天气', '气温'],
    ['weather', 'forecast', 'sunny', 'rain', '天气', '下雨', '晴天'],
    20);
    
  Engine.RegisterIntent('calculate',
    ['calculate', 'compute', '计算', '算一�?],
    ['calculate', 'compute', 'sum', 'add', '计算', '�?, '�?, '�?, '�?],
    20);
  
  // 测试各种输入
  var TestInputs: array of string := [
    'Hello there!',
    'What is the weather like today?',
    'Can you calculate 2 + 2?',
    'I need help',
    'Goodbye, see you later'
  ];
  
  for var Input in TestInputs do
  begin
    Response := Engine.ProcessRequest('intent-test', Input, 'test-user');
    try
      Writeln(Format('Input: "%s"', [Input]));
      Writeln(Format('  -> Response: %s', [Response.Message]));
      Writeln('');
    finally
      Response.Free;
    end;
  end;
end;

// ============================================================================
// Demo 5: 诊断与调�?
// ============================================================================

procedure Demo5_Diagnostics;
var
  Diag: TUniFlowDiagnostics;
begin
  Writeln('');
  Writeln('=== Demo 5: Diagnostics ===');
  Writeln('');
  
  Diag := Engine.GetDiagnostics;
  if Diag = nil then
  begin
    Writeln('Diagnostics not enabled');
    Exit;
  end;
  
  // 设置追踪级别
  Writeln('Trace level: Normal');
  Writeln('');
  
  // 执行一些操作并记录
  Writeln('Executing operations with tracing...');
  
  var Response := Engine.ProcessRequest('diag-session', 'Test message', 'diag-user');
  try
    Writeln('Request processed');
  finally
    Response.Free;
  end;
  
  // 导出追踪
  Writeln('');
  Writeln('Trace export available via Engine.ExportTrace(correlationId)');
end;

// ============================================================================
// Main
// ============================================================================

procedure RunAllDemos;
begin
  Writeln('');
  Writeln('============================================');
  Writeln('     UniFlow Integration Demo');
  Writeln('============================================');
  
  // 创建引擎
  Engine := TUniFlowEngine.Create;
  try
    // 配置
    Engine.Config.EnableAudit := True;
    Engine.Config.EnableMetrics := True;
    Engine.Config.EnableDiagnostics := True;
    Engine.Config.SkillServiceURL := ''; // 禁用 Skill（本 Demo 不需要）
    
    // 注册事件
    Engine.OnWorkflowStart := OnWorkflowStart;
    Engine.OnWorkflowComplete := OnWorkflowComplete;
    Engine.OnError := OnError;
    
    // 初始�?
    Engine.Initialize;
    Writeln('Engine initialized successfully');
    
    // 运行 Demo
    Demo1_BasicRequest;
    Demo2_WorkflowExecution;
    Demo3_SessionManagement;
    Demo4_IntentRecognition;
    Demo5_Diagnostics;
    
    // 显示已注册的工作�?
    Writeln('');
    Writeln('============================================');
    Writeln('Registered Workflows:');
    for var Id in Engine.GetWorkflowIds do
      Writeln('  - ' + Id);
    Writeln('============================================');
    
  finally
    Engine.Free;
  end;
  
  Writeln('');
  Writeln('Demo completed successfully!');
  Writeln('Press Enter to exit...');
  Readln;
end;

begin
  try
    RunAllDemos;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ' + E.Message);
      Writeln('Press Enter to exit...');
      Readln;
    end;
  end;
end.
