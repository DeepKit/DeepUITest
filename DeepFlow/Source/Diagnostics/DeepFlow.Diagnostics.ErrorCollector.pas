unit UniFlow.Diagnostics.ErrorCollector;
(*
  UniFlow Diagnostics Error Collector
  ===================================
  增强的错误收集器，包含错误分类、上下文收集、智能建议等功能�?
*)

interface

uses
  System.SysUtils, System.Classes, System.DateUtils, System.SyncObjs, 
  System.Generics.Collections, System.JSON, Winapi.Windows,
  UniFlow.Diagnostics;

type
  // ============================================================================
  // 错误严重级别
  // ============================================================================
  
  TErrorSeverity = (
    esWarning,    // 警告，可继续
    esError,      // 错误，步骤失�?
    esCritical,   // 严重，工作流失败
    esFatal       // 致命，系统级错误
  );

  // ============================================================================
  // 错误分类
  // ============================================================================
  
  TErrorCategory = (
    ecUnknown,        // 未知
    ecValidation,     // 输入验证
    ecConfiguration,  // 配置错误
    ecNetwork,        // 网络错误
    ecTimeout,        // 超时
    ecAuthentication, // 认证失败
    ecAuthorization,  // 授权失败
    ecRateLimit,      // 限流
    ecLLM,            // LLM 调用错误
    ecSkill,          // Skill 调用错误
    ecScript,         // 脚本执行错误
    ecData,           // 数据错误
    ecInternal        // 内部错误
  );

  // ============================================================================
  // 增强的错误上下文
  // ============================================================================
  
  TEnhancedErrorContext = record
    // 基本信息
    Id: string;
    Timestamp: TDateTime;
    Severity: TErrorSeverity;
    Category: TErrorCategory;
    
    // 追踪信息
    CorrelationId: string;
    WorkflowId: string;
    WorkflowName: string;
    StepId: string;
    StepType: string;
    StepIndex: Integer;
    
    // 错误详情
    ErrorCode: string;
    ErrorMessage: string;
    ErrorClass: string;
    InnerError: string;
    StackTrace: string;
    
    // 上下文数�?
    Variables: TJSONObject;
    InputData: TJSONObject;
    OutputData: TJSONObject;
    StepConfig: TJSONObject;
    
    // 执行路径
    ExecutedSteps: TStringArray;
    FailedAttempt: Integer;
    MaxRetries: Integer;
    
    // 环境信息
    MachineName: string;
    ProcessId: Integer;
    ThreadId: Integer;
    MemoryUsage: Int64;
    
    // 建议
    Suggestion: string;
    DocumentationUrl: string;
    
    function ToJSON: TJSONObject;
    function ToString: string;
    function ToMarkdown: string;
  end;
  
  TEnhancedErrorContextArray = array of TEnhancedErrorContext;

  // ============================================================================
  // 错误收集器配�?
  // ============================================================================
  
  TErrorCollectorConfig = record
    MaxErrors: Integer;
    CaptureVariables: Boolean;
    CaptureStackTrace: Boolean;
    CaptureEnvironment: Boolean;
    AutoSuggest: Boolean;
    RetentionHours: Integer;
    
    class function Default: TErrorCollectorConfig; static;
  end;

  // ============================================================================
  // 错误收集�?
  // ============================================================================
  
  TErrorCollectorEvent = procedure(const Error: TEnhancedErrorContext) of object;

  TErrorCollector = class
  private
    FConfig: TErrorCollectorConfig;
    FErrors: TEnhancedErrorContextArray;
    FErrorIndex: Integer;
    FLock: TCriticalSection;
    FOnError: TErrorCollectorEvent;
    
    procedure AddError(const Error: TEnhancedErrorContext);
    function GetErrorCount: Integer;
    function GetErrors: TEnhancedErrorContextArray;
    function GenerateSuggestion(Category: TErrorCategory; const ErrorMsg: string): string;
    function CategorizeError(const ErrorClass, ErrorMsg: string): TErrorCategory;
  public
    constructor Create(const AConfig: TErrorCollectorConfig);
    destructor Destroy; override;
    
    // 收集错误
    function Collect(
      const CorrelationId, WorkflowId, WorkflowName, StepId, StepType: string;
      const ErrorMsg, ErrorClass: string;
      Severity: TErrorSeverity;
      Variables, InputData: TJSONObject;
      const ExecutedSteps: TStringArray
    ): TEnhancedErrorContext;
    
    // 从异常收�?
    function CollectFromException(
      const CorrelationId, WorkflowId, WorkflowName, StepId, StepType: string;
      E: Exception;
      Variables, InputData: TJSONObject;
      const ExecutedSteps: TStringArray
    ): TEnhancedErrorContext;
    
    // 查询错误
    function GetRecentErrors(Count: Integer = 10): TEnhancedErrorContextArray;
    function GetErrorsByCorrelation(const CorrelationId: string): TEnhancedErrorContextArray;
    function GetErrorsByWorkflow(const WorkflowId: string): TEnhancedErrorContextArray;
    function GetErrorsByCategory(Category: TErrorCategory): TEnhancedErrorContextArray;
    function GetErrorsBySeverity(Severity: TErrorSeverity): TEnhancedErrorContextArray;
    
    // 导出
    function ExportToJSON: string;
    function ExportToMarkdown: string;
    function ExportToCSV: string;
    
    // 清理
    procedure Clear;
    procedure ClearOlderThan(Hours: Integer);
    
    // 属�?
    property Config: TErrorCollectorConfig read FConfig write FConfig;
    property ErrorCount: Integer read GetErrorCount;
    property Errors: TEnhancedErrorContextArray read GetErrors;
    property OnError: TErrorCollectorEvent read FOnError write FOnError;
  end;

// ============================================================================
// 辅助函数
// ============================================================================

function ErrorSeverityToString(Severity: TErrorSeverity): string;
function ErrorCategoryToString(Category: TErrorCategory): string;
function StringToErrorSeverity(const S: string): TErrorSeverity;
function StringToErrorCategory(const S: string): TErrorCategory;

// 全局错误收集�?
function ErrorCollector: TErrorCollector;
procedure InitializeErrorCollector(const AConfig: TErrorCollectorConfig);

implementation

var
  GErrorCollector: TErrorCollector = nil;
  GErrorCollectorLock: TCriticalSection = nil;

// ============================================================================
// 辅助函数实现
// ============================================================================

function ErrorSeverityToString(Severity: TErrorSeverity): string;
begin
  case Severity of
    esWarning:  Result := 'WARNING';
    esError:    Result := 'ERROR';
    esCritical: Result := 'CRITICAL';
    esFatal:    Result := 'FATAL';
  else
    Result := 'UNKNOWN';
  end;
end;

function ErrorCategoryToString(Category: TErrorCategory): string;
begin
  case Category of
    ecUnknown:        Result := 'Unknown';
    ecValidation:     Result := 'Validation';
    ecConfiguration:  Result := 'Configuration';
    ecNetwork:        Result := 'Network';
    ecTimeout:        Result := 'Timeout';
    ecAuthentication: Result := 'Authentication';
    ecAuthorization:  Result := 'Authorization';
    ecRateLimit:      Result := 'RateLimit';
    ecLLM:            Result := 'LLM';
    ecSkill:          Result := 'Skill';
    ecScript:         Result := 'Script';
    ecData:           Result := 'Data';
    ecInternal:       Result := 'Internal';
  else
    Result := 'Unknown';
  end;
end;

function StringToErrorSeverity(const S: string): TErrorSeverity;
begin
  if SameText(S, 'WARNING') then Result := esWarning
  else if SameText(S, 'ERROR') then Result := esError
  else if SameText(S, 'CRITICAL') then Result := esCritical
  else if SameText(S, 'FATAL') then Result := esFatal
  else Result := esError;
end;

function StringToErrorCategory(const S: string): TErrorCategory;
begin
  if SameText(S, 'Validation') then Result := ecValidation
  else if SameText(S, 'Configuration') then Result := ecConfiguration
  else if SameText(S, 'Network') then Result := ecNetwork
  else if SameText(S, 'Timeout') then Result := ecTimeout
  else if SameText(S, 'Authentication') then Result := ecAuthentication
  else if SameText(S, 'Authorization') then Result := ecAuthorization
  else if SameText(S, 'RateLimit') then Result := ecRateLimit
  else if SameText(S, 'LLM') then Result := ecLLM
  else if SameText(S, 'Skill') then Result := ecSkill
  else if SameText(S, 'Script') then Result := ecScript
  else if SameText(S, 'Data') then Result := ecData
  else if SameText(S, 'Internal') then Result := ecInternal
  else Result := ecUnknown;
end;

function GenerateErrorId: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := 'ERR-' + Copy(GUIDToString(G), 2, 8);
end;

// ============================================================================
// TEnhancedErrorContext
// ============================================================================

function TEnhancedErrorContext.ToJSON: TJSONObject;
var
  StepsArr: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  
  // 基本信息
  Result.AddPair('id', Id);
  Result.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Timestamp));
  Result.AddPair('severity', ErrorSeverityToString(Severity));
  Result.AddPair('category', ErrorCategoryToString(Category));
  
  // 追踪信息
  Result.AddPair('correlationId', CorrelationId);
  Result.AddPair('workflowId', WorkflowId);
  Result.AddPair('workflowName', WorkflowName);
  Result.AddPair('stepId', StepId);
  Result.AddPair('stepType', StepType);
  Result.AddPair('stepIndex', TJSONNumber.Create(StepIndex));
  
  // 错误详情
  if ErrorCode <> '' then Result.AddPair('errorCode', ErrorCode);
  Result.AddPair('errorMessage', ErrorMessage);
  Result.AddPair('errorClass', ErrorClass);
  if InnerError <> '' then Result.AddPair('innerError', InnerError);
  if StackTrace <> '' then Result.AddPair('stackTrace', StackTrace);
  
  // 上下文数�?
  if Assigned(Variables) then Result.AddPair('variables', Variables.Clone as TJSONObject);
  if Assigned(InputData) then Result.AddPair('inputData', InputData.Clone as TJSONObject);
  if Assigned(OutputData) then Result.AddPair('outputData', OutputData.Clone as TJSONObject);
  if Assigned(StepConfig) then Result.AddPair('stepConfig', StepConfig.Clone as TJSONObject);
  
  // 执行路径
  if Length(ExecutedSteps) > 0 then
  begin
    StepsArr := TJSONArray.Create;
    for I := 0 to High(ExecutedSteps) do
      StepsArr.Add(ExecutedSteps[I]);
    Result.AddPair('executedSteps', StepsArr as TJSONValue);
  end;
  
  if FailedAttempt > 0 then
  begin
    Result.AddPair('failedAttempt', TJSONNumber.Create(FailedAttempt));
    Result.AddPair('maxRetries', TJSONNumber.Create(MaxRetries));
  end;
  
  // 环境信息
  if MachineName <> '' then Result.AddPair('machineName', MachineName);
  if ProcessId > 0 then Result.AddPair('processId', TJSONNumber.Create(ProcessId));
  if ThreadId > 0 then Result.AddPair('threadId', TJSONNumber.Create(ThreadId));
  if MemoryUsage > 0 then Result.AddPair('memoryUsage', TJSONNumber.Create(MemoryUsage));
  
  // 建议
  if Suggestion <> '' then Result.AddPair('suggestion', Suggestion);
  if DocumentationUrl <> '' then Result.AddPair('documentationUrl', DocumentationUrl);
end;

function TEnhancedErrorContext.ToString: string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('╔══════════════════════════════════════════════════════════════╗');
    SB.AppendLine('�?                     ERROR REPORT                            �?);
    SB.AppendLine('╠══════════════════════════════════════════════════════════════╣');
    SB.AppendFormat('�?ID:            %s', [Id]).AppendLine;
    SB.AppendFormat('�?Time:          %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Timestamp)]).AppendLine;
    SB.AppendFormat('�?Severity:      %s', [ErrorSeverityToString(Severity)]).AppendLine;
    SB.AppendFormat('�?Category:      %s', [ErrorCategoryToString(Category)]).AppendLine;
    SB.AppendLine('╠══════════════════════════════════════════════════════════════╣');
    SB.AppendFormat('�?Correlation:   %s', [CorrelationId]).AppendLine;
    SB.AppendFormat('�?Workflow:      %s (%s)', [WorkflowName, WorkflowId]).AppendLine;
    SB.AppendFormat('�?Step:          %s [%s] (#%d)', [StepId, StepType, StepIndex]).AppendLine;
    SB.AppendLine('╠══════════════════════════════════════════════════════════════╣');
    SB.AppendFormat('�?Error:         %s', [ErrorMessage]).AppendLine;
    SB.AppendFormat('�?Exception:     %s', [ErrorClass]).AppendLine;
    
    if InnerError <> '' then
      SB.AppendFormat('�?Inner:         %s', [InnerError]).AppendLine;
    
    if Length(ExecutedSteps) > 0 then
    begin
      SB.AppendLine('╠══════════════════════════════════════════════════════════════╣');
      SB.AppendLine('�?Execution Path:');
      for I := 0 to High(ExecutedSteps) do
        SB.AppendFormat('�?  %d. %s', [I + 1, ExecutedSteps[I]]).AppendLine;
    end;
    
    if Suggestion <> '' then
    begin
      SB.AppendLine('╠══════════════════════════════════════════════════════════════╣');
      SB.AppendFormat('�?Suggestion:    %s', [Suggestion]).AppendLine;
    end;
    
    if StackTrace <> '' then
    begin
      SB.AppendLine('╠══════════════════════════════════════════════════════════════╣');
      SB.AppendLine('�?Stack Trace:');
      SB.AppendLine(StackTrace);
    end;
    
    SB.AppendLine('╚══════════════════════════════════════════════════════════════╝');
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TEnhancedErrorContext.ToMarkdown: string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendFormat('## Error: %s', [Id]).AppendLine;
    SB.AppendLine;
    SB.AppendFormat('**Time:** %s  ', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Timestamp)]).AppendLine;
    SB.AppendFormat('**Severity:** `%s`  ', [ErrorSeverityToString(Severity)]).AppendLine;
    SB.AppendFormat('**Category:** `%s`', [ErrorCategoryToString(Category)]).AppendLine;
    SB.AppendLine;
    SB.AppendLine('### Context');
    SB.AppendFormat('- **Correlation ID:** `%s`', [CorrelationId]).AppendLine;
    SB.AppendFormat('- **Workflow:** %s (`%s`)', [WorkflowName, WorkflowId]).AppendLine;
    SB.AppendFormat('- **Step:** %s (`%s`)', [StepId, StepType]).AppendLine;
    SB.AppendLine;
    SB.AppendLine('### Error Details');
    SB.AppendLine('```');
    SB.AppendFormat('%s: %s', [ErrorClass, ErrorMessage]).AppendLine;
    SB.AppendLine('```');
    
    if Length(ExecutedSteps) > 0 then
    begin
      SB.AppendLine;
      SB.AppendLine('### Execution Path');
      for I := 0 to High(ExecutedSteps) do
        SB.AppendFormat('%d. `%s`', [I + 1, ExecutedSteps[I]]).AppendLine;
    end;
    
    if Suggestion <> '' then
    begin
      SB.AppendLine;
      SB.AppendLine('### Suggestion');
      SB.AppendFormat('> %s', [Suggestion]).AppendLine;
    end;
    
    if StackTrace <> '' then
    begin
      SB.AppendLine;
      SB.AppendLine('### Stack Trace');
      SB.AppendLine('```');
      SB.AppendLine(StackTrace);
      SB.AppendLine('```');
    end;
    
    SB.AppendLine;
    SB.AppendLine('---');
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// ============================================================================
// TErrorCollectorConfig
// ============================================================================

class function TErrorCollectorConfig.Default: TErrorCollectorConfig;
begin
  Result.MaxErrors := 500;
  Result.CaptureVariables := True;
  Result.CaptureStackTrace := True;
  Result.CaptureEnvironment := True;
  Result.AutoSuggest := True;
  Result.RetentionHours := 24;
end;

// ============================================================================
// TErrorCollector
// ============================================================================

constructor TErrorCollector.Create(const AConfig: TErrorCollectorConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FLock := TCriticalSection.Create;
  SetLength(FErrors, FConfig.MaxErrors);
  FErrorIndex := 0;
end;

destructor TErrorCollector.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TErrorCollector.AddError(const Error: TEnhancedErrorContext);
begin
  FLock.Enter;
  try
    FErrors[FErrorIndex mod FConfig.MaxErrors] := Error;
    Inc(FErrorIndex);
  finally
    FLock.Leave;
  end;
  
  // 触发事件
  if Assigned(FOnError) then
    FOnError(Error);
end;

function TErrorCollector.GetErrorCount: Integer;
begin
  FLock.Enter;
  try
    if FErrorIndex < FConfig.MaxErrors then
      Result := FErrorIndex
    else
      Result := FConfig.MaxErrors;
  finally
    FLock.Leave;
  end;
end;

function TErrorCollector.GetErrors: TEnhancedErrorContextArray;
var
  Count, I, Idx: Integer;
begin
  FLock.Enter;
  try
    if FErrorIndex < FConfig.MaxErrors then
      Count := FErrorIndex
    else
      Count := FConfig.MaxErrors;
    
    SetLength(Result, Count);
    for I := 0 to Count - 1 do
    begin
      if FErrorIndex < FConfig.MaxErrors then
        Idx := I
      else
        Idx := (FErrorIndex + I) mod FConfig.MaxErrors;
      Result[I] := FErrors[Idx];
    end;
  finally
    FLock.Leave;
  end;
end;

function TErrorCollector.CategorizeError(const ErrorClass, ErrorMsg: string): TErrorCategory;
var
  LowerMsg: string;
begin
  LowerMsg := LowerCase(ErrorMsg);
  
  // 根据错误消息关键词分�?
  if Pos('timeout', LowerMsg) > 0 then
    Result := ecTimeout
  else if Pos('network', LowerMsg) > 0 then
    Result := ecNetwork
  else if Pos('connection', LowerMsg) > 0 then
    Result := ecNetwork
  else if Pos('authentication', LowerMsg) > 0 then
    Result := ecAuthentication
  else if Pos('unauthorized', LowerMsg) > 0 then
    Result := ecAuthentication
  else if Pos('forbidden', LowerMsg) > 0 then
    Result := ecAuthorization
  else if Pos('permission', LowerMsg) > 0 then
    Result := ecAuthorization
  else if Pos('rate limit', LowerMsg) > 0 then
    Result := ecRateLimit
  else if Pos('too many', LowerMsg) > 0 then
    Result := ecRateLimit
  else if Pos('validation', LowerMsg) > 0 then
    Result := ecValidation
  else if Pos('invalid', LowerMsg) > 0 then
    Result := ecValidation
  else if Pos('required', LowerMsg) > 0 then
    Result := ecValidation
  else if Pos('config', LowerMsg) > 0 then
    Result := ecConfiguration
  else if Pos('llm', LowerMsg) > 0 then
    Result := ecLLM
  else if Pos('openai', LowerMsg) > 0 then
    Result := ecLLM
  else if Pos('skill', LowerMsg) > 0 then
    Result := ecSkill
  else if Pos('script', LowerMsg) > 0 then
    Result := ecScript
  else if Pos('parse', LowerMsg) > 0 then
    Result := ecData
  else if Pos('json', LowerMsg) > 0 then
    Result := ecData
  else
    Result := ecUnknown;
end;

function TErrorCollector.GenerateSuggestion(Category: TErrorCategory; const ErrorMsg: string): string;
begin
  case Category of
    ecTimeout:
      Result := '检查网络连接，考虑增加超时时间或添加重试策�?;
    ecNetwork:
      Result := '检查网络连接和目标服务是否可用';
    ecAuthentication:
      Result := '检查认证凭据是否正确和有效';
    ecAuthorization:
      Result := '检查用户权限配�?;
    ecRateLimit:
      Result := '等待一段时间后重试，考虑减少请求频率';
    ecValidation:
      Result := '检查输入数据格式和必填字段';
    ecConfiguration:
      Result := '检查配置文件和环境变量';
    ecLLM:
      Result := '检�?LLM API 配置和配额，确认模型名称正确';
    ecSkill:
      Result := '检�?Skill 服务是否运行，确认技能名称正�?;
    ecScript:
      Result := '检查脚本语法和依赖';
    ecData:
      Result := '检查数据格式，确认 JSON 结构正确';
  else
    Result := '查看详细错误信息和堆栈跟�?;
  end;
end;

function TErrorCollector.Collect(
  const CorrelationId, WorkflowId, WorkflowName, StepId, StepType: string;
  const ErrorMsg, ErrorClass: string;
  Severity: TErrorSeverity;
  Variables, InputData: TJSONObject;
  const ExecutedSteps: TStringArray
): TEnhancedErrorContext;
begin
  Result.Id := GenerateErrorId;
  Result.Timestamp := Now;
  Result.Severity := Severity;
  Result.Category := CategorizeError(ErrorClass, ErrorMsg);
  
  Result.CorrelationId := CorrelationId;
  Result.WorkflowId := WorkflowId;
  Result.WorkflowName := WorkflowName;
  Result.StepId := StepId;
  Result.StepType := StepType;
  Result.StepIndex := Length(ExecutedSteps);
  
  Result.ErrorCode := '';
  Result.ErrorMessage := ErrorMsg;
  Result.ErrorClass := ErrorClass;
  Result.InnerError := '';
  
  if FConfig.CaptureStackTrace then
    Result.StackTrace := '' // Delphi: use madExcept or JclDebug for stack traces
  else
    Result.StackTrace := '';
  
  if FConfig.CaptureVariables and Assigned(Variables) then
    Result.Variables := Variables.Clone as TJSONObject
  else
    Result.Variables := nil;
  
  if FConfig.CaptureVariables and Assigned(InputData) then
    Result.InputData := InputData.Clone as TJSONObject
  else
    Result.InputData := nil;
  
  Result.OutputData := nil;
  Result.StepConfig := nil;
  Result.ExecutedSteps := ExecutedSteps;
  Result.FailedAttempt := 0;
  Result.MaxRetries := 0;
  
  if FConfig.CaptureEnvironment then
  begin
    Result.MachineName := GetEnvironmentVariable('COMPUTERNAME');
    Result.ProcessId := Winapi.Windows.GetCurrentProcessId;
    Result.ThreadId := TThread.CurrentThread.ThreadID;
    Result.MemoryUsage := 0; // Could add memory info
  end;
  
  if FConfig.AutoSuggest then
    Result.Suggestion := GenerateSuggestion(Result.Category, ErrorMsg)
  else
    Result.Suggestion := '';
  
  Result.DocumentationUrl := '';
  
  AddError(Result);
end;

function TErrorCollector.CollectFromException(
  const CorrelationId, WorkflowId, WorkflowName, StepId, StepType: string;
  E: Exception;
  Variables, InputData: TJSONObject;
  const ExecutedSteps: TStringArray
): TEnhancedErrorContext;
begin
  Result := Collect(
    CorrelationId, WorkflowId, WorkflowName, StepId, StepType,
    E.Message, E.ClassName, esError,
    Variables, InputData, ExecutedSteps
  );
end;

function TErrorCollector.GetRecentErrors(Count: Integer): TEnhancedErrorContextArray;
var
  All: TEnhancedErrorContextArray;
  StartIdx: Integer;
begin
  All := GetErrors;
  if Length(All) <= Count then
    Result := All
  else
  begin
    StartIdx := Length(All) - Count;
    SetLength(Result, Count);
    Move(All[StartIdx], Result[0], Count * SizeOf(TEnhancedErrorContext));
  end;
end;

function TErrorCollector.GetErrorsByCorrelation(const CorrelationId: string): TEnhancedErrorContextArray;
var
  All: TEnhancedErrorContextArray;
  I, Count: Integer;
begin
  All := GetErrors;
  SetLength(Result, Length(All));
  Count := 0;
  
  for I := 0 to High(All) do
  begin
    if All[I].CorrelationId = CorrelationId then
    begin
      Result[Count] := All[I];
      Inc(Count);
    end;
  end;
  
  SetLength(Result, Count);
end;

function TErrorCollector.GetErrorsByWorkflow(const WorkflowId: string): TEnhancedErrorContextArray;
var
  All: TEnhancedErrorContextArray;
  I, Count: Integer;
begin
  All := GetErrors;
  SetLength(Result, Length(All));
  Count := 0;
  
  for I := 0 to High(All) do
  begin
    if All[I].WorkflowId = WorkflowId then
    begin
      Result[Count] := All[I];
      Inc(Count);
    end;
  end;
  
  SetLength(Result, Count);
end;

function TErrorCollector.GetErrorsByCategory(Category: TErrorCategory): TEnhancedErrorContextArray;
var
  All: TEnhancedErrorContextArray;
  I, Count: Integer;
begin
  All := GetErrors;
  SetLength(Result, Length(All));
  Count := 0;
  
  for I := 0 to High(All) do
  begin
    if All[I].Category = Category then
    begin
      Result[Count] := All[I];
      Inc(Count);
    end;
  end;
  
  SetLength(Result, Count);
end;

function TErrorCollector.GetErrorsBySeverity(Severity: TErrorSeverity): TEnhancedErrorContextArray;
var
  All: TEnhancedErrorContextArray;
  I, Count: Integer;
begin
  All := GetErrors;
  SetLength(Result, Length(All));
  Count := 0;
  
  for I := 0 to High(All) do
  begin
    if All[I].Severity = Severity then
    begin
      Result[Count] := All[I];
      Inc(Count);
    end;
  end;
  
  SetLength(Result, Count);
end;

function TErrorCollector.ExportToJSON: string;
var
  Arr: TJSONArray;
  All: TEnhancedErrorContextArray;
  I: Integer;
begin
  Arr := TJSONArray.Create;
  try
    All := GetErrors;
    for I := 0 to High(All) do
      Arr.AddElement(All[I].ToJSON);
    Result := Arr.Format;
  finally
    Arr.Free;
  end;
end;

function TErrorCollector.ExportToMarkdown: string;
var
  SB: TStringBuilder;
  All: TEnhancedErrorContextArray;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Error Report');
    SB.AppendFormat('Generated: %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]).AppendLine;
    SB.AppendFormat('Total Errors: %d', [ErrorCount]).AppendLine;
    SB.AppendLine;
    
    All := GetErrors;
    for I := High(All) downto 0 do // 最新的在前
      SB.Append(All[I].ToMarkdown);
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TErrorCollector.ExportToCSV: string;
var
  SB: TStringBuilder;
  All: TEnhancedErrorContextArray;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    // Header
    SB.AppendLine('ID,Timestamp,Severity,Category,CorrelationId,WorkflowId,StepId,ErrorClass,ErrorMessage');
    
    All := GetErrors;
    for I := 0 to High(All) do
    begin
      SB.AppendFormat('"%s","%s","%s","%s","%s","%s","%s","%s","%s"',
        [All[I].Id,
         FormatDateTime('yyyy-mm-dd hh:nn:ss', All[I].Timestamp),
         ErrorSeverityToString(All[I].Severity),
         ErrorCategoryToString(All[I].Category),
         All[I].CorrelationId,
         All[I].WorkflowId,
         All[I].StepId,
         All[I].ErrorClass,
         StringReplace(All[I].ErrorMessage, '"', '""', [rfReplaceAll])
        ]).AppendLine;
    end;
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TErrorCollector.Clear;
begin
  FLock.Enter;
  try
    FErrorIndex := 0;
  finally
    FLock.Leave;
  end;
end;

procedure TErrorCollector.ClearOlderThan(Hours: Integer);
var
  Cutoff: TDateTime;
  I, NewIndex: Integer;
  NewErrors: TEnhancedErrorContextArray;
begin
  Cutoff := Now - Hours / 24;
  
  FLock.Enter;
  try
    SetLength(NewErrors, FConfig.MaxErrors);
    NewIndex := 0;
    
    for I := 0 to GetErrorCount - 1 do
    begin
      if FErrors[I].Timestamp >= Cutoff then
      begin
        NewErrors[NewIndex] := FErrors[I];
        Inc(NewIndex);
      end;
    end;
    
    FErrors := NewErrors;
    FErrorIndex := NewIndex;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// 全局实例
// ============================================================================

function ErrorCollector: TErrorCollector;
begin
  if GErrorCollector = nil then
  begin
    GErrorCollectorLock.Enter;
    try
      if GErrorCollector = nil then
        GErrorCollector := TErrorCollector.Create(TErrorCollectorConfig.Default);
    finally
      GErrorCollectorLock.Leave;
    end;
  end;
  Result := GErrorCollector;
end;

procedure InitializeErrorCollector(const AConfig: TErrorCollectorConfig);
begin
  GErrorCollectorLock.Enter;
  try
    if GErrorCollector <> nil then
      FreeAndNil(GErrorCollector);
    GErrorCollector := TErrorCollector.Create(AConfig);
  finally
    GErrorCollectorLock.Leave;
  end;
end;

initialization
  GErrorCollectorLock := TCriticalSection.Create;

finalization
  FreeAndNil(GErrorCollector);
  FreeAndNil(GErrorCollectorLock);

end.
