unit UniFlow.Diagnostics.Integration;
(*
  UniFlow Diagnostics Integration
  ===============================
  诊断集成助手，提�?HTTP/LLM/Skill 调用的简化跟踪接口�?
*)

interface

uses
  System.SysUtils, System.Classes, System.DateUtils, System.JSON, 
  UniFlow.Diagnostics;

type
  // ============================================================================
  // 工作流诊断包装器 - 简化集�?
  // ============================================================================
  
  TWorkflowDiagnostics = class
  private
    FDiagnostics: TUniFlowDiagnostics;
    FWorkflowId: string;
    FWorkflowName: string;
    FCorrelationId: string;
    FOwnsCorrelation: Boolean;
  public
    constructor Create(const AWorkflowId, AWorkflowName: string; 
      const ACorrelationId: string = '');
    destructor Destroy; override;
    
    // 步骤追踪
    procedure StepBegin(const StepId, StepType: string; Input: TJSONObject = nil);
    procedure StepEnd(const StepId: string; Output: TJSONObject = nil);
    procedure StepError(const StepId, ErrorMsg: string; E: Exception = nil);
    
    // 日志快捷方法
    procedure LogDebug(const Msg: string); overload;
    procedure LogDebug(const Msg: string; const Args: array of const); overload;
    procedure LogInfo(const Msg: string); overload;
    procedure LogInfo(const Msg: string; const Args: array of const); overload;
    procedure LogWarning(const Msg: string); overload;
    procedure LogWarning(const Msg: string; const Args: array of const); overload;
    procedure LogError(const Msg: string); overload;
    procedure LogError(const Msg: string; const Args: array of const); overload;
    
    // 错误上下�?
    function CaptureError(const StepId: string; E: Exception;
      Variables, InputData: TJSONObject): TErrorContext;
    
    // 属�?
    property CorrelationId: string read FCorrelationId;
    property WorkflowId: string read FWorkflowId;
    property WorkflowName: string read FWorkflowName;
  end;

  // ============================================================================
  // HTTP 请求诊断助手
  // ============================================================================
  
  THTTPDiagnostics = class
  private
    FDiagnostics: TUniFlowDiagnostics;
    FCorrelationId: string;
  public
    constructor Create(const ACorrelationId: string = '');
    
    // 添加追踪头到 HTTP 请求
    procedure AddTraceHeaders(Headers: TStrings);
    
    // �?HTTP 请求头提�?CorrelationId
    class function ExtractCorrelationId(Headers: TStrings): string;
    
    // 日志 HTTP 请求/响应
    procedure LogRequest(const Method, URL: string; Headers: TStrings = nil);
    procedure LogResponse(StatusCode: Integer; const Body: string = '');
    procedure LogError(const ErrorMsg: string);
    
    property CorrelationId: string read FCorrelationId;
  end;

  // ============================================================================
  // LLM 调用诊断助手
  // ============================================================================
  
  TLLMDiagnostics = class
  private
    FDiagnostics: TUniFlowDiagnostics;
    FCorrelationId: string;
    FStartTime: TDateTime;
    FProvider: string;
    FModel: string;
  public
    constructor Create(const ACorrelationId, AProvider, AModel: string);
    
    procedure LogRequest(const Prompt: string; TokenCount: Integer = 0);
    procedure LogResponse(const Response: string; TokenCount: Integer = 0; 
      DurationMs: Int64 = 0);
    procedure LogError(const ErrorMsg: string);
    procedure LogTokenUsage(InputTokens, OutputTokens: Integer; Cost: Double = 0);
    
    property CorrelationId: string read FCorrelationId;
    property Provider: string read FProvider;
    property Model: string read FModel;
  end;

  // ============================================================================
  // Skill 调用诊断助手
  // ============================================================================
  
  TSkillDiagnostics = class
  private
    FDiagnostics: TUniFlowDiagnostics;
    FCorrelationId: string;
    FSkillName: string;
    FStartTime: TDateTime;
  public
    constructor Create(const ACorrelationId, ASkillName: string);
    
    procedure LogInvoke(Params: TJSONObject);
    procedure LogResult(Result: TJSONObject; DurationMs: Int64 = 0);
    procedure LogError(const ErrorMsg: string);
    
    property CorrelationId: string read FCorrelationId;
    property SkillName: string read FSkillName;
  end;

// ============================================================================
// 便捷函数
// ============================================================================

// 创建带追踪的工作流诊�?
function CreateWorkflowDiagnostics(const WorkflowId, WorkflowName: string;
  const CorrelationId: string = ''): TWorkflowDiagnostics;

// HTTP 追踪头常�?
const
  HEADER_CORRELATION_ID = 'X-Correlation-ID';
  HEADER_WORKFLOW_ID = 'X-Workflow-ID';
  HEADER_STEP_ID = 'X-Step-ID';
  HEADER_TRACE_ID = 'X-Trace-ID';

implementation

// ============================================================================
// TWorkflowDiagnostics
// ============================================================================

constructor TWorkflowDiagnostics.Create(const AWorkflowId, AWorkflowName: string;
  const ACorrelationId: string);
begin
  inherited Create;
  FDiagnostics := Diagnostics;
  FWorkflowId := AWorkflowId;
  FWorkflowName := AWorkflowName;
  
  // 如果没有传入 CorrelationId，创建新�?
  if ACorrelationId = '' then
  begin
    FDiagnostics.BeginCorrelation;
    FCorrelationId := FDiagnostics.CorrelationId;
    FOwnsCorrelation := True;
  end
  else
  begin
    // 使用已有�?CorrelationId（跨服务调用场景�?
    FDiagnostics.BeginCorrelation(ACorrelationId);
    FCorrelationId := ACorrelationId;
    FOwnsCorrelation := True;
  end;
  
  FDiagnostics.SetWorkflowContext(AWorkflowId);
  FDiagnostics.Info('Workflow', 'Workflow [%s] (%s) started', [AWorkflowName, AWorkflowId]);
end;

destructor TWorkflowDiagnostics.Destroy;
begin
  if FOwnsCorrelation then
  begin
    FDiagnostics.Info('Workflow', 'Workflow [%s] (%s) ended', [FWorkflowName, FWorkflowId]);
    FDiagnostics.EndCorrelation;
  end;
  inherited;
end;

procedure TWorkflowDiagnostics.StepBegin(const StepId, StepType: string; Input: TJSONObject);
begin
  FDiagnostics.TraceStepEnter(StepId, StepType, Input);
end;

procedure TWorkflowDiagnostics.StepEnd(const StepId: string; Output: TJSONObject);
begin
  FDiagnostics.TraceStepExit(StepId, Output);
end;

procedure TWorkflowDiagnostics.StepError(const StepId, ErrorMsg: string; E: Exception);
var
  FullMsg: string;
begin
  if Assigned(E) then
    FullMsg := Format('%s: %s', [E.ClassName, ErrorMsg])
  else
    FullMsg := ErrorMsg;
  FDiagnostics.TraceStepError(StepId, FullMsg);
end;

procedure TWorkflowDiagnostics.LogDebug(const Msg: string);
begin
  FDiagnostics.Debug('Workflow', Msg);
end;

procedure TWorkflowDiagnostics.LogDebug(const Msg: string; const Args: array of const);
begin
  FDiagnostics.Debug('Workflow', Msg, Args);
end;

procedure TWorkflowDiagnostics.LogInfo(const Msg: string);
begin
  FDiagnostics.Info('Workflow', Msg);
end;

procedure TWorkflowDiagnostics.LogInfo(const Msg: string; const Args: array of const);
begin
  FDiagnostics.Info('Workflow', Msg, Args);
end;

procedure TWorkflowDiagnostics.LogWarning(const Msg: string);
begin
  FDiagnostics.Warning('Workflow', Msg);
end;

procedure TWorkflowDiagnostics.LogWarning(const Msg: string; const Args: array of const);
begin
  FDiagnostics.Warning('Workflow', Msg, Args);
end;

procedure TWorkflowDiagnostics.LogError(const Msg: string);
begin
  FDiagnostics.Error('Workflow', Msg);
end;

procedure TWorkflowDiagnostics.LogError(const Msg: string; const Args: array of const);
begin
  FDiagnostics.Error('Workflow', Msg, Args);
end;

function TWorkflowDiagnostics.CaptureError(const StepId: string; E: Exception;
  Variables, InputData: TJSONObject): TErrorContext;
begin
  Result := FDiagnostics.CaptureErrorContext(
    StepId, 
    E.Message, 
    E.ClassName,
    Variables, 
    InputData
  );
end;

// ============================================================================
// THTTPDiagnostics
// ============================================================================

constructor THTTPDiagnostics.Create(const ACorrelationId: string);
begin
  inherited Create;
  FDiagnostics := Diagnostics;
  
  if ACorrelationId = '' then
    FCorrelationId := FDiagnostics.CorrelationId
  else
    FCorrelationId := ACorrelationId;
end;

procedure THTTPDiagnostics.AddTraceHeaders(Headers: TStrings);
begin
  if FCorrelationId <> '' then
    Headers.Values[HEADER_CORRELATION_ID] := FCorrelationId;
  
  if FDiagnostics.CorrelationId <> '' then
    Headers.Values[HEADER_TRACE_ID] := FDiagnostics.CorrelationId;
end;

class function THTTPDiagnostics.ExtractCorrelationId(Headers: TStrings): string;
begin
  Result := Headers.Values[HEADER_CORRELATION_ID];
  if Result = '' then
    Result := Headers.Values[HEADER_TRACE_ID];
end;

procedure THTTPDiagnostics.LogRequest(const Method, URL: string; Headers: TStrings);
begin
  FDiagnostics.Debug('HTTP', '%s %s', [Method, URL]);
end;

procedure THTTPDiagnostics.LogResponse(StatusCode: Integer; const Body: string);
begin
  if StatusCode >= 400 then
    FDiagnostics.Warning('HTTP', 'Response: %d', [StatusCode])
  else
    FDiagnostics.Debug('HTTP', 'Response: %d', [StatusCode]);
end;

procedure THTTPDiagnostics.LogError(const ErrorMsg: string);
begin
  FDiagnostics.Error('HTTP', ErrorMsg);
end;

// ============================================================================
// TLLMDiagnostics
// ============================================================================

constructor TLLMDiagnostics.Create(const ACorrelationId, AProvider, AModel: string);
begin
  inherited Create;
  FDiagnostics := Diagnostics;
  FCorrelationId := ACorrelationId;
  FProvider := AProvider;
  FModel := AModel;
  FStartTime := Now;
end;

procedure TLLMDiagnostics.LogRequest(const Prompt: string; TokenCount: Integer);
begin
  FStartTime := Now;
  if TokenCount > 0 then
    FDiagnostics.Debug('LLM', '[%s/%s] Request (%d tokens)', [FProvider, FModel, TokenCount])
  else
    FDiagnostics.Debug('LLM', '[%s/%s] Request', [FProvider, FModel]);
end;

procedure TLLMDiagnostics.LogResponse(const Response: string; TokenCount: Integer;
  DurationMs: Int64);
var
  ActualDuration: Int64;
begin
  if DurationMs > 0 then
    ActualDuration := DurationMs
  else
    ActualDuration := MilliSecondsBetween(Now, FStartTime);
  
  if TokenCount > 0 then
    FDiagnostics.Info('LLM', '[%s/%s] Response (%d tokens, %dms)', 
      [FProvider, FModel, TokenCount, ActualDuration])
  else
    FDiagnostics.Info('LLM', '[%s/%s] Response (%dms)', 
      [FProvider, FModel, ActualDuration]);
end;

procedure TLLMDiagnostics.LogError(const ErrorMsg: string);
begin
  FDiagnostics.Error('LLM', '[%s/%s] Error: %s', [FProvider, FModel, ErrorMsg]);
end;

procedure TLLMDiagnostics.LogTokenUsage(InputTokens, OutputTokens: Integer; Cost: Double);
begin
  if Cost > 0 then
    FDiagnostics.Info('LLM', '[%s/%s] Tokens: in=%d out=%d cost=$%.4f',
      [FProvider, FModel, InputTokens, OutputTokens, Cost])
  else
    FDiagnostics.Info('LLM', '[%s/%s] Tokens: in=%d out=%d',
      [FProvider, FModel, InputTokens, OutputTokens]);
end;

// ============================================================================
// TSkillDiagnostics
// ============================================================================

constructor TSkillDiagnostics.Create(const ACorrelationId, ASkillName: string);
begin
  inherited Create;
  FDiagnostics := Diagnostics;
  FCorrelationId := ACorrelationId;
  FSkillName := ASkillName;
  FStartTime := Now;
end;

procedure TSkillDiagnostics.LogInvoke(Params: TJSONObject);
begin
  FStartTime := Now;
  FDiagnostics.Debug('Skill', '[%s] Invoking', [FSkillName]);
end;

procedure TSkillDiagnostics.LogResult(Result: TJSONObject; DurationMs: Int64);
var
  ActualDuration: Int64;
begin
  if DurationMs > 0 then
    ActualDuration := DurationMs
  else
    ActualDuration := MilliSecondsBetween(Now, FStartTime);
  
  FDiagnostics.Info('Skill', '[%s] Completed (%dms)', [FSkillName, ActualDuration]);
end;

procedure TSkillDiagnostics.LogError(const ErrorMsg: string);
begin
  FDiagnostics.Error('Skill', '[%s] Error: %s', [FSkillName, ErrorMsg]);
end;

// ============================================================================
// 便捷函数
// ============================================================================

function CreateWorkflowDiagnostics(const WorkflowId, WorkflowName: string;
  const CorrelationId: string): TWorkflowDiagnostics;
begin
  Result := TWorkflowDiagnostics.Create(WorkflowId, WorkflowName, CorrelationId);
end;

end.
