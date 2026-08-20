unit DeepBase.DeepFlow;
(*
  DeepBase.DeepFlow - Facade Unit for DeepFlow Integration
  =====================================================
  
  统一导出 DeepFlow 所有功能的外观单元，简化集成�?
  
  使用示例:
  
  ```pascal
  uses
    DeepBase.DeepFlow,
  DeepBase.Exceptions;
  
  var
    Engine: TDeepFlowEngine;
  begin
    Engine := TDeepFlowEngine.Create;
    try
      // 加载工作流定�?
      Engine.LoadWorkflow('Config/workflows/simple_qa.workflow.json');
      
      // 处理用户请求
      var Response := Engine.ProcessRequest('user-123', 'Hello, how are you?');
      Writeln(Response.Message);
    finally
      Engine.Free;
    end;
  end;
  ```
  
  Architecture:
  
  ```
  ┌─────────────────────────────────────────────────────────────�?
  �?                   TDeepFlowEngine (Facade)                  �?
  ├─────────────────────────────────────────────────────────────�?
  �? ProcessRequest()   Execute()   LoadWorkflow()              �?
  └─────────────────────────────────────────────────────────────�?
              �?             �?             �?
              �?             �?             �?
  ┌───────────────�?┌───────────────�?┌───────────────�?
  �? TCommander   �?�? TExecutor    �?�? TDefinition  �?
  �? (意图识别)    �?�? (步骤执行)    �?�? (工作流定�?  �?
  └───────────────�?└───────────────�?└───────────────�?
              �?             �?             �?
              �?             �?             �?
  ┌───────────────�?┌───────────────�?┌───────────────�?
  �? TSession     �?�? LLM/Skill    �?�? Context      �?
  �? (会话管理)    �?�? (AI调用)      �?�? (变量上下�?  �?
  └───────────────�?└───────────────�?└───────────────�?
  ```
*)

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.IOUtils,
  System.SyncObjs,
  DeepBase.Exceptions,
  // Workflow
  DeepFlow.Workflow.Definition,
  DeepFlow.Workflow.Context,
  DeepFlow.Workflow.Executor,
  DeepFlow.Workflow.State,
  // Session
  DeepFlow.Session.Types,
  DeepFlow.Session.Manager,
  // Roles
  DeepFlow.Roles.Commander,
  // AI Integration
  DeepFlow.AI.Adapter,
  // Skill
  DeepFlow.Skill.Types,
  DeepFlow.Skill.Client,
  DeepFlow.Skill.Executor,
  // Security
  DeepFlow.Security.Sanitizer,
  DeepFlow.Security.Filter,
  DeepFlow.Security.RateLimit,
  // Validation
  DeepFlow.Validation.Schema,
  // Audit
  DeepFlow.Audit.Types,
  DeepFlow.Audit.Store,
  DeepFlow.Audit.Manager,
  // Metrics
  DeepFlow.Metrics.Types,
  DeepFlow.Metrics.Collector,
  // Diagnostics
  DeepFlow.Diagnostics,
  DeepFlow.Diagnostics.Integration,
  DeepFlow.Diagnostics.ErrorCollector,
  DeepFlow.Diagnostics.TraceExporter,
  DeepFlow.Diagnostics.Debugger;

type
  // ============================================================================
  // 重新导出核心类型
  // ============================================================================
  
  // Workflow
  TDeepFlowDefinition = DeepFlow.Workflow.Definition.TWorkflowDefinition;
  TDeepFlowStep = DeepFlow.Workflow.Definition.TWorkflowStep;
  TDeepFlowStepType = DeepFlow.Workflow.Definition.TStepType;
  TDeepFlowActionType = DeepFlow.Workflow.Definition.TActionType;
  
  // Execution
  TDeepFlowExecutor = DeepFlow.Workflow.Executor.TWorkflowExecutor;
  TDeepFlowContext = DeepFlow.Workflow.Context.TWorkflowContext;
  TDeepFlowStepResult = DeepFlow.Workflow.Executor.TStepResult;
  TDeepFlowExecutionStatus = DeepFlow.Workflow.Executor.TExecutionStatus;
  
  // Session
  TDeepFlowSession = DeepFlow.Session.Types.TSession;
  TDeepFlowSessionManager = DeepFlow.Session.Manager.TSessionManager;
  
  // Commander
  TDeepFlowRequest = DeepFlow.Roles.Commander.TUserRequest;
  TDeepFlowResponse = DeepFlow.Roles.Commander.TCommanderResponse;
  TDeepFlowCommander = DeepFlow.Roles.Commander.TCommander;
  
  // Diagnostics
  TDeepFlowDiagnostics = DeepFlow.Diagnostics.TDeepFlowDiagnostics;
  TDeepFlowDebugger = DeepFlow.Diagnostics.Debugger.TWorkflowDebugger;
  
  // Metrics
  TDeepFlowMetrics = DeepFlow.Metrics.Collector.TDeepFlowMetrics;
  
  // ============================================================================
  // Engine 配置
  // ============================================================================
  
  TDeepFlowEngineConfig = class
  private
    FWorkflowDir: string;
    FSessionTimeout: Integer;
    FMaxSessionsPerUser: Integer;
    FEnableAudit: Boolean;
    FEnableMetrics: Boolean;
    FEnableDiagnostics: Boolean;
    FSkillServiceURL: string;
    FLLMConfigName: string;
  public
    constructor Create;
    
    /// <summary>工作流定义目�?/summary>
    property WorkflowDir: string read FWorkflowDir write FWorkflowDir;
    /// <summary>会话超时(�?</summary>
    property SessionTimeout: Integer read FSessionTimeout write FSessionTimeout;
    /// <summary>每用户最大会话数</summary>
    property MaxSessionsPerUser: Integer read FMaxSessionsPerUser write FMaxSessionsPerUser;
    /// <summary>启用审计日志</summary>
    property EnableAudit: Boolean read FEnableAudit write FEnableAudit;
    /// <summary>启用指标收集</summary>
    property EnableMetrics: Boolean read FEnableMetrics write FEnableMetrics;
    /// <summary>启用诊断追踪</summary>
    property EnableDiagnostics: Boolean read FEnableDiagnostics write FEnableDiagnostics;
    /// <summary>Skill 服务 URL</summary>
    property SkillServiceURL: string read FSkillServiceURL write FSkillServiceURL;
    /// <summary>LLM 配置名称</summary>
    property LLMConfigName: string read FLLMConfigName write FLLMConfigName;
  end;
  
  // ============================================================================
  // 事件类型
  // ============================================================================
  
  TOnWorkflowStartEvent = procedure(Sender: TObject; const WorkflowId, SessionId: string) of object;
  TOnWorkflowCompleteEvent = procedure(Sender: TObject; const WorkflowId: string; Success: Boolean) of object;
  TOnStepExecuteEvent = procedure(Sender: TObject; const WorkflowId, StepId: string) of object;
  TOnErrorEvent = procedure(Sender: TObject; const ErrorCode, ErrorMessage: string) of object;
  
  // ============================================================================
  // TDeepFlowEngine - 主引擎外观类
  // ============================================================================
  
  TDeepFlowEngine = class
  private
    FConfig: TDeepFlowEngineConfig;
    FSessionManager: TSessionManager;
    FCommander: TCommander;
    FWorkflowRegistry: TSimpleWorkflowRegistry;
    FWorkflows: TObjectDictionary<string, TWorkflowDefinition>;
    FSkillClient: TSkillClient;
    FDiagnostics: TDeepFlowDiagnostics;
    FLock: TCriticalSection;
    FInitialized: Boolean;
    
    // 事件
    FOnWorkflowStart: TOnWorkflowStartEvent;
    FOnWorkflowComplete: TOnWorkflowCompleteEvent;
    FOnStepExecute: TOnStepExecuteEvent;
    FOnError: TOnErrorEvent;
    
    procedure EnsureInitialized;
    function CreateExecutor(const AWorkflowId: string; ASession: TSession): TWorkflowExecutor;
    procedure RegisterBuiltinIntents;
    procedure DoWorkflowStart(const AWorkflowId, ASessionId: string);
    procedure DoWorkflowComplete(const AWorkflowId: string; ASuccess: Boolean);
    procedure DoStepExecute(const AWorkflowId, AStepId: string);
    procedure DoError(const AErrorCode, AErrorMessage: string);
  public
    constructor Create; overload;
    constructor Create(AConfig: TDeepFlowEngineConfig); overload;
    destructor Destroy; override;
    
    /// <summary>初始化引�?/summary>
    procedure Initialize;
    
    /// <summary>关闭引擎</summary>
    procedure Shutdown;
    
    // ========================================================================
    // 工作流管�?
    // ========================================================================
    
    /// <summary>�?JSON 文件加载工作流定�?/summary>
    function LoadWorkflow(const AFilePath: string): string;
    
    /// <summary>�?JSON 字符串加载工作流定义</summary>
    function LoadWorkflowFromJSON(const AJSON: string): string;
    
    /// <summary>获取已注册的工作流定�?/summary>
    function GetWorkflow(const AWorkflowId: string): TWorkflowDefinition;
    
    /// <summary>获取所有工作流 ID</summary>
    function GetWorkflowIds: TArray<string>;
    
    /// <summary>注册意图到工作流的路�?/summary>
    procedure RegisterRoute(const AIntentName, AWorkflowId: string);
    
    /// <summary>注册意图识别模式</summary>
    procedure RegisterIntent(const AIntentName: string;
      const APatterns, AKeywords: TArray<string>;
      APriority: Integer = 0);
    
    // ========================================================================
    // 请求处理
    // ========================================================================
    
    /// <summary>处理用户请求（主入口�?/summary>
    function ProcessRequest(const ASessionId, AMessage: string;
      const AUserId: string = ''): TCommanderResponse;
    
    /// <summary>处理用户请求（使用请求对象）</summary>
    function ProcessRequestObj(ARequest: TUserRequest): TCommanderResponse;
    
    /// <summary>直接执行指定工作�?/summary>
    function ExecuteWorkflow(const AWorkflowId, ASessionId: string;
      AInput: TJSONObject = nil): TStepResult;
    
    /// <summary>获取或创建会�?/summary>
    function GetOrCreateSession(const ASessionId: string;
      const AUserId: string = ''): TSession;
    
    // ========================================================================
    // 诊断与调�?
    // ========================================================================
    
    /// <summary>获取诊断实例</summary>
    function GetDiagnostics: TDeepFlowDiagnostics;
    
    /// <summary>创建工作流调试器</summary>
    function CreateDebugger(const AWorkflowId, ASessionId: string): TWorkflowDebugger;
    
    /// <summary>导出执行轨迹</summary>
    function ExportTrace(const ACorrelationId: string): string;
    
    // ========================================================================
    // 属�?
    // ========================================================================
    
    property Config: TDeepFlowEngineConfig read FConfig;
    property SessionManager: TSessionManager read FSessionManager;
    property Commander: TCommander read FCommander;
    property Initialized: Boolean read FInitialized;
    
    // 事件
    property OnWorkflowStart: TOnWorkflowStartEvent read FOnWorkflowStart write FOnWorkflowStart;
    property OnWorkflowComplete: TOnWorkflowCompleteEvent read FOnWorkflowComplete write FOnWorkflowComplete;
    property OnStepExecute: TOnStepExecuteEvent read FOnStepExecute write FOnStepExecute;
    property OnError: TOnErrorEvent read FOnError write FOnError;
  end;

// ============================================================================
// 全局实例访问
// ============================================================================

/// <summary>获取全局 DeepFlow 引擎实例</summary>
function DeepFlowEngine: TDeepFlowEngine;

/// <summary>初始化全局引擎</summary>
procedure InitializeDeepFlow(AConfig: TDeepFlowEngineConfig = nil);

/// <summary>关闭全局引擎</summary>
procedure FinalizeDeepFlow;

implementation

var
  GEngine: TDeepFlowEngine = nil;
  GEngineLock: TCriticalSection = nil;

function DeepFlowEngine: TDeepFlowEngine;
begin
  if GEngine = nil then
    raise EOperationException.Create('DeepFlow engine not initialized. Call InitializeDeepFlow first.');
  Result := GEngine;
end;

procedure InitializeDeepFlow(AConfig: TDeepFlowEngineConfig);
begin
  if GEngineLock = nil then
    GEngineLock := TCriticalSection.Create;
    
  GEngineLock.Enter;
  try
    if GEngine = nil then
    begin
      if AConfig <> nil then
        GEngine := TDeepFlowEngine.Create(AConfig)
      else
        GEngine := TDeepFlowEngine.Create;
      GEngine.Initialize;
    end;
  finally
    GEngineLock.Leave;
  end;
end;

procedure FinalizeDeepFlow;
begin
  if GEngineLock <> nil then
  begin
    GEngineLock.Enter;
    try
      if GEngine <> nil then
      begin
        GEngine.Shutdown;
        FreeAndNil(GEngine);
      end;
    finally
      GEngineLock.Leave;
    end;
    FreeAndNil(GEngineLock);
  end;
end;

{ TDeepFlowEngineConfig }

constructor TDeepFlowEngineConfig.Create;
begin
  inherited;
  FWorkflowDir := 'Config/workflows';
  FSessionTimeout := 3600; // 1 hour
  FMaxSessionsPerUser := 10;
  FEnableAudit := True;
  FEnableMetrics := True;
  FEnableDiagnostics := True;
  FSkillServiceURL := 'http://localhost:8000';
  FLLMConfigName := 'Default';
end;

{ TDeepFlowEngine }

constructor TDeepFlowEngine.Create;
begin
  Create(TDeepFlowEngineConfig.Create);
end;

constructor TDeepFlowEngine.Create(AConfig: TDeepFlowEngineConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FLock := TCriticalSection.Create;
  FWorkflows := TObjectDictionary<string, TWorkflowDefinition>.Create([doOwnsValues]);
  FInitialized := False;
end;

destructor TDeepFlowEngine.Destroy;
begin
  Shutdown;
  FWorkflows.Free;
  FLock.Free;
  FConfig.Free;
  inherited;
end;

procedure TDeepFlowEngine.Initialize;
var
  SessionConfig: TSessionConfig;
begin
  FLock.Enter;
  try
    if FInitialized then
      Exit;
    
    // 初始化会话管理器
    SessionConfig.DefaultTimeoutMinutes := FConfig.SessionTimeout div 60;
    SessionConfig.MaxSessionsPerUser := FConfig.MaxSessionsPerUser;
    SessionConfig.CleanupIntervalMinutes := 5;
    
    FSessionManager := TSessionManager.Create(TMemorySessionStore.Create);
    FSessionManager.Config := SessionConfig;
    
    // 初始化工作流注册�?
    FWorkflowRegistry := TSimpleWorkflowRegistry.Create;
    
    // 初始�?Commander
    FCommander := TCommander.Create(FSessionManager, FWorkflowRegistry);
    RegisterBuiltinIntents;
    
    // 初始�?Skill 客户�?
    if FConfig.SkillServiceURL <> '' then
      FSkillClient := TSkillClient.Create(FConfig.SkillServiceURL);
    
    // 初始化诊�?
    if FConfig.EnableDiagnostics then
      FDiagnostics := Diagnostics();  // 使用全局实例
    
    // 初始化审�?
    if FConfig.EnableAudit then
      InitializeAuditManager(TMemoryAuditStore.Create);
    
    FInitialized := True;
  finally
    FLock.Leave;
  end;
end;

procedure TDeepFlowEngine.Shutdown;
begin
  FLock.Enter;
  try
    if not FInitialized then
      Exit;
    
    // 清理资源
    if FConfig.EnableAudit then
      FinalizeAuditManager;
    
    FreeAndNil(FSkillClient);
    FreeAndNil(FCommander);
    FreeAndNil(FWorkflowRegistry);
    FreeAndNil(FSessionManager);
    
    FInitialized := False;
  finally
    FLock.Leave;
  end;
end;

procedure TDeepFlowEngine.EnsureInitialized;
begin
  if not FInitialized then
    raise EOperationException.Create('DeepFlow engine not initialized. Call Initialize first.');
end;

procedure TDeepFlowEngine.RegisterBuiltinIntents;
begin
  // 默认意图
  FCommander.IntentRecognizer.RegisterIntent('greeting',
    ['^(hi|hello|hey|你好|嗨'],
    ['hello', 'hi', 'hey', '你好', '嗨', '早上好', '下午好'],
    10);
    
  FCommander.IntentRecognizer.RegisterIntent('help',
    ['^(help|帮助|怎么停止'],
    ['help', '帮助', '怎么停止', '如何使用'],
    10);
    
  FCommander.IntentRecognizer.RegisterIntent('bye',
    ['^(bye|goodbye|再见|拜拜)'],
    ['bye', 'goodbye', '再见', '拜拜', '结束'],
    10);
    
  FCommander.IntentRecognizer.DefaultIntent := 'chat';
end;

function TDeepFlowEngine.LoadWorkflow(const AFilePath: string): string;
var
  JSON: string;
begin
  if not TFile.Exists(AFilePath) then
    raise EOperationException.CreateFmt('Workflow file not found: %s', [AFilePath]);
    
  JSON := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
  Result := LoadWorkflowFromJSON(JSON);
end;

function TDeepFlowEngine.LoadWorkflowFromJSON(const AJSON: string): string;
var
  Workflow: TWorkflowDefinition;
  JSONObj: TJSONObject;
begin
  EnsureInitialized;
  
  JSONObj := TJSONObject.ParseJSONValue(AJSON) as TJSONObject;
  if JSONObj = nil then
    raise EOperationException.Create('Invalid workflow JSON');
    
  try
    Workflow := TWorkflowDefinition.Create;
    try
      Workflow.LoadFromJSON(JSONObj);
      
      // 注册到内部字�?
      FLock.Enter;
      try
        if FWorkflows.ContainsKey(Workflow.Id) then
          FWorkflows.Remove(Workflow.Id);
        FWorkflows.Add(Workflow.Id, Workflow);
      finally
        FLock.Leave;
      end;
      
      // 注册�?Commander 工作流注册表
      FWorkflowRegistry.RegisterWorkflow(Workflow);
      
      Result := Workflow.Id;
    except
      Workflow.Free;
      raise;
    end;
  finally
    JSONObj.Free;
  end;
end;

function TDeepFlowEngine.GetWorkflow(const AWorkflowId: string): TWorkflowDefinition;
begin
  FLock.Enter;
  try
    if not FWorkflows.TryGetValue(AWorkflowId, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TDeepFlowEngine.GetWorkflowIds: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FWorkflows.Keys.ToArray;
  finally
    FLock.Leave;
  end;
end;

procedure TDeepFlowEngine.RegisterRoute(const AIntentName, AWorkflowId: string);
begin
  EnsureInitialized;
  FCommander.RegisterRoute(AIntentName, AWorkflowId);
end;

procedure TDeepFlowEngine.RegisterIntent(const AIntentName: string;
  const APatterns, AKeywords: TArray<string>; APriority: Integer);
begin
  EnsureInitialized;
  FCommander.IntentRecognizer.RegisterIntent(AIntentName, APatterns, AKeywords, APriority);
end;

function TDeepFlowEngine.ProcessRequest(const ASessionId, AMessage: string;
  const AUserId: string): TCommanderResponse;
var
  Request: TUserRequest;
begin
  EnsureInitialized;
  
  Request := TUserRequest.Create;
  try
    Request.SessionId := ASessionId;
    Request.Message := AMessage;
    Request.UserId := AUserId;
    Request.Timestamp := Now;
    
    Result := ProcessRequestObj(Request);
  finally
    Request.Free;
  end;
end;

function TDeepFlowEngine.ProcessRequestObj(ARequest: TUserRequest): TCommanderResponse;
begin
  EnsureInitialized;
  
  // 记录审计
  if FConfig.EnableAudit then
    AuditManager.LogSession(aaSessionCreated, ARequest.SessionId, ARequest.UserId,
      Format('Processing request: %s', [Copy(ARequest.Message, 1, 100)]));
  
  try
    Result := FCommander.ProcessRequest(ARequest);
    
    // 记录成功
    if FConfig.EnableAudit and (Result.Status = rsSuccess) then
      AuditManager.LogWorkflow(aaWorkflowCompleted, '', '', 'Request processed successfully');
  except
    on E: Exception do
    begin
      DoError('PROCESS_ERROR', E.Message);
      
      if FConfig.EnableAudit then
        AuditManager.LogError(Format('ProcessRequest failed: %s', [E.Message]));
      
      Result := TCommanderResponse.Error('PROCESS_ERROR', E.Message);
    end;
  end;
end;

function TDeepFlowEngine.CreateExecutor(const AWorkflowId: string;
  ASession: TSession): TWorkflowExecutor;
var
  Workflow: TWorkflowDefinition;
  Context: TWorkflowContext;
begin
  Workflow := GetWorkflow(AWorkflowId);
  if Workflow = nil then
    raise EOperationException.CreateFmt('Workflow not found: %s', [AWorkflowId]);
    
  Context := TWorkflowContext.Create(AWorkflowId, TGUID.NewGuid.ToString);
  
  // 从会话复制变量
  if ASession <> nil then
  begin
    var Vars := ASession.Variables;
    for var Key in Vars.Keys.ToArray do
      Context.SetVariable(Key, Vars[Key]);
  end;
  
  Result := TWorkflowExecutor.Create(Workflow, Context);
  
  // 注册内置执行�?
  Result.RegisterActionExecutor(TLogActionExecutor.Create);
  Result.RegisterActionExecutor(TAssignActionExecutor.Create);
  Result.RegisterActionExecutor(TGuardActionExecutor.Create);
  
  // 注册 Skill 执行器
  if FSkillClient <> nil then
    Result.RegisterActionExecutor(
      DeepFlow.Workflow.Executor.TSkillActionExecutor.Create(FSkillClient.Config.BaseURL));
end;

function TDeepFlowEngine.ExecuteWorkflow(const AWorkflowId, ASessionId: string;
  AInput: TJSONObject): TStepResult;
var
  Session: TSession;
  Executor: TWorkflowExecutor;
begin
  EnsureInitialized;
  
  Session := GetOrCreateSession(ASessionId);
  Executor := CreateExecutor(AWorkflowId, Session);
  try
    // 设置输入变量
    if AInput <> nil then
    begin
      for var Pair in AInput do
        Executor.Context.SetVariable('input.' + Pair.JsonString.Value,
          Pair.JsonValue.Value);
    end;
    
    DoWorkflowStart(AWorkflowId, ASessionId);
    
    // 执行
    Result := Executor.Start;
    
    // 保存输出到会�?
    if Result.Success and (Result.Output <> nil) then
      Session.SetVariable('last_output', Result.Output.ToJSON);
    
    FSessionManager.SaveSession(Session);
    
    DoWorkflowComplete(AWorkflowId, Result.Success);
  finally
    Executor.Free;
  end;
end;

function TDeepFlowEngine.GetOrCreateSession(const ASessionId: string;
  const AUserId: string): TSession;
begin
  EnsureInitialized;
  Result := FSessionManager.GetOrCreateSession(ASessionId, AUserId);
end;

function TDeepFlowEngine.GetDiagnostics: TDeepFlowDiagnostics;
begin
  Result := FDiagnostics;
end;

function TDeepFlowEngine.CreateDebugger(const AWorkflowId, ASessionId: string): TWorkflowDebugger;
var
  Workflow: TWorkflowDefinition;
  Session: TSession;
  Executor: TWorkflowExecutor;
begin
  EnsureInitialized;
  
  Workflow := GetWorkflow(AWorkflowId);
  if Workflow = nil then
    raise EOperationException.CreateFmt('Workflow not found: %s', [AWorkflowId]);
    
  Session := GetOrCreateSession(ASessionId);
  Executor := CreateExecutor(AWorkflowId, Session);
  
  Result := TWorkflowDebugger.Create(TDebuggerConfig.Default);
end;

function TDeepFlowEngine.ExportTrace(const ACorrelationId: string): string;
var
  Exporter: TTraceExporter;
begin
  if FDiagnostics = nil then
    Exit('Diagnostics not enabled');
    
  Exporter := CreateTraceExporter;
  try
    Result := Exporter.GenerateTimelineReport(FDiagnostics.TraceEntries);
  finally
    Exporter.Free;
  end;
end;

procedure TDeepFlowEngine.DoWorkflowStart(const AWorkflowId, ASessionId: string);
begin
  if Assigned(FOnWorkflowStart) then
    FOnWorkflowStart(Self, AWorkflowId, ASessionId);
    
  if FConfig.EnableMetrics then
    Metrics.WorkflowStarted(AWorkflowId);
end;

procedure TDeepFlowEngine.DoWorkflowComplete(const AWorkflowId: string; ASuccess: Boolean);
begin
  if Assigned(FOnWorkflowComplete) then
    FOnWorkflowComplete(Self, AWorkflowId, ASuccess);
    
  if FConfig.EnableMetrics then
  begin
    if ASuccess then
      Metrics.WorkflowCompleted(AWorkflowId, 0)  // TODO: duration
    else
      Metrics.WorkflowFailed(AWorkflowId, 'unknown');
  end;
end;

procedure TDeepFlowEngine.DoStepExecute(const AWorkflowId, AStepId: string);
begin
  if Assigned(FOnStepExecute) then
    FOnStepExecute(Self, AWorkflowId, AStepId);
end;

procedure TDeepFlowEngine.DoError(const AErrorCode, AErrorMessage: string);
begin
  if Assigned(FOnError) then
    FOnError(Self, AErrorCode, AErrorMessage);
end;

initialization
  GEngineLock := TCriticalSection.Create;

finalization
  FinalizeDeepFlow;

end.
